// Seeds ServiceTerritory + 3 OperatingHours templates + US federal + FL state
// holidays for the masseyFlow / Massey Services demo.
//
// Idempotent: every insert is guarded by a SOQL match on Name (or on
// OperatingHoursId for child TimeSlots, ActivityDate for Holidays). Reruns
// are safe and will not duplicate records.
//
// Run with: sf apex run --file scripts/apex/seed_service_territory.apex --target-org <alias>
//
// MIXED_DML caveat: Holiday is a setup object. If your org throws
// MIXED_DML_OPERATION when this script combines Holiday DML with
// ServiceTerritory/OperatingHours DML in a single transaction, run the
// script twice — the second run will skip the already-inserted records and
// complete only the Holiday section (or vice versa). Both runs are
// idempotent.

String tz = 'America/New_York';

// 1. OperatingHours templates ------------------------------------------------
//    Day Shift                              — standard quarterly-pest-tech route window, Mon–Sat 7a–6p
//    Mosquito Season Extended Hours (Apr–Oct) — evening dusk-application coverage during FL mosquito peak, Mon–Sat 7a–8p
//    Emergency Standby                      — 24/7 cluster-response coverage (post-rainfall mosquito surge, swarming termite events)
Map<String, OperatingHours> existingOh = new Map<String, OperatingHours>();
for (OperatingHours oh : [SELECT Id, Name FROM OperatingHours
                          WHERE Name IN ('Day Shift',
                                         'Mosquito Season Extended Hours (Apr-Oct)',
                                         'Emergency Standby')]) {
    existingOh.put(oh.Name, oh);
}

List<OperatingHours> ohToInsert = new List<OperatingHours>();
if (!existingOh.containsKey('Day Shift')) {
    ohToInsert.add(new OperatingHours(Name = 'Day Shift', TimeZone = tz,
        Description = 'Standard quarterly-pest-tech route window, Mon-Sat 7a-6p.'));
}
if (!existingOh.containsKey('Mosquito Season Extended Hours (Apr-Oct)')) {
    ohToInsert.add(new OperatingHours(Name = 'Mosquito Season Extended Hours (Apr-Oct)', TimeZone = tz,
        Description = 'FL mosquito peak (Apr-Oct) — evening dusk-application coverage, Mon-Sat 7a-8p.'));
}
if (!existingOh.containsKey('Emergency Standby')) {
    ohToInsert.add(new OperatingHours(Name = 'Emergency Standby', TimeZone = tz,
        Description = '24/7 cluster-response coverage (post-rainfall mosquito surge, swarming termite events).'));
}
if (!ohToInsert.isEmpty()) insert ohToInsert;

Map<String, OperatingHours> ohByName = new Map<String, OperatingHours>();
for (OperatingHours oh : [SELECT Id, Name FROM OperatingHours
                          WHERE Name IN ('Day Shift',
                                         'Mosquito Season Extended Hours (Apr-Oct)',
                                         'Emergency Standby')]) {
    ohByName.put(oh.Name, oh);
}

// TimeSlots — only insert if missing per OperatingHours
Set<Id> ohIds = new Set<Id>();
for (OperatingHours oh : ohByName.values()) ohIds.add(oh.Id);
Set<Id> ohWithSlots = new Set<Id>();
for (TimeSlot ts : [SELECT OperatingHoursId FROM TimeSlot WHERE OperatingHoursId IN :ohIds]) {
    ohWithSlots.add(ts.OperatingHoursId);
}

List<String> monSat = new List<String>{'Monday','Tuesday','Wednesday','Thursday','Friday','Saturday'};
List<String> allDays = new List<String>{'Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'};

List<TimeSlot> slots = new List<TimeSlot>();

// Day Shift: Mon-Sat 7:00am - 6:00pm
OperatingHours dayShift = ohByName.get('Day Shift');
if (dayShift != null && !ohWithSlots.contains(dayShift.Id)) {
    for (String d : monSat) {
        slots.add(new TimeSlot(OperatingHoursId = dayShift.Id, DayOfWeek = d,
            StartTime = Time.newInstance(7, 0, 0, 0),
            EndTime = Time.newInstance(18, 0, 0, 0),
            Type = 'Normal'));
    }
}

// Mosquito Season Extended: Mon-Sat 7:00am - 8:00pm
OperatingHours mosqShift = ohByName.get('Mosquito Season Extended Hours (Apr-Oct)');
if (mosqShift != null && !ohWithSlots.contains(mosqShift.Id)) {
    for (String d : monSat) {
        slots.add(new TimeSlot(OperatingHoursId = mosqShift.Id, DayOfWeek = d,
            StartTime = Time.newInstance(7, 0, 0, 0),
            EndTime = Time.newInstance(20, 0, 0, 0),
            Type = 'Normal'));
    }
}

// Emergency Standby: 24/7 across all days
OperatingHours emerShift = ohByName.get('Emergency Standby');
if (emerShift != null && !ohWithSlots.contains(emerShift.Id)) {
    for (String d : allDays) {
        slots.add(new TimeSlot(OperatingHoursId = emerShift.Id, DayOfWeek = d,
            StartTime = Time.newInstance(0, 0, 0, 0),
            EndTime = Time.newInstance(23, 59, 0, 0),
            Type = 'Normal'));
    }
}
if (!slots.isEmpty()) insert slots;

// 2. ServiceTerritory --------------------------------------------------------
//    Single Massey-named territory; address: Massey Services HQ, Lake Mary, FL.
List<ServiceTerritory> existingSt = [SELECT Id, Name FROM ServiceTerritory
                                     WHERE Name = 'Massey Orlando Service Center' LIMIT 1];
ServiceTerritory st;
if (existingSt.isEmpty()) {
    st = new ServiceTerritory(
        Name = 'Massey Orlando Service Center',
        OperatingHoursId = ohByName.get('Day Shift').Id,
        IsActive = true,
        Description = 'Primary Massey Services branch for the masseyFlow demo. Covers Orange + Seminole counties; cluster ZIP 32828 (Avalon Park / Waterford Lakes).',
        Street = '610 Crescent Executive Ct',
        City = 'Lake Mary',
        State = 'FL',
        PostalCode = '32746',
        Country = 'USA',
        Latitude = 28.7589,
        Longitude = -81.3445
    );
    insert st;
} else {
    st = existingSt[0];
}

// Holiday + OperatingHoursHoliday DML moved to scripts/apex/seed_holidays.apex
// (must run in a separate transaction because Holiday is a setup object —
// MIXED_DML_OPERATION otherwise).

System.debug('OperatingHours total: ' + ohByName.size());
System.debug('TimeSlots inserted this run: ' + slots.size());
System.debug('ServiceTerritory: ' + st.Id + ' (' + st.Name + ')');
