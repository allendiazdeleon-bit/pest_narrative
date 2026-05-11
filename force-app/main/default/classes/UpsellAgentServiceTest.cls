@isTest
private class UpsellAgentServiceTest {

    @isTest
    static void portfolioForLisa() {
        Account a = new Account(Name='Lisa Chen');
        insert a;

        UpsellAgentService.PortfolioRequest req = new UpsellAgentService.PortfolioRequest();
        req.accountId = a.Id;

        Test.startTest();
        List<UpsellAgentService.PortfolioResponse> resps =
            UpsellAgentService.getCustomerServicePortfolio(
                new List<UpsellAgentService.PortfolioRequest>{ req }
            );
        Test.stopTest();

        System.assertEquals(1, resps.size(), 'one response per request');
        UpsellAgentService.PortfolioResponse resp = resps[0];
        System.assertEquals('Lisa Chen', resp.accountName);
        System.assertEquals(4, resp.services.size(), 'Lisa has 4 service lines');
        System.assertEquals('active', resp.services[0].status, 'GoGreen is active');
        System.assert(resp.summary.contains('1 active'), 'summary mentions 1 active');
        System.assert(resp.summary.contains('3 eligible'), 'summary mentions 3 eligible');
        System.assertNotEquals(null, resp.customerSince);
    }

    @isTest
    static void portfolioForSandra() {
        Account a = new Account(Name='Sandra Reyes');
        insert a;

        UpsellAgentService.PortfolioRequest req = new UpsellAgentService.PortfolioRequest();
        req.accountId = a.Id;

        Test.startTest();
        List<UpsellAgentService.PortfolioResponse> resps =
            UpsellAgentService.getCustomerServicePortfolio(
                new List<UpsellAgentService.PortfolioRequest>{ req }
            );
        Test.stopTest();

        System.assertEquals('Sandra Reyes', resps[0].accountName);
        System.assertEquals(4, resps[0].services.size());
        System.assertEquals('active', resps[0].services[0].status);
    }

    @isTest
    static void portfolioForUnknownAccount() {
        Account a = new Account(Name='ACME Co');
        insert a;

        UpsellAgentService.PortfolioRequest req = new UpsellAgentService.PortfolioRequest();
        req.accountId = a.Id;

        Test.startTest();
        List<UpsellAgentService.PortfolioResponse> resps =
            UpsellAgentService.getCustomerServicePortfolio(
                new List<UpsellAgentService.PortfolioRequest>{ req }
            );
        Test.stopTest();

        System.assertEquals('ACME Co', resps[0].accountName);
        System.assertEquals(1, resps[0].services.size());
        System.assertEquals('unknown', resps[0].services[0].status);
    }

    @isTest
    static void portfolioForMissingAccountId() {
        UpsellAgentService.PortfolioRequest req = new UpsellAgentService.PortfolioRequest();

        Test.startTest();
        List<UpsellAgentService.PortfolioResponse> resps =
            UpsellAgentService.getCustomerServicePortfolio(
                new List<UpsellAgentService.PortfolioRequest>{ req }
            );
        Test.stopTest();

        System.assertEquals(1, resps.size());
        System.assertEquals('Unknown', resps[0].accountName);
        System.assertEquals(0, resps[0].services.size());
    }

    @isTest
    static void bulkRequestsReturnSameOrder() {
        Account lisa   = new Account(Name='Lisa Chen');
        Account sandra = new Account(Name='Sandra Reyes');
        Account other  = new Account(Name='Other Co');
        insert new List<Account>{ lisa, sandra, other };

        List<UpsellAgentService.PortfolioRequest> reqs = new List<UpsellAgentService.PortfolioRequest>();
        for (Id aid : new List<Id>{ lisa.Id, sandra.Id, other.Id }) {
            UpsellAgentService.PortfolioRequest r = new UpsellAgentService.PortfolioRequest();
            r.accountId = aid;
            reqs.add(r);
        }

        Test.startTest();
        List<UpsellAgentService.PortfolioResponse> resps =
            UpsellAgentService.getCustomerServicePortfolio(reqs);
        Test.stopTest();

        System.assertEquals(3, resps.size(), 'returns one response per request');
        System.assertEquals('Lisa Chen', resps[0].accountName);
        System.assertEquals('Sandra Reyes', resps[1].accountName);
        System.assertEquals('Other Co', resps[2].accountName);
    }
}
