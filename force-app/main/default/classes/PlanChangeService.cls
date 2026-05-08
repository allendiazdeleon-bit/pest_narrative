/**
 * PlanChangeService — pest service-plan change.
 *
 * Customer requests an upgrade or change to their Massey service plan
 * — typical motion: GoGreen Pest Prevention → +Mosquito Hunter add-on,
 * or Pest+Termite → full Pest+Termite+Mosquito+Lawn bundle. We locate
 * their primary property Asset and update Plan_Tier__c. No billing
 * system is modeled — purely a picklist change. Surfaced from
 * Customer 360 / Sidekick, also callable directly by Agentforce.
 *
 * PRODUCTION REPLACEMENT: emit a billing event, await provisioning ACK,
 * confirm the new plan tier is reflected on the next quarterly visit
 * route, return enriched response.
 */
public with sharing class PlanChangeService {

    private static final Map<String, String> TIER_LABELS = new Map<String, String>{
        'GoGreen_Pest'             => 'GoGreen Pest Prevention',
        'GoGreen_Plus_Mosquito'    => 'GoGreen + Mosquito Hunter',
        'Termite_Protection'       => 'Massey Termite Protection',
        'Pest_Plus_Termite'        => 'Pest + Termite Bundle',
        'Full_Bundle'              => 'Pest + Termite + Mosquito + Lawn'
    };

    /**
     * Update the customer's primary property Asset to a new plan tier.
     * Returns the human-readable label of the new tier on success.
     *
     * @param personAccountId Person Account Id of the customer.
     * @param newTier Picklist API value (e.g. 'GoGreen_Plus_Mosquito').
     * @return The label of the new tier (e.g. "GoGreen + Mosquito Hunter").
     */
    @AuraEnabled
    public static String changeTier(Id personAccountId, String newTier) {
        if (personAccountId == null) {
            throw new AuraHandledException('personAccountId is required.');
        }
        if (String.isBlank(newTier) || !TIER_LABELS.containsKey(newTier)) {
            throw new AuraHandledException(
                'newTier must be one of: ' + String.join(new List<String>(TIER_LABELS.keySet()), ', ')
            );
        }

        Asset primary = findPrimaryAsset(personAccountId);
        if (primary == null) {
            throw new AuraHandledException(
                'No primary property Asset found for this account.'
            );
        }

        primary.Plan_Tier__c = newTier;
        update primary;

        return TIER_LABELS.get(newTier);
    }

    /**
     * Read the customer's current plan tier label. Cacheable so the LWC
     * can wire it without recomputing.
     */
    @AuraEnabled(cacheable=true)
    public static String getCurrentTier(Id personAccountId) {
        if (personAccountId == null) return null;
        Asset primary = findPrimaryAsset(personAccountId);
        if (primary == null || String.isBlank(primary.Plan_Tier__c)) return null;
        String label = TIER_LABELS.get(primary.Plan_Tier__c);
        return label != null ? label : primary.Plan_Tier__c;
    }

    /**
     * Pick the customer's primary property Asset. Preference order:
     *   1. The first Asset on the account with a Service_Line__c populated
     *   2. First Asset on the account (fallback)
     */
    private static Asset findPrimaryAsset(Id personAccountId) {
        List<Asset> assets;
        try {
            assets = [
                SELECT Id, Service_Line__c, Plan_Tier__c, AccountId
                FROM Asset
                WHERE AccountId = :personAccountId
                WITH SECURITY_ENFORCED
                ORDER BY CreatedDate ASC
                LIMIT 50
            ];
        } catch (Exception e) {
            return null;
        }
        if (assets.isEmpty()) return null;

        for (Asset a : assets) {
            if (String.isNotBlank(a.Service_Line__c)) return a;
        }
        return assets[0];
    }
}
