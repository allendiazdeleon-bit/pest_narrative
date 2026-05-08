/**
 * ProactiveWoGenerator — creates proactive Field Service Work Orders for
 * customer properties currently breaching a pest-pressure monitor's
 * threshold. Mocks the "Agentforce ran an overnight scan and generated
 * Booster Termite Inspection WOs before anyone called" arc — see
 * PEST_NARRATIVE § Proactive scenario.
 *
 * Production replacement: a scheduled job (or external IoT bait-station
 * webhook) calls Agentforce, which uses PestPressureAnalyzer to diagnose,
 * then calls AppointmentBooker.book + AppointmentConfirmer.confirm to
 * create the WO. This class shortcuts that by reading the existing
 * RecordsetFltrCritMonitor breaches and writing the WOs directly.
 *
 * Customer reply behavior is scripted via the (optional)
 * Demo_Reply_Outcome__mdt records:
 *   - YES      → create a proactive Booster Termite Inspection WO + linking Case
 *   - NO       → create only a Case noting the customer declined
 *   - NO_REPLY → create only a Case marked "follow-up needed"
 * If the metadata isn't deployed, default per-account behavior is YES for
 * the first 11 pest-pressure candidates, NO for the remaining 3 (matching
 * the "11 of 14 say yes" beat in the demo plan).
 *
 * Idempotency: skips Accounts that already have a proactive WO or Case
 * from a prior run (matched by AccountId + Origin='Proactive Telemetry').
 */
