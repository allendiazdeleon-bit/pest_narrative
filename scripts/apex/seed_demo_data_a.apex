// Seeds the comprehensive Massey Services demo dataset for the masseyFlow
// project (Ticket P5.7). Authors ~120 customer Accounts across 5 Orange/
// Seminole-county ZIPs, ~120 Property Assets, ~280 child Assets (Sentricon
// stations, Mosquito Hunter nozzles, treatment perimeters), ~50 historical
// WorkOrders, the marquee Mosquito Surge cluster shape, and the named anchor
// personas (Sandra Reyes, David Kim, Lisa Chen, the Bennett family + 3
// Bennett-neighbors on Maple Ave) that drive the 9 demo scenes in
// docs/PEST_NARRATIVE.md.
//
// ---------------------------------------------------------------------------
// Recommended run order across the 6 seed scripts
// ---------------------------------------------------------------------------
// 1. seed_service_territory.apex   — ServiceTerritory + OperatingHours + Holidays
// 2. seed_work_types.apex          — 10 pest WorkTypes (referenced when this
//                                    script creates historical WorkOrders)
// 3. seed_work_plan_templates.apex — Work Plan Templates + Steps per WorkType
// 4. seed_demo_data.apex           — THIS SCRIPT. Accounts, Assets, WOs,
//                                    cluster shape (Incident + PSC + Cases +
//                                    PSCItems + dispatch WO).
// 5. seed_hazards.apex             — Hazard__c taxonomy (master-detail anchored
//                                    on the oldest WorkOrder, which this
//                                    script created in step 4 — so step 5
//                                    must run AFTER step 4).
// 6. (Custom Metadata)             — Upsell_Talk_Track__mdt + Service_Boundary__mdt
//                                    + Demo_Reply_Outcome__mdt are deployed via
//                                    sf project deploy start, NOT seeded here.
//
// MIXED_DML caveat: If any future addition involves Holiday or User-side DML
// alongside the Account/Asset DML below, split into separate transactions per
// the precedent set in seed_service_territory.apex.
//
// ---------------------------------------------------------------------------
// Idempotency strategy
// ---------------------------------------------------------------------------
// Every Massey-demo Account, Asset, WorkOrder, Incident, ProductServiceCampaign,
// PSCItem, Case, and Lead authored by this script carries the sentinel token
// "[MSY-DEMO]" in a stable text field (Account.Description, Asset.Description
// where present, WorkOrder.Subject, Incident.Subject, etc.). Re-runs SOQL-match
// on the sentinel + a per-record stable identifier (Name + ZIP for Accounts,
// the parent Account's Id + Equipment_Type__c for Assets, etc.), and skip any
// row that's already present. Result: re-runs are a no-op (or fill in any
// rows that failed in a previous partial run).
//
// Run with: sf apex run --file scripts/apex/seed_demo_data.apex --target-org <alias>
// ---------------------------------------------------------------------------

final String SENTINEL = '[MSY-DEMO]';

// =============================================================================
// 0. Locate the ServiceTerritory + WorkType ids the historical WOs reference
// =============================================================================
List<ServiceTerritory> sts = [SELECT Id FROM ServiceTerritory
                              WHERE Name = 'Massey Orlando Service Center' LIMIT 1];
if (sts.isEmpty()) {
    System.debug(LoggingLevel.WARN,
        'seed_demo_data.apex: ServiceTerritory "Massey Orlando Service Center" ' +
        'not found. Run seed_service_territory.apex first. Exiting cleanly.');
    return;
}
Id territoryId = sts[0].Id;

Map<String, Id> wtByName = new Map<String, Id>();
for (WorkType wt : [SELECT Id, Name FROM WorkType
                    WHERE Name IN ('Quarterly Pest Service',
                                   'Sentricon Service',
                                   'Mosquito System Service',
                                   'Mosquito Surge Area Treatment')]) {
    wtByName.put(wt.Name, wt.Id);
}
if (!wtByName.containsKey('Quarterly Pest Service')) {
    System.debug(LoggingLevel.WARN,
        'seed_demo_data.apex: WorkType "Quarterly Pest Service" not found. ' +
        'Run seed_work_types.apex first. Exiting cleanly.');
    return;
}

