/**
 * NextBestActionService — Mock-AI next-best-action suggester per work step.
 * Surfaced as cards in masseyFlowWorkStep + safetyStep + siteStep when a
 * tech enters a Step_Category__c phase.
 *
 * The "AI" here is a hardcoded heuristics table keyed off
 * (WorkType.Name, Step_Category__c). Each suggestion has a title,
 * 1-sentence rationale, priority, category, and confidence score.
 *
 * PRODUCTION REPLACEMENT: drive from a Knowledge / playbook taxonomy
 * with org-trained Einstein for Field Service or an LLM-fronted
 * guidance service.
 */
public with sharing class NextBestActionService {

    public class NextBestAction {
        @AuraEnabled public String title;
        @AuraEnabled public String rationale;
        @AuraEnabled public String priority;          // 'Recommended' | 'Optional'
        @AuraEnabled public String category;          // 'Safety' | 'Quality' | 'Compliance' | 'Efficiency'
        @AuraEnabled public Decimal confidence;       // 0-100
        @AuraEnabled public String summary;           // short label for AI Insight Card
        @AuraEnabled public String source;
        @AuraEnabled public DateTime generatedAt;

        public NextBestAction(String title, String rationale, String priority, String category, Decimal confidence) {
            this.title = title;
            this.rationale = rationale;
            this.priority = priority;
            this.category = category;
            this.confidence = confidence;
            this.summary = title;
            this.source = 'NextBestActionService heuristics';
            this.generatedAt = DateTime.now();
        }
    }

    /**
     * Returns 1-3 actions for the given Work Order + step category. The
     * step category is the Step_Category__c value on the active WorkStep
     * (e.g., 'Work_Safety', 'Work_DeEnergize', 'Work_Execute', 'Work_Site',
     * 'Work_Summary', 'Work_ServiceImpact').
     */
    @AuraEnabled(cacheable=true)
    public static List<NextBestAction> suggestForStep(Id workOrderId, String stepCategory) {
        List<NextBestAction> out = new List<NextBestAction>();
        if (workOrderId == null || String.isBlank(stepCategory)) return out;

        WorkOrder wo;
        try {
            wo = [
                SELECT Id, Subject, WorkType.Name, AssetId,
                       Asset.Service_Line__c,
                       Asset.Is_Pest_Pressure_Candidate__c
                FROM WorkOrder WHERE Id = :workOrderId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
        } catch (QueryException qe) {
            return out;
        }

        String wt = wo.WorkType != null && wo.WorkType.Name != null ? wo.WorkType.Name : '';
        String svc = wo.Asset != null && wo.Asset.Service_Line__c != null ? wo.Asset.Service_Line__c : '';
        Boolean activePressure = wo.Asset != null && wo.Asset.Is_Pest_Pressure_Candidate__c == true;

        out.addAll(genericForCategory(stepCategory));
        out.addAll(workTypeOverlay(wt, stepCategory, svc, activePressure));

        Set<String> seen = new Set<String>();
        List<NextBestAction> deduped = new List<NextBestAction>();
        for (NextBestAction nba : out) {
            if (seen.contains(nba.title)) continue;
            seen.add(nba.title);
            deduped.add(nba);
            if (deduped.size() >= 3) break;
        }
        return deduped;
    }

    private static List<NextBestAction> genericForCategory(String cat) {
        List<NextBestAction> actions = new List<NextBestAction>();
        if (cat == 'Work_Safety') {
            actions.add(new NextBestAction(
                'Confirm treatment perimeter is set',
                'Industry standard requires a marked treatment perimeter to keep pets and bystanders out during the re-entry interval.',
                'Recommended', 'Safety', 92
            ));
            actions.add(new NextBestAction(
                'Verify PPE for the active hazards',
                'Safety briefing should call out hazards specific to this service line — gloves, respirator, eye protection at minimum for restricted-use products.',
                'Recommended', 'Safety', 88
            ));
        } else if (cat == 'Work_DeEnergize' || cat == 'Work_Energize') {
            actions.add(new NextBestAction(
                'Pre-treatment site walk + photo',
                'Pre-treatment walk-around catches obstacles (toys, pet bowls, decorative features) before chemical is mixed.',
                'Recommended', 'Quality', 90
            ));
            actions.add(new NextBestAction(
                'Verify product mix + dose ratio',
                'Confirm the mix ratio matches the product label for this target species before applying.',
                'Recommended', 'Quality', 85
            ));
        } else if (cat == 'Work_Site') {
            actions.add(new NextBestAction(
                'NFC scan the property marker before any work',
                'Confirms you are on the right property and ties the visit to the WorkOrder for audit.',
                'Recommended', 'Compliance', 95
            ));
            actions.add(new NextBestAction(
                'Capture pre-treatment pest pressure score',
                'Baseline reading enables before/after comparison and proves treatment efficacy to QA.',
                'Recommended', 'Quality', 88
            ));
        } else if (cat == 'Work_Execute') {
            actions.add(new NextBestAction(
                'Capture before/after photos',
                'Photo evidence is the fastest way to close out QA on a field job and satisfy regulatory record-keeping.',
                'Recommended', 'Compliance', 90
            ));
        } else if (cat == 'Work_ServiceImpact') {
            actions.add(new NextBestAction(
                'Confirm linked Incident is closeable',
                'All cluster sub-Cases must be in a closeable state before the parent Incident can flip Resolved.',
                'Recommended', 'Compliance', 92
            ));
            actions.add(new NextBestAction(
                'Capture root-cause classification',
                'Required by FL Dept of Agriculture record-keeping — pick from the standard taxonomy on the WO.',
                'Recommended', 'Compliance', 90
            ));
        } else if (cat == 'Work_Summary') {
            actions.add(new NextBestAction(
                'Run VisitSummaryGenerator before close',
                'Auto-summary attaches a structured close-out artifact to the WO; downstream branch ops and customer comms pull it.',
                'Recommended', 'Quality', 88
            ));
            actions.add(new NextBestAction(
                'Verify all required photos uploaded',
                'WO will not auto-close if photo gates are missing — failsafe to avoid stuck records.',
                'Optional', 'Compliance', 80
            ));
        }
        return actions;
    }

    private static List<NextBestAction> workTypeOverlay(String workType, String cat, String svc, Boolean activePressure) {
        List<NextBestAction> actions = new List<NextBestAction>();
        if (String.isBlank(workType)) return actions;

        if (workType == 'Mosquito Surge Area Treatment') {
            if (cat == 'Work_Execute') {
                actions.add(new NextBestAction(
                    'Identify the breeding source first',
                    'Treating the source (clogged storm drain, standing water) eliminates the population; perimeter fog without source treatment is short-lived.',
                    'Recommended', 'Quality', 95
                ));
                actions.add(new NextBestAction(
                    'Apply larvicide to standing water',
                    'Larvicide tablets in standing water break the Aedes life cycle for 30+ days; perimeter ULV fog handles the adults already on the wing.',
                    'Recommended', 'Quality', 92
                ));
            }
        } else if (workType == 'Whole-Home Tent Fumigation') {
            if (cat == 'Work_DeEnergize') {
                actions.add(new NextBestAction(
                    'Confirm seal before introducing fumigant',
                    'A bad tent seal is the #1 cause of fumigation reapplications. Walk all 4 sides + roof seam before opening the cylinder.',
                    'Recommended', 'Safety', 95
                ));
            } else if (cat == 'Work_Execute') {
                actions.add(new NextBestAction(
                    'Verify clearance reading before re-entry',
                    'Customer cannot re-enter until detector reads 0 ppm sulfuryl fluoride. No exceptions.',
                    'Recommended', 'Safety', 98
                ));
            }
        } else if (workType == 'Sentricon Install' || workType == 'Sentricon Re-baiting') {
            if (cat == 'Work_Site') {
                actions.add(new NextBestAction(
                    'Photograph each station location',
                    'Captures the layout for compliance + for the next tech\'s reference. FL mandates per-station photo evidence.',
                    'Recommended', 'Compliance', 90
                ));
            }
            if (cat == 'Work_Execute') {
                actions.add(new NextBestAction(
                    'Log EPA Reg # + applicator license',
                    'Sentricon noviflumuron is restricted-use. FL requires EPA Reg # + applicator license logged per visit.',
                    'Recommended', 'Compliance', 96
                ));
            }
        } else if (workType == 'GoGreen Quarterly Pest' || workType == 'New Service Activation') {
            if (cat == 'Work_Site') {
                actions.add(new NextBestAction(
                    'Note conducive conditions for the homeowner',
                    'Conducive conditions (mulch against foundation, A/C condensate pools) are root causes of recurring activity. Note them and brief the homeowner.',
                    'Recommended', 'Quality', 88
                ));
            }
        } else if (workType == 'Booster Termite Inspection') {
            if (cat == 'Work_Safety' || cat == 'Work_Site') {
                actions.add(new NextBestAction(
                    'Crawl-space PPE check before entry',
                    'FL crawl spaces are humid + may contain spider populations. Tyvek + respirator if entering.',
                    'Recommended', 'Safety', 96
                ));
            }
        } else if (workType == 'Mosquito Hunter Activation') {
            if (cat == 'Work_Site') {
                actions.add(new NextBestAction(
                    'Verify system controller pairs correctly',
                    'Bench-pair the system controller before mounting; field re-pair adds 30 minutes if it fails.',
                    'Recommended', 'Efficiency', 90
                ));
            }
        } else if (workType == 'Lawn Treatment') {
            if (cat == 'Work_Execute') {
                actions.add(new NextBestAction(
                    'Capture turf condition photo',
                    'Turf condition photo is the fastest way to flag chinch bug / brown patch issues for the next route.',
                    'Recommended', 'Quality', 88
                ));
            }
        }

        if (activePressure && cat == 'Work_Site') {
            actions.add(new NextBestAction(
                'Property flagged for pest pressure — capture extra evidence',
                'This property was on the predictive watch list; take extra photos and a thorough station inventory for engineering.',
                'Recommended', 'Quality', 87
            ));
        }
        return actions;
    }
}
