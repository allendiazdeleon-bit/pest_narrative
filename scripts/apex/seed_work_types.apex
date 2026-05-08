// Seeds the 10 pest-side WorkType records for the masseyFlow / Massey Services
// demo (Ticket P1.5).
//
// Idempotent: every insert is guarded by a SOQL match on Name. A re-run is a
// no-op for any WorkType that already exists; only missing rows are inserted.
//
// Duration unit: Hours (DurationType = 'Hours'), matching the telco precedent
// at telcoFlow-neurafiber/scripts/apex/seed_work_types.apex. Salesforce stores
// EstimatedDuration as a Decimal with DurationType determining the unit; the
// telco demo standardized on Hours and so does this one.
//
// AutoCreateSA: The API field is ShouldAutoCreateSvcAppt (not
// AutoCreateServiceAppointment). All 10 are true except Termite Liquid
// Treatment, which uses the parent + child Service Appointment pattern (the
// pest analogue of telco's Tower Climb): the parent WO does not auto-create an
// SA; child WOs handle the per-zone soil-treatment work.
//
// Run with: sf apex run --file scripts/apex/seed_work_types.apex --target-org <alias>

// ------------------------------------------------------------------
// 1. Define the 10 pest WorkTypes
// ------------------------------------------------------------------
List<WorkType> targets = new List<WorkType>{
    new WorkType(Name = 'Quarterly Pest Service',         EstimatedDuration = 0.50, DurationType = 'Hours', ShouldAutoCreateSvcAppt = true,  Description = 'Standard residential GoGreen Pest route stop. Exterior perimeter sweep, web removal, and active-area spot treatment.'),
    new WorkType(Name = 'Pest Inspection (New)',          EstimatedDuration = 1.00, DurationType = 'Hours', ShouldAutoCreateSvcAppt = true,  Description = 'Pre-service home assessment for a new GoGreen Pest customer. Identifies entry points, conducive conditions, and active pressure.'),
    new WorkType(Name = 'Termite Inspection (Booster)',   EstimatedDuration = 1.00, DurationType = 'Hours', ShouldAutoCreateSvcAppt = true,  Description = 'Proactive booster inspection for a Termite Protection customer — checks Sentricon stations, conducive moisture, and visible swarmer activity.'),
    new WorkType(Name = 'Sentricon Install',              EstimatedDuration = 2.50, DurationType = 'Hours', ShouldAutoCreateSvcAppt = true,  Description = 'Install Sentricon Always Active bait stations on a 10-foot interval around the structure perimeter. Includes site mapping and customer walkthrough.'),
    new WorkType(Name = 'Sentricon Service',              EstimatedDuration = 1.00, DurationType = 'Hours', ShouldAutoCreateSvcAppt = true,  Description = 'Quarterly Sentricon station check: bait condition, station integrity, hit/no-hit log, and replenishment as needed.'),
    new WorkType(Name = 'Termite Liquid Treatment',       EstimatedDuration = 4.00, DurationType = 'Hours', ShouldAutoCreateSvcAppt = false, Description = 'Termidor SC liquid soil treatment, full structural perimeter. Parent WO does not auto-create an SA; child WOs handle the per-zone trench/rod/treat work (parent + child SA pattern).'),
    new WorkType(Name = 'Mosquito System Install',        EstimatedDuration = 3.00, DurationType = 'Hours', ShouldAutoCreateSvcAppt = true,  Description = 'Mosquito Hunter automated misting system install: perimeter tubing, nozzle placement, reservoir + pump commissioning, first charge.'),
    new WorkType(Name = 'Mosquito System Service',        EstimatedDuration = 1.00, DurationType = 'Hours', ShouldAutoCreateSvcAppt = true,  Description = 'Monthly Mosquito Hunter system service: reservoir charge, nozzle clean/replace, pressure check, and active-pressure spot fog as needed.'),
    new WorkType(Name = 'Mosquito Surge Area Treatment',  EstimatedDuration = 2.00, DurationType = 'Hours', ShouldAutoCreateSvcAppt = true,  Description = 'Cluster-response area treatment after a post-rainfall mosquito surge: BTI larvicide on standing water + ULV adulticide fog across affected lots.'),
    new WorkType(Name = 'Wasp / Stinging Insect Removal', EstimatedDuration = 1.50, DurationType = 'Hours', ShouldAutoCreateSvcAppt = true,  Description = 'PPE-required emergency removal of wasp, hornet, or yellowjacket nests. Includes nest knockdown, residual treatment, and customer safety briefing.')
};

// ------------------------------------------------------------------
// 2. Idempotency guard — SOQL by Name, only insert the missing ones
// ------------------------------------------------------------------
Set<String> wantedNames = new Set<String>();
for (WorkType wt : targets) wantedNames.add(wt.Name);

Map<String, WorkType> existingByName = new Map<String, WorkType>();
for (WorkType wt : [SELECT Id, Name FROM WorkType WHERE Name IN :wantedNames]) {
    existingByName.put(wt.Name, wt);
}

List<WorkType> toInsert = new List<WorkType>();
for (WorkType wt : targets) {
    if (!existingByName.containsKey(wt.Name)) toInsert.add(wt);
}
if (!toInsert.isEmpty()) {
    insert toInsert;
    System.debug('Inserted ' + toInsert.size() + ' new pest WorkType records.');
} else {
    System.debug('All 10 pest WorkType records already exist; nothing to insert.');
}

System.debug('Total pest-side WorkTypes now in org: ' + [SELECT count() FROM WorkType WHERE Name IN :wantedNames]);
