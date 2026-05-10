// Part B of seed_demo_data.apex — cluster shape only (Mosquito Surge ZIP 32828).
// Run AFTER seed_demo_data_a.apex.
//
// Rewritten to drop the dependency on the in-memory `specs` list (which would
// force re-including 25KB of literal data and exceed the anonymous-Apex size
// limit). Re-queries the Accounts seeded by Part A to anchor the cluster.
//
// Skipped vs the original spec:
//   - Section 8 (David Kim Lead): manual / standalone
//   - Section 9 (~50 historical WorkOrders): nice-to-have demo backstory
//   - Section 11 (summary stats): replaced by terminal SOQL counts at the end.
//
// Idempotent: SOQL guards by SENTINEL prefix in Subject/Description fields.

final String SENTINEL = '[MSY-DEMO]';

// Locate ServiceTerritory + cluster-relevant WorkType
List<ServiceTerritory> sts = [SELECT Id FROM ServiceTerritory
                              WHERE Name = 'Massey Orlando Service Center' LIMIT 1];
if (sts.isEmpty()) {
    System.debug(LoggingLevel.WARN, 'ServiceTerritory missing — run seed_service_territory.apex first.');
    return;
}
Id territoryId = sts[0].Id;

Map<String, Id> wtByName = new Map<String, Id>();
for (WorkType wt : [SELECT Id, Name FROM WorkType
                    WHERE Name = 'Mosquito Surge Area Treatment']) {
    wtByName.put(wt.Name, wt.Id);
}
Id surgeWtId = wtByName.get('Mosquito Surge Area Treatment');

// All 32828 (Avalon Park) Massey-demo accounts that Part A seeded
List<Account> cluster32828 = [SELECT Id, Name, BillingStreet, BillingCity, BillingPostalCode
                              FROM Account
                              WHERE BillingPostalCode = '32828'
                              AND BillingState = 'FL'
                              ORDER BY Name];
System.debug('Cluster anchor: ' + cluster32828.size() + ' Accounts in ZIP 32828.');
if (cluster32828.isEmpty()) {
    System.debug(LoggingLevel.WARN, 'No 32828 accounts — run seed_demo_data_a.apex first.');
    return;
}

// Find Lisa Chen for the parent dispatch WO anchor
Account lisaChen;
for (Account a : cluster32828) {
    if (a.Name.contains('Chen') || a.Name.toLowerCase().contains('lisa')) {
        lisaChen = a; break;
    }
}
if (lisaChen == null) lisaChen = cluster32828[0];   // fallback

// Lisa's Property Asset for the dispatch WO
List<Asset> lisaAssets = [SELECT Id FROM Asset
                          WHERE AccountId = :lisaChen.Id
                          AND Equipment_Type__c = 'Property' LIMIT 1];
Id lisaPropertyId = lisaAssets.isEmpty() ? null : lisaAssets[0].Id;

// =============================================================================
// 1. Cluster Incident (idempotent)
// =============================================================================
String incidentSubject = SENTINEL + ' Mosquito Surge — ZIP 32828';
List<Incident> existingIncs = [SELECT Id FROM Incident WHERE Subject = :incidentSubject LIMIT 1];
Incident clusterIncident;
if (existingIncs.isEmpty()) {
    clusterIncident = new Incident(
        Subject = incidentSubject,
        Description = 'Aedes aegypti surge in Avalon Park / Waterford Lakes following 3+ inches '
            + 'overnight rainfall. Standing water in clogged municipal storm drain at Avalon Park Blvd '
            + 'is the primary breeding source. ETR pending. Demo-magic flips this Incident from New to Active.',
        Circuit__c = 'ZIP-32828-Mosquito',
        Affected_Customers__c = 47,
        Outage_Latitude__c = 28.5450,
        Outage_Longitude__c = -81.1880,
        Status = 'New',
        Priority = 'High'
    );
    insert clusterIncident;
    System.debug('Inserted cluster Incident: ' + clusterIncident.Id);
} else {
    clusterIncident = existingIncs[0];
    System.debug('Cluster Incident already present.');
}

