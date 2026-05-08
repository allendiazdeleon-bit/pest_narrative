/**
 * PestPressureAnalyzerTest — covers happy paths + edge cases for the
 * pest-pressure analyzer (no Asset, heavy termite pressure, elevated
 * activity, mosquito service line, lawn service line, default branch).
 */
@isTest
private class PestPressureAnalyzerTest {

    @TestSetup
    static void setup() {
        // 5 distinct Accounts to exercise different branches deterministically
        List<Account> accts = new List<Account>{
            new Account(Name = 'Bennett Residence — Termite Heavy'),
            new Account(Name = 'Lopez Residence — Mosquito Heavy'),
            new Account(Name = 'Vargas Residence — Lawn Heavy'),
            new Account(Name = 'Reyes Residence — Elevated Activity'),
            new Account(Name = 'Chen Residence — No Pressure'),
            new Account(Name = 'Walker Residence — No Asset')
        };
        insert accts;

        // Heavy termite pressure
        Asset termiteAsset = new Asset(
            Name = 'Bennett Property — 1247 Maple Ave',
            AccountId = accts[0].Id,
            Service_Line__c = 'Termite',
            Equipment_Type__c = 'Sentricon_Station',
            Is_Pest_Pressure_Candidate__c = true,
            Bait_Station_Hits_30d__c = 5,
            Bait_Station_State__c = 'Heavy_Activity',
            Last_Bait_Station_Hit_Date__c = Date.today().addDays(-3),
            Pest_Pressure_Score__c = 88,
            Conducive_Conditions__c = true,
            Days_Since_Last_Service__c = 14
        );

        // Heavy mosquito pressure
        Asset mosquitoAsset = new Asset(
            Name = 'Lopez Property — Mosquito System',
            AccountId = accts[1].Id,
            Service_Line__c = 'Mosquito',
            Equipment_Type__c = 'Mosquito_System',
            Is_Pest_Pressure_Candidate__c = true,
            Trap_Catch_Count_24h__c = 22,
            Conducive_Conditions__c = true,
            Pest_Pressure_Score__c = 75
        );

        // Heavy lawn pressure (no precomputed score — exercise fallback path)
        Asset lawnAsset = new Asset(
            Name = 'Vargas Property — Lawn',
            AccountId = accts[2].Id,
            Service_Line__c = 'Lawn',
            Equipment_Type__c = 'Property',
            Is_Pest_Pressure_Candidate__c = true,
            Bait_Station_Hits_30d__c = 0,
            Conducive_Conditions__c = true
        );

        // Elevated (light) activity — soft anomaly branch
        Asset elevatedAsset = new Asset(
            Name = 'Reyes Property — Quarterly Pest',
            AccountId = accts[3].Id,
            Service_Line__c = 'Pest',
            Equipment_Type__c = 'Property',
            Is_Pest_Pressure_Candidate__c = false,
            Bait_Station_Hits_30d__c = 2,
            Bait_Station_State__c = 'Activity'
        );

        // No pressure — fully clean
        Asset cleanAsset = new Asset(
            Name = 'Chen Property — Quarterly Pest',
            AccountId = accts[4].Id,
            Service_Line__c = 'Pest',
            Equipment_Type__c = 'Property',
            Is_Pest_Pressure_Candidate__c = false,
            Bait_Station_State__c = 'Untouched',
            Bait_Station_Hits_30d__c = 0
        );

        insert new List<Asset>{termiteAsset, mosquitoAsset, lawnAsset, elevatedAsset, cleanAsset};
        // accts[5] (Walker) intentionally has no Asset
    }

    @isTest
    static void heavyTermitePressure_returnsHeavyDiagnosisAndScore() {
        Account a = [SELECT Id FROM Account WHERE Name LIKE 'Bennett%' LIMIT 1];
        PestPressureAnalyzer.Request req = new PestPressureAnalyzer.Request();
        req.personAccountId = a.Id;
        req.daysBack = 30;

        Test.startTest();
        List<PestPressureAnalyzer.Response> resp = PestPressureAnalyzer.analyze(new List<PestPressureAnalyzer.Request>{req});
        Test.stopTest();

        System.assertEquals(1, resp.size(), 'One response expected');
        System.assertEquals('HEAVY_PRESSURE', resp[0].anomalyType);
        System.assert(resp[0].diagnosis.toLowerCase().contains('termite'), 'Diagnosis should mention termite');
        System.assert(resp[0].diagnosis.toLowerCase().contains('bait station'), 'Diagnosis should mention bait station');
        System.assertEquals(88, resp[0].pestPressureScore);
        System.assertNotEquals(null, resp[0].primaryAssetId);
    }

