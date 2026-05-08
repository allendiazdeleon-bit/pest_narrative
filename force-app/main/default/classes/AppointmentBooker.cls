/**
 * AppointmentBooker — Agentforce-invocable: returns 2-3 candidate slots
 * for a customer + work type. Companion classes handle confirm /
 * reschedule / cancel (separate classes because Apex permits only one
 * @InvocableMethod per class).
 *
 * Massey pest demo — used by Sandra's Scene 1 ant-call booking, David's
 * Scene 4 portal signup, and any Agentforce flow that needs to surface
 * available service-visit windows before committing the customer.
 */
public with sharing class AppointmentBooker {

    public class Request {
        @InvocableVariable(required=true) public Id personAccountId;
        @InvocableVariable(required=true) public Id workTypeId;
        @InvocableVariable public String preferenceWindow; // 'morning' / 'afternoon' / 'asap'
    }

    public class Slot {
        @InvocableVariable public DateTime startTime;
        @InvocableVariable public DateTime endTime;
        @InvocableVariable public String slotId;
        @InvocableVariable public String windowLabel;
    }

    public class Response {
        @InvocableVariable public List<Slot> slots;
        @InvocableVariable public String message;
    }

    @InvocableMethod(label='Book Service Visit Slots' description='Return 2-3 candidate service-visit windows for a Massey customer + work type (e.g., GoGreen quarterly, Sentricon install, Mosquito Hunter activation).')
    public static List<Response> book(List<Request> requests) {
        List<Response> out = new List<Response>();
        for (Request r : requests) {
            Response resp = new Response();
            resp.slots = generateCandidateSlots(r.preferenceWindow);
            resp.message = 'Returned ' + resp.slots.size() + ' candidate visit windows for the ' + (r.preferenceWindow != null ? r.preferenceWindow : 'asap') + ' preference.';
            out.add(resp);
        }
        return out;
    }

    // PRODUCTION REPLACEMENT: call FSL.AppointmentBookingService.getSlots()
    // and filter by Scheduling Policy ('Massey Standard' or 'Cluster Response')
    // and Work Type.
    private static List<Slot> generateCandidateSlots(String preferenceWindow) {
        List<Slot> slots = new List<Slot>();
        DateTime today = DateTime.now();
        Integer hourOffset = preferenceWindow == 'morning' ? 8 : preferenceWindow == 'afternoon' ? 13 : 10;
        for (Integer day = 1; day <= 3; day++) {
            DateTime start = DateTime.newInstance(
                today.addDays(day).date(),
                Time.newInstance(hourOffset, 0, 0, 0)
            );
            Slot s = new Slot();
            s.startTime = start;
            s.endTime = start.addHours(2);
            s.slotId = 'SLOT-' + start.getTime();
            s.windowLabel = preferenceWindow != null ? preferenceWindow : 'asap';
            slots.add(s);
        }
        return slots;
    }
}
