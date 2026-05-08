@isTest
private class ImpactPreviewServiceTest {

    @isTest static void testPreviewForWorkOrder() {
        Account a = new Account(Name = 'Anchor', AccountNumber = 'MASSEY-1010');
        insert a;
        for (Integer i = 0; i < 4; i++) {
            insert new Account(Name = 'Neighbor ' + i, AccountNumber = 'MASSEY-' + (1011 + i));
        }
        WorkOrder wo = new WorkOrder(Subject = 'Test', AccountId = a.Id, Status = 'New');
        insert wo;

        Test.startTest();
        ImpactPreviewService.ImpactSummary s =
            ImpactPreviewService.previewForWorkOrder(wo.Id, 'Restricted-Use Pesticide Application');
        Test.stopTest();
        System.assertEquals('Restricted-Use Pesticide Application', s.action);
        System.assert(s.affectedCount >= 0);
    }

    @isTest static void testPreviewForIncident() {
        Account a = new Account(Name = 'Anchor', AccountNumber = 'MASSEY-2020');
        insert a;
        Incident inc = new Incident(Subject = 'Cluster', Priority = 'High');
        insert inc;
        Case c = new Case(AccountId = a.Id, Subject = 'Mosquitoes at 1', Linked_Incident__c = inc.Id, Status = 'New');
        insert c;

        ImpactPreviewService.ImpactSummary s = ImpactPreviewService.previewForIncident(inc.Id, 'Perimeter ULV Fog');
        System.assert(s.affectedCount >= 1);
    }

    @isTest static void testGenerateNotification() {
        Account a = new Account(Name = 'Anchor', AccountNumber = 'MASSEY-3030');
        insert a;
        WorkOrder wo = new WorkOrder(Subject = 'Test', AccountId = a.Id, Status = 'New');
        insert wo;

        Id pscId = ImpactPreviewService.generateNotification(wo.Id, 'Tent Fumigation');
        System.assertNotEquals(null, pscId);
    }

    @isTest static void testNullThrows() {
        try {
            ImpactPreviewService.previewForWorkOrder(null, 'X');
            System.assert(false);
        } catch (AuraHandledException e) {}
    }
}
