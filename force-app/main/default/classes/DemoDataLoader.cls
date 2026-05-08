/**
 * DemoDataLoader — orchestrates demo data for the Massey Services pest demo.
 *
 * Single-vertical pest control. PMT capital-program data is intentionally
 * NOT modeled (see PEST_NARRATIVE § Capital Programs).
 *
 * Public API:
 *   - load()                              — full pest demo data set
 *   - loadVariant(String)                 — DEPRECATED; delegates to load()
 *   - reset()                             — tear down (idempotent)
 *   - setDemoTime(Integer daysAgo)        — shift sensor timestamps
 *   - activateMockIncident()              — flip 8-call cluster Draft → Active
 *   - getClusterCalls()                   — cluster Cases for demoMagicActivateIncident
 *   - createPlanAndStepsForWo(Id)         — WorkPlan/WorkStep helper for a WO
 *
 * Demo-record tracking: every seeded record carries a marker tag in its
 * Description. Account.AccountNumber (MASSEYDEMO-) and Asset.SerialNumber
 * (MSY-) carry filterable prefixes so reset() can find the records
 * without scanning Description on every object.
 */
public with sharing class DemoDataLoader {

    private static final String DEMO_TAG = '[masseyFlow demo seed]';
    public static final String ACCOUNT_NUMBER_PREFIX = 'MASSEYDEMO-';
    private static final String ASSET_SERIAL_PREFIX = 'MSY-';

    // Persona / address generators (Orlando Metro)
    private static final List<List<String>> NAMED_PERSONAS = new List<List<String>>{
        new List<String>{'Sandra', 'Reyes'},
        new List<String>{'David', 'Kim'},
        new List<String>{'Lisa', 'Chen'},
        new List<String>{'Tom', 'Walker'},
        new List<String>{'Jordan', 'Martinez'},
        new List<String>{'Ray', 'Garcia'},
        new List<String>{'Maria', 'Lopez'},
        new List<String>{'Hector', 'Bennett'},
        new List<String>{'Carmen', 'Henderson'},
        new List<String>{'Roberto', 'Diaz'},
        new List<String>{'Sofia', 'Perez'},
        new List<String>{'Diego', 'Ramirez'},
        new List<String>{'Elena', 'Torres'},
        new List<String>{'Antonio', 'Flores'},
        new List<String>{'Lucia', 'Vargas'},
        new List<String>{'Fernando', 'Castro'},
        new List<String>{'Isabel', 'Morales'},
        new List<String>{'Javier', 'Ortega'},
        new List<String>{'Camila', 'Ruiz'},
        new List<String>{'Sebastian', 'Romero'},
        new List<String>{'Valeria', 'Mendoza'},
        new List<String>{'Andres', 'Silva'},
        new List<String>{'Natalia', 'Cruz'},
        new List<String>{'Pablo', 'Aguilar'},
        new List<String>{'Daniela', 'Vega'},
        new List<String>{'Manuel', 'Rivas'},
        new List<String>{'Adriana', 'Fuentes'},
        new List<String>{'Beatriz', 'Salazar'},
        new List<String>{'Ricardo', 'Acosta'},
        new List<String>{'Monica', 'Cortez'},
        new List<String>{'Eduardo', 'Esparza'},
        new List<String>{'Gabriela', 'Navarro'},
        new List<String>{'Tomas', 'Reyna'},
        new List<String>{'Marisol', 'Galvan'},
        new List<String>{'Oscar', 'Trevino'},
        new List<String>{'Renata', 'Bautista'},
        new List<String>{'Felipe', 'Ochoa'},
        new List<String>{'Veronica', 'Solis'},
        new List<String>{'Ignacio', 'Cardenas'},
        new List<String>{'Cristina', 'Pena'},
        new List<String>{'Arturo', 'Quintero'},
        new List<String>{'Esperanza', 'Tovar'},
        new List<String>{'Rafael', 'Estrada'},
        new List<String>{'Yolanda', 'Carrillo'},
        new List<String>{'Emilio', 'Padilla'},
        new List<String>{'Alondra', 'Bernal'},
        new List<String>{'Salvador', 'Avila'},
        new List<String>{'Rocio', 'Cabrera'},
        new List<String>{'Patricia', 'Hernandez'},
        new List<String>{'Miguel', 'Lopez'}
    };

    // Orlando-area streets (Avalon Park, Lake Nona, Waterford Lakes, Winter Park).
    private static final List<String> STREET_NAMES = new List<String>{
        'Avalon Park Blvd', 'Waterford Lakes Pkwy', 'Lake Nona Blvd', 'Narcoossee Rd',
        'Conroy Rd', 'Sand Lake Rd', 'Goldenrod Rd', 'Aloma Ave',
        'Maple St', 'Oak Ln', 'Pine Cir', 'Magnolia Dr',
        'Conway Rd', 'Curry Ford Rd', 'Semoran Blvd', 'Tuskawilla Rd',
        'Park Ave', 'Mills Ave', 'Edgewater Dr', 'Princeton St',
        'Orange Ave', 'Colonial Dr', 'Robinson St', 'Rosalind Ave',
        'Magnolia Ave', 'Westmoreland Dr', 'Lake Underhill Rd', 'Chickasaw Trl',
        'Goldenrod Park', 'University Blvd', 'Alafaya Trl', 'Rouse Rd',
        'Dean Rd', 'Howell Branch Rd', 'Aloma Park', 'Lake Howell Rd',
        'Lockwood Blvd', 'Tuskawilla Park', 'Red Bug Lake Rd', 'Lake Mary Blvd',
        'International Dr', 'Major Blvd', 'Apopka-Vineland', 'Conroy-Windermere',
        'Vineland Rd', 'Universal Blvd', 'Turkey Lake Rd', 'Apopka Blvd',
        'Hiawassee Rd', 'Pine Hills Rd'
    };

    // ZIPs covering the Orlando branch service area (Orange + Seminole counties).
    private static final List<String> ZIPS = new List<String>{
        '32828', '32827', '32825', '32826', '32792', '32708', '32750', '32779',
        '32801', '32803', '32804', '32806', '32812', '32814', '32817', '32819'
    };
    private static final String CLUSTER_ZIP = '32828';

    @AuraEnabled
    public static String load() {
        return loadCore();
    }

    @AuraEnabled
    public static String loadCore() {
        Integer resources    = loadServiceResources();
        Integer accounts     = loadCustomerAndAsset();
        Integer cluster      = loadMockCluster();
        Integer dispatchQ    = loadDispatchQueue();
        Integer proactive    = loadProactiveSensorRun();
        Integer workPlans    = loadWorkPlans();
        return 'Loaded ' + resources + ' ServiceResource personas, '
            + accounts + ' Accounts/Properties, '
            + cluster + ' cluster records, '
            + dispatchQ + ' dispatch queue WOs, '
            + proactive + ' proactive booster WOs/Cases, '
            + workPlans + ' WorkPlan/Step records (Massey pest demo).';
    }

    /**
     * Deprecated. Single-vertical pest build — the variant arg is ignored.
     */
    @AuraEnabled
    public static String loadVariant(String industry) {
        return load();
    }

    @AuraEnabled
    public static String reset() {
        Integer total = 0;

        Set<Id> demoAccountIds = new Map<Id, Account>(
            [SELECT Id FROM Account WHERE AccountNumber LIKE :(ACCOUNT_NUMBER_PREFIX + '%')]
        ).keySet();

        try {
            List<Incident> demoIncidents = [SELECT Id FROM Incident
                                             WHERE Subject LIKE 'Mosquito Surge%'
                                                OR Subject LIKE 'Demo_%'
                                                OR Subject LIKE 'Cluster%'
                                                OR Subject LIKE 'Termite Swarm%'];
            Set<Id> incIds = new Map<Id, Incident>(demoIncidents).keySet();
            if (!incIds.isEmpty()) {
                List<ProductServiceCampaign> camps = [SELECT Id FROM ProductServiceCampaign
                                                       WHERE Trigger_Incident__c IN :incIds];
                if (!camps.isEmpty()) { delete camps; total += camps.size(); }
            }
        } catch (Exception e) { System.debug('PSC reset skipped: ' + e.getMessage()); }

        if (!demoAccountIds.isEmpty()) {
            List<Case> cases = [SELECT Id FROM Case WHERE AccountId IN :demoAccountIds];
            if (!cases.isEmpty()) { delete cases; total += cases.size(); }
        }

        try {
            List<Incident> incs = [SELECT Id FROM Incident
                                    WHERE Subject LIKE 'Mosquito Surge%'
                                       OR Subject LIKE 'Demo_%'
                                       OR Subject LIKE 'Cluster%'
                                       OR Subject LIKE 'Termite Swarm%'];
            if (!incs.isEmpty()) { delete incs; total += incs.size(); }
        } catch (Exception e) { System.debug('Incident reset skipped: ' + e.getMessage()); }

        if (!demoAccountIds.isEmpty()) {
            List<WorkOrder> wos = [SELECT Id, ParentWorkOrderId FROM WorkOrder
                                    WHERE AccountId IN :demoAccountIds];
            Set<Id> woIds = new Map<Id, WorkOrder>(wos).keySet();
            if (!woIds.isEmpty()) {
                List<ServiceAppointment> sas = [SELECT Id FROM ServiceAppointment
                                                 WHERE ParentRecordId IN :woIds];
                if (!sas.isEmpty()) { delete sas; total += sas.size(); }

                List<WorkOrder> children = new List<WorkOrder>();
                List<WorkOrder> parents  = new List<WorkOrder>();
                for (WorkOrder w : wos) {
                    if (w.ParentWorkOrderId != null) children.add(w);
                    else parents.add(w);
                }
                if (!children.isEmpty()) { delete children; total += children.size(); }
                if (!parents.isEmpty())  { delete parents;  total += parents.size(); }
            }
        }

        List<Asset> assets = [SELECT Id FROM Asset WHERE SerialNumber LIKE :(ASSET_SERIAL_PREFIX + '%')];
        if (!assets.isEmpty()) { delete assets; total += assets.size(); }

        List<Account> accts = [SELECT Id FROM Account WHERE AccountNumber LIKE :(ACCOUNT_NUMBER_PREFIX + '%')];
        if (!accts.isEmpty()) { delete accts; total += accts.size(); }

        return 'Deleted ' + total + ' demo records.';
    }

    @AuraEnabled
    public static String setDemoTime(Integer daysAgo) {
        if (daysAgo == null) daysAgo = 0;
        DateTime cutoff = DateTime.now().addDays(-daysAgo);
        List<Asset> assets;
        try {
            assets = [SELECT Id, Last_Sensor_Reading__c FROM Asset
                       WHERE SerialNumber LIKE :(ASSET_SERIAL_PREFIX + '%') LIMIT 5000];
        } catch (Exception e) {
            return 'Last_Sensor_Reading__c field not deployed yet — skipping.';
        }
        for (Asset a : assets) {
            try { a.put('Last_Sensor_Reading__c', cutoff); } catch (Exception e) {}
        }
        if (!assets.isEmpty()) update assets;
        return 'Shifted ' + assets.size() + ' Asset Last_Sensor_Reading__c values to ' + cutoff + '.';
    }

    /**
     * Returns the cluster Cases pre-staged for the Mosquito Surge scenario,
     * sorted by Subject. Rendered by demoMagicActivateIncident as the
     * "incoming calls" list before activation.
     */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getClusterCalls() {
        List<Map<String, String>> calls = new List<Map<String, String>>();
        for (Case c : [SELECT Id, CaseNumber, Subject, Account.Name FROM Case
                        WHERE Subject LIKE 'Mosquitoes at%'
                           OR Subject LIKE 'Pest activity at%'
                        ORDER BY Subject LIMIT 8]) {
            String address = c.Subject.contains(' at ') ? c.Subject.substringAfter(' at ') : c.Subject;
            calls.add(new Map<String, String>{
                'caseNumber' => c.CaseNumber,
                'address'    => address,
                'caller'     => c.Account.Name
            });
        }
        return calls;
    }

    @AuraEnabled
    public static String activateMockIncident() {
        Integer count = 0;
        Set<Id> demoAccountIds = new Map<Id, Account>(
            [SELECT Id FROM Account WHERE AccountNumber LIKE :(ACCOUNT_NUMBER_PREFIX + '%')]
        ).keySet();

        if (!demoAccountIds.isEmpty()) {
            List<Case> cases = [SELECT Id, Status FROM Case WHERE AccountId IN :demoAccountIds];
            for (Case c : cases) {
                if (c.Status == 'Draft' || c.Status == 'New') { c.Status = 'Working'; count++; }
            }
            if (!cases.isEmpty()) update cases;
        }

        List<Incident> incs = [SELECT Id, StatusCode FROM Incident
                                WHERE Subject LIKE 'Mosquito Surge%'];
        for (Incident i : incs) {
            if (i.StatusCode == 'New' || i.StatusCode == 'Draft') { i.StatusCode = 'Active'; count++; }
        }
        if (!incs.isEmpty()) update incs;
        return 'Activated ' + count + ' cluster records.';
    }

    private static Integer loadCustomerAndAsset() {
        Integer existing = [SELECT count() FROM Account WHERE AccountNumber LIKE :(ACCOUNT_NUMBER_PREFIX + '%')];
        if (existing > 0) return 0;

        Id pa;
        try {
            pa = [SELECT Id FROM RecordType WHERE SObjectType='Account' AND DeveloperName='PersonAccount' LIMIT 1].Id;
        } catch (Exception e) {}

        List<String> addresses = new List<String>();
        for (Integer i = 0; i < 50; i++) {
            Integer streetNumber = 1400 + i * 47 + Math.mod(i, 13) * 11;
            String street = STREET_NAMES[Math.mod(i, STREET_NAMES.size())];
            addresses.add(streetNumber + ' ' + street);
        }

        List<Account> accts = new List<Account>();
        for (Integer i = 0; i < NAMED_PERSONAS.size() && i < 50; i++) {
            List<String> persona = NAMED_PERSONAS[i];
            Account a = new Account(
                FirstName     = persona[0],
                LastName      = persona[1],
                AccountNumber = ACCOUNT_NUMBER_PREFIX + String.valueOf(1000 + i),
                BillingStreet = addresses[i],
                BillingCity   = 'Orlando',
                BillingState  = 'FL',
                BillingPostalCode = (i < 8 ? CLUSTER_ZIP : ZIPS[Math.mod(i, ZIPS.size())]),
                Description   = DEMO_TAG + ' Massey customer persona'
            );
            if (pa != null) a.RecordTypeId = pa;
            accts.add(a);
        }
        insert accts;

        // 14 pest-pressure candidates spread across the customer base.
        Set<Integer> candidateIdx = new Set<Integer>{ 2, 8, 12, 15, 19, 22, 26, 30, 34, 37, 40, 43, 46, 49 };

        // Service mix:
        //   ~70% GoGreen Pest Prevention
        //   ~25% Termite Protection (Sentricon)
        //   ~15% Mosquito Hunter (overlap with above)
        //   ~10% Lawn (overlap)
        // First 8 are cluster targets in ZIP 32828.

        List<Asset> assets = new List<Asset>();
        for (Integer i = 0; i < accts.size(); i++) {
            Account a = accts[i];
            Boolean isCandidate = candidateIdx.contains(i);
            Boolean isCluster   = i < 8;

            String svcLine;
            if (isCluster) {
                svcLine = 'Mosquito Hunter';
            } else if (Math.mod(i, 4) == 0) {
                svcLine = 'Massey Termite Protection';
            } else if (Math.mod(i, 7) == 1) {
                svcLine = 'Mosquito Hunter';
            } else if (Math.mod(i, 9) == 2) {
                svcLine = 'Massey Lawn Service';
            } else {
                svcLine = 'GoGreen Pest Prevention';
            }

            Asset asset = new Asset(
                Name                  = addresses[i] + ' (' + svcLine + ')',
                AccountId             = a.Id,
                SerialNumber          = ASSET_SERIAL_PREFIX + String.valueOf(1000000 + i),
                Status                = 'Installed',
                Description           = DEMO_TAG + ' customer property'
            );
            // Try to set pest-flavored fields if they're deployed.
            try { asset.put('Service_Line__c', svcLine); } catch (Exception e) {}
            try { asset.put('Service_Group__c', isCluster ? 'ZIP-32828-MOSQUITO' : 'ZIP-' + ZIPS[Math.mod(i, ZIPS.size())]); } catch (Exception e) {}
            try { asset.put('NFC_Tag_Id__c', 'NFC-' + String.valueOf(2000000 + i)); } catch (Exception e) {}
            try { asset.put('Is_Pest_Pressure_Candidate__c', isCandidate); } catch (Exception e) {}
            try { asset.put('Last_Sensor_Reading__c', DateTime.now().addMinutes(-Math.mod(i, 30))); } catch (Exception e) {}

            // Service-line-specific synthetic readings.
            if (svcLine.containsIgnoreCase('Termite')) {
                try { asset.put('Bait_Station_Hits_30d__c', isCandidate ? 7 : 1); } catch (Exception e) {}
                try { asset.put('Soil_Temp_F__c', isCandidate ? 75 : 65); } catch (Exception e) {}
                try { asset.put('Pest_Pressure_Score__c', isCandidate ? 72 : 12); } catch (Exception e) {}
            } else if (svcLine.containsIgnoreCase('Mosquito')) {
                try { asset.put('Pest_Pressure_Score__c', isCandidate ? 68 : 18); } catch (Exception e) {}
            }
            try { asset.put('Conducive_Conditions__c', isCandidate); } catch (Exception e) {}

            assets.add(asset);
        }
        insert assets;
        return accts.size();
    }

    private static Integer loadMockCluster() {
        Integer existing = [SELECT count() FROM Case
                             WHERE Subject LIKE 'Mosquitoes at%'
                                OR Subject LIKE 'Pest activity at%'];
        if (existing > 0) return 0;

        // Pull the 8 cluster customers we just seeded.
        List<Asset> clusterAssets;
        try {
            clusterAssets = [SELECT Id, Name, AccountId FROM Asset
                                      WHERE SerialNumber LIKE :(ASSET_SERIAL_PREFIX + '%')
                                        AND Service_Group__c = :('ZIP-' + CLUSTER_ZIP + '-MOSQUITO')
                                      ORDER BY SerialNumber LIMIT 8];
        } catch (Exception e) {
            // Fallback: just take first 8 by serial number
            clusterAssets = [SELECT Id, Name, AccountId FROM Asset
                              WHERE SerialNumber LIKE :(ASSET_SERIAL_PREFIX + '%')
                              ORDER BY SerialNumber LIMIT 8];
        }
        if (clusterAssets.size() < 8) return 0;

        // Cases — one per affected customer in ZIP 32828.
        List<String> clusterAddresses = new List<String>{
            '1407 Avalon Park Blvd', '1431 Avalon Park Blvd', '1455 Avalon Park Blvd', '1479 Avalon Park Blvd',
            '1502 Waterford Lakes Pkwy', '1526 Waterford Lakes Pkwy', '1550 Waterford Lakes Pkwy', '1574 Waterford Lakes Pkwy'
        };
        List<Case> cases = new List<Case>();
        for (Integer i = 0; i < 8; i++) {
            Asset a = clusterAssets[i];
            String addr = clusterAddresses[i];
            cases.add(new Case(
                AccountId   = a.AccountId,
                AssetId     = a.Id,
                Subject     = (Math.mod(i, 2) == 0
                    ? 'Mosquitoes at ' + addr
                    : 'Pest activity at ' + addr),
                Description = DEMO_TAG + ' cluster-member Case (post-storm Mosquito Surge in ZIP ' + CLUSTER_ZIP + '); awaiting AI cluster detection.',
                Status      = 'New',
                Origin      = 'Phone',
                Priority    = 'High'
            ));
        }
        insert cases;
        return cases.size();
    }

    private static Integer loadDispatchQueue() {
        Integer existing = [SELECT count() FROM WorkOrder
                             WHERE Subject LIKE 'Yesterday spillover%'
                                OR Subject LIKE 'Emergency dispatch%'
                                OR Subject LIKE 'New service start%'];
        if (existing > 0) return 0;

        Map<String, Id> wtByName = new Map<String, Id>();
        for (WorkType wt : [SELECT Id, Name FROM WorkType
                             WHERE Name IN ('GoGreen Quarterly Pest','Sentricon Install','Sentricon Re-baiting',
                                            'Booster Termite Inspection','Booster Pest Treatment',
                                            'Mosquito Hunter Activation','Mosquito Surge Area Treatment',
                                            'Lawn Treatment','New Service Activation')]) {
            wtByName.put(wt.Name, wt.Id);
        }

        List<Account> accts = [SELECT Id, FirstName, LastName, Name FROM Account
                                WHERE AccountNumber LIKE :(ACCOUNT_NUMBER_PREFIX + '%')
                                ORDER BY AccountNumber LIMIT 50];
        Map<Id, Asset> assetByAccount = new Map<Id, Asset>();
        for (Asset a : [SELECT Id, Name, AccountId FROM Asset WHERE SerialNumber LIKE :(ASSET_SERIAL_PREFIX + '%')]) {
            assetByAccount.put(a.AccountId, a);
        }

        List<WorkOrder> wos = new List<WorkOrder>();

        // 6 break-fix from yesterday's spillover.
        List<String> spillTypes = new List<String>{
            'Booster Pest Treatment', 'GoGreen Quarterly Pest', 'Sentricon Re-baiting',
            'Booster Pest Treatment', 'Mosquito Hunter Activation', 'Lawn Treatment'
        };
        for (Integer i = 0; i < 6 && i + 20 < accts.size(); i++) {
            Account a = accts[i + 20];
            Asset asset = assetByAccount.get(a.Id);
            wos.add(new WorkOrder(
                AccountId   = a.Id,
                AssetId     = asset != null ? asset.Id : null,
                WorkTypeId  = wtByName.get(spillTypes[i]),
                Subject     = 'Yesterday spillover — ' + spillTypes[i] + ' at ' + (asset != null ? asset.Name : 'service location'),
                Status      = 'New',
                Priority    = 'Medium',
                StartDate   = DateTime.now(),
                EndDate     = DateTime.now().addHours(2),
                Description = DEMO_TAG + ' carried over from yesterday.'
            ));
        }
        // 2 emergency dispatches.
        for (Integer i = 0; i < 2 && i + 30 < accts.size(); i++) {
            Account a = accts[i + 30];
            Asset asset = assetByAccount.get(a.Id);
            wos.add(new WorkOrder(
                AccountId   = a.Id,
                AssetId     = asset != null ? asset.Id : null,
                WorkTypeId  = wtByName.get('Booster Pest Treatment'),
                Subject     = 'Emergency dispatch — active swarm at ' + (asset != null ? asset.Name : 'site'),
                Status      = 'New',
                Priority    = 'High',
                StartDate   = DateTime.now(),
                EndDate     = DateTime.now().addHours(1),
                Description = DEMO_TAG + ' active swarm reported via inbound call. Same-day truck roll required.'
            ));
        }
        // 1 service start WO for David Kim.
        Account david;
        for (Account a : accts) {
            if (a.FirstName == 'David' && a.LastName == 'Kim') { david = a; break; }
        }
        if (david != null) {
            Asset davidAsset = assetByAccount.get(david.Id);
            wos.add(new WorkOrder(
                AccountId   = david.Id,
                AssetId     = davidAsset != null ? davidAsset.Id : null,
                WorkTypeId  = wtByName.get('New Service Activation'),
                Subject     = 'New service start — David Kim at ' + (davidAsset != null ? davidAsset.Name : 'new address'),
                Status      = 'New',
                Priority    = 'Medium',
                StartDate   = DateTime.now().addDays(1),
                EndDate     = DateTime.now().addDays(1).addHours(1),
                Description = DEMO_TAG + ' self-service start booked via massey-portal Experience Cloud site.'
            ));
        }

        if (!wos.isEmpty()) insert wos;
        return wos.size();
    }

    private static Integer loadProactiveSensorRun() {
        try {
            ProactiveWoGenerator.Result r = ProactiveWoGenerator.runAll();
            return (r.proactiveWosCreated == null ? 0 : r.proactiveWosCreated)
                 + (r.declinedCasesCreated == null ? 0 : r.declinedCasesCreated)
                 + (r.noReplyCasesCreated == null ? 0 : r.noReplyCasesCreated);
        } catch (Exception e) {
            System.debug('Proactive sensor run skipped: ' + e.getMessage());
            return 0;
        }
    }

    private static Integer loadWorkPlans() {
        List<WorkOrder> targets = [SELECT Id, Subject FROM WorkOrder
                                    WHERE (Subject LIKE 'Booster%'
                                        OR Subject LIKE 'Visit % (Day 1 of %)'
                                        OR Subject LIKE 'New service start%')
                                      AND Id NOT IN (SELECT WorkOrderId FROM WorkPlan)
                                    LIMIT 15];
        if (targets.isEmpty()) return 0;

        List<WorkPlan> plans = new List<WorkPlan>();
        for (WorkOrder w : targets) {
            plans.add(new WorkPlan(
                Name = 'Standard Service Visit Plan',
                WorkOrderId = w.Id,
                ExecutionOrder = 1
            ));
        }
        insert plans;

        List<WorkStep> steps = new List<WorkStep>();
        for (WorkPlan wp : plans) steps.addAll(stepsForPlan(wp.Id));
        if (!steps.isEmpty()) insert steps;

        return plans.size() + steps.size();
    }

    public static Id createPlanAndStepsForWo(Id workOrderId) {
        if (workOrderId == null) return null;
        Integer existing = [SELECT count() FROM WorkPlan WHERE WorkOrderId = :workOrderId];
        if (existing > 0) {
            for (WorkPlan wp : [SELECT Id FROM WorkPlan WHERE WorkOrderId = :workOrderId LIMIT 1]) return wp.Id;
            return null;
        }
        WorkPlan wp = new WorkPlan(
            Name = 'Standard Service Visit Plan',
            WorkOrderId = workOrderId,
            ExecutionOrder = 1
        );
        insert wp;
        insert stepsForPlan(wp.Id);
        return wp.Id;
    }

    private static List<WorkStep> stepsForPlan(Id planId) {
        List<WorkStep> steps = new List<WorkStep>();
        Integer order = 1;
        // Safety_Critical — block the safety gate until cleared.
        for (String name : new List<String>{'PPE Verified', 'Truck Locked / Brake On', 'Route Briefing Reviewed'}) {
            steps.add(new WorkStep(Name = name, WorkPlanId = planId, ExecutionOrder = order++,
                Step_Category__c = 'Safety_Critical', Is_Critical__c = true, Sort_Order__c = order));
        }
        // Safety_Site
        steps.add(new WorkStep(Name = 'Property Walk-around', WorkPlanId = planId, ExecutionOrder = order++,
            Step_Category__c = 'Safety_Site', Is_Critical__c = false, Sort_Order__c = order));
        // Safety_Admin
        for (String name : new List<String>{'Customer Contact Confirmed', 'Re-Entry Interval Briefed'}) {
            steps.add(new WorkStep(Name = name, WorkPlanId = planId, ExecutionOrder = order++,
                Step_Category__c = 'Safety_Admin', Is_Critical__c = false, Sort_Order__c = order));
        }
        // Work_DeEnergize → for pest = Pre-Treatment Setup (capture site, confirm pets indoors, mix product)
        steps.add(new WorkStep(Name = 'Capture Pre-Treatment Pressure / Confirm Pets Indoors', WorkPlanId = planId, ExecutionOrder = order++,
            Step_Category__c = 'Work_DeEnergize', Is_Critical__c = false, Sort_Order__c = order));
        // Work_Execute
        for (String name : new List<String>{'NFC Scan Property Marker', 'Apply Treatment / Re-Bait Stations', 'Photograph Application Areas'}) {
            steps.add(new WorkStep(Name = name, WorkPlanId = planId, ExecutionOrder = order++,
                Step_Category__c = 'Work_Execute', Is_Critical__c = false, Sort_Order__c = order));
        }
        // Work_ReEnergize → for pest = Post-Treatment Verification (verify customer sign-off, set re-entry timer)
        for (String name : new List<String>{'Set Treatment Perimeter', 'Capture Customer Sign-off', 'Confirm Re-Entry Interval Posted'}) {
            steps.add(new WorkStep(Name = name, WorkPlanId = planId, ExecutionOrder = order++,
                Step_Category__c = 'Work_ReEnergize', Is_Critical__c = false, Sort_Order__c = order));
        }
        return steps;
    }

    private static Integer loadServiceResources() {
        Integer existing = [SELECT count() FROM ServiceResource
                             WHERE Name IN ('Tom Walker', 'Maria Lopez')];
        if (existing >= 2) return 0;

        Id userId = UserInfo.getUserId();
        Integer affected = 0;

        List<ServiceResource> existingTech = [SELECT Id, Name FROM ServiceResource
                                                WHERE RelatedRecordId = :userId AND ResourceType = 'T' LIMIT 1];
        if (!existingTech.isEmpty() && existingTech[0].Name != 'Maria Lopez') {
            existingTech[0].Name = 'Maria Lopez';
            update existingTech[0];
            affected++;
        } else if (existingTech.isEmpty()) {
            insert new ServiceResource(Name = 'Maria Lopez', RelatedRecordId = userId,
                ResourceType = 'T', IsActive = true);
            affected++;
        }

        List<ServiceResource> existingDispatcher = [SELECT Id FROM ServiceResource
                                                      WHERE RelatedRecordId = :userId AND ResourceType = 'D' LIMIT 1];
        if (existingDispatcher.isEmpty()) {
            insert new ServiceResource(Name = 'Tom Walker', RelatedRecordId = userId,
                ResourceType = 'D', IsActive = true);
            affected++;
        }
        return affected;
    }
}
