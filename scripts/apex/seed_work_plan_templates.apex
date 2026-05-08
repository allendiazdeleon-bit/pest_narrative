// Seeds 10 WorkPlanTemplate records (one per pest WorkType from P1.5) and
// ~60 WorkStepTemplate child records covering the 6 standard step categories
// (Safety_Critical, Safety_Site, Safety_Admin, Work_DeEnergize, Work_Execute,
// Work_ReEnergize). Hazard steps are NOT seeded at design time — they are
// created at runtime by the orchestrator's hazard-reporting flow (decision #13
// in ARCHITECTURE_PROPOSAL.md) via createRecord on WorkStep with
// Step_Category__c = 'Hazard'.
//
// Idempotent: every insert is guarded by a SOQL match on Name. A re-run is a
// no-op for any plan or step that already exists; only missing rows are
// inserted. Step uniqueness is established by the composite key
// (WorkPlanTemplate Name, WorkStepTemplate Name).
//
// LABEL POLICY: Step API names are domain-neutral and inherited from telco —
// Work_DeEnergize and Work_ReEnergize are NOT renamed in this script. The
// "Pre-Treatment Setup" / "Post-Treatment Verification" pest labels swap via
// Custom Labels in P2.1 (decision #20). This script only writes API names.
//
// LINK POLICY: Plans are linked to Work Types via the standard
// WorkPlanTemplate.WorkTypeId lookup. Steps are linked to plans via
// WorkPlanTemplate.WorkStepTemplate__c... actually no — the platform standard
// pattern is the WorkPlanTemplateEntry junction (parent = WorkPlanTemplate,
// child = WorkStepTemplate, ExecutionOrder drives sort). We populate that
// junction here.
//
// Run with:
//   sf apex run --file scripts/apex/seed_work_plan_templates.apex --target-org <alias>

// ------------------------------------------------------------------
// 0. Plan -> WorkType mapping (matches P1.5 seed_work_types.apex)
// ------------------------------------------------------------------
Map<String, String> planByWorkType = new Map<String, String>{
    'Quarterly Pest Service'         => 'Plan: Quarterly Pest Service',
    'Pest Inspection (New)'          => 'Plan: Pest Inspection (New)',
    'Termite Inspection (Booster)'   => 'Plan: Termite Inspection (Booster)',
    'Sentricon Install'              => 'Plan: Sentricon Install',
    'Sentricon Service'              => 'Plan: Sentricon Service',
    'Termite Liquid Treatment'       => 'Plan: Termite Liquid Treatment',
    'Mosquito System Install'        => 'Plan: Mosquito System Install',
    'Mosquito System Service'        => 'Plan: Mosquito System Service',
    'Mosquito Surge Area Treatment'  => 'Plan: Mosquito Surge Area Treatment',
    'Wasp / Stinging Insect Removal' => 'Plan: Wasp / Stinging Insect Removal'
};

// ------------------------------------------------------------------
// 1. Resolve WorkType IDs
// ------------------------------------------------------------------
Map<String, Id> workTypeIdByName = new Map<String, Id>();
for (WorkType wt : [SELECT Id, Name FROM WorkType WHERE Name IN :planByWorkType.keySet()]) {
    workTypeIdByName.put(wt.Name, wt.Id);
}
for (String wtName : planByWorkType.keySet()) {
    if (!workTypeIdByName.containsKey(wtName)) {
        System.debug(LoggingLevel.WARN, 'Missing WorkType: "' + wtName + '". Run scripts/apex/seed_work_types.apex first.');
    }
}

// ------------------------------------------------------------------
// 2. Insert missing WorkPlanTemplates (idempotent: SOQL by Name)
// ------------------------------------------------------------------
Set<String> wantedPlanNames = new Set<String>(planByWorkType.values());

Map<String, WorkPlanTemplate> existingPlanByName = new Map<String, WorkPlanTemplate>();
for (WorkPlanTemplate wpt : [SELECT Id, Name, WorkTypeId FROM WorkPlanTemplate WHERE Name IN :wantedPlanNames]) {
    existingPlanByName.put(wpt.Name, wpt);
}

