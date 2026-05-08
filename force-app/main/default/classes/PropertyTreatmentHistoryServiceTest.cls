/**
 * PropertyTreatmentHistoryServiceTest — covers happy paths + edge cases
 * for property topology synthesis (around an asset, around an incident,
 * preview of perimeter-leg offline impact, prior-treatment query).
 *
 * NOTE: Tests are tolerant of person-account org-config sensitivity. If
 * person accounts aren't enabled in the test scratch org, the topology
 * around-asset path still works (uses the seed Asset directly); only the
 * "nearby route" enrichment query depends on IsPersonAccount = true. The
 * tests assert structural invariants rather than exact node counts.
 */
@isTest
private class PropertyTreatmentHistoryServiceTest {

    @TestSetup
    static void setup() {
        Account seedAcct = new Account(
            Name = 'Bennett Residence — 1247 Maple Ave',
            BillingStreet = '1247 Maple Ave',
            BillingCity = 'Orlando',
            BillingState = 'FL',
            BillingPostalCode = '32828'
        );
        insert seedAcct;

        Asset termiteAsset = new Asset(
            Name = 'Bennett Property — Termite',
            AccountId = seedAcct.Id,
            Service_Line__c = 'Termite',
            Equipment_Type__c = 'Sentricon_Station',
            Service_Group__c = 'ZIP-32828-Termite',
            Bait_Station_State__c = 'Activity',
            Bait_Station_Hits_30d__c = 3,
            Last_Bait_Station_Hit_Date__c = Date.today().addDays(-5),
            Pest_Pressure_Score__c = 65,
            Last_Treatment_DateTime__c = DateTime.now().addDays(-90),
            EPA_Reg_Number_Last_Used__c = '432-1404',
            Days_Since_Last_Service__c = 90
        );

        Account mosquitoAcct = new Account(
            Name = 'Lopez Residence — 88 Oak Way',
            BillingStreet = '88 Oak Way',
            BillingCity = 'Orlando',
            BillingState = 'FL',
            BillingPostalCode = '32828'
        );
        insert mosquitoAcct;

        Asset mosquitoAsset = new Asset(
            Name = 'Lopez Property — Mosquito System',
            AccountId = mosquitoAcct.Id,
            Service_Line__c = 'Mosquito',
            Equipment_Type__c = 'Mosquito_System',
            Service_Group__c = 'ZIP-32828-Mosquito',
            Bait_Station_State__c = 'Untouched'
        );

        Account pestAcct = new Account(
            Name = 'Reyes Residence — 12 Pine Ln',
            BillingStreet = '12 Pine Ln',
            BillingCity = 'Orlando',
            BillingState = 'FL',
            BillingPostalCode = '32828'
        );
        insert pestAcct;

        Asset pestAsset = new Asset(
            Name = 'Reyes Property — Quarterly Pest',
            AccountId = pestAcct.Id,
            Service_Line__c = 'Pest',
            Equipment_Type__c = 'Property',
            Service_Group__c = 'ZIP-32828-Pest',
            Bait_Station_State__c = 'Untouched'
        );

        insert new List<Asset>{termiteAsset, mosquitoAsset, pestAsset};
    }

    @isTest
    static void getTopologyAroundAsset_termite_returnsTermiteShape() {
        Asset a = [SELECT Id FROM Asset WHERE Service_Line__c = 'Termite' LIMIT 1];

        Test.startTest();
        PropertyTreatmentHistoryService.PropertyTopology topo =
            PropertyTreatmentHistoryService.getTopologyAroundAsset(a.Id);
        Test.stopTest();

        System.assertNotEquals(null, topo);
        System.assertNotEquals(null, topo.centerLatitude);
        System.assertNotEquals(null, topo.centerLongitude);
        System.assert(topo.nodes.size() > 0, 'Topology must contain nodes');
        System.assert(topo.edges.size() > 0, 'Topology must contain edges');
        System.assert(topo.summary.contains('Sentricon') || topo.summary.contains('Termite'),
            'Termite summary should reference Sentricon');

        Boolean hasStation = false;
        Boolean hasPerimeter = false;
        for (PropertyTreatmentHistoryService.PropertyNode n : topo.nodes) {
            if (n.nodeType == 'Sentricon_Station') hasStation = true;
            if (n.nodeType == 'Treatment_Perimeter') hasPerimeter = true;
        }
        System.assert(hasStation, 'Termite topology should include Sentricon station endpoint');
        System.assert(hasPerimeter, 'Termite topology should include perimeter legs');
    }