// =============================================================================
// 2. Cluster ProductServiceCampaign
// =============================================================================
String pscName = 'Mosquito Surge — ZIP 32828';
List<ProductServiceCampaign> existingPsc = [SELECT Id FROM ProductServiceCampaign
                                             WHERE ProductServiceCampaignName = :pscName LIMIT 1];
ProductServiceCampaign clusterPsc;
if (existingPsc.isEmpty()) {
    clusterPsc = new ProductServiceCampaign(
        ProductServiceCampaignName = pscName,
        Description = SENTINEL + ' Cluster response campaign for Mosquito Surge ZIP 32828. '
            + 'Demo-magic activation flips Status to Active.',
        Type = 'Service',
        Status = 'New',
        Priority = 'High',
        Trigger_Incident__c = clusterIncident.Id,
        StartDate = Date.today(),
        EndDate = Date.today().addDays(7)
    );
    try { insert clusterPsc; }
    catch (DmlException e) {
        // Fallback: insert with bare-minimum fields if Type/Priority picklists differ
        clusterPsc = new ProductServiceCampaign(
            ProductServiceCampaignName = pscName,
            Description = SENTINEL + ' Cluster response campaign for Mosquito Surge ZIP 32828.'
        );
        insert clusterPsc;
    }
    System.debug('Inserted cluster PSC: ' + clusterPsc.Id);
} else {
    clusterPsc = existingPsc[0];
    System.debug('Cluster PSC already present.');
}

// =============================================================================
// 3. 8 Cases anchored on Lisa Chen + 7 fillers
// =============================================================================
List<Account> caseAnchors = new List<Account>();
caseAnchors.add(lisaChen);
for (Integer i = 0; i < cluster32828.size() && caseAnchors.size() < 8; i++) {
    if (cluster32828[i].Id != lisaChen.Id) caseAnchors.add(cluster32828[i]);
}

Set<String> existingCaseSubjects = new Set<String>();
for (Case c : [SELECT Subject FROM Case WHERE Subject LIKE :(SENTINEL + ' Mosquito Surge case%')]) {
    existingCaseSubjects.add(c.Subject);
}
List<Case> casesToInsert = new List<Case>();
for (Account a : caseAnchors) {
    String subj = SENTINEL + ' Mosquito Surge case — ' + a.Name;
    if (existingCaseSubjects.contains(subj)) continue;
    casesToInsert.add(new Case(
        AccountId = a.Id,
        Subject = subj,
        Description = 'Customer reporting heavy mosquito activity following overnight storm. '
            + 'Anchored to cluster Incident ' + clusterIncident.Id + '.',
        Status = 'New',
        Priority = 'High',
        Origin = 'Phone'
    ));
}
if (!casesToInsert.isEmpty()) insert casesToInsert;
System.debug('Cluster Cases inserted this run: ' + casesToInsert.size());

// =============================================================================
// 4. PSCItems — one per 32828 Property Asset (PSCItem links to Asset, not Account)
// =============================================================================
Set<Id> clusterAcctIds = new Set<Id>();
for (Account a : cluster32828) clusterAcctIds.add(a.Id);

Map<Id, Id> propertyAssetByAcct = new Map<Id, Id>();
for (Asset p : [SELECT Id, AccountId FROM Asset
                WHERE Equipment_Type__c = 'Property' AND AccountId IN :clusterAcctIds]) {
    propertyAssetByAcct.put(p.AccountId, p.Id);
}

