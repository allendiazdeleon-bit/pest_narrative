/**
 * RemoteRemediationService — limited remote-action service for Massey.
 *
 * Pest control has a much narrower remote-action surface than connected-
 * device service models — most pest issues require a physical truck roll.
 * The one analog we model:
 * a customer's Mosquito Hunter system controller can be remotely triggered
 * for a manual fog cycle (e.g., before a backyard event), or its tank-level
 * status can be polled. For everything else (active pest sighting, termite
 * swarm, lawn distress) the response is always "EscalateToTruck" — there
 * is no remote-fix path.
 *
 * DECISION FLAG: Massey's product mix doesn't have a clean device-side
 * remote-fix analog (reboot / resync), so this service is a thin stub.
 * The few remote actions that DO exist (Mosquito Hunter manual fog
 * trigger, tank check) are wired here for completeness.
 *
 * PRODUCTION REPLACEMENT: real Mosquito Hunter system integration via
 * the manufacturer API; await ACK + post-action sensor reading.
 */
public with sharing class RemoteRemediationService {

    // ---------------------------------------------------------------------
    // DTOs
    // ---------------------------------------------------------------------

    public class RemediationResponse {
        @AuraEnabled @InvocableVariable public String outcome;          // 'Resolved' | 'NoChange' | 'EscalateToTruck'
        @AuraEnabled @InvocableVariable public String strategy;         // 'Manual Mosquito Fog Cycle' | 'Tank Level Check' | 'No Remote Action'
        @AuraEnabled @InvocableVariable public String summary;
        @AuraEnabled @InvocableVariable public Decimal confidence;      // 0-100
        @AuraEnabled @InvocableVariable public String source;
        @AuraEnabled @InvocableVariable public DateTime generatedAt;
        @AuraEnabled @InvocableVariable public Integer latencyMs;       // simulated round-trip
        @AuraEnabled @InvocableVariable public Id assetId;
    }

    public class RemediationRequest {
        @InvocableVariable(required=true) public Id assetId;
        @InvocableVariable public Id personAccountId;
    }

    // Outcome-probability tunings per strategy (out of 100).
    private static final Integer FOG_CYCLE_RESOLVE_PCT  = 60;
    private static final Integer TANK_CHECK_RESOLVE_PCT = 50;

    // ---------------------------------------------------------------------
    // Public entry points
    // ---------------------------------------------------------------------

    @AuraEnabled
    public static RemediationResponse triggerMosquitoFogCycle(Id assetId) {
        return runStrategy(assetId, 'Manual Mosquito Fog Cycle', FOG_CYCLE_RESOLVE_PCT);
    }

    @AuraEnabled
    public static RemediationResponse checkTankLevel(Id assetId) {
        return runStrategy(assetId, 'Tank Level Check', TANK_CHECK_RESOLVE_PCT);
    }

    /**
     * Agentforce-invocable wrapper. Picks the strategy based on the
     * Asset's Service_Line__c — only Mosquito Hunter has a remote-action
     * surface. Everything else returns EscalateToTruck.
     */
    @InvocableMethod(label='Attempt Remote Remediation' description='Try a remote action against the customer\'s property equipment (limited to Mosquito Hunter systems). Returns Resolved / NoChange / EscalateToTruck.')
    public static List<RemediationResponse> attemptRemoteRemediation(List<RemediationRequest> requests) {
        List<RemediationResponse> out = new List<RemediationResponse>();
        if (requests == null || requests.isEmpty()) return out;

        Set<Id> assetIds = new Set<Id>();
        for (RemediationRequest r : requests) if (r.assetId != null) assetIds.add(r.assetId);

        Map<Id, Asset> assetById = new Map<Id, Asset>();
        if (!assetIds.isEmpty()) {
            for (Asset a : [
                SELECT Id, Service_Line__c, AccountId, Is_Pest_Pressure_Candidate__c
                FROM Asset
                WHERE Id IN :assetIds
                WITH SECURITY_ENFORCED
            ]) {
                assetById.put(a.Id, a);
            }
        }

        for (RemediationRequest r : requests) {
            Asset a = assetById.get(r.assetId);
            if (a == null) {
                RemediationResponse miss = new RemediationResponse();
                miss.outcome = 'EscalateToTruck';
                miss.strategy = 'No Asset On File';
                miss.summary = 'No property Asset record on file. Skipping remote action; recommend booking a truck for site assessment.';
                miss.confidence = 95;
                miss.source = 'RemoteRemediationService';
                miss.generatedAt = DateTime.now();
                miss.latencyMs = 0;
                miss.assetId = r.assetId;
                out.add(miss);
                continue;
            }

            String svc = a.Service_Line__c != null ? a.Service_Line__c : '';
            if (svc.contains('Mosquito')) {
                // Mosquito Hunter: try manual fog cycle as the remote action
                out.add(runStrategy(r.assetId, 'Manual Mosquito Fog Cycle', FOG_CYCLE_RESOLVE_PCT));
            } else {
                // No remote-action path for GoGreen, Termite, or Lawn — escalate
                RemediationResponse esc = new RemediationResponse();
                esc.outcome = 'EscalateToTruck';
                esc.strategy = 'No Remote Action';
                esc.summary = svc + ' has no remote-action surface. Recommended next step: schedule a truck roll for an on-site visit.';
                esc.confidence = 92;
                esc.source = 'RemoteRemediationService';
                esc.generatedAt = DateTime.now();
                esc.latencyMs = 0;
                esc.assetId = r.assetId;
                out.add(esc);
            }
        }
        return out;
    }

    // ---------------------------------------------------------------------
    // Strategy core
    // ---------------------------------------------------------------------

    private static RemediationResponse runStrategy(Id assetId, String strategy, Integer resolvePct) {
        RemediationResponse resp = new RemediationResponse();
        resp.assetId = assetId;
        resp.strategy = strategy;
        resp.source = 'RemoteRemediationService';
        resp.generatedAt = DateTime.now();
        resp.latencyMs = simulatedLatency(assetId, strategy);

        if (assetId == null) {
            resp.outcome = 'EscalateToTruck';
            resp.summary = 'No Asset Id provided. Cannot continue.';
            resp.confidence = 99;
            return resp;
        }

        Integer roll = deterministicRoll(assetId, strategy);
        if (roll < resolvePct) {
            resp.outcome = 'Resolved';
            resp.summary = strategy + ' completed successfully within '
                + resp.latencyMs + ' ms. Recommended action: close the case as remotely resolved; no truck roll required.';
            resp.confidence = 78 + Math.mod(roll, 12);
        } else if (roll < resolvePct + 25) {
            resp.outcome = 'NoChange';
            resp.summary = strategy + ' executed but the customer is still reporting activity. Recommend retrying once or escalating to truck.';
            resp.confidence = 62 + Math.mod(roll, 10);
        } else {
            resp.outcome = 'EscalateToTruck';
            resp.summary = strategy + ' did not resolve the issue. The pattern is consistent with an active infestation that requires on-site treatment. Recommend booking a truck.';
            resp.confidence = 80 + Math.mod(roll, 10);
        }

        return resp;
    }

    private static Integer deterministicRoll(Id assetId, String strategy) {
        if (assetId == null) return 99;
        Integer h = Math.abs((String.valueOf(assetId) + ':' + strategy).hashCode());
        return Math.mod(h, 100);
    }

    private static Integer simulatedLatency(Id assetId, String strategy) {
        if (assetId == null) return 1200;
        Integer h = Math.abs((String.valueOf(assetId) + ':' + strategy + ':lat').hashCode());
        return 800 + Math.mod(h, 1601);   // 800..2400
    }
}
