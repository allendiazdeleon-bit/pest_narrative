@isTest
private class AppointmentCancelerTest {

    @isTest static void testCancelHappy() {
        Account a = new Account(Name = 'Test Customer');
        insert a;
        WorkOrder wo = new WorkOrder(Subject = 'Quarterly GoGreen Visit', AccountId = a.Id, Status = 'New');
        insert wo;
        ServiceAppointment sa = new ServiceAppointment(
            ParentRecordId = wo.Id,
            Subject = 'GoGreen visit',
            EarliestStartTime = DateTime.now().addDays(1),
            DueDate = DateTime.now().addDays(2)
        );
        insert sa;

        AppointmentCanceler.Request r = new AppointmentCanceler.Request();
        r.serviceAppointmentId = sa.Id;
        r.reason = 'Customer travelling';

        Test.startTest();
        List<AppointmentCanceler.Response> responses = AppointmentCanceler.cancel(new List<AppointmentCanceler.Request>{ r });
        Test.stopTest();

        System.assertEquals(1, responses.size());
        System.assertEquals(sa.Id, responses[0].recordId);
        System.assert(responses[0].message.contains('Customer travelling'));

        ServiceAppointment after = [SELECT Status FROM ServiceAppointment WHERE Id = :sa.Id];
        System.assertEquals('Canceled', after.Status);
    }

    @isTest static void testCancelNoReason() {
        Account a = new Account(Name = 'Test Customer 2');
        insert a;
        WorkOrder wo = new WorkOrder(Subject = 'Sentricon Install', AccountId = a.Id, Status = 'New');
        insert wo;
        ServiceAppointment sa = new ServiceAppointment(
            ParentRecordId = wo.Id,
            Subject = 'Sentricon',
            EarliestStartTime = DateTime.now().addDays(1),
            DueDate = DateTime.now().addDays(2)
        );
        insert sa;

        AppointmentCanceler.Request r = new AppointmentCanceler.Request();
        r.serviceAppointmentId = sa.Id;

        List<AppointmentCanceler.Response> responses = AppointmentCanceler.cancel(new List<AppointmentCanceler.Request>{ r });
        System.assert(responses[0].message.contains('not provided'));
    }
}
