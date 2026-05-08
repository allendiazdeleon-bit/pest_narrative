/**
 * IncidentDispatchService — backs the "Dispatch Field Response" Quick
 * Action on Incident. Lets Ray Garcia (operations supervisor) pick a
 * dispatch strategy that matches the situation:
 *
 *   - SINGLE_RESPONSE:  one root-cause WO at the suspected source (the
 *                       right call for a confirmed cluster like the
 *                       mosquito surge — don't dispatch 8 crews to 8
 *                       affected homes when the clogged storm drain is
 *                       the real source. One ULV-fog truck targets the
 *                       breeding event).
 *   - BUNDLED_BY_SEGMENT: group affected addresses by street segment and
 *                       create one WO + SA per group (good for phased
 *                       perimeter sweeps after the source is cleared).
 *   - PER_PROPERTY:     one WO per affected property (storm-cleanup mode
 *                       where each home truly needs its own visit, e.g.,
 *                       a termite swarm cluster where every property gets
 *                       its own Sentricon inspection).
 *
 * All created WOs carry Linked_Incident__c so the Emergency Divert
 * flow downstream can find them by Incident.
 */
public with sharing class IncidentDispatchService {

    public class WorkTypeOption {
        @AuraEnabled public Id workTypeId;
        @AuraEnabled public String name;
    }

    public class AffectedAsset {
        @AuraEnabled public Id assetId;
        @AuraEnabled public Id accountId;
        @AuraEnabled public String accountName;
        @AuraEnabled public String address;
        @AuraEnabled public String segment;
    }

    public class DispatchPreview {
        @AuraEnabled public List<AffectedAsset> affectedAssets;
        @AuraEnabled public Integer segmentCount;
        @AuraEnabled public List<WorkTypeOption> workTypes;
    }

    public class DispatchResult {
        @AuraEnabled public List<Id> workOrderIds;
        @AuraEnabled public Integer workOrdersCreated;
        @AuraEnabled public Integer serviceAppointmentsCreated;
        @AuraEnabled public String strategy;
    }

    @AuraEnabled(cacheable=true)
    public static DispatchPreview previewDispatch(Id incidentId) {
        DispatchPreview p = new DispatchPreview();
        p.affectedAssets = buildAffectedAssets(incidentId);

        Set<String> segments = new Set<String>();
        for (AffectedAsset a : p.affectedAssets) segments.add(a.segment);
        p.segmentCount = segments.size();

        p.workTypes = new List<WorkTypeOption>();
        for (WorkType wt : [SELECT Id, Name FROM WorkType
                             WHERE Name IN ('Mosquito Surge Area Treatment','Sentricon Install',
                                            'Sentricon Re-baiting','GoGreen Quarterly Pest',
                                            'Booster Termite Inspection','Booster Pest Treatment',
                                            'Mosquito Hunter Activation','Lawn Treatment',
                                            'New Service Activation')
                             ORDER BY Name]) {
            WorkTypeOption opt = new WorkTypeOption();
            opt.workTypeId = wt.Id;
            opt.name = wt.Name;
            p.workTypes.add(opt);
        }
        return p;
    }

    @AuraEnabled
    public static DispatchResult dispatch(Id incidentId, String strategy, Id workTypeId, String priority) {
        DispatchResult r = new DispatchResult();
        r.workOrderIds = new List<Id>();
        r.strategy = strategy;

        Incident inc = [SELECT Id, Subject, Circuit__c FROM Incident WHERE Id = :incidentId LIMIT 1];
        List<AffectedAsset> affected = buildAffectedAssets(incidentId);
        if (affected.isEmpty()) {
            r.workOrdersCreated = 0;
            r.serviceAppointmentsCreated = 0;
            return r;
        }

        if (priority == null) priority = 'High';
        DateTime startTime = DateTime.now();
        DateTime endTime = DateTime.now().addHours(4);

        List<WorkOrder> wos = new List<WorkOrder>();

        if (strategy == 'SINGLE_RESPONSE') {
            AffectedAsset root = affected[0];
            WorkOrder w = new WorkOrder(
                AccountId = root.accountId,
                AssetId = root.assetId,
                WorkTypeId = workTypeId,
                Subject = 'Source-Site Treatment: ' + inc.Subject,
                Status = 'New',
                Priority = priority,
                StartDate = startTime,
                EndDate = endTime,
                Linked_Incident__c = incidentId,
                Description = '[masseyFlow] Single-response WO covering ' + affected.size()
                    + ' affected properties on ' + inc.Circuit__c
                    + '. Crew treats the source (e.g., clogged storm drain breeding event); per-property follow-up only if needed after the source is cleared.'
            );
            applyAddress(w, root.address);
            wos.add(w);
        } else if (strategy == 'BUNDLED_BY_SEGMENT') {
            Map<String, List<AffectedAsset>> bySegment = new Map<String, List<AffectedAsset>>();
            for (AffectedAsset a : affected) {
                if (!bySegment.containsKey(a.segment)) bySegment.put(a.segment, new List<AffectedAsset>());
                bySegment.get(a.segment).add(a);
            }
            for (String seg : bySegment.keySet()) {
                List<AffectedAsset> segMembers = bySegment.get(seg);
                AffectedAsset rep = segMembers[0];
                WorkOrder w = new WorkOrder(
                    AccountId = rep.accountId,
                    AssetId = rep.assetId,
                    WorkTypeId = workTypeId,
                    Subject = 'Segment Sweep: ' + seg + ' (' + segMembers.size() + ' properties)',
                    Status = 'New',
                    Priority = priority,
                    StartDate = startTime,
                    EndDate = endTime,
                    Linked_Incident__c = incidentId,
                    Description = '[masseyFlow] Bundled WO covering ' + segMembers.size()
                        + ' properties on ' + seg + ' segment of ' + inc.Circuit__c
                        + '.\n\nAddresses included:\n' + addressList(segMembers)
                );
                applyAddress(w, rep.address);
                wos.add(w);
            }
        } else { // PER_PROPERTY
            for (AffectedAsset a : affected) {
                WorkOrder w = new WorkOrder(
                    AccountId = a.accountId,
                    AssetId = a.assetId,
                    WorkTypeId = workTypeId,
                    Subject = 'Inspection: ' + a.address,
                    Status = 'New',
                    Priority = priority,
                    StartDate = startTime,
                    EndDate = endTime,
                    Linked_Incident__c = incidentId,
                    Description = '[masseyFlow] Per-property inspection at ' + a.address + '.'
                );
                applyAddress(w, a.address);
                wos.add(w);
            }
        }

        insert wos;
        for (WorkOrder w : wos) r.workOrderIds.add(w.Id);
        r.workOrdersCreated = wos.size();

        List<ServiceAppointment> sas = new List<ServiceAppointment>();
        for (WorkOrder w : wos) {
            sas.add(new ServiceAppointment(
                ParentRecordId = w.Id,
                Subject = 'SA for ' + w.Subject,
                EarliestStartTime = startTime,
                DueDate = endTime,
                SchedStartTime = startTime,
                SchedEndTime = endTime,
                Description = '[masseyFlow] Auto-created SA for cluster response.'
            ));
        }
        if (!sas.isEmpty()) insert sas;
        r.serviceAppointmentsCreated = sas.size();
        return r;
    }

    private static List<AffectedAsset> buildAffectedAssets(Id incidentId) {
        Map<Id, AffectedAsset> byAccount = new Map<Id, AffectedAsset>();
        for (Case c : [SELECT Id, Subject, AccountId, Account.Name FROM Case
                        WHERE Linked_Incident__c = :incidentId AND AccountId != null
                        ORDER BY Subject]) {
            AffectedAsset a = new AffectedAsset();
            a.accountId = c.AccountId;
            a.accountName = c.Account.Name;
            a.address = c.Subject != null && c.Subject.contains(' at ')
                ? c.Subject.substringAfter(' at ') : c.Subject;
            a.segment = parseSegment(a.address);
            byAccount.put(c.AccountId, a);
        }
        if (byAccount.isEmpty()) return new List<AffectedAsset>();

        for (Asset asset : [SELECT Id, AccountId FROM Asset
                             WHERE AccountId IN :byAccount.keySet()]) {
            if (byAccount.containsKey(asset.AccountId)) {
                byAccount.get(asset.AccountId).assetId = asset.Id;
            }
        }
        // Strip out any rows without an Asset (defensive)
        List<AffectedAsset> out = new List<AffectedAsset>();
        for (AffectedAsset a : byAccount.values()) {
            if (a.assetId != null) out.add(a);
        }
        return out;
    }

    /**
     * Parse the street name from an address like "1407 Avalon Park Blvd"
     * so we can group affected properties into rough geographic segments.
     */
    private static String parseSegment(String address) {
        if (String.isBlank(address)) return 'Unknown';
        // Strip leading number, take everything else
        String trimmed = address.trim();
        Integer firstSpace = trimmed.indexOf(' ');
        return firstSpace > 0 ? trimmed.substring(firstSpace + 1).trim() : trimmed;
    }

    /**
     * Populate the WorkOrder's address fields from a "1407 Avalon Park Blvd"
     * style street string. Service Appointments inherit address from
     * the parent WO when their own address fields are null, so the
     * crew sees a real address to navigate to. Default city/zip is
     * Orlando (Massey HQ branch) — ZIP 32828 covers Avalon Park /
     * Waterford Lakes, the cluster anchor.
     */
    private static void applyAddress(WorkOrder w, String street) {
        if (String.isBlank(street)) return;
        w.Street = street;
        w.City = 'Orlando';
        w.State = 'FL';
        w.PostalCode = '32828';
        w.Country = 'USA';
    }

    private static String addressList(List<AffectedAsset> members) {
        List<String> addrs = new List<String>();
        for (AffectedAsset a : members) addrs.add('  • ' + a.address);
        return String.join(addrs, '\n');
    }
}
