@isTest
private class NextBestActionServiceTest {

    @isTest static void testSuggestForSafetyStep() {
        Account a = new Account(Name = 'Test Customer');
        insert a;
        WorkType wt = new WorkType(Name = 'GoGreen Quarterly Pest', EstimatedDuration = 60, DurationType = 'Minutes');
        insert wt;
        WorkOrder wo = new WorkOrder(Subject = 'Test', AccountId = a.Id, WorkTypeId = wt.Id, Status = 'New');
        insert wo;

        Test.startTest();
        List<NextBestActionService.NextBestAction> out =
            NextBestActionService.suggestForStep(wo.Id, 'Work_Safety');
        Test.stopTest();
        System.assert(!out.isEmpty());
        System.assert(out.size() <= 3);
    }

    @isTest static void testSuggestForMosquitoSurge() {
        Account a = new Account(Name = 'Mosq Customer');
        insert a;
        WorkType wt = new WorkType(Name = 'Mosquito Surge Area Treatment',
                                    EstimatedDuration = 120, DurationType = 'Minutes');
        insert wt;
        WorkOrder wo = new WorkOrder(Subject = 'Mosquito Surge', AccountId = a.Id,
                                     WorkTypeId = wt.Id, Status = 'In Progress');
        insert wo;

        List<NextBestActionService.NextBestAction> out =
            NextBestActionService.suggestForStep(wo.Id, 'Work_Execute');
        System.assert(!out.isEmpty());
    }

    @isTest static void testSuggestNullArgs() {
        List<NextBestActionService.NextBestAction> out =
            NextBestActionService.suggestForStep(null, null);
        System.assertEquals(0, out.size());
    }
}
