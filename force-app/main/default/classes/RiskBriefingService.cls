/**
 * RiskBriefingService — Mock-AI risk briefing rendered on safety-step
 * entry of the masseyFlow orchestrator.
 *
 * Pulls WorkOrder + property + nearby Hazards and returns a single shaped
 * RiskBriefing (weather, prior-incident history, nearby hazard count,
 * property-history risk) plus a blended summary string.
 *
 * Mock-AI rules:
 *   - Weather: hardcoded "Orlando sunny" for the demo. Could swap for
 *     Open-Meteo / NOAA in production.
 *   - Locate ticket field reused as "Permit Status" for restricted-use
 *     pesticide application — 'Verified' if Service_Line__c='Termite Protection',
 *     otherwise 'N/A'. Real-world: query a permit tracker.
 *   - Nearby hazards: count of Hazard__c rows with same Service_Group__c
 *     and Status='Open'. Falls back to 0 if Hazard__c isn't queryable.
 *   - Property-history risk: derived from Is_Pest_Pressure_Candidate__c +
 *     sensor staleness.
 */
public with sharing class RiskBriefingService {

    public class RiskBriefing {
        @AuraEnabled public String weatherRisk;          // 'Low' | 'Moderate' | 'Severe'
        @AuraEnabled public String weatherDetail;
        @AuraEnabled public String locateTicketStatus;   // pest reuse: 'Verified' | 'Pending' | 'N/A'
        @AuraEnabled public Integer nearbyHazards;
        @AuraEnabled public List<String> nearbyHazardLabels;
        @AuraEnabled public String assetHistoryRisk;     // 'Low' | 'Medium' | 'High'
        @AuraEnabled public String assetHistoryDetail;
        @AuraEnabled public String summary;
        @AuraEnabled public Decimal confidence;
        @AuraEnabled public String source;
        @AuraEnabled public DateTime generatedAt;

        public RiskBriefing() {
            this.nearbyHazardLabels = new List<String>();
        }
    }

    @AuraEnabled(cacheable=true)
    public static RiskBriefing briefForWorkOrder(Id workOrderId) {
        if (workOrderId == null) {
            throw new AuraHandledException('workOrderId is required.');
        }

        WorkOrder wo;
        try {
            wo = [
                SELECT Id, Subject, AssetId, WorkType.Name,
                       Asset.Id, Asset.Name, Asset.Service_Line__c,
                       Asset.Service_Group__c,
                       Asset.Is_Pest_Pressure_Candidate__c,
                       Asset.Last_Sensor_Reading__c
                FROM WorkOrder WHERE Id = :workOrderId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
        } catch (QueryException qe) {
            throw new AuraHandledException('WorkOrder not found: ' + workOrderId);
        }

        RiskBriefing rb = new RiskBriefing();
        rb.source = 'RiskBriefingService + Hazard__c + property signals';
        rb.generatedAt = DateTime.now();

        // ---- Weather (mock — Orlando is sunny in this demo) ----
        rb.weatherRisk = 'Low';
        rb.weatherDetail = 'Orlando Metro forecast: sunny, 82F, 6 mph wind. No precipitation expected during the work window. UV high — apply sunscreen.';

        // ---- Permit / locate-ticket reuse ----
        String svcLine = wo.Asset != null ? (String) safeGet(wo.Asset, 'Service_Line__c') : null;
        if (svcLine != null && svcLine.containsIgnoreCase('Termite')) {
            rb.locateTicketStatus = 'Verified';
        } else {
            rb.locateTicketStatus = 'N/A';
        }

        // ---- Nearby hazards (count Hazard__c with matching Service_Group__c + Status=Open) ----
        rb.nearbyHazards = countNearbyHazards(wo, rb.nearbyHazardLabels);

        // ---- Property history risk ----
        Boolean candidate = wo.Asset != null && safeGet(wo.Asset, 'Is_Pest_Pressure_Candidate__c') == true;
        DateTime lastSensor = wo.Asset != null ? (DateTime) safeGet(wo.Asset, 'Last_Sensor_Reading__c') : null;
        Integer staleDays = daysSince(lastSensor);
        if (candidate && staleDays > 7) {
            rb.assetHistoryRisk = 'High';
            rb.assetHistoryDetail = 'Property is on the pest-pressure watch list and last reported sensor reading '
                + staleDays + ' days ago. Treat as pre-escalation.';
        } else if (candidate) {
            rb.assetHistoryRisk = 'Medium';
            rb.assetHistoryDetail = 'Property is on the pest-pressure watch list. Sensor data is current; capture extra evidence on site.';
        } else if (staleDays > 14) {
            rb.assetHistoryRisk = 'Medium';
            rb.assetHistoryDetail = 'No sensor reading in '
                + staleDays + ' days — bait stations may be offline or inactive.';
        } else {
            rb.assetHistoryRisk = 'Low';
            rb.assetHistoryDetail = 'No notable history flags on this property.';
        }

        // ---- Blended summary in Massey-tech voice ----
        List<String> bullets = new List<String>();
        bullets.add('Weather: ' + rb.weatherRisk + ' — ' + rb.weatherDetail);
        bullets.add('Permit / restricted-use pesticide auth: ' + rb.locateTicketStatus);
        bullets.add('Nearby hazards: ' + rb.nearbyHazards
            + (rb.nearbyHazards > 0 ? ' open within the same service group.' : ' (clear).'));
        bullets.add('Property history: ' + rb.assetHistoryRisk + ' — ' + rb.assetHistoryDetail);

        rb.summary = String.join(bullets, ' • ');
        rb.confidence = computeConfidence(rb);
        return rb;
    }

    private static Integer countNearbyHazards(WorkOrder wo, List<String> labels) {
        if (wo == null || wo.Asset == null) return 0;
        String sg = (String) safeGet(wo.Asset, 'Service_Group__c');
        if (String.isBlank(sg)) return 0;
        if (!Schema.getGlobalDescribe().containsKey('Hazard__c')) return 0;

        try {
            List<SObject> hazards = Database.query(
                'SELECT Id, Name FROM Hazard__c '
                + 'WHERE Service_Group__c = :sg '
                + 'AND Status__c = \'Open\' '
                + 'LIMIT 10'
            );
            for (SObject h : hazards) {
                String n = (String) h.get('Name');
                if (n != null) labels.add(n);
            }
            return hazards.size();
        } catch (Exception ex) {
            return 0;
        }
    }

    private static Object safeGet(SObject rec, String fieldName) {
        try { return rec.get(fieldName); } catch (Exception e) { return null; }
    }

    private static Integer daysSince(DateTime dt) {
        if (dt == null) return 999;
        Long ms = DateTime.now().getTime() - dt.getTime();
        return (Integer) (ms / (1000L * 60L * 60L * 24L));
    }

    private static Decimal computeConfidence(RiskBriefing rb) {
        Integer base = 70;
        if (rb.locateTicketStatus != 'N/A') base += 8;
        if (rb.nearbyHazards >= 0) base += 5;
        if (!rb.assetHistoryDetail.startsWith('No notable')) base += 7;
        return Math.min(95, base);
    }
}
