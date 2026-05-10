/**
 * RestorationVerifier — "Treatment Verification" gate for the Summary &
 * Close step of the masseyFlow orchestrator. (Custom Label
 * MasseyFlow_Verify_Phase_Title resolves to "Verify & Close Service Visit"
 * — keep the class name as RestorationVerifier per BUILD_TICKETS.)
 *
 * Before a field tech can mark a Work Order Complete, this class confirms
 * via downstream signals that pest pressure has actually receded at every
 * property the WO touches. The result is a structured pass/fail-per-property
 * and an overall gateRecommendation that the LWC uses to either allow,
 * defer, or block the close action.
 *
 * Affected Properties are gathered from:
 *   1. The WorkOrder's own AssetId (single-customer WO case), AND
 *   2. Cases linked to the WO's Linked_Incident__c (multi-customer cluster)
 *      → Case.AccountId → Property Assets on those Accounts.
 *
 * DEMO ONLY: there is no real bait-station / sensor integration. Status,
 * currentValue, and lastReadingAt are SYNTHESIZED deterministically from
 * Asset metadata (Id hash, Last_Treatment_DateTime__c, Is_Pest_Pressure_Candidate__c)
 * and the WorkType narrative. Real org Assets are queried — only the
 * readings are faked.
 *
 * PRODUCTION REPLACEMENT: replace synthesizeCheck() with a call to the
 * bait-station / soil-temp time-series store and apply the same range
 * thresholds against the most recent real reading.
 *
 * Mirrors the synthesis pattern in BaitStationReadingService for narrative
 * coherence (the sparkline tells the same story as the verifier verdict).
 */
