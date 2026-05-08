/**
 * IncidentNotifyService — backs the "Notify Affected Customers" Quick
 * Action on Incident. Lets Ray (Orlando ops manager) choose channel
 * + message template, previews the audience, then creates one
 * ProductServiceCampaign + per-Property ProductServiceCampaignItems.
 *
 * The campaign is the deliberate customer-comms decision after a
 * cluster Incident is opened — distinct from field dispatch
 * (IncidentDispatchService). Demo flow: Mosquito Hunter customers in
 * the ZIP-32828 cluster get a proactive "we got it before you called"
 * SMS once Tom's team finishes treatment (Scene 8 → 9 transition).
 *
 * Idempotency: re-running on the same Incident reuses the existing
 * Campaign and tops up missing per-Property items.
 */
public with sharing class IncidentNotifyService {

    public class AffectedCustomer {
        @AuraEnabled public Id accountId;
        @AuraEnabled public String accountName;
        @AuraEnabled public Id assetId;
        @AuraEnabled public String address;
        @AuraEnabled public Id caseId;
        @AuraEnabled public String caseNumber;
    }

    public class SendResult {
        @AuraEnabled public Id campaignId;
        @AuraEnabled public String campaignName;
        @AuraEnabled public Integer itemsCreated;
        @AuraEnabled public Boolean reused;
    }

    @AuraEnabled(cacheable=true)
    public static List<AffectedCustomer> previewAudience(Id incidentId) {
        List<AffectedCustomer> out = new List<AffectedCustomer>();
        Map<Id, AffectedCustomer> byAccount = new Map<Id, AffectedCustomer>();

        for (Case c : [SELECT Id, CaseNumber, Subject, AccountId, Account.Name
                         FROM Case
                        WHERE Linked_Incident__c = :incidentId
                          AND AccountId != null
                        ORDER BY Subject]) {
            AffectedCustomer ac = new AffectedCustomer();
            ac.accountId = c.AccountId;
            ac.accountName = c.Account.Name;
            ac.caseId = c.Id;
            ac.caseNumber = c.CaseNumber;
            ac.address = c.Subject != null && c.Subject.contains(' at ')
                ? c.Subject.substringAfter(' at ') : c.Subject;
            byAccount.put(c.AccountId, ac);
        }

        if (!byAccount.isEmpty()) {
            for (Asset a : [SELECT Id, AccountId FROM Asset
                             WHERE AccountId IN :byAccount.keySet()]) {
                if (byAccount.containsKey(a.AccountId)) {
                    byAccount.get(a.AccountId).assetId = a.Id;
                }
            }
        }
        out.addAll(byAccount.values());
        return out;
    }

    @AuraEnabled
    public static SendResult sendCampaign(Id incidentId, String channel, String messageBody) {
        SendResult r = new SendResult();
        Incident inc = [SELECT Id, Subject, Affected_Customers__c, Circuit__c
                          FROM Incident WHERE Id = :incidentId LIMIT 1];

        // Reuse existing Campaign if one already exists for this Incident.
        List<ProductServiceCampaign> existing = [SELECT Id, ProductServiceCampaignName
                                                   FROM ProductServiceCampaign
                                                  WHERE Trigger_Incident__c = :incidentId LIMIT 1];

        ProductServiceCampaign psc;
        if (existing.isEmpty()) {
            Integer reach = inc.Affected_Customers__c == null ? 0 : inc.Affected_Customers__c.intValue();
            String narrative = 'Channel: ' + channel + '  |  Estimated reach: ' + reach + ' customers\n\n'
                + 'Message body:\n' + messageBody;
            psc = new ProductServiceCampaign(
                ProductServiceCampaignName = 'Cluster Notification — ' + inc.Subject,
                Trigger_Incident__c = incidentId,
                Type = 'Service',
                Status = 'New',
                Priority = 'High',
                StartDate = Date.today(),
                EndDate = Date.today().addDays(1),
                Description = narrative
            );
            insert psc;
            r.reused = false;
        } else {
            psc = existing[0];
            // Refresh the narrative with the latest channel + body the user picked
            Integer reach = inc.Affected_Customers__c == null ? 0 : inc.Affected_Customers__c.intValue();
            psc.Description = 'Channel: ' + channel + '  |  Estimated reach: ' + reach + ' customers\n\n'
                + 'Message body:\n' + messageBody;
            update psc;
            r.reused = true;
        }
        r.campaignId = psc.Id;
        r.campaignName = psc.ProductServiceCampaignName;

        // Build per-Property items for affected accounts
        Set<Id> accountIds = new Set<Id>();
        for (Case c : [SELECT AccountId FROM Case WHERE Linked_Incident__c = :incidentId AND AccountId != null]) {
            accountIds.add(c.AccountId);
        }

        Map<Id, Asset> assetsByAccount = new Map<Id, Asset>();
        for (Asset a : [SELECT Id, AccountId FROM Asset
                         WHERE AccountId IN :accountIds]) {
            assetsByAccount.put(a.AccountId, a);
        }

        Set<Id> existingAssetIds = new Set<Id>();
        for (ProductServiceCampaignItem psci : [SELECT AssetId FROM ProductServiceCampaignItem
                                                  WHERE ProductServiceCampaignId = :psc.Id]) {
            existingAssetIds.add(psci.AssetId);
        }

        List<ProductServiceCampaignItem> items = new List<ProductServiceCampaignItem>();
        for (Asset a : assetsByAccount.values()) {
            if (existingAssetIds.contains(a.Id)) continue;
            items.add(new ProductServiceCampaignItem(
                ProductServiceCampaignId = psc.Id,
                AssetId = a.Id,
                Status = 'New'
            ));
        }
        if (!items.isEmpty()) insert items;
        r.itemsCreated = items.size();
        return r;
    }
}
