/**
 * DispatcherScenarioLoader — seeds a 30+ Service Appointment BACKLOG so
 * Ray (Orlando branch ops manager) can run optimization and watch the
 * Gantt fill in.
 *
 * What's seeded:
 *   - 4 individual technicians (Maria Lopez Primary, plus 3 borrowed FSL
 *     sample techs as Relocation members of Orlando Service Area)
 *   - 1 crew (Massey OSP Termite Crew, 3 members) for multi-hour
 *     Sentricon installs / whole-home tent fumigations
 *   - 31 Work Orders / Service Appointments — UNSCHEDULED — sitting in
 *     the dispatcher's backlog, ready to be assigned by optimization
 *   - Each SA carries FSL__GanttLabel__c, FSL__GanttIcon__c, and
 *     FSL__Emergency__c so it renders richly on the Gantt once scheduled
 *
 * Why backlog (and not a pre-scheduled bad plan): when SAs are pre-
 * assigned with SchedStartTime, the optimizer treats them as committed
 * and can only nudge a few. A pure backlog gives the optimizer full
 * latitude — which is what makes the Gantt visibly fill in front of
 * the audience.
 *
 * Idempotent: tagged via WO Description prefix '[masseyFlow]' so we
 * can clean up + replay without colliding with cluster Cases or
 * other demo data.
 */
