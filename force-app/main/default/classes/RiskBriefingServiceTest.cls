@isTest
private class RiskBriefingServiceTest {

    @isTest static void testBriefHappy() {
        Account a = new Account(Name = 'Test Customer');
        insert a;
        Asset asset = new Asset(Name = 'Property A', AccountId = a.Id);
        insert asset;
        WorkType wt = new WorkType(Name = 'GoGreen Quarterly Pest',
                                    EstimatedDuration = 60, DurationType = 'Minutes');
        insert wt;
        WorkOrder wo = new WorkOrder(Subject = 'Q1 GoGreen', AccountId = a.Id, AssetId = asset.Id,
                                     WorkTypeId = wt.Id, Status = 'New');
        insert wo;

        Test.startTest();
        RiskBriefingService.RiskBriefing rb = RiskBriefingService.briefForWorkOrder(wo.Id);
        Test.stopTest();

        System.assertEquals('Low', rb.weatherRisk);
        System.assertNotEquals(null, rb.summary);
    }

    @isTest static void testBriefNullThrows() {
        try {
            RiskBriefingService.briefForWorkOrder(null);
            System.assert(false);
        } catch (AuraHandledException e) {}
    }

    @isTest static void testBriefMissingThrows() {
        try {
            RiskBriefingService.briefForWorkOrder('08q000000000001AAA');
            System.assert(false);
        } catch (AuraHandledException e) {}
    }
}
