/**
 * UpsellCoachService
 *
 * Load-bearing class for the marquee Massey demo scene (Scene 5: Maria pitches
 * Mosquito Hunter to the Bennett family because their neighbors signed up).
 *
 * Net-new for this lifecycle (no analogue in prior demo lifecycles). Pairs with:
 *   - Account upsell fields (P1.7): Eligible_Upsells__c, Last_Upsell_*__c, Upsell_Score__c
 *   - Upsell_Talk_Track__mdt (P3.4): ~12 empathetic "while I'm here..." scripts
 *   - masseyUpsellCoach LWC (P5.6): renders the recommendation in Site / Summary steps
 *   - "Upsell Recommendation" Agentforce topic (P4.3): on-demand pitch from Sidekick
 *   - Manager Coaching dashboard (P6.1): rolls up Last_Upsell_Outcome__c metrics
 *
 * Philosophy: empathetic + low-pressure. Bad pitches damage retention in a
 * recurring-relationship business — score thresholds and talk-track copy reflect that.
 *
 * @see docs/PEST_NARRATIVE.md Scene 5
 * @see ARCHITECTURE_PROPOSAL.md Section 11
 * @see docs/BUILD_TICKETS_PEST.md ticket P3.4
 */
public with sharing class UpsellCoachService {

    // -------- DTO returned to LWC + Agentforce --------

    public class UpsellRecommendation {
        @AuraEnabled public String serviceLine;        // Pest / Termite / Mosquito / Lawn
        @AuraEnabled public Integer score;             // 0-100 composite
        @AuraEnabled public List<String> reasonCodes;  // e.g., 'NEIGHBOR_BOUGHT_MOSQUITO'
        @AuraEnabled public String suggestedTalkTrack; // copy from Upsell_Talk_Track__mdt
        @AuraEnabled public Decimal estimatedAnnualValue;
    }

    // -------- Constants --------

    private static final Set<String> ALL_LINES = new Set<String>{
        'Pest', 'Termite', 'Mosquito', 'Lawn'
    };

    // Cap neighbor lookup so an Account in a dense ZIP doesn't blow heap.
    // Returns count, not the records themselves — we only need the magnitude.
    private static final Integer NEIGHBOR_LOOKUP_LIMIT = 200;

    // Score component weights (must sum to <=100 across all positive contributors).
    private static final Integer SCORE_BASE = 20;
    private static final Integer SCORE_NEIGHBOR_HIT = 25;
    private static final Integer SCORE_SEASONAL = 20;
    private static final Integer SCORE_PROPERTY_FIT = 15;
    private static final Integer SCORE_TENURE_LOYAL = 10;
    private static final Integer SCORE_CONDUCIVE = 10;

    // -------- Public API --------

    /**
     * Recommend ranked upsells for an Account.
     *
     * Cacheable — pure read. Caller (LWC @wire or Agentforce) can refresh after
     * captureOutcome() via notifyRecordUpdateAvailable / refreshApex.
     *
     * @param accountId target Account
     * @return ordered list, highest score first; empty when no eligible lines
     */
    @AuraEnabled(cacheable=true)
    public static List<UpsellRecommendation> recommend(Id accountId) {
        if (accountId == null) {
            return new List<UpsellRecommendation>();
        }

        Account acct = loadAccount(accountId);
        if (acct == null) {
            return new List<UpsellRecommendation>();
        }

        Set<String> existingLines = collectExistingServiceLines(acct);
        Set<String> eligibleLines = parseEligibleUpsells(acct.Eligible_Upsells__c);

        // Default eligibility: any line not already on the Account.
        if (eligibleLines.isEmpty()) {
            eligibleLines = new Set<String>(ALL_LINES);
            eligibleLines.removeAll(existingLines);
        } else {
            // Never recommend a line they already have.
            eligibleLines.removeAll(existingLines);
        }

        if (eligibleLines.isEmpty()) {
            return new List<UpsellRecommendation>();
        }

        // Per-recommendation context.
        Asset primary = pickPrimaryAsset(acct);
        Integer neighborSignal = neighborMosquitoSignups(acct);
        Integer month = Date.today().month();
        Integer tenureDays = computeTenureDays(acct.CreatedDate);

        Map<String, UpsellRecommendation> byLine = new Map<String, UpsellRecommendation>();

        for (String line : eligibleLines) {
            UpsellRecommendation rec = scoreLine(
                line, existingLines, primary, neighborSignal, month, tenureDays
            );
            byLine.put(line, rec);
        }

        // Hydrate talk-tracks in one pass — single SOQL on the metadata table.
        hydrateTalkTracks(byLine);

        // Rank: score desc, line name asc for deterministic tie-break.
        List<UpsellRecommendation> out = new List<UpsellRecommendation>(byLine.values());
        out.sort(new RecCompare());
        return out;
    }

    /**
     * Capture the outcome of a pitch. Stamps Account; spawns Lead on Yes.
     *
     * @param accountId   target Account (required)
     * @param serviceLine which line was pitched
     * @param outcome     'Yes' | 'NotNow' | 'NotInterested' | 'NoResponse'
     * @return Lead Id when outcome == 'Yes' (and Lead create succeeded), else null
     */
    @AuraEnabled
    public static Id captureOutcome(Id accountId, String serviceLine, String outcome) {
        if (accountId == null) {
            throw new AuraHandledException('Account Id is required.');
        }
        if (String.isBlank(serviceLine) || !ALL_LINES.contains(serviceLine)) {
            throw new AuraHandledException(
                'Service line must be one of Pest, Termite, Mosquito, Lawn.'
            );
        }
        if (String.isBlank(outcome)) {
            throw new AuraHandledException('Outcome is required.');
        }

        // Stamp the Account regardless of outcome — drives Manager Coaching dashboard.
        Account acct = [
            SELECT Id, Name, FirstName, LastName, BillingPostalCode, BillingStreet,
                   BillingCity, BillingState, IsPersonAccount
            FROM Account
            WHERE Id = :accountId
            WITH USER_MODE
            LIMIT 1
        ];

        Account stamp = new Account(
            Id = accountId,
            Last_Upsell_Pitched__c = System.now(),
            Last_Upsell_Service_Line__c = serviceLine,
            Last_Upsell_Outcome__c = outcome,
            Upsell_Score_Last_Updated__c = System.now()
        );
        update as user stamp;

        if (outcome != 'Yes') {
            return null;
        }

        Lead l = buildLeadFromAccount(acct, serviceLine);
        insert as user l;
        return l.Id;
    }

    // -------- Internal: scoring --------

    private static UpsellRecommendation scoreLine(
        String line,
        Set<String> existingLines,
        Asset primary,
        Integer neighborSignal,
        Integer month,
        Integer tenureDays
    ) {
        UpsellRecommendation rec = new UpsellRecommendation();
        rec.serviceLine = line;
        rec.reasonCodes = new List<String>();
        Integer score = SCORE_BASE;

        // --- Cross-sell matrix (existing lines drive which reasons fire) ---
        Boolean hasPest = existingLines.contains('Pest');
        Boolean hasTermite = existingLines.contains('Termite');
        Boolean hasMosquito = existingLines.contains('Mosquito');
        Boolean hasLawn = existingLines.contains('Lawn');

        if (line == 'Termite' && hasPest) {
            rec.reasonCodes.add('EXISTING_PEST_CUSTOMER');
            score += 10;
        }
        if (line == 'Mosquito' && hasPest) {
            rec.reasonCodes.add('EXISTING_PEST_CUSTOMER');
            score += 10;
        }
        if (line == 'Pest' && hasTermite && !hasPest) {
            rec.reasonCodes.add('TERMITE_ONLY_NO_PEST');
            score += 15;
        }
        if (line == 'Lawn' && hasMosquito) {
            rec.reasonCodes.add('OUTDOOR_FOCUSED_PROFILE');
            score += 8;
        }
        if (line == 'Mosquito' && hasLawn) {
            rec.reasonCodes.add('OUTDOOR_FOCUSED_PROFILE');
            score += 8;
        }

        // --- Seasonal multipliers (FL termite Mar-May, mosquito Apr-Oct) ---
        if (line == 'Termite' && month >= 3 && month <= 5) {
            rec.reasonCodes.add('FL_TERMITE_SEASON_PEAK');
            score += SCORE_SEASONAL;
        }
        if (line == 'Mosquito' && month >= 4 && month <= 10) {
            rec.reasonCodes.add('MOSQUITO_SEASON_ACTIVE');
            score += SCORE_SEASONAL;
        }

        // --- Neighborhood signal (only mosquito-relevant for now per Scene 5) ---
        if (line == 'Mosquito' && neighborSignal > 0) {
            rec.reasonCodes.add('NEIGHBOR_BOUGHT_MOSQUITO');
            // Diminishing returns: 1 neighbor = +10, 3+ = full +25.
            Integer bonus = Math.min(SCORE_NEIGHBOR_HIT, neighborSignal * 9);
            score += bonus;
        }

        // --- Property characteristics (from primary Asset) ---
        if (primary != null) {
            if (line == 'Termite' && primary.Conducive_Conditions__c == true) {
                rec.reasonCodes.add('CONDUCIVE_CONDITIONS_FLAGGED');
                score += SCORE_CONDUCIVE;
            }
            if (line == 'Pest' && primary.Lot_Size_Sqft__c != null
                && primary.Lot_Size_Sqft__c >= 12000) {
                rec.reasonCodes.add('LARGE_LOT_BIFEN_OPPORTUNITY');
                score += SCORE_PROPERTY_FIT;
            }
            if (line == 'Mosquito' && primary.Lot_Size_Sqft__c != null
                && primary.Lot_Size_Sqft__c >= 10000) {
                rec.reasonCodes.add('LARGE_OUTDOOR_FOOTPRINT');
                score += 5;
            }
            // Trap-catch high → mosquito recommendation gets a bump.
            if (line == 'Mosquito' && primary.Trap_Catch_Count_24h__c != null
                && primary.Trap_Catch_Count_24h__c >= 30) {
                rec.reasonCodes.add('MOSQUITO_TRAP_HIGH_CATCH');
                score += SCORE_PROPERTY_FIT;
            }
        }

        // --- Tenure (loyal customers convert better) ---
        if (tenureDays >= 365) {
            score += SCORE_TENURE_LOYAL;
        }

        // Clamp to [0, 100].
        if (score > 100) score = 100;
        if (score < 0) score = 0;
        rec.score = score;
        return rec;
    }

    /**
     * Pull matching talk-tracks via single SOQL. For each rec, prefer the talk-track
     * keyed by the *first* reason code (the cross-sell or seasonal trigger), then fall
     * back to any active talk-track for the line. Missing rows are tolerated — copy
     * stays null and the LWC falls back to a generic prompt.
     */
    private static void hydrateTalkTracks(Map<String, UpsellRecommendation> byLine) {
        if (byLine.isEmpty()) {
            return;
        }
        Set<String> lines = byLine.keySet();
        List<Upsell_Talk_Track__mdt> rows = [
            SELECT Service_Line__c, Reason_Code__c, Talk_Track__c, Estimated_Annual_Value__c
            FROM Upsell_Talk_Track__mdt
            WHERE Active__c = true AND Service_Line__c IN :lines
        ];

        // Index: line -> reasonCode -> row.
        Map<String, Map<String, Upsell_Talk_Track__mdt>> idx =
            new Map<String, Map<String, Upsell_Talk_Track__mdt>>();
        Map<String, Upsell_Talk_Track__mdt> firstByLine = new Map<String, Upsell_Talk_Track__mdt>();
        for (Upsell_Talk_Track__mdt r : rows) {
            if (!idx.containsKey(r.Service_Line__c)) {
                idx.put(r.Service_Line__c, new Map<String, Upsell_Talk_Track__mdt>());
            }
            idx.get(r.Service_Line__c).put(r.Reason_Code__c, r);
            if (!firstByLine.containsKey(r.Service_Line__c)) {
                firstByLine.put(r.Service_Line__c, r);
            }
        }

        for (UpsellRecommendation rec : byLine.values()) {
            Upsell_Talk_Track__mdt match;
            Map<String, Upsell_Talk_Track__mdt> forLine = idx.get(rec.serviceLine);
            if (forLine != null) {
                for (String reason : rec.reasonCodes) {
                    if (forLine.containsKey(reason)) {
                        match = forLine.get(reason);
                        break;
                    }
                }
            }
            if (match == null) {
                match = firstByLine.get(rec.serviceLine);
            }
            if (match != null) {
                rec.suggestedTalkTrack = match.Talk_Track__c;
                rec.estimatedAnnualValue = match.Estimated_Annual_Value__c;
            }
        }
    }

    // -------- Internal: data access --------

    private static Account loadAccount(Id accountId) {
        List<Account> acs = [
            SELECT Id, Name, CreatedDate, BillingPostalCode, BillingStreet,
                   Eligible_Upsells__c,
                   (SELECT Id, Service_Line__c, Lot_Size_Sqft__c, Property_Type__c,
                           Conducive_Conditions__c, Trap_Catch_Count_24h__c
                    FROM Assets)
            FROM Account
            WHERE Id = :accountId
            WITH USER_MODE
            LIMIT 1
        ];
        return acs.isEmpty() ? null : acs[0];
    }

    private static Set<String> collectExistingServiceLines(Account acct) {
        Set<String> lines = new Set<String>();
        if (acct.Assets != null) {
            for (Asset a : acct.Assets) {
                if (a.Service_Line__c != null) {
                    lines.add(a.Service_Line__c);
                }
            }
        }
        return lines;
    }

    private static Set<String> parseEligibleUpsells(String multiselect) {
        Set<String> out = new Set<String>();
        if (String.isBlank(multiselect)) {
            return out;
        }
        for (String v : multiselect.split(';')) {
            String trimmed = v.trim();
            if (!String.isBlank(trimmed)) {
                out.add(trimmed);
            }
        }
        return out;
    }

    private static Asset pickPrimaryAsset(Account acct) {
        if (acct.Assets == null || acct.Assets.isEmpty()) {
            return null;
        }
        // Prefer Pest asset (the recurring-relationship anchor); else first.
        for (Asset a : acct.Assets) {
            if (a.Service_Line__c == 'Pest') {
                return a;
            }
        }
        return acct.Assets[0];
    }

    /**
     * Count Mosquito Hunter signups on the same street/ZIP. Capped at
     * NEIGHBOR_LOOKUP_LIMIT — in dense ZIPs this can return thousands of rows
     * and we only need the magnitude of the social-proof signal, not the records.
     */
    private static Integer neighborMosquitoSignups(Account acct) {
        if (String.isBlank(acct.BillingPostalCode)) {
            return 0;
        }
        // Count Accounts in the same ZIP that have a Mosquito asset, excluding self.
        Integer cnt = [
            SELECT COUNT()
            FROM Account
            WHERE BillingPostalCode = :acct.BillingPostalCode
              AND Id != :acct.Id
              AND Id IN (SELECT AccountId FROM Asset WHERE Service_Line__c = 'Mosquito')
            LIMIT :NEIGHBOR_LOOKUP_LIMIT
        ];
        return cnt;
    }

    private static Integer computeTenureDays(Datetime createdDate) {
        if (createdDate == null) {
            return 0;
        }
        return Date.today().daysBetween(createdDate.date()) * -1;
    }

    // -------- Internal: lead creation --------

    private static Lead buildLeadFromAccount(Account acct, String serviceLine) {
        // Prefer Person Account FirstName/LastName if available; else split Name.
        String first = (acct.FirstName != null) ? acct.FirstName : '';
        String last  = (acct.LastName != null) ? acct.LastName  : acct.Name;
        if (String.isBlank(last)) {
            last = 'Unknown';
        }

        Lead l = new Lead(
            FirstName = String.isBlank(first) ? null : first,
            LastName = last,
            Company = (acct.Name != null) ? acct.Name : 'Massey Customer',
            Status = 'Open - Not Contacted',
            LeadSource = 'Tech Route Pitch',
            Street = acct.BillingStreet,
            City = acct.BillingCity,
            State = acct.BillingState,
            PostalCode = acct.BillingPostalCode,
            Description = 'Upsell pitch captured by tech / agent. Service line: '
                + serviceLine + '. Source Account: ' + acct.Id
                + '. Follow up via outbound call queue.'
        );
        return l;
    }

    // -------- Internal: comparator --------

    private class RecCompare implements System.Comparator<UpsellRecommendation> {
        public Integer compare(UpsellRecommendation a, UpsellRecommendation b) {
            if (a.score == b.score) {
                return a.serviceLine.compareTo(b.serviceLine);
            }
            return (b.score - a.score); // desc by score
        }
    }
}
