/**
 * ChemicalApplicationService — Restricted-Use Pesticide (RUP) attestation
 * lifecycle service for masseyFlow. Per Architecture Decision #10, the
 * RUP attestation reuses the inherited LOTO_Record__c object name; this
 * service swaps in pest semantics: chemical name, dose, EPA reg #,
 * applicator + second-person verifier, and the gate logic that decides
 * whether all required chemical-application steps for a Work Order are
 * complete (so the work execution step can unlock).
 *
 * Manages the lifecycle of LOTO_Record__c rows tied to a Work Order:
 *   Pending -> Isolated -> Verified -> Removed
 *   (mapped semantically: Pending = drafted, Isolated = chemical applied,
 *    Verified = second-person sign-off complete, Removed = corrected /
 *    superseded).
 *
 * Enforces the safety rule that the second-person Verifier MUST be a
 * different user than the Applicator. Provides deterministic
 * application-step suggestions per pest Work Type for the field tech UI.
 *
 * Massey RUP coverage: Termidor SC perimeter trench (Termite), Sentricon
 * Recruit HD bait reload (Termite), DeltaGard CS ULV fog (Mosquito), and
 * targeted general-use applications for Quarterly Pest Service.
 *
 * Public method signatures preserved from the inherited service so
 * existing LWC bindings continue to resolve.
 */
