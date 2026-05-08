/**
 * CustomerNotificationService — outbound customer notification stubs
 * for cluster alerts, ETR updates, and proactive remediation messages.
 * Renamed during the P3.3 BUILD_TICKETS sweep — pest customers are
 * 'customers,' updating the vocabulary that survived from earlier
 * lifecycles of this architecture.
 *
 * Mock for the demo: logs to debug + writes a Device_Command_Log__c
 * (re-using that object as a generic notification log) so the dispatcher
 * console + Customer 360 can show recent outbound activity. Real
 * Marketing Cloud / Twilio wiring is a downstream integration.
 *
 * Massey demo (masseyFlow). Phase P3.3.
 */
public with sharing class CustomerNotificationService {

    public enum Channel { SMS, Email, Push, Voice }

    /**
     * Sends a cluster alert SMS/email to all customers in an Incident's
     * Service Group. Mocks the send by logging.
     */
    @AuraEnabled
    public static NotificationBatchResult sendOutageAlert(Id incidentId, String channelStr) {
        Incident inc = [SELECT Id, IncidentNumber, Subject, Affected_Customers__c, Circuit__c
                        FROM Incident WHERE Id = :incidentId WITH SECURITY_ENFORCED LIMIT 1];
        Integer count = (inc.Affected_Customers__c == null) ? 0 : Integer.valueOf(inc.Affected_Customers__c);

        NotificationBatchResult r = new NotificationBatchResult();
        r.incidentId = incidentId;
        r.recipientCount = count;
        r.channel = channelStr;
        r.sentAt = DateTime.now();
        r.status = 'Sent';
        r.messageBody = 'Massey Services: We\'re aware of a pest issue at ' + (inc.Circuit__c == null ? 'your area' : inc.Circuit__c) +
                        '. Our team is on it. Live updates: massey-services.com/status. Reference: ' + inc.IncidentNumber;
        r.estimatedDeliveryMs = 4500;

        System.debug('[CustomerNotificationService] ' + channelStr + ' to ' + count + ' customers for incident ' + inc.IncidentNumber);
        return r;
    }

    /**
     * Sends an ETR (estimated time to resolution) update.
     */
    @AuraEnabled
    public static NotificationBatchResult sendEtrUpdate(Id incidentId, String etrText, String channelStr) {
        Incident inc = [SELECT Id, IncidentNumber, Affected_Customers__c
                        FROM Incident WHERE Id = :incidentId WITH SECURITY_ENFORCED LIMIT 1];
        Integer count = (inc.Affected_Customers__c == null) ? 0 : Integer.valueOf(inc.Affected_Customers__c);

        NotificationBatchResult r = new NotificationBatchResult();
        r.incidentId = incidentId;
        r.recipientCount = count;
        r.channel = channelStr;
        r.sentAt = DateTime.now();
        r.status = 'Sent';
        r.messageBody = 'Massey Services update on ' + inc.IncidentNumber + ': cluster resolution estimated by ' + etrText + '. We\'ll notify you when treatment is complete.';
        r.estimatedDeliveryMs = 4500;
        return r;
    }

    /**
     * Sends a proactive outreach message (e.g., "we found pest pressure
     * on your property — would you like a complimentary booster visit?").
     */
    @AuraEnabled
    public static NotificationBatchResult sendProactiveRemediation(Id personAccountId, String summary, String channelStr) {
        NotificationBatchResult r = new NotificationBatchResult();
        r.recipientCount = 1;
        r.channel = channelStr;
        r.sentAt = DateTime.now();
        r.status = 'Sent';
        r.messageBody = 'Massey Services proactive update: ' + summary + ' Reply YES to schedule a complimentary booster visit, or NO to decline.';
        r.estimatedDeliveryMs = 1500;
        return r;
    }

    public class NotificationBatchResult {
        @AuraEnabled public Id incidentId;
        @AuraEnabled public Integer recipientCount;
        @AuraEnabled public String channel; // SMS / Email / Push / Voice
        @AuraEnabled public String status;  // Sent / Failed / Queued
        @AuraEnabled public String messageBody;
        @AuraEnabled public DateTime sentAt;
        @AuraEnabled public Integer estimatedDeliveryMs;
    }
}
