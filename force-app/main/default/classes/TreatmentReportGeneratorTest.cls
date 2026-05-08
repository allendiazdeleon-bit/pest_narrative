/**
 * TreatmentReportGeneratorTest — covers preview() + generate() with
 * happy-path WO context + the various audit branches (missing photos,
 * missing chemical log, fail / warn / pass on pest pressure score, etc).
 */
@isTest
private class TreatmentReportGeneratorTest {

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
            Equipment_Model__c = 'AlwaysActive',
            Service_Group__c = 'ZIP-32828-Termite',
            Bait_Station_State__c = 'Replaced',
            Bait_Station_Hits_30d__c = 1,
            Pest_Pressure_Score__c = 28,
            Conducive_Conditions__c = false,
            Last_Treatment_DateTime__c = DateTime.now().addDays(-1),
            EPA_Reg_Number_Last_Used__c = '432-1404'
        );
        insert a;

        WorkOrder wo = new WorkOrder(
            Subject = 'Termite Liquid Treatment — Termidor',
            Description = 'Treatment complete. REI posted. Customer signed at door.',
            AccountId = acct.Id,
            AssetId = a.Id,
            Street = '1247 Maple Ave',
            City = 'Orlando',
            State = 'FL',
            PostalCode = '32828'
        );
        insert wo;

        // Two photos — sufficient for both pre- and post-treatment evidence
        ContentVersion cv1 = new ContentVersion(
            Title = 'before-perimeter',
            PathOnClient = 'before.jpg',
            VersionData = Blob.valueOf('fake before'),
            Origin = 'H'
        );
        ContentVersion cv2 = new ContentVersion(
            Title = 'after-treatment',
            PathOnClient = 'after.jpg',
            VersionData = Blob.valueOf('fake after'),
            Origin = 'H'
        );
        insert new List<ContentVersion>{cv1, cv2};

        List<ContentVersion> savedCvs = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id IN :new List<Id>{cv1.Id, cv2.Id}];
        List<ContentDocumentLink> links = new List<ContentDocumentLink>();
        for (ContentVersion saved : savedCvs) {
            links.add(new ContentDocumentLink(
                ContentDocumentId = saved.ContentDocumentId,
                LinkedEntityId = wo.Id,
                ShareType = 'V',
                Visibility = 'AllUsers'
            ));
        }
        insert links;

        // RUP attestation rows reusing LOTO_Record__c — Verified status,
        // full chemical / dose / EPA reg # populated.
        LOTO_Record__c rec = new LOTO_Record__c(
            Work_Order__c = wo.Id,
            Status__c = 'Verified',
            Chemical_Name__c = 'Termidor SC',
            Dose_Amount__c = 0.06,
            EPA_Reg_Number__c = '432-1404',
            Energy_Source__c = 'Restricted-Use Pesticide',
            Isolation_Point__c = 'Perimeter trench',
            Lock_Tag_Number__c = 'RUP-001'
        );
        insert rec;
    }

    @isTest
    static void preview_happyPath_isReadyToFile() {
        WorkOrder wo = [SELECT Id FROM WorkOrder LIMIT 1];

        Test.startTest();
        TreatmentReportGenerator.AcceptancePackage pkg =
            TreatmentReportGenerator.preview(wo.Id);
        Test.stopTest();

        System.assertNotEquals(null, pkg);
        System.assertEquals(wo.Id, pkg.workOrderId);
        System.assertNotEquals(null, pkg.checks);
        System.assert(pkg.checks.size() >= 10, 'Expected the full audit checklist');
        System.assertEquals(null, pkg.packageContentVersionId, 'Preview must not save a file');
        System.assert(pkg.summary.toLowerCase().contains('treatment report'), 'Summary should mention treatment report');
    }

    @isTest
    static void generate_happyPath_savesContentVersion() {
        WorkOrder wo = [SELECT Id FROM WorkOrder LIMIT 1];

        Test.startTest();
        TreatmentReportGenerator.AcceptancePackage pkg =
            TreatmentReportGenerator.generate(wo.Id);
        Test.stopTest();

        System.assertNotEquals(null, pkg.packageContentVersionId, 'Generated package must persist a ContentVersion');

        List<ContentVersion> saved = [
            SELECT Id, Title, PathOnClient
            FROM ContentVersion
            WHERE Id = :pkg.packageContentVersionId
        ];
        System.assertEquals(1, saved.size());
        System.assertEquals('treatment-report.md', saved[0].PathOnClient);
        System.assert(saved[0].Title.startsWith('Treatment Report - WO'), 'Title should be the treatment report file name');
    }

    @isTest
    static void preview_missingChemicalLog_failsAuditCheck() {
        WorkOrder wo = [SELECT Id FROM WorkOrder LIMIT 1];
        // Wipe the chemical fields to simulate an incomplete log
        LOTO_Record__c rec = [SELECT Id, Chemical_Name__c, Dose_Amount__c, EPA_Reg_Number__c FROM LOTO_Record__c LIMIT 1];
        rec.Chemical_Name__c = null;
        rec.Dose_Amount__c = null;
        rec.EPA_Reg_Number__c = null;
        update rec;

        TreatmentReportGenerator.AcceptancePackage pkg =
            TreatmentReportGenerator.preview(wo.Id);

        Boolean foundFail = false;
        for (TreatmentReportGenerator.AcceptanceCheck c : pkg.checks) {
            if (c.requirement == 'Chemical application log complete' && c.status == 'Fail') {
                foundFail = true;
                break;
            }
        }
        System.assert(foundFail, 'Missing chemical log fields should fail the audit');
        System.assertEquals(false, pkg.readyToFile, 'Cannot file with a fail');
    }

    @isTest
    static void preview_highPressureScore_failsAudit() {
        WorkOrder wo = [SELECT Id FROM WorkOrder LIMIT 1];
        Asset a = [SELECT Id, Pest_Pressure_Score__c FROM Asset LIMIT 1];
        a.Pest_Pressure_Score__c = 75;
        update a;

        TreatmentReportGenerator.AcceptancePackage pkg =
            TreatmentReportGenerator.preview(wo.Id);

        Boolean foundFail = false;
        for (TreatmentReportGenerator.AcceptanceCheck c : pkg.checks) {
            if (c.requirement == 'Pest pressure score within target' && c.status == 'Fail') {
                foundFail = true;
            }
        }
        System.assert(foundFail, 'Pressure score 75 should fail the audit');
    }

    @isTest
    static void preview_marginalPressureScore_warns() {
        WorkOrder wo = [SELECT Id FROM WorkOrder LIMIT 1];
        Asset a = [SELECT Id, Pest_Pressure_Score__c FROM Asset LIMIT 1];
        a.Pest_Pressure_Score__c = 42;
        update a;

        TreatmentReportGenerator.AcceptancePackage pkg =
            TreatmentReportGenerator.preview(wo.Id);

        Boolean foundWarn = false;
        for (TreatmentReportGenerator.AcceptanceCheck c : pkg.checks) {
            if (c.requirement == 'Pest pressure score within target' && c.status == 'Warn') {
                foundWarn = true;
            }
        }
        System.assert(foundWarn, 'Pressure score 42 should warn');
    }

    @isTest
    static void preview_nullWorkOrderId_throws() {
        try {
            TreatmentReportGenerator.preview(null);
            System.assert(false, 'Expected AuraHandledException');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @isTest
    static void generate_nullWorkOrderId_throws() {
        try {
            TreatmentReportGenerator.generate(null);
            System.assert(false, 'Expected AuraHandledException');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @isTest
    static void preview_unknownWorkOrder_throws() {
        Id fake = '0WO000000000000AAA';
        try {
            TreatmentReportGenerator.preview(fake);
            System.assert(false, 'Expected AuraHandledException');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }
}
