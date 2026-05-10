/**
 * PredictiveFailureForecaster — Mock-AI property pest-pressure forecaster.
 *
 * Pest-equivalent of a "failure forecast": predicts which properties are
 * most likely to escalate into an active infestation event in the next
 * 30 days. Reads property signals (bait station hit trend, soil temp,
 * conducive conditions, sensor staleness) and ranks properties by risk.
 *
 * Each FailureForecast is AI-shaped (riskScore, confidence,
 * predictedFailureWindow, recommendedAction, summary, source, generatedAt)
 * but the math is purely deterministic: count the number of bad signals
 * fired, weight them, and bucket the result.
 *
 * PRODUCTION REPLACEMENT: feed property signals to a real ML model
 * (Einstein Discovery, an external service, or Data Cloud-driven CDP
 * propensity scores) and consume the score back here.
 *
 * Used by:
 *   - dispatch_TopOfQueueSummary  (top-N predicted escalations for the day)
 *   - demoMagicCustomer360        (single-property forecast on the customer page)
 */
public with sharing class PredictiveFailureForecaster {

    // Pest-pressure score thresholds — bait station hits, soil temp, etc.
    private static final Decimal PRESSURE_SCORE_LIMIT     = 50;
    private static final Decimal STATION_HITS_THRESHOLD   = 5;     // hits per 30 days
    private static final Integer SENSOR_STALE_DAYS        = 7;

    public class FailureForecast {
        @AuraEnabled public Id assetId;
        @AuraEnabled public String assetName;
        @AuraEnabled public String accountName;
        @AuraEnabled public String equipmentType;     // for compat — reused as Service_Line__c value
        @AuraEnabled public String networkDomain;     // for compat — pest "Domain" = Termite/Pest/Mosquito/Lawn
        @AuraEnabled public Decimal riskScore;
        @AuraEnabled public String predictedFailureWindow;
        @AuraEnabled public String recommendedAction;
        @AuraEnabled public List<String> contributingSignals;
        @AuraEnabled public String summary;
        @AuraEnabled public Decimal confidence;
        @AuraEnabled public String source;
        @AuraEnabled public DateTime generatedAt;

        public FailureForecast() {
            this.contributingSignals = new List<String>();
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<FailureForecast> forecastNext30Days(Integer topN) {
        Integer effectiveLimit = (topN == null || topN <= 0) ? 10 : Math.min(topN, 100);

        DateTime staleCutoff = DateTime.now().addDays(-SENSOR_STALE_DAYS);

        List<Asset> candidates;
        try {
            candidates = [
                SELECT Id, Name, AccountId, Account.Name,
                       Service_Line__c,
                       Pest_Pressure_Score__c, Bait_Station_Hits_30d__c,
                       Is_Pest_Pressure_Candidate__c, Last_Treatment_DateTime__c,
                       Soil_Temp_F__c, Conducive_Conditions__c
                FROM Asset
                WHERE Is_Pest_Pressure_Candidate__c = true
                   OR Pest_Pressure_Score__c > :PRESSURE_SCORE_LIMIT
                   OR Bait_Station_Hits_30d__c > :STATION_HITS_THRESHOLD
                   OR Last_Treatment_DateTime__c < :staleCutoff
                WITH SECURITY_ENFORCED
                ORDER BY Is_Pest_Pressure_Candidate__c DESC NULLS LAST,
                         Pest_Pressure_Score__c DESC NULLS LAST
                LIMIT 200
            ];
        } catch (Exception e) {
            // Some pest fields may not be deployed in early phases — return empty
            return new List<FailureForecast>();
        }

        List<FailureForecast> forecasts = new List<FailureForecast>();
        for (Asset a : candidates) {
            forecasts.add(buildForecast(a));
        }

        for (Integer i = 1; i < forecasts.size(); i++) {
            FailureForecast key = forecasts[i];
            Integer j = i - 1;
            while (j >= 0 && forecasts[j].riskScore < key.riskScore) {
                forecasts[j + 1] = forecasts[j];
                j--;
            }
            forecasts[j + 1] = key;
        }

        if (forecasts.size() > effectiveLimit) {
            List<FailureForecast> trimmed = new List<FailureForecast>();
            for (Integer i = 0; i < effectiveLimit; i++) trimmed.add(forecasts[i]);
            return trimmed;
        }
        return forecasts;
    }

    @AuraEnabled(cacheable=true)
    public static FailureForecast forecastForAsset(Id assetId) {
        if (assetId == null) {
            throw new AuraHandledException('assetId is required.');
        }

        List<Asset> hits;
        try {
            hits = [
                SELECT Id, Name, AccountId, Account.Name,
                       Service_Line__c,
                       Pest_Pressure_Score__c, Bait_Station_Hits_30d__c,
                       Is_Pest_Pressure_Candidate__c, Last_Treatment_DateTime__c,
                       Soil_Temp_F__c, Conducive_Conditions__c
                FROM Asset
                WHERE Id = :assetId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
        } catch (Exception e) {
            throw new AuraHandledException('Asset lookup failed (fields may not be deployed): ' + e.getMessage());
        }
        if (hits.isEmpty()) {
            throw new AuraHandledException('Asset not found: ' + assetId);
        }
        return buildForecast(hits[0]);
    }

    private static FailureForecast buildForecast(Asset a) {
        FailureForecast f = new FailureForecast();
        f.assetId = a.Id;
        f.assetName = a.Name;
        f.accountName = a.Account != null ? a.Account.Name : null;
        f.equipmentType = (String) safeGet(a, 'Service_Line__c');
        f.networkDomain = (String) safeGet(a, 'Service_Line__c');
        f.source = 'PredictiveFailureForecaster + property pest signals';
        f.generatedAt = DateTime.now();

        Decimal score = 0;

        Boolean isCandidate = (Boolean) safeGet(a, 'Is_Pest_Pressure_Candidate__c');
        if (isCandidate == true) {
            score += 35;
            f.contributingSignals.add('Property is flagged as a pest-pressure candidate.');
        }
        Decimal pressureScore = (Decimal) safeGet(a, 'Pest_Pressure_Score__c');
        if (pressureScore != null && pressureScore > PRESSURE_SCORE_LIMIT) {
            score += 25;
            f.contributingSignals.add('Pest pressure score '
                + pressureScore.setScale(0) + ' exceeds the ' + PRESSURE_SCORE_LIMIT + ' threshold.');
        }
        Decimal hits = (Decimal) safeGet(a, 'Bait_Station_Hits_30d__c');
        if (hits != null && hits > STATION_HITS_THRESHOLD) {
            score += 25;
            f.contributingSignals.add('Bait station hits at '
                + hits.setScale(0) + ' over 30 days (threshold ' + STATION_HITS_THRESHOLD + ').');
        }
        DateTime lastSensor = (DateTime) safeGet(a, 'Last_Treatment_DateTime__c');
        Integer daysSince = daysSinceReading(lastSensor);
        if (daysSince > SENSOR_STALE_DAYS) {
            score += 15;
            f.contributingSignals.add('No sensor reading in '
                + daysSince + ' days (stale signal — possible offline station).');
        }
        Boolean conducive = (Boolean) safeGet(a, 'Conducive_Conditions__c');
        if (conducive == true) {
            score += 10;
            f.contributingSignals.add('Conducive conditions flagged on last inspection.');
        }
        Decimal soilTemp = (Decimal) safeGet(a, 'Soil_Temp_F__c');
        if (soilTemp != null && soilTemp > 70) {
            score += 8;
            f.contributingSignals.add('Soil temperature ' + soilTemp.setScale(0) + 'F is in the termite-active range.');
        }

        if (score > 100) score = 100;
        f.riskScore = score.setScale(0);

        if (score >= 70) {
            f.predictedFailureWindow = '7 days';
            f.recommendedAction = 'Schedule a Booster Termite Inspection within the week. Notify customer via SMS.';
        } else if (score >= 40) {
            f.predictedFailureWindow = '14 days';
            f.recommendedAction = 'Add to watch list, attempt customer outreach for booster visit if signals worsen.';
        } else if (score > 0) {
            f.predictedFailureWindow = '30 days';
            f.recommendedAction = 'Monitor — re-run forecast weekly. No immediate dispatch warranted.';
        } else {
            f.predictedFailureWindow = '30 days';
            f.recommendedAction = 'No action required. Property is within healthy operating envelope.';
        }

        Integer signalCount = f.contributingSignals.size();
        f.confidence = Math.min(95, 55 + signalCount * 10);

        String svcLabel = String.isNotBlank(f.equipmentType) ? f.equipmentType : 'Property';
        if (signalCount == 0) {
            f.summary = svcLabel + ' is healthy — no pest-pressure signals fired in the current window. '
                + 'Forecast confidence ' + f.confidence + '%.';
        } else {
            String windowText = (score >= 70) ? 'within 7 days'
                              : (score >= 40) ? 'in the next 2 weeks'
                                              : 'in the next 30 days';
            f.summary = svcLabel + ' shows ' + signalCount + ' pest-pressure signal'
                + (signalCount == 1 ? '' : 's')
                + '. Predicted escalation window: ' + windowText
                + '. Recommended action: ' + f.recommendedAction;
        }
        return f;
    }

    private static Object safeGet(SObject rec, String fieldName) {
        try { return rec.get(fieldName); } catch (Exception e) { return null; }
    }

    private static Integer daysSinceReading(DateTime last) {
        if (last == null) return 999;
        Long diffMs = DateTime.now().getTime() - last.getTime();
        return (Integer) (diffMs / (1000L * 60L * 60L * 24L));
    }
}
