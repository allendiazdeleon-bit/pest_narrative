/**
 * UpsellCoachServiceTest — covers happy paths + edges for the marquee
 * Scene 5 demo class. Target: ≥85% line coverage (load-bearing).
 *
 * Pattern note: tests use programmatic Account/Asset creation in @TestSetup;
 * Custom Metadata (Upsell_Talk_Track__mdt) is read at runtime — assertions are
 * tolerant of whether the deployed talk-tracks are present in the scratch org,
 * because hydrateTalkTracks() degrades gracefully on missing rows.
 *
 * Person Account fields (FirstName / LastName / IsPersonAccount) are referenced
 * by the production code; this test does not require Person Accounts to be
 * enabled — biz Accounts plus child Assets exercise every branch.
 */
@isTest(SeeAllData=false)
private class UpsellCoachServiceTest {

    private static final String AVALON_ZIP = '32828';

    @TestSetup
    static void setup() {
        // --- Bennett: existing Pest customer in Avalon Park (Scene 5 anchor) ---
        Account bennett = new Account(
            Name = 'Bennett Residence — 1247 Maple Ave',
            BillingStreet = '1247 Maple Ave',
            BillingCity = 'Orlando',
            BillingState = 'FL',
            BillingPostalCode = AVALON_ZIP,
            Eligible_Upsells__c = 'Termite;Mosquito;Lawn'
        );
        insert bennett;

        Asset bennettPest = new Asset(
            Name = 'Bennett Property — Quarterly Pest',
            AccountId = bennett.Id,
            Service_Line__c = 'Pest',
            Equipment_Type__c = 'Property',
            Lot_Size_Sqft__c = 9500,
            Property_Type__c = 'Single_Family',
            Conducive_Conditions__c = true,
            Trap_Catch_Count_24h__c = 42
        );
        insert bennettPest;

        // --- Three neighbors with Mosquito Hunter in same ZIP (drives social proof) ---
        List<Account> neighbors = new List<Account>{
            new Account(Name='Henderson 101', BillingPostalCode=AVALON_ZIP, BillingStreet='101 Maple Ave'),
            new Account(Name='Garcia 105',    BillingPostalCode=AVALON_ZIP, BillingStreet='105 Maple Ave'),
            new Account(Name='Patel 109',     BillingPostalCode=AVALON_ZIP, BillingStreet='109 Maple Ave')
        };
        insert neighbors;
        List<Asset> neighborAssets = new List<Asset>();
        for (Account n : neighbors) {
            neighborAssets.add(new Asset(
                Name = n.Name + ' — Mosquito',
                AccountId = n.Id,
                Service_Line__c = 'Mosquito',
                Equipment_Type__c = 'Mosquito_System'
            ));
        }
        insert neighborAssets;

        // --- "All four lines" Account: should yield empty recommendations ---
        Account fully = new Account(
            Name = 'FullStack Residence',
            BillingPostalCode = '32827'
        );
        insert fully;
        List<Asset> fullyAssets = new List<Asset>();
        for (String line : new List<String>{'Pest','Termite','Mosquito','Lawn'}) {
            fullyAssets.add(new Asset(
                Name = 'FullStack — ' + line,
                AccountId = fully.Id,
                Service_Line__c = line
            ));
        }
        insert fullyAssets;

        // --- Termite-only Account: should pitch Pest cross-sell ---
        Account termiteOnly = new Account(
            Name = 'TermiteOnly Residence',
            BillingPostalCode = '32830'
        );
        insert termiteOnly;
        insert new Asset(
            Name = 'TermiteOnly — Termite',
            AccountId = termiteOnly.Id,
            Service_Line__c = 'Termite',
            Conducive_Conditions__c = false
        );

        // --- Stranded Account: no Eligible_Upsells, no assets, no ZIP ---
        insert new Account(Name = 'Stranded Residence');
    }

    private static Account fetchByName(String name) {
        return [SELECT Id, BillingPostalCode FROM Account WHERE Name = :name LIMIT 1];
    }

    // --------------------------------------------------------------------
    // recommend() happy paths
    // --------------------------------------------------------------------

    @isTest
    static void recommend_pestCustomerInSeason_returnsRanked() {
        Account a = fetchByName('Bennett Residence — 1247 Maple Ave');

        Test.startTest();
        List<UpsellCoachService.UpsellRecommendation> recs =
            UpsellCoachService.recommend(a.Id);
        Test.stopTest();

        System.assert(!recs.isEmpty(), 'Expected at least one recommendation for Bennett.');
        // Top result must be highest score (sort verification).
        for (Integer i = 1; i < recs.size(); i++) {
            System.assert(recs[i-1].score >= recs[i].score,
                'Recommendations must be sorted descending by score.');
        }
        // No service line that's already on the Account should show up.
        Set<String> recommendedLines = new Set<String>();
        for (UpsellCoachService.UpsellRecommendation r : recs) {
            recommendedLines.add(r.serviceLine);
        }
        System.assert(!recommendedLines.contains('Pest'),
            'Should not recommend Pest to an Account that already has Pest.');

        // Score is bounded.
        for (UpsellCoachService.UpsellRecommendation r : recs) {
            System.assert(r.score >= 0 && r.score <= 100,
                'Score must be in [0,100]: ' + r.score);
        }
    }

