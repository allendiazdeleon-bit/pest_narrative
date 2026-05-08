/**
 * KnowledgeArticleSuggester — Sidekick-style AI suggester that recommends
 * Knowledge articles based on the active customer's context (open case
 * subject, recent property pest pressure, plan tier, recent visits).
 *
 * Mock-AI for the demo: deterministic keyword matching against a hardcoded
 * article catalog matching the 12 pest Knowledge articles authored in
 * P2.5. Real version would query Knowledge + use semantic embedding search.
 *
 * Massey demo (masseyFlow). Phase P3.3.
 */
public with sharing class KnowledgeArticleSuggester {

    /**
     * Suggest articles for the active customer given a free-text context
     * snippet (call-center transcript, case subject, etc.) and the
     * customer's Person Account.
     */
    @AuraEnabled(cacheable=true)
    public static List<ArticleSuggestion> suggest(Id personAccountId, String contextSnippet) {
        List<ArticleSuggestion> all = catalog();
        List<ArticleSuggestion> ranked = new List<ArticleSuggestion>();

        String ctx = (contextSnippet == null) ? '' : contextSnippet.toLowerCase();

        // Augment context with customer state
        if (personAccountId != null) {
            try {
                List<Asset> assets = [SELECT Id, Service_Line__c, Is_Pest_Pressure_Candidate__c
                                       FROM Asset WHERE AccountId = :personAccountId
                                       WITH SECURITY_ENFORCED LIMIT 5];
                for (Asset a : assets) {
                    if (a.Is_Pest_Pressure_Candidate__c) ctx += ' active pest pressure';
                    if (a.Service_Line__c != null) ctx += ' ' + a.Service_Line__c.toLowerCase();
                }
            } catch (Exception e) {
                // ignore — best effort
            }
        }

        // Score each article by keyword hit count
        for (ArticleSuggestion art : all) {
            Integer score = 0;
            for (String kw : art.keywords) {
                if (ctx.contains(kw.toLowerCase())) score += 10;
            }
            if (score > 0) {
                art.relevanceScore = score;
                art.confidence = Math.min(95, 50 + score * 4);
                ranked.add(art);
            }
        }

        // Sort desc by score
        for (Integer i = 0; i < ranked.size(); i++) {
            Integer maxIdx = i;
            for (Integer j = i + 1; j < ranked.size(); j++) {
                if (ranked[j].relevanceScore > ranked[maxIdx].relevanceScore) maxIdx = j;
            }
            if (maxIdx != i) {
                ArticleSuggestion tmp = ranked[i];
                ranked[i] = ranked[maxIdx];
                ranked[maxIdx] = tmp;
            }
        }

        // Return top 5
        List<ArticleSuggestion> result = new List<ArticleSuggestion>();
        for (Integer i = 0; i < Math.min(5, ranked.size()); i++) result.add(ranked[i]);
        return result;
    }

    /** Hardcoded article catalog covering the 12 pest articles from P2.5. */
    private static List<ArticleSuggestion> catalog() {
        return new List<ArticleSuggestion>{
            article('KA-001', 'Identifying common Florida pests', 'Visual ID guide for ants, roaches, silverfish, palmetto bugs.', new List<String>{'ant', 'ants', 'roach', 'silverfish', 'palmetto', 'identify'}),
            article('KA-002', 'Why are termite swarmers in my house?', 'FL spring termite swarm season; what to do; when to call.', new List<String>{'termite', 'swarm', 'swarmer', 'wings', 'spring'}),
            article('KA-003', 'How quarterly GoGreen Pest Prevention works', 'What\'s included; product safety; re-entry interval.', new List<String>{'quarterly', 'gogreen', 'pest prevention', 'plan', 'service'}),
            article('KA-004', 'Mosquito Hunter system overview', 'Perimeter system, monthly service, system controller.', new List<String>{'mosquito', 'mosquitoes', 'biting', 'system', 'fog', 'perimeter'}),
            article('KA-005', 'Sentricon AlwaysActive — how it works', 'Bait stations, monitoring, why no liquid-only treatment is needed.', new List<String>{'sentricon', 'bait', 'station', 'termite protection', 'alwaysactive'}),
            article('KA-006', 'Conducive conditions on your property', 'Moisture, wood-to-soil contact, mulch, what to fix yourself.', new List<String>{'conducive', 'moisture', 'mulch', 'wood', 'wet'}),
            article('KA-007', 'Re-entry interval explained', 'When pets and kids can come back outside after a treatment.', new List<String>{'re-entry', 'reentry', 'pets', 'kids', 'safe', 'reenter'}),
            article('KA-008', 'Lawn Service plan — what we do', 'Fertilization, weed/insect control, seasonal program.', new List<String>{'lawn', 'turf', 'fertilizer', 'weed', 'grass'}),
            article('KA-009', 'I see ants in my kitchen — what now?', 'Triage steps for active ant intrusion before tech arrives.', new List<String>{'ants kitchen', 'ant trail', 'sugar ants', 'intrusion'}),
            article('KA-010', 'Moving service to a new home', 'Transfer flow, address validation, what carries over.', new List<String>{'move', 'transfer', 'new address', 'relocate'}),
            article('KA-011', 'Whole-home tent fumigation prep guide', 'Bag food, plan kennels, when re-entry is safe.', new List<String>{'tent', 'fumigation', 'vikane', 'sulfuryl', 'fumigate'}),
            article('KA-012', 'Bait station status — what the colors mean', 'Reading Sentricon station hits; when to call; what is normal.', new List<String>{'bait station', 'hits', 'feeding', 'monitoring', 'station status'})
        };
    }

    private static ArticleSuggestion article(String id, String title, String summary, List<String> keywords) {
        ArticleSuggestion a = new ArticleSuggestion();
        a.articleId = id;
        a.title = title;
        a.summary = summary;
        a.keywords = keywords;
        a.relevanceScore = 0;
        a.confidence = 0;
        a.source = 'KnowledgeArticleSuggester';
        return a;
    }

    public class ArticleSuggestion {
        @AuraEnabled public String articleId;
        @AuraEnabled public String title;
        @AuraEnabled public String summary;
        @AuraEnabled public List<String> keywords;
        @AuraEnabled public Integer relevanceScore;
        @AuraEnabled public Decimal confidence;
        @AuraEnabled public String source;
    }
}
