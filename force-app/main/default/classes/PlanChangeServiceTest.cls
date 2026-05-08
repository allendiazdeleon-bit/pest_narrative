@isTest
private class PlanChangeServiceTest {

    @isTest static void testChangeTierNoAccountThrows() {
        try {
            PlanChangeService.changeTier(null, 'GoGreen_Pest');
            System.assert(false, 'Should have thrown');
        } catch (AuraHandledException e) {
            // expected
        }
    }

    @isTest static void testChangeTierInvalidPicklistThrows() {
        Account a = new Account(Name = 'Test');
        insert a;
        try {
            PlanChangeService.changeTier(a.Id, 'INVALID_TIER');
            System.assert(false, 'Should have thrown');
        } catch (AuraHandledException e) {
            // expected
        }
    }

    @isTest static void testGetCurrentTierNullAccount() {
        System.assertEquals(null, PlanChangeService.getCurrentTier(null));
    }

    @isTest static void testGetCurrentTierNoAsset() {
        Account a = new Account(Name = 'No Assets');
        insert a;
        System.assertEquals(null, PlanChangeService.getCurrentTier(a.Id));
    }
}