    @isTest
    static void recommend_termiteOnly_pitchesPestCrossSell() {
        Account a = fetchByName('TermiteOnly Residence');

        Test.startTest();
        List<UpsellCoachService.UpsellRecommendation> recs =
            UpsellCoachService.recommend(a.Id);
        Test.stopTest();

        Boolean foundPest = false;
        for (UpsellCoachService.UpsellRecommendation r : recs) {
            if (r.serviceLine == 'Pest') {
                foundPest = true;
                System.assert(r.reasonCodes.contains('TERMITE_ONLY_NO_PEST'),
                    'Termite-only Account should fire TERMITE_ONLY_NO_PEST reason.');
            }
        }
        System.assert(foundPest, 'Termite-only Account should produce a Pest recommendation.');
    }

    @isTest
    static void recommend_allFourLines_returnsEmpty() {
        Account a = fetchByName('FullStack Residence');

        Test.startTest();
        List<UpsellCoachService.UpsellRecommendation> recs =
            UpsellCoachService.recommend(a.Id);
        Test.stopTest();

        System.assertEquals(0, recs.size(),
            'Account with all 4 service lines should yield no recommendations.');
    }

    @isTest
    static void recommend_strandedAccount_handlesGracefully() {
        Account a = fetchByName('Stranded Residence');

        Test.startTest();
        List<UpsellCoachService.UpsellRecommendation> recs =
            UpsellCoachService.recommend(a.Id);
        Test.stopTest();

        System.assertNotEquals(null, recs, 'recs list must never be null.');
        // No assets → no existing lines → all 4 lines eligible (defaults).
        // No ZIP → neighbor signal is 0. Just assert it ran without throwing.
    }

    @isTest
    static void recommend_nullAccountId_returnsEmpty() {
        Test.startTest();
        List<UpsellCoachService.UpsellRecommendation> recs =
            UpsellCoachService.recommend(null);
        Test.stopTest();

        System.assertEquals(0, recs.size(), 'Null Id must return empty list.');
    }

    @isTest
    static void recommend_nonExistentAccountId_returnsEmpty() {
        // Construct a syntactically valid Account Id that doesn't resolve.
        Id fakeId = '001000000000000AAA';
        Test.startTest();
        List<UpsellCoachService.UpsellRecommendation> recs =
            UpsellCoachService.recommend(fakeId);
        Test.stopTest();

        System.assertEquals(0, recs.size(), 'Unknown Account Id must return empty list.');
    }

    @isTest
    static void recommend_neighborSignal_appearsForMosquito() {
        Account a = fetchByName('Bennett Residence — 1247 Maple Ave');

        Test.startTest();
        List<UpsellCoachService.UpsellRecommendation> recs =
            UpsellCoachService.recommend(a.Id);
        Test.stopTest();

        // Bennett has 3 mosquito neighbors in 32828 → NEIGHBOR_BOUGHT_MOSQUITO must fire.
        Boolean neighborSignalFired = false;
        for (UpsellCoachService.UpsellRecommendation r : recs) {
            if (r.serviceLine == 'Mosquito'
                && r.reasonCodes.contains('NEIGHBOR_BOUGHT_MOSQUITO')) {
                neighborSignalFired = true;
            }
        }
        System.assert(neighborSignalFired,
            'Mosquito recommendation should include NEIGHBOR_BOUGHT_MOSQUITO when neighbors have it.');
    }

    @isTest
    static void recommend_conduciveConditions_firesTermiteReason() {
        Account a = fetchByName('Bennett Residence — 1247 Maple Ave');

        Test.startTest();
        List<UpsellCoachService.UpsellRecommendation> recs =
            UpsellCoachService.recommend(a.Id);
        Test.stopTest();

        Boolean fired = false;
        for (UpsellCoachService.UpsellRecommendation r : recs) {
            if (r.serviceLine == 'Termite'
                && r.reasonCodes.contains('CONDUCIVE_CONDITIONS_FLAGGED')) {
                fired = true;
            }
        }
        System.assert(fired,
            'Termite rec should fire CONDUCIVE_CONDITIONS_FLAGGED when Asset.Conducive_Conditions__c=true.');
    }

    // --------------------------------------------------------------------
    // captureOutcome()
    // --------------------------------------------------------------------