// =============================================================================
// 1. Account distribution spec — 120 accounts across 5 ZIPs
// =============================================================================
// Per-ZIP spec aligns with Service_Boundary__mdt (P2.4):
//   32828 Avalon Park / Waterford Lakes — 47 (cluster scenario zone)
//   32827 Lake Nona                     — 25 (David Kim signup neighborhood)
//   32789 Winter Park                   — 20
//   32765 Oviedo (Seminole County)      — 15
//   32703 Apopka (NW Orange County)     — 13
//   total                                  120
//
// Service-line tenure mix (applied across all ZIPs):
//   ~60% pest-only (GoGreen)
//   ~15% pest + mosquito
//   ~10% pest + termite
//   ~10% pest + termite + mosquito
//   ~ 5% lawn customer (no pest)

class ZipSpec {
    String zip;
    String city;
    Decimal lat;
    Decimal lng;
    Integer count;
    ZipSpec(String z, String c, Decimal la, Decimal ln, Integer n) {
        this.zip = z; this.city = c; this.lat = la; this.lng = ln; this.count = n;
    }
}

List<ZipSpec> zipSpecs = new List<ZipSpec>{
    new ZipSpec('32828', 'Orlando',     28.5450, -81.1880, 47),  // Avalon Park
    new ZipSpec('32827', 'Orlando',     28.3760, -81.2480, 25),  // Lake Nona
    new ZipSpec('32789', 'Winter Park', 28.6000, -81.3390, 20),
    new ZipSpec('32765', 'Oviedo',      28.6700, -81.2080, 15),
    new ZipSpec('32703', 'Apopka',      28.6940, -81.5320, 13)
};

// Stable street pools per ZIP. Streets are drawn deterministically by index so
// re-runs produce identical Account names. Maple Ave is reserved for the
// Bennett-cluster anchor in 32828 (slots 1-4 there).
Map<String, List<String>> streetsByZip = new Map<String, List<String>>{
    '32828' => new List<String>{'Maple Ave','Pine Brook Way','Avalon Park Blvd','Timberland Pointe','Waterford Lakes Dr','Eagle Creek Dr','Sweetwater Park Dr','Stoneybrook Pkwy','Lake Hart Dr','Tanja King Blvd'},
    '32827' => new List<String>{'Lake Nona Blvd','Tavistock Lakes Blvd','Narcoossee Rd','Northlake Pkwy','Wyndham Lakes Blvd','Boggy Creek Rd','Innovation Way','Medical City Dr'},
    '32789' => new List<String>{'Park Ave','Aloma Ave','Fairbanks Ave','Holt Ave','Lakemont Ave','Orange Ave','Genius Dr','Webster Ave'},
    '32765' => new List<String>{'Red Bug Lake Rd','Mitchell Hammock Rd','Alafaya Trl','Twin Rivers Dr','Lockwood Blvd','Slavia Rd','Carillon Dr'},
    '32703' => new List<String>{'Vick Rd','Park Ave','Rock Springs Rd','Marden Rd','Edgewater Dr','Ocoee Apopka Rd'}
};

// Stable pool of last names — drawn deterministically by index. 50 surnames is
// plenty for 120 accounts (with the per-ZIP street rotation each pair is unique).
List<String> lastNames = new List<String>{
    'Anderson','Bennett','Brooks','Carter','Chen','Cooper','Diaz','Edwards','Fisher','Garcia',
    'Gonzalez','Harris','Hayes','Hernandez','Holt','Jackson','Jenkins','Johnson','Jones','Kim',
    'King','Lewis','Lopez','Martinez','Miller','Mitchell','Morris','Murphy','Nguyen','Owens',
    'Parker','Patel','Perez','Phillips','Powell','Ramirez','Reed','Reyes','Rivera','Roberts',
    'Robinson','Rodriguez','Rogers','Russell','Sanchez','Sanders','Scott','Shah','Sullivan','Taylor',
    'Thomas','Thompson','Torres','Walker','Ward','Watson','Williams','Wilson','Wright','Young'
};

