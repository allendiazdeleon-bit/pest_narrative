/**
 * NocMapService — read-only feed for the operations map LWC (active
 * cluster events plotted on an Orlando-area static map).
 *
 * Returns a flat list of OutageMarker DTOs (one per active Incident with
 * geo coordinates) for plotting on the SVG static-map. Status / Priority
 * are surfaced as plain strings so the LWC can drive its color buckets
 * without re-reading picklists.
 *
 * NOTE: class name retains 'Noc' for compat with prior architecture
 * naming (LWCs and cross-references). Internal vocabulary is fully
 * pest-toned — markers represent active cluster events (e.g., the
 * mosquito surge in ZIP 32828) and proactive dispatch zones.
 *
 * Public-facing safe: every field is a sanitized read; the LWC has a
 * `compact` mode for Experience Cloud surfaces (massey-portal).
 */
public with sharing class NocMapService {

    public class OutageMarker {
        @AuraEnabled public Id incidentId;
        @AuraEnabled public String incidentNumber;
        @AuraEnabled public Decimal latitude;
        @AuraEnabled public Decimal longitude;
        @AuraEnabled public String priority;
        @AuraEnabled public String status;
        @AuraEnabled public Integer affectedProperties;
        @AuraEnabled public String etrText;
        @AuraEnabled public String serviceGroup;          // e.g., 'ZIP-32828-MOSQUITO'
    }

    /**
     * Returns all open Incidents that have geo-coords set.
     *
     * Caller: operations map LWC (and the active-PSC drawer via composition).
     */
    @AuraEnabled(cacheable=true)
    public static List<OutageMarker> getActiveOutages() {
        List<OutageMarker> out = new List<OutageMarker>();

        List<Incident> incidents = [
            SELECT Id, IncidentNumber, Subject, StatusCode, Priority,
                   Affected_Customers__c, Circuit__c,
                   Outage_Latitude__c, Outage_Longitude__c,
                   CreatedDate
              FROM Incident
             WHERE StatusCode NOT IN ('Resolved','Closed')
               AND Outage_Latitude__c != null
               AND Outage_Longitude__c != null
             WITH SECURITY_ENFORCED
             ORDER BY Affected_Customers__c DESC NULLS LAST
             LIMIT 200
        ];

        for (Incident inc : incidents) {
            OutageMarker m = new OutageMarker();
            m.incidentId = inc.Id;
            m.incidentNumber = inc.IncidentNumber;
            m.latitude = inc.Outage_Latitude__c;
            m.longitude = inc.Outage_Longitude__c;
            m.priority = inc.Priority;
            m.status = inc.StatusCode;
            m.affectedProperties = inc.Affected_Customers__c != null
                ? Integer.valueOf(inc.Affected_Customers__c) : 0;
            // Demo ETR: 90 minutes from incident creation, formatted as a wall-clock string.
            DateTime etr = inc.CreatedDate != null
                ? inc.CreatedDate.addMinutes(90)
                : DateTime.now().addMinutes(90);
            m.etrText = etr.format('h:mm a');
            m.serviceGroup = String.isBlank(inc.Circuit__c) ? 'Unassigned' : inc.Circuit__c;
            out.add(m);
        }
        return out;
    }
}