    @isTest
    static void captureOutcome_yes_createsLeadAndStampsAccount() {
        Account a = fetchByName('Bennett Residence — 1247 Maple Ave');

        Test.startTest();
        Id leadId = UpsellCoachService.captureOutcome(a.Id, 'Mosquito', 'Yes');
        Test.stopTest();

        System.assertNotEquals(null, leadId, 'captureOutcome("Yes") must return a Lead Id.');
        Lead l = [SELECT Id, Company, LastName, Description, LeadSource, PostalCode
                  FROM Lead WHERE Id = :leadId];
        System.assertEquals('Tech Route Pitch', l.LeadSource);
        System.assert(l.Description.contains('Mosquito'),
            'Lead description should mention the service line.');

        Account stamped = [
            SELECT Last_Upsell_Pitched__c, Last_Upsell_Service_Line__c,
                   Last_Upsell_Outcome__c, Upsell_Score_Last_Updated__c
            FROM Account WHERE Id = :a.Id
        ];
        System.assertEquals('Mosquito', stamped.Last_Upsell_Service_Line__c);
        System.assertEquals('Yes', stamped.Last_Upsell_Outcome__c);
        System.assertNotEquals(null, stamped.Last_Upsell_Pitched__c);
        System.assertNotEquals(null, stamped.Upsell_Score_Last_Updated__c);
    }

    @isTest
    static void captureOutcome_notNow_stampsButReturnsNull() {
        Account a = fetchByName('Bennett Residence — 1247 Maple Ave');

        Test.startTest();
        Id leadId = UpsellCoachService.captureOutcome(a.Id, 'Termite', 'NotNow');
        Test.stopTest();

        System.assertEquals(null, leadId,
            'captureOutcome with non-Yes outcome must return null.');

        Account stamped = [
            SELECT Last_Upsell_Outcome__c, Last_Upsell_Service_Line__c
            FROM Account WHERE Id = :a.Id
        ];
        System.assertEquals('NotNow', stamped.Last_Upsell_Outcome__c);
        System.assertEquals('Termite', stamped.Last_Upsell_Service_Line__c);

        // Should NOT have created a Lead.
        Integer leadCount = [SELECT COUNT() FROM Lead];
        System.assertEquals(0, leadCount, 'No Lead should be created when outcome != Yes.');
    }

    @isTest
    static void captureOutcome_notInterested_returnsNull() {
        Account a = fetchByName('Bennett Residence — 1247 Maple Ave');

        Test.startTest();
        Id leadId = UpsellCoachService.captureOutcome(a.Id, 'Lawn', 'NotInterested');
        Test.stopTest();

        System.assertEquals(null, leadId);
    }

    @isTest
    static void captureOutcome_noResponse_returnsNull() {
        Account a = fetchByName('Bennett Residence — 1247 Maple Ave');

        Test.startTest();
        Id leadId = UpsellCoachService.captureOutcome(a.Id, 'Mosquito', 'NoResponse');
        Test.stopTest();

        System.assertEquals(null, leadId);
    }

    @isTest
    static void captureOutcome_nullAccountId_throws() {
        Boolean threw = false;
        Test.startTest();
        try {
            UpsellCoachService.captureOutcome(null, 'Mosquito', 'Yes');
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'Null accountId must throw AuraHandledException.');
    }

    @isTest
    static void captureOutcome_invalidServiceLine_throws() {
        Account a = fetchByName('Bennett Residence — 1247 Maple Ave');
        Boolean threw = false;
        Test.startTest();
        try {
            UpsellCoachService.captureOutcome(a.Id, 'Solar', 'Yes');
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'Invalid service line must throw.');
    }

    @isTest
    static void captureOutcome_blankOutcome_throws() {
        Account a = fetchByName('Bennett Residence — 1247 Maple Ave');
        Boolean threw = false;
        Test.startTest();
        try {
            UpsellCoachService.captureOutcome(a.Id, 'Mosquito', '');
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'Blank outcome must throw.');
    }

    // --------------------------------------------------------------------
    // Eligible_Upsells parsing
    // --------------------------------------------------------------------

    @isTest
    static void recommend_explicitEligibleUpsells_filtersCandidates() {
        // Bennett's Eligible_Upsells = "Termite;Mosquito;Lawn"
        // Bennett already has Pest. So recommendations should be a subset of {Termite,Mosquito,Lawn}.
        Account a = fetchByName('Bennett Residence — 1247 Maple Ave');

        Test.startTest();
        List<UpsellCoachService.UpsellRecommendation> recs =
            UpsellCoachService.recommend(a.Id);
        Test.stopTest();

        Set<String> allowed = new Set<String>{'Termite', 'Mosquito', 'Lawn'};
        for (UpsellCoachService.UpsellRecommendation r : recs) {
            System.assert(allowed.contains(r.serviceLine),
                'Eligible_Upsells should restrict candidates: ' + r.serviceLine);
        }
    }
}
