@isTest
private class AppointmentConfirmerTest {

    @isTest static void testConfirmHappyCreatesTrio() {
        Account a = new Account(Name = 'Sandra Reyes Test');
        insert a;
        WorkType wt = new WorkType(Name = 'GoGreen Quarterly Pest', EstimatedDuration = 60, DurationType = 'Minutes');
        insert wt;

        AppointmentConfirmer.Request r = new AppointmentConfirmer.Request();
        r.personAccountId = a.Id;
        r.workTypeId = wt.Id;
        r.startTime = DateTime.now().addDays(1);
        r.endTime = DateTime.now().addDays(1).addHours(2);
        r.caseContext = 'Ants in kitchen';

        Test.startTest();
        List<AppointmentConfirmer.Response> responses = AppointmentConfirmer.confirm(new List<AppointmentConfirmer.Request>{ r });
        Test.stopTest();

        System.assertEquals(1, responses.size());
        AppointmentConfirmer.Response resp = responses[0];
        System.assertNotEquals(null, resp.caseId);
        System.assertNotEquals(null, resp.workOrderId);
        System.assertNotEquals(null, resp.serviceAppointmentId);

        Case c = [SELECT Subject, Origin FROM Case WHERE Id = :resp.caseId];
        System.assert(c.Subject.contains('Ants in kitchen'));
        System.assertEquals('Agentforce', c.Origin);
    }

    @isTest static void testConfirmNoContext() {
        Account a = new Account(Name = 'David Kim Test');
        insert a;
        WorkType wt = new WorkType(Name = 'New Service Activation', EstimatedDuration = 60, DurationType = 'Minutes');
        insert wt;

        AppointmentConfirmer.Request r = new AppointmentConfirmer.Request();
        r.personAccountId = a.Id;
        r.workTypeId = wt.Id;
        r.startTime = DateTime.now().addDays(1);
        r.endTime = DateTime.now().addDays(1).addHours(2);

        List<AppointmentConfirmer.Response> responses = AppointmentConfirmer.confirm(new List<AppointmentConfirmer.Request>{ r });
        System.assert(responses[0].message.contains('Booked Case'));
    }
}
