@isTest
private class RemoteRemediationServiceTest {

    @isTest static void testNullAsset() {
        RemoteRemediationService.RemediationResponse r = RemoteRemediationService.triggerMosquitoFogCycle(null);
        System.assertEquals('EscalateToTruck', r.outcome);
    }

    @isTest static void testTriggerFogCycleHappy() {
        Account a = new Account(Name = 'Mosquito Customer');
        insert a;
        Asset asset = new Asset(Name = 'Mosquito Hunter System', AccountId = a.Id);
        insert asset;

        Test.startTest();
        RemoteRemediationService.RemediationResponse r = RemoteRemediationService.triggerMosquitoFogCycle(asset.Id);
        Test.stopTest();

        System.assertNotEquals(null, r.outcome);
        System.assertNotEquals(null, r.summary);
    }

    @isTest static void testCheckTankLevel() {
        Account a = new Account(Name = 'Mosquito Customer 2');
        insert a;
        Asset asset = new Asset(Name = 'Mosquito Hunter System 2', AccountId = a.Id);
        insert asset;

        RemoteRemediationService.RemediationResponse r = RemoteRemediationService.checkTankLevel(asset.Id);
        System.assertNotEquals(null, r.outcome);
    }

    @isTest static void testAttemptRemoteRemediationNoAsset() {
        RemoteRemediationService.RemediationRequest req = new RemoteRemediationService.RemediationRequest();
        req.assetId = '02i000000000001AAA';
        List<RemoteRemediationService.RemediationResponse> out =
            RemoteRemediationService.attemptRemoteRemediation(new List<RemoteRemediationService.RemediationRequest>{ req });
        System.assertEquals(1, out.size());
        System.assertEquals('EscalateToTruck', out[0].outcome);
    }

    @isTest static void testAttemptRemoteRemediationNonMosquito() {
        Account a = new Account(Name = 'GoGreen Customer');
        insert a;
        Asset asset = new Asset(Name = 'Property A', AccountId = a.Id, Service_Line__c = 'GoGreen Pest Prevention');
        insert asset;

        RemoteRemediationService.RemediationRequest req = new RemoteRemediationService.RemediationRequest();
        req.assetId = asset.Id;
        List<RemoteRemediationService.RemediationResponse> out =
            RemoteRemediationService.attemptRemoteRemediation(new List<RemoteRemediationService.RemediationRequest>{ req });
        System.assertEquals('EscalateToTruck', out[0].outcome);
    }
}
