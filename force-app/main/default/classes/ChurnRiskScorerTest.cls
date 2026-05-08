@isTest
private class ChurnRiskScorerTest {

    @isTest static void testNoCasesLowRisk() {
        Account a = new Account(Name = 'Healthy Customer');
        insert a;

        Test.startTest();
        ChurnRiskScorer.ChurnRiskAssessment res = ChurnRiskScorer.score(a.Id);
        Test.stopTest();

        System.assertEquals(a.Id, res.personAccountId);
        System.assert(res.riskScore >= 0 && res.riskScore <= 100);
        System.assertNotEquals(null, res.tier);
        System.assertNotEquals(null, res.summary);
    }

    @isTest static void testHighFrictionElevatesScore() {
        Account a = new Account(Name = 'Frustrated Customer');
        insert a;
        List<Case> cases = new List<Case>();
        for (Integer i = 0; i < 3; i++) {
            cases.add(new Case(AccountId = a.Id, Subject = 'Issue ' + i, Status = 'New'));
        }
        insert cases;

        ChurnRiskScorer.ChurnRiskAssessment res = ChurnRiskScorer.score(a.Id);
        System.assertEquals(3, res.recentCaseCount);
        System.assert(res.riskScore >= 25);
    }

    @isTest static void testNullThrows() {
        try {
            ChurnRiskScorer.score(null);
            System.assert(false, 'Should have thrown');
        } catch (AuraHandledException e) {
            // expected
        }
    }
}
