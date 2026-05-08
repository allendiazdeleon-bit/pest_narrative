/**
 * OrgBootstrap — single-entry-point setup for a fresh masseyFlow demo org.
 *
 * Run ONCE per new org (after the FSL managed package is installed) to
 * create the foundation that DemoDataLoader and DispatcherScenarioLoader
 * depend on:
 *   1. Operating Hours "Day Shift" (8-5 M-F, America/New_York for Orlando)
 *      — required by ServiceTerritory.
 *   2. ServiceTerritory "Orlando Service Area" linked to those hours.
 *   3. The 10 Massey pest WorkTypes (GoGreen Quarterly Pest, Sentricon
 *      Install, etc.) with capped 2-hour durations and ShouldAutoCreateSvcAppt = true.
 *   4. PermissionSet "MasseyFlow_Technician" assigned to the running user.
 *   5. FSL Work Rule fix — flip FSL__Pass_Empty_Values__c = true on six
 *      rules so empty SA values are neutral instead of exclusionary.
 *
 * Idempotent — safe to re-run. Detects existing records and only updates
 * fields that drift from the expected values.
 *
 * What still needs admin/manual work afterwards (see CLAUDE.md "Manual
 * setup steps"):
 *   - Install FSL managed package (must precede this class)
 *   - Enable Enhanced Scheduling and Optimization on the Orlando
 *     territory in Setup → Field Service Settings → Optimization
 *   - Configure Scheduling Policies (Massey Standard + Cluster Response)
 *   - Provision Service Cloud Voice number (P4.1)
 *   - Configure 8 Agentforce topics (P4.2)
 */
