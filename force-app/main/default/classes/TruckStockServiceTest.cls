@isTest
private class TruckStockServiceTest {

    @isTest static void testNullResource() {
        TruckStockService.StockSummary s = TruckStockService.getStockSummary(null);
        System.assertEquals('No resource selected', s.resourceName);
    }

    @isTest static void testHappyResource() {
        ServiceResource sr = new ServiceResource(Name = 'Maria Lopez',
                                                 RelatedRecordId = UserInfo.getUserId(),
                                                 ResourceType = 'T',
                                                 IsActive = true);
        insert sr;

        Test.startTest();
        TruckStockService.StockSummary s = TruckStockService.getStockSummary(sr.Id);
        Test.stopTest();

        System.assertEquals('Maria Lopez', s.resourceName);
        System.assertEquals(0, s.todaysWoCount);
        System.assert(s.truckNumber.startsWith('MSY-'));
    }
}