List<WorkPlanTemplate> plansToInsert = new List<WorkPlanTemplate>();
for (String wtName : planByWorkType.keySet()) {
    String planName = planByWorkType.get(wtName);
    if (!existingPlanByName.containsKey(planName)) {
        plansToInsert.add(new WorkPlanTemplate(
            Name = planName,
            WorkTypeId = workTypeIdByName.get(wtName),
            Description = 'Auto-generated checklist for the "' + wtName + '" Work Type. Massey Services pest demo (P1.6).'
        ));
    }
}
if (!plansToInsert.isEmpty()) {
    insert plansToInsert;
    for (WorkPlanTemplate wpt : plansToInsert) existingPlanByName.put(wpt.Name, wpt);
}
System.debug('WorkPlanTemplates inserted this run: ' + plansToInsert.size());
System.debug('WorkPlanTemplates total in scope: ' + existingPlanByName.size());

// ------------------------------------------------------------------
// 3. Define WorkStepTemplate rows per plan
//
// Each row: planName, stepName, stepCategory, isCritical, sortOrder
// Category counts per plan are documented in the comment block above the
// rows. Every plan includes >= 1 Safety_Critical step (acceptance crit.).
// ------------------------------------------------------------------
class StepDef {
    String planName;
    String stepName;
    String stepCategory;
    Boolean isCritical;
    Integer sortOrder;
    StepDef(String p, String s, String c, Boolean ic, Integer so) {
        this.planName = p; this.stepName = s; this.stepCategory = c;
        this.isCritical = ic; this.sortOrder = so;
    }
}

List<StepDef> stepDefs = new List<StepDef>();

// --- Plan: Quarterly Pest Service (6 steps: 1 SC, 1 SS, 1 SA, 1 WD, 1 WE, 1 WR) ---
stepDefs.add(new StepDef('Plan: Quarterly Pest Service', 'PPE Verified (gloves, eye protection, closed-toe boots)', 'Safety_Critical', true,  10));
stepDefs.add(new StepDef('Plan: Quarterly Pest Service', 'Vehicle / Site Briefing — Pets, Children, Beehive Check',  'Safety_Site',     false, 20));
stepDefs.add(new StepDef('Plan: Quarterly Pest Service', 'Customer Identity & Service Address Confirmed',            'Safety_Admin',    false, 30));
stepDefs.add(new StepDef('Plan: Quarterly Pest Service', 'Pre-Treatment Perimeter Walk + Web/Activity Spot',         'Work_DeEnergize', false, 40));
stepDefs.add(new StepDef('Plan: Quarterly Pest Service', 'Apply GoGreen Perimeter Treatment + EPA Reg # Logged',     'Work_Execute',    false, 50));
stepDefs.add(new StepDef('Plan: Quarterly Pest Service', 'Verify Coverage + Customer Sign-Off (or Door Hanger)',     'Work_ReEnergize', false, 60));

// --- Plan: Pest Inspection (New) (5 steps: 1 SC, 1 SS, 1 SA, 1 WE, 1 WR) ---
stepDefs.add(new StepDef('Plan: Pest Inspection (New)', 'PPE Verified (gloves, eye protection, flashlight ready)',   'Safety_Critical', true,  10));
stepDefs.add(new StepDef('Plan: Pest Inspection (New)', 'Crawl Space / Attic Access Hazards Assessed',               'Safety_Site',     false, 20));
stepDefs.add(new StepDef('Plan: Pest Inspection (New)', 'Customer Walkthrough Agreement Signed',                     'Safety_Admin',    false, 30));
stepDefs.add(new StepDef('Plan: Pest Inspection (New)', 'Inspect Entry Points, Conducive Conditions, Active Pressure','Work_Execute',   false, 40));
stepDefs.add(new StepDef('Plan: Pest Inspection (New)', 'Findings Reviewed with Customer + Service Plan Proposed',   'Work_ReEnergize', false, 50));

