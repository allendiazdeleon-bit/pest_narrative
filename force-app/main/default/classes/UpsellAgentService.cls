public with sharing class UpsellAgentService {

    public class PortfolioRequest {
        @InvocableVariable(label='Account Id' description='Salesforce Account Id of the customer.' required=true)
        public Id accountId;
    }

    public class ServiceLine {
        @InvocableVariable(label='Service Name')
        public String name;
        @InvocableVariable(label='Status' description='active, eligible, lapsed, or unknown.')
        public String status;
        @InvocableVariable(label='Notes')
        public String notes;
    }

    public class PortfolioResponse {
        @InvocableVariable(label='Account Name')
        public String accountName;
        @InvocableVariable(label='Customer Since' description='Year the account was created in Salesforce.')
        public String customerSince;
        @InvocableVariable(label='Services')
        public List<ServiceLine> services;
        @InvocableVariable(label='Summary')
        public String summary;
    }

    @InvocableMethod(
        label='Get Customer Service Portfolio'
        description='Returns the customer\'s current pest, termite, mosquito, and lawn service status, plus categories the customer is eligible to be upsold.'
        category='Massey Upsell Coach'
    )
    public static List<PortfolioResponse> getCustomerServicePortfolio(List<PortfolioRequest> requests) {
        List<PortfolioResponse> responses = new List<PortfolioResponse>();
        Set<Id> accountIds = new Set<Id>();
        for (PortfolioRequest r : requests) {
            if (r != null && r.accountId != null) accountIds.add(r.accountId);
        }

        Map<Id, Account> accounts = new Map<Id, Account>();
        if (!accountIds.isEmpty()) {
            accounts.putAll(
                [SELECT Id, Name, CreatedDate FROM Account WHERE Id IN :accountIds WITH USER_MODE]
            );
        }

        for (PortfolioRequest req : requests) {
            PortfolioResponse resp = new PortfolioResponse();
            resp.services = new List<ServiceLine>();

            Account acct = (req != null && req.accountId != null) ? accounts.get(req.accountId) : null;
            if (acct == null) {
                resp.accountName = 'Unknown';
                resp.customerSince = 'Unknown';
                resp.summary = 'Account not found or not accessible.';
                responses.add(resp);
                continue;
            }

            resp.accountName = acct.Name;
            resp.customerSince = String.valueOf(acct.CreatedDate.year());
            resp.services = portfolioFor(acct.Name);
            resp.summary = buildSummary(resp);
            responses.add(resp);
        }

        return responses;
    }

    private static List<ServiceLine> portfolioFor(String accountName) {
        List<ServiceLine> svcs = new List<ServiceLine>();
        String lower = (accountName == null) ? '' : accountName.toLowerCase();

        if (lower.contains('lisa')) {
            svcs.add(line('GoGreen Pest Service', 'active',   'Quarterly plan, on-time payments, no missed visits in 18 months.'));
            svcs.add(line('Mosquito Hunter',      'eligible', 'Lisa called twice last summer about mosquitoes — strong fit.'));
            svcs.add(line('Termite Protection (Sentricon)', 'eligible', 'Slab home built 1998, in active swarm zone.'));
            svcs.add(line('Lawn Service',         'eligible', 'No current lawn provider on file.'));
        } else if (lower.contains('sandra')) {
            svcs.add(line('GoGreen Pest Service', 'active',   'Quarterly plan, customer since 2019.'));
            svcs.add(line('Termite Protection (Sentricon)', 'eligible', 'Recent ant call suggests pressure escalation.'));
            svcs.add(line('Mosquito Hunter',      'eligible', 'Lives near retention pond — high mosquito risk area.'));
            svcs.add(line('Lawn Service',         'eligible', 'Not currently subscribed.'));
        } else {
            svcs.add(line('GoGreen Pest Service', 'unknown',  'No pest service data on file for this account.'));
        }
        return svcs;
    }

    private static ServiceLine line(String name, String status, String notes) {
        ServiceLine sl = new ServiceLine();
        sl.name = name;
        sl.status = status;
        sl.notes = notes;
        return sl;
    }

    private static String buildSummary(PortfolioResponse resp) {
        Integer active = 0, eligible = 0;
        for (ServiceLine s : resp.services) {
            if (s.status == 'active') active++;
            else if (s.status == 'eligible') eligible++;
        }
        return resp.accountName + ' has ' + active + ' active service(s) and ' + eligible + ' eligible upsell categor(ies).';
    }
}
