/**
 * EscalationContextBuilder — assembles a handoff payload when Agentforce
 * escalates a customer conversation to a human agent (Scene 3 of
 * PEST_NARRATIVE — Jordan escalates an unusual-insect ID to entomology).
 *
 * Returns AI summary, pest-pressure snapshot from PestPressureAnalyzer,
 * prior cases, payment history summary, and suggested next-best actions.
 *
 * Cross-references P3.1 class: PestPressureAnalyzer.analyze(...)
 */
public with sharing class EscalationContextBuilder {

    public class Request {
        @InvocableVariable(required=true) public Id personAccountId;
        @InvocableVariable public String transcript;
    }

    public class NextBestAction {
        @InvocableVariable public String action;
        @InvocableVariable public String reason;
    }

    public class Response {
        @InvocableVariable public String aiSummary;
        @InvocableVariable public String lineHealthSnapshot; // kept for LWC compat — value is pest-pressure diagnosis
        @InvocableVariable public Integer priorCaseCount;
        @InvocableVariable public List<String> priorCaseSubjects;
        @InvocableVariable public String paymentHistorySummary;
        @InvocableVariable public List<NextBestAction> suggestedNbas;
    }

    @InvocableMethod(label='Build Escalation Context' description='Assemble a customer handoff payload when escalating a conversation from Agentforce to a human agent (e.g., entomology specialist).')
    public static List<Response> summarize(List<Request> requests) {
        List<Response> out = new List<Response>();
        for (Request r : requests) {
            Response resp = new Response();

            // Prior cases
            List<Case> cases = [SELECT Id, Subject, Status, CreatedDate FROM Case
                                WHERE AccountId = :r.personAccountId ORDER BY CreatedDate DESC LIMIT 5];
            resp.priorCaseCount = cases.size();
            resp.priorCaseSubjects = new List<String>();
            for (Case c : cases) resp.priorCaseSubjects.add(c.Subject);

            // Pest-pressure snapshot via PestPressureAnalyzer (P3.1)
            String diagnosis = 'No pest-pressure telemetry available.';
            String anomalyType = null;
            try {
                PestPressureAnalyzer.Request ar = new PestPressureAnalyzer.Request();
                ar.personAccountId = r.personAccountId;
                ar.daysBack = 30;
                List<PestPressureAnalyzer.Response> pestResp = PestPressureAnalyzer.analyze(new List<PestPressureAnalyzer.Request>{ar});
                if (pestResp != null && !pestResp.isEmpty()) {
                    diagnosis = pestResp[0].diagnosis;
                    anomalyType = pestResp[0].anomalyType;
                }
            } catch (Exception e) {
                // PestPressureAnalyzer may not be deployed yet; degrade gracefully.
            }
            resp.lineHealthSnapshot = diagnosis;

            resp.paymentHistorySummary = 'Payment history not available in this demo build.';
            resp.aiSummary = (r.transcript != null ? 'Customer conversation: ' + r.transcript.left(500) : '')
                + ' | Prior cases: ' + resp.priorCaseCount
                + ' | Pest pressure: ' + diagnosis;

            // NBAs
            resp.suggestedNbas = new List<NextBestAction>();
            if (resp.priorCaseCount >= 2) {
                NextBestAction n = new NextBestAction();
                n.action = 'Offer Booster Visit + Goodwill Credit';
                n.reason = 'Customer has ' + resp.priorCaseCount + ' prior cases — repeat-friction account.';
                resp.suggestedNbas.add(n);
            }
            if (anomalyType == 'ELEVATED_PEST_PRESSURE') {
                NextBestAction n = new NextBestAction();
                n.action = 'Book Booster Termite Inspection';
                n.reason = 'Pest-pressure analyzer shows rising bait station hits + soil temp in active range.';
                resp.suggestedNbas.add(n);
            }
            if (resp.suggestedNbas.isEmpty()) {
                NextBestAction n = new NextBestAction();
                n.action = 'Standard Empathy Script + Entomology Handoff';
                n.reason = 'No specific signals detected; escalation likely needs specialist ID.';
                resp.suggestedNbas.add(n);
            }

            out.add(resp);
        }
        return out;
    }
}
