/**
 * ClusterDetector — invoked from a Case to simulate the AI/Voice
 * pattern-detection that recognizes a geographic cluster of similar
 * pest-related calls and creates the parent Incident.
 *
 * Real-world flow: each call lands as a Case via Voice/Chat. When
 * Agentforce sees N similar Cases in a 4-block radius within a few
 * minutes (e.g., 8 customers in ZIP 32828 reporting mosquitoes after
 * a heavy overnight rain), it opens a parent Incident and links them.
 * This class shortcuts that by matching on a known-cluster Subject
 * pattern.
 *
 * Anchor scenario (Scenes 6-8 of PEST_NARRATIVE):
 *   Heavy overnight rain (3+ inches) hits Avalon Park / Waterford Lakes
 *   (ZIP 32828). A clogged municipal storm drain creates an Aedes aegypti
 *   breeding event. 8 Mosquito Hunter and adjacent customers call in over
 *   ~48 hours. ClusterDetector identifies the geographic + weather-event
 *   correlation and opens the parent Incident "Mosquito Surge — 32828".
 *
 * Detection ONLY. Customer notification (Product Service Campaign)
 * and field dispatch (Work Orders) are deliberate next-step actions
 * driven from the Incident page — see IncidentNotifyService and
 * IncidentDispatchService.
 *
 * Idempotency: if the source Case is already linked to an Incident,
 * the existing Incident is returned and no duplicate is created.
 */
public with sharing class ClusterDetector {

    public class Result {
        @AuraEnabled public Id incidentId;
        @AuraEnabled public String incidentSubject;
        @AuraEnabled public Integer linkedCaseCount;
        @AuraEnabled public List<Map<String, String>> siblingCalls;
        @AuraEnabled public String message;
    }

    /**
     * Returns the sibling Cases that would be detected as part of the
     * cluster. Used by the LWC to render the "discovery" animation
     * BEFORE the user commits to creating the Incident.
     */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> previewSiblings(Id sourceCaseId) {
        List<Map<String, String>> out = new List<Map<String, String>>();
        Case source = [SELECT Id, Subject FROM Case WHERE Id = :sourceCaseId LIMIT 1];
        String pattern = patternFor(source.Subject);
        for (Case c : [SELECT Id, CaseNumber, Subject, Account.Name FROM Case
                        WHERE Id != :sourceCaseId
                          AND Subject LIKE :pattern
                          AND Linked_Incident__c = null
                        ORDER BY Subject LIMIT 7]) {
            String address = c.Subject.contains(' at ') ? c.Subject.substringAfter(' at ') : c.Subject;
            out.add(new Map<String, String>{
                'caseNumber' => c.CaseNumber,
                'address' => address,
                'caller' => c.Account.Name
            });
        }
        return out;
    }

    @AuraEnabled
    public static Result detectFromCase(Id sourceCaseId) {
        Result r = new Result();
        r.siblingCalls = new List<Map<String, String>>();

        Case source = [SELECT Id, AccountId, AssetId, Subject, Linked_Incident__c, Asset.AccountId
                        FROM Case WHERE Id = :sourceCaseId LIMIT 1];

        // Idempotency: if already linked, just return the existing Incident
        if (source.Linked_Incident__c != null) {
            Incident inc = [SELECT Id, Subject FROM Incident WHERE Id = :source.Linked_Incident__c LIMIT 1];
            r.incidentId = inc.Id;
            r.incidentSubject = inc.Subject;
            r.linkedCaseCount = [SELECT count() FROM Case WHERE Linked_Incident__c = :inc.Id];
            r.message = 'This Case is already linked to Incident ' + inc.Subject + ' (' + r.linkedCaseCount + ' Cases linked).';
            return r;
        }

        String pattern = patternFor(source.Subject);
        Boolean isTermite = source.Subject != null && (source.Subject.containsIgnoreCase('termite')
            || source.Subject.containsIgnoreCase('swarm') || source.Subject.containsIgnoreCase('sentricon'));

        // Find sibling Cases matching the pattern
        List<Case> siblings = [SELECT Id, CaseNumber, Subject, AccountId, Account.Name FROM Case
                                WHERE Id != :sourceCaseId
                                  AND Subject LIKE :pattern
                                  AND Linked_Incident__c = null
                                ORDER BY Subject LIMIT 7];

        // Create parent Incident — mosquito surge cluster (default) or
        // termite swarm correlation, depending on the cluster.
        Incident inc = new Incident(
            Subject = isTermite
                ? 'Termite Swarm Cluster — Avalon Park'
                : 'Mosquito Surge — ZIP 32828 (Avalon Park / Waterford Lakes)',
            Description = '[masseyFlow demo seed] Auto-correlated from ' + (siblings.size() + 1)
                + ' inbound Cases within a 4-block radius. ' + (isTermite
                    ? 'Likely subterranean termite swarm event triggered by FL spring conditions.'
                    : 'Likely Aedes aegypti breeding event triggered by clogged municipal storm drain after overnight rain.'),
            Priority = 'High',
            Affected_Customers__c = siblings.size() + 1,
            Circuit__c = isTermite ? 'AVALON-TERMITE' : 'ZIP-32828-MOSQUITO'
        );
        insert inc;
        r.incidentId = inc.Id;
        r.incidentSubject = inc.Subject;

        // Link all Cases (source + siblings) to the new Incident
        List<Case> casesToUpdate = new List<Case>();
        casesToUpdate.add(new Case(Id = source.Id, Linked_Incident__c = inc.Id, Status = 'Working'));
        for (Case s : siblings) {
            casesToUpdate.add(new Case(Id = s.Id, Linked_Incident__c = inc.Id, Status = 'Working'));
            String addr = s.Subject.contains(' at ') ? s.Subject.substringAfter(' at ') : s.Subject;
            r.siblingCalls.add(new Map<String, String>{
                'caseNumber' => s.CaseNumber,
                'address' => addr,
                'caller' => s.Account.Name
            });
        }
        update casesToUpdate;
        r.linkedCaseCount = casesToUpdate.size();

        r.message = 'Cluster detected. Created Incident ' + inc.Subject
            + ' linking ' + r.linkedCaseCount + ' Cases. '
            + 'Next: notify affected customers and dispatch field response from the Incident page.';
        return r;
    }

    private static String patternFor(String subject) {
        if (subject == null) return '';
        if (subject.containsIgnoreCase('mosquito') || subject.containsIgnoreCase('biting')
            || subject.containsIgnoreCase('swarm of mosquitoes')) {
            return 'Mosquitoes at%';
        }
        if (subject.containsIgnoreCase('termite') || subject.containsIgnoreCase('swarmer')
            || subject.containsIgnoreCase('sentricon')) {
            return 'Termite swarmers at%';
        }
        if (subject.containsIgnoreCase('ants') || subject.containsIgnoreCase('roach')
            || subject.containsIgnoreCase('pest')) {
            return 'Pest activity at%';
        }
        return subject.substringBefore(' at ') + ' at%';
    }
}
