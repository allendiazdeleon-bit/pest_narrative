@isTest
private class CustomerNotificationServiceTest {

    @isTest static void testSendOutageAlert() {
        Incident inc = new Incident(Subject = 'Mosquito Surge — ZIP 32828', Priority = 'High',
                                     Affected_Customers__c = 47, Circuit__c = 'ZIP-32828-MOSQUITO');
        insert inc;

        Test.startTest();
        CustomerNotificationService.NotificationBatchResult r =
            CustomerNotificationService.sendOutageAlert(inc.Id, 'SMS');
        Test.stopTest();

        System.assertEquals(47, r.recipientCount);
        System.assertEquals('SMS', r.channel);
        System.assert(r.messageBody.contains('Massey Services'));
    }

    @isTest static void testSendEtrUpdate() {
        Incident inc = new Incident(Subject = 'Termite Cluster', Priority = 'Medium',
                                     Affected_Customers__c = 5);
        insert inc;
        CustomerNotificationService.NotificationBatchResult r =
            CustomerNotificationService.sendEtrUpdate(inc.Id, '4:00 PM', 'Email');
        System.assertEquals(5, r.recipientCount);
    }

    @isTest static void testSendProactiveRemediation() {
        Account a = new Account(Name = 'Customer X');
        insert a;
        CustomerNotificationService.NotificationBatchResult r =
            CustomerNotificationService.sendProactiveRemediation(a.Id, 'Pest pressure detected on your property.', 'SMS');
        System.assertEquals(1, r.recipientCount);
        System.assert(r.messageBody.contains('booster visit'));
    }
}
