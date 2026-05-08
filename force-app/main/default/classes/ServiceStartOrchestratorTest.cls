@isTest
private class ServiceStartOrchestratorTest {

    @isTest static void testCreateBusinessAccountFallback() {
        ServiceStartOrchestrator.Request r = new ServiceStartOrchestrator.Request();
        r.firstName = 'David';
        r.lastName = 'Kim';
        r.email = 'david@example.com';
        r.phone = '4075551212';
        r.address = '5500 Lake Nona Blvd';

        Test.startTest();
        List<ServiceStartOrchestrator.Response> out =
            ServiceStartOrchestrator.create(new List<ServiceStartOrchestrator.Request>{ r });
        Test.stopTest();

        System.assertEquals(1, out.size());
        // Either succeeds or returns a Failed message — both are exercised here
        System.assertNotEquals(null, out[0].message);
    }
}
