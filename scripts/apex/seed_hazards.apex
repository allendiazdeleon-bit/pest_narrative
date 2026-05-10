// Seeds ~9 Hazard__c taxonomy records for the masseyFlow / Massey Services demo.
//
// These are reference / taxonomy hazards that represent the realistic safety
// surface a Massey field tech encounters across pest, termite, mosquito, and
// lawn routes in Central Florida. They power the Hazard step in the
// orchestrator and seed the picklist of "common hazards" the tech can clone
// onto a live Work Order in later phases.
//
// Idempotent: each hazard is keyed by a stable sentinel prefix at the head of
// Description__c (e.g. "[HZ-CHEM-RUP] ..."). Reruns SOQL-match on the prefix
// and skip any sentinel already present. Hazard__c.Name is AutoNumber
// (HAZ-{0000}) so the sentinel-in-Description approach is the cleanest stable
// key available without adding an External_Id__c field.
//
// Master-detail constraint: Hazard__c.Work_Order__c is master-detail and
// required, so these records cannot be parent-less. The script picks the
// oldest available WorkOrder as the taxonomy parent. If no WorkOrder exists
// in the org yet (early-phase scaffold), the script logs and exits cleanly —
// rerun after Work Orders are seeded (P3.x) and idempotency will kick in.
//
// Run with: sf apex run --file scripts/apex/seed_hazards.apex --target-org <alias>

// 1. Locate a parent WorkOrder for the taxonomy records --------------------
//    Master-detail requires a parent. We use the oldest WorkOrder in the org
//    as a stable "taxonomy anchor" — these records are reference data, not
//    incident reports tied to a specific job.
List<WorkOrder> anchorWos = [SELECT Id FROM WorkOrder ORDER BY CreatedDate ASC LIMIT 1];
if (anchorWos.isEmpty()) {
    System.debug(LoggingLevel.WARN,
        'seed_hazards.apex: no WorkOrder exists in the org yet. ' +
        'Hazard__c.Work_Order__c is master-detail (required), so taxonomy ' +
        'hazards cannot be inserted. Rerun after Work Orders are seeded ' +
        '(see P3.x). Exiting cleanly — script is idempotent.');
    return;
}
Id anchorWoId = anchorWos[0].Id;

// 2. Hazard taxonomy spec ---------------------------------------------------
//    Each entry: sentinel -> { description, severity }. The sentinel is the
//    stable idempotency key, embedded as the leading token of Description__c.
//    Status__c uses the picklist default ('Open') unless overridden — these
//    records are taxonomy templates, not actively-mitigated incidents, but
//    'Open' is the platform-default and a fine seed value.
class HazardSpec {
    String sentinel;
    String description;
    String severity;
    HazardSpec(String s, String d, String sev) {
        this.sentinel = s; this.description = d; this.severity = sev;
    }
}

List<HazardSpec> specs = new List<HazardSpec>{
    new HazardSpec(
        '[HZ-CHEM-RUP]',
        'Restricted-Use Pesticide (RUP) exposure risk during mixing, loading, or application. Tech must wear nitrile gloves, chemical-splash goggles, and long sleeves; verify SDS on file and applicator license category before use.',
        'High'),
    new HazardSpec(
        '[HZ-WASP-STING]',
        'Stinging insect encounter — paper wasps, yellow jackets, or hornets nesting under eaves, in soffits, or in ground voids. High risk during summer perimeter treatments. Carry epinephrine auto-injector if route includes known-allergic technicians.',
        'Medium'),
    new HazardSpec(
        '[HZ-DOG-BITE]',
        'Aggressive or unsecured dog on residential premises — most common safety incident on quarterly pest routes. Confirm pet status with customer at door before entering side yard or screen enclosure; do not proceed if dog is loose.',
        'Medium'),
    new HazardSpec(
        '[HZ-LADDER-FALL]',
        'Fall-from-height risk during overhead exterior treatment, soffit dusting, or attic-access entry. Inspect ladder feet, maintain three points of contact, and never stand above the second-from-top rung. Avoid ladder use in wet or windy conditions.',
        'High'),
    new HazardSpec(
        '[HZ-ATTIC-HEAT]',
        'Heat stress and confined-space exhaustion during attic inspections (rodent baiting, termite swarmer surveys). Central FL attic temps can exceed 140 F in summer; limit attic time to 10-15 minutes and hydrate before and after entry.',
        'High'),
    new HazardSpec(
        '[HZ-FIRE-ANT]',
        'Red imported fire ant (Solenopsis invicta) exposure during lawn, perimeter, and mound-treatment work. Multiple stings can trigger systemic reaction even in non-allergic individuals. Tuck pants into boots and treat upwind of mound.',
        'Medium'),
    new HazardSpec(
        '[HZ-SNAKE]',
        'Florida wildlife encounter — venomous snakes including eastern diamondback rattlesnake, water moccasin (cottonmouth), and coral snake near lake-edge, palmetto, and woodpile habitats. Use a flashlight in dim crawlspaces and never reach into voids unseen.',
        'Critical'),
    new HazardSpec(
        '[HZ-TICK]',
        'Tick exposure during perimeter, woodline, and tall-grass work — risk of Lyme disease, Rocky Mountain spotted fever, and ehrlichiosis in the Southeast US. Wear treated long sleeves, perform a full tick check at end of route, and report any embedded tick to the branch.',
        'Medium'),
    new HazardSpec(
        '[HZ-ALLERGEN]',
        'Allergen / hypersensitivity reaction risk — bee or wasp sting, fire ant, or pesticide-active-ingredient sensitivity. Techs with known allergies must carry prescribed epinephrine and disclose status to dispatcher; partner-tech protocol applies on cluster-response routes.',
        'High')
};

// 3. Idempotency check — find any sentinels already seeded -----------------
//    Description__c is a long-text field that can't be filtered in SOQL.
//    Fall back to a per-record-batch check: pull all Hazard__c records and
//    filter sentinels in Apex.
Set<String> existingSentinels = new Set<String>();
for (Hazard__c h : [SELECT Id, Description__c FROM Hazard__c LIMIT 2000]) {
    if (h.Description__c == null) continue;
    Integer endIdx = h.Description__c.indexOf(']');
    if (endIdx > 0 && h.Description__c.startsWith('[HZ-')) {
        existingSentinels.add(h.Description__c.substring(0, endIdx + 1));
    }
}

// 4. Build inserts ----------------------------------------------------------
List<Hazard__c> toInsert = new List<Hazard__c>();
for (HazardSpec spec : specs) {
    if (existingSentinels.contains(spec.sentinel)) continue;
    toInsert.add(new Hazard__c(
        Work_Order__c   = anchorWoId,
        Description__c  = spec.sentinel + ' ' + spec.description,
        Severity__c     = spec.severity,
        Status__c       = 'Open',
        Reported_At__c  = System.now(),
        Reported_By__c  = UserInfo.getUserId()
    ));
}

if (!toInsert.isEmpty()) insert toInsert;

System.debug('Hazard__c taxonomy total spec count: ' + specs.size());
System.debug('Hazard__c sentinels already present: ' + existingSentinels.size());
System.debug('Hazard__c records inserted this run: ' + toInsert.size());
System.debug('Anchor WorkOrder used: ' + anchorWoId);
