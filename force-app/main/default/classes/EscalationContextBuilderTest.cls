@isTest
private class EscalationContextBuilderTest {

    @isTest static void testSummarizeNoCases() {
        Account a = new Account(Name = 'Healthy Customer');
        insert a;

        EscalationContextBuilder.Request r = new EscalationContextBuilder.Request();
        r.personAccountId = a.Id;
        r.transcript = 'Customer reports unusual insect — small, brown, six legs.';

        Test.startTest();
        List<EscalationContextBuilder.Response> out =
            EscalationContextBuilder.summarize(new List<EscalationContextBuilder.Request>{ r });
        Test.stopTest();

        System.assertEquals(1, out.size());
        System.assertEquals(0, out[0].priorCaseCount);
        System.assert(!out[0].suggestedNbas.isEmpty());
    }

    @isTest static void testSummarizeWithPriorCases() {
        Account a = new Account(Name = 'Frustrated Customer');
        insert a;
        List<Case> cases = new List<Case>();
        for (Integer i = 0; i < 3; i++) {
            cases.add(new Case(AccountId = a.Id, Subject = 'Issue ' + i, Status = 'New'));
        }
        insert cases;

        EscalationContextBuilder.Request r = new EscalationContextBuilder.Request();
        r.personAccountId = a.Id;

        List<EscalationContextBuilder.Response> out =
            EscalationContextBuilder.summarize(new List<EscalationContextBuilder.Request>{ r });
        System.assertEquals(3, out[0].priorCaseCount);
    }
}
