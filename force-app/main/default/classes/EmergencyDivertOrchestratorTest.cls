@isTest
private class EmergencyDivertOrchestratorTest {

    @isTest static void testDivertNoAssignments() {
        // Create a ServiceResource
        ServiceResource sr = new ServiceResource(Name = 'Tom Walker (test)',
                                                 RelatedRecordId = UserInfo.getUserId(),
                                                 ResourceType = 'T',
                                                 IsActive = true);
        insert sr;

        Incident inc = new Incident(Subject = 'Mosquito Surge — ZIP 32828', Priority = 'High');
        insert inc;

        EmergencyDivertOrchestrator.Request r = new EmergencyDivertOrchestrator.Request();
        r.serviceResourceId = sr.Id;
        r.incidentId = inc.Id;
        r.deferReason = 'Cluster response';

        Test.startTest();
        List<EmergencyDivertOrchestrator.Response> responses =
            EmergencyDivertOrchestrator.divert(new List<EmergencyDivertOrchestrator.Request>{ r });
        Test.stopTest();

        System.assertEquals(1, responses.size());
        System.assertEquals(0, responses[0].assignmentsCleared);
        System.assertNotEquals(null, responses[0].message);
    }

    @isTest static void testGetCandidates() {
        ServiceResource sr = new ServiceResource(Name = 'Maria Lopez (test)',
                                                 RelatedRecordId = UserInfo.getUserId(),
                                                 ResourceType = 'T',
                                                 IsActive = true);
        insert sr;
        Incident inc = new Incident(Subject = 'Test Incident', Priority = 'Medium');
        insert inc;

        EmergencyDivertOrchestrator.Candidates c = EmergencyDivertOrchestrator.getDivertCandidates();
        System.assertNotEquals(null, c.serviceResources);
        System.assertNotEquals(null, c.incidents);
    }

    @isTest static void testDivertFromLwc() {
        ServiceResource sr = new ServiceResource(Name = 'LWC Tech',
                                                 RelatedRecordId = UserInfo.getUserId(),
                                                 ResourceType = 'T',
                                                 IsActive = true);
        insert sr;
        Incident inc = new Incident(Subject = 'LWC Cluster', Priority = 'High');
        insert inc;

        EmergencyDivertOrchestrator.Request r = new EmergencyDivertOrchestrator.Request();
        r.serviceResourceId = sr.Id;
        r.incidentId = inc.Id;

        List<EmergencyDivertOrchestrator.Response> resp =
            EmergencyDivertOrchestrator.divertFromLwc(new List<EmergencyDivertOrchestrator.Request>{ r });
        System.assertEquals(1, resp.size());
    }
}
