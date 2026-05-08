/**
 * EmergencyDivertOrchestrator — handles the dispatcher's "divert this
 * crew to an emergency" action. Scene 7 of PEST_NARRATIVE: Ray pulls
 * Tom's termite team off this morning's Sentricon install to handle
 * the area mosquito treatment when the post-storm cluster activates.
 *
 *   1. Walk the resource's active SAs and WOs.
 *   2. Defer them (status = None, defer reason populated).
 *   3. Update parent WOs to On Hold.
 *   4. Assign the resource to the emergency parent WO linked to the Incident.
 *
 * All operations in a single transaction. PMT is not modeled in the pest
 * lifecycle (see PEST_NARRATIVE § Capital Programs), so there is no
 * PMT-task pause leg here.
 */
public with sharing class EmergencyDivertOrchestrator {

    public class Request {
        @InvocableVariable(required=true) public Id serviceResourceId;
        @InvocableVariable(required=true) public Id incidentId;
        @InvocableVariable public String deferReason;
    }

    public class Response {
        @InvocableVariable public Integer assignmentsCleared;
        @InvocableVariable public Integer woDeferred;
        @InvocableVariable public Integer parentWosPaused;
        @InvocableVariable public Id newAssignmentId;
        @InvocableVariable public String message;
    }

    // Wrapper types so the LWC can pull dropdown options in one Apex call.
    public class Candidates {
        @AuraEnabled public List<ResourceOption> serviceResources;
        @AuraEnabled public List<IncidentOption> incidents;
    }
    public class ResourceOption {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public Integer activeAssignmentCount;
    }
    public class IncidentOption {
        @AuraEnabled public Id id;
        @AuraEnabled public String subject;
    }

    /**
     * Used by the demoMagicEmergencyDivert LWC to populate the picklists.
     * Returns active Service Resources (with their current open-assignment
     * counts) and active Incidents.
     */
    @AuraEnabled(cacheable=true)
    public static Candidates getDivertCandidates() {
        Candidates c = new Candidates();
        c.serviceResources = new List<ResourceOption>();
        c.incidents = new List<IncidentOption>();

        Map<Id, Integer> activeCountByResource = new Map<Id, Integer>();
        for (AggregateResult ar : [SELECT ServiceResourceId rid, count(Id) cnt
                                    FROM AssignedResource
                                    WHERE ServiceAppointment.Status NOT IN ('Completed','Canceled')
                                    GROUP BY ServiceResourceId]) {
            activeCountByResource.put((Id) ar.get('rid'), (Integer) ar.get('cnt'));
        }
        for (ServiceResource sr : [SELECT Id, Name FROM ServiceResource
                                    WHERE IsActive = true ORDER BY Name LIMIT 50]) {
            ResourceOption r = new ResourceOption();
            r.id = sr.Id;
            r.name = sr.Name;
            r.activeAssignmentCount = activeCountByResource.containsKey(sr.Id) ? activeCountByResource.get(sr.Id) : 0;
            c.serviceResources.add(r);
        }

        for (Incident inc : [SELECT Id, Subject FROM Incident
                              WHERE StatusCode IN ('New','In Progress','Active')
                              ORDER BY CreatedDate DESC LIMIT 50]) {
            IncidentOption i = new IncidentOption();
            i.id = inc.Id;
            i.subject = inc.Subject;
            c.incidents.add(i);
        }
        return c;
    }

    /**
     * @AuraEnabled wrapper so the demoMagicEmergencyDivert LWC can call
     * the same logic. (@InvocableMethod isn't directly callable from LWC.)
     */
    @AuraEnabled
    public static List<Response> divertFromLwc(List<Request> requests) {
        return divert(requests);
    }

    @InvocableMethod(label='Emergency Divert Resource' description='Clear a field tech\'s queue and reassign to a cluster-response Incident (e.g., post-storm mosquito surge).')
    public static List<Response> divert(List<Request> requests) {
        List<Response> out = new List<Response>();
        for (Request r : requests) {
            Savepoint sp = Database.setSavepoint();
            try {
                out.add(divertOne(r));
            } catch (Exception e) {
                Database.rollback(sp);
                Response err = new Response();
                err.message = 'Failed: ' + e.getMessage();
                out.add(err);
            }
        }
        return out;
    }

    private static Response divertOne(Request req) {
        Response resp = new Response();
        String reason = req.deferReason != null ? req.deferReason : 'Emergency Divert — Cluster Response';

        // 1. Find active assignments for this resource
        List<AssignedResource> currentAssignments = [
            SELECT Id, ServiceAppointmentId, ServiceAppointment.ParentRecordId, ServiceAppointment.Status
            FROM AssignedResource
            WHERE ServiceResourceId = :req.serviceResourceId
              AND ServiceAppointment.Status NOT IN ('Completed', 'Canceled')
        ];

        Set<Id> saIds = new Set<Id>();
        Set<Id> parentIds = new Set<Id>();
        for (AssignedResource ar : currentAssignments) {
            saIds.add(ar.ServiceAppointmentId);
            if (ar.ServiceAppointment != null && ar.ServiceAppointment.ParentRecordId != null) {
                parentIds.add(ar.ServiceAppointment.ParentRecordId);
            }
        }

        // 2. Clear assignments
        if (!currentAssignments.isEmpty()) {
            delete currentAssignments;
            resp.assignmentsCleared = currentAssignments.size();
        } else {
            resp.assignmentsCleared = 0;
        }

        // 3. Defer the SAs
        List<ServiceAppointment> saUpdates = new List<ServiceAppointment>();
        for (Id saId : saIds) {
            saUpdates.add(new ServiceAppointment(
                Id = saId,
                Status = 'None'
            ));
        }
        if (!saUpdates.isEmpty()) update saUpdates;
        resp.woDeferred = saUpdates.size();

        // 4. Pause parent WOs (best-effort; only WorkOrder ParentRecordIds)
        List<WorkOrder> parentUpdates = new List<WorkOrder>();
        for (WorkOrder wo : [SELECT Id, Status FROM WorkOrder WHERE Id IN :parentIds]) {
            wo.Status = 'On Hold';
            parentUpdates.add(wo);
        }
        if (!parentUpdates.isEmpty()) update parentUpdates;
        resp.parentWosPaused = parentUpdates.size();

        // 5. Assign resource to incident's emergency WO
        // Find an emergency WO linked to this incident
        List<WorkOrder> emergencyWos = [SELECT Id FROM WorkOrder WHERE Linked_Incident__c = :req.incidentId LIMIT 1];
        if (!emergencyWos.isEmpty()) {
            // Find the SA on the emergency WO
            List<ServiceAppointment> emergencySas = [SELECT Id FROM ServiceAppointment WHERE ParentRecordId = :emergencyWos[0].Id LIMIT 1];
            if (!emergencySas.isEmpty()) {
                AssignedResource ar = new AssignedResource(
                    ServiceResourceId = req.serviceResourceId,
                    ServiceAppointmentId = emergencySas[0].Id
                );
                insert ar;
                resp.newAssignmentId = ar.Id;
            }
        }

        resp.message = 'Diverted resource: cleared ' + resp.assignmentsCleared + ' assignments, '
            + 'deferred ' + resp.woDeferred + ' SAs, paused ' + resp.parentWosPaused + ' parent WOs, '
            + (resp.newAssignmentId != null ? 'reassigned to cluster-response WO.' : 'no cluster-response WO found to reassign to.');
        return resp;
    }
}
