@isTest
private class WOCompletionRollupHelperTest {

    @isTest static void testProcessNoParents() {
        Account a = new Account(Name = 'Roll Up Customer');
        insert a;
        WorkOrder child = new WorkOrder(Subject = 'Child WO', AccountId = a.Id, Status = 'Completed');
        insert child;

        WOCompletionRollupHelper.Request r = new WOCompletionRollupHelper.Request();
        r.workOrderId = child.Id;

        Test.startTest();
        WOCompletionRollupHelper.process(new List<WOCompletionRollupHelper.Request>{ r });
        Test.stopTest();
        // No parent — nothing to verify other than no exception
        System.assert(true);
    }

    @isTest static void testProcessWithParent() {
        Account a = new Account(Name = 'Roll Up Customer 2');
        insert a;
        WorkOrder parent = new WorkOrder(Subject = 'Parent WO', AccountId = a.Id, Status = 'In Progress',
                                          Children_Total__c = 1, Children_Completed__c = 0);
        insert parent;
        WorkOrder child = new WorkOrder(Subject = 'Child', AccountId = a.Id,
                                         ParentWorkOrderId = parent.Id, Status = 'Completed');
        insert child;

        WOCompletionRollupHelper.Request r = new WOCompletionRollupHelper.Request();
        r.workOrderId = child.Id;
        WOCompletionRollupHelper.process(new List<WOCompletionRollupHelper.Request>{ r });

        WorkOrder after = [SELECT Status, Children_Completed__c FROM WorkOrder WHERE Id = :parent.Id];
        System.assertEquals(1, after.Children_Completed__c);
        System.assertEquals('Completed', after.Status);
    }
}
