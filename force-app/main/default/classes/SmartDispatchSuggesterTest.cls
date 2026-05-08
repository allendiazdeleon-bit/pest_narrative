@isTest
private class SmartDispatchSuggesterTest {

    @isTest static void testSuggestEmpty() {
        List<SmartDispatchSuggester.DispatchSuggestion> out = SmartDispatchSuggester.suggestOrderForToday();
        System.assertNotEquals(null, out);
    }

    @isTest static void testSuggestWithSA() {
        Account a = new Account(Name = 'Test Customer');
        insert a;
        WorkType wt = new WorkType(Name = 'GoGreen Quarterly Pest', EstimatedDuration = 60, DurationType = 'Minutes');
        insert wt;
        WorkOrder wo = new WorkOrder(Subject = 'Q4 GoGreen', AccountId = a.Id, WorkTypeId = wt.Id, Status = 'New');
        insert wo;
        ServiceAppointment sa = new ServiceAppointment(
            ParentRecordId = wo.Id,
            Subject = 'GoGreen visit',
            EarliestStartTime = DateTime.now().addHours(2),
            DueDate = DateTime.now().addHours(6)
        );
        insert sa;

        Test.startTest();
        List<SmartDispatchSuggester.DispatchSuggestion> out = SmartDispatchSuggester.suggestOrderForToday();
        Test.stopTest();
        System.assert(out.size() >= 1);
        System.assert(out[0].recommendedRank >= 1);
    }
}
