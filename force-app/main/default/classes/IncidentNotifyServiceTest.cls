@isTest
private class IncidentNotifyServiceTest {

    private static Incident makeIncidentWithCases(Integer numCases) {
        Incident inc = new Incident(Subject = 'Mosquito Surge — ZIP 32828', Priority = 'High',
                                     Affected_Customers__c = numCases);
        insert inc;
        List<Account> accts = new List<Account>();
        for (Integer i = 0; i < numCases; i++) accts.add(new Account(Name = 'Cust ' + i));
        insert accts;
        List<Asset> assets = new List<Asset>();
        for (Integer i = 0; i < numCases; i++) assets.add(new Asset(Name = 'Property ' + i, AccountId = accts[i].Id));
        insert assets;
        List<Case> cases = new List<Case>();
        for (Integer i = 0; i < numCases; i++) {
            cases.add(new Case(AccountId = accts[i].Id, AssetId = assets[i].Id,
                               Subject = 'Mosquitoes at ' + (1500 + i) + ' Maple St',
                               Linked_Incident__c = inc.Id, Status = 'New'));
        }
        insert cases;
        return inc;
    }

    @isTest static void testPreviewAudience() {
        Incident inc = makeIncidentWithCases(2);
        List<IncidentNotifyService.AffectedCustomer> out = IncidentNotifyService.previewAudience(inc.Id);
        System.assertEquals(2, out.size());
    }

    @isTest static void testSendCampaignCreates() {
        Incident inc = makeIncidentWithCases(2);
        Test.startTest();
        IncidentNotifyService.SendResult r = IncidentNotifyService.sendCampaign(inc.Id, 'SMS',
            'Massey Services: We treated the mosquito breeding source in your area.');
        Test.stopTest();
        System.assertNotEquals(null, r.campaignId);
        System.assertEquals(false, r.reused);
        System.assertEquals(2, r.itemsCreated);
    }

    @isTest static void testSendCampaignReuses() {
        Incident inc = makeIncidentWithCases(1);
        IncidentNotifyService.sendCampaign(inc.Id, 'SMS', 'First message');
        IncidentNotifyService.SendResult r = IncidentNotifyService.sendCampaign(inc.Id, 'Email', 'Updated message');
        System.assertEquals(true, r.reused);
    }
}
