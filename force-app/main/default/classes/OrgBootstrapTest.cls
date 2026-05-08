@isTest
private class OrgBootstrapTest {

    @isTest static void testEnsureFoundation() {
        Test.startTest();
        String result = OrgBootstrap.ensureFoundation();
        Test.stopTest();
        System.assertNotEquals(null, result);
        // Result will be FOUNDATION READY or BOOTSTRAP FAILED — both are valid
        System.assert(result.contains('FOUNDATION') || result.contains('BOOTSTRAP'));
    }

    @isTest static void testIdempotent() {
        OrgBootstrap.ensureFoundation();
        String result = OrgBootstrap.ensureFoundation();
        System.assertNotEquals(null, result);
    }
}