// Service-line tenure roster — stable cycle that yields the target mix when
// applied modulo the 120-account total:
//   60 pest-only, 15 pest+mosquito, 10 pest+termite, 10 pest+termite+mosquito, 5 lawn
// Cycle length 20: 12 pest, 3 pest+mosquito, 2 pest+termite, 2 pest+termite+mosquito, 1 lawn.
List<String> tenureCycle = new List<String>();
for (Integer i = 0; i < 12; i++) tenureCycle.add('pest');
for (Integer i = 0; i < 3;  i++) tenureCycle.add('pest_mosq');
for (Integer i = 0; i < 2;  i++) tenureCycle.add('pest_term');
for (Integer i = 0; i < 2;  i++) tenureCycle.add('pest_term_mosq');
for (Integer i = 0; i < 1;  i++) tenureCycle.add('lawn');

// =============================================================================
// 2. Build canonical Account spec list (~120 entries)
// =============================================================================
// Each entry is keyed by (Name, BillingPostalCode); the (Name, ZIP) pair is the
// idempotency key. Anchor personas (Sandra, Lisa, Bennett, Bennett-neighbors)
// are pre-injected into specific slots so the demo always finds them by Name.

class AcctSpec {
    String name;
    String firstName;
    String lastName;
    String street;
    String city;
    String zip;
    Decimal lat;
    Decimal lng;
    String tenure;        // pest / pest_mosq / pest_term / pest_term_mosq / lawn
    Datetime createdOverride; // for Sandra's 4-year tenure backdating; null = now
    String serviceGroup;  // optional Service_Group__c on the Property Asset
    Boolean inClusterZone;
    Boolean isPressureCandidate;
    Boolean isAnchor;     // marks named-persona accounts so we never reshuffle them
    AcctSpec() { this.inClusterZone = false; this.isPressureCandidate = false; this.isAnchor = false; }
}

List<AcctSpec> specs = new List<AcctSpec>();

// ---- 32828 Avalon Park anchor block (Maple Ave — Bennett family + 3 neighbors) ----
// The Bennett-cluster is the marquee Scene 5 trigger (UpsellCoachService keys
// on Service_Group__c = 'Maple-Ave-Bennett-Cluster' to detect the neighbor
// signal: 3 of 5 Maple Ave Accounts have Mosquito_System Assets / Eligible
// Mosquito upsell, so when Maria visits the Bennett residence on Maple, the
// neighbor signal fires).
ZipSpec ap = zipSpecs[0];

AcctSpec bennett = new AcctSpec();
bennett.name = 'Bennett Residence';
bennett.firstName = 'Mark'; bennett.lastName = 'Bennett';
bennett.street = '1247 Maple Ave';
bennett.city = ap.city; bennett.zip = ap.zip; bennett.lat = ap.lat; bennett.lng = ap.lng;
bennett.tenure = 'pest';   // pest-only — this is the upsell candidate
bennett.serviceGroup = 'Maple-Ave-Bennett-Cluster';
bennett.inClusterZone = true; bennett.isAnchor = true;
specs.add(bennett);

// 3 Bennett neighbors on Maple Ave with Mosquito Hunter installed (the
// "social signal" the upsell coach surfaces).
String[] neighborStreets = new String[]{ '1239 Maple Ave', '1255 Maple Ave', '1263 Maple Ave' };
String[] neighborSurnames = new String[]{ 'Henderson', 'Patel', 'Romero' };
String[] neighborFirsts   = new String[]{ 'David', 'Anita', 'Carlos' };
for (Integer i = 0; i < 3; i++) {
    AcctSpec n = new AcctSpec();
    n.name = neighborSurnames[i] + ' Residence';
    n.firstName = neighborFirsts[i]; n.lastName = neighborSurnames[i];
    n.street = neighborStreets[i];
    n.city = ap.city; n.zip = ap.zip; n.lat = ap.lat; n.lng = ap.lng;
    n.tenure = 'pest_mosq';   // pest + mosquito — the social signal
    n.serviceGroup = 'Maple-Ave-Bennett-Cluster';
    n.inClusterZone = true; n.isAnchor = true;
    specs.add(n);
}

