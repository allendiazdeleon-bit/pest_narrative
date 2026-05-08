/**
 * SafetyBriefService — AI-flavored safety brief for the Safety Gate step
 * of the masseyFlow orchestrator. Pest-toned: PPE for restricted-use
 * pesticides, weather (FL heat + thunderstorms), wildlife (fire ants,
 * snakes, dogs), and conducive conditions on the property.
 *
 * In the production vision, an Agentforce action calls out to: a weather
 * provider (Open-Meteo / NOAA), a property-history lookup, and the Service
 * Cloud incident history at the work address. The results are fused into
 * a site-specific risk picture and pre-fill the tech's safety checklist
 * with hazards relevant to THIS address and THIS work type.
 *
 * For the demo this is FAKED deterministically — no real callouts. The
 * synthesis is seeded by the Work Order address and WorkType so the same
 * WO produces the same brief every time, while different addresses /
 * work types produce visibly different hazards.
 *
 * Replace getBrief() with real callouts in production; the LWC contract
 * (SafetyBrief / Hazard shape) stays the same.
 */
public with sharing class SafetyBriefService {

    public class Hazard {
        @AuraEnabled public String id;
        @AuraEnabled public String category;            // OnProperty|Weather|Wildlife|PriorIncident|Compliance
        @AuraEnabled public String severity;            // Low|Medium|High|Critical
        @AuraEnabled public String title;
        @AuraEnabled public String detail;
        @AuraEnabled public String suggestedMitigation;
        @AuraEnabled public String iconUrl;
    }

    public class SafetyBrief {
        @AuraEnabled public Id workOrderId;
        @AuraEnabled public Id assetId;
        @AuraEnabled public String address;
        @AuraEnabled public DateTime generatedAt;
        @AuraEnabled public Decimal confidenceScore;
        @AuraEnabled public List<Hazard> hazards;
        @AuraEnabled public String weatherSummary;
        @AuraEnabled public List<String> recommendedPpe;
        @AuraEnabled public String siteRiskLevel;
        @AuraEnabled public String summary;
    }

    private static final Map<String, Integer> SEV_RANK = new Map<String, Integer>{
        'Low' => 1, 'Medium' => 2, 'High' => 3, 'Critical' => 4
    };
    private static final Map<Integer, String> RANK_SEV = new Map<Integer, String>{
        1 => 'Low', 2 => 'Medium', 3 => 'High', 4 => 'Critical'
    };

    @AuraEnabled(cacheable=true)
    public static SafetyBrief getBrief(Id workOrderId) {
        SafetyBrief brief = new SafetyBrief();
        brief.workOrderId = workOrderId;
        brief.generatedAt = System.now();
        brief.hazards = new List<Hazard>();
        brief.recommendedPpe = new List<String>();

        WorkOrder wo;
        try {
            List<WorkOrder> rows = [
                SELECT Id, AssetId, AccountId, Street, City, State, PostalCode,
                       WorkType.Name
                FROM WorkOrder
                WHERE Id = :workOrderId
                LIMIT 1
            ];
            if (!rows.isEmpty()) {
                wo = rows[0];
            }
        } catch (Exception e) {
            // fall through with empty wo
        }

        String workTypeName = (wo != null && wo.WorkType != null) ? wo.WorkType.Name : null;
        String composedAddress = composeAddress(wo);
        brief.assetId = (wo != null) ? wo.AssetId : null;
        brief.address = composedAddress;

        Integer addrSeed = stableSeed(composedAddress);

        addPropertyHazards(brief.hazards, addrSeed);
        String weatherSummary = addWeatherHazard(brief.hazards, addrSeed);
        brief.weatherSummary = weatherSummary;

        addWildlifeHazardIfApplicable(brief.hazards, addrSeed);
        addPriorIncidentHazardIfApplicable(brief.hazards, wo);
        addWorkTypeHazards(brief.hazards, workTypeName);

        brief.recommendedPpe = computePpe(brief.hazards);
        brief.siteRiskLevel = computeSiteRisk(brief.hazards);
        brief.confidenceScore = computeConfidence(brief.hazards.size(), wo != null);
        brief.summary = buildSummary(brief.siteRiskLevel, brief.hazards, workTypeName);

        return brief;
    }

    private static void addPropertyHazards(List<Hazard> hazards, Integer addrSeed) {
        Integer lastDigit = Math.mod(addrSeed, 10);
        Integer pick = Math.mod(lastDigit, 3);
        if (pick == 0) {
            hazards.add(buildHazard(
                'property-pool-pets',
                'OnProperty',
                'Medium',
                'Pool / pets present — re-entry interval critical',
                'Property has a backyard pool and prior visit notes mention two dogs. Restricted-use pesticide application requires a strict 4-hour re-entry interval before any animal or person re-enters the treated area.',
                'Confirm pool cover or skim treatment timing; brief homeowner on the re-entry interval before applying.',
                '/img/icon/t4v35/utility/info.svg'
            ));
        } else if (pick == 1) {
            hazards.add(buildHazard(
                'property-conducive-conditions',
                'OnProperty',
                'Medium',
                'Conducive conditions noted (moisture / wood-to-soil contact)',
                'Last inspection flagged Conducive_Conditions__c on this property — wood mulch piled against the foundation, A/C condensate pooling near the slab, and a partially-rotted fence post within 3 ft of the structure.',
                'Note conducive conditions in the visit summary; recommend remediation to homeowner before applying termiticide.',
                '/img/icon/t4v35/utility/warning.svg'
            ));
        } else {
            hazards.add(buildHazard(
                'property-fence-locked',
                'OnProperty',
                'Low',
                'Backyard gate may be locked',
                'Prior visits report needing customer access for the back yard perimeter spray. Plan to call ahead if no one answers the door.',
                'Phone customer 30 min before arrival; confirm gate access before stepping out of the truck.',
                '/img/icon/t4v35/utility/info.svg'
            ));
        }

        if (Math.mod(addrSeed, 2) == 0) {
            hazards.add(buildHazard(
                'property-children',
                'OnProperty',
                'Low',
                'Young children household — heightened re-entry care',
                'Customer profile notes school-age children. Restricted-use product application requires extra care on toy storage areas, sandboxes, and kitchen surfaces.',
                'Ask homeowner to keep kids and toys indoors during application; confirm re-entry interval verbally.',
                '/img/icon/t4v35/utility/info.svg'
            ));
        }
    }

    private static String addWeatherHazard(List<Hazard> hazards, Integer addrSeed) {
        Integer dow = Math.mod(Date.today().toStartOfWeek().daysBetween(Date.today()), 7);
        Integer combo = Math.abs(Math.mod(addrSeed + dow * 13, 100));

        Integer tempF = 70 + Math.mod(combo, 25);                 // 70..94 (FL)
        Integer precipPct = Math.mod(combo * 7, 90);              // 0..89
        String[] uvLevels = new String[]{ 'low', 'moderate', 'high', 'very high' };
        String uv = uvLevels[Math.mod(combo, 4)];
        String[] precipKinds = new String[]{ 'afternoon thunderstorms', 'isolated showers', 'scattered showers', 'tropical rainband' };
        String precipKind = precipKinds[Math.mod(combo / 3, 4)];
        Integer afterHour = 1 + Math.mod(combo, 8);

        String weatherSummary = tempF + 'F, ' + precipPct + '% chance of '
            + precipKind + ' after ' + afterHour + 'pm, UV ' + uv;

        if (precipPct >= 50) {
            hazards.add(buildHazard(
                'weather-precip',
                'Weather',
                precipPct >= 70 ? 'High' : 'Medium',
                'Elevated rain chance during shift',
                precipPct + '% chance of ' + precipKind + ' starting around ' + afterHour
                    + 'pm. Liquid termiticide and lawn applications wash off if applied within 2 hours of rainfall.',
                'Front-load the route with liquid applications; defer ULV fogging if storm cell is close.',
                '/img/icon/t4v35/utility/warning.svg'
            ));
        }
        if (tempF >= 88) {
            hazards.add(buildHazard(
                'weather-heat',
                'Weather',
                tempF >= 92 ? 'High' : 'Medium',
                'Heat stress risk',
                'Forecast high of ' + tempF + 'F combined with PPE load (long sleeves, respirator) increases heat-stress risk per OSHA water-rest-shade.',
                'Rotate every 45 min; pre-cool water bottles in the truck; buddy-check hourly.',
                '/img/icon/t4v35/utility/warning.svg'
            ));
        }
        if (uv == 'very high') {
            hazards.add(buildHazard(
                'weather-uv',
                'Weather',
                'Low',
                'UV index very high',
                'FL midday UV exposure; sunscreen and long sleeves recommended.',
                'Apply SPF 30+; reapply every 2 hours.',
                '/img/icon/t4v35/utility/info.svg'
            ));
        }
        return weatherSummary;
    }

    private static void addWildlifeHazardIfApplicable(List<Hazard> hazards, Integer addrSeed) {
        Integer pick = Math.mod(addrSeed, 5);
        if (pick == 0) {
            hazards.add(buildHazard(
                'wildlife-fireants',
                'Wildlife',
                'Medium',
                'Fire ant mounds active in service area',
                'Two prior 311 reports of fire ant activity within 100 ft of this address in the last 90 days. FL summer = active mound season.',
                'Inspect ground before kneeling; carry sting kit; treat mounds with bait if encountered.',
                '/img/icon/t4v35/utility/info.svg'
            ));
        } else if (pick == 1) {
            hazards.add(buildHazard(
                'wildlife-snakes',
                'Wildlife',
                'Medium',
                'Snake activity noted near property',
                'Black racers and rat snakes are common in this Orlando neighborhood, especially around mulch beds and woodpiles where Sentricon stations are typically placed.',
                'Use long-handled tools to disturb mulch beds; wear snake-proof boots if entering wood piles.',
                '/img/icon/t4v35/utility/warning.svg'
            ));
        } else if (pick == 2) {
            hazards.add(buildHazard(
                'wildlife-dogs',
                'Wildlife',
                'Low',
                'Dogs on property',
                'Customer profile notes 1-2 dogs. Confirm they are kenneled or indoors before stepping into the back yard.',
                'Phone homeowner before stepping past the gate; never spray with pets in the yard.',
                '/img/icon/t4v35/utility/info.svg'
            ));
        }
    }

    private static void addPriorIncidentHazardIfApplicable(List<Hazard> hazards, WorkOrder wo) {
        if (wo == null || wo.AccountId == null) return;
        Integer priorWoCount = 0;
        Integer priorCaseCount = 0;
        try {
            priorWoCount = [SELECT count() FROM WorkOrder
                            WHERE AccountId = :wo.AccountId AND Id != :wo.Id];
        } catch (Exception e) {}
        try {
            priorCaseCount = [SELECT count() FROM Case WHERE AccountId = :wo.AccountId];
        } catch (Exception e) {}

        Integer total = priorWoCount + priorCaseCount;
        if (total <= 0) return;

        String sev = total >= 5 ? 'High' : (total >= 2 ? 'Medium' : 'Low');
        hazards.add(buildHazard(
            'prior-incident-history',
            'PriorIncident',
            sev,
            'Repeat-visit address (' + total + ' prior records)',
            'This service address has ' + priorWoCount + ' prior work order(s) and ' + priorCaseCount
                + ' prior case(s) on file. Recurring activity often indicates an unresolved root cause (conducive conditions, treatment-resistant population, etc.).',
            'Review prior visit close-out notes and recent cases before starting; flag pattern to supervisor if applicable.',
            '/img/icon/t4v35/utility/info.svg'
        ));
    }

    private static void addWorkTypeHazards(List<Hazard> hazards, String workTypeName) {
        if (String.isBlank(workTypeName)) return;
        String wt = workTypeName.toLowerCase();

        if (wt.contains('mosquito surge') || wt.contains('mosquito hunter')) {
            hazards.add(buildHazard(
                'wt-ulv-application',
                'Compliance',
                'High',
                'ULV fog application — drift control + bystander exposure',
                'ULV fogging is a restricted-use pesticide application. Drift onto neighboring properties, water bodies, and pollinator habitat is a regulatory violation.',
                'Verify wind speed under 10 mph; mark adjacent properties with notice; do not fog within 25 ft of open water.',
                '/img/icon/t4v35/utility/warning.svg'
            ));
        } else if (wt.contains('whole-home tent') || wt.contains('tent fumigation')) {
            hazards.add(buildHazard(
                'wt-tent-fumigation',
                'Compliance',
                'Critical',
                'Tent fumigation — sulfuryl fluoride exposure / re-entry',
                'Vikane (sulfuryl fluoride) tent fumigation is a Critical-PPE operation. Direct exposure is fatal; the home must be cleared for 6+ hours before re-entry.',
                'SCBA required during seal/aerate phases; clearance reading with portable detector before homeowner re-enters; signed re-entry log on close-out.',
                '/img/icon/t4v35/utility/warning.svg'
            ));
        } else if (wt.contains('sentricon')) {
            hazards.add(buildHazard(
                'wt-sentricon-bait',
                'Compliance',
                'Medium',
                'Sentricon noviflumuron bait — restricted-use, log application',
                'Sentricon AlwaysActive is a restricted-use chitin-synthesis inhibitor. Per FL Dept of Agriculture, every station inspection / re-baiting must be logged with EPA Reg # + applicator license.',
                'Log EPA Reg #, target species (Reticulitermes), dose; photograph each station; capture homeowner sign-off.',
                '/img/icon/t4v35/utility/warning.svg'
            ));
        } else if (wt.contains('booster termite')) {
            hazards.add(buildHazard(
                'wt-termite-booster',
                'Compliance',
                'Medium',
                'Booster termite inspection — confined-space crawl risk',
                'Crawl-space inspections may involve confined-space entry. FL crawl spaces are humid + may have black widow / brown recluse populations.',
                'Use full-body Tyvek and respirator if entering crawl; keep observer at the access opening; carry sting/bite first-aid.',
                '/img/icon/t4v35/utility/warning.svg'
            ));
        } else if (wt.contains('lawn treatment')) {
            hazards.add(buildHazard(
                'wt-lawn-low',
                'Compliance',
                'Low',
                'Lawn treatment — granular + spray application',
                'Standard turf herbicide / fertilizer / insecticide application. No restricted-use products on a typical residential turf visit.',
                'Standard PPE; confirm pets are indoors; log granular product names + rates.',
                '/img/icon/t4v35/utility/info.svg'
            ));
        } else if (wt.contains('gogreen quarterly') || wt.contains('quarterly pest')
                   || wt.contains('new service activation')) {
            hazards.add(buildHazard(
                'wt-quarterly-low',
                'Compliance',
                'Low',
                'Quarterly perimeter visit — standard PPE only',
                'Routine perimeter spray with bifenthrin or similar. Low-toxicity baseline product.',
                'Standard PPE; verify pet / child safety before applying; log product name + rate.',
                '/img/icon/t4v35/utility/info.svg'
            ));
        }
    }

    private static Hazard buildHazard(String id, String category, String severity,
                                      String title, String detail,
                                      String mitigation, String iconUrl) {
        Hazard h = new Hazard();
        h.id = id;
        h.category = category;
        h.severity = severity;
        h.title = title;
        h.detail = detail;
        h.suggestedMitigation = mitigation;
        h.iconUrl = iconUrl;
        return h;
    }

    private static List<String> computePpe(List<Hazard> hazards) {
        Set<String> ppe = new Set<String>{
            'Nitrile gloves',
            'Long sleeves & long pants',
            'Closed-toe boots',
            'Safety glasses'
        };
        for (Hazard h : hazards) {
            String id = h.id != null ? h.id : '';
            String cat = h.category != null ? h.category : '';
            if (id.contains('ulv') || id.contains('fumigation') || id.contains('sentricon')) {
                ppe.add('Half-mask respirator (organic vapor)');
                ppe.add('Tyvek coverall');
            }
            if (id.contains('fumigation')) {
                ppe.add('SCBA (self-contained breathing apparatus)');
                ppe.add('Sulfuryl fluoride detector');
            }
            if (id.contains('snakes')) {
                ppe.add('Snake-proof boots');
            }
            if (id.contains('fireants')) {
                ppe.add('Sting / EpiPen kit');
            }
            if (id.contains('crawl')) {
                ppe.add('Disposable Tyvek');
                ppe.add('Knee pads');
            }
            if (id.contains('weather-heat')) {
                ppe.add('Cooling neck gaiter');
                ppe.add('Hydration pack');
            }
        }
        List<String> out = new List<String>(ppe);
        out.sort();
        return out;
    }

    private static String computeSiteRisk(List<Hazard> hazards) {
        Integer maxRank = 1;
        for (Hazard h : hazards) {
            Integer r = SEV_RANK.containsKey(h.severity) ? SEV_RANK.get(h.severity) : 1;
            if (r > maxRank) maxRank = r;
        }
        return RANK_SEV.get(maxRank);
    }

    private static Decimal computeConfidence(Integer hazardCount, Boolean haveWo) {
        Decimal base = haveWo ? 0.65 : 0.40;
        Decimal bonus = Math.min(0.30, (Decimal) hazardCount * 0.05);
        Decimal score = base + bonus;
        if (score > 0.95) score = 0.95;
        return score.setScale(2);
    }

    private static String buildSummary(String siteRisk, List<Hazard> hazards, String workTypeName) {
        Hazard top;
        Integer topRank = 0;
        for (Hazard h : hazards) {
            Integer r = SEV_RANK.containsKey(h.severity) ? SEV_RANK.get(h.severity) : 1;
            if (r > topRank) {
                top = h;
                topRank = r;
            }
        }
        String riskWord;
        if (siteRisk == 'Critical') riskWord = 'High-risk';
        else if (siteRisk == 'High') riskWord = 'Elevated-risk';
        else if (siteRisk == 'Medium') riskWord = 'Moderate-risk';
        else riskWord = 'Low-risk';

        String wt = String.isNotBlank(workTypeName) ? workTypeName : 'this assignment';
        String first = riskWord + ' site for ' + wt + '.';
        String second;
        if (top != null) {
            second = ' ' + top.title + ' — ' + (top.suggestedMitigation != null
                ? top.suggestedMitigation
                : 'review hazard list before starting.');
        } else {
            second = ' No site-specific hazards detected; proceed with standard safety protocol.';
        }
        return first + second;
    }

    private static String composeAddress(WorkOrder wo) {
        if (wo == null) return '';
        List<String> parts = new List<String>();
        if (String.isNotBlank(wo.Street))     parts.add(wo.Street);
        if (String.isNotBlank(wo.City))       parts.add(wo.City);
        if (String.isNotBlank(wo.State))      parts.add(wo.State);
        if (String.isNotBlank(wo.PostalCode)) parts.add(wo.PostalCode);
        return String.join(parts, ', ');
    }

    private static Integer stableSeed(String s) {
        if (String.isBlank(s)) return 0;
        Integer total = 0;
        String lower = s.toLowerCase();
        for (Integer i = 0; i < lower.length(); i++) {
            total += lower.substring(i, i + 1).getChars()[0];
        }
        return total;
    }
}