public with sharing class ProactiveWoGenerator {

    public class Result {
        @AuraEnabled public Integer breachesScanned;
        @AuraEnabled public Integer proactiveWosCreated;
        @AuraEnabled public Integer declinedCasesCreated;
        @AuraEnabled public Integer noReplyCasesCreated;
        @AuraEnabled public Integer skippedExisting;
        @AuraEnabled public List<Id> createdRecordIds;
        @AuraEnabled public String message;
    }

    @AuraEnabled
    public static Result runAll() {
        // Skip Lisa Chen — she's the demo hero,
        // her WO should be created LIVE when the presenter clicks the
        // "Trigger Proactive Outreach (Demo)" Quick Action on her property record.
        return runFiltered(null, null, new Set<String>{'Lisa Chen'});
    }

    @AuraEnabled
    public static Result runAllIncludingHeroes() {
        return runFiltered(null, null, null);
    }

    @AuraEnabled
    public static Result runForMonitor(Id monitorId) {
        return runFiltered(new Set<Id>{ monitorId }, null, null);
    }

    /**
     * Asset-scoped run — for the QA on the property record page. Creates
     * a proactive WO for THIS one property if it's currently breaching any
     * pest-pressure monitor.
     */
    @AuraEnabled
    public static Result runForAsset(Id assetId) {
        return runFiltered(null, new Set<Id>{ assetId }, null);
    }

    private static Result runFiltered(Set<Id> monitorIds, Set<Id> assetIds, Set<String> excludeAccountNames) {
        Result r = new Result();
        r.breachesScanned = 0;
        r.proactiveWosCreated = 0;
        r.declinedCasesCreated = 0;
        r.noReplyCasesCreated = 0;
        r.skippedExisting = 0;
        r.createdRecordIds = new List<Id>();

        List<RecordsetFltrCritMonitor> breaches;
        if (monitorIds == null && assetIds == null) {
            breaches = [SELECT Id, AssetId, Asset.Name, Asset.AccountId, Asset.Account.Name,
                               Asset.Service_Line__c, RecordsetFilterCriteriaId,
                               RecordsetFilterCriteria.Name
                        FROM RecordsetFltrCritMonitor
                        WHERE IsWithinThreshold = false];
        } else if (assetIds != null) {
            breaches = [SELECT Id, AssetId, Asset.Name, Asset.AccountId, Asset.Account.Name,
                               Asset.Service_Line__c, RecordsetFilterCriteriaId,
                               RecordsetFilterCriteria.Name
                        FROM RecordsetFltrCritMonitor
                        WHERE IsWithinThreshold = false
                          AND AssetId IN :assetIds];
        } else {
            breaches = [SELECT Id, AssetId, Asset.Name, Asset.AccountId, Asset.Account.Name,
                               Asset.Service_Line__c, RecordsetFilterCriteriaId,
                               RecordsetFilterCriteria.Name
                        FROM RecordsetFltrCritMonitor
                        WHERE IsWithinThreshold = false
                          AND RecordsetFilterCriteriaId IN :monitorIds];
        }
        r.breachesScanned = breaches.size();
        if (breaches.isEmpty()) {
            r.message = 'No threshold breaches found. All monitored properties are within their pest-pressure thresholds.';
            return r;
        }

        // Load Demo_Reply_Outcome__mdt if available; build a Name → Outcome map
        Map<String, String> replyByAccountName = new Map<String, String>();
        try {
            for (Demo_Reply_Outcome__mdt row : Demo_Reply_Outcome__mdt.getAll().values()) {
                if (row.Person_Account_Name__c != null) {
                    replyByAccountName.put(row.Person_Account_Name__c.toLowerCase(), row.Outcome__c);
                }
            }
        } catch (Exception e) {
            // MDT not deployed; use the per-index fallback below.
        }

        // Idempotency: skip Accounts that already have an Origin='Proactive Telemetry'
        // WO or Case from a prior run.
        Set<Id> accountIds = new Set<Id>();
        for (RecordsetFltrCritMonitor link : breaches) accountIds.add(link.Asset.AccountId);
        Set<Id> accountsAlreadyHandled = new Set<Id>();
        for (WorkOrder w : [SELECT AccountId FROM WorkOrder
                             WHERE AccountId IN :accountIds
                               AND Subject LIKE 'Booster Termite Inspection%']) {
            accountsAlreadyHandled.add(w.AccountId);
        }
        for (Case c : [SELECT AccountId FROM Case
                        WHERE AccountId IN :accountIds
                          AND Origin = 'Proactive Telemetry'
                          AND Status NOT IN ('Closed','Cancelled')]) {
            accountsAlreadyHandled.add(c.AccountId);
        }

        // Fallback ordering: first N breaches → YES, rest → NO
        Integer YES_QUOTA = 11;
        Integer NO_QUOTA = 3;
        Integer yesGiven = 0, noGiven = 0;

        Id boosterWorkTypeId;
        try {
            boosterWorkTypeId = [SELECT Id FROM WorkType
                                    WHERE Name = 'Booster Termite Inspection' LIMIT 1].Id;
        } catch (QueryException e) {
            r.message = 'Failed: "Booster Termite Inspection" Work Type not found. Run OrgBootstrap.ensureFoundation() first.';
            return r;
        }

        List<Case> casesToInsert = new List<Case>();
        List<WorkOrder> wosToInsert = new List<WorkOrder>();

        // Demo polish: process named heroes (Lisa, Sandra, David) first so
        // they always land in the YES bucket. Otherwise the demo plan's
        // "Lisa is one of the 11 who reply YES" beat breaks at random.
        Set<String> heroes = new Set<String>{'Lisa Chen','Sandra Reyes','David Kim'};
        List<RecordsetFltrCritMonitor> orderedBreaches = new List<RecordsetFltrCritMonitor>();
        List<RecordsetFltrCritMonitor> heroBreaches = new List<RecordsetFltrCritMonitor>();
        List<RecordsetFltrCritMonitor> otherBreaches = new List<RecordsetFltrCritMonitor>();
        for (RecordsetFltrCritMonitor b : breaches) {
            if (heroes.contains(b.Asset.Account.Name)) heroBreaches.add(b);
            else otherBreaches.add(b);
        }
        orderedBreaches.addAll(heroBreaches);
        orderedBreaches.addAll(otherBreaches);

        for (RecordsetFltrCritMonitor link : orderedBreaches) {
            if (accountsAlreadyHandled.contains(link.Asset.AccountId)) {
                r.skippedExisting++;
                continue;
            }
            if (excludeAccountNames != null && link.Asset.Account.Name != null
                && excludeAccountNames.contains(link.Asset.Account.Name)) {
                r.skippedExisting++;
                continue;
            }
            String accountName = link.Asset.Account.Name == null ? '' : link.Asset.Account.Name.toLowerCase();
            String outcome = replyByAccountName.get(accountName);
            if (outcome == null) {
                if (yesGiven < YES_QUOTA) { outcome = 'YES'; yesGiven++; }
                else if (noGiven < NO_QUOTA) { outcome = 'NO'; noGiven++; }
                else { outcome = 'NO_REPLY'; }
            }

            String diagnosis = 'Overnight pest-pressure scan flagged elevated risk at ' + link.Asset.Name
                + ' — bait station hits trending up, soil temp in active range, FL termite swarm window approaching. '
                + 'Recommend booster termite inspection before next quarterly visit.';

            if (outcome == 'YES') {
                WorkOrder wo = new WorkOrder(
                    AccountId = link.Asset.AccountId,
                    AssetId = link.AssetId,
                    WorkTypeId = boosterWorkTypeId,
                    Subject = 'Booster Termite Inspection — ' + link.Asset.Name,
                    Description = diagnosis + '\n\nCustomer accepted proactive visit offer.\n\n[proactive-telemetry] [monitor:' + link.RecordsetFilterCriteriaId + ']',
                    Status = 'New',
                    Priority = 'Medium',
                    StartDate = DateTime.now().addDays(1),
                    EndDate = DateTime.now().addDays(1).addHours(2)
                );
                wosToInsert.add(wo);
            } else if (outcome == 'NO') {
                casesToInsert.add(new Case(
                    AccountId = link.Asset.AccountId,
                    AssetId = link.AssetId,
                    Subject = 'Proactive Outreach Declined — ' + link.Asset.Name,
                    Description = diagnosis + '\n\nCustomer declined proactive visit. Recommend follow-up if pattern persists.\n\n[proactive-telemetry]',
                    Status = 'New',
                    Origin = 'Proactive Telemetry',
                    Priority = 'Low'
                ));
            } else {
                casesToInsert.add(new Case(
                    AccountId = link.Asset.AccountId,
                    AssetId = link.AssetId,
                    Subject = 'Proactive Outreach — No Reply — ' + link.Asset.Name,
                    Description = diagnosis + '\n\nNo reply from customer. Queue for follow-up call.\n\n[proactive-telemetry]',
                    Status = 'New',
                    Origin = 'Proactive Telemetry',
                    Priority = 'Medium'
                ));
            }
        }

        if (!wosToInsert.isEmpty()) {
            insert wosToInsert;
            for (WorkOrder w : wosToInsert) {
                r.createdRecordIds.add(w.Id);
                // Seed the WorkPlan + WorkSteps so the orchestrator's
                // checklist is populated when the presenter walks the
                // newly-created WO. Bulk-loader path has the same effect.
                try { DemoDataLoader.createPlanAndStepsForWo(w.Id); }
                catch (Exception planEx) { System.debug('WorkPlan seed skipped for ' + w.Id + ': ' + planEx.getMessage()); }
            }
            r.proactiveWosCreated = wosToInsert.size();
        }
        if (!casesToInsert.isEmpty()) {
            insert casesToInsert;
            for (Case c : casesToInsert) {
                r.createdRecordIds.add(c.Id);
                if (c.Subject.contains('Declined')) r.declinedCasesCreated++;
                else r.noReplyCasesCreated++;
            }
        }

        r.message = 'Scanned ' + r.breachesScanned + ' breaches. Created '
            + r.proactiveWosCreated + ' booster WOs (YES), '
            + r.declinedCasesCreated + ' declined Cases (NO), '
            + r.noReplyCasesCreated + ' no-reply Cases. Skipped ' + r.skippedExisting + ' already-handled.';
        return r;
    }
}