// Lisa Chen — Mosquito Hunter customer in Avalon Park (in cluster). Scene 6
// "walk-on" — her property is one of the 47 affected by the cluster.
AcctSpec lisa = new AcctSpec();
lisa.name = 'Chen Residence (Lisa)';
lisa.firstName = 'Lisa'; lisa.lastName = 'Chen';
lisa.street = '4810 Pine Brook Way';
lisa.city = ap.city; lisa.zip = ap.zip; lisa.lat = ap.lat; lisa.lng = ap.lng;
lisa.tenure = 'pest_mosq';
lisa.inClusterZone = true; lisa.isAnchor = true;
specs.add(lisa);

// Fill the remaining 32828 slots (47 - 5 = 42) deterministically.
List<String> apStreets = streetsByZip.get('32828');
for (Integer i = 0; i < 42; i++) {
    AcctSpec s = new AcctSpec();
    String last = lastNames[Math.mod(i * 7, 60)];
    Integer firstIdx = Math.mod(i * 11 + 3, 60);
    String firstSeed = lastNames[firstIdx];
    String first = firstSeed.substring(0, Math.min(firstSeed.length(), 8));
    String street = apStreets[Math.mod(i + 2, apStreets.size() - 1) + 1];   // skip Maple Ave (index 0)
    String houseNum = String.valueOf(2000 + i * 13);
    s.name = last + ' Residence (' + houseNum + ')';
    s.firstName = first; s.lastName = last;
    s.street = houseNum + ' ' + street;
    s.city = ap.city; s.zip = ap.zip; s.lat = ap.lat; s.lng = ap.lng;
    s.tenure = tenureCycle[Math.mod(i, tenureCycle.size())];
    s.inClusterZone = true;
    // Flag a portion as proactive pest-pressure candidates (14 total across
    // all ZIPs — all 14 live in 32828 for the cluster overlap).
    if (i < 14) s.isPressureCandidate = true;
    specs.add(s);
}

// ---- 32827 Lake Nona — Sandra Reyes (anchor) + 24 fillers ----
// Sandra is a 4-year GoGreen customer, no termite, kitchen-ant call ready.
// Lake Nona puts her OUTSIDE the 32828 cluster so Scene 1 stays clean of the
// surge backdrop.
ZipSpec ln = zipSpecs[1];
AcctSpec sandra = new AcctSpec();
sandra.name = 'Reyes Residence (Sandra)';
sandra.firstName = 'Sandra'; sandra.lastName = 'Reyes';
sandra.street = '8420 Tavistock Lakes Blvd';
sandra.city = ln.city; sandra.zip = ln.zip; sandra.lat = ln.lat; sandra.lng = ln.lng;
sandra.tenure = 'pest';   // GoGreen-only — eligible for the termite upsell pitch
sandra.createdOverride = System.now().addDays(-4 * 365 - 30);  // ~4y + 30d ago
sandra.isAnchor = true;
specs.add(sandra);

List<String> lnStreets = streetsByZip.get('32827');
for (Integer i = 0; i < 24; i++) {
    AcctSpec s = new AcctSpec();
    String last = lastNames[Math.mod(i * 9 + 5, 60)];
    Integer firstIdx = Math.mod(i * 13 + 1, 60);
    String firstSeed = lastNames[firstIdx];
    String first = firstSeed.substring(0, Math.min(firstSeed.length(), 8));
    String street = lnStreets[Math.mod(i, lnStreets.size())];
    String houseNum = String.valueOf(7000 + i * 17);
    s.name = last + ' Residence (' + houseNum + ')';
    s.firstName = first; s.lastName = last;
    s.street = houseNum + ' ' + street;
    s.city = ln.city; s.zip = ln.zip; s.lat = ln.lat; s.lng = ln.lng;
    // Lake Nona tenure mix uses a different rotation offset to vary the data.
    s.tenure = tenureCycle[Math.mod(i + 7, tenureCycle.size())];
    specs.add(s);
}