// --- Plan: Termite Inspection (Booster) (5 steps: 1 SC, 1 SS, 1 SA, 1 WE, 1 WR) ---
stepDefs.add(new StepDef('Plan: Termite Inspection (Booster)', 'PPE Verified (gloves, knee pads for crawl space)',     'Safety_Critical', true,  10));
stepDefs.add(new StepDef('Plan: Termite Inspection (Booster)', 'Moisture / Wood-Soil Contact Hazards Noted',           'Safety_Site',     false, 20));
stepDefs.add(new StepDef('Plan: Termite Inspection (Booster)', 'Termite Protection Service Agreement on File',         'Safety_Admin',    false, 30));
stepDefs.add(new StepDef('Plan: Termite Inspection (Booster)', 'Inspect Sentricon Stations + Visible Swarmer Activity','Work_Execute',    false, 40));
stepDefs.add(new StepDef('Plan: Termite Inspection (Booster)', 'Booster Findings Reviewed + Next-Action Recommended',  'Work_ReEnergize', false, 50));

// --- Plan: Sentricon Install (8 steps: 2 SC, 1 SS, 1 SA, 1 WD, 2 WE, 1 WR) ---
stepDefs.add(new StepDef('Plan: Sentricon Install', 'PPE Verified (gloves, eye protection, steel-toe boots)',         'Safety_Critical', true,  10));
stepDefs.add(new StepDef('Plan: Sentricon Install', 'Sentricon AlwaysActive SDS Reviewed (active ingredient noviflumuron)', 'Safety_Critical', true,  20));
stepDefs.add(new StepDef('Plan: Sentricon Install', '811 Utility Locate Verified — Property Boundary Marked',          'Safety_Site',     false, 30));
stepDefs.add(new StepDef('Plan: Sentricon Install', 'Customer Signed Sentricon Install Agreement',                     'Safety_Admin',    false, 40));
stepDefs.add(new StepDef('Plan: Sentricon Install', 'Mark Station Locations on 10-ft Interval Around Structure',       'Work_DeEnergize', false, 50));
stepDefs.add(new StepDef('Plan: Sentricon Install', 'Drill Pilot Holes + Insert AlwaysActive Stations',                'Work_Execute',    false, 60));
stepDefs.add(new StepDef('Plan: Sentricon Install', 'Affix NFC Tag to Each Station + Photograph In-Place',             'Work_Execute',    false, 70));
stepDefs.add(new StepDef('Plan: Sentricon Install', 'Verify Spacing + Register Stations in Service Group',             'Work_ReEnergize', false, 80));

// --- Plan: Sentricon Service (5 steps: 1 SC, 1 SS, 1 SA, 1 WE, 1 WR) ---
stepDefs.add(new StepDef('Plan: Sentricon Service', 'PPE Verified (gloves, eye protection)',                            'Safety_Critical', true,  10));
stepDefs.add(new StepDef('Plan: Sentricon Service', 'Station-Access Hazards Cleared (mulch, irrigation, landscaping)',  'Safety_Site',     false, 20));
stepDefs.add(new StepDef('Plan: Sentricon Service', 'Service Visit Logged Against Termite Protection Agreement',        'Safety_Admin',    false, 30));
stepDefs.add(new StepDef('Plan: Sentricon Service', 'Open Each Station, Log Hit/No-Hit, Replenish Bait As Needed',      'Work_Execute',    false, 40));
stepDefs.add(new StepDef('Plan: Sentricon Service', 'Re-Seat Stations + Customer Walk-Around if Home',                  'Work_ReEnergize', false, 50));

// --- Plan: Termite Liquid Treatment (10 steps: 2 SC, 1 SS, 1 SA, 2 WD, 2 WE, 2 WR) ---
stepDefs.add(new StepDef('Plan: Termite Liquid Treatment', 'PPE Verified (chem-resistant gloves, eye protection, Tyvek)','Safety_Critical', true,  10));
stepDefs.add(new StepDef('Plan: Termite Liquid Treatment', 'Termidor SC SDS Reviewed + REI Confirmed (24h post-app)',     'Safety_Critical', true,  20));
stepDefs.add(new StepDef('Plan: Termite Liquid Treatment', '811 Utility Locate Verified + Trench Path Clear',             'Safety_Site',     false, 30));
stepDefs.add(new StepDef('Plan: Termite Liquid Treatment', 'Customer Notification Logged + RUP Application Authorized',  'Safety_Admin',    false, 40));
stepDefs.add(new StepDef('Plan: Termite Liquid Treatment', 'Trench Full Structural Perimeter (6" wide x 6" deep)',        'Work_DeEnergize', false, 50));
stepDefs.add(new StepDef('Plan: Termite Liquid Treatment', 'Mix Termidor SC at Label Rate + Verify EPA Reg # 7969-210',   'Work_DeEnergize', false, 60));
stepDefs.add(new StepDef('Plan: Termite Liquid Treatment', 'Apply Termidor SC to Trench (4 gal per 10 linear ft)',        'Work_Execute',    false, 70));
stepDefs.add(new StepDef('Plan: Termite Liquid Treatment', 'Sub-Slab Rod Treatment of Slab Penetrations + Expansion Joints','Work_Execute',  false, 80));
stepDefs.add(new StepDef('Plan: Termite Liquid Treatment', 'Backfill Trench + Restore Landscape Surface',                 'Work_ReEnergize', false, 90));
stepDefs.add(new StepDef('Plan: Termite Liquid Treatment', 'Post REI Notice + Customer Sign-Off + Treatment Photos Logged','Work_ReEnergize', false, 100));