public with sharing class DispatcherScenarioLoader {

    private static final String TAG = '[masseyFlow]';
    private static final String TERRITORY_NAME = 'Orlando Service Area';
    private static final List<String> LOCAL_TECH_NAMES = new List<String>{ 'Maria Lopez' };
    private static final List<String> BORROWED_TECH_NAMES = new List<String>{
        'Gloria Barnes', 'Paul Morrison', 'Ralph Clark'
    };
    private static final String CREW_NAME = 'Massey Termite Crew';
    private static final List<String> CREW_MEMBER_NAMES = new List<String>{
        'Harry Long', 'Jane Austin', 'Matthew Parker'
    };

    @AuraEnabled
    public static String load() {
        Integer cleaned = resetInternal();

        ServiceTerritory terr;
        try {
            terr = [SELECT Id, OperatingHoursId FROM ServiceTerritory
                     WHERE Name = :TERRITORY_NAME LIMIT 1];
        } catch (QueryException qe) {
            return 'No "' + TERRITORY_NAME + '" territory found. Run OrgBootstrap.ensureFoundation first.';
        }

        Map<String, ServiceResource> techsByName = new Map<String, ServiceResource>();
        Set<String> localSet = new Set<String>(LOCAL_TECH_NAMES);
        Set<String> wantedNames = new Set<String>(LOCAL_TECH_NAMES);
        wantedNames.addAll(BORROWED_TECH_NAMES);
        for (ServiceResource sr : [SELECT Id, Name FROM ServiceResource
                                     WHERE Name IN :wantedNames AND ResourceType = 'T']) {
            techsByName.put(sr.Name, sr);
        }
        if (techsByName.isEmpty()) {
            return 'No technician ServiceResources found. Cannot build dispatcher scenario.';
        }

        Set<Id> resourceIds = new Set<Id>();
        Set<Id> localResourceIds = new Set<Id>();
        for (ServiceResource sr : techsByName.values()) {
            resourceIds.add(sr.Id);
            if (localSet.contains(sr.Name)) localResourceIds.add(sr.Id);
        }

        List<ServiceTerritoryMember> stale = [SELECT Id FROM ServiceTerritoryMember
                                                WHERE ServiceTerritoryId = :terr.Id
                                                  AND ServiceResourceId IN :resourceIds];
        if (!stale.isEmpty()) delete stale;

        if (!localResourceIds.isEmpty()) {
            List<ServiceTerritoryMember> strayPrimaries = [SELECT Id, EffectiveEndDate FROM ServiceTerritoryMember
                                                            WHERE ServiceResourceId IN :localResourceIds
                                                              AND TerritoryType = 'P'
                                                              AND EffectiveEndDate = null];
            if (!strayPrimaries.isEmpty()) {
                for (ServiceTerritoryMember m : strayPrimaries) m.EffectiveEndDate = Date.today().addDays(-1);
                update strayPrimaries;
            }
        }

        Set<Id> hasPrimaryElsewhere = new Set<Id>();
        for (ServiceTerritoryMember m : [SELECT ServiceResourceId FROM ServiceTerritoryMember
                                           WHERE ServiceResourceId IN :resourceIds
                                             AND TerritoryType = 'P'
                                             AND EffectiveEndDate = null]) {
            hasPrimaryElsewhere.add(m.ServiceResourceId);
        }

        List<ServiceTerritoryMember> newMembers = new List<ServiceTerritoryMember>();
        for (ServiceResource sr : techsByName.values()) {
            String type = hasPrimaryElsewhere.contains(sr.Id) ? 'R' : 'P';
            newMembers.add(new ServiceTerritoryMember(
                ServiceResourceId = sr.Id,
                ServiceTerritoryId = terr.Id,
                TerritoryType = type,
                EffectiveStartDate = Date.today().addDays(-1),
                EffectiveEndDate = Date.today().addDays(14)
            ));
        }
        insert newMembers;

        ServiceResource crewResource = ensureCrew(terr.Id);

        List<Account> demoAccts = [SELECT Id, Name, PersonContactId,
                                          BillingStreet, BillingCity, BillingState, BillingPostalCode,
                                          (SELECT Id FROM Assets LIMIT 1)
                                     FROM Account
                                    WHERE AccountNumber LIKE :(DemoDataLoader.ACCOUNT_NUMBER_PREFIX + '%')
                                      AND BillingStreet != null
                                    ORDER BY AccountNumber LIMIT 50];
        if (demoAccts.size() < 31) {
            return 'Need at least 31 demo Accounts. Found ' + demoAccts.size() + '. Run DemoDataLoader.load first.';
        }

        Map<String, WorkType> wtByName = new Map<String, WorkType>();
        List<WorkType> wtUpdates = new List<WorkType>();
        Set<String> ptNames = new Set<String>{
            'GoGreen Quarterly Pest','Sentricon Install','Sentricon Re-baiting',
            'Booster Termite Inspection','Booster Pest Treatment','Mosquito Hunter Activation',
            'Mosquito Surge Area Treatment','Lawn Treatment','Whole-Home Tent Fumigation',
            'New Service Activation'
        };
        for (WorkType wt : [SELECT Id, Name, EstimatedDuration, DurationType, ShouldAutoCreateSvcAppt
                             FROM WorkType
                             WHERE Name IN :ptNames]) {
            Boolean changed = false;
            Integer mins = workTypeMinutes(wt);
            if (mins == null || mins > 120) {
                wt.EstimatedDuration = 120;
                wt.DurationType = 'Minutes';
                changed = true;
            }
            if (wt.ShouldAutoCreateSvcAppt != true) {
                wt.ShouldAutoCreateSvcAppt = true;
                changed = true;
            }
            if (changed) wtUpdates.add(wt);
            wtByName.put(wt.Name, wt);
        }
        if (!wtUpdates.isEmpty()) update wtUpdates;

        ensureBusinessHours(terr.OperatingHoursId);

        DateTime day = DateTime.newInstance(Date.today().addDays(1), Time.newInstance(0, 0, 0, 0));
        List<Job> jobs = buildJobPlan(day, techsByName, crewResource);

        DateTime windowEnd = DateTime.newInstance(Date.today().addDays(5), Time.newInstance(23, 59, 0, 0));

        List<Case> cases = new List<Case>();
        for (Integer i = 0; i < jobs.size() && i < demoAccts.size(); i++) {
            Job j = jobs[i];
            Account acct = demoAccts[i];
            cases.add(new Case(
                AccountId = acct.Id,
                ContactId = acct.PersonContactId,
                Subject = caseSubjectFor(j.workTypeName, acct.BillingStreet),
                Description = TAG + ' Originating service request for the ' + j.workTypeName + ' work order.',
                Origin = 'Phone',
                Priority = (j.priority == 'Emergency' ? 'High' : j.priority),
                Status = 'New'
            ));
        }
        insert cases;

        List<WorkOrder> wos = new List<WorkOrder>();
        for (Integer i = 0; i < jobs.size() && i < demoAccts.size(); i++) {
            Job j = jobs[i];
            Account acct = demoAccts[i];
            Id assetId = (acct.Assets != null && !acct.Assets.isEmpty()) ? acct.Assets[0].Id : null;
            String addr = acct.BillingStreet;
            wos.add(new WorkOrder(
                AccountId = acct.Id,
                ContactId = acct.PersonContactId,
                CaseId = cases[i].Id,
                AssetId = assetId,
                ServiceTerritoryId = terr.Id,
                WorkTypeId = wtByName.containsKey(j.workTypeName) ? wtByName.get(j.workTypeName).Id : null,
                Subject = j.workTypeName + ' — ' + addr,
                Status = 'New',
                Priority = j.priority,
                StartDate = day,
                EndDate = windowEnd,
                Street = addr,
                City = acct.BillingCity,
                State = acct.BillingState,
                PostalCode = acct.BillingPostalCode,
                Country = 'USA',
                Description = TAG + ' ' + j.notes
            ));
        }
        insert wos;

        Set<Id> woIds = new Map<Id, WorkOrder>(wos).keySet();
        Map<Id, ServiceAppointment> autoSaByWo = new Map<Id, ServiceAppointment>();
        for (ServiceAppointment sa : [SELECT Id, ParentRecordId, Duration FROM ServiceAppointment
                                        WHERE ParentRecordId IN :woIds]) {
            autoSaByWo.put(sa.ParentRecordId, sa);
        }

        List<ServiceAppointment> toUpdate = new List<ServiceAppointment>();
        for (Integer i = 0; i < wos.size(); i++) {
            Job j = jobs[i];
            Account acct = demoAccts[i];
            String addr = acct.BillingStreet;
            ServiceAppointment sa = autoSaByWo.get(wos[i].Id);
            if (sa == null) continue;

            sa.ServiceTerritoryId = terr.Id;
            sa.Subject = j.workTypeName + ' — ' + addr;
            sa.Status = 'None';
            sa.EarliestStartTime = day;
            sa.DueDate = windowEnd;
            sa.Street = addr;
            sa.City = acct.BillingCity;
            sa.State = acct.BillingState;
            sa.PostalCode = acct.BillingPostalCode;
            sa.Country = 'USA';
            sa.FSL__Emergency__c = j.isEmergency;
            sa.FSL__GanttLabel__c = j.workTypeName + ' · ' + addr;
            sa.FSL__GanttIcon__c = j.iconUrl;
            sa.Description = TAG + ' Backlog appointment awaiting scheduling.';
            toUpdate.add(sa);
        }
        if (!toUpdate.isEmpty()) update toUpdate;

        Integer totalSas = toUpdate.size();
        return 'Cleaned ' + cleaned + ' prior records. Loaded ' + cases.size() + ' Cases / '
            + wos.size() + ' WOs / ' + totalSas + ' unscheduled SAs (backlog). '
            + techsByName.size() + ' individual techs + 1 crew (' + CREW_NAME + ', '
            + CREW_MEMBER_NAMES.size() + ' members) in ' + TERRITORY_NAME
            + '. SLA window: ' + day.format('EEE MMM d') + ' 08:00 → '
            + windowEnd.format('EEE MMM d HH:mm') + '.';
    }

    @AuraEnabled
    public static String reset() {
        Integer n = resetInternal();
        return 'Cleaned ' + n + ' dispatcher demo records.';
    }

    private static Integer resetInternal() {
        Integer total = 0;
        Id terrId;
        try {
            terrId = [SELECT Id FROM ServiceTerritory WHERE Name = :TERRITORY_NAME LIMIT 1].Id;
        } catch (QueryException qe) { return 0; }

        List<WorkOrder> candidates = [SELECT Id, Description FROM WorkOrder
                                        WHERE ServiceTerritoryId = :terrId];
        List<Id> woIds = new List<Id>();
        for (WorkOrder w : candidates) {
            if (w.Description == null) continue;
            if (w.Description.contains(TAG)) woIds.add(w.Id);
        }
        if (woIds.isEmpty()) return 0;

        Set<Id> caseIds = new Set<Id>();
        for (WorkOrder w : [SELECT CaseId FROM WorkOrder WHERE Id IN :woIds]) {
            if (w.CaseId != null) caseIds.add(w.CaseId);
        }

        List<ServiceAppointment> sas = [SELECT Id FROM ServiceAppointment WHERE ParentRecordId IN :woIds];
        if (!sas.isEmpty()) {
            Set<Id> saIds = new Map<Id, ServiceAppointment>(sas).keySet();
            List<AssignedResource> ars = [SELECT Id FROM AssignedResource WHERE ServiceAppointmentId IN :saIds];
            if (!ars.isEmpty()) { delete ars; total += ars.size(); }
            delete sas; total += sas.size();
        }
        List<WorkOrder> wos = [SELECT Id FROM WorkOrder WHERE Id IN :woIds];
        if (!wos.isEmpty()) { delete wos; total += wos.size(); }
        if (!caseIds.isEmpty()) {
            List<Case> cases = [SELECT Id FROM Case WHERE Id IN :caseIds];
            if (!cases.isEmpty()) { delete cases; total += cases.size(); }
        }
        return total;
    }

    private class Job {
        String workTypeName;
        String priority;
        String notes;
        String iconUrl;
        Boolean isEmergency;
    }

    private static Job mkJob(String wt, String pri, String notes) {
        Job j = new Job();
        j.workTypeName = wt;
        j.priority = pri;
        j.notes = notes;
        j.isEmergency = (pri == 'Emergency');

        if (wt == 'Mosquito Surge Area Treatment')      j.iconUrl = '/img/icon/t4v35/utility/error.svg';
        else if (wt == 'Sentricon Install')             j.iconUrl = '/img/icon/t4v35/utility/asset_object.svg';
        else if (wt == 'Sentricon Re-baiting')          j.iconUrl = '/img/icon/t4v35/utility/checkin.svg';
        else if (wt == 'Booster Termite Inspection')    j.iconUrl = '/img/icon/t4v35/utility/insights.svg';
        else if (wt == 'Booster Pest Treatment')        j.iconUrl = '/img/icon/t4v35/utility/warning.svg';
        else if (wt == 'GoGreen Quarterly Pest')        j.iconUrl = '/img/icon/t4v35/utility/work_order_type.svg';
        else if (wt == 'Mosquito Hunter Activation')    j.iconUrl = '/img/icon/t4v35/utility/work_order_type.svg';
        else if (wt == 'Whole-Home Tent Fumigation')    j.iconUrl = '/img/icon/t4v35/utility/warning.svg';
        else if (wt == 'Lawn Treatment')                j.iconUrl = '/img/icon/t4v35/utility/checkin.svg';
        else if (wt == 'New Service Activation')        j.iconUrl = '/img/icon/t4v35/utility/work_order_type.svg';
        else                                             j.iconUrl = '/img/icon/t4v35/utility/case.svg';
        return j;
    }

    private static List<Job> buildJobPlan(DateTime day, Map<String, ServiceResource> techs, ServiceResource crew) {
        List<Job> jobs = new List<Job>();

        // ── Emergencies (3) ──
        jobs.add(mkJob('Mosquito Surge Area Treatment', 'Emergency', 'Cluster response — ULV fog + larvicide at breeding source.'));
        jobs.add(mkJob('Booster Pest Treatment',        'Emergency', 'Customer reporting active swarm — same-day truck roll.'));
        jobs.add(mkJob('Booster Termite Inspection',    'Emergency', 'Termite swarmers reported on-property.'));

        // ── High priority (5) ──
        jobs.add(mkJob('Booster Termite Inspection', 'High', ''));
        jobs.add(mkJob('Booster Termite Inspection', 'High', ''));
        jobs.add(mkJob('Booster Pest Treatment',     'High', ''));
        jobs.add(mkJob('Mosquito Hunter Activation', 'High', ''));
        jobs.add(mkJob('Mosquito Hunter Activation', 'High', ''));

        // ── Medium priority (12) ──
        jobs.add(mkJob('GoGreen Quarterly Pest', 'Medium', ''));
        jobs.add(mkJob('GoGreen Quarterly Pest', 'Medium', ''));
        jobs.add(mkJob('GoGreen Quarterly Pest', 'Medium', ''));
        jobs.add(mkJob('GoGreen Quarterly Pest', 'Medium', ''));
        jobs.add(mkJob('GoGreen Quarterly Pest', 'Medium', ''));
        jobs.add(mkJob('Sentricon Re-baiting',   'Medium', ''));
        jobs.add(mkJob('Sentricon Re-baiting',   'Medium', ''));
        jobs.add(mkJob('Sentricon Re-baiting',   'Medium', ''));
        jobs.add(mkJob('Lawn Treatment',         'Medium', ''));
        jobs.add(mkJob('Lawn Treatment',         'Medium', ''));
        jobs.add(mkJob('GoGreen Quarterly Pest', 'Medium', ''));
        jobs.add(mkJob('GoGreen Quarterly Pest', 'Medium', ''));

        // ── Low priority (10) ──
        jobs.add(mkJob('Sentricon Install',         'Low', ''));
        jobs.add(mkJob('Sentricon Install',         'Low', ''));
        jobs.add(mkJob('Sentricon Install',         'Low', ''));
        jobs.add(mkJob('Sentricon Install',         'Low', ''));
        jobs.add(mkJob('Sentricon Install',         'Low', ''));
        jobs.add(mkJob('Sentricon Install',         'Low', ''));
        jobs.add(mkJob('New Service Activation',    'Low', ''));
        jobs.add(mkJob('New Service Activation',    'Low', ''));
        jobs.add(mkJob('New Service Activation',    'Low', ''));
        jobs.add(mkJob('New Service Activation',    'Low', ''));

        if (crew != null) {
            jobs.add(mkJob('Whole-Home Tent Fumigation', 'High',
                'Crew-level work — optimizer should route this to the ' + CREW_NAME + '.'));
        }
        return jobs;
    }

    private static String caseSubjectFor(String workTypeName, String address) {
        String addr = (address == null) ? '' : ' at ' + address;
        if (workTypeName == 'Mosquito Surge Area Treatment') return 'Mosquito surge cluster response' + addr;
        if (workTypeName == 'Booster Pest Treatment')        return 'Active pest issue reported' + addr;
        if (workTypeName == 'Booster Termite Inspection')    return 'Termite swarmers reported' + addr;
        if (workTypeName == 'GoGreen Quarterly Pest')        return 'Quarterly GoGreen visit' + addr;
        if (workTypeName == 'Sentricon Install')             return 'Sentricon AlwaysActive install' + addr;
        if (workTypeName == 'Sentricon Re-baiting')          return 'Sentricon station re-baiting' + addr;
        if (workTypeName == 'Mosquito Hunter Activation')    return 'Mosquito Hunter system activation' + addr;
        if (workTypeName == 'Whole-Home Tent Fumigation')    return 'Whole-home tent fumigation scheduled' + addr;
        if (workTypeName == 'Lawn Treatment')                return 'Lawn service visit scheduled' + addr;
        if (workTypeName == 'New Service Activation')        return 'New service activation' + addr;
        return workTypeName + addr;
    }

    private static Integer workTypeMinutes(WorkType wt) {
        if (wt == null || wt.EstimatedDuration == null) return null;
        Decimal d = wt.EstimatedDuration;
        if (wt.DurationType == 'Hours') return Integer.valueOf(d * 60);
        return Integer.valueOf(d);
    }

    private static void ensureBusinessHours(Id operatingHoursId) {
        if (operatingHoursId == null) return;
        List<TimeSlot> slots = [SELECT Id, DayOfWeek, StartTime, EndTime FROM TimeSlot
                                  WHERE OperatingHoursId = :operatingHoursId];
        Time start = Time.newInstance(8, 0, 0, 0);
        Time stop  = Time.newInstance(17, 0, 0, 0);
        List<TimeSlot> updates = new List<TimeSlot>();
        for (TimeSlot ts : slots) {
            if (ts.StartTime != start || ts.EndTime != stop) {
                ts.StartTime = start;
                ts.EndTime = stop;
                updates.add(ts);
            }
        }
        if (!updates.isEmpty()) update updates;
    }

    private static ServiceResource ensureCrew(Id territoryId) {
        List<ServiceCrew> existingCrews = [SELECT Id, Name FROM ServiceCrew WHERE Name = :CREW_NAME LIMIT 1];
        ServiceCrew crew;
        if (existingCrews.isEmpty()) {
            crew = new ServiceCrew(Name = CREW_NAME, CrewSize = CREW_MEMBER_NAMES.size());
            insert crew;
        } else {
            crew = existingCrews[0];
        }

        Map<String, Id> memberSrIds = new Map<String, Id>();
        for (ServiceResource sr : [SELECT Id, Name FROM ServiceResource
                                     WHERE Name IN :CREW_MEMBER_NAMES AND ResourceType = 'T']) {
            memberSrIds.put(sr.Name, sr.Id);
        }
        Set<Id> alreadyLinked = new Set<Id>();
        for (ServiceCrewMember scm : [SELECT ServiceResourceId FROM ServiceCrewMember
                                        WHERE ServiceCrewId = :crew.Id]) {
            alreadyLinked.add(scm.ServiceResourceId);
        }
        List<ServiceCrewMember> newLinks = new List<ServiceCrewMember>();
        for (Id mid : memberSrIds.values()) {
            if (alreadyLinked.contains(mid)) continue;
            newLinks.add(new ServiceCrewMember(
                ServiceCrewId = crew.Id,
                ServiceResourceId = mid,
                StartDate = DateTime.newInstance(Date.today().addDays(-1), Time.newInstance(0,0,0,0))
            ));
        }
        if (!newLinks.isEmpty()) insert newLinks;

        List<ServiceResource> existingCrewSr = [SELECT Id, Name FROM ServiceResource
                                                  WHERE Name = :CREW_NAME AND ResourceType = 'C' LIMIT 1];
        ServiceResource crewSr;
        if (existingCrewSr.isEmpty()) {
            crewSr = new ServiceResource(
                Name = CREW_NAME,
                ResourceType = 'C',
                IsActive = true,
                ServiceCrewId = crew.Id
            );
            insert crewSr;
        } else {
            crewSr = existingCrewSr[0];
        }

        Set<Id> crewAndMemberIds = new Set<Id>{ crewSr.Id };
        crewAndMemberIds.addAll(memberSrIds.values());

        List<ServiceTerritoryMember> stale = [SELECT Id FROM ServiceTerritoryMember
                                                WHERE ServiceTerritoryId = :territoryId
                                                  AND ServiceResourceId IN :crewAndMemberIds];
        if (!stale.isEmpty()) delete stale;

        List<ServiceTerritoryMember> stms = new List<ServiceTerritoryMember>();
        for (Id rid : crewAndMemberIds) {
            stms.add(new ServiceTerritoryMember(
                ServiceResourceId = rid,
                ServiceTerritoryId = territoryId,
                TerritoryType = 'R',
                EffectiveStartDate = Date.today().addDays(-1),
                EffectiveEndDate = Date.today().addDays(14)
            ));
        }
        insert stms;
        return crewSr;
    }
}
