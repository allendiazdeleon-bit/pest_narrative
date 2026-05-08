@isTest
private class PhotoAnalysisServiceTest {

    @isTest static void testAnalyzeNullThrows() {
        try {
            PhotoAnalysisService.analyzePhoto(null);
            System.assert(false);
        } catch (AuraHandledException e) {}
    }

    @isTest static void testMatchTemplateRouting() {
        // Each route in matchTemplate exercised
        PhotoAnalysisService.AnalysisResult r1 = PhotoAnalysisService.matchTemplate('sentricon-station-15.jpg', null);
        System.assertEquals('Sentricon station — active termite feeding', r1.title);

        PhotoAnalysisService.AnalysisResult r2 = PhotoAnalysisService.matchTemplate('mud-tube-foundation', null);
        System.assert(r2.title.containsIgnoreCase('termite'));

        PhotoAnalysisService.AnalysisResult r3 = PhotoAnalysisService.matchTemplate('mosquito-breeding.jpg', null);
        System.assert(r3.title.containsIgnoreCase('mosquito'));

        PhotoAnalysisService.AnalysisResult r4 = PhotoAnalysisService.matchTemplate('mulch-against-foundation', null);
        System.assertEquals('Conducive conditions — wood-to-soil + moisture ingress', r4.title);

        PhotoAnalysisService.AnalysisResult r5 = PhotoAnalysisService.matchTemplate('ant-trail-kitchen', null);
        System.assertEquals('Active pest intrusion — sugar ants + entry point identified', r5.title);

        PhotoAnalysisService.AnalysisResult r6 = PhotoAnalysisService.matchTemplate('lawn-chinch-bug', null);
        System.assert(r6.title.containsIgnoreCase('lawn'));

        PhotoAnalysisService.AnalysisResult r7 = PhotoAnalysisService.matchTemplate('site-clear', null);
        System.assertEquals('Low', r7.severity);

        PhotoAnalysisService.AnalysisResult r8 = PhotoAnalysisService.matchTemplate('random-name.jpg', null);
        System.assertNotEquals(null, r8.title);  // fallback
    }

    @isTest static void testAnalyzeMostRecentNoLinks() {
        Account a = new Account(Name = 'Photo Customer');
        insert a;
        WorkOrder wo = new WorkOrder(Subject = 'Test', AccountId = a.Id, Status = 'New');
        insert wo;

        PhotoAnalysisService.AnalysisResult r = PhotoAnalysisService.analyzeMostRecentPhoto(wo.Id);
        System.assertEquals(null, r);
    }
}
