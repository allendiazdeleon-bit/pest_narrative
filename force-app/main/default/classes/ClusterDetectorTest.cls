@isTest
private class ClusterDetectorTest {

    @isTest static void testDetectMosquitoCluster() {
        Account a1 = new Account(Name = 'Mosquito Customer 1');
        Account a2 = new Account(Name = 'Mosquito Customer 2');
        insert new List<Account>{ a1, a2 };

        Case source = new Case(AccountId = a1.Id, Subject = 'Mosquitoes at 1407 Avalon Park Blvd', Status = 'New');
        Case sib = new Case(AccountId = a2.Id, Subject = 'Mosquitoes at 1431 Avalon Park Blvd', Status = 'New');
        insert new List<Case>{ source, sib };

        Test.startTest();
        ClusterDetector.Result r = ClusterDetector.detectFromCase(source.Id);
        Test.stopTest();

        System.assertNotEquals(null, r.incidentId);
        System.assert(r.incidentSubject.contains('Mosquito'));
        System.assertEquals(2, r.linkedCaseCount);

        Case after = [SELECT Linked_Incident__c, Status FROM Case WHERE Id = :source.Id];
        System.assertEquals(r.incidentId, after.Linked_Incident__c);
    }

    @isTest static void testIdempotency() {
        Account a = new Account(Name = 'Already Linked');
        insert a;
        Incident existing = new Incident(Subject = 'Existing Mosquito Surge', Priority = 'High');
        insert existing;
        Case c = new Case(AccountId = a.Id, Subject = 'Mosquitoes at 1455 Avalon Park Blvd',
                          Linked_Incident__c = existing.Id, Status = 'Working');
        insert c;

        ClusterDetector.Result r = ClusterDetector.detectFromCase(c.Id);
        System.assertEquals(existing.Id, r.incidentId);
        System.assert(r.message.contains('already linked'));
    }

    @isTest static void testPreviewSiblings() {
        Account a1 = new Account(Name = 'Source Customer');
        Account a2 = new Account(Name = 'Sibling Customer');
        insert new List<Account>{ a1, a2 };
        Case source = new Case(AccountId = a1.Id, Subject = 'Mosquitoes at 1500 Maple St', Status = 'New');
        Case sib = new Case(AccountId = a2.Id, Subject = 'Mosquitoes at 1502 Maple St', Status = 'New');
        insert new List<Case>{ source, sib };

        List<Map<String, String>> preview = ClusterDetector.previewSiblings(source.Id);
        System.assert(!preview.isEmpty());
    }

    @isTest static void testTermitePattern() {
        Account a1 = new Account(Name = 'Termite Customer 1');
        insert a1;
        Case source = new Case(AccountId = a1.Id, Subject = 'Termite swarmers at 1600 Oak Ln', Status = 'New');
        insert source;

        ClusterDetector.Result r = ClusterDetector.detectFromCase(source.Id);
        System.assert(r.incidentSubject.contains('Termite'));
    }
}
