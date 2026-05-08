/**
 * BaitStationReadingService — Backs the inline pest-pressure sparkline
 * shown to the field tech during Site Assessment and post-treatment
 * verification.
 *
 * Public method signatures preserved from the inherited reading service
 * so existing LWC bindings continue to resolve.
 *
 * DEMO ONLY: there is no real bait-station IoT integration. Readings are
 * SYNTHESIZED deterministically from Asset metadata
 * (Bait_Station_Hits_30d__c, Last_Bait_Station_Hit_Date__c,
 * Is_Pest_Pressure_Candidate__c, Last_Treatment_DateTime__c) and the
 * WorkType context so the sparkline tells a believable story (e.g.
 * pest pressure drops post-treatment on a Termidor liquid treatment job).
 *
 * PRODUCTION REPLACEMENT: replace synthesizeReadings() with a call to a
 * treatment-history time-series store (Data Cloud Stream, route IoT
 * feed, or Treatment_Reading__c custom object) bucketed at daily
 * intervals.
 */
public with sharing class BaitStationReadingService {

    // ---- Tunables (Pest Pressure Score, 0-100) ---------------------------
    // 0-34   = nominal post-treatment / quarterly-clean
    // 35-49  = elevated, watch on next route stop
    // 50-100 = heavy, treatment indicated
    private static final Decimal PRESSURE_NOMINAL_LOW   = 0;
    private static final Decimal PRESSURE_NOMINAL_HIGH  = 34;
    private static final Decimal PRESSURE_NOMINAL_MID   = 18;
    private static final Decimal PRESSURE_HEAVY_FLOOR   = 50;

    // Daily sample interval for the pest-pressure trend
    private static final Integer INTERVAL_MINUTES = 24 * 60;

    // ---- DTOs -------------------------------------------------------------

    public class Reading {
        @AuraEnabled public DateTime timestamp;
        @AuraEnabled public Decimal value;
        @AuraEnabled public String unit;
        @AuraEnabled public Boolean isAnomaly;

        public Reading() {}
        public Reading(DateTime ts, Decimal v, String u, Boolean anomaly) {
            this.timestamp = ts;
            this.value = v;
            this.unit = u;
            this.isAnomaly = anomaly;
        }
    }

    public class ReadingSeries {
        @AuraEnabled public Id assetId;
        @AuraEnabled public String assetName;
        @AuraEnabled public String unit;
        @AuraEnabled public List<Reading> readings;
        @AuraEnabled public Decimal normalRangeLow;
        @AuraEnabled public Decimal normalRangeHigh;
        @AuraEnabled public Decimal currentValue;
        @AuraEnabled public String trendDirection; // rising | stable | falling | restored
        @AuraEnabled public String summary;

        public ReadingSeries() {
            this.readings = new List<Reading>();
        }
    }

    // ---- Public API -------------------------------------------------------

    /**
     * Fetch a synthesized pest-pressure sparkline series for one Asset.
     * Method name preserved from the inherited service so existing LWC
     * bindings continue to resolve.
     *
     * @param assetId   the Asset to read for
     * @param hoursBack how many hours of history to surface — interpreted
     *                  as days for pest-pressure (one sample per day) so
     *                  the sparkline maps to a quarterly service trend.
     */
    @AuraEnabled(cacheable=true)
    public static ReadingSeries getReadings(Id assetId, Integer hoursBack) {
        if (assetId == null) {
            throw new AuraHandledException('assetId is required.');
        }
        Integer hrs = (hoursBack != null && hoursBack > 0) ? hoursBack : 12;

        List<Asset> assets = [
            SELECT Id, Name, SerialNumber, Service_Line__c, Equipment_Type__c,
                   Last_Treatment_DateTime__c, Is_Pest_Pressure_Candidate__c,
                   Pest_Pressure_Score__c, Bait_Station_Hits_30d__c,
                   Last_Bait_Station_Hit_Date__c, Bait_Station_State__c,
                   Trap_Catch_Count_24h__c
            FROM Asset
            WHERE Id = :assetId
            LIMIT 1
        ];
        if (assets.isEmpty()) {
            throw new AuraHandledException('Asset not found: ' + assetId);
        }
        // No WorkType context here — render baseline behavior (stable / current state).
        return synthesizeSeries(assets[0], hrs, null);
    }

    /**
     * Convenience: for post-treatment verification on a WorkOrder, return
     * a ReadingSeries per affected Asset showing the post-treatment
     * picture. Method name preserved from the inherited service.
     *
     * Affected Assets are gathered from:
     *   1. WorkOrder.AssetId
     *   2. Cases linked via Linked_Incident__c (if WO.Linked_Incident__c is set)
     *      where Case.AssetId is populated — i.e. all properties on a
     *      cluster-response area-treatment WO.
     */
    @AuraEnabled(cacheable=false)
    public static List<ReadingSeries> getReadingsForRestoration(Id workOrderId) {
        if (workOrderId == null) {
            throw new AuraHandledException('workOrderId is required.');
        }

        List<WorkOrder> wos = [
            SELECT Id, AssetId, WorkTypeId, WorkType.Name, Linked_Incident__c
            FROM WorkOrder
            WHERE Id = :workOrderId
            LIMIT 1
        ];
        if (wos.isEmpty()) {
            throw new AuraHandledException('WorkOrder not found: ' + workOrderId);
        }
        WorkOrder wo = wos[0];
        String workTypeName = (wo.WorkType != null) ? wo.WorkType.Name : null;

        Set<Id> assetIds = new Set<Id>();
        if (wo.AssetId != null) assetIds.add(wo.AssetId);

        if (wo.Linked_Incident__c != null) {
            for (Case c : [
                SELECT AssetId
                FROM Case
                WHERE Linked_Incident__c = :wo.Linked_Incident__c
                  AND AssetId != null
            ]) {
                assetIds.add(c.AssetId);
            }
        }

        List<ReadingSeries> out = new List<ReadingSeries>();
        if (assetIds.isEmpty()) return out;

        List<Asset> assets = [
            SELECT Id, Name, SerialNumber, Service_Line__c, Equipment_Type__c,
                   Last_Treatment_DateTime__c, Is_Pest_Pressure_Candidate__c,
                   Pest_Pressure_Score__c, Bait_Station_Hits_30d__c,
                   Last_Bait_Station_Hit_Date__c, Bait_Station_State__c,
                   Trap_Catch_Count_24h__c
            FROM Asset
            WHERE Id IN :assetIds
        ];

        // Post-treatment verification view: 12 days back, with WorkType
        // context driving the pre-treatment / post-treatment narrative.
        for (Asset a : assets) {
            out.add(synthesizeSeries(a, 12, workTypeName));
        }
        return out;
    }

    // ---- Synthesis --------------------------------------------------------

    private static ReadingSeries synthesizeSeries(Asset a, Integer hoursBack, String workTypeName) {
        String unit = 'score';

        ReadingSeries s = new ReadingSeries();
        s.assetId = a.Id;
        s.assetName = a.Name;
        s.unit = unit;
        s.normalRangeLow  = PRESSURE_NOMINAL_LOW;
        s.normalRangeHigh = PRESSURE_NOMINAL_HIGH;

        // Anchor the series end at Last_Treatment_DateTime__c if present, else now.
        DateTime endTs = (a.Last_Treatment_DateTime__c != null)
            ? a.Last_Treatment_DateTime__c
            : DateTime.now();

        // hoursBack is interpreted as the number of daily samples for the
        // pest-pressure trend. Default 12 days = quarterly service window
        // approximation.
        Integer points = hoursBack;
        if (points <= 0) points = 12;

        // Deterministic seed per Asset so the sparkline doesn't jitter across calls.
        Integer seed = Math.abs((a.Id + '').hashCode());

        // Treatment-job narrative: pressure climbs pre-treatment and drops
        // post-treatment. Driven by WorkType keywords AND the deterministic
        // Is_Pest_Pressure_Candidate__c flag carried by the demo data.
        Boolean isTreatmentJob = workTypeName != null
            && (workTypeName.containsIgnoreCase('Termite Liquid Treatment')
                || workTypeName.containsIgnoreCase('Sentricon Service')
                || workTypeName.containsIgnoreCase('Mosquito Surge Area Treatment')
                || workTypeName.containsIgnoreCase('Mosquito System Service')
                || workTypeName.containsIgnoreCase('Quarterly Pest Service')
                || workTypeName.containsIgnoreCase('Wasp')
                || workTypeName.containsIgnoreCase('Stinging Insect'));
        Boolean isInspection = workTypeName != null
            && (workTypeName.containsIgnoreCase('Pest Inspection')
                || workTypeName.containsIgnoreCase('Termite Inspection')
                || workTypeName.containsIgnoreCase('Sentricon Install')
                || workTypeName.containsIgnoreCase('Mosquito System Install'));

        synthesizePestPressure(s, endTs, points, seed, isTreatmentJob, isInspection);

        // currentValue = the most recent reading
        if (!s.readings.isEmpty()) {
            s.currentValue = s.readings[s.readings.size() - 1].value;
        }
        return s;
    }

    /**
     * Pest-pressure score (0-100) is a POSITIVE number — higher = worse.
     * On a treatment job the score climbs from a healthy ~18 up to ~70
     * pre-treatment, then drops back to ~18 post-treatment.
     */
    private static void synthesizePestPressure(
        ReadingSeries s, DateTime endTs, Integer points, Integer seed,
        Boolean isTreatmentJob, Boolean isInspection
    ) {
        // 6 days of climb before the end, 1 day of drop right at the end
        Integer climbStartIdx = points - 6;
        if (climbStartIdx < 0) climbStartIdx = 0;
        Integer recoveryIdx  = points - 1;
        if (recoveryIdx < climbStartIdx) recoveryIdx = climbStartIdx;

        for (Integer i = 0; i < points; i++) {
            DateTime ts = endTs.addMinutes(-INTERVAL_MINUTES * (points - 1 - i));
            // ~+/- 2 score wobble (realistic seasonal jitter)
            Decimal jitter = pseudoNoise(seed, i, 4);
            Decimal value;
            Boolean anomaly = false;

            if (isTreatmentJob && i >= climbStartIdx && i < recoveryIdx) {
                // Pre-treatment climb: from ~18 up to ~70
                Decimal progress = (Decimal)(i - climbStartIdx) / Math.max(1, (recoveryIdx - climbStartIdx));
                value = (18 + (52 * progress)) + jitter;
                anomaly = (value >= PRESSURE_HEAVY_FLOOR);
            } else if (isTreatmentJob && i >= recoveryIdx) {
                // Post-treatment drop: from ~70 back down to ~18
                Decimal progress = (Decimal)(i - recoveryIdx) / Math.max(1, (points - 1 - recoveryIdx));
                value = (70 - (52 * progress)) + jitter;
                if (value < 0) value = 0;
                anomaly = (value >= PRESSURE_HEAVY_FLOOR);
            } else {
                // Stable around the healthy mid (18) with small wobble
                value = PRESSURE_NOMINAL_MID + jitter;
                if (value < 0) value = 0;
                anomaly = (value > PRESSURE_NOMINAL_HIGH);
            }
            value = value.setScale(0);
            s.readings.add(new Reading(ts, value, 'score', anomaly));
        }

        // Trend + summary
        if (isTreatmentJob) {
            s.trendDirection = 'restored';
            Long minutesAgo = (DateTime.now().getTime() - endTs.getTime()) / (1000L * 60L);
            if (minutesAgo < 0) minutesAgo = 0;
            // If anchored "now-ish", say 2 minutes for narrative punch
            Long minutesNarrative = (minutesAgo < 5) ? 2 : minutesAgo;
            s.summary = 'Pest pressure dropped back into the nominal band post-treatment as of '
                + minutesNarrative + ' minute' + (minutesNarrative == 1 ? '' : 's') + ' ago.';
        } else if (isInspection) {
            s.trendDirection = 'stable';
            s.summary = 'Pest pressure stable in nominal range ('
                + PRESSURE_NOMINAL_LOW + ' to ' + PRESSURE_NOMINAL_HIGH + ').';
        } else {
            s.trendDirection = computeTrend(s.readings);
            s.summary = 'Pest pressure ' + s.trendDirection + ' — current '
                + (s.readings.isEmpty() ? '?' : String.valueOf(s.readings[s.readings.size()-1].value)) + '.';
        }
    }

    /**
     * Domain-specific helper: quick fetch of bait-station + trap-count
     * state for an Asset. Called by Site step LWCs that want the headline
     * numbers without the full sparkline.
     */
    @AuraEnabled(cacheable=true)
    public static List<Asset> getBaitStationState(Id accountId) {
        if (accountId == null) {
            throw new AuraHandledException('accountId is required.');
        }
        return [
            SELECT Id, Name, Service_Line__c, Equipment_Type__c,
                   Bait_Station_State__c, Bait_Station_Hits_30d__c,
                   Last_Bait_Station_Hit_Date__c, Trap_Catch_Count_24h__c,
                   Pest_Pressure_Score__c, Conducive_Conditions__c,
                   Last_Treatment_DateTime__c, EPA_Reg_Number_Last_Used__c
            FROM Asset
            WHERE AccountId = :accountId
              AND Equipment_Type__c IN ('Sentricon_Station','Mosquito_System','Property','Trap','Treatment_Perimeter')
            ORDER BY Last_Bait_Station_Hit_Date__c DESC NULLS LAST
        ];
    }

    // ---- Helpers ----------------------------------------------------------

    /**
     * Deterministic pseudo-noise in roughly [-amplitude/2, +amplitude/2].
     * Not cryptographic — just enough variability to make the sparkline
     * look like real telemetry without using Math.random() (which would
     * change across cacheable wire calls).
     */
    private static Decimal pseudoNoise(Integer seed, Integer idx, Integer amplitude) {
        // Simple LCG-ish hash; mod gives a 0..(amp*10-1) integer, then center.
        Integer h = Math.abs((seed * 31 + idx * 1103515245 + 12345));
        Integer band = amplitude * 10; // tenths of a unit
        Integer raw = Math.mod(h, band);
        Decimal centered = (Decimal)(raw - (band / 2)) / 10.0;
        return centered;
    }

    private static String computeTrend(List<Reading> readings) {
        if (readings == null || readings.size() < 4) return 'stable';
        Integer n = readings.size();
        Decimal head = average(readings, 0, Math.min(4, n));
        Decimal tail = average(readings, n - Math.min(4, n), n);
        Decimal delta = tail - head;
        // For pest-pressure score, "rising" = worse pressure
        if (delta > 4) return 'rising';
        if (delta < -4) return 'falling';
        return 'stable';
    }

    private static Decimal average(List<Reading> readings, Integer fromIdx, Integer toExclusive) {
        if (toExclusive <= fromIdx) return 0;
        Decimal sum = 0;
        for (Integer i = fromIdx; i < toExclusive; i++) sum += readings[i].value;
        return sum / (toExclusive - fromIdx);
    }
}
