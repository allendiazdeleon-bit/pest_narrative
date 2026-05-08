@isTest
private class DemoDataLoaderTest {

    @isTest static void testLoadAndReset() {
        Test.startTest();
        String loadResult = DemoDataLoader.load();
        Test.stopTest();
        System.assertNotEquals(null, loadResult);

        String resetResult = DemoDataLoader.reset();
        System.assert(resetResult.contains('Deleted'));
    }

    @isTest static void testLoadVariantDelegates() {
        String r = DemoDataLoader.loadVariant('Pest');
        System.assertNotEquals(null, r);
    }

    @isTest static void testActivateMockIncidentEmpty() {
        String r = DemoDataLoader.activateMockIncident();
        System.assert(r.contains('Activated'));
    }

    @isTest static void testGetClusterCalls() {
        List<Map<String, String>> calls = DemoDataLoader.getClusterCalls();
        System.assertNotEquals(null, calls);
    }

    @isTest static void testSetDemoTime() {
        String r = DemoDataLoader.setDemoTime(7);
        System.assertNotEquals(null, r);
    }

    @isTest static void testCreatePlanAndStepsForWo() {
        Account a = new Account(Name = 'Plan Test');
        insert a;
        WorkOrder wo = new WorkOrder(Subject = 'Test WO', AccountId = a.Id, Status = 'New');
        insert wo;
        Id planId = DemoDataLoader.createPlanAndStepsForWo(wo.Id);
        System.assertNotEquals(null, planId);

        // Idempotent
        Id planId2 = DemoDataLoader.createPlanAndStepsForWo(wo.Id);
        System.assertEquals(planId, planId2);

        // Null-safe
        System.assertEquals(null, DemoDataLoader.createPlanAndStepsForWo(null));
    }
}