public with sharing class RestorationVerifier {

    // ---- Tunables: pest-pressure score thresholds ------------------------
    // Higher pressure score = worse. "Recovering" sits between active
    // infestation and the cleared band; "StillInterrupted" is above the
    // hard active-infestation threshold.
    private static final Decimal PRESSURE_NORMAL_LOW       = 0;    // healthy band: 0..25
    private static final Decimal PRESSURE_NORMAL_HIGH      = 25;
    private static final Decimal PRESSURE_RECOVERING_HIGH  = 50;   // 25..50 = Recovering
    // Above PRESSURE_RECOVERING_HIGH = StillInterrupted

    // ---- DTOs -------------------------------------------------------------

    public class MeterCheck {
        @AuraEnabled public Id assetId;
        @AuraEnabled public String assetName;
        @AuraEnabled public String accountName;
        @AuraEnabled public String address;
        @AuraEnabled public String expectedMetric;   // e.g. 'Pest Pressure 0-25'
        @AuraEnabled public Decimal currentValue;
        @AuraEnabled public String unit;
        @AuraEnabled public DateTime lastReadingAt;
        @AuraEnabled public String status;           // Restored | Recovering | StillInterrupted | NoData
        @AuraEnabled public Decimal confidence;      // 0-1
        @AuraEnabled public String notes;

        public MeterCheck() {}
    }

    public class VerificationResult {
        @AuraEnabled public Id workOrderId;
        @AuraEnabled public DateTime runAt;
        @AuraEnabled public Integer totalMeters;     // = number of properties verified
        @AuraEnabled public Integer restoredCount;
        @AuraEnabled public Integer recoveringCount;
        @AuraEnabled public Integer interruptedCount;
        @AuraEnabled public Integer noDataCount;
        @AuraEnabled public String overallStatus;    // Verified | Partial | Failed | Pending
        @AuraEnabled public String gateRecommendation; // Allow Close | Recheck in 5 minutes | Block Close
        @AuraEnabled public String summary;
        @AuraEnabled public List<MeterCheck> checks;

        public VerificationResult() {
            this.checks = new List<MeterCheck>();
            this.totalMeters = 0;
            this.restoredCount = 0;
            this.recoveringCount = 0;
            this.interruptedCount = 0;
            this.noDataCount = 0;
        }
    }

    @AuraEnabled(cacheable=false)
    public static VerificationResult verify(Id workOrderId) {
        return run(workOrderId);
    }

    @AuraEnabled(cacheable=true)
    public static VerificationResult preview(Id workOrderId) {
        return run(workOrderId);
    }

    private static VerificationResult run(Id workOrderId) {
        if (workOrderId == null) {
            throw new AuraHandledException('workOrderId is required.');
        }

        VerificationResult result = new VerificationResult();
        result.workOrderId = workOrderId;
        result.runAt = DateTime.now();

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
            Set<Id> incidentAccountIds = new Set<Id>();
            for (Case c : [
                SELECT AssetId, AccountId
                FROM Case
                WHERE Linked_Incident__c = :wo.Linked_Incident__c
            ]) {
                if (c.AssetId != null) assetIds.add(c.AssetId);
                if (c.AccountId != null) incidentAccountIds.add(c.AccountId);
            }
            if (!incidentAccountIds.isEmpty()) {
                for (Asset a : [
                    SELECT Id
                    FROM Asset
                    WHERE AccountId IN :incidentAccountIds
                ]) {
                    assetIds.add(a.Id);
                }
            }
        }

        if (assetIds.isEmpty()) {
            result.overallStatus = 'Pending';
            result.gateRecommendation = 'Block Close';
            result.summary = 'No properties could be identified for this work order. '
                + 'Verify the Work Order has an Asset or a Linked Incident before closing.';
            return result;
        }

        List<Asset> assets = [
            SELECT Id, Name, Service_Line__c,
                   Last_Treatment_DateTime__c, Is_Pest_Pressure_Candidate__c,
                   AccountId, Account.Name,
                   City, State, PostalCode, Street
            FROM Asset
            WHERE Id IN :assetIds
        ];

        for (Asset a : assets) {
            result.checks.add(synthesizeCheck(a, workTypeName));
        }

        for (MeterCheck mc : result.checks) {
            result.totalMeters++;
            if ('Restored'.equals(mc.status)) {
                result.restoredCount++;
            } else if ('Recovering'.equals(mc.status)) {
                result.recoveringCount++;
            } else if ('StillInterrupted'.equals(mc.status)) {
                result.interruptedCount++;
            } else {
                result.noDataCount++;
            }
        }

        applyOverallStatus(result);
        applyGateRecommendation(result);
        result.summary = buildSummary(result);
        return result;
    }

    private static MeterCheck synthesizeCheck(Asset a, String workTypeName) {
        MeterCheck mc = new MeterCheck();
        mc.assetId = a.Id;
        mc.assetName = a.Name;
        mc.accountName = (a.Account != null) ? a.Account.Name : null;
        mc.address = formatAddress(a);
        mc.unit = 'pressure score';
        mc.expectedMetric = 'Pest Pressure ' + PRESSURE_NORMAL_LOW + ' to ' + PRESSURE_NORMAL_HIGH;

        DateTime lastReading = null;
        try { lastReading = (DateTime) a.get('Last_Treatment_DateTime__c'); } catch (Exception e) {}
        if (lastReading != null) {
            mc.lastReadingAt = lastReading;
        } else {
            Integer minutesAgo = 1 + Math.mod(stableHash(a.Id, 7), 3);
            mc.lastReadingAt = DateTime.now().addMinutes(-minutesAgo);
        }

        Integer roll = Math.mod(stableHash(a.Id, 17), 100);
        String bucket = pickStatusBucket(workTypeName, roll);
        mc.status = bucket;

        if ('Restored'.equals(bucket)) {
            mc.currentValue = roundOne((Decimal)Math.mod(stableHash(a.Id, 23), 200) / 10);  // 0.0..19.9
            mc.confidence = 0.95;
            mc.notes = 'Pest pressure has receded into the normal range; bait stations show no fresh hits.';
        } else if ('Recovering'.equals(bucket)) {
            mc.currentValue = roundOne(25 + (Decimal)Math.mod(stableHash(a.Id, 29), 240) / 10);  // 25.0..48.9
            mc.confidence = 0.70;
            mc.notes = 'Pressure trending downward — re-entry interval likely sufficient; recheck in 24 hours.';
        } else if ('StillInterrupted'.equals(bucket)) {
            mc.currentValue = roundOne(55 + (Decimal)Math.mod(stableHash(a.Id, 31), 400) / 10);  // 55.0..94.9
            mc.confidence = 0.90;
            mc.notes = 'Pest pressure still elevated — recommend a follow-up booster treatment before closing.';
        } else {
            mc.currentValue = null;
            mc.confidence = 0.0;
            mc.notes = 'Property has not reported a fresh sensor / inspection reading since the work was performed.';
        }
        return mc;
    }

    private static String pickStatusBucket(String workTypeName, Integer roll) {
        Boolean isClusterJob = workTypeName != null && (
            workTypeName.containsIgnoreCase('Mosquito Surge') ||
            workTypeName.containsIgnoreCase('Booster Termite') ||
            workTypeName.containsIgnoreCase('Booster Pest') ||
            workTypeName.containsIgnoreCase('Whole-Home Tent') ||
            workTypeName.containsIgnoreCase('Sentricon Re-bait')
        );
        Boolean isRoutine = workTypeName != null && (
            workTypeName.containsIgnoreCase('Sentricon Install') ||
            workTypeName.containsIgnoreCase('New Service Activation') ||
            workTypeName.containsIgnoreCase('GoGreen Quarterly') ||
            workTypeName.containsIgnoreCase('Mosquito Hunter Activation') ||
            workTypeName.containsIgnoreCase('Lawn Treatment')
        );

        if (isRoutine) return 'Restored';

        if (isClusterJob) {
            if (roll < 80) return 'Restored';
            if (roll < 95) return 'Recovering';
            return 'StillInterrupted';
        }
        return 'Restored';
    }

    private static void applyOverallStatus(VerificationResult r) {
        if (r.totalMeters == 0) {
            r.overallStatus = 'Pending';
            return;
        }
        if (r.interruptedCount > 0) {
            r.overallStatus = 'Failed';
            return;
        }
        if (r.recoveringCount > 0 || r.noDataCount > 0) {
            r.overallStatus = 'Partial';
            return;
        }
        r.overallStatus = 'Verified';
    }

    private static void applyGateRecommendation(VerificationResult r) {
        if (r.totalMeters == 0) {
            r.gateRecommendation = 'Block Close';
            return;
        }
        if (r.interruptedCount > 0) {
            r.gateRecommendation = 'Block Close';
            return;
        }
        if (r.restoredCount == r.totalMeters) {
            r.gateRecommendation = 'Allow Close';
            return;
        }
        r.gateRecommendation = 'Recheck in 5 minutes';
    }

    private static String buildSummary(VerificationResult r) {
        if (r.totalMeters == 0) {
            return 'No properties in scope to verify.';
        }
        String base = r.restoredCount + ' of ' + r.totalMeters
            + ' propert' + (r.totalMeters == 1 ? 'y' : 'ies') + ' confirmed treated.';

        List<String> tail = new List<String>();
        if (r.recoveringCount > 0) {
            tail.add(r.recoveringCount + ' propert'
                + (r.recoveringCount == 1 ? 'y' : 'ies')
                + ' still showing residual pressure');
        }
        if (r.interruptedCount > 0) {
            tail.add(r.interruptedCount + ' propert'
                + (r.interruptedCount == 1 ? 'y' : 'ies')
                + ' still showing active infestation');
        }
        if (r.noDataCount > 0) {
            tail.add(r.noDataCount + ' propert'
                + (r.noDataCount == 1 ? 'y' : 'ies')
                + ' have not reported fresh readings');
        }

        if (tail.isEmpty()) {
            return base + ' All readings are within the expected range — safe to close the work order.';
        }

        String joined = String.join(tail, '; ');
        if ('Block Close'.equals(r.gateRecommendation)) {
            return base + ' ' + capitalize(joined)
                + ' — recommend a follow-up booster visit before closing the work order.';
        }
        return base + ' ' + capitalize(joined)
            + ' — recommend re-checking in about 5 minutes before closing the work order.';
    }

    private static Integer stableHash(Id assetId, Integer salt) {
        if (assetId == null) return Math.abs(salt);
        return Math.abs((String.valueOf(assetId) + ':' + salt).hashCode());
    }

    private static Decimal roundOne(Decimal v) {
        if (v == null) return null;
        return v.setScale(1);
    }

    private static String formatAddress(Asset a) {
        if (a == null) return null;
        List<String> parts = new List<String>();
        if (String.isNotBlank(a.Street)) parts.add(a.Street);
        List<String> cityState = new List<String>();
        if (String.isNotBlank(a.City)) cityState.add(a.City);
        if (String.isNotBlank(a.State)) cityState.add(a.State);
        String cityStateStr = String.join(cityState, ', ');
        if (String.isNotBlank(cityStateStr)) parts.add(cityStateStr);
        if (String.isNotBlank(a.PostalCode)) parts.add(a.PostalCode);
        return parts.isEmpty() ? null : String.join(parts, ' ');
    }

    private static String capitalize(String s) {
        if (String.isBlank(s)) return s;
        return s.substring(0, 1).toUpperCase() + s.substring(1);
    }
}