// --- Plan: Mosquito System Install (8 steps: 2 SC, 1 SS, 1 SA, 1 WD, 2 WE, 1 WR) ---
stepDefs.add(new StepDef('Plan: Mosquito System Install', 'PPE Verified (gloves, eye protection, hearing protection)',  'Safety_Critical', true,  10));
stepDefs.add(new StepDef('Plan: Mosquito System Install', 'Pyrethrin Concentrate SDS Reviewed + REI Confirmed',          'Safety_Critical', true,  20));
stepDefs.add(new StepDef('Plan: Mosquito System Install', '811 Utility Locate Verified + Tubing Route Clear of Sprinklers','Safety_Site',   false, 30));
stepDefs.add(new StepDef('Plan: Mosquito System Install', 'Customer Signed Mosquito Hunter Install Agreement',           'Safety_Admin',    false, 40));
stepDefs.add(new StepDef('Plan: Mosquito System Install', 'Map Perimeter Tubing Route + Mark Nozzle Locations',          'Work_DeEnergize', false, 50));
stepDefs.add(new StepDef('Plan: Mosquito System Install', 'Run Tubing, Set Nozzles, Mount Reservoir + Pump Manifold',    'Work_Execute',    false, 60));
stepDefs.add(new StepDef('Plan: Mosquito System Install', 'First Charge: Prime System + Verify Each Nozzle Output',      'Work_Execute',    false, 70));
stepDefs.add(new StepDef('Plan: Mosquito System Install', 'Affix NFC Tag to Controller + Customer Smart-Schedule Setup', 'Work_ReEnergize', false, 80));

// --- Plan: Mosquito System Service (5 steps: 1 SC, 1 SS, 1 SA, 1 WE, 1 WR) ---
stepDefs.add(new StepDef('Plan: Mosquito System Service', 'PPE Verified (gloves, eye protection)',                       'Safety_Critical', true,  10));
stepDefs.add(new StepDef('Plan: Mosquito System Service', 'Yard Hazards Cleared (pets, children, neighboring lots)',     'Safety_Site',     false, 20));
stepDefs.add(new StepDef('Plan: Mosquito System Service', 'Service Visit Logged Against Mosquito Hunter Agreement',      'Safety_Admin',    false, 30));
stepDefs.add(new StepDef('Plan: Mosquito System Service', 'Charge Reservoir, Clean/Replace Nozzles, Pressure-Test',      'Work_Execute',    false, 40));
stepDefs.add(new StepDef('Plan: Mosquito System Service', 'Active-Pressure Spot Fog (if needed) + Customer Walk-Around', 'Work_ReEnergize', false, 50));