    @isTest
    static void getTopologyAroundAsset_mosquito_returnsMosquitoShape() {
        Asset a = [SELECT Id FROM Asset WHERE Service_Line__c = 'Mosquito' LIMIT 1];

        PropertyTreatmentHistoryService.PropertyTopology topo =
            PropertyTreatmentHistoryService.getTopologyAroundAsset(a.Id);

        Boolean hasNozzle = false;
        Boolean hasMosquitoSystem = false;
        for (PropertyTreatmentHistoryService.PropertyNode n : topo.nodes) {
            if (n.nodeType == 'Mosquito_Nozzle') hasNozzle = true;
            if (n.nodeType == 'Mosquito_System') hasMosquitoSystem = true;
        }
        System.assert(hasNozzle, 'Mosquito topology should include nozzle zones');
        System.assert(hasMosquitoSystem, 'Mosquito topology should include the controller endpoint');
    }

    @isTest
    static void getTopologyAroundAsset_pest_returnsPestShape() {
        Asset a = [SELECT Id FROM Asset WHERE Service_Line__c = 'Pest' LIMIT 1];

        PropertyTreatmentHistoryService.PropertyTopology topo =
            PropertyTreatmentHistoryService.getTopologyAroundAsset(a.Id);

        Boolean hasTrap = false;
        for (PropertyTreatmentHistoryService.PropertyNode n : topo.nodes) {
            if (n.nodeType == 'Trap') hasTrap = true;
        }
        System.assert(hasTrap, 'Pest topology should include trap endpoints');
    }

    @isTest
    static void getTopologyAroundAsset_nullId_throws() {
        try {
            PropertyTreatmentHistoryService.getTopologyAroundAsset(null);
            System.assert(false, 'Expected AuraHandledException');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @isTest
    static void getTopologyAroundAsset_nonexistent_throws() {
        Id fakeId = '02i000000000000AAA';
        try {
            PropertyTreatmentHistoryService.getTopologyAroundAsset(fakeId);
            System.assert(false, 'Expected AuraHandledException for missing asset');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @isTest
    static void previewValveClose_perimeterLeg_returnsImpactArea() {
        Asset a = [SELECT Id FROM Asset WHERE Service_Line__c = 'Termite' LIMIT 1];
        PropertyTreatmentHistoryService.PropertyTopology topo =
            PropertyTreatmentHistoryService.getTopologyAroundAsset(a.Id);

        String legId;
        for (PropertyTreatmentHistoryService.PropertyNode n : topo.nodes) {
            if (n.nodeType == 'Treatment_Perimeter') {
                legId = n.id;
                break;
            }
        }
        System.assertNotEquals(null, legId, 'Topology must include at least one perimeter leg');

        Test.startTest();
        PropertyTreatmentHistoryService.ImpactArea area =
            PropertyTreatmentHistoryService.previewValveClose(a.Id, legId);
        Test.stopTest();

        System.assertEquals(legId, area.closedValveId);
        System.assertNotEquals(null, area.affectedNodeIds);
        System.assertNotEquals(null, area.highPriorityFlags);
        System.assertEquals(area.affectedNodeIds.size(), area.affectedCount);
    }

    @isTest
    static void previewValveClose_unknownLeg_throws() {
        Asset a = [SELECT Id FROM Asset WHERE Service_Line__c = 'Termite' LIMIT 1];
        try {
            PropertyTreatmentHistoryService.previewValveClose(a.Id, 'BOGUS-LEG');
            System.assert(false, 'Expected AuraHandledException');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @isTest
    static void getPriorTreatments_returnsAssetsByLastTreatment() {
        Account a = [SELECT Id FROM Account WHERE Name LIKE 'Bennett%' LIMIT 1];

        List<Asset> prior = PropertyTreatmentHistoryService.getPriorTreatments(a.Id);

        System.assertEquals(1, prior.size());
        System.assertEquals('432-1404', prior[0].EPA_Reg_Number_Last_Used__c);
    }

    @isTest
    static void getPriorTreatments_nullAccount_throws() {
        try {
            PropertyTreatmentHistoryService.getPriorTreatments(null);
            System.assert(false, 'Expected AuraHandledException');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @isTest
    static void getTopologyForIncident_emptyIncident_returnsEmpty() {
        // No Incident records inserted — passing a fake Id still resolves
        // to the "no linked cases" early return.
        Id fakeIncidentId = '01i000000000000AAA';

        PropertyTreatmentHistoryService.PropertyTopology topo =
            PropertyTreatmentHistoryService.getTopologyForIncident(fakeIncidentId);

        System.assertNotEquals(null, topo);
        System.assert(topo.nodes.isEmpty(), 'No-asset incident should yield empty topology');
        System.assert(topo.summary.toLowerCase().contains('no assets'), 'Summary should report empty state');
    }

    @isTest
    static void getTopologyForIncident_nullId_throws() {
        try {
            PropertyTreatmentHistoryService.getTopologyForIncident(null);
            System.assert(false, 'Expected AuraHandledException');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }
}