// ---- 32789 Winter Park — 20 fillers ----
ZipSpec wp = zipSpecs[2];
List<String> wpStreets = streetsByZip.get('32789');
for (Integer i = 0; i < 20; i++) {
    AcctSpec s = new AcctSpec();
    String last = lastNames[Math.mod(i * 11 + 17, 60)];
    Integer firstIdx = Math.mod(i * 7 + 23, 60);
    String firstSeed = lastNames[firstIdx];
    String first = firstSeed.substring(0, Math.min(firstSeed.length(), 8));
    String street = wpStreets[Math.mod(i, wpStreets.size())];
    String houseNum = String.valueOf(400 + i * 11);
    s.name = last + ' Residence (' + houseNum + ')';
    s.firstName = first; s.lastName = last;
    s.street = houseNum + ' ' + street;
    s.city = wp.city; s.zip = wp.zip; s.lat = wp.lat; s.lng = wp.lng;
    s.tenure = tenureCycle[Math.mod(i + 3, tenureCycle.size())];
    specs.add(s);
}

// ---- 32765 Oviedo — 15 fillers ----
ZipSpec ov = zipSpecs[3];
List<String> ovStreets = streetsByZip.get('32765');
for (Integer i = 0; i < 15; i++) {
    AcctSpec s = new AcctSpec();
    String last = lastNames[Math.mod(i * 19 + 31, 60)];
    Integer firstIdx = Math.mod(i * 5 + 41, 60);
    String firstSeed = lastNames[firstIdx];
    String first = firstSeed.substring(0, Math.min(firstSeed.length(), 8));
    String street = ovStreets[Math.mod(i, ovStreets.size())];
    String houseNum = String.valueOf(1200 + i * 19);
    s.name = last + ' Residence (' + houseNum + ')';
    s.firstName = first; s.lastName = last;
    s.street = houseNum + ' ' + street;
    s.city = ov.city; s.zip = ov.zip; s.lat = ov.lat; s.lng = ov.lng;
    s.tenure = tenureCycle[Math.mod(i + 11, tenureCycle.size())];
    specs.add(s);
}

// ---- 32703 Apopka — 13 fillers ----
ZipSpec ak = zipSpecs[4];
List<String> akStreets = streetsByZip.get('32703');
for (Integer i = 0; i < 13; i++) {
    AcctSpec s = new AcctSpec();
    String last = lastNames[Math.mod(i * 23 + 47, 60)];
    Integer firstIdx = Math.mod(i * 17 + 13, 60);
    String firstSeed = lastNames[firstIdx];
    String first = firstSeed.substring(0, Math.min(firstSeed.length(), 8));
    String street = akStreets[Math.mod(i, akStreets.size())];
    String houseNum = String.valueOf(900 + i * 23);
    s.name = last + ' Residence (' + houseNum + ')';
    s.firstName = first; s.lastName = last;
    s.street = houseNum + ' ' + street;
    s.city = ak.city; s.zip = ak.zip; s.lat = ak.lat; s.lng = ak.lng;
    s.tenure = tenureCycle[Math.mod(i + 17, tenureCycle.size())];
    specs.add(s);
}

System.debug('Account specs assembled: ' + specs.size() + ' (target 120)');

// =============================================================================
// 3. Idempotency lookup — match existing Massey-demo Accounts by Name + ZIP
// =============================================================================
// Description carries the SENTINEL token — that's how we distinguish demo
// records from any real customer Accounts in the org.
Set<String> wantedNames = new Set<String>();
for (AcctSpec s : specs) wantedNames.add(s.name);

// Account.Description can't be filtered in SOQL; use Name+ZIP as the dedupe
// key. Risk: collides with real Accounts of the same Name+ZIP. Acceptable in
// a demo org. The SENTINEL still lives in Description for human inspection.
Map<String, Account> existingByKey = new Map<String, Account>();   // key: Name|ZIP
for (Account a : [SELECT Id, Name, BillingPostalCode, Description, Eligible_Upsells__c
                  FROM Account
                  WHERE Name IN :wantedNames]) {
    existingByKey.put(a.Name + '|' + a.BillingPostalCode, a);
}

// =============================================================================
// 4. Helper: tenure -> service-line + Eligible_Upsells__c roster
// =============================================================================
// primary Service_Line__c (on the Property Asset) maps from the tenure code:
//   pest, pest_mosq, pest_term, pest_term_mosq -> 'Pest'
//   lawn -> 'Lawn'
// Eligible_Upsells__c (multiselect) is the COMPLEMENT of what they have today,
// drawn from the 4-line catalog (Pest / Termite / Mosquito / Lawn).

