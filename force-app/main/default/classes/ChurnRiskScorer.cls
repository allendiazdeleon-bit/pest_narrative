/**
 * ChurnRiskScorer — Mock-AI customer churn-risk scorer for Massey Services.
 *
 * Returns a 0-100 risk score, tier label, top contributing signals, and
 * 0-3 retention-offer suggestions for a Person Account. Used by the
 * Customer 360 LWC + Agent Sidekick when a long-tenure GoGreen customer
 * (or anyone) is reaching out about cancelling — Scene 2 / 3 territory.
 *
 * The score is computed deterministically from real data:
 *   - Count of Cases in the last 90 days (more cases → higher risk)
 *   - Asset.Is_Pest_Pressure_Candidate__c (active pest pressure drag)
 *   - Mock account tenure (1-10 years, deterministic by Account Id hash)
 *   - 1-2 simulated extra signals per account (engagement gap,
 *     competitor notice) selected by Account Id hash so the same
 *     account always shows the same signals
 *
 * Retention offers are gated by tier:
 *   - Critical → up to $100 credit + free quarter
 *   - High    → $50 credit + free Mosquito Hunter trial
 *   - Medium  → small goodwill credit
 *   - Low     → no offer (no need)
 *
 * PRODUCTION REPLACEMENT: train an Einstein Discovery model on
 * historical churn outcomes and consume the predicted score back here.
 */
