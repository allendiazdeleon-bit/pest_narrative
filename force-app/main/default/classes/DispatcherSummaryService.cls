/**
 * DispatcherSummaryService — read-only counts for the Dispatcher Console
 * top-of-queue summary and active-PSC drawer LWCs that Ray Garcia (Orlando
 * branch ops manager) watches throughout the day.
 */
public with sharing class DispatcherSummaryService {

    public class Summary {
        @AuraEnabled public Integer openSaCount;
        @AuraEnabled public Integer activeIncidentCount;
        @AuraEnabled public Integer affectedCustomersTotal;
        @AuraEnabled public Decimal capacityPctUsed;
        @AuraEnabled public String marginIndicator; // 'red' / 'yellow' / 'green'
    }

    @AuraEnabled(cacheable=true)
    public static Summary getSummary() {
        Summary s = new Summary();
        s.openSaCount = [SELECT count() FROM ServiceAppointment
                         WHERE Status NOT IN ('Completed','Canceled')];
        s.activeIncidentCount = [SELECT count() FROM Incident
                                  WHERE StatusCode IN ('New','In Progress','Active')];
        AggregateResult[] sums = [SELECT SUM(Affected_Customers__c) total
                                   FROM Incident
                                   WHERE StatusCode IN ('New','In Progress','Active')];
        Decimal aff = (Decimal) sums[0].get('total');
        s.affectedCustomersTotal = aff != null ? Integer.valueOf(aff) : 0;

        // Demo-only capacity calc: open-SA count / 50 as a fake utilization %
        // (Massey Orlando branch runs ~20 quarterly pest techs + 1 termite team).
        s.capacityPctUsed = Math.min(100, Math.round((Double) s.openSaCount * 100.0 / 50.0));
        s.marginIndicator = s.capacityPctUsed > 90 ? 'red'
                           : s.capacityPctUsed > 70 ? 'yellow'
                           : 'green';
        return s;
    }

    public class IncidentRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String subject;
        @AuraEnabled public String status;
        @AuraEnabled public String priority;
        @AuraEnabled public Integer affectedCustomers;
        @AuraEnabled public String circuit;
        @AuraEnabled public DateTime createdDate;
    }

    @AuraEnabled(cacheable=true)
    public static List<IncidentRow> getActiveIncidents() {
        List<IncidentRow> out = new List<IncidentRow>();
        for (Incident inc : [SELECT Id, Subject, StatusCode, Priority, Affected_Customers__c, Circuit__c, CreatedDate
                              FROM Incident
                              WHERE StatusCode IN ('New','In Progress','Active')
                              ORDER BY Affected_Customers__c DESC NULLS LAST
                              LIMIT 20]) {
            IncidentRow r = new IncidentRow();
            r.id = inc.Id;
            r.subject = inc.Subject;
            r.status = inc.StatusCode;
            r.priority = inc.Priority;
            r.affectedCustomers = inc.Affected_Customers__c != null ? Integer.valueOf(inc.Affected_Customers__c) : 0;
            r.circuit = inc.Circuit__c;
            r.createdDate = inc.CreatedDate;
            out.add(r);
        }
        return out;
    }
}