// --- Plan: Mosquito Surge Area Treatment (10 steps: 2 SC, 1 SS, 1 SA, 1 WD, 3 WE, 2 WR) ---
// Marquee cluster-response scenario from PEST_NARRATIVE Scene 8 + ARCHITECTURE_PROPOSAL § 7.
stepDefs.add(new StepDef('Plan: Mosquito Surge Area Treatment', 'PPE Verified (gloves, respirator, eye protection, Tyvek)','Safety_Critical', true,  10));
stepDefs.add(new StepDef('Plan: Mosquito Surge Area Treatment', 'BTI Larvicide + ULV Adulticide SDS Reviewed + REI Confirmed','Safety_Critical', true,  20));
stepDefs.add(new StepDef('Plan: Mosquito Surge Area Treatment', 'Weather Check — No Rain in Next 4 Hours, Wind <10 mph',  'Safety_Site',     false, 30));
stepDefs.add(new StepDef('Plan: Mosquito Surge Area Treatment', 'Permit-to-Treat Logged + Affected-Property Notifications Sent','Safety_Admin', false, 40));
stepDefs.add(new StepDef('Plan: Mosquito Surge Area Treatment', 'Locate Breeding Source + Mix/Calibrate ULV Fogger',      'Work_DeEnergize', false, 50));
stepDefs.add(new StepDef('Plan: Mosquito Surge Area Treatment', 'Apply BTI Larvicide to Standing Water Sources',          'Work_Execute',    false, 60));
stepDefs.add(new StepDef('Plan: Mosquito Surge Area Treatment', 'ULV Fog Affected-Lot Perimeters (cluster geography)',    'Work_Execute',    false, 70));
stepDefs.add(new StepDef('Plan: Mosquito Surge Area Treatment', 'Treat Identified Harborage Areas (vegetation, drains)',  'Work_Execute',    false, 80));
stepDefs.add(new StepDef('Plan: Mosquito Surge Area Treatment', 'Verify Nozzle Output + Coverage Pattern Photos',         'Work_ReEnergize', false, 90));
stepDefs.add(new StepDef('Plan: Mosquito Surge Area Treatment', 'Post REI Notices + Customer Door-Hangers (or Sign-Off)', 'Work_ReEnergize', false, 100));

// --- Plan: Wasp / Stinging Insect Removal (6 steps: 2 SC, 1 SS, 0 SA, 0 WD, 2 WE, 1 WR) ---
stepDefs.add(new StepDef('Plan: Wasp / Stinging Insect Removal', 'PPE Verified (full bee suit, gloves, veil, EpiPen on hand)','Safety_Critical', true,  10));
stepDefs.add(new StepDef('Plan: Wasp / Stinging Insect Removal', 'Customer Allergy Status Confirmed + Standoff Distance Set','Safety_Critical', true,  20));
stepDefs.add(new StepDef('Plan: Wasp / Stinging Insect Removal', 'Site Cleared (pets indoors, neighbors notified, kids inside)','Safety_Site',  false, 30));
stepDefs.add(new StepDef('Plan: Wasp / Stinging Insect Removal', 'Approach Nest + Apply Knockdown Aerosol (residual + contact)','Work_Execute',  false, 40));
stepDefs.add(new StepDef('Plan: Wasp / Stinging Insect Removal', 'Remove Nest + Apply Residual to Cavity / Entry Point',  'Work_Execute',    false, 50));
stepDefs.add(new StepDef('Plan: Wasp / Stinging Insect Removal', 'Customer Safety Briefing + Re-Activity Watch Window',   'Work_ReEnergize', false, 60));

System.debug('Total StepDef rows assembled: ' + stepDefs.size());

// ------------------------------------------------------------------
// 4. Idempotency guard — SOQL existing WorkStepTemplates by Name
//    (composite uniqueness is plan + step name; check both)
// ------------------------------------------------------------------
Set<String> wantedStepNames = new Set<String>();
for (StepDef sd : stepDefs) wantedStepNames.add(sd.stepName);

// Build a set of existing (planName, stepName) pairs already linked
// via WorkPlanTemplateEntry. This is the composite-key check that
// makes reruns safe even if two plans share a step name.
Set<String> existingPlanStepKeys = new Set<String>();
for (WorkPlanTemplateEntry wpte : [
    SELECT Id, WorkPlanTemplateId, WorkPlanTemplate.Name, WorkStepTemplateId, WorkStepTemplate.Name
    FROM WorkPlanTemplateEntry
    WHERE WorkPlanTemplate.Name IN :wantedPlanNames
      AND WorkStepTemplate.Name IN :wantedStepNames
]) {
    existingPlanStepKeys.add(wpte.WorkPlanTemplate.Name + '||' + wpte.WorkStepTemplate.Name);
}

