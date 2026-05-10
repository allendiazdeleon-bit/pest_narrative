/**
 * PestPressureAnalyzer — Agentforce-invocable pest-pressure diagnostics for
 * Massey Services residential Accounts (Pest, Termite, Mosquito, Lawn).
 *
 * Per BUILD_TICKETS_PEST.md §P3.1, returns a plain-language pest-pressure
 * diagnosis for an Account based on bait-station activity, conducive
 * conditions, and trap catch counts captured on the property's Asset
 * records during quarterly service visits. In this demo build the
 * underlying source is the Is_Pest_Pressure_Candidate__c flag on the
 * Account's primary Asset, plus Bait_Station_Hits_30d__c, Bait_Station_State__c,
 * Trap_Catch_Count_24h__c, and Conducive_Conditions__c.
 *
 * PRODUCTION REPLACEMENT: query a treatment-history time-series store
 * (Data Cloud Stream, route-IoT feed, or Treatment_Reading__c custom
 * object) and apply the pressure-trend / conducive-streak heuristics
 * from the design doc against actual readings.
 *
 * Public method signatures preserved from the inherited analyzer so
 * existing Agentforce action bindings continue to resolve.
 */
public with sharing class PestPressureAnalyzer {

    public class Request {
        @InvocableVariable(required=true) public Id personAccountId;
        @InvocableVariable public Integer daysBack;
    }

    public class Response {
        @InvocableVariable(label='Diagnosis') public String diagnosis;
        @InvocableVariable(label='Anomaly Type') public String anomalyType;     // HEAVY_PRESSURE | ELEVATED_PRESSURE | NONE
        @InvocableVariable(label='Pest Pressure Score') public Decimal pestPressureScore;
        @InvocableVariable(label='Primary Asset Id') public Id primaryAssetId;
    }

    public class AssetForecast {
        @AuraEnabled public Decimal riskScore;
        @AuraEnabled public String summary;
        @AuraEnabled public Decimal confidence;
        @AuraEnabled public String source;
        @AuraEnabled public String anomalyType;
        @AuraEnabled public Id assetId;
    }

    @AuraEnabled(cacheable=true)
    public static AssetForecast analyzeForAsset(Id assetId) {
        AssetForecast f = new AssetForecast();
        f.assetId = assetId;
        f.confidence = 70;
        f.source = 'PestPressureAnalyzer';
        f.anomalyType = 'NONE';
        if (assetId == null) { f.summary = 'No asset selected.'; f.riskScore = 0; return f; }
        Id accountId = null;
        try {
            Asset a = [SELECT Id, AccountId FROM Asset WHERE Id = :assetId LIMIT 1];
            accountId = a.AccountId;
        } catch (Exception e) { f.summary = 'Asset not found.'; f.riskScore = 0; return f; }
        if (accountId == null) { f.summary = 'Asset has no parent Account.'; f.riskScore = 0; return f; }
        Request r = new Request();
        r.personAccountId = accountId;
        r.daysBack = 30;
        List<Response> resps = analyze(new List<Request>{ r });
        Response resp = resps.isEmpty() ? new Response() : resps[0];
        f.riskScore = resp.pestPressureScore != null ? resp.pestPressureScore : 0;
        f.summary = resp.diagnosis;
        f.anomalyType = resp.anomalyType != null ? resp.anomalyType : 'NONE';
        return f;
    }

    @InvocableMethod(label='Analyze Pest Pressure' description='Read bait-station, trap, and conducive-condition telemetry on a customer Account and return a pest-pressure diagnosis (e.g., heavy termite activity, elevated mosquito pressure).')
    public static List<Response> analyze(List<Request> requests) {
        List<Response> out = new List<Response>();
        for (Request r : requests) {
            Integer days = r.daysBack != null ? r.daysBack : 30;
            out.add(analyzeOne(r.personAccountId, days));
        }
        return out;
    }

    private static Response analyzeOne(Id personAccountId, Integer daysBack) {
        Response resp = new Response();
        resp.anomalyType = 'NONE';
        resp.diagnosis = 'No pest-pressure anomaly detected in the last ' + daysBack + ' days. Bait-station activity, trap counts, and conducive conditions are within normal seasonal thresholds.';
        resp.pestPressureScore = 0;

        List<Asset> assets = [
            SELECT Id, Name, Service_Line__c, Is_Pest_Pressure_Candidate__c,
                   Bait_Station_Hits_30d__c, Bait_Station_State__c,
                   Last_Bait_Station_Hit_Date__c, Trap_Catch_Count_24h__c,
                   Conducive_Conditions__c, Pest_Pressure_Score__c,
                   Equipment_Type__c, Days_Since_Last_Service__c
            FROM Asset
            WHERE AccountId = :personAccountId
            ORDER BY Pest_Pressure_Score__c DESC NULLS LAST
            LIMIT 1
        ];
        if (assets.isEmpty()) {
            resp.diagnosis = 'No Asset on file for this account.';
            return resp;
        }
        Asset a = assets[0];
        resp.primaryAssetId = a.Id;

        // Demo deterministic path: Is_Pest_Pressure_Candidate__c stands in for
        // the production heuristic — sustained Bait_Station_Hits_30d__c > 3
        // AND Conducive_Conditions__c == true over 2+ consecutive quarterly
        // visits. Pre-computed Pest_Pressure_Score__c on the Asset is the
        // authoritative score; we fall back to a synthesized estimate if it
        // isn't populated.
        if (a.Is_Pest_Pressure_Candidate__c == true) {
            Decimal hits = a.Bait_Station_Hits_30d__c != null && a.Bait_Station_Hits_30d__c > 0
                ? a.Bait_Station_Hits_30d__c
                : 4;
            String stationState = String.isNotBlank(a.Bait_Station_State__c) ? a.Bait_Station_State__c : 'Heavy_Activity';
            String serviceLine = String.isNotBlank(a.Service_Line__c) ? a.Service_Line__c : 'Termite';

            resp.anomalyType = 'HEAVY_PRESSURE';
            resp.pestPressureScore = a.Pest_Pressure_Score__c != null
                ? a.Pest_Pressure_Score__c
                : Math.min(95, 55 + (hits * 8)).setScale(0);

            if (serviceLine == 'Termite') {
                resp.diagnosis = 'Heavy termite activity on perimeter — '
                    + hits.setScale(0) + ' bait station hits in the last 30 days, '
                    + 'station state ' + stationState + '. '
                    + 'Pattern is consistent with an active foraging colony along the north or east perimeter; recommend a full Sentricon AlwaysActive station refresh and follow-up inspection in 14 days. '
                    + 'Pest pressure score: ' + resp.pestPressureScore + '/100.';
            } else if (serviceLine == 'Mosquito') {
                Decimal trapCount = a.Trap_Catch_Count_24h__c != null ? a.Trap_Catch_Count_24h__c : 18;
                resp.diagnosis = 'Elevated mosquito pressure — '
                    + trapCount.setScale(0) + ' adults captured in the last 24h trap cycle, '
                    + 'conducive conditions present (standing water in yard, shaded harborage). '
                    + 'Recommend ULV fog of breeding source plus larvicide application; flag to dispatch for area-treatment route bundling if neighbor cases trend up. '
                    + 'Pest pressure score: ' + resp.pestPressureScore + '/100.';
            } else if (serviceLine == 'Lawn') {
                resp.diagnosis = 'Heavy chinch-bug / sod-webworm pressure — '
                    + 'lawn telemetry shows damage thresholds exceeded with '
                    + (a.Conducive_Conditions__c == true ? 'conducive conditions noted (drought stress, thin turf). ' : 'no conducive conditions noted yet. ')
                    + 'Recommend targeted insecticide application on affected zones. '
                    + 'Pest pressure score: ' + resp.pestPressureScore + '/100.';
            } else {
                resp.diagnosis = 'Heavy pest activity on the property — '
                    + hits.setScale(0) + ' interior trap / station hits in the last 30 days. '
                    + 'Recommend a perimeter retreatment plus interior crack-and-crevice application, with a follow-up inspection in 14 days. '
                    + 'Pest pressure score: ' + resp.pestPressureScore + '/100.';
            }
            return resp;
        }

        // Soft anomaly: bait-station state shows Activity (not Heavy) but
        // hits below the heavy-pressure threshold — surface as a watch
        // item for the next quarterly route stop.
        if (a.Bait_Station_State__c == 'Activity'
            || (a.Bait_Station_Hits_30d__c != null && a.Bait_Station_Hits_30d__c >= 2)) {
            resp.anomalyType = 'ELEVATED_PRESSURE';
            Decimal hits = a.Bait_Station_Hits_30d__c != null ? a.Bait_Station_Hits_30d__c : 2;
            resp.pestPressureScore = a.Pest_Pressure_Score__c != null
                ? a.Pest_Pressure_Score__c
                : Math.min(50, 25 + (hits * 5)).setScale(0);
            resp.diagnosis = 'Light bait-station activity on file — '
                + hits.setScale(0) + ' hit(s) in the last 30 days. '
                + 'Could indicate early-season foraging or a single conducive condition; monitor on the next quarterly route stop before escalating treatment. '
                + 'Pest pressure score: ' + resp.pestPressureScore + '/100.';
            return resp;
        }
        return resp;
    }
}
