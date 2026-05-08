/**
 * WOCompletionRollupHelper — invoked by the WO_Completion_Rollup Flow when
 * a child WO's Status changes to Completed. Drives the day-close roll-up
 * chain in Scene 9 (Tom finishes, Maria finishes, parent emergency WO
 * recomputes, parent flips to Completed, VisitSummaryGenerator emits a
 * summary, the linked Incident closes, the PSC closes).
 *
 *   1. If the WO has a parent (ParentWorkOrderId), increment parent.Children_Completed__c.
 *   2. If parent.Children_Completed__c == Children_Total__c, flip parent.Status to
 *      Completed.
 *
 * NOTE: PMT is intentionally not modeled in the pest demo (see
 * PEST_NARRATIVE § Capital Programs), so the PMT-task-close leg from
 * prior lifecycles of this architecture has been removed.
 */
public with sharing class WOCompletionRollupHelper {

    public class Request {
        @InvocableVariable(required=true) public Id workOrderId;
    }

    @InvocableMethod(label='Roll Up Child WO Completion' description='Increment parent rollup, close parent when all children complete.')
    public static void process(List<Request> requests) {
        Set<Id> ids = new Set<Id>();
        for (Request r : requests) ids.add(r.workOrderId);

        // Load completing children with their parent-ish refs
        Map<Id, WorkOrder> childMap = new Map<Id, WorkOrder>([
            SELECT Id, Status, ParentWorkOrderId, Work_Order_Coverage_Type__c
            FROM WorkOrder WHERE Id IN :ids
        ]);

        Set<Id> parentIds = new Set<Id>();
        for (WorkOrder w : childMap.values()) {
            if (w.ParentWorkOrderId != null) parentIds.add(w.ParentWorkOrderId);
        }
        if (parentIds.isEmpty()) return;

        // Load parents with current rollup
        Map<Id, WorkOrder> parentMap = new Map<Id, WorkOrder>([
            SELECT Id, Status, Children_Completed__c, Children_Total__c
            FROM WorkOrder WHERE Id IN :parentIds
        ]);

        // Re-count completed children authoritatively (avoids drift)
        Map<Id, Integer> completedCount = new Map<Id, Integer>();
        for (Id pid : parentIds) completedCount.put(pid, 0);
        for (WorkOrder c : [SELECT ParentWorkOrderId FROM WorkOrder
                             WHERE ParentWorkOrderId IN :parentIds AND Status = 'Completed']) {
            completedCount.put(c.ParentWorkOrderId, completedCount.get(c.ParentWorkOrderId) + 1);
        }

        // Update parents
        List<WorkOrder> parentUpdates = new List<WorkOrder>();
        for (WorkOrder p : parentMap.values()) {
            Integer done = completedCount.get(p.Id);
            p.Children_Completed__c = done;
            if (done >= (p.Children_Total__c == null ? 0 : p.Children_Total__c)
                && (p.Children_Total__c != null && p.Children_Total__c > 0)) {
                p.Status = 'Completed';
            }
            parentUpdates.add(p);
        }
        if (!parentUpdates.isEmpty()) update parentUpdates;
    }
}
