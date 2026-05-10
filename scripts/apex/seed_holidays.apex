// Seeds US federal + FL state Holiday records for 2026 + 2027 and links
// them to the Day Shift + Mosquito Season Extended OperatingHours templates
// from seed_service_territory.apex.
//
// Split out from seed_service_territory.apex because Holiday is a setup
// object; combining its DML with non-setup OperatingHours/ServiceTerritory
// inserts in one transaction throws MIXED_DML_OPERATION.
//
// Idempotent: SOQL guards on Name (Holiday) and OperatingHoursId|HolidayId
// (junction). Reruns are safe.
//
// Run AFTER seed_service_territory.apex.
//   sf apex run --file scripts/apex/seed_holidays.apex --target-org <alias>

Map<String, Date> holidaySpec = new Map<String, Date>{
    // 2026 — US federal
    'New Year\'s Day 2026'    => Date.newInstance(2026, 1, 1),
    'MLK Day 2026'            => Date.newInstance(2026, 1, 19),
    'Presidents Day 2026'     => Date.newInstance(2026, 2, 16),
    'Memorial Day 2026'       => Date.newInstance(2026, 5, 25),
    'Juneteenth 2026'         => Date.newInstance(2026, 6, 19),
    'Independence Day 2026'   => Date.newInstance(2026, 7, 3),
    'Labor Day 2026'          => Date.newInstance(2026, 9, 7),
    'Veterans Day 2026'       => Date.newInstance(2026, 11, 11),
    'Thanksgiving 2026'       => Date.newInstance(2026, 11, 26),
    'Day After Thanksgiving 2026' => Date.newInstance(2026, 11, 27),
    'Christmas 2026'          => Date.newInstance(2026, 12, 25),
    // 2026 — FL state observances
    'Confederate Memorial Day 2026' => Date.newInstance(2026, 4, 26),
    // 2027 — US federal
    'New Year\'s Day 2027'    => Date.newInstance(2027, 1, 1),
    'MLK Day 2027'            => Date.newInstance(2027, 1, 18),
    'Presidents Day 2027'     => Date.newInstance(2027, 2, 15),
    'Memorial Day 2027'       => Date.newInstance(2027, 5, 31),
    'Juneteenth 2027'         => Date.newInstance(2027, 6, 18),
    'Independence Day 2027'   => Date.newInstance(2027, 7, 5),
    'Labor Day 2027'          => Date.newInstance(2027, 9, 6),
    'Veterans Day 2027'       => Date.newInstance(2027, 11, 11),
    'Thanksgiving 2027'       => Date.newInstance(2027, 11, 25),
    'Day After Thanksgiving 2027' => Date.newInstance(2027, 11, 26),
    'Christmas 2027'          => Date.newInstance(2027, 12, 24),
    'Confederate Memorial Day 2027' => Date.newInstance(2027, 4, 26)
};

Set<String> wantedHolidayNames = holidaySpec.keySet();
Map<String, Holiday> existingHolidays = new Map<String, Holiday>();
for (Holiday h : [SELECT Id, Name FROM Holiday WHERE Name IN :wantedHolidayNames]) {
    existingHolidays.put(h.Name, h);
}

List<Holiday> holidaysToInsert = new List<Holiday>();
for (String hName : holidaySpec.keySet()) {
    if (!existingHolidays.containsKey(hName)) {
        holidaysToInsert.add(new Holiday(
            Name = hName,
            ActivityDate = holidaySpec.get(hName),
            IsAllDay = true,
            IsRecurrence = false
        ));
    }
}
if (!holidaysToInsert.isEmpty()) insert holidaysToInsert;

// Link to OperatingHours via OperatingHoursHoliday (Day Shift + Mosquito Season
// observe holidays; Emergency Standby is intentionally not linked — 24/7
// cluster response runs through holidays).
Set<Id> holidayIds = new Set<Id>();
for (Holiday h : [SELECT Id FROM Holiday WHERE Name IN :wantedHolidayNames]) {
    holidayIds.add(h.Id);
}

Map<String, OperatingHours> ohByName = new Map<String, OperatingHours>();
for (OperatingHours oh : [SELECT Id, Name FROM OperatingHours
                           WHERE Name IN ('Day Shift', 'Mosquito Season Extended Hours (Apr-Oct)')]) {
    ohByName.put(oh.Name, oh);
}

try {
    Set<Id> observingOhIds = new Set<Id>();
    for (OperatingHours oh : ohByName.values()) observingOhIds.add(oh.Id);

    String linkSObject = 'OperatingHoursHoliday';
    Schema.SObjectType linkType = Schema.getGlobalDescribe().get(linkSObject);
    if (linkType != null && !observingOhIds.isEmpty() && !holidayIds.isEmpty()) {
        String soql = 'SELECT OperatingHoursId, HolidayId FROM ' + linkSObject +
                      ' WHERE OperatingHoursId IN :observingOhIds AND HolidayId IN :holidayIds';
        Set<String> existingLinks = new Set<String>();
        for (SObject link : Database.query(soql)) {
            existingLinks.add(String.valueOf(link.get('OperatingHoursId')) + '|' +
                              String.valueOf(link.get('HolidayId')));
        }
        List<SObject> linksToInsert = new List<SObject>();
        for (Id ohId : observingOhIds) {
            for (Id hId : holidayIds) {
                String key = String.valueOf(ohId) + '|' + String.valueOf(hId);
                if (!existingLinks.contains(key)) {
                    SObject link = linkType.newSObject();
                    link.put('OperatingHoursId', ohId);
                    link.put('HolidayId', hId);
                    linksToInsert.add(link);
                }
            }
        }
        if (!linksToInsert.isEmpty()) insert linksToInsert;
        System.debug('OperatingHoursHoliday links inserted: ' + linksToInsert.size());
    } else {
        System.debug('OperatingHoursHoliday object not present in org; skipping link section.');
    }
} catch (Exception e) {
    System.debug('OperatingHoursHoliday link section skipped: ' + e.getMessage());
}

System.debug('Holidays inserted this run: ' + holidaysToInsert.size());
System.debug('Holidays already present: ' + existingHolidays.size());
