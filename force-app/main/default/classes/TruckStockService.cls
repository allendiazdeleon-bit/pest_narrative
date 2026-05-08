/**
 * TruckStockService — pre-flight truck-stock check for a Massey tech.
 *
 * Aggregates parts (chemicals + bait stations + Sentricon stakes) required
 * across today's ServiceAppointments for a given ServiceResource (via
 * AssignedResource → ServiceAppointment → ParentRecordId WorkOrder →
 * ProductRequired) and compares against a deterministic mock "On Truck"
 * inventory keyed off ServiceResource Id × part name. Returns a single
 * DTO that the masseyFlowTruckStock LWC renders end-to-end.
 *
 * Pest-relevant inventory: Termidor SC, Demand CS, BifenIT, larvicide
 * tablets, Sentricon stations + AlwaysActive bait, ULV concentrate, lawn
 * granular, etc. — see Energy_Source__c picklist (P2.3).
 *
 * Demo-only:
 *   - "On Truck" is synthesized deterministically (no ProductItem /
 *     ProductTransfer query) so the same resource always shows the same
 *     stock pattern. Real implementation would join against ProductItem
 *     where Location is the resource's truck.
 *   - Read-only, no DML.
 *
 * Per CLAUDE.md: WITH SECURITY_ENFORCED, with sharing, AuraEnabled
 * cacheable. Targets the ServiceResource record-page LWC; safe to call
 * with null when used from the home-page placement (returns an empty
 * summary with a friendly message).
 */
