@isTest
private class AppointmentReschedulerTest {

    @isTest static void testReschedule() {
        Account a = new Account(Name = 'Reschedule Test Customer');
        insert a;
        WorkOrder wo = new WorkOrder(Subject = 'Quarterly GoGreen', AccountId = a.Id, Status = 'New');
        insert wo;
        ServiceAppointment sa = new ServiceAppointment(
            ParentRecordId = wo.Id,
            Subject = 'GoGreen visit',
            EarliestStartTime = DateTime.now().addDays(1),
            DueDate = DateTime.now().addDays(2)
        );
        insert sa;

        AppointmentRescheduler.Request r = new AppointmentRescheduler.Request();
        r.serviceAppointmentId = sa.Id;
        r.newStartTime = DateTime.now().addDays(5);
        r.newEndTime = DateTime.now().addDays(5).addHours(2);

        Test.startTest();
        List<AppointmentRescheduler.Response> responses = AppointmentRescheduler.reschedule(new List<AppointmentRescheduler.Request>{ r });
        Test.stopTest();

        System.assertEquals(1, responses.size());
        System.assertEquals(sa.Id, responses[0].recordId);
        System.assert(responses[0].message.contains('Rescheduled'));

        ServiceAppointment after = [SELECT EarliestStartTime FROM ServiceAppointment WHERE Id = :sa.Id];
        System.assertEquals(r.newStartTime, after.EarliestStartTime);
    }
}