Map<String, String> primaryLineByTenure = new Map<String, String>{
    'pest'           => 'Pest',
    'pest_mosq'      => 'Pest',
    'pest_term'      => 'Pest',
    'pest_term_mosq' => 'Pest',
    'lawn'           => 'Lawn'
};

Map<String, String> eligibleUpsellsByTenure = new Map<String, String>{
    'pest'           => 'Termite;Mosquito;Lawn',
    'pest_mosq'      => 'Termite;Lawn',
    'pest_term'      => 'Mosquito;Lawn',
    'pest_term_mosq' => 'Lawn',
    'lawn'           => 'Pest;Termite;Mosquito'
};

// =============================================================================
// 5. Insert missing Accounts
// =============================================================================
List<Account> toInsertAccts = new List<Account>();
List<AcctSpec> toInsertSpecs = new List<AcctSpec>();   // parallel — used to set Asset linkage

for (AcctSpec s : specs) {
    String key = s.name + '|' + s.zip;
    if (existingByKey.containsKey(key)) continue;

    Account a = new Account();
    a.Name = s.name;
    a.BillingStreet = s.street;
    a.BillingCity = s.city;
    a.BillingState = 'FL';
    a.BillingPostalCode = s.zip;
    a.BillingCountry = 'US';
    a.Description = SENTINEL + ' ' + s.tenure + ' tenure | first=' + s.firstName + ' last=' + s.lastName;
    a.Eligible_Upsells__c = eligibleUpsellsByTenure.get(s.tenure);
    a.Phone = '(407) 555-' + String.valueOf(1000 + Math.mod(Math.abs((s.name + s.zip).hashCode()), 9000));
    toInsertAccts.add(a);
    toInsertSpecs.add(s);
}

if (!toInsertAccts.isEmpty()) {
    insert toInsertAccts;
    System.debug('Inserted ' + toInsertAccts.size() + ' new Massey demo Accounts.');
} else {
    System.debug('All Account specs already present — skipping insert.');
}

// CreatedDate is system-managed; for Sandra's 4-year backdate we use Test
// context normally, but in anonymous Apex this isn't available, so we record
// the intended createdAt via Description (already done above with the tenure
// label) — the demo presenter's "4-year tenure" claim is reinforced by the
// historical WO patterns seeded in section 9.

// Re-fetch the full Account map keyed by Name|ZIP for downstream linkage.
Map<String, Id> acctIdByKey = new Map<String, Id>();
for (Account a : [SELECT Id, Name, BillingPostalCode FROM Account
                  WHERE Name IN :wantedNames
                 ]) {
    acctIdByKey.put(a.Name + '|' + a.BillingPostalCode, a.Id);
}
System.debug('Total Massey demo Accounts now in org: ' + acctIdByKey.size());

// =============================================================================
// 6. Insert one Property Asset per Account (idempotent)
// =============================================================================
// Asset key: AccountId + Equipment_Type__c = 'Property'. Description carries
// the sentinel for re-run match.
Set<Id> allAccountIds = new Set<Id>(acctIdByKey.values());
Map<Id, Asset> propertyByAcctId = new Map<Id, Asset>();
for (Asset ast : [SELECT Id, AccountId, Service_Line__c, Equipment_Type__c,
                         Service_Group__c, Is_Pest_Pressure_Candidate__c
                  FROM Asset
                  WHERE AccountId IN :allAccountIds
                  AND Equipment_Type__c = 'Property']) {
    propertyByAcctId.put(ast.AccountId, ast);
}

