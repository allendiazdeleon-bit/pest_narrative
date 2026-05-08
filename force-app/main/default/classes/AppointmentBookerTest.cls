@isTest
private class AppointmentBookerTest {

    @isTest static void testMorningWindow() {
        AppointmentBooker.Request r = new AppointmentBooker.Request();
        r.personAccountId = '001000000000001AAA';
        r.workTypeId = '08q000000000001AAA';
        r.preferenceWindow = 'morning';

        Test.startTest();
        List<AppointmentBooker.Response> responses = AppointmentBooker.book(new List<AppointmentBooker.Request>{ r });
        Test.stopTest();

        System.assertEquals(1, responses.size());
        System.assertEquals(3, responses[0].slots.size());
        for (AppointmentBooker.Slot s : responses[0].slots) {
            System.assertEquals('morning', s.windowLabel);
            System.assertEquals(8, s.startTime.hour());
        }
        System.assert(responses[0].message.contains('morning'));
    }

    @isTest static void testAfternoonWindow() {
        AppointmentBooker.Request r = new AppointmentBooker.Request();
        r.personAccountId = '001000000000002AAA';
        r.workTypeId = '08q000000000002AAA';
        r.preferenceWindow = 'afternoon';

        List<AppointmentBooker.Response> responses = AppointmentBooker.book(new List<AppointmentBooker.Request>{ r });
        System.assertEquals(13, responses[0].slots[0].startTime.hour());
    }

    @isTest static void testAsapDefaults() {
        AppointmentBooker.Request r = new AppointmentBooker.Request();
        r.personAccountId = '001000000000003AAA';
        r.workTypeId = '08q000000000003AAA';
        // No preference

        List<AppointmentBooker.Response> responses = AppointmentBooker.book(new List<AppointmentBooker.Request>{ r });
        System.assertEquals(3, responses[0].slots.size());
        System.assertEquals('asap', responses[0].slots[0].windowLabel);
    }
}