public with sharing class ChemicalApplicationService {

    // ------------------------------------------------------------------
    // DTOs
    // ------------------------------------------------------------------

    public class LotoView {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String energySource;
        @AuraEnabled public String isolationPoint;
        @AuraEnabled public String lockTagNumber;
        @AuraEnabled public String status;
        @AuraEnabled public String isolatedByName;
        @AuraEnabled public DateTime isolatedAt;
        @AuraEnabled public String verifiedByName;
        @AuraEnabled public DateTime verifiedAt;
        @AuraEnabled public String photoContentVersionId;
        @AuraEnabled public String notes;
        @AuraEnabled public String chemicalName;
        @AuraEnabled public Decimal doseAmount;
        @AuraEnabled public String epaRegNumber;
    }

    public class LotoSummary {
        @AuraEnabled public Id workOrderId;
        @AuraEnabled public Integer totalPoints;
        @AuraEnabled public Integer pendingCount;
        @AuraEnabled public Integer isolatedCount;
        @AuraEnabled public Integer verifiedCount;
        @AuraEnabled public Integer removedCount;
        @AuraEnabled public Boolean allVerified;
        @AuraEnabled public Boolean canStartWork;
        @AuraEnabled public List<LotoView> records;
    }

    // ------------------------------------------------------------------
    // Read
    // ------------------------------------------------------------------

    @AuraEnabled(cacheable=true)
    public static LotoSummary getSummary(Id workOrderId) {
        if (workOrderId == null) {
            throw new AuraHandledException('workOrderId is required');
        }

        LotoSummary summary = new LotoSummary();
        summary.workOrderId = workOrderId;
        summary.records = new List<LotoView>();
        summary.totalPoints = 0;
        summary.pendingCount = 0;
        summary.isolatedCount = 0;
        summary.verifiedCount = 0;
        summary.removedCount = 0;
        summary.allVerified = false;
        summary.canStartWork = false;

        try {
            for (LOTO_Record__c rec : [
                SELECT Id, Name, Energy_Source__c, Isolation_Point__c, Lock_Tag_Number__c,
                       Status__c, Isolated_By__c, Isolated_By__r.Name, Isolated_At__c,
                       Verified_By__c, Verified_By__r.Name, Verified_At__c,
                       Photo_ContentVersion_Id__c, Notes__c,
                       Chemical_Name__c, Dose_Amount__c, EPA_Reg_Number__c
                FROM LOTO_Record__c
                WHERE Work_Order__c = :workOrderId
                WITH SECURITY_ENFORCED
                ORDER BY CreatedDate ASC
            ]) {
                LotoView v = new LotoView();
                v.id = rec.Id;
                v.name = rec.Name;
                v.energySource = rec.Energy_Source__c;
                v.isolationPoint = rec.Isolation_Point__c;
                v.lockTagNumber = rec.Lock_Tag_Number__c;
                v.status = rec.Status__c;
                v.isolatedByName = rec.Isolated_By__r != null ? rec.Isolated_By__r.Name : null;
                v.isolatedAt = rec.Isolated_At__c;
                v.verifiedByName = rec.Verified_By__r != null ? rec.Verified_By__r.Name : null;
                v.verifiedAt = rec.Verified_At__c;
                v.photoContentVersionId = rec.Photo_ContentVersion_Id__c;
                v.notes = rec.Notes__c;
                v.chemicalName = rec.Chemical_Name__c;
                v.doseAmount = rec.Dose_Amount__c;
                v.epaRegNumber = rec.EPA_Reg_Number__c;
                summary.records.add(v);

                summary.totalPoints++;
                if (rec.Status__c == 'Pending') {
                    summary.pendingCount++;
                } else if (rec.Status__c == 'Isolated') {
                    summary.isolatedCount++;
                } else if (rec.Status__c == 'Verified') {
                    summary.verifiedCount++;
                } else if (rec.Status__c == 'Removed') {
                    summary.removedCount++;
                }
            }

            // allVerified = at least one record exists AND every non-removed
            // application is Verified (second-person attestation captured)
            // canStartWork = same condition (gate logic for the WO execution
            // step — all RUP attestations have full second-person sign-off)
            if (summary.totalPoints > 0) {
                Integer activePoints = summary.totalPoints - summary.removedCount;
                summary.allVerified = activePoints > 0 && summary.verifiedCount == activePoints;
                summary.canStartWork = summary.allVerified;
            }
        } catch (Exception e) {
            throw new AuraHandledException('Unable to load RUP attestation summary: ' + e.getMessage());
        }

        return summary;
    }

    // ------------------------------------------------------------------
    // Mutations
    // ------------------------------------------------------------------

    @AuraEnabled
    public static Id createIsolationPoint(
        Id workOrderId,
        String energySource,
        String isolationPoint,
        String lockTagNumber,
        String notes
    ) {
        if (workOrderId == null) {
            throw new AuraHandledException('workOrderId is required');
        }
        if (String.isBlank(energySource)) {
            throw new AuraHandledException('energySource is required');
        }
        if (String.isBlank(isolationPoint)) {
            throw new AuraHandledException('isolationPoint is required');
        }
        if (String.isBlank(lockTagNumber)) {
            throw new AuraHandledException('lockTagNumber is required');
        }

        LOTO_Record__c rec = new LOTO_Record__c();
        rec.Work_Order__c = workOrderId;
        rec.Energy_Source__c = energySource;
        rec.Isolation_Point__c = isolationPoint;
        rec.Lock_Tag_Number__c = lockTagNumber;
        rec.Status__c = 'Pending';
        if (String.isNotBlank(notes)) {
            rec.Notes__c = notes;
        }

        try {
            insert rec;
        } catch (DmlException e) {
            throw new AuraHandledException('Unable to create RUP attestation row: ' + e.getDmlMessage(0));
        }

        return rec.Id;
    }

    @AuraEnabled
    public static void markIsolated(Id lotoId, String photoContentVersionId) {
        if (lotoId == null) {
            throw new AuraHandledException('lotoId is required');
        }

        LOTO_Record__c rec;
        try {
            rec = [
                SELECT Id, Status__c
                FROM LOTO_Record__c
                WHERE Id = :lotoId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
        } catch (Exception e) {
            throw new AuraHandledException('RUP attestation row not found: ' + lotoId);
        }

        rec.Status__c = 'Isolated';
        rec.Isolated_By__c = UserInfo.getUserId();
        rec.Isolated_At__c = System.now();
        if (String.isNotBlank(photoContentVersionId)) {
            rec.Photo_ContentVersion_Id__c = photoContentVersionId;
        }

        try {
            update rec;
        } catch (DmlException e) {
            throw new AuraHandledException('Unable to mark applied: ' + e.getDmlMessage(0));
        }
    }

    @AuraEnabled
    public static void markVerified(Id lotoId) {
        if (lotoId == null) {
            throw new AuraHandledException('lotoId is required');
        }

        LOTO_Record__c rec;
        try {
            rec = [
                SELECT Id, Status__c, Isolated_By__c
                FROM LOTO_Record__c
                WHERE Id = :lotoId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
        } catch (Exception e) {
            throw new AuraHandledException('RUP attestation row not found: ' + lotoId);
        }

        Id currentUserId = UserInfo.getUserId();

        // Safety rule: the second-person verifier MUST be a different user
        // than the certified applicator that logged the application.
        if (rec.Isolated_By__c != null && rec.Isolated_By__c == currentUserId) {
            throw new AuraHandledException(
                'Safety violation: the second-person verifier must be a different user than the certified applicator.'
            );
        }

        rec.Status__c = 'Verified';
        rec.Verified_By__c = currentUserId;
        rec.Verified_At__c = System.now();

        try {
            update rec;
        } catch (DmlException e) {
            throw new AuraHandledException('Unable to mark verified: ' + e.getDmlMessage(0));
        }
    }

    @AuraEnabled
    public static void markRemoved(Id lotoId) {
        if (lotoId == null) {
            throw new AuraHandledException('lotoId is required');
        }

        LOTO_Record__c rec;
        try {
            rec = [
                SELECT Id, Status__c
                FROM LOTO_Record__c
                WHERE Id = :lotoId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
        } catch (Exception e) {
            throw new AuraHandledException('RUP attestation row not found: ' + lotoId);
        }

        rec.Status__c = 'Removed';
        rec.Removed_By__c = UserInfo.getUserId();
        rec.Removed_At__c = System.now();

        try {
            update rec;
        } catch (DmlException e) {
            throw new AuraHandledException('Unable to mark removed: ' + e.getDmlMessage(0));
        }
    }

    // ------------------------------------------------------------------
    // Suggestions
    // ------------------------------------------------------------------

    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> suggestIsolationPointsForWorkType(Id workOrderId) {
        List<Map<String, String>> suggestions = new List<Map<String, String>>();

        if (workOrderId == null) {
            return suggestions;
        }

        String workTypeName = null;
        try {
            for (WorkOrder wo : [
                SELECT Id, WorkType.Name
                FROM WorkOrder
                WHERE Id = :workOrderId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ]) {
                workTypeName = wo.WorkType != null ? wo.WorkType.Name : null;
            }
        } catch (Exception e) {
            // Fall through to default suggestion below.
            workTypeName = null;
        }

        if (workTypeName == 'Termite Liquid Treatment (Termidor)') {
            suggestions.add(buildSuggestion('Restricted-Use Pesticide', 'Termidor SC perimeter trench application — full attestation required'));
            suggestions.add(buildSuggestion('Restricted-Use Pesticide', 'Concrete-slab drilling / sub-slab injection points'));
        } else if (workTypeName == 'Sentricon Install' || workTypeName == 'Sentricon Service') {
            suggestions.add(buildSuggestion('Restricted-Use Pesticide', 'Recruit HD bait reload — log per-station dose'));
            suggestions.add(buildSuggestion('Bait Station Perimeter', 'Perimeter ring inspection + replacement of triggered stations'));
        } else if (workTypeName == 'Mosquito Surge Area Treatment') {
            suggestions.add(buildSuggestion('Restricted-Use Pesticide', 'DeltaGard CS ULV fog — log per-zone dose; avoid drift to apiaries'));
            suggestions.add(buildSuggestion('Larvicide', 'Standing-water larvicide briquette placement'));
        } else if (workTypeName == 'Mosquito System Install' || workTypeName == 'Mosquito System Service') {
            suggestions.add(buildSuggestion('Insecticide Reservoir', 'Mosquito system controller refill + nozzle calibration'));
        } else if (workTypeName == 'Quarterly Pest Service') {
            suggestions.add(buildSuggestion('General-Use Pesticide', 'Perimeter spray + interior crack-and-crevice'));
            suggestions.add(buildSuggestion('Bait Station', 'Interior bait-station inspection / refill'));
        } else if (workTypeName == 'Wasp / Stinging Insect Removal' || workTypeName == 'Pest Inspection (New)' ||
                   workTypeName == 'Termite Inspection (Booster)') {
            // Intentionally empty — these work types are inspection / spot
            // treatments and do not require a full RUP attestation row.
        } else {
            suggestions.add(buildSuggestion('Other', 'Identify and log primary chemical application + EPA reg #'));
        }

        return suggestions;
    }

    private static Map<String, String> buildSuggestion(String energySource, String point) {
        Map<String, String> m = new Map<String, String>();
        m.put('energySource', energySource);
        m.put('point', point);
        return m;
    }
}
