/**
 * BaitStationReadingServiceTest — covers getReadings,
 * getReadingsForRestoration, and getBaitStationState plus null/edge
 * cases.
 */
@isTest
private class BaitStationReadingServiceTest {

    @TestSetup
    static void setup() {
        Account acct = new Account(
            Name = 'Bennett Residence',
            BillingStreet = '1247 Maple Ave',
            BillingCity = 'Orlando',
            BillingState = 'FL',
            BillingPostalCode = '32828'
        );
        insert acct;

        Asset a = new Asset(
            Name = 'Bennett Property — Termite',
            AccountId = acct.Id,
            Service_Line__c = 'Termite',
            Equipment_Type__c = 'Sentricon_Station',
            Bait_Station_State__c = 'Activity',
            Bait_Station_Hits_30d__c = 4,
            Last_Bait_Station_Hit_Date__c = Date.today().addDays(-3),
            Pest_Pressure_Score__c = 65,
            Last_Treatment_DateTime__c = DateTime.now().addDays(-2),
            Is_Pest_Pressure_Candidate__c = true
        );
        insert a;

        WorkOrder wo = new WorkOrder(
            Subject = 'Termite Liquid Treatment (Termidor)',
            AccountId = acct.Id,
            AssetId = a.Id,
            Street = '1247 Maple Ave',
            City = 'Orlando',
            State = 'FL',
            PostalCode = '32828'
        );
        insert wo;
    }

    @isTest
    static void getReadings_happyPath_returnsSeries() {
        Asset a = [SELECT Id FROM Asset LIMIT 1];

        Test.startTest();
        BaitStationReadingService.ReadingSeries s = BaitStationReadingService.getReadings(a.Id, 12);
        Test.stopTest();

        System.assertNotEquals(null, s);
        System.assertEquals(a.Id, s.assetId);
        System.assertEquals('score', s.unit);
        System.assertEquals(12, s.readings.size());
        System.assertNotEquals(null, s.currentValue);
        System.assertNotEquals(null, s.summary);
    }

    @isTest
    static void getReadings_nullHoursBack_usesDefault() {
        Asset a = [SELECT Id FROM Asset LIMIT 1];

        BaitStationReadingService.ReadingSeries s = BaitStationReadingService.getReadings(a.Id, null);

        System.assertEquals(12, s.readings.size(), 'Default of 12 daily samples expected');
    }

    @isTest
    static void getReadings_nullAsset_throws() {
        try {
            BaitStationReadingService.getReadings(null, 12);
            System.assert(false);
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @isTest
    static void getReadings_unknownAsset_throws() {
        Id fake = '02i000000000000AAA';
        try {
            BaitStationReadingService.getReadings(fake, 12);
            System.assert(false);
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @isTest
    static void getReadingsForRestoration_workOrderWithAsset_returnsSeries() {
        WorkOrder wo = [SELECT Id FROM WorkOrder LIMIT 1];

        Test.startTest();
        List<BaitStationReadingService.ReadingSeries> series = BaitStationReadingService.getReadingsForRestoration(wo.Id);
        Test.stopTest();

        System.assertEquals(1, series.size());
        System.assert(series[0].readings.size() > 0, 'Series should have readings');
        // No work type set on the WO, so trend should compute (not "restored")
        System.assertNotEquals('restored', series[0].trendDirection);
    }

    @isTest
    static void getReadingsForRestoration_unknownWorkOrder_throws() {
        Id fake = '0WO000000000000AAA';
        try {
            BaitStationReadingService.getReadingsForRestoration(fake);
            System.assert(false);
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @isTest
    static void getReadingsForRestoration_nullId_throws() {
        try {
            BaitStationReadingService.getReadingsForRestoration(null);
            System.assert(false);
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @isTest
    static void getReadingsForRestoration_workOrderWithoutAsset_returnsEmpty() {
        Account a = [SELECT Id FROM Account LIMIT 1];
        WorkOrder bare = new WorkOrder(Subject = 'Bare WO', AccountId = a.Id);
        insert bare;

        List<BaitStationReadingService.ReadingSeries> series = BaitStationReadingService.getReadingsForRestoration(bare.Id);

        System.assertEquals(0, series.size());
    }

    @isTest
    static void getBaitStationState_returnsSortedAssets() {
        Account a = [SELECT Id FROM Account LIMIT 1];

        List<Asset> rows = BaitStationReadingService.getBaitStationState(a.Id);

        System.assertEquals(1, rows.size());
        System.assertEquals('Activity', rows[0].Bait_Station_State__c);
        System.assertEquals(4, rows[0].Bait_Station_Hits_30d__c);
    }

    @isTest
    static void getBaitStationState_nullAccount_throws() {
        try {
            BaitStationReadingService.getBaitStationState(null);
            System.assert(false);
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }
}
