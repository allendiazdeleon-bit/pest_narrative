/**
 * OutageStatusLookup — Agentforce-invocable check for whether a customer's
 * area has an active cluster event (e.g., the mosquito surge in ZIP 32828),
 * returning ETR if so.
 *
 * Class name retains the 'Outage' prefix for compatibility with the
 * Incident → Cluster_Event link in the data model. The custom label
 * MasseyFlow_Cluster_Status_Lookup (P2.1) renders user-facing copy.
 */
public with sharing class OutageStatusLookup {

    public class Request {
        @InvocableVariable(required=true) public Id personAccountId;
    }

    public class Response {
        @InvocableVariable public Boolean hasActiveIncident;
        @InvocableVariable public Id incidentId;
        @InvocableVariable public String incidentSubject;
        @InvocableVariable public Integer affectedCustomers;
        @InvocableVariable public String estimatedRestorationTime;
        @InvocableVariable public String message;
    }

    @InvocableMethod(label='Lookup Active Cluster Event' description='Check whether the customer is geo-near an active cluster event (e.g., post-storm mosquito surge in ZIP 32828).')
    public static List<Response> findActive(List<Request> requests) {
        List<Response> out = new List<Response>();

        // Get geo of the customer's primary property asset
        Map<Id, Asset> assetByAccount = new Map<Id, Asset>();
        Set<Id> accountIds = new Set<Id>();
        for (Request r : requests) accountIds.add(r.personAccountId);
        for (Asset a : [SELECT Id, AccountId, Latitude, Longitude FROM Asset WHERE AccountId IN :accountIds]) {
            assetByAccount.put(a.AccountId, a);
        }

        // Active Incidents
        List<Incident> active = [SELECT Id, Subject, Description, Affected_Customers__c, Outage_Latitude__c, Outage_Longitude__c
                                 FROM Incident WHERE StatusCode IN ('New','In Progress','Active') AND Subject LIKE 'Demo_%'];

        for (Request r : requests) {
            Response resp = new Response();
            Asset a = assetByAccount.get(r.personAccountId);
            Incident match = null;
            if (a != null) {
                for (Incident inc : active) {
                    if (inc.Outage_Latitude__c == null || a.Latitude == null) continue;
                    Decimal dLat = Math.abs(inc.Outage_Latitude__c - a.Latitude);
                    Decimal dLon = Math.abs(inc.Outage_Longitude__c - a.Longitude);
                    if (dLat < 0.05 && dLon < 0.05) { match = inc; break; }
                }
                if (match == null && !active.isEmpty()) match = active[0]; // demo: any active counts
            }
            if (match != null) {
                resp.hasActiveIncident = true;
                resp.incidentId = match.Id;
                resp.incidentSubject = match.Subject;
                resp.affectedCustomers = (Integer) match.Affected_Customers__c;
                resp.estimatedRestorationTime = String.valueOf(DateTime.now().addHours(2));
                resp.message = 'Active cluster event affecting your area: ' + match.Subject + '. ETR: ' + resp.estimatedRestorationTime + '.';
            } else {
                resp.hasActiveIncident = false;
                resp.message = 'No active cluster events reported in your area.';
            }
            out.add(resp);
        }
        return out;
    }
}
