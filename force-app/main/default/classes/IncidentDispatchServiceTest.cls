@isTest
private class IncidentDispatchServiceTest {

    private static Incident makeIncidentWithCases(Integer numCases) {
        Incident inc = new Incident(Subject = 'Mosquito Surge', Priority = 'High',
                                     Affected_Customers__c = numCases, Circuit__c = 'ZIP-32828');
        insert inc;
        List<Account> accts = new List<Account>();
        for (Integer i = 0; i < numCases; i++) {
            accts.add(new Account(Name = 'Test ' + i));
        }
        insert accts;

        List<Asset> assets = new List<Asset>();
        for (Integer i = 0; i < numCases; i++) {
            assets.add(new Asset(Name = 'Property ' + i, AccountId = accts[i].Id));
        }
        insert assets;

        List<Case> cases = new List<Case>();
        for (Integer i = 0; i < numCases; i++) {
            cases.add(new Case(AccountId = accts[i].Id, AssetId = assets[i].Id,
                               Subject = 'Mosquitoes at ' + (1400 + i) + ' Avalon Park Blvd',
                               Linked_Incident__c = inc.Id, Status = 'New'));
        }
        insert cases;
        return inc;
    }

    @isTest static void testPreviewDispatch() {
        Incident inc = makeIncidentWithCases(3);
        IncidentDispatchService.DispatchPreview p = IncidentDispatchService.previewDispatch(inc.Id);
        System.assertEquals(3, p.affectedAssets.size());
    }

    @isTest static void testDispatchSingleResponse() {
        Incident inc = makeIncidentWithCases(3);
        WorkType wt = new WorkType(Name = 'Mosquito Surge Area Treatment',
                                    EstimatedDuration = 120, DurationType = 'Minutes');
        insert wt;

        Test.startTest();
        IncidentDispatchService.DispatchResult res =
            IncidentDispatchService.dispatch(inc.Id, 'SINGLE_RESPONSE', wt.Id, 'High');
        Test.stopTest();

        System.assertEquals(1, res.workOrdersCreated);
        System.assertEquals('SINGLE_RESPONSE', res.strategy);
    }

    @isTest static void testDispatchPerProperty() {
        Incident inc = makeIncidentWithCases(2);
        WorkType wt = new WorkType(Name = 'Booster Termite Inspection',
                                    EstimatedDuration = 60, DurationType = 'Minutes');
        insert wt;

        IncidentDispatchService.DispatchResult res =
            IncidentDispatchService.dispatch(inc.Id, 'PER_PROPERTY', wt.Id, 'Medium');
        System.assertEquals(2, res.workOrdersCreated);
    }

    @isTest static void testDispatchBundledBySegment() {
        Incident inc = makeIncidentWithCases(2);
        WorkType wt = new WorkType(Name = 'Booster Pest Treatment',
                                    EstimatedDuration = 90, DurationType = 'Minutes');
        insert wt;

        IncidentDispatchService.DispatchResult res =
            IncidentDispatchService.dispatch(inc.Id, 'BUNDLED_BY_SEGMENT', wt.Id, null);
        System.assert(res.workOrdersCreated >= 1);
    }
}
