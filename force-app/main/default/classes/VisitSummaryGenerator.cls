/**
 * VisitSummaryGenerator — produces a 3-4 sentence plain-language visit
 * summary by aggregating Work Order context. Per BUILD_TICKETS the
 * production version submits to Agentforce via Connect API; this stub
 * returns a deterministic summary built from the WO's data so the
 * demo flow can complete end-to-end without an Agentforce dependency.
 *
 * Used in Scene 8 Step 6 (Tom finishes the Mosquito Surge Area Treatment)
 * and Scene 9 (Maria's quarterly visit close-out feeding the manager
 * coaching dashboard).
 *
 * PRODUCTION REPLACEMENT: replace generateOne() body with a callout to
 * the Agentforce summary topic via Connect API or the Anthropic Claude
 * API. Pass the assembled context as the prompt input.
 */
public with sharing class VisitSummaryGenerator {

    public class Request {
        @InvocableVariable(required=true) public Id workOrderId;
    }

    public class Response {
        @InvocableVariable public String summary;
        @InvocableVariable public Id workOrderId;
    }

    @InvocableMethod(label='Generate Visit Summary' description='Produce a customer-facing 3-4 sentence summary of a completed pest, termite, mosquito, or lawn service visit.')
    public static List<Response> generate(List<Request> requests) {
        Set<Id> ids = new Set<Id>();
        for (Request r : requests) ids.add(r.workOrderId);

        Map<Id, WorkOrder> woMap = new Map<Id, WorkOrder>([
            SELECT Id, Subject, Description, Status, AccountId, AssetId,
                   Asset.Name, Asset.Service_Line__c,
                   WorkType.Name, StartDate, EndDate, Outage_Cause__c
            FROM WorkOrder WHERE Id IN :ids
        ]);

        List<Response> out = new List<Response>();
        for (Request r : requests) {
            Response resp = new Response();
            resp.workOrderId = r.workOrderId;
            WorkOrder w = woMap.get(r.workOrderId);
            resp.summary = generateOne(w);
            out.add(resp);
        }
        return out;
    }

    private static String generateOne(WorkOrder w) {
        if (w == null) return 'Unable to generate a summary — Work Order not found.';
        String assetName = w.Asset != null ? w.Asset.Name : 'the customer property';
        String wtName = w.WorkType != null ? w.WorkType.Name : 'the scheduled service visit';
        String svcLine = (w.Asset != null && w.Asset.Service_Line__c != null)
            ? w.Asset.Service_Line__c : 'GoGreen Pest Prevention';

        String summary = 'On ' + (w.StartDate != null ? w.StartDate.format('MMMM d') : 'today')
            + ', our technician completed ' + wtName + ' at ' + assetName + '. ';
        if (svcLine.containsIgnoreCase('Termite')) {
            summary += 'Sentricon stations were inspected, hits logged, and fresh bait deployed where active feeding was observed. ';
        } else if (svcLine.containsIgnoreCase('Mosquito')) {
            summary += 'The perimeter was misted, breeding sources identified and treated with larvicide, and the system controller verified. ';
        } else if (svcLine.containsIgnoreCase('Lawn')) {
            summary += 'Turf health was assessed, fertilizer / herbicide applied per the seasonal program, and any insect activity flagged for follow-up. ';
        } else {
            summary += 'The home perimeter was treated with our standard low-toxicity baseline product, all entry points were inspected, and any conducive conditions were noted in your file. ';
        }
        if (w.Outage_Cause__c != null) {
            summary += 'Root cause: ' + w.Outage_Cause__c + '. ';
        }
        summary += 'Thank you for choosing Massey Services — The Quality Service Company.';
        return summary;
    }
}