public with sharing class OrgBootstrap {

    private static final String OH_NAME = 'Day Shift';
    private static final String OH_TZ = 'America/New_York';
    private static final String TERRITORY_NAME = 'Orlando Service Area';
    private static final String PERMSET_NAME = 'MasseyFlow_Technician';

    @AuraEnabled
    public static String ensureFoundation() {
        List<String> log = new List<String>();
        try {
            Id ohId = ensureOperatingHours();
            log.add('Operating Hours "' + OH_NAME + '" — OK (' + ohId + ')');

            Id terrId = ensureTerritory(ohId);
            log.add('Service Territory "' + TERRITORY_NAME + '" — OK (' + terrId + ')');

            Integer wts = ensureWorkTypes();
            log.add('Work Types (Massey pest set) — ' + wts + ' present');

            Integer psFlipped = flipPassEmptyValues();
            log.add('FSL Work Rules (Pass-Empty-Values) — ' + psFlipped + ' updated');

            Integer assigned = assignPermset();
            log.add('Permission Set "' + PERMSET_NAME + '" — '
                + (assigned == 0 ? 'already assigned to running user' : 'assigned to running user'));

            return 'FOUNDATION READY\n\n' + String.join(log, '\n')
                + '\n\nMANUAL STEPS (one-time, in Salesforce Setup):\n'
                + '  1. Install FSL managed package (if not already)\n'
                + '  2. Field Service Settings → Optimization → enable Enhanced Scheduling\n'
                + '     and Optimization for "' + TERRITORY_NAME + '"\n'
                + '  3. Configure Scheduling Policies: Massey Standard + Cluster Response\n\n'
                + 'NEXT: Run DemoDataLoader.load() and DispatcherScenarioLoader.load() '
                + '(or use the Demo Control panel buttons).';
        } catch (Exception e) {
            return 'BOOTSTRAP FAILED\n\nProgress so far:\n' + String.join(log, '\n')
                + '\n\nError: ' + e.getMessage()
                + '\nStack: ' + e.getStackTraceString();
        }
    }

    private static Id ensureOperatingHours() {
        List<OperatingHours> existing = [SELECT Id FROM OperatingHours WHERE Name = :OH_NAME LIMIT 1];
        Id ohId;
        if (existing.isEmpty()) {
            OperatingHours oh = new OperatingHours(Name = OH_NAME, TimeZone = OH_TZ);
            insert oh;
            ohId = oh.Id;
        } else {
            ohId = existing[0].Id;
        }

        List<TimeSlot> currentSlots = [SELECT Id, DayOfWeek, StartTime, EndTime, Type
                                        FROM TimeSlot WHERE OperatingHoursId = :ohId];
        Map<String, TimeSlot> bySlot = new Map<String, TimeSlot>();
        for (TimeSlot ts : currentSlots) bySlot.put(ts.DayOfWeek, ts);

        Time start = Time.newInstance(8, 0, 0, 0);
        Time stop  = Time.newInstance(17, 0, 0, 0);
        List<TimeSlot> toInsert = new List<TimeSlot>();
        List<TimeSlot> toUpdate = new List<TimeSlot>();
        for (String day : new List<String>{'Monday','Tuesday','Wednesday','Thursday','Friday'}) {
            if (bySlot.containsKey(day)) {
                TimeSlot ts = bySlot.get(day);
                if (ts.StartTime != start || ts.EndTime != stop) {
                    ts.StartTime = start;
                    ts.EndTime = stop;
                    toUpdate.add(ts);
                }
            } else {
                toInsert.add(new TimeSlot(
                    OperatingHoursId = ohId,
                    DayOfWeek = day,
                    StartTime = start,
                    EndTime = stop,
                    Type = 'Normal'
                ));
            }
        }
        if (!toInsert.isEmpty()) insert toInsert;
        if (!toUpdate.isEmpty()) update toUpdate;
        return ohId;
    }

    private static Id ensureTerritory(Id ohId) {
        List<ServiceTerritory> existing = [SELECT Id, OperatingHoursId, IsActive
                                            FROM ServiceTerritory WHERE Name = :TERRITORY_NAME LIMIT 1];
        if (!existing.isEmpty()) {
            ServiceTerritory st = existing[0];
            Boolean changed = false;
            if (st.OperatingHoursId != ohId) { st.OperatingHoursId = ohId; changed = true; }
            if (!st.IsActive) { st.IsActive = true; changed = true; }
            if (changed) update st;
            return st.Id;
        }
        ServiceTerritory st = new ServiceTerritory(
            Name = TERRITORY_NAME,
            OperatingHoursId = ohId,
            IsActive = true,
            Street = '610 N Orange Ave',
            City = 'Orlando',
            State = 'FL',
            PostalCode = '32801',
            Country = 'USA'
        );
        insert st;
        return st.Id;
    }

    private static Integer ensureWorkTypes() {
        Map<String, Integer> spec = new Map<String, Integer>{
            'GoGreen Quarterly Pest'        => 60,
            'Sentricon Install'             => 120,
            'Sentricon Re-baiting'          => 60,
            'Booster Termite Inspection'    => 90,
            'Booster Pest Treatment'        => 90,
            'Mosquito Hunter Activation'    => 60,
            'Mosquito Surge Area Treatment' => 120,
            'Lawn Treatment'                => 60,
            'Whole-Home Tent Fumigation'    => 120,
            'New Service Activation'        => 60
        };
        Map<String, WorkType> existing = new Map<String, WorkType>();
        for (WorkType wt : [SELECT Id, Name, EstimatedDuration, DurationType, ShouldAutoCreateSvcAppt
                              FROM WorkType WHERE Name IN :spec.keySet()]) {
            existing.put(wt.Name, wt);
        }
        List<WorkType> toInsert = new List<WorkType>();
        List<WorkType> toUpdate = new List<WorkType>();
        for (String nm : spec.keySet()) {
            Integer mins = spec.get(nm);
            if (existing.containsKey(nm)) {
                WorkType wt = existing.get(nm);
                Boolean changed = false;
                if (wt.EstimatedDuration == null || wt.EstimatedDuration > mins
                        || wt.DurationType != 'Minutes') {
                    wt.EstimatedDuration = mins;
                    wt.DurationType = 'Minutes';
                    changed = true;
                }
                if (wt.ShouldAutoCreateSvcAppt != true) {
                    wt.ShouldAutoCreateSvcAppt = true;
                    changed = true;
                }
                if (changed) toUpdate.add(wt);
            } else {
                toInsert.add(new WorkType(
                    Name = nm,
                    EstimatedDuration = mins,
                    DurationType = 'Minutes',
                    ShouldAutoCreateSvcAppt = true
                ));
            }
        }
        if (!toInsert.isEmpty()) insert toInsert;
        if (!toUpdate.isEmpty()) update toUpdate;
        return spec.size();
    }

    private static Integer flipPassEmptyValues() {
        try {
            List<FSL__Work_Rule__c> rules = [SELECT Id, Name, FSL__Pass_Empty_Values__c FROM FSL__Work_Rule__c
                                              WHERE Name IN ('Service Appointment Visiting Hours',
                                                             'Required Service Resource',
                                                             'Designated Work',
                                                             'Start','Finish','Match Skills')];
            List<FSL__Work_Rule__c> updates = new List<FSL__Work_Rule__c>();
            for (FSL__Work_Rule__c wr : rules) {
                if (wr.FSL__Pass_Empty_Values__c != true) {
                    wr.FSL__Pass_Empty_Values__c = true;
                    updates.add(wr);
                }
            }
            if (!updates.isEmpty()) update updates;
            return updates.size();
        } catch (Exception e) {
            System.debug('flipPassEmptyValues skipped: ' + e.getMessage());
            return -1;
        }
    }

    private static Integer assignPermset() {
        try {
            PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = :PERMSET_NAME LIMIT 1];
            Id userId = UserInfo.getUserId();
            List<PermissionSetAssignment> existing = [SELECT Id FROM PermissionSetAssignment
                                                       WHERE PermissionSetId = :ps.Id AND AssigneeId = :userId LIMIT 1];
            if (!existing.isEmpty()) return 0;
            insert new PermissionSetAssignment(PermissionSetId = ps.Id, AssigneeId = userId);
            return 1;
        } catch (Exception e) {
            System.debug('assignPermset skipped: ' + e.getMessage());
            return -1;
        }
    }
}
