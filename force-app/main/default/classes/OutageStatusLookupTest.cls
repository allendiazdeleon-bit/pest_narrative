@isTest
private class OutageStatusLookupTest {

    @isTest static void testNoActiveIncident() {
        Account a = new Account(Name = 'Quiet Customer');
        insert a;
        OutageStatusLookup.Request r = new OutageStatusLookup.Request();
        r.personAccountId = a.Id;

        List<OutageStatusLookup.Response> out = OutageStatusLookup.findActive(new List<OutageStatusLookup.Request>{ r });
        System.assertEquals(false, out[0].hasActiveIncident);
    }

    @isTest static void testWithMatchingIncident() {
        Account a = new Account(Name = 'Cluster Customer');
        insert a;
        Asset asset = new Asset(Name = 'Property A', AccountId = a.Id, Latitude = 28.54, Longitude = -81.38);
        insert asset;
        Incident inc = new Incident(Subject = 'Demo_Mosquito_Surge', Priority = 'High',
                                     Affected_Customers__c = 47,
                                     Outage_Latitude__c = 28.55,
                                     Outage_Longitude__c = -81.38);
        insert inc;

        OutageStatusLookup.Request r = new OutageStatusLookup.Request();
        r.personAccountId = a.Id;
        List<OutageStatusLookup.Response> out = OutageStatusLookup.findActive(new List<OutageStatusLookup.Request>{ r });
        System.assertEquals(true, out[0].hasActiveIncident);
    }
}
