@isTest
private class RestorationVerifierTest {

    @isTest static void testVerifyNoAsset() {
        Account a = new Account(Name = 'Empty Customer');
        insert a;
        WorkOrder wo = new WorkOrder(Subject = 'Test WO', AccountId = a.Id, Status = 'New');
        insert wo;

        Test.startTest();
        RestorationVerifier.VerificationResult res = RestorationVerifier.verify(wo.Id);
        Test.stopTest();

        System.assertEquals('Pending', res.overallStatus);
        System.assertEquals('Block Close', res.gateRecommendation);
    }

    @isTest static void testVerifyHappyClusterJob() {
        Account a = new Account(Name = 'Cluster Customer');
        insert a;
        Asset asset = new Asset(Name = 'Property A', AccountId = a.Id);
        insert asset;
        WorkType wt = new WorkType(Name = 'Mosquito Surge Area Treatment',
                                    EstimatedDuration = 120, DurationType = 'Minutes');
        insert wt;
        WorkOrder wo = new WorkOrder(Subject = 'Mosquito Surge', AccountId = a.Id,
                                     AssetId = asset.Id, WorkTypeId = wt.Id, Status = 'In Progress');
        insert wo;

        RestorationVerifier.VerificationResult res = RestorationVerifier.verify(wo.Id);
        System.assert(res.totalMeters >= 1);
        System.assertNotEquals(null, res.overallStatus);
    }

    @isTest static void testPreviewWrappersVerify() {
        Account a = new Account(Name = 'Preview Test');
        insert a;
        Asset asset = new Asset(Name = 'Property B', AccountId = a.Id);
        insert asset;
        WorkType wt = new WorkType(Name = 'GoGreen Quarterly Pest',
                                    EstimatedDuration = 60, DurationType = 'Minutes');
        insert wt;
        WorkOrder wo = new WorkOrder(Subject = 'Quarterly', AccountId = a.Id,
                                     AssetId = asset.Id, WorkTypeId = wt.Id, Status = 'In Progress');
        insert wo;

        RestorationVerifier.VerificationResult r = RestorationVerifier.preview(wo.Id);
        System.assertEquals(wo.Id, r.workOrderId);
    }

    @isTest static void testNullThrows() {
        try {
            RestorationVerifier.verify(null);
            System.assert(false, 'Should have thrown');
        } catch (AuraHandledException e) {}
    }
}
