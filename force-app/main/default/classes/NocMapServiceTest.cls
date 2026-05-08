@isTest
private class NocMapServiceTest {

    @isTest static void testGetActiveOutagesEmpty() {
        List<NocMapService.OutageMarker> markers = NocMapService.getActiveOutages();
        System.assertNotEquals(null, markers);
    }

    @isTest static void testGetActiveOutagesWithGeo() {
        Incident inc = new Incident(Subject = 'Mosquito Surge', Priority = 'High',
                                     Affected_Customers__c = 47,
                                     Outage_Latitude__c = 28.5383,
                                     Outage_Longitude__c = -81.3792,
                                     Circuit__c = 'ZIP-32828-MOSQUITO');
        insert inc;

        List<NocMapService.OutageMarker> markers = NocMapService.getActiveOutages();
        System.assert(markers.size() >= 1);
        Boolean found = false;
        for (NocMapService.OutageMarker m : markers) {
            if (m.incidentId == inc.Id) {
                found = true;
                System.assertEquals('ZIP-32828-MOSQUITO', m.serviceGroup);
                System.assertEquals(47, m.affectedProperties);
            }
        }
        System.assert(found);
    }
}
