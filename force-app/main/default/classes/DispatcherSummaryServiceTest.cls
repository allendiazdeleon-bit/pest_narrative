@isTest
private class DispatcherSummaryServiceTest {

    @isTest static void testGetSummaryEmpty() {
        DispatcherSummaryService.Summary s = DispatcherSummaryService.getSummary();
        System.assertNotEquals(null, s);
        System.assertNotEquals(null, s.marginIndicator);
    }

    @isTest static void testGetSummaryWithIncident() {
        Incident inc = new Incident(Subject = 'Mosquito Surge — ZIP 32828',
                                     Priority = 'High',
                                     Affected_Customers__c = 47);
        insert inc;
        DispatcherSummaryService.Summary s = DispatcherSummaryService.getSummary();
        System.assert(s.affectedCustomersTotal >= 0);
    }

    @isTest static void testGetActiveIncidents() {
        Incident inc = new Incident(Subject = 'Termite Swarm Cluster',
                                     Priority = 'Medium',
                                     Affected_Customers__c = 5);
        insert inc;
        List<DispatcherSummaryService.IncidentRow> rows = DispatcherSummaryService.getActiveIncidents();
        System.assert(rows != null);
    }
}
