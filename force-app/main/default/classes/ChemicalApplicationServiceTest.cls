/**
 * ChemicalApplicationServiceTest — covers the RUP attestation lifecycle:
 * createIsolationPoint -> markIsolated -> markVerified -> markRemoved,
 * the safety rule that the verifier must differ from the applicator,
 * the gate logic in getSummary, and the work-type suggestion picklist.
 */
@isTest
private class ChemicalApplicationServiceTest {

    @TestSetup
    static void setup() {
        Account acct = new Account(Name = 'Bennett Residence');
        insert acct;

        WorkOrder wo = new WorkOrder(
            Subject = 'Termite Liquid Treatment',
            AccountId = acct.Id,
            Street = '1247 Maple Ave',
            City = 'Orlando',
            State = 'FL',
            PostalCode = '32828'
        );
        insert wo;
    }

    private static User createSecondUser() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            FirstName = 'Second',
            LastName = 'Verifier',
            Alias = 'verfy',
            Email = 'second.verifier@masseyflow.demo.test',
            Username = 'second.verifier+' + DateTime.now().getTime() + '@masseyflow.demo.test',
            ProfileId = p.Id,
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/New_York'
        );
        insert u;
        return u;
    }

    @isTest
    static void createIsolationPoint_happyPath_createsPendingRow() {
        WorkOrder wo = [SELECT Id FROM WorkOrder LIMIT 1];

        Test.startTest();
        Id rupId = ChemicalApplicationService.createIsolationPoint(
            wo.Id,
            'Restricted-Use Pesticide',
            'Termidor SC perimeter trench',
            'RUP-T001',
            'Initial perimeter application'
        );
        Test.stopTest();

        System.assertNotEquals(null, rupId);
        LOTO_Record__c saved = [SELECT Status__c, Notes__c FROM LOTO_Record__c WHERE Id = :rupId];
        System.assertEquals('Pending', saved.Status__c);
        System.assertEquals('Initial perimeter application', saved.Notes__c);
    }

    @isTest
    static void createIsolationPoint_missingArgs_throws() {
        WorkOrder wo = [SELECT Id FROM WorkOrder LIMIT 1];
        try {
            ChemicalApplicationService.createIsolationPoint(null, 'x', 'y', 'z', null);
            System.assert(false);
        } catch (AuraHandledException e) { System.assert(true); }
        try {
            ChemicalApplicationService.createIsolationPoint(wo.Id, '', 'y', 'z', null);
            System.assert(false);
        } catch (AuraHandledException e) { System.assert(true); }
        try {
            ChemicalApplicationService.createIsolationPoint(wo.Id, 'x', '', 'z', null);
            System.assert(false);
        } catch (AuraHandledException e) { System.assert(true); }
        try {
            ChemicalApplicationService.createIsolationPoint(wo.Id, 'x', 'y', '', null);
            System.assert(false);
        } catch (AuraHandledException e) { System.assert(true); }
    }

    @isTest
    static void markIsolated_happyPath_setsAppliedFields() {
        WorkOrder wo = [SELECT Id FROM WorkOrder LIMIT 1];
        Id rupId = ChemicalApplicationService.createIsolationPoint(
            wo.Id, 'Restricted-Use Pesticide', 'Termidor SC perimeter trench', 'RUP-T001', null
        );

        Test.startTest();
        ChemicalApplicationService.markIsolated(rupId, null);
        Test.stopTest();

        LOTO_Record__c saved = [SELECT Status__c, Isolated_By__c, Isolated_At__c FROM LOTO_Record__c WHERE Id = :rupId];
        System.assertEquals('Isolated', saved.Status__c);
        System.assertEquals(UserInfo.getUserId(), saved.Isolated_By__c);
        System.assertNotEquals(null, saved.Isolated_At__c);
    }

    @isTest
    static void markVerified_byDifferentUser_succeeds() {
        WorkOrder wo = [SELECT Id FROM WorkOrder LIMIT 1];
        User secondUser = createSecondUser();

        Id rupId;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            rupId = ChemicalApplicationService.createIsolationPoint(
                wo.Id, 'Restricted-Use Pesticide', 'Termidor SC perimeter trench', 'RUP-T001', null
            );
            ChemicalApplicationService.markIsolated(rupId, null);
        }

        Test.startTest();
        System.runAs(secondUser) {
            ChemicalApplicationService.markVerified(rupId);
        }
        Test.stopTest();

        LOTO_Record__c saved = [SELECT Status__c, Verified_By__c FROM LOTO_Record__c WHERE Id = :rupId];
        System.assertEquals('Verified', saved.Status__c);
        System.assertEquals(secondUser.Id, saved.Verified_By__c);
    }

    @isTest
    static void markVerified_bySameUser_throwsSafetyViolation() {
        WorkOrder wo = [SELECT Id FROM WorkOrder LIMIT 1];

        Id rupId = ChemicalApplicationService.createIsolationPoint(
            wo.Id, 'Restricted-Use Pesticide', 'Termidor SC perimeter trench', 'RUP-T001', null
        );
        ChemicalApplicationService.markIsolated(rupId, null);

        try {
            ChemicalApplicationService.markVerified(rupId);
            System.assert(false, 'Expected safety violation');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @isTest
    static void markRemoved_happyPath_setsRemovedFields() {
        WorkOrder wo = [SELECT Id FROM WorkOrder LIMIT 1];
        Id rupId = ChemicalApplicationService.createIsolationPoint(
            wo.Id, 'Restricted-Use Pesticide', 'Termidor SC perimeter trench', 'RUP-T001', null
        );

        ChemicalApplicationService.markRemoved(rupId);

        LOTO_Record__c saved = [SELECT Status__c, Removed_By__c FROM LOTO_Record__c WHERE Id = :rupId];
        System.assertEquals('Removed', saved.Status__c);
        System.assertEquals(UserInfo.getUserId(), saved.Removed_By__c);
    }

    @isTest
    static void getSummary_emptyWorkOrder_returnsEmptySummary() {
        WorkOrder wo = [SELECT Id FROM WorkOrder LIMIT 1];

        ChemicalApplicationService.LotoSummary s = ChemicalApplicationService.getSummary(wo.Id);

        System.assertEquals(0, s.totalPoints);
        System.assertEquals(false, s.canStartWork);
        System.assertEquals(false, s.allVerified);
    }

    @isTest
    static void getSummary_allVerified_unlocksGate() {
        WorkOrder wo = [SELECT Id FROM WorkOrder LIMIT 1];
        User secondUser = createSecondUser();

        Id rupId = ChemicalApplicationService.createIsolationPoint(
            wo.Id, 'Restricted-Use Pesticide', 'Termidor SC perimeter trench', 'RUP-T001', null
        );
        ChemicalApplicationService.markIsolated(rupId, null);
        // Populate chemical fields directly (createIsolationPoint doesn't take them).
        LOTO_Record__c rec = [SELECT Id FROM LOTO_Record__c WHERE Id = :rupId];
        rec.Chemical_Name__c = 'Termidor SC';
        rec.Dose_Amount__c = 0.06;
        rec.EPA_Reg_Number__c = '432-1404';
        update rec;

        System.runAs(secondUser) {
            ChemicalApplicationService.markVerified(rupId);
        }

        ChemicalApplicationService.LotoSummary s = ChemicalApplicationService.getSummary(wo.Id);

        System.assertEquals(1, s.totalPoints);
        System.assertEquals(1, s.verifiedCount);
        System.assertEquals(true, s.allVerified);
        System.assertEquals(true, s.canStartWork);
        System.assertEquals('Termidor SC', s.records[0].chemicalName);
        System.assertEquals('432-1404', s.records[0].epaRegNumber);
    }

    @isTest
    static void getSummary_nullId_throws() {
        try {
            ChemicalApplicationService.getSummary(null);
            System.assert(false);
        } catch (AuraHandledException e) { System.assert(true); }
    }

    @isTest
    static void suggestIsolationPointsForWorkType_nullWorkType_returnsDefault() {
        WorkOrder wo = [SELECT Id FROM WorkOrder LIMIT 1];
        List<Map<String, String>> sug = ChemicalApplicationService.suggestIsolationPointsForWorkType(wo.Id);
        // The seeded WO has no WorkType — falls into the default "Other" branch
        System.assertEquals(1, sug.size());
        System.assertEquals('Other', sug[0].get('energySource'));
    }

    @isTest
    static void suggestIsolationPointsForWorkType_nullId_returnsEmpty() {
        List<Map<String, String>> sug = ChemicalApplicationService.suggestIsolationPointsForWorkType(null);
        System.assertEquals(0, sug.size());
    }

    @isTest
    static void mutationGuards_unknownIds_throw() {
        Id fake = '0WO000000000000AAA';
        try {
            ChemicalApplicationService.markIsolated(null, null);
            System.assert(false);
        } catch (AuraHandledException e) { System.assert(true); }
        try {
            ChemicalApplicationService.markVerified(null);
            System.assert(false);
        } catch (AuraHandledException e) { System.assert(true); }
        try {
            ChemicalApplicationService.markRemoved(null);
            System.assert(false);
        } catch (AuraHandledException e) { System.assert(true); }
    }
}
