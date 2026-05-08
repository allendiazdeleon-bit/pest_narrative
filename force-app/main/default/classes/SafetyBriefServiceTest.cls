@isTest
private class SafetyBriefServiceTest {

    @isTest static void testBriefForGoGreenQuarterly() {
        Account a = new Account(Name = 'Quarterly Customer');
        insert a;
        WorkType wt = new WorkType(Name = 'GoGreen Quarterly Pest',
                                    EstimatedDuration = 60, DurationType = 'Minutes');
        insert wt;
        WorkOrder wo = new WorkOrder(Subject = 'Q1 GoGreen', AccountId = a.Id, WorkTypeId = wt.Id,
                                     Status = 'New',
                                     Street = '1407 Avalon Park Blvd', City = 'Orlando',
                                     State = 'FL', PostalCode = '32828');
        insert wo;

        Test.startTest();
        SafetyBriefService.SafetyBrief brief = SafetyBriefService.getBrief(wo.Id);
        Test.stopTest();

        System.assertEquals(wo.Id, brief.workOrderId);
        System.assertNotEquals(null, brief.summary);
        System.assertNotEquals(null, brief.siteRiskLevel);
        System.assert(brief.recommendedPpe.size() >= 4);
    }

    @isTest static void testBriefForFumigation() {
        Account a = new Account(Name = 'Fumigation Customer');
        insert a;
        WorkType wt = new WorkType(Name = 'Whole-Home Tent Fumigation',
                                    EstimatedDuration = 240, DurationType = 'Minutes');
        insert wt;
        WorkOrder wo = new WorkOrder(Subject = 'Tent Fum', AccountId = a.Id, WorkTypeId = wt.Id,
                                     Status = 'New',
                                     Street = '99 Highway 50', City = 'Orlando',
                                     State = 'FL', PostalCode = '32828');
        insert wo;

        SafetyBriefService.SafetyBrief brief = SafetyBriefService.getBrief(wo.Id);
        System.assertEquals('Critical', brief.siteRiskLevel);
    }

    @isTest static void testBriefMissingWO() {
        SafetyBriefService.SafetyBrief brief = SafetyBriefService.getBrief(null);
        System.assertNotEquals(null, brief);
    }

    @isTest static void testBriefForMosquito() {
        Account a = new Account(Name = 'Mosq Customer');
        insert a;
        WorkType wt = new WorkType(Name = 'Mosquito Hunter Activation',
                                    EstimatedDuration = 60, DurationType = 'Minutes');
        insert wt;
        WorkOrder wo = new WorkOrder(Subject = 'Mosquito', AccountId = a.Id, WorkTypeId = wt.Id,
                                     Status = 'New', Street = '123 Lake Nona Blvd',
                                     City = 'Orlando', State = 'FL', PostalCode = '32827');
        insert wo;

        SafetyBriefService.SafetyBrief brief = SafetyBriefService.getBrief(wo.Id);
        System.assert(brief.hazards.size() >= 1);
    }
}
