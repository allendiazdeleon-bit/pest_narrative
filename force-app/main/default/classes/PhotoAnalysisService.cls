/**
 * PhotoAnalysisService — DEMO-ONLY simulated AI vision analysis for
 * Massey field photos.
 *
 * In a production build, analyzePhoto() would post the ContentVersion's
 * VersionData to a vision endpoint (Einstein Vision, Bedrock Claude
 * Vision, GPT-4o, etc.) and parse the structured response. For the
 * masseyFlow demo this is FAKED deterministically so the storyline
 * lands without external dependencies or network from the FSL Mobile
 * app. The fake matches on the photo's filename / Title against a
 * curated set of pest-themed templates and falls back to a default
 * "active termite damage" analysis if nothing matches.
 *
 * Surfaces this is wired into:
 *  - masseyFlow Site Assessment step (bait stations, conducive conditions, swarmers)
 *  - Agent Sidekick "what does the tech see?" panel (Jordan can review
 *    Maria's mid-route photos)
 *  - Dispatcher Console photo-review side panel
 *
 * Per CLAUDE.md, this is a `demoMagic`-style mock — convincing but
 * entirely scripted. Replace before any non-demo deployment.
 */
public with sharing class PhotoAnalysisService {

    public class AnalysisResult {
        @AuraEnabled public String title;
        @AuraEnabled public String description;
        @AuraEnabled public String severity;            // Low | Medium | High | Critical
        @AuraEnabled public Decimal confidence;         // 0.0 - 1.0
        @AuraEnabled public List<String> recommendedActions;
        @AuraEnabled public List<String> tags;
        @AuraEnabled public Id contentVersionId;
        @AuraEnabled public String analyzedFileName;

        public AnalysisResult() {
            this.recommendedActions = new List<String>();
            this.tags = new List<String>();
        }
    }

    @AuraEnabled(cacheable=false)
    public static AnalysisResult analyzePhoto(Id contentVersionId) {
        if (contentVersionId == null) {
            throw new AuraHandledException('contentVersionId is required.');
        }

        ContentVersion cv;
        try {
            cv = [
                SELECT Id, Title, PathOnClient, FileType, ContentSize, CreatedDate
                FROM ContentVersion
                WHERE Id = :contentVersionId
                LIMIT 1
            ];
        } catch (QueryException e) {
            throw new AuraHandledException('ContentVersion not found: ' + contentVersionId);
        }

        AnalysisResult result = matchTemplate(cv.Title, cv.PathOnClient);
        result.contentVersionId = cv.Id;
        result.analyzedFileName = String.isNotBlank(cv.PathOnClient) ? cv.PathOnClient : cv.Title;
        return result;
    }

    @AuraEnabled(cacheable=false)
    public static AnalysisResult analyzeMostRecentPhoto(Id workOrderId) {
        if (workOrderId == null) {
            throw new AuraHandledException('workOrderId is required.');
        }

        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :workOrderId
        ];
        if (links.isEmpty()) {
            return null;
        }

        Set<Id> docIds = new Set<Id>();
        for (ContentDocumentLink l : links) {
            docIds.add(l.ContentDocumentId);
        }

        List<ContentVersion> versions = [
            SELECT Id, Title, PathOnClient, FileType, ContentSize, CreatedDate
            FROM ContentVersion
            WHERE ContentDocumentId IN :docIds
              AND IsLatest = true
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        if (versions.isEmpty()) {
            return null;
        }

        ContentVersion cv = versions[0];
        AnalysisResult result = matchTemplate(cv.Title, cv.PathOnClient);
        result.contentVersionId = cv.Id;
        result.analyzedFileName = String.isNotBlank(cv.PathOnClient) ? cv.PathOnClient : cv.Title;
        return result;
    }

    @TestVisible
    private static AnalysisResult matchTemplate(String title, String pathOnClient) {
        String haystack = ((title == null ? '' : title) + ' ' + (pathOnClient == null ? '' : pathOnClient)).toLowerCase();

        if (containsAny(haystack, new List<String>{ 'bait', 'station', 'sentricon', 'monitoring' })) {
            return templateBaitStationActive();
        }
        if (containsAny(haystack, new List<String>{ 'termite', 'swarm', 'swarmer', 'mud tube' })) {
            return templateTermiteActivity();
        }
        if (containsAny(haystack, new List<String>{ 'mosquito', 'standing water', 'breeding' })) {
            return templateMosquitoBreedingSource();
        }
        if (containsAny(haystack, new List<String>{ 'mulch', 'wood', 'moisture', 'conducive' })) {
            return templateConduciveConditions();
        }
        if (containsAny(haystack, new List<String>{ 'ant', 'roach', 'silverfish', 'palmetto' })) {
            return templateActivePestIntrusion();
        }
        if (containsAny(haystack, new List<String>{ 'lawn', 'turf', 'chinch', 'brown patch' })) {
            return templateLawnDistress();
        }
        if (containsAny(haystack, new List<String>{ 'clear', 'ok', 'noissue', 'no-issue', 'clean', 'baseline', 'before' })) {
            return templateSiteClear();
        }

        // Deterministic fallback
        List<AnalysisResult> rotation = new List<AnalysisResult>{
            templateBaitStationActive(),
            templateTermiteActivity(),
            templateMosquitoBreedingSource(),
            templateConduciveConditions(),
            templateActivePestIntrusion(),
            templateLawnDistress()
        };
        Integer idx = Math.abs(haystack.trim().hashCode()) | 0;
        return rotation[Math.mod(idx, rotation.size())];
    }

    private static Boolean containsAny(String haystack, List<String> needles) {
        if (String.isBlank(haystack)) return false;
        for (String n : needles) {
            if (haystack.contains(n)) return true;
        }
        return false;
    }

    private static AnalysisResult templateBaitStationActive() {
        AnalysisResult r = new AnalysisResult();
        r.title = 'Sentricon station — active termite feeding';
        r.description = 'Sentricon monitoring station shows fresh termite activity inside the bait '
            + 'matrix. Workers (Reticulitermes flavipes) visible in the active gallery; cellulose '
            + 'consumption pattern is consistent with a feeding population in the past 14 days. '
            + 'Confirms the property has an active subterranean termite colony.';
        r.severity = 'High';
        r.confidence = 0.92;
        r.recommendedActions = new List<String>{
            'Replace the bait matrix with fresh AlwaysActive bait',
            'Photograph the active station for the property file',
            'Check adjacent stations on the same elevation for spread',
            'Brief the homeowner — this is exactly what the system is designed to catch'
        };
        r.tags = new List<String>{ 'sentricon', 'termite', 'bait', 'active-feeding' };
        return r;
    }

    private static AnalysisResult templateTermiteActivity() {
        AnalysisResult r = new AnalysisResult();
        r.title = 'Termite swarmers + mud tube — active subterranean infestation';
        r.description = 'Photo shows discarded swarmer wings near a window sill plus a fresh mud tube '
            + 'climbing the foundation block. The mud tube is moist (active construction within '
            + '~48 hours). Combined with the season (FL spring swarm window), this is an active '
            + 'subterranean termite colony, not residual evidence.';
        r.severity = 'High';
        r.confidence = 0.89;
        r.recommendedActions = new List<String>{
            'Schedule an immediate Sentricon install if not already protected',
            'Photograph the mud tube before disturbing for the property file',
            'Inspect interior wall plates above the tube termination for damage',
            'Quote the homeowner Massey Termite Protection if not currently subscribed'
        };
        r.tags = new List<String>{ 'termite', 'swarmer', 'mud-tube', 'subterranean' };
        return r;
    }

    private static AnalysisResult templateMosquitoBreedingSource() {
        AnalysisResult r = new AnalysisResult();
        r.title = 'Mosquito breeding source — Aedes larvae visible';
        r.description = 'Photo shows standing water (clogged storm drain / bird bath / tarp pocket) '
            + 'with visible Aedes aegypti larvae and pupae. Estimated population density is '
            + 'consistent with a 5-7 day breeding event. Untreated, this single source can produce '
            + '~1,000 adult mosquitoes per square meter of water.';
        r.severity = 'High';
        r.confidence = 0.94;
        r.recommendedActions = new List<String>{
            'Apply larvicide tablets directly to the water (Bti or methoprene)',
            'Drain the source if customer-owned (tarp, planter, gutter)',
            'Open a 311 ticket with City of Orlando if it\'s a municipal storm drain',
            'ULV fog the surrounding 50-ft perimeter to knock down adult population'
        };
        r.tags = new List<String>{ 'mosquito', 'aedes', 'larvae', 'breeding-source', 'standing-water' };
        return r;
    }

    private static AnalysisResult templateConduciveConditions() {
        AnalysisResult r = new AnalysisResult();
        r.title = 'Conducive conditions — wood-to-soil + moisture ingress';
        r.description = 'Photo shows wood mulch piled directly against the foundation slab plus a '
            + 'partially-rotted decorative timber within 3 ft of an exterior wall. A/C condensate '
            + 'line discharges into the same area, keeping the soil saturated. This is a textbook '
            + 'conducive-conditions pattern — termite, carpenter ant, and earwig populations all '
            + 'thrive here.';
        r.severity = 'Medium';
        r.confidence = 0.86;
        r.recommendedActions = new List<String>{
            'Note conducive_conditions = true on the property',
            'Brief the homeowner: pull mulch back 6 in from foundation; redirect A/C condensate',
            'Add a perimeter spray pass on this elevation',
            'Schedule a follow-up inspection in 60 days if homeowner agrees to remediate'
        };
        r.tags = new List<String>{ 'conducive', 'mulch', 'moisture', 'wood-to-soil' };
        return r;
    }

    private static AnalysisResult templateActivePestIntrusion() {
        AnalysisResult r = new AnalysisResult();
        r.title = 'Active pest intrusion — sugar ants + entry point identified';
        r.description = 'Photo shows an active foraging trail of small sugar ants (likely '
            + 'Tapinoma sessile / odorous house ants) emerging from a baseboard gap and tracking '
            + 'toward a kitchen counter. Trail width and continuous traffic suggest the colony '
            + 'is well-established, likely in an exterior wall void.';
        r.severity = 'Medium';
        r.confidence = 0.91;
        r.recommendedActions = new List<String>{
            'Apply non-repellent gel bait at the trail entry point',
            'Locate exterior entry — likely a utility penetration or weep hole',
            'Perimeter spray with non-repellent product on this elevation',
            'Schedule a 14-day follow-up to confirm colony elimination'
        };
        r.tags = new List<String>{ 'ants', 'intrusion', 'foraging-trail', 'kitchen' };
        return r;
    }

    private static AnalysisResult templateLawnDistress() {
        AnalysisResult r = new AnalysisResult();
        r.title = 'Lawn distress — chinch bug damage in St. Augustine turf';
        r.description = 'Photo shows yellow-to-brown patches in St. Augustine turf with a sharp '
            + 'expanding-circle pattern characteristic of chinch bug damage. Patch margins show '
            + 'the classic "irregular die-back" shape rather than the uniform pattern of brown '
            + 'patch fungus or under-watering.';
        r.severity = 'Medium';
        r.confidence = 0.88;
        r.recommendedActions = new List<String>{
            'Treat affected zone with bifenthrin granular per label rate',
            'Recommend customer increase irrigation frequency on the affected zone',
            'Photograph the patch margin for the next route\'s before/after comparison',
            'Schedule a 21-day follow-up to confirm recovery'
        };
        r.tags = new List<String>{ 'lawn', 'chinch-bug', 'st-augustine', 'turf-damage' };
        return r;
    }

    private static AnalysisResult templateSiteClear() {
        AnalysisResult r = new AnalysisResult();
        r.title = 'Site appears clear — no visible pest activity';
        r.description = 'Image shows the property in apparently normal condition. No visible '
            + 'pest activity, conducive conditions, or environmental hazard within frame. '
            + 'Lighting and angle are sufficient for a baseline reference photo. Recommend '
            + 'retaining as the "before" image for this work order.';
        r.severity = 'Low';
        r.confidence = 0.78;
        r.recommendedActions = new List<String>{
            'Retain as the baseline / pre-treatment reference image',
            'Proceed with planned scope; capture a matching "after" photo on close-out'
        };
        r.tags = new List<String>{ 'baseline', 'no-issue', 'reference' };
        return r;
    }
}