// Pre-load existing WorkStepTemplate records so we can reuse them
// across plans where step names happen to match.
Map<String, Id> existingStepIdByName = new Map<String, Id>();
for (WorkStepTemplate wst : [SELECT Id, Name FROM WorkStepTemplate WHERE Name IN :wantedStepNames]) {
    existingStepIdByName.put(wst.Name, wst.Id);
}

// ------------------------------------------------------------------
// 5. Insert missing WorkStepTemplates (de-dup by Name)
// ------------------------------------------------------------------
Map<String, WorkStepTemplate> stepsToInsertByName = new Map<String, WorkStepTemplate>();
for (StepDef sd : stepDefs) {
    if (existingStepIdByName.containsKey(sd.stepName)) continue;
    if (stepsToInsertByName.containsKey(sd.stepName)) continue;
    stepsToInsertByName.put(sd.stepName, new WorkStepTemplate(
        Name = sd.stepName,
        Description = sd.stepName,
        Step_Category__c = sd.stepCategory,
        Is_Critical__c = sd.isCritical
    ));
}
if (!stepsToInsertByName.isEmpty()) {
    insert stepsToInsertByName.values();
    for (WorkStepTemplate wst : stepsToInsertByName.values()) {
        existingStepIdByName.put(wst.Name, wst.Id);
    }
}
System.debug('WorkStepTemplates inserted this run: ' + stepsToInsertByName.size());

// ------------------------------------------------------------------
// 6. Insert missing WorkPlanTemplateEntry junction rows
// ------------------------------------------------------------------
List<WorkPlanTemplateEntry> entriesToInsert = new List<WorkPlanTemplateEntry>();
for (StepDef sd : stepDefs) {
    String key = sd.planName + '||' + sd.stepName;
    if (existingPlanStepKeys.contains(key)) continue;

    WorkPlanTemplate plan = existingPlanByName.get(sd.planName);
    Id stepId = existingStepIdByName.get(sd.stepName);
    if (plan == null || stepId == null) {
        System.debug(LoggingLevel.WARN, 'Skipping junction (missing parent or step): ' + key);
        continue;
    }
    entriesToInsert.add(new WorkPlanTemplateEntry(
        WorkPlanTemplateId = plan.Id,
        WorkStepTemplateId = stepId,
        ExecutionOrder = sd.sortOrder
    ));
    existingPlanStepKeys.add(key);
}
if (!entriesToInsert.isEmpty()) insert entriesToInsert;

System.debug('WorkPlanTemplateEntry junctions inserted this run: ' + entriesToInsert.size());
System.debug('WorkPlanTemplateEntry junctions total in scope: ' + [
    SELECT count() FROM WorkPlanTemplateEntry WHERE WorkPlanTemplate.Name IN :wantedPlanNames
]);

// ------------------------------------------------------------------
// 7. Acceptance-criterion check: every plan has >= 1 Safety_Critical step
// ------------------------------------------------------------------
Map<Id, Integer> safetyCriticalByPlanId = new Map<Id, Integer>();
for (WorkPlanTemplateEntry wpte : [
    SELECT WorkPlanTemplateId, WorkStepTemplate.Step_Category__c
    FROM WorkPlanTemplateEntry
    WHERE WorkPlanTemplate.Name IN :wantedPlanNames
      AND WorkStepTemplate.Step_Category__c = 'Safety_Critical'
]) {
    Integer prior = safetyCriticalByPlanId.containsKey(wpte.WorkPlanTemplateId)
        ? safetyCriticalByPlanId.get(wpte.WorkPlanTemplateId) : 0;
    safetyCriticalByPlanId.put(wpte.WorkPlanTemplateId, prior + 1);
}
for (WorkPlanTemplate wpt : existingPlanByName.values()) {
    Integer count = safetyCriticalByPlanId.containsKey(wpt.Id) ? safetyCriticalByPlanId.get(wpt.Id) : 0;
    if (count < 1) {
        System.debug(LoggingLevel.ERROR, 'ACCEPTANCE FAIL — plan "' + wpt.Name + '" has no Safety_Critical steps.');
    }
}
System.debug('Acceptance check complete — ' + safetyCriticalByPlanId.size() + ' of ' + existingPlanByName.size() + ' plans have at least one Safety_Critical step.');
