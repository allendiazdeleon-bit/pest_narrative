@isTest
private class ProactiveWoGeneratorTest {

    @isTest static void testRunAllNoBreaches() {
        Test.startTest();
        ProactiveWoGenerator.Result r = ProactiveWoGenerator.runAll();
        Test.stopTest();
        System.assertEquals(0, r.breachesScanned);
        System.assert(r.message.contains('No threshold breaches'));
    }

    @isTest static void testRunForAssetEmpty() {
        Account a = new Account(Name = 'No Breach');
        insert a;
        Asset asset = new Asset(Name = 'Property X', AccountId = a.Id);
        insert asset;

        ProactiveWoGenerator.Result r = ProactiveWoGenerator.runForAsset(asset.Id);
        System.assertEquals(0, r.breachesScanned);
    }

    @isTest static void testRunForMonitorEmpty() {
        // Just exercise the path with an arbitrary id
        Account a = new Account(Name = 'Test');
        insert a;
        ProactiveWoGenerator.Result r = ProactiveWoGenerator.runForMonitor(a.Id);
        System.assertEquals(0, r.breachesScanned);
    }

    @isTest static void testRunAllIncludingHeroes() {
        ProactiveWoGenerator.Result r = ProactiveWoGenerator.runAllIncludingHeroes();
        System.assertNotEquals(null, r.message);
    }
}
