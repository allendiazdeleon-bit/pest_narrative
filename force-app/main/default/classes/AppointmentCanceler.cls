/**
 * AppointmentCanceler — cancels an existing ServiceAppointment (e.g., a
 * customer can no longer make their quarterly pest visit; a Sentricon
 * install gets pushed because the homeowner is travelling).
 *
 * Split from AppointmentBooker because Apex permits only one
 * @InvocableMethod per class.
 */
public with sharing class AppointmentCanceler {

    public class Request {
        @InvocableVariable(required=true) public Id serviceAppointmentId;
        @InvocableVariable public String reason;
    }

    public class Response {
        @InvocableVariable public String message;
        @InvocableVariable public Id recordId;
    }

    @InvocableMethod(label='Cancel Service Visit' description='Cancel an existing customer ServiceAppointment (quarterly pest, Sentricon install, Mosquito Hunter activation, etc.).')
    public static List<Response> cancel(List<Request> requests) {
        List<Response> out = new List<Response>();
        List<ServiceAppointment> updates = new List<ServiceAppointment>();
        for (Request r : requests) {
            updates.add(new ServiceAppointment(
                Id = r.serviceAppointmentId,
                Status = 'Canceled',
                Description = r.reason
            ));
        }
        if (!updates.isEmpty()) update updates;
        for (Request r : requests) {
            Response resp = new Response();
            resp.recordId = r.serviceAppointmentId;
            resp.message = 'Canceled service visit ' + r.serviceAppointmentId + '. Reason: ' + (r.reason != null ? r.reason : 'not provided') + '.';
            out.add(resp);
        }
        return out;
    }
}
