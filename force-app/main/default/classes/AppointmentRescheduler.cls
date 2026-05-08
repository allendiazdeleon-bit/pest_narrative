/**
 * AppointmentRescheduler — moves an existing ServiceAppointment to a new
 * window (e.g., a customer who needs to push their quarterly visit because
 * of weather, or a Sentricon install rescheduled around an HVAC tech).
 *
 * Split from AppointmentBooker because Apex permits only one
 * @InvocableMethod per class.
 */
public with sharing class AppointmentRescheduler {

    public class Request {
        @InvocableVariable(required=true) public Id serviceAppointmentId;
        @InvocableVariable(required=true) public DateTime newStartTime;
        @InvocableVariable(required=true) public DateTime newEndTime;
    }

    public class Response {
        @InvocableVariable public String message;
        @InvocableVariable public Id recordId;
    }

    @InvocableMethod(label='Reschedule Service Visit' description='Move an existing customer ServiceAppointment to a new window.')
    public static List<Response> reschedule(List<Request> requests) {
        List<Response> out = new List<Response>();
        List<ServiceAppointment> updates = new List<ServiceAppointment>();
        for (Request r : requests) {
            updates.add(new ServiceAppointment(
                Id = r.serviceAppointmentId,
                EarliestStartTime = r.newStartTime,
                DueDate = r.newEndTime,
                SchedStartTime = r.newStartTime,
                SchedEndTime = r.newEndTime
            ));
        }
        if (!updates.isEmpty()) update updates;
        for (Request r : requests) {
            Response resp = new Response();
            resp.recordId = r.serviceAppointmentId;
            resp.message = 'Rescheduled service visit ' + r.serviceAppointmentId + ' to ' + r.newStartTime + '.';
            out.add(resp);
        }
        return out;
    }
}