List<Asset> propsToInsert = new List<Asset>();
Map<Id, AcctSpec> specByAcctId = new Map<Id, AcctSpec>();
for (AcctSpec s : specs) {
    Id acctId = acctIdByKey.get(s.name + '|' + s.zip);
    if (acctId == null) continue;
    specByAcctId.put(acctId, s);
    if (propertyByAcctId.containsKey(acctId)) continue;

    String primaryLine = primaryLineByTenure.get(s.tenure);
    // Lot size: 6,500 - 18,000 sqft varies deterministically.
    Integer lotSize = 6500 + Math.mod(Math.abs(s.name.hashCode()), 12000);

    Asset prop = new Asset(
        AccountId = acctId,
        Name = s.lastName + ' Property — ' + s.street,
        Description = SENTINEL + ' Primary property Asset for ' + s.name,
        Service_Line__c = primaryLine,
        Equipment_Type__c = 'Property',
        Property_Type__c = 'Single_Family',
        Lot_Size_Sqft__c = lotSize,
        Latitude = s.lat,
        Longitude = s.lng,
        Status = 'Installed',
        InstallDate = Date.today().addDays(-365 * 2),
        Is_Pest_Pressure_Candidate__c = s.isPressureCandidate,
        Service_Group__c = s.serviceGroup,
        // Light telemetry to make the Site step render well:
        Days_Since_Last_Service__c = 30 + Math.mod(Math.abs(s.name.hashCode()), 60),
        Pest_Pressure_Score__c = (s.isPressureCandidate ? 75 : 30) + Math.mod(Math.abs(s.name.hashCode()), 15)
    );
    propsToInsert.add(prop);
}
if (!propsToInsert.isEmpty()) {
    insert propsToInsert;
    System.debug('Inserted ' + propsToInsert.size() + ' Property Assets.');
}

// Refetch property map.
propertyByAcctId.clear();
for (Asset ast : [SELECT Id, AccountId FROM Asset
                  WHERE AccountId IN :allAccountIds
                  AND Equipment_Type__c = 'Property']) {
    propertyByAcctId.put(ast.AccountId, ast);
}

// =============================================================================
// 7. Insert child Assets (Sentricon stations, Mosquito nozzles, Treatment perimeters)
// =============================================================================
// Idempotency: per-property, we count existing children of each Equipment_Type__c
// against the spec count. If the count is at or above the spec, skip; otherwise
// insert the delta. (This means a partial run gets its delta filled in; a
// fully-seeded property is a no-op.)

Map<Id, Map<String, Integer>> existingChildCounts = new Map<Id, Map<String, Integer>>();
Set<Id> propertyIds = new Set<Id>();
for (Asset p : propertyByAcctId.values()) propertyIds.add(p.Id);

for (AggregateResult ar : [SELECT ParentId, Equipment_Type__c, COUNT(Id) ct
                           FROM Asset
                           WHERE ParentId IN :propertyIds
                           AND Equipment_Type__c IN ('Sentricon_Station','Mosquito_Nozzle','Treatment_Perimeter','Trap','Mosquito_System')
                           GROUP BY ParentId, Equipment_Type__c]) {
    Id pid = (Id) ar.get('ParentId');
    String etype = (String) ar.get('Equipment_Type__c');
    Integer ct = (Integer) ar.get('ct');
    if (!existingChildCounts.containsKey(pid)) existingChildCounts.put(pid, new Map<String, Integer>());
    existingChildCounts.get(pid).put(etype, ct);
}

List<Asset> childrenToInsert = new List<Asset>();

