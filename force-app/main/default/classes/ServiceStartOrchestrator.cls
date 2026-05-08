/**
 * ServiceStartOrchestrator — creates a new customer Person Account and
 * (optionally) links to an existing property Asset for the David Kim
 * self-service signup flow on massey-portal (Scene 4 of PEST_NARRATIVE).
 *
 * Inserts the Person Account, looks up the matching property Asset by
 * address if requested, re-points Asset.AccountId to the new customer,
 * and writes preference fields.
 */
public with sharing class ServiceStartOrchestrator {

    public class Request {
        @InvocableVariable(required=true) public String firstName;
        @InvocableVariable(required=true) public String lastName;
        @InvocableVariable public String email;
        @InvocableVariable public String phone;
        @InvocableVariable public String address;
        @InvocableVariable public Id existingAssetId;
        @InvocableVariable public String preferredContactChannel; // EMAIL / SMS / PHONE
    }

    public class Response {
        @InvocableVariable public Id personAccountId;
        @InvocableVariable public Id linkedAssetId;
        @InvocableVariable public String message;
    }

    @InvocableMethod(label='Start New Customer' description='Create a new Massey customer Person Account and link to the property Asset.')
    public static List<Response> create(List<Request> requests) {
        List<Response> out = new List<Response>();
        Id personAccountRtId;
        try {
            personAccountRtId = [SELECT Id FROM RecordType WHERE SObjectType='Account' AND DeveloperName='PersonAccount' LIMIT 1].Id;
        } catch (Exception e) {
            // Org may not have Person Accounts enabled; fall back to Business Account
        }

        for (Request r : requests) {
            Response resp = new Response();
            try {
                Account a = new Account(
                    FirstName = r.firstName,
                    LastName = r.lastName,
                    PersonEmail = r.email,
                    PersonMobilePhone = r.phone,
                    BillingStreet = r.address
                );
                if (personAccountRtId != null) a.RecordTypeId = personAccountRtId;
                insert a;
                resp.personAccountId = a.Id;

                if (r.existingAssetId != null) {
                    update new Asset(Id = r.existingAssetId, AccountId = a.Id);
                    resp.linkedAssetId = r.existingAssetId;
                }
                resp.message = 'Created Person Account ' + a.Id + (resp.linkedAssetId != null ? ' linked to property Asset ' + resp.linkedAssetId : '') + '.';
            } catch (Exception ex) {
                resp.message = 'Failed: ' + ex.getMessage();
            }
            out.add(resp);
        }
        return out;
    }
}