public with sharing class ChurnRiskScorer {

    // ---------------------------------------------------------------------
    // DTOs
    // ---------------------------------------------------------------------

    public class RetentionOffer {
        @AuraEnabled public String label;
        @AuraEnabled public Decimal amount;          // dollars; null for non-monetary
        @AuraEnabled public String eligibility;      // 'eligible' | 'requires-supervisor' | 'not-eligible'
        @AuraEnabled public String description;
    }

    public class ChurnRiskAssessment {
        @AuraEnabled public Id personAccountId;
        @AuraEnabled public Decimal riskScore;        // 0-100
        @AuraEnabled public String tier;              // 'Low'|'Medium'|'High'|'Critical'
        @AuraEnabled public List<String> topSignals;
        @AuraEnabled public List<RetentionOffer> retentionOffers;
        @AuraEnabled public Integer tenureYears;
        @AuraEnabled public Integer recentCaseCount;
        @AuraEnabled public String summary;
        @AuraEnabled public Decimal confidence;
        @AuraEnabled public String source;
        @AuraEnabled public DateTime generatedAt;

        public ChurnRiskAssessment() {
            this.topSignals = new List<String>();
            this.retentionOffers = new List<RetentionOffer>();
        }
    }

    // ---------------------------------------------------------------------
    // Public entry point
    // ---------------------------------------------------------------------

    @AuraEnabled(cacheable=true)
    public static ChurnRiskAssessment score(Id personAccountId) {
        if (personAccountId == null) {
            throw new AuraHandledException('personAccountId is required.');
        }

        ChurnRiskAssessment a = new ChurnRiskAssessment();
        a.personAccountId = personAccountId;
        a.source = 'ChurnRiskScorer + Case + Asset history';
        a.generatedAt = DateTime.now();

        // ---- Tenure (mock — 1-10 years deterministic by Id hash) ----
        Integer tenureHash = Math.abs((String.valueOf(personAccountId) + ':tenure').hashCode());
        a.tenureYears = 1 + Math.mod(tenureHash, 10);

        // ---- Case volume in last 90 days ----
        DateTime windowStart = DateTime.now().addDays(-90);
        Integer caseCount = [
            SELECT COUNT()
            FROM Case
            WHERE AccountId = :personAccountId
              AND CreatedDate >= :windowStart
            WITH SECURITY_ENFORCED
        ];
        a.recentCaseCount = caseCount;

        // ---- Asset / property health ----
        List<Asset> assets;
        try {
            assets = [
                SELECT Id, Service_Line__c, Is_Pest_Pressure_Candidate__c
                FROM Asset
                WHERE AccountId = :personAccountId
                WITH SECURITY_ENFORCED
                LIMIT 5
            ];
        } catch (Exception e) {
            assets = new List<Asset>();
        }
        Boolean anyPressure = false;
        for (Asset asset : assets) {
            if (asset.Is_Pest_Pressure_Candidate__c == true) anyPressure = true;
        }

        // ---- Score derivation ----
        Decimal score = 0;

        if (caseCount >= 3) {
            score += 35;
            a.topSignals.add(caseCount + ' cases in last 90 days — repeated friction.');
        } else if (caseCount == 2) {
            score += 18;
            a.topSignals.add('2 cases in last 90 days — elevated friction.');
        } else if (caseCount == 1) {
            score += 6;
        }

        if (anyPressure) {
            score += 22;
            a.topSignals.add('Active pest pressure on the property — predictive watch.');
        }

        // Tenure: very new (<2 yrs) and very old (>8 yrs) are demographic
        // churn cohorts. Mid-tenure is sticky.
        if (a.tenureYears < 2) {
            score += 12;
            a.topSignals.add('New customer (' + a.tenureYears + ' yr tenure) — early-life churn risk.');
        } else if (a.tenureYears >= 8) {
            score += 8;
            a.topSignals.add('Long-tenure customer (' + a.tenureYears
                + ' yrs) — re-eval cohort, susceptible to competitor offers.');
        }

        // Deterministic synthetic signals — pick 1-2 from a fixed library
        // based on account-id hash. Demo realism without random output.
        Integer sigHash = Math.abs((String.valueOf(personAccountId) + ':sig').hashCode());
        if (Math.mod(sigHash, 3) == 0) {
            score += 10;
            a.topSignals.add('No portal engagement in 60+ days.');
        }
        if (Math.mod(sigHash / 5, 4) == 1) {
            score += 12;
            a.topSignals.add('Competitor in market notice — Truly Nolen door hangers reported in service area.');
        }
        if (Math.mod(sigHash / 11, 5) == 2) {
            score += 8;
            a.topSignals.add('Mentioned cancelling on previous call — sentiment drag.');
        }

        if (score > 100) score = 100;
        a.riskScore = score.setScale(0);

        // ---- Tier ----
        if (score >= 70) a.tier = 'Critical';
        else if (score >= 50) a.tier = 'High';
        else if (score >= 25) a.tier = 'Medium';
        else a.tier = 'Low';

        // ---- Retention offers ----
        a.retentionOffers = buildOffers(a.tier, a.tenureYears, anyPressure);

        // ---- Confidence + summary ----
        a.confidence = Math.min(92, 65 + a.topSignals.size() * 6);

        if (a.topSignals.isEmpty()) {
            a.topSignals.add('No churn signals detected — healthy account.');
        }
        a.summary = 'Churn tier ' + a.tier + ' (' + a.riskScore + '/100). '
            + a.recentCaseCount + ' recent case'
            + (a.recentCaseCount == 1 ? '' : 's') + ', '
            + a.tenureYears + '-yr tenure. '
            + (a.retentionOffers.isEmpty()
                ? 'No retention offer needed at this tier.'
                : a.retentionOffers.size() + ' retention offer'
                    + (a.retentionOffers.size() == 1 ? '' : 's') + ' available.');
        return a;
    }

    // ---------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------

    private static List<RetentionOffer> buildOffers(String tier, Integer tenureYears, Boolean activePressure) {
        List<RetentionOffer> offers = new List<RetentionOffer>();
        if (tier == 'Critical') {
            offers.add(makeOffer('One-Time Credit',          100, 'requires-supervisor',
                'Maximum first-pass save credit. Supervisor approval required above $50.'));
            offers.add(makeOffer('Free Quarterly Visit',     null, 'eligible',
                'Waive next quarterly GoGreen visit fee; positions us to demonstrate value before billing recurs.'));
            offers.add(makeOffer('Service-Call No Charge',     0,   'eligible',
                'Waive standard service-call fee on next emergency truck roll.'));
        } else if (tier == 'High') {
            offers.add(makeOffer('One-Time Credit',          50, 'eligible',
                'Standard first-pass save credit. Auto-applied on next bill.'));
            offers.add(makeOffer('Mosquito Hunter Trial',   null, 'eligible',
                'Free 30-day Mosquito Hunter trial — demonstrates cross-line value, sets up an attach.'));
        } else if (tier == 'Medium') {
            offers.add(makeOffer('Goodwill Credit',          25, 'eligible',
                'Light-touch goodwill credit; reinforces loyalty without flagging the account as save-pool.'));
        }
        // Add a pest-pressure specific offer regardless of tier when applicable.
        if (activePressure && tier != 'Low') {
            offers.add(makeOffer('Booster Treatment Visit', null, 'eligible',
                'Schedule a same-week booster visit to address active pest pressure before the next quarterly.'));
        }
        // Long-tenure recognition
        if (tenureYears >= 8 && (tier == 'High' || tier == 'Critical')) {
            offers.add(makeOffer('Loyalty Recognition Bonus', 25, 'eligible',
                'Recognition credit for ' + tenureYears + '-year tenure.'));
        }
        return offers;
    }

    private static RetentionOffer makeOffer(String label, Decimal amount, String eligibility, String description) {
        RetentionOffer o = new RetentionOffer();
        o.label = label;
        o.amount = amount;
        o.eligibility = eligibility;
        o.description = description;
        return o;
    }
}
