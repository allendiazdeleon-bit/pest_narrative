/**
 * ImpactPreviewService — answers "who and what gets affected" before a
 * field tech takes a service-affecting action (e.g., perimeter ULV fog
 * application, restricted-use pesticide spray, or whole-home tent
 * fumigation that requires neighbors to be notified). Backs the Impact
 * Preview LWC inside the Service Impact step on Work Order.
 *
 * Demo-grade: the affected-customer set is FAKED but uses real org
 * data — neighbors are looked up by AccountNumber proximity (Massey
 * demo accounts have adjacent numbers on adjacent addresses).
 *
 * For incident-driven previews, the affected set comes from
 * Cases linked via Case.Linked_Incident__c (real, not faked).
 *
 * generateNotification() materializes the preview into a draft
 * ProductServiceCampaign + per-customer ProductServiceCampaignItems
 * so the supervisor can review/send before the tech executes the action.
 */
public with sharing class ImpactPreviewService {

    public class AffectedCustomer {
        @AuraEnabled public Id accountId;
        @AuraEnabled public String accountName;
        @AuraEnabled public String address;
        @AuraEnabled public Id assetId;
        @AuraEnabled public String assetName;
        @AuraEnabled public String priority;        // 'Standard' | 'Vulnerable' | 'Critical'
        @AuraEnabled public String priorityReason;  // '' | 'Senior household' | 'Medical condition' | 'Has young children' | 'Has pets'
    }

    public class ImpactSummary {
        @AuraEnabled public Id workOrderId;
        @AuraEnabled public String action;                       // 'Perimeter ULV Fog' | 'Restricted-Use Pesticide Application' | 'Tent Fumigation' | 'Service Disconnect'
        @AuraEnabled public Integer affectedCount;
        @AuraEnabled public Integer durationEstimateMinutes;
        @AuraEnabled public List<AffectedCustomer> affectedCustomers;
        @AuraEnabled public List<String> criticalFlags;
        @AuraEnabled public String recommendedNotificationChannel;
        @AuraEnabled public Integer notificationLeadTimeMinutes;
        @AuraEnabled public String summary;
    }

    private static final Map<String, Integer> DURATION_BY_ACTION = new Map<String, Integer>{
        'Perimeter ULV Fog'                  => 90,
        'Restricted-Use Pesticide Application' => 120,
        'Tent Fumigation'                   => 1440,  // 24 hours sealed
        'Service Disconnect'                => 30,
        'Set Treatment Perimeter'           => 60,
        'Release Property after Re-Entry Interval' => 30,
        'Booster Pest Treatment'            => 90,
        'Sentricon Re-baiting'              => 45
    };

    @AuraEnabled(cacheable=true)
    public static ImpactSummary previewForWorkOrder(Id workOrderId, String actionType) {
        if (workOrderId == null) {
            throw new AuraHandledException('workOrderId is required');
        }
        String action = normalizeAction(actionType);

        WorkOrder wo = [
            SELECT Id, AccountId, AssetId, Account.AccountNumber
              FROM WorkOrder
             WHERE Id = :workOrderId
             LIMIT 1
        ];

        List<Account> neighbors = findNeighborAccounts(wo.Account != null ? wo.Account.AccountNumber : null, wo.AccountId);
        List<AffectedCustomer> customers = buildAffectedCustomers(neighbors);

        return assemble(workOrderId, action, customers);
    }

    @AuraEnabled(cacheable=true)
    public static ImpactSummary previewForIncident(Id incidentId, String actionType) {
        if (incidentId == null) {
            throw new AuraHandledException('incidentId is required');
        }
        String action = normalizeAction(actionType);

        Set<Id> accountIds = new Set<Id>();
        for (Case c : [SELECT AccountId FROM Case WHERE Linked_Incident__c = :incidentId AND AccountId != null]) {
            accountIds.add(c.AccountId);
        }
        List<Account> accounts = [
            SELECT Id, Name, AccountNumber, BillingStreet,
                   (SELECT Id, Name FROM Assets LIMIT 1)
              FROM Account WHERE Id IN :accountIds
              ORDER BY Name LIMIT 50
        ];
        List<AffectedCustomer> customers = buildAffectedCustomers(accounts);
        return assemble(null, action, customers);
    }

    @AuraEnabled
    public static Id generateNotification(Id workOrderId, String actionType) {
        ImpactSummary s = previewForWorkOrder(workOrderId, actionType);

        ProductServiceCampaign psc = new ProductServiceCampaign(
            ProductServiceCampaignName = 'Impact Preview — ' + s.action,
            Type = 'Service',
            Status = 'New',
            Priority = 'High',
            StartDate = Date.today(),
            EndDate = Date.today().addDays(1),
            Description = s.summary
        );
        insert psc;

        List<ProductServiceCampaignItem> items = new List<ProductServiceCampaignItem>();
        for (AffectedCustomer ac : s.affectedCustomers) {
            if (ac.assetId == null) continue;
            items.add(new ProductServiceCampaignItem(
                ProductServiceCampaignId = psc.Id,
                AssetId = ac.assetId,
                Status = 'New'
            ));
        }
        if (!items.isEmpty()) insert items;
        return psc.Id;
    }

    // ---------- Helpers ----------

    private static String normalizeAction(String actionType) {
        if (String.isBlank(actionType)) return 'Restricted-Use Pesticide Application';
        return actionType;
    }

    private static List<Account> findNeighborAccounts(String anchorNumber, Id selfId) {
        // Adjacent demo Accounts by AccountNumber. Best-effort fallback to first 5.
        List<Account> all = [SELECT Id, Name, AccountNumber, BillingStreet,
                                    (SELECT Id, Name FROM Assets LIMIT 1)
                               FROM Account WHERE Id != :selfId
                               ORDER BY AccountNumber LIMIT 50];
        if (String.isBlank(anchorNumber) || all.isEmpty()) {
            List<Account> trim = new List<Account>();
            for (Integer i = 0; i < Math.min(5, all.size()); i++) trim.add(all[i]);
            return trim;
        }
        Integer anchor = -1;
        try { anchor = Integer.valueOf(anchorNumber.replaceAll('[^0-9]','')); } catch (Exception e) {}
        if (anchor < 0) {
            List<Account> trim = new List<Account>();
            for (Integer i = 0; i < Math.min(5, all.size()); i++) trim.add(all[i]);
            return trim;
        }

        List<Account> withDist = new List<Account>();
        for (Account a : all) {
            if (a.AccountNumber == null) continue;
            try {
                Integer n = Integer.valueOf(a.AccountNumber.replaceAll('[^0-9]',''));
                if (Math.abs(n - anchor) <= 5) withDist.add(a);
            } catch (Exception e) {}
            if (withDist.size() >= 6) break;
        }
        return withDist;
    }

    private static List<AffectedCustomer> buildAffectedCustomers(List<Account> accts) {
        List<AffectedCustomer> out = new List<AffectedCustomer>();
        for (Account a : accts) {
            AffectedCustomer ac = new AffectedCustomer();
            ac.accountId = a.Id;
            ac.accountName = a.Name;
            ac.address = a.BillingStreet;
            if (a.Assets != null && !a.Assets.isEmpty()) {
                ac.assetId = a.Assets[0].Id;
                ac.assetName = a.Assets[0].Name;
            }
            // Deterministic priority pick based on Id hash.
            Integer h = Math.abs(String.valueOf(a.Id).hashCode());
            Integer pick = Math.mod(h, 8);
            if (pick == 0) {
                ac.priority = 'Critical';
                ac.priorityReason = 'Has young children';
            } else if (pick == 1) {
                ac.priority = 'Vulnerable';
                ac.priorityReason = 'Senior household';
            } else if (pick == 2) {
                ac.priority = 'Vulnerable';
                ac.priorityReason = 'Has pets';
            } else {
                ac.priority = 'Standard';
                ac.priorityReason = '';
            }
            out.add(ac);
        }
        return out;
    }

    private static ImpactSummary assemble(Id workOrderId, String action, List<AffectedCustomer> customers) {
        ImpactSummary s = new ImpactSummary();
        s.workOrderId = workOrderId;
        s.action = action;
        s.affectedCustomers = customers;
        s.affectedCount = customers.size();
        s.durationEstimateMinutes = DURATION_BY_ACTION.containsKey(action)
            ? DURATION_BY_ACTION.get(action) : 60;

        List<String> flags = new List<String>();
        for (AffectedCustomer ac : customers) {
            if (ac.priority == 'Critical' || ac.priority == 'Vulnerable') {
                flags.add(ac.accountName + ' — ' + ac.priorityReason);
            }
        }
        s.criticalFlags = flags;
        s.recommendedNotificationChannel = (action.containsIgnoreCase('Tent') || action.containsIgnoreCase('ULV')) ? 'SMS' : 'Email';
        s.notificationLeadTimeMinutes = (action.containsIgnoreCase('Tent')) ? 1440 : 60;

        s.summary = 'Impact: ' + s.affectedCount + ' propert' + (s.affectedCount == 1 ? 'y' : 'ies')
            + ' affected by ' + action + '. Estimated duration: ' + s.durationEstimateMinutes + ' min. '
            + (flags.isEmpty() ? 'No vulnerable households flagged.' : flags.size() + ' vulnerable household(s) flagged.');
        return s;
    }
}
