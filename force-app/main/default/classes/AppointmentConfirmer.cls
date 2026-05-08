/**
 * AppointmentConfirmer — creates Case + WorkOrder + ServiceAppointment
 * in one transaction at a chosen slot. Massey demo path: Sandra accepts a
 * same-week truck roll on her ant call (Scene 1) — this class spawns the
 * record trio that hits the dispatch board and Maria's tablet.
 *
 * Split from AppointmentBooker because Apex permits only one
 * @InvocableMethod per class.
 */
public with sharing class AppointmentConfirmer {

    public class Request {
        @InvocableVariable(required=true) public Id personAccountId;
        @InvocableVariable(required=true) public Id workTypeId;
        @InvocableVariable(required=true) public DateTime startTime;
        @InvocableVariable(required=true) public DateTime endTime;
        @InvocableVariable public String caseContext;
    }

    public class Response {
        @InvocableVariable public Id caseId;
        @InvocableVariable public Id workOrderId;
        @InvocableVariable public Id serviceAppointmentId;
        @InvocableVariable public String message;
    }

    @InvocableMethod(label='Confirm Service Visit Slot' description='Create Case + WorkOrder + ServiceAppointment for a chosen customer service-visit slot.')
    public static List<Response> confirm(List<Request> requests) {
        List<Response> out = new List<Response>();
        for (Request r : requests) out.add(confirmOne(r));
        return out;
    }

    private static Response confirmOne(Request req) {
        Response resp = new Response();

        Case c = new Case(
            AccountId = req.personAccountId,
            Subject = 'Booked: ' + (req.caseContext != null ? req.caseContext : 'customer-requested visit'),
            Description = req.caseContext,
            Status = 'New',
            Origin = 'Agentforce'
        );
        insert c;
        resp.caseId = c.Id;

        WorkOrder wo = new WorkOrder(
            AccountId = req.personAccountId,
            CaseId = c.Id,
            WorkTypeId = req.workTypeId,
            Subject = 'WO from ' + (req.caseContext != null ? req.caseContext : 'Agentforce booking'),
            Status = 'New',
            StartDate = req.startTime,
            EndDate = req.endTime
        );
        insert wo;
        resp.workOrderId = wo.Id;

        // Some WorkType auto-create-SA flags create the SA via trigger;
        // create one here only if absent.
        List<ServiceAppointment> existingSa = [SELECT Id FROM ServiceAppointment WHERE ParentRecordId = :wo.Id LIMIT 1];
        if (existingSa.isEmpty()) {
            ServiceAppointment sa = new ServiceAppointment(
                ParentRecordId = wo.Id,
                Subject = 'SA for ' + wo.Subject,
                EarliestStartTime = req.startTime,
                DueDate = req.endTime,
                SchedStartTime = req.startTime,
                SchedEndTime = req.endTime
            );
            insert sa;
            resp.serviceAppointmentId = sa.Id;
        } else {
            resp.serviceAppointmentId = existingSa[0].Id;
        }

        resp.message = 'Booked Case ' + c.Id + ', WO ' + wo.Id + ', SA ' + resp.serviceAppointmentId + '.';
        return resp;
    }
}
