/**
 * SmartDispatchSuggester — Mock-AI dispatch ranker for Massey's Orlando
 * branch. Reads today + tomorrow's open ServiceAppointments and ranks
 * them using a deterministic heuristic that mimics what an AI dispatcher
 * would do:
 *   1. SAs whose parent WorkOrder is linked to an active customer-impacting
 *      Incident bubble to the top (Major Incident Linked) — e.g., Cluster
 *      Response WOs spawned from the post-storm mosquito surge.
 *   2. SAs for high-churn-risk customers bubble next (Churn Risk).
 *   3. SAs sharing a Service_Group__c (route/cluster id) get a geo-efficiency boost.
 *   4. SAs close to SLA breach (DueDate within 8 hours) earn an SLA Risk badge.
 *
 * PRODUCTION REPLACEMENT: feed the candidates to an Einstein model trained
 * on historical dispatch + churn outcomes; consume the score back here.
 *
 * Used by the dispatch_SmartSuggester LWC on Ray Garcia's Dispatcher Console.
 */
public with sharing class SmartDispatchSuggester {

    // ---------------------------------------------------------------------
    // DTO
    // ---------------------------------------------------------------------

    public class DispatchSuggestion {
        @AuraEnabled public Id serviceAppointmentId;
        @AuraEnabled public String subject;
        @AuraEnabled public DateTime earliestStartTime;
        @AuraEnabled public DateTime dueDate;
        @AuraEnabled public String workTypeName;
        @AuraEnabled public Id workOrderId;
        @AuraEnabled public Id incidentId;
        @AuraEnabled public Integer recommendedRank;
        @AuraEnabled public String rationale;
        @AuraEnabled public String criticalityBadge;        // 'SLA Risk' | 'Major Incident Linked' | 'Geo-Cluster' | 'Standard'
        @AuraEnabled public Decimal score;                  // internal raw score
        @AuraEnabled public Decimal confidence;             // 0-100
        @AuraEnabled public String summary;
        @AuraEnabled public String source;
        @AuraEnabled public DateTime generatedAt;
    }

    // ---------------------------------------------------------------------
    // Public entry point
    // ---------------------------------------------------------------------

    @AuraEnabled(cacheable=true)
    public static List<DispatchSuggestion> suggestOrderForToday() {
        DateTime startWindow = DateTime.newInstance(Date.today(), Time.newInstance(0, 0, 0, 0));
        DateTime endWindow = startWindow.addDays(2);   // today + tomorrow

        List<ServiceAppointment> sas = [
            SELECT Id, Subject, Status, ParentRecordId,
                   SchedStartTime, EarliestStartTime, DueDate, Duration
            FROM ServiceAppointment
            WHERE Status NOT IN ('Completed','Canceled','Cannot Complete')
              AND (
                    (EarliestStartTime != null AND EarliestStartTime < :endWindow)
                 OR (SchedStartTime  != null AND SchedStartTime  < :endWindow)
              )
            WITH SECURITY_ENFORCED
            ORDER BY EarliestStartTime ASC NULLS LAST
            LIMIT 100
        ];

        if (sas.isEmpty()) return new List<DispatchSuggestion>();

        // Resolve parent WOs in one query — pulls Asset + Incident link.
        Set<Id> woIds = new Set<Id>();
        for (ServiceAppointment sa : sas) {
            if (sa.ParentRecordId != null) woIds.add(sa.ParentRecordId);
        }
        Map<Id, WorkOrder> woById = new Map<Id, WorkOrder>();
        if (!woIds.isEmpty()) {
            for (WorkOrder wo : [
                SELECT Id, Subject, AccountId, AssetId, WorkType.Name,
                       Asset.Service_Group__c, Asset.Service_Line__c,
                       Asset.Is_Pest_Pressure_Candidate__c,
                       CaseId, Case.Linked_Incident__c
                FROM WorkOrder WHERE Id IN :woIds
                WITH SECURITY_ENFORCED
            ]) {
                woById.put(wo.Id, wo);
            }
        }

        // Build incident lookup so we know which WOs reference active incidents.
        Set<Id> incidentIds = new Set<Id>();
        for (WorkOrder wo : woById.values()) {
            if (wo.Case != null && wo.Case.Linked_Incident__c != null) {
                incidentIds.add(wo.Case.Linked_Incident__c);
            }
        }
        Map<Id, Incident> incidentById = new Map<Id, Incident>();
        if (!incidentIds.isEmpty()) {
            for (Incident inc : [
                SELECT Id, Subject, StatusCode, Priority, Affected_Customers__c
                FROM Incident WHERE Id IN :incidentIds
                WITH SECURITY_ENFORCED
            ]) {
                incidentById.put(inc.Id, inc);
            }
        }

        // Account-Id -> churn risk score (cached). We keep it cheap by
        // computing only for accounts that appear in this SA batch.
        Set<Id> accountIds = new Set<Id>();
        for (WorkOrder wo : woById.values()) {
            if (wo.AccountId != null) accountIds.add(wo.AccountId);
        }
        Map<Id, Integer> churnByAccount = computeChurnScores(accountIds);

        // Service_Group__c -> count of SAs in the batch (cluster boost).
        Map<String, Integer> sgCounts = new Map<String, Integer>();
        for (ServiceAppointment sa : sas) {
            WorkOrder wo = woById.get(sa.ParentRecordId);
            if (wo == null || wo.Asset == null) continue;
            String sg = wo.Asset.Service_Group__c;
            if (String.isBlank(sg)) continue;
            sgCounts.put(sg, (sgCounts.containsKey(sg) ? sgCounts.get(sg) : 0) + 1);
        }

        // Score every SA, pack into DispatchSuggestion.
        List<DispatchSuggestion> suggestions = new List<DispatchSuggestion>();
        for (ServiceAppointment sa : sas) {
            DispatchSuggestion s = new DispatchSuggestion();
            s.serviceAppointmentId = sa.Id;
            s.subject = sa.Subject;
            s.earliestStartTime = sa.EarliestStartTime;
            s.dueDate = sa.DueDate;
            s.workOrderId = sa.ParentRecordId;
            s.source = 'SmartDispatchSuggester';
            s.generatedAt = DateTime.now();

            WorkOrder wo = woById.get(sa.ParentRecordId);
            Decimal score = 0;
            List<String> reasons = new List<String>();
            String badge = 'Standard';

            // 1. Incident-linked SAs (highest priority)
            Id incId = null;
            if (wo != null) {
                s.workTypeName = wo.WorkType != null ? wo.WorkType.Name : null;
                if (wo.Case != null && wo.Case.Linked_Incident__c != null
                        && incidentById.containsKey(wo.Case.Linked_Incident__c)) {
                    incId = wo.Case.Linked_Incident__c;
                }
            }
            if (incId != null) {
                Incident inc = incidentById.get(incId);
                Integer affected = inc.Affected_Customers__c != null
                    ? Integer.valueOf(inc.Affected_Customers__c) : 0;
                score += 80 + Math.min(affected / 5, 15);
                badge = 'Major Incident Linked';
                reasons.add('Linked to active Incident "' + inc.Subject
                    + '" (' + affected + ' customers affected).');
                s.incidentId = incId;
            }

            // 2. Churn risk on the customer
            Integer churn = (wo != null && wo.AccountId != null)
                ? (churnByAccount.containsKey(wo.AccountId) ? churnByAccount.get(wo.AccountId) : 0)
                : 0;
            if (churn >= 70) {
                score += 35;
                if (badge == 'Standard') badge = 'Churn Risk';
                reasons.add('High-churn-risk customer (score ' + churn + ') — prioritize to retain.');
            } else if (churn >= 40) {
                score += 12;
                reasons.add('Moderate churn risk (' + churn + ') on this account.');
            }

            // 3. Geo-cluster boost
            if (wo != null && wo.Asset != null && String.isNotBlank(wo.Asset.Service_Group__c)) {
                Integer cnt = sgCounts.containsKey(wo.Asset.Service_Group__c)
                    ? sgCounts.get(wo.Asset.Service_Group__c) : 0;
                if (cnt >= 2) {
                    score += 15 + Math.min(cnt * 2, 12);
                    if (badge == 'Standard') badge = 'Geo-Cluster';
                    reasons.add(cnt + ' SAs share Service Group ' + wo.Asset.Service_Group__c
                        + ' — geo-efficient route.');
                }
            }

            // 4. SLA risk (DueDate close)
            Integer hoursToDue = hoursBetweenNowAnd(sa.DueDate);
            if (hoursToDue >= 0 && hoursToDue <= 8) {
                score += 25;
                if (badge == 'Standard') badge = 'SLA Risk';
                reasons.add('SLA window closes in ~' + hoursToDue + ' hr — schedule first.');
            }

            // 5. Property flagged for pest pressure — small boost
            if (wo != null && wo.Asset != null && wo.Asset.Is_Pest_Pressure_Candidate__c == true) {
                score += 8;
                reasons.add('Property is on the pest-pressure watch list.');
            }

            if (reasons.isEmpty()) {
                reasons.add('No special signals; route by standard rules.');
            }

            s.score = score;
            s.criticalityBadge = badge;
            s.rationale = String.join(reasons, ' ');
            s.confidence = Math.min(95, 60 + reasons.size() * 8);
            s.summary = badge + ' — ' + s.rationale;
            suggestions.add(s);
        }

        // Sort descending by score (insertion sort; n<=100).
        for (Integer i = 1; i < suggestions.size(); i++) {
            DispatchSuggestion key = suggestions[i];
            Integer j = i - 1;
            while (j >= 0 && suggestions[j].score < key.score) {
                suggestions[j + 1] = suggestions[j];
                j--;
            }
            suggestions[j + 1] = key;
        }
        for (Integer i = 0; i < suggestions.size(); i++) {
            suggestions[i].recommendedRank = i + 1;
        }
        return suggestions;
    }

    // ---------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------

    /**
     * Lightweight churn estimate per account — same shape as
     * ChurnRiskScorer but avoids a callout to that class to keep this
     * service self-contained. Counts cases in last 90 days +
     * adds a deterministic per-account hash so neighbors differ.
     */
    private static Map<Id, Integer> computeChurnScores(Set<Id> accountIds) {
        Map<Id, Integer> out = new Map<Id, Integer>();
        if (accountIds == null || accountIds.isEmpty()) return out;
        for (Id aid : accountIds) out.put(aid, 0);

        DateTime windowStart = DateTime.now().addDays(-90);
        for (AggregateResult ar : [
            SELECT AccountId acc, COUNT(Id) cnt
            FROM Case
            WHERE AccountId IN :accountIds
              AND CreatedDate >= :windowStart
            WITH SECURITY_ENFORCED
            GROUP BY AccountId
        ]) {
            Id aid = (Id) ar.get('acc');
            Integer cnt = (Integer) ar.get('cnt');
            Integer caseScore = Math.min(cnt * 18, 60);
            out.put(aid, caseScore);
        }
        // Deterministic per-account sprinkle so the demo mix isn't all 0/18/36/...
        for (Id aid : new Set<Id>(out.keySet())) {
            Integer h = Math.abs(String.valueOf(aid).hashCode());
            Integer sprinkle = Math.mod(h, 30);   // 0-29
            out.put(aid, Math.min(100, out.get(aid) + sprinkle));
        }
        return out;
    }

    private static Integer hoursBetweenNowAnd(DateTime dt) {
        if (dt == null) return -1;
        Long ms = dt.getTime() - DateTime.now().getTime();
        if (ms < 0) return 0;
        return (Integer) (ms / (1000L * 60L * 60L));
    }
}