Set<Id> existingPscItemAssets = new Set<Id>();
for (ProductServiceCampaignItem psci : [SELECT AssetId FROM ProductServiceCampaignItem
                                         WHERE ProductServiceCampaignId = :clusterPsc.Id]) {
    existingPscItemAssets.add(psci.AssetId);
}
List<ProductServiceCampaignItem> pscItems = new List<ProductServiceCampaignItem>();
for (Id acctId : propertyAssetByAcct.keySet()) {
    Id assetId = propertyAssetByAcct.get(acctId);
    if (existingPscItemAssets.contains(assetId)) continue;
    pscItems.add(new ProductServiceCampaignItem(
        ProductServiceCampaignId = clusterPsc.Id,
        AssetId = assetId,
        Status = 'Pending'
    ));
}
if (!pscItems.isEmpty()) {
    try { insert pscItems; }
    catch (DmlException e) {
        pscItems.clear();
        for (Id acctId : propertyAssetByAcct.keySet()) {
            Id assetId = propertyAssetByAcct.get(acctId);
            if (existingPscItemAssets.contains(assetId)) continue;
            pscItems.add(new ProductServiceCampaignItem(ProductServiceCampaignId = clusterPsc.Id, AssetId = assetId));
        }
        if (!pscItems.isEmpty()) insert pscItems;
    }
}
System.debug('PSCItems inserted this run: ' + pscItems.size());

// =============================================================================
// 5. Parent dispatch WorkOrder
// =============================================================================
String dispatchWoSubject = SENTINEL + ' Mosquito Surge Area Treatment — ZIP 32828 dispatch';
List<WorkOrder> existingDispatchWo = [SELECT Id FROM WorkOrder WHERE Subject = :dispatchWoSubject LIMIT 1];
if (existingDispatchWo.isEmpty() && lisaPropertyId != null && surgeWtId != null) {
    WorkOrder dispatchWo = new WorkOrder(
        AccountId = lisaChen.Id,
        AssetId = lisaPropertyId,
        WorkTypeId = surgeWtId,
        ServiceTerritoryId = territoryId,
        Subject = dispatchWoSubject,
        Description = 'Parent dispatch WO for the Avalon Park mosquito surge cluster. '
            + 'BTI larvicide on standing water + ULV adulticide fog at the clogged storm-drain '
            + 'breeding source (Avalon Park Blvd). Tom Walker\'s team reassigned via Scene 7 EmergencyDivertOrchestrator.',
        Status = 'New',
        Priority = 'High',
        Linked_Incident__c = clusterIncident.Id,
        StartDate = System.now().addHours(2),
        EndDate = System.now().addHours(4),
        Street = '14000 Avalon Park Blvd', City = 'Orlando', State = 'FL', PostalCode = '32828', Country = 'US'
    );
    insert dispatchWo;
    System.debug('Inserted parent dispatch WO: ' + dispatchWo.Id);
} else if (!existingDispatchWo.isEmpty()) {
    System.debug('Parent dispatch WO already present.');
} else {
    System.debug(LoggingLevel.WARN, 'Skipped dispatch WO — Lisa Chen Property Asset or Mosquito Surge Area Treatment WorkType not found.');
}

// =============================================================================
// 6. Summary
// =============================================================================
Integer totalAccts = [SELECT COUNT() FROM Account WHERE BillingState = 'FL'];
Integer totalProps = [SELECT COUNT() FROM Asset WHERE Equipment_Type__c = 'Property'];
Integer totalChildren = [SELECT COUNT() FROM Asset WHERE Equipment_Type__c != 'Property' AND Equipment_Type__c != null];
Integer totalCases = [SELECT COUNT() FROM Case WHERE Subject LIKE :(SENTINEL + '%')];
Integer totalPscItems = [SELECT COUNT() FROM ProductServiceCampaignItem WHERE ProductServiceCampaignId = :clusterPsc.Id];

System.debug('=== seed_demo_data_b SUMMARY ===');
System.debug('Total FL Accounts:          ' + totalAccts);
System.debug('Total Property Assets:      ' + totalProps);
System.debug('Total Child Assets:         ' + totalChildren);
System.debug('Cluster Cases (sentinel):   ' + totalCases);
System.debug('Cluster PSCItems:           ' + totalPscItems);
System.debug('Cluster Incident Id:        ' + clusterIncident.Id);
System.debug('Cluster PSC Id:             ' + clusterPsc.Id);