    @isTest
    static void heavyMosquitoPressure_returnsMosquitoDiagnosis() {
        Account a = [SELECT Id FROM Account WHERE Name LIKE 'Lopez%' LIMIT 1];
        PestPressureAnalyzer.Request req = new PestPressureAnalyzer.Request();
        req.personAccountId = a.Id;

        List<PestPressureAnalyzer.Response> resp = PestPressureAnalyzer.analyze(new List<PestPressureAnalyzer.Request>{req});

        System.assertEquals('HEAVY_PRESSURE', resp[0].anomalyType);
        System.assert(resp[0].diagnosis.toLowerCase().contains('mosquito'), 'Diagnosis should mention mosquito');
        System.assert(resp[0].diagnosis.toLowerCase().contains('larvicide') || resp[0].diagnosis.toLowerCase().contains('ulv'),
            'Diagnosis should reference treatment approach');
    }

    @isTest
    static void heavyLawnPressure_fallsBackToSyntheticScore() {
        Account a = [SELECT Id FROM Account WHERE Name LIKE 'Vargas%' LIMIT 1];
        PestPressureAnalyzer.Request req = new PestPressureAnalyzer.Request();
        req.personAccountId = a.Id;

        List<PestPressureAnalyzer.Response> resp = PestPressureAnalyzer.analyze(new List<PestPressureAnalyzer.Request>{req});

        System.assertEquals('HEAVY_PRESSURE', resp[0].anomalyType);
        System.assert(resp[0].diagnosis.toLowerCase().contains('lawn') || resp[0].diagnosis.toLowerCase().contains('chinch'),
            'Diagnosis should reference lawn pests');
        System.assertNotEquals(null, resp[0].pestPressureScore);
    }

    @isTest
    static void elevatedActivity_returnsWatchItem() {
        Account a = [SELECT Id FROM Account WHERE Name LIKE 'Reyes%' LIMIT 1];
        PestPressureAnalyzer.Request req = new PestPressureAnalyzer.Request();
        req.personAccountId = a.Id;

        List<PestPressureAnalyzer.Response> resp = PestPressureAnalyzer.analyze(new List<PestPressureAnalyzer.Request>{req});

        System.assertEquals('ELEVATED_PRESSURE', resp[0].anomalyType);
        System.assert(resp[0].diagnosis.toLowerCase().contains('quarterly') || resp[0].diagnosis.toLowerCase().contains('foraging'),
            'Diagnosis should reference watch / quarterly check');
    }

    @isTest
    static void noPressure_returnsClean() {
        Account a = [SELECT Id FROM Account WHERE Name LIKE 'Chen%' LIMIT 1];
        PestPressureAnalyzer.Request req = new PestPressureAnalyzer.Request();
        req.personAccountId = a.Id;
        // No daysBack — exercise default 30

        List<PestPressureAnalyzer.Response> resp = PestPressureAnalyzer.analyze(new List<PestPressureAnalyzer.Request>{req});

        System.assertEquals('NONE', resp[0].anomalyType);
        System.assertEquals(0, resp[0].pestPressureScore);
    }

    @isTest
    static void noAsset_returnsNoAssetMessage() {
        Account a = [SELECT Id FROM Account WHERE Name LIKE 'Walker%' LIMIT 1];
        PestPressureAnalyzer.Request req = new PestPressureAnalyzer.Request();
        req.personAccountId = a.Id;

        List<PestPressureAnalyzer.Response> resp = PestPressureAnalyzer.analyze(new List<PestPressureAnalyzer.Request>{req});

        System.assertEquals('NONE', resp[0].anomalyType);
        System.assert(resp[0].diagnosis.toLowerCase().contains('no asset'), 'Should report no asset on file');
    }

    @isTest
    static void bulk_handlesMultipleRequestsInOneInvocation() {
        List<Account> accts = [SELECT Id FROM Account ORDER BY Name LIMIT 3];
        List<PestPressureAnalyzer.Request> reqs = new List<PestPressureAnalyzer.Request>();
        for (Account a : accts) {
            PestPressureAnalyzer.Request r = new PestPressureAnalyzer.Request();
            r.personAccountId = a.Id;
            reqs.add(r);
        }
        List<PestPressureAnalyzer.Response> resp = PestPressureAnalyzer.analyze(reqs);
        System.assertEquals(3, resp.size());
    }
}