for (Id acctId : propertyByAcctId.keySet()) {
    Asset prop = propertyByAcctId.get(acctId);
    AcctSpec s = specByAcctId.get(acctId);
    if (s == null) continue;
    Map<String, Integer> existing = existingChildCounts.containsKey(prop.Id)
        ? existingChildCounts.get(prop.Id) : new Map<String, Integer>();

    // 7a. Treatment perimeter — 1 per property, all service lines.
    Integer existingPerim = existing.containsKey('Treatment_Perimeter') ? existing.get('Treatment_Perimeter') : 0;
    if (existingPerim < 1) {
        childrenToInsert.add(new Asset(
            AccountId = acctId,
            ParentId = prop.Id,
            Name = s.lastName + ' — Treatment Perimeter',
            Description = SENTINEL + ' Treatment perimeter marker',
            Service_Line__c = primaryLineByTenure.get(s.tenure),
            Equipment_Type__c = 'Treatment_Perimeter',
            Latitude = s.lat,
            Longitude = s.lng,
            Status = 'Installed'
        ));
    }

    // 7b. Sentricon stations — 6 per termite-protected property.
    Boolean hasTermite = (s.tenure == 'pest_term' || s.tenure == 'pest_term_mosq');
    if (hasTermite) {
        Integer existingSent = existing.containsKey('Sentricon_Station') ? existing.get('Sentricon_Station') : 0;
        Integer toAdd = 6 - existingSent;
        for (Integer k = 0; k < toAdd; k++) {
            childrenToInsert.add(new Asset(
                AccountId = acctId,
                ParentId = prop.Id,
                Name = s.lastName + ' — Sentricon Station #' + String.valueOf(existingSent + k + 1),
                Description = SENTINEL + ' Sentricon Always Active bait station',
                SerialNumber = 'SCN-' + s.zip + '-' + String.valueOf(Math.mod(Math.abs((String.valueOf(acctId) + String.valueOf(k)).hashCode()), 100000)),
                Service_Line__c = 'Termite',
                Equipment_Type__c = 'Sentricon_Station',
                Equipment_Model__c = 'Sentricon Always Active',
                Bait_Station_State__c = (k == 0 ? 'Activity' : 'Untouched'),
                Bait_Station_Hits_30d__c = (k == 0 ? 2 : 0),
                NFC_Tag_Id__c = 'NFC-SCN-' + acctId + '-' + String.valueOf(k),
                Status = 'Installed'
            ));
        }
    }

    // 7c. Mosquito system + nozzles — 1 system + 12 nozzles per Mosquito Hunter property.
    Boolean hasMosquito = (s.tenure == 'pest_mosq' || s.tenure == 'pest_term_mosq');
    if (hasMosquito) {
        Integer existingSys = existing.containsKey('Mosquito_System') ? existing.get('Mosquito_System') : 0;
        if (existingSys < 1) {
            childrenToInsert.add(new Asset(
                AccountId = acctId,
                ParentId = prop.Id,
                Name = s.lastName + ' — Mosquito Hunter Controller',
                Description = SENTINEL + ' Mosquito Hunter system controller',
                SerialNumber = 'MHS-' + s.zip + '-' + String.valueOf(Math.mod(Math.abs(String.valueOf(acctId).hashCode()), 100000)),
                Service_Line__c = 'Mosquito',
                Equipment_Type__c = 'Mosquito_System',
                Equipment_Model__c = 'Mosquito Hunter MK-IV',
                NFC_Tag_Id__c = 'NFC-MHS-' + acctId,
                Status = 'Installed'
            ));
        }
        Integer existingNoz = existing.containsKey('Mosquito_Nozzle') ? existing.get('Mosquito_Nozzle') : 0;
        Integer toAdd = 12 - existingNoz;
        for (Integer k = 0; k < toAdd; k++) {
            childrenToInsert.add(new Asset(
                AccountId = acctId,
                ParentId = prop.Id,
                Name = s.lastName + ' — Mosquito Nozzle #' + String.valueOf(existingNoz + k + 1),
                Description = SENTINEL + ' Mosquito Hunter perimeter nozzle',
                Service_Line__c = 'Mosquito',
                Equipment_Type__c = 'Mosquito_Nozzle',
                Status = 'Installed'
            ));
        }
    }

    // 7d. A trap on roughly 1 in 6 properties (visual variety in the demo).
    if (Math.mod(Math.abs(s.name.hashCode()), 6) == 0) {
        Integer existingTrap = existing.containsKey('Trap') ? existing.get('Trap') : 0;
        if (existingTrap < 1) {
            childrenToInsert.add(new Asset(
                AccountId = acctId,
                ParentId = prop.Id,
                Name = s.lastName + ' — Rodent Trap',
                Description = SENTINEL + ' Exterior tamper-resistant rodent bait station',
                Service_Line__c = primaryLineByTenure.get(s.tenure),
                Equipment_Type__c = 'Trap',
                Trap_Catch_Count_24h__c = 0,
                Status = 'Installed'
            ));
        }
    }
}

if (!childrenToInsert.isEmpty()) {
    insert childrenToInsert;
    System.debug('Inserted ' + childrenToInsert.size() + ' child Assets.');
}
