/**
 * WorkStepService — Apex fallback for WorkPlan/WorkStep retrieval when
 * getRelatedListRecords doesn't return data (briefcase priming gaps,
 * sharing model edges, mobile offline runtime quirks).
 *
 * Cacheable: results are primed by Komaci on first online call and survive
 * offline reads on FSL Mobile. The masseyFlow* step LWCs use this as a
 * primary path; the related-list wire stays as a secondary fallback.
 */
public with sharing class WorkStepService {

    public class WorkStepDto {
        @AuraEnabled public Id wsId;
        @AuraEnabled public String name;
        @AuraEnabled public String description;
        @AuraEnabled public String stepCategory;
        @AuraEnabled public Boolean isCritical;
        @AuraEnabled public DateTime completedAt;
        @AuraEnabled public String completedBy;
        @AuraEnabled public Decimal sortOrder;
        @AuraEnabled public String status;
        @AuraEnabled public Id workPlanId;
    }

    @AuraEnabled(cacheable=true)
    public static List<WorkStepDto> getStepsForWorkOrder(Id workOrderId) {
        List<WorkStepDto> out = new List<WorkStepDto>();
        if (workOrderId == null) return out;

        // SOQL across WorkPlan -> WorkStep. Driven by parent WO Id directly
        // so the user only needs read access on the WO (and inherited child
        // records). Works on mobile even without briefcase priming because
        // cacheable Apex is primed by Komaci automatically.
        for (WorkStep ws : [
            SELECT Id, Name, Description, Step_Category__c, Is_Critical__c,
                   Completed_At__c, Completed_By__c, Sort_Order__c, Status,
                   WorkPlanId
            FROM WorkStep
            WHERE WorkPlan.WorkOrderId = :workOrderId
            ORDER BY Sort_Order__c ASC NULLS LAST, Id ASC
            LIMIT 200
        ]) {
            WorkStepDto d = new WorkStepDto();
            d.wsId = ws.Id;
            d.name = ws.Name;
            d.description = ws.Description;
            d.stepCategory = ws.Step_Category__c;
            d.isCritical = ws.Is_Critical__c;
            d.completedAt = ws.Completed_At__c;
            d.completedBy = ws.Completed_By__c;
            d.sortOrder = ws.Sort_Order__c;
            d.status = ws.Status;
            d.workPlanId = ws.WorkPlanId;
            out.add(d);
        }
        return out;
    }
}