public with sharing class TruckStockService {

    private static final Integer LOW_STOCK_THRESHOLD = 1;

    public class StockSummary {
        @AuraEnabled public Id serviceResourceId;
        @AuraEnabled public String resourceName;
        @AuraEnabled public String truckNumber;
        @AuraEnabled public DateTime lastInventoryCheck;
        @AuraEnabled public Integer todaysWoCount;
        @AuraEnabled public Boolean anyInsufficient;
        @AuraEnabled public List<TodayWoRow> todaysWos;
        @AuraEnabled public List<StockRow> stock;
        @AuraEnabled public String aiSummary;
        @AuraEnabled public String aiSeverity;

        public StockSummary() {
            this.todaysWos = new List<TodayWoRow>();
            this.stock = new List<StockRow>();
            this.todaysWoCount = 0;
            this.anyInsufficient = false;
            this.aiSeverity = 'success';
        }
    }

    public class TodayWoRow {
        @AuraEnabled public Id serviceAppointmentId;
        @AuraEnabled public Id workOrderId;
        @AuraEnabled public String workOrderNumber;
        @AuraEnabled public String subject;
        @AuraEnabled public DateTime scheduledStart;
        @AuraEnabled public List<String> partsRequired;

        public TodayWoRow() {
            this.partsRequired = new List<String>();
        }
    }

    public class StockRow {
        @AuraEnabled public String partName;
        @AuraEnabled public String partCode;
        @AuraEnabled public Integer qtyOnHand;
        @AuraEnabled public Integer requiredToday;
        @AuraEnabled public String status;
    }

    @AuraEnabled(cacheable=true)
    public static StockSummary getStockSummary(Id serviceResourceId) {
        StockSummary summary = new StockSummary();
        summary.serviceResourceId = serviceResourceId;
        summary.lastInventoryCheck = DateTime.now().addHours(-2);

        if (serviceResourceId == null) {
            summary.resourceName = 'No resource selected';
            summary.aiSummary = 'No service resource bound to this view — open a tech\'s record page to load their truck stock.';
            summary.aiSeverity = 'info';
            return summary;
        }

        List<ServiceResource> resList = [
            SELECT Id, Name
            FROM ServiceResource
            WHERE Id = :serviceResourceId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        if (resList.isEmpty()) {
            summary.resourceName = 'Unknown resource';
            summary.aiSummary = 'Service resource not found or not visible.';
            summary.aiSeverity = 'warning';
            return summary;
        }
        summary.resourceName = resList[0].Name;
        summary.truckNumber = synthTruckNumber(serviceResourceId);

        Date today = Date.today();
        Date tomorrow = today.addDays(1);

        List<ServiceAppointment> sas = [
            SELECT Id, ParentRecordId, Subject, SchedStartTime, Status
            FROM ServiceAppointment
            WHERE Id IN (
                SELECT ServiceAppointmentId
                FROM AssignedResource
                WHERE ServiceResourceId = :serviceResourceId
            )
              AND SchedStartTime >= :today
              AND SchedStartTime < :tomorrow
              AND Status NOT IN ('Completed', 'Canceled')
            WITH SECURITY_ENFORCED
            ORDER BY SchedStartTime ASC
        ];

        summary.todaysWoCount = sas.size();

        Set<Id> woIds = new Set<Id>();
        Map<Id, ServiceAppointment> saByWo = new Map<Id, ServiceAppointment>();
        for (ServiceAppointment sa : sas) {
            if (sa.ParentRecordId != null && String.valueOf(sa.ParentRecordId).startsWith('0WO')) {
                woIds.add(sa.ParentRecordId);
                saByWo.put(sa.ParentRecordId, sa);
            }
        }

        Map<Id, WorkOrder> woById = new Map<Id, WorkOrder>();
        if (!woIds.isEmpty()) {
            for (WorkOrder w : [
                SELECT Id, WorkOrderNumber, Subject
                FROM WorkOrder
                WHERE Id IN :woIds
                WITH SECURITY_ENFORCED
            ]) {
                woById.put(w.Id, w);
            }
        }

        Map<Id, List<ProductRequired>> reqByWo = new Map<Id, List<ProductRequired>>();
        Map<String, Decimal> totalQtyByPart = new Map<String, Decimal>();
        Map<String, String> codeByPart = new Map<String, String>();
        if (!woIds.isEmpty()) {
            for (ProductRequired pr : [
                SELECT Id, ParentRecordId, Product2Id, Product2.Name, Product2.ProductCode,
                       QuantityRequired
                FROM ProductRequired
                WHERE ParentRecordId IN :woIds
                WITH SECURITY_ENFORCED
            ]) {
                if (!reqByWo.containsKey(pr.ParentRecordId)) {
                    reqByWo.put(pr.ParentRecordId, new List<ProductRequired>());
                }
                reqByWo.get(pr.ParentRecordId).add(pr);

                String pn = pr.Product2 != null && pr.Product2.Name != null ? pr.Product2.Name : 'Unspecified part';
                Decimal q = pr.QuantityRequired == null ? 0 : pr.QuantityRequired;
                totalQtyByPart.put(pn, (totalQtyByPart.containsKey(pn) ? totalQtyByPart.get(pn) : 0) + q);
                if (pr.Product2 != null && pr.Product2.ProductCode != null) {
                    codeByPart.put(pn, pr.Product2.ProductCode);
                }
            }
        }

        for (ServiceAppointment sa : sas) {
            TodayWoRow row = new TodayWoRow();
            row.serviceAppointmentId = sa.Id;
            row.scheduledStart = sa.SchedStartTime;
            row.subject = sa.Subject;
            if (sa.ParentRecordId != null && woById.containsKey(sa.ParentRecordId)) {
                WorkOrder w = woById.get(sa.ParentRecordId);
                row.workOrderId = w.Id;
                row.workOrderNumber = w.WorkOrderNumber;
                if (String.isBlank(row.subject)) row.subject = w.Subject;
            }
            List<ProductRequired> prs = reqByWo.containsKey(row.workOrderId) ? reqByWo.get(row.workOrderId) : new List<ProductRequired>();
            for (ProductRequired pr : prs) {
                String pn = pr.Product2 != null && pr.Product2.Name != null ? pr.Product2.Name : 'Unspecified part';
                Decimal q = pr.QuantityRequired == null ? 0 : pr.QuantityRequired;
                row.partsRequired.add(pn + ' ×' + q.intValue());
            }
            summary.todaysWos.add(row);
        }

        Integer insufficientCount = 0;
        Integer lowCount = 0;
        String firstInsufficient = null;

        for (String partName : totalQtyByPart.keySet()) {
            StockRow s = new StockRow();
            s.partName = partName;
            s.partCode = codeByPart.containsKey(partName) ? codeByPart.get(partName) : null;
            s.requiredToday = totalQtyByPart.get(partName).intValue();
            s.qtyOnHand = synthQtyOnHand(serviceResourceId, partName, s.requiredToday);
            Integer slack = s.qtyOnHand - s.requiredToday;
            if (slack < 0) {
                s.status = 'Insufficient';
                insufficientCount++;
                if (firstInsufficient == null) firstInsufficient = partName;
            } else if (slack <= LOW_STOCK_THRESHOLD) {
                s.status = 'Low';
                lowCount++;
            } else {
                s.status = 'OK';
            }
            summary.stock.add(s);
        }
        summary.stock.sort(new StockRowComparator());

        summary.anyInsufficient = insufficientCount > 0;
        summary.aiSeverity = insufficientCount > 0 ? 'warning' : (lowCount > 0 ? 'info' : 'success');
        summary.aiSummary = buildAiSummary(summary, insufficientCount, lowCount, firstInsufficient);

        return summary;
    }

    private static Integer synthQtyOnHand(Id resourceId, String partName, Integer requiredToday) {
        String key = String.valueOf(resourceId) + '::' + (partName == null ? '' : partName);
        Integer h = Math.abs(key.hashCode());
        Integer bucket = Math.mod(h, 10);
        if (bucket < 2 && requiredToday > 0) {
            return Math.max(0, requiredToday - 1);
        }
        Integer slack = 1 + Math.mod(h / 7, 3);
        return requiredToday + slack;
    }

    private static String synthTruckNumber(Id resourceId) {
        String s = String.valueOf(resourceId);
        Integer h = Math.abs(s.hashCode());
        Integer n = 100 + Math.mod(h, 900);
        return 'MSY-' + n;
    }

    private static String buildAiSummary(StockSummary s, Integer insufficientCount, Integer lowCount, String firstInsufficient) {
        Integer woCount = s.todaysWoCount;
        if (woCount == 0) {
            return 'No work orders scheduled for today on ' + s.resourceName + '. Truck stock check skipped.';
        }
        if (insufficientCount > 0) {
            String partRef = firstInsufficient != null ? firstInsufficient : 'one part';
            String partsClause = insufficientCount == 1
                ? '1 ' + partRef + ' (insufficient)'
                : insufficientCount + ' parts insufficient';
            return 'Mostly stocked for today\'s ' + woCount + ' WO' + (woCount == 1 ? '' : 's') + ' — except ' + partsClause + '. Recommend: pick up before first WO at the branch warehouse.';
        }
        if (lowCount > 0) {
            return 'All parts present for today\'s ' + woCount + ' WO' + (woCount == 1 ? '' : 's') + '. ' + lowCount + ' part' + (lowCount == 1 ? '' : 's') + ' running low — top up at end of shift.';
        }
        return 'Truck fully stocked for today\'s ' + woCount + ' WO' + (woCount == 1 ? '' : 's') + '. No warehouse stop needed.';
    }

    private class StockRowComparator implements System.Comparator<StockRow> {
        public Integer compare(StockRow a, StockRow b) {
            Integer ra = rank(a.status);
            Integer rb = rank(b.status);
            if (ra != rb) return ra - rb;
            if (a.partName == null) return 1;
            if (b.partName == null) return -1;
            return a.partName.compareTo(b.partName);
        }
        private Integer rank(String status) {
            if (status == 'Insufficient') return 0;
            if (status == 'Low') return 1;
            return 2;
        }
    }
}
