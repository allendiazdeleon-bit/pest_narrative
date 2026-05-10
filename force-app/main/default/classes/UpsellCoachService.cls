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
        return captureOutcomeWithQuote(accountId, serviceLine, outcome, null);
    }

    /**
     * Same as captureOutcome but also marks an existing Quote as Accepted on
     * outcome='Yes' or 'QuotedYes'. The masseyUpsellCoach LWC calls this
     * variant after generateQuote().
     */
    @AuraEnabled
    public static Id captureOutcomeWithQuote(Id accountId, String serviceLine, String outcome, Id quoteId) {
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

        Boolean isYes = (outcome == 'Yes' || outcome == 'QuotedYes');

        // Mark the Quote accepted if one was attached and customer said yes.
        if (isYes && quoteId != null) {
            try {
                Quote q = new Quote(Id = quoteId, Status = 'Accepted');
                update q;
            } catch (Exception e) {
                System.debug(LoggingLevel.WARN, 'Quote update skipped: ' + e.getMessage());
            }
        }

        if (!isYes) {
            return null;
        }

        Lead l = buildLeadFromAccount(acct, serviceLine);
        if (quoteId != null) {
            l.Description = (l.Description == null ? '' : l.Description + '\n\n')
                + 'Linked Quote: ' + quoteId;
        }
        insert as user l;
        return l.Id;
    }

    // -------- Quote generation --------

    public class QuoteEstimate {
        @AuraEnabled public Id quoteId;
        @AuraEnabled public String quoteNumber;
        @AuraEnabled public String displayName;        // e.g., "Mosquito Hunter Perimeter Misting System"
        @AuraEnabled public String sku;                // e.g., "MOSQUITO_HUNTER"
        @AuraEnabled public String serviceLine;
        @AuraEnabled public Decimal installFee;
        @AuraEnabled public Decimal monthlyService;
        @AuraEnabled public Decimal annualY1Subtotal;  // before discount
        @AuraEnabled public Decimal bundleDiscountPct; // 0–100
        @AuraEnabled public Decimal bundleDiscountAmount; // negative absolute amount
        @AuraEnabled public Decimal annualY1Total;     // after discount
        @AuraEnabled public Boolean bundleApplied;
        @AuraEnabled public String inclusions;
        @AuraEnabled public String warrantyDescription;
    }

    /**
     * Generate (or reuse) a Quote for an Account + service line. Reads pricing
     * from Upsell_Pricing__mdt, applies the bundle discount if the Account
     * already has another Massey service line on Eligible_Upsells__c, and
     * persists a real Quote + QuoteLineItems anchored to a back-staged
     * Opportunity. Returns a flat estimate DTO for the LWC to render.
     *
     * Idempotent — finds an existing Draft/Presented Quote for this Account+Sku
     * before creating a new one.
     */
    @AuraEnabled
    public static QuoteEstimate generateQuote(Id accountId, String serviceLine) {
        if (accountId == null) throw new AuraHandledException('Account Id is required.');
        if (String.isBlank(serviceLine) || !ALL_LINES.contains(serviceLine)) {
            throw new AuraHandledException('Service line must be one of Pest, Termite, Mosquito, Lawn.');
        }

        // Default SKU per service line (Termite defaults to Sentricon).
        String sku = defaultSkuForLine(serviceLine);

        Upsell_Pricing__mdt pricing;
        for (Upsell_Pricing__mdt p : [SELECT Sku__c, Service_Line__c, Display_Name__c,
                                             Install_Fee__c, Monthly_Service__c,
                                             Annual_Y1_Estimate__c, Bundle_Discount_Pct__c,
                                             Inclusions__c, Warranty_Description__c, Active__c
                                      FROM Upsell_Pricing__mdt
                                      WHERE Sku__c = :sku AND Active__c = true
                                      LIMIT 1]) {
            pricing = p;
        }
        if (pricing == null) {
            throw new AuraHandledException('No pricing found for SKU ' + sku + '.');
        }

        // Bundle: customer already has at least one Massey line.
        Account acct = [SELECT Id, Name, Eligible_Upsells__c, OwnerId
                        FROM Account WHERE Id = :accountId LIMIT 1];
        Set<String> alreadyHas = currentLinesForAccount(acct);
        Boolean bundleApplies = (pricing.Bundle_Discount_Pct__c != null
                                 && pricing.Bundle_Discount_Pct__c > 0
                                 && !alreadyHas.isEmpty());

        Decimal installFee = pricing.Install_Fee__c == null ? 0 : pricing.Install_Fee__c;
        Decimal monthly = pricing.Monthly_Service__c == null ? 0 : pricing.Monthly_Service__c;
        Decimal annualSubtotal = installFee + (monthly * 12);
        Decimal discountPct = bundleApplies ? pricing.Bundle_Discount_Pct__c : 0;
        Decimal discountAmount = bundleApplies ? (annualSubtotal * discountPct / 100).setScale(2) : 0;
        Decimal annualTotal = annualSubtotal - discountAmount;

        // 1. Find or create Opportunity
        String oppName = '[MSY-DEMO] Upsell — ' + pricing.Display_Name__c + ' — ' + acct.Name;
        Opportunity opp;
        for (Opportunity o : [SELECT Id, Name FROM Opportunity
                              WHERE Name = :oppName AND AccountId = :accountId LIMIT 1]) {
            opp = o;
        }
        if (opp == null) {
            opp = new Opportunity(
                Name = oppName,
                AccountId = accountId,
                StageName = 'Qualification',
                CloseDate = Date.today().addDays(30),
                Amount = annualTotal
            );
            insert opp;
        }

        // 2. Find pricebook + product entries
        Pricebook2 masseyPb;
        for (Pricebook2 pb : [SELECT Id FROM Pricebook2
                              WHERE Name = 'Massey Pest Pricebook' AND IsActive = true LIMIT 1]) {
            masseyPb = pb;
        }
        if (masseyPb == null) {
            // Fall back to standard pricebook.
            masseyPb = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1];
        }

        Map<String, PricebookEntry> pbeByCode = new Map<String, PricebookEntry>();
        for (PricebookEntry pbe : [SELECT Id, Product2.ProductCode, UnitPrice
                                   FROM PricebookEntry
                                   WHERE Pricebook2Id = :masseyPb.Id
                                   AND Product2.ProductCode IN (:sku + '_INSTALL', :sku + '_MONTHLY', 'BUNDLE_DISCOUNT')
                                   AND IsActive = true]) {
            pbeByCode.put(pbe.Product2.ProductCode, pbe);
        }

        // 3. Find or create Quote
        String quoteName = pricing.Display_Name__c + ' — ' + acct.Name;
        Quote q;
        for (Quote existing : [SELECT Id, QuoteNumber, Name, Status FROM Quote
                               WHERE OpportunityId = :opp.Id
                               AND Name = :quoteName
                               AND Status IN ('Draft', 'Presented', 'Needs Review')
                               LIMIT 1]) {
            q = existing;
        }
        if (q == null) {
            q = new Quote(
                Name = quoteName,
                OpportunityId = opp.Id,
                Pricebook2Id = masseyPb.Id,
                Status = 'Presented',
                ExpirationDate = Date.today().addDays(30),
                Description = pricing.Inclusions__c
            );
            insert q;
            // Re-query to pick up QuoteNumber
            q = [SELECT Id, QuoteNumber, Name, Status FROM Quote WHERE Id = :q.Id LIMIT 1];

            // Create QLIs only on first create (existing quote keeps its lines).
            List<QuoteLineItem> qlis = new List<QuoteLineItem>();
            if (installFee > 0 && pbeByCode.containsKey(sku + '_INSTALL')) {
                PricebookEntry pbe = pbeByCode.get(sku + '_INSTALL');
                qlis.add(new QuoteLineItem(
                    QuoteId = q.Id, PricebookEntryId = pbe.Id,
                    Quantity = 1, UnitPrice = installFee,
                    Description = 'One-time install / setup'
                ));
            }
            if (monthly > 0 && pbeByCode.containsKey(sku + '_MONTHLY')) {
                PricebookEntry pbe = pbeByCode.get(sku + '_MONTHLY');
                qlis.add(new QuoteLineItem(
                    QuoteId = q.Id, PricebookEntryId = pbe.Id,
                    Quantity = 12, UnitPrice = monthly,
                    Description = 'Year 1 monthly service (12 months)'
                ));
            }
            if (bundleApplies && pbeByCode.containsKey('BUNDLE_DISCOUNT')) {
                PricebookEntry pbe = pbeByCode.get('BUNDLE_DISCOUNT');
                qlis.add(new QuoteLineItem(
                    QuoteId = q.Id, PricebookEntryId = pbe.Id,
                    Quantity = 1, UnitPrice = -1 * discountAmount,
                    Description = 'Existing-customer bundle discount (' + discountPct + '%)'
                ));
            }
            if (!qlis.isEmpty()) insert qlis;
        }

        QuoteEstimate est = new QuoteEstimate();
        est.quoteId = q.Id;
        est.quoteNumber = q.QuoteNumber;
        est.displayName = pricing.Display_Name__c;
        est.sku = sku;
        est.serviceLine = serviceLine;
        est.installFee = installFee;
        est.monthlyService = monthly;
        est.annualY1Subtotal = annualSubtotal;
        est.bundleDiscountPct = discountPct;
        est.bundleDiscountAmount = discountAmount;
        est.annualY1Total = annualTotal;
        est.bundleApplied = bundleApplies;
        est.inclusions = pricing.Inclusions__c;
        est.warrantyDescription = pricing.Warranty_Description__c;
        return est;
    }

    private static String defaultSkuForLine(String line) {
        if (line == 'Pest') return 'GOGREEN_PEST';
        if (line == 'Termite') return 'TERMITE_SENTRICON';
        if (line == 'Mosquito') return 'MOSQUITO_HUNTER';
        if (line == 'Lawn') return 'LAWN_CARE';
        return 'GOGREEN_PEST';
    }

    private static Set<String> currentLinesForAccount(Account a) {
        // Eligible_Upsells__c is the COMPLEMENT (what they don't have).
        // Compute "what they DO have" = ALL_LINES \ Eligible_Upsells__c.
        Set<String> eligible = new Set<String>();
        if (String.isNotBlank(a.Eligible_Upsells__c)) {
            for (String s : a.Eligible_Upsells__c.split(';')) {
                eligible.add(s.trim());
            }
        }
        Set<String> currentLines = new Set<String>(ALL_LINES);
        currentLines.removeAll(eligible);
        return currentLines;
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
