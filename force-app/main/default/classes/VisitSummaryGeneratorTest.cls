@isTest
private class VisitSummaryGeneratorTest {

    @isTest static void testGenerateGoGreen() {
        Account a = new Account(Name = 'Test Customer');
        insert a;
        Asset asset = new Asset(Name = '1407 Avalon Park Blvd', AccountId = a.Id,
                                Service_Line__c = 'GoGreen Pest Prevention');
        insert asset;
        WorkType wt = new WorkType(Name = 'GoGreen Quarterly Pest',
                                    EstimatedDuration = 60, DurationType = 'Minutes');
        insert wt;
        WorkOrder wo = new WorkOrder(Subject = 'Q1 GoGreen', AccountId = a.Id, AssetId = asset.Id,
                                     WorkTypeId = wt.Id, Status = 'Completed',
                                     StartDate = DateTime.now());
        insert wo;

        VisitSummaryGenerator.Request r = new VisitSummaryGenerator.Request();
        r.workOrderId = wo.Id;

        Test.startTest();
        List<VisitSummaryGenerator.Response> out =
            VisitSummaryGenerator.generate(new List<VisitSummaryGenerator.Request>{ r });
        Test.stopTest();

        System.assertEquals(1, out.size());
        System.assert(out[0].summary.contains('Massey Services'));
    }

    @isTest static void testGenerateMosquito() {
        Account a = new Account(Name = 'Mosq Customer');
        insert a;
        Asset asset = new Asset(Name = '500 Lake Nona Blvd', AccountId = a.Id,
                                Service_Line__c = 'Mosquito Hunter');
        insert asset;
        WorkType wt = new WorkType(Name = 'Mosquito Surge Area Treatment',
                                    EstimatedDuration = 120, DurationType = 'Minutes');
        insert wt;
        WorkOrder wo = new WorkOrder(Subject = 'Mosquito', AccountId = a.Id, AssetId = asset.Id,
                                     WorkTypeId = wt.Id, Status = 'Completed',
                                     StartDate = DateTime.now());
        insert wo;

        VisitSummaryGenerator.Request r = new VisitSummaryGenerator.Request();
        r.workOrderId = wo.Id;
        List<VisitSummaryGenerator.Response> out =
            VisitSummaryGenerator.generate(new List<VisitSummaryGenerator.Request>{ r });
        System.assert(out[0].summary.containsIgnoreCase('mosquito') || out[0].summary.containsIgnoreCase('larvicide'));
    }

    @isTest static void testGenerateMissingWO() {
        VisitSummaryGenerator.Request r = new VisitSummaryGenerator.Request();
        r.workOrderId = '08q000000000001AAA'; // bogus id
        List<VisitSummaryGenerator.Response> out =
            VisitSummaryGenerator.generate(new List<VisitSummaryGenerator.Request>{ r });
        System.assert(out[0].summary.contains('Work Order not found'));
    }
}
