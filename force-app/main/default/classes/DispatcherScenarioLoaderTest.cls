@isTest
private class DispatcherScenarioLoaderTest {

    @isTest static void testLoadNoTerritory() {
        Test.startTest();
        String result = DispatcherScenarioLoader.load();
        Test.stopTest();
        System.assertNotEquals(null, result);
    }

    @isTest static void testReset() {
        String result = DispatcherScenarioLoader.reset();
        System.assert(result.contains('Cleaned'));
    }
}
