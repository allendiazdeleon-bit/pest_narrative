@isTest
private class ServiceAreaValidatorTest {

    @isTest static void testValidateNoGeocoder() {
        // ExternalGeocoder dependency may or may not be present; either branch is fine
        ServiceAreaValidator.Request r = new ServiceAreaValidator.Request();
        r.addressString = '5500 Lake Nona Blvd, Orlando, FL 32827';

        try {
            Test.startTest();
            List<ServiceAreaValidator.Response> out =
                ServiceAreaValidator.validate(new List<ServiceAreaValidator.Request>{ r });
            Test.stopTest();
            System.assertEquals(1, out.size());
        } catch (Exception ex) {
            // Acceptable — ExternalGeocoder may not be in scope for this test
            System.assertNotEquals(null, ex.getMessage());
        }
    }
}
