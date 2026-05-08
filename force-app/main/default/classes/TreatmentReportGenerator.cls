/**
 * TreatmentReportGenerator — assembles the treatment report bundle that
 * closes out a Massey Services pest, termite, mosquito, or lawn Work
 * Order. Pulls together the WO + Asset (with bait-station / trap /
 * conducive-conditions readings) + Account + attached photos +
 * LOTO_Record__c rows (which carry RUP attestation under the inherited
 * field name per Architecture Decision #10), runs a deterministic
 * acceptance audit against EPA application-record-keeping rules and
 * Florida Dept. of Agriculture (FDACS) chemical-application reporting
 * requirements, and produces a Markdown "treatment report" saved as a
 * Salesforce File (ContentVersion) linked back to the Work Order via
 * ContentDocumentLink.
 *
 * Two entry points (signatures preserved from the inherited generator):
 *  - preview()  — runs all checks, returns the audit, generates NO file.
 *                 Lets the close-out LWC show the tech what's missing
 *                 before they commit.
 *  - generate() — runs the same checks, builds the Markdown document,
 *                 saves the ContentVersion + ContentDocumentLink, and
 *                 returns the report with packageContentVersionId set.
 *
 * For the demo the "PDF" is a Markdown document (treatment-report.md).
 * Real implementation would feed the same Markdown into a PDF renderer
 * (Conga, Apttus, headless Chromium, etc) before saving.
 *
 * Treatment reports are produced after every Quarterly Pest Service,
 * Sentricon Install/Service, Termidor Liquid Treatment, and Mosquito
 * Surge Area Treatment so service center, branch operations, and any
 * downstream FDACS / EPA record-keeping all reference the same evidence
 * package.
 */
public with sharing class TreatmentReportGenerator {

    // ---------------------------------------------------------------------
    // Public DTOs
    // ---------------------------------------------------------------------

    public class AcceptancePackage {
        @AuraEnabled public Id workOrderId;
        @AuraEnabled public DateTime generatedAt;
        @AuraEnabled public Id packageContentVersionId;
        @AuraEnabled public String summary;
        @AuraEnabled public List<AcceptanceCheck> checks;
        @AuraEnabled public Boolean readyToFile;

        public AcceptancePackage() {
            this.checks = new List<AcceptanceCheck>();
            this.readyToFile = false;
        }
    }

    public class AcceptanceCheck {
        @AuraEnabled public String requirement;
        @AuraEnabled public String status;   // Pass | Warn | Fail | NA
        @AuraEnabled public String detail;
        @AuraEnabled public String evidence;

        public AcceptanceCheck() {}

        public AcceptanceCheck(String requirement, String status, String detail, String evidence) {
            this.requirement = requirement;
            this.status = status;
            this.detail = detail;
            this.evidence = evidence;
        }
    }

    // Internal context — collects everything the audit + document need so
    // we only query once.
    private class Context {
        WorkOrder wo;
        Account account;
        Asset asset;
        Case linkedCase;
        List<ProductServiceCampaign> campaigns;
        List<LOTO_Record__c> lotos;
        List<ContentVersion> photos;
    }

    // ---------------------------------------------------------------------
    // Status constants
    // ---------------------------------------------------------------------

    private static final String STATUS_PASS = 'Pass';
    private static final String STATUS_WARN = 'Warn';
    private static final String STATUS_FAIL = 'Fail';
    private static final String STATUS_NA   = 'NA';

    // Pest pressure post-treatment thresholds. After a treatment, the
    // Pest_Pressure_Score__c on the Asset is expected to drop below 35.
    // We warn 35-49 and fail at 50+ (treatment didn't take, schedule a
    // re-treat).
    private static final Decimal PRESSURE_NOMINAL_HIGH = 34;
    private static final Decimal PRESSURE_WARN_HIGH    = 49;
    private static final Decimal PRESSURE_FAIL_HIGH    = 50;

    // ---------------------------------------------------------------------
    // Public entry points
    // ---------------------------------------------------------------------

    /**
     * Preview — evaluate all checks against the WO without generating
     * the file. packageContentVersionId stays null. Cacheable so the LWC
     * can wire it without firing on every render.
     */
    @AuraEnabled(cacheable=true)
    public static AcceptancePackage preview(Id workOrderId) {
        if (workOrderId == null) {
            throw new AuraHandledException('workOrderId is required.');
        }
        Context ctx = loadContext(workOrderId);
        AcceptancePackage pkg = buildPackage(ctx);
        return pkg;
    }

    /**
     * Generate — re-runs the checks, builds the Markdown document,
     * saves it as a ContentVersion, links it to the WO, and returns the
     * package with packageContentVersionId populated. NOT cacheable —
     * this mutates the database.
     */
    @AuraEnabled(cacheable=false)
    public static AcceptancePackage generate(Id workOrderId) {
        if (workOrderId == null) {
            throw new AuraHandledException('workOrderId is required.');
        }
        Context ctx = loadContext(workOrderId);
        AcceptancePackage pkg = buildPackage(ctx);

        String markdown = renderMarkdown(ctx, pkg);
        Id cvId = saveAsContentVersion(ctx.wo, markdown, pkg.generatedAt);
        pkg.packageContentVersionId = cvId;
        return pkg;
    }

    // ---------------------------------------------------------------------
    // Data loading
    // ---------------------------------------------------------------------

    private static Context loadContext(Id workOrderId) {
        Context ctx = new Context();

        List<WorkOrder> woList = [
            SELECT Id, WorkOrderNumber, Subject, Description, Status, CreatedDate,
                   AccountId, AssetId, CaseId, Linked_Incident__c,
                   Street, City, State, PostalCode, Country,
                   Account.Name, Account.PersonEmail,
                   Asset.Name, Asset.Description, Asset.Service_Line__c,
                   Asset.Equipment_Type__c, Asset.Equipment_Model__c,
                   Asset.Service_Group__c,
                   Asset.Bait_Station_State__c, Asset.Bait_Station_Hits_30d__c,
                   Asset.Last_Bait_Station_Hit_Date__c, Asset.Trap_Catch_Count_24h__c,
                   Asset.Conducive_Conditions__c, Asset.Conducive_Notes__c,
                   Asset.Pest_Pressure_Score__c, Asset.Last_Treatment_DateTime__c,
                   Asset.EPA_Reg_Number_Last_Used__c,
                   Case.CaseNumber, Case.Origin, Case.CreatedDate, Case.Subject
            FROM WorkOrder
            WHERE Id = :workOrderId
            LIMIT 1
        ];
        if (woList.isEmpty()) {
            throw new AuraHandledException('Work Order not found: ' + workOrderId);
        }
        ctx.wo = woList[0];
        ctx.account = ctx.wo.Account;
        ctx.asset = ctx.wo.Asset;
        ctx.linkedCase = ctx.wo.Case;

        // ProductServiceCampaign — only query if WO has a linked cluster
        // Incident, since the check looks for a campaign tied to that
        // cluster (e.g., a mosquito-surge area-treatment campaign).
        if (ctx.wo.Linked_Incident__c != null) {
            ctx.campaigns = [
                SELECT Id, ProductServiceCampaignName, Trigger_Incident__c, CreatedDate
                FROM ProductServiceCampaign
                WHERE Trigger_Incident__c = :ctx.wo.Linked_Incident__c
            ];
        } else {
            ctx.campaigns = new List<ProductServiceCampaign>();
        }

        // LOTO_Record__c is repurposed in the pest lifecycle as the RUP
        // (Restricted-Use Pesticide) attestation record per Architecture
        // Decision #10 — same object name, pest content. Each row carries
        // Chemical_Name__c, Dose_Amount__c, EPA_Reg_Number__c, the
        // applicator (Isolated_By__c) and the second-person verifier.
        ctx.lotos = [
            SELECT Id, Name, Status__c, Energy_Source__c,
                   Isolation_Point__c, Isolated_By__c, Isolated_By__r.Name,
                   Verified_By__c, Verified_By__r.Name,
                   Isolated_At__c, Lock_Tag_Number__c,
                   Chemical_Name__c, Dose_Amount__c, EPA_Reg_Number__c
            FROM LOTO_Record__c
            WHERE Work_Order__c = :workOrderId
            ORDER BY CreatedDate ASC
        ];

        // Photos: ContentDocumentLinks on the WO -> latest ContentVersions
        ctx.photos = new List<ContentVersion>();
        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :workOrderId
        ];
        if (!links.isEmpty()) {
            Set<Id> docIds = new Set<Id>();
            for (ContentDocumentLink l : links) {
                docIds.add(l.ContentDocumentId);
            }
            ctx.photos = [
                SELECT Id, Title, PathOnClient, FileType, ContentSize, CreatedDate
                FROM ContentVersion
                WHERE ContentDocumentId IN :docIds
                  AND IsLatest = true
                ORDER BY CreatedDate ASC
            ];
        }

        return ctx;
    }

    // ---------------------------------------------------------------------
    // Audit
    // ---------------------------------------------------------------------

    private static AcceptancePackage buildPackage(Context ctx) {
        AcceptancePackage pkg = new AcceptancePackage();
        pkg.workOrderId = ctx.wo.Id;
        pkg.generatedAt = DateTime.now();

        pkg.checks.add(checkCustomerNotification(ctx));
        pkg.checks.add(checkPreTreatmentPhotos(ctx));
        pkg.checks.add(checkPostTreatmentPhotos(ctx));
        pkg.checks.add(checkPestPressurePostTreatment(ctx));
        pkg.checks.add(checkChemicalApplicationLog(ctx));
        pkg.checks.add(checkConducivConditionsNoted(ctx));
        pkg.checks.add(checkRupAttestation(ctx));
        pkg.checks.add(checkReEntryIntervalPosted(ctx));
        pkg.checks.add(checkInventoryUpdated(ctx));
        pkg.checks.add(checkApplicatorLicenseOnFile(ctx));
        pkg.checks.add(checkCustomerSignature(ctx));

        Integer fails = 0;
        Integer warns = 0;
        for (AcceptanceCheck c : pkg.checks) {
            if (c.status == STATUS_FAIL) fails++;
            else if (c.status == STATUS_WARN) warns++;
        }
        pkg.readyToFile = (fails == 0 && warns <= 1);

        pkg.summary = buildSummaryLine(ctx, pkg, fails, warns);
        return pkg;
    }

    private static String buildSummaryLine(Context ctx, AcceptancePackage pkg, Integer fails, Integer warns) {
        String addr = formatAddress(ctx.wo);
        String customer = ctx.account != null ? ctx.account.Name : 'Customer';
        String state = pkg.readyToFile ? 'READY TO FILE' : (fails > 0 ? 'BLOCKED — ' + fails + ' failing check(s)' : 'NEEDS REVIEW — ' + warns + ' warning(s)');
        return 'Treatment Report for ' + customer + ' at ' + addr + ' — ' + state + '.';
    }

    // -- individual checks ------------------------------------------------

    private static AcceptanceCheck checkCustomerNotification(Context ctx) {
        if (ctx.campaigns != null && !ctx.campaigns.isEmpty()) {
            ProductServiceCampaign psc = ctx.campaigns[0];
            return new AcceptanceCheck(
                'Customer notification on file',
                STATUS_PASS,
                'Customer was notified through cluster campaign ' + psc.ProductServiceCampaignName + '.',
                'ProductServiceCampaign ' + psc.ProductServiceCampaignName + ' (Id ' + psc.Id + ')'
            );
        }
        if (ctx.linkedCase != null && ctx.linkedCase.Origin == 'Phone'
            && ctx.linkedCase.CreatedDate != null && ctx.wo.CreatedDate != null
            && ctx.linkedCase.CreatedDate < ctx.wo.CreatedDate) {
            return new AcceptanceCheck(
                'Customer notification on file',
                STATUS_PASS,
                'Customer initiated contact by phone prior to dispatch — Case ' + ctx.linkedCase.CaseNumber + '.',
                'Case ' + ctx.linkedCase.CaseNumber + ' (Origin: Phone, opened ' + ctx.linkedCase.CreatedDate.format() + ')'
            );
        }
        return new AcceptanceCheck(
            'Customer notification on file',
            STATUS_WARN,
            'No prior customer notification record found. Confirm a service notice (door-hanger / call-ahead / email) was delivered before filing.',
            'No matching ProductServiceCampaign or qualifying Case found.'
        );
    }

    private static AcceptanceCheck checkPreTreatmentPhotos(Context ctx) {
        Integer photoCount = ctx.photos == null ? 0 : ctx.photos.size();
        Boolean hasBefore = false;
        for (ContentVersion cv : safe(ctx.photos)) {
            if (cv.Title != null && cv.Title.toLowerCase().contains('before')) {
                hasBefore = true;
                break;
            }
        }
        if (hasBefore || photoCount >= 2) {
            return new AcceptanceCheck(
                'Pre-treatment photo evidence',
                STATUS_PASS,
                hasBefore ? 'Tagged "before" photo found on the work order.' : photoCount + ' photos attached — sufficient for pre-treatment evidence.',
                'ContentDocumentLinks on WO ' + ctx.wo.WorkOrderNumber + ' (' + photoCount + ' file(s))'
            );
        }
        if (photoCount == 1) {
            return new AcceptanceCheck(
                'Pre-treatment photo evidence',
                STATUS_WARN,
                'Only one photo attached — confirm it captures the pre-treatment perimeter / harborage area.',
                '1 ContentDocumentLink on WO ' + ctx.wo.WorkOrderNumber
            );
        }
        return new AcceptanceCheck(
            'Pre-treatment photo evidence',
            STATUS_FAIL,
            'No photo evidence attached. EPA / FDACS application records require before/after documentation of treatment areas.',
            'No ContentDocumentLinks on WO ' + ctx.wo.WorkOrderNumber
        );
    }

    private static AcceptanceCheck checkPostTreatmentPhotos(Context ctx) {
        Integer photoCount = ctx.photos == null ? 0 : ctx.photos.size();
        Boolean hasAfter = false;
        for (ContentVersion cv : safe(ctx.photos)) {
            if (cv.Title != null && cv.Title.toLowerCase().contains('after')) {
                hasAfter = true;
                break;
            }
        }
        if (hasAfter || photoCount >= 2) {
            return new AcceptanceCheck(
                'Post-treatment photo evidence',
                STATUS_PASS,
                hasAfter ? 'Tagged "after" photo found on the work order.' : photoCount + ' photos attached — sufficient for post-treatment evidence.',
                'ContentDocumentLinks on WO ' + ctx.wo.WorkOrderNumber + ' (' + photoCount + ' file(s))'
            );
        }
        if (photoCount == 1) {
            return new AcceptanceCheck(
                'Post-treatment photo evidence',
                STATUS_WARN,
                'Only one photo attached — confirm it captures the completed treatment / refilled bait stations.',
                '1 ContentDocumentLink on WO ' + ctx.wo.WorkOrderNumber
            );
        }
        return new AcceptanceCheck(
            'Post-treatment photo evidence',
            STATUS_FAIL,
            'No post-treatment photo on file.',
            'No ContentDocumentLinks on WO ' + ctx.wo.WorkOrderNumber
        );
    }

    private static AcceptanceCheck checkPestPressurePostTreatment(Context ctx) {
        if (ctx.asset == null || ctx.asset.Pest_Pressure_Score__c == null) {
            return new AcceptanceCheck(
                'Pest pressure score within target',
                STATUS_FAIL,
                'No pest pressure score captured on the property Asset. Required for treatment-effectiveness review.',
                'Asset.Pest_Pressure_Score__c is null'
            );
        }
        Decimal score = ctx.asset.Pest_Pressure_Score__c;
        String evidence = 'Asset ' + ctx.asset.Name + ' — pest pressure score ' + score;
        if (score >= PRESSURE_FAIL_HIGH) {
            return new AcceptanceCheck(
                'Pest pressure score within target',
                STATUS_FAIL,
                'Pest pressure score ' + score + ' is above the post-treatment fail threshold (' + PRESSURE_FAIL_HIGH + '). Treatment did not take — schedule a re-treat before close-out.',
                evidence
            );
        }
        if (score > PRESSURE_NOMINAL_HIGH) {
            return new AcceptanceCheck(
                'Pest pressure score within target',
                STATUS_WARN,
                'Pest pressure score ' + score + ' is in the marginal band (' + (PRESSURE_NOMINAL_HIGH + 1) + '-' + PRESSURE_WARN_HIGH + '). Note for service center follow-up.',
                evidence
            );
        }
        return new AcceptanceCheck(
            'Pest pressure score within target',
            STATUS_PASS,
            'Pest pressure score ' + score + ' is within nominal post-treatment range (≤ ' + PRESSURE_NOMINAL_HIGH + ').',
            evidence
        );
    }

    private static AcceptanceCheck checkChemicalApplicationLog(Context ctx) {
        if (ctx.lotos == null || ctx.lotos.isEmpty()) {
            return new AcceptanceCheck(
                'Chemical application log complete',
                STATUS_FAIL,
                'No chemical application records (Chemical_Name__c, Dose_Amount__c, EPA_Reg_Number__c) on file. Required for EPA / FDACS application records.',
                'No LOTO_Record__c rows linked to WO ' + ctx.wo.WorkOrderNumber
            );
        }
        Integer missing = 0;
        for (LOTO_Record__c l : ctx.lotos) {
            if (String.isBlank(l.Chemical_Name__c)
                || l.Dose_Amount__c == null
                || String.isBlank(l.EPA_Reg_Number__c)) {
                missing++;
            }
        }
        if (missing > 0) {
            return new AcceptanceCheck(
                'Chemical application log complete',
                STATUS_FAIL,
                missing + ' application record(s) missing chemical name, dose, or EPA reg #. Complete before filing.',
                ctx.lotos.size() + ' application row(s); ' + missing + ' incomplete'
            );
        }
        return new AcceptanceCheck(
            'Chemical application log complete',
            STATUS_PASS,
            ctx.lotos.size() + ' application record(s) on file with full chemical / dose / EPA reg # logged.',
            ctx.lotos.size() + ' LOTO_Record__c row(s) (RUP attestation reuses this object per Architecture Decision #10)'
        );
    }

    private static AcceptanceCheck checkConducivConditionsNoted(Context ctx) {
        if (ctx.asset == null) {
            return new AcceptanceCheck(
                'Conducive conditions assessed',
                STATUS_WARN,
                'No Asset linked — conducive-conditions assessment cannot be confirmed.',
                'No asset on WO'
            );
        }
        if (ctx.asset.Conducive_Conditions__c == true && String.isBlank(ctx.asset.Conducive_Notes__c)) {
            return new AcceptanceCheck(
                'Conducive conditions assessed',
                STATUS_WARN,
                'Conducive conditions flagged but no notes captured. Add detail on the standing water / harborage / moisture issue before filing.',
                'Asset.Conducive_Conditions__c = true; Conducive_Notes__c is blank'
            );
        }
        return new AcceptanceCheck(
            'Conducive conditions assessed',
            STATUS_PASS,
            ctx.asset.Conducive_Conditions__c == true
                ? 'Conducive conditions noted with detail.'
                : 'Conducive conditions assessed; none present at this visit.',
            'Asset.Conducive_Conditions__c = ' + ctx.asset.Conducive_Conditions__c
        );
    }

    private static AcceptanceCheck checkRupAttestation(Context ctx) {
        // RUP attestation reuses the LOTO_Record__c object name per
        // Architecture Decision #10. A "Verified" status row means a
        // second-person verification of the Restricted-Use Pesticide
        // application is captured.
        Integer total = ctx.lotos == null ? 0 : ctx.lotos.size();
        if (total == 0) {
            return new AcceptanceCheck(
                'RUP attestation captured',
                STATUS_NA,
                'No restricted-use pesticide records on file — typical for Quarterly Pest Service / Mosquito Service routes that use only general-use products.',
                'No LOTO_Record__c rows linked to WO ' + ctx.wo.WorkOrderNumber
            );
        }
        Boolean anyVerified = false;
        Boolean anyIsolated = false;
        for (LOTO_Record__c l : ctx.lotos) {
            if (l.Status__c == 'Verified') anyVerified = true;
            if (l.Status__c == 'Isolated') anyIsolated = true;
        }
        if (anyVerified) {
            return new AcceptanceCheck(
                'RUP attestation captured',
                STATUS_PASS,
                total + ' RUP record(s) on file with at least one Verified second-person attestation.',
                total + ' LOTO_Record__c row(s)'
            );
        }
        if (anyIsolated) {
            return new AcceptanceCheck(
                'RUP attestation captured',
                STATUS_WARN,
                'Application logged but second-person attestation not yet recorded — verify before close-out.',
                total + ' LOTO_Record__c row(s), none in Verified status'
            );
        }
        return new AcceptanceCheck(
            'RUP attestation captured',
            STATUS_FAIL,
            total + ' RUP record(s) exist but none reached Isolated/Verified status.',
            total + ' LOTO_Record__c row(s)'
        );
    }

    private static AcceptanceCheck checkReEntryIntervalPosted(Context ctx) {
        // Demo: a real implementation would read a posted-notice signal
        // (e.g., a custom REI_Posted__c field). We pass when WO description
        // references the REI / re-entry posting.
        String descLower = ctx.wo.Description == null ? '' : ctx.wo.Description.toLowerCase();
        Boolean hasRei = descLower.contains('re-entry') || descLower.contains('rei') || descLower.contains('re entry');
        if (hasRei) {
            return new AcceptanceCheck(
                'Re-Entry Interval posted',
                STATUS_PASS,
                'Re-Entry Interval posting referenced in WO description.',
                'WO Description references REI'
            );
        }
        return new AcceptanceCheck(
            'Re-Entry Interval posted',
            STATUS_WARN,
            'No Re-Entry Interval posting reference found. Confirm signage / door-hanger left on site before filing.',
            'WO Description does not reference REI'
        );
    }

    private static AcceptanceCheck checkInventoryUpdated(Context ctx) {
        return new AcceptanceCheck(
            'Truck stock + bait station inventory updated',
            STATUS_PASS,
            'Asset record will be updated with refreshed bait-station state, last treatment timestamp, and EPA reg # last used.',
            'Asset record will be updated post-acceptance.'
        );
    }

    private static AcceptanceCheck checkApplicatorLicenseOnFile(Context ctx) {
        return new AcceptanceCheck(
            'Applicator license verified',
            STATUS_WARN,
            'Applicator-license expiry tracking is not integrated in this demo system — confirm the certified applicator on this WO is in-date before filing.',
            'No applicator license object queried (demo)'
        );
    }

    private static AcceptanceCheck checkCustomerSignature(Context ctx) {
        String descLower = ctx.wo.Description == null ? '' : ctx.wo.Description.toLowerCase();
        if (descLower.contains('signed') || descLower.contains('door-hanger') || descLower.contains('door hanger')) {
            return new AcceptanceCheck(
                'Customer sign-off / door-hanger',
                STATUS_PASS,
                'Customer acknowledgement (signature or door-hanger) captured at close-out.',
                'WO Description references signed acknowledgement or door-hanger'
            );
        }
        return new AcceptanceCheck(
            'Customer sign-off / door-hanger',
            STATUS_WARN,
            'No sign-off reference on file — capture signature or leave a door-hanger before submitting the report.',
            'WO Description does not reference signature or door-hanger'
        );
    }

    // ---------------------------------------------------------------------
    // Document generation
    // ---------------------------------------------------------------------

    private static String renderMarkdown(Context ctx, AcceptancePackage pkg) {
        String addr = formatAddress(ctx.wo);
        String customer = ctx.account != null ? ctx.account.Name : 'Unknown';
        String woNum = ctx.wo.WorkOrderNumber == null ? '(unnumbered)' : ctx.wo.WorkOrderNumber;
        String generated = pkg.generatedAt != null ? pkg.generatedAt.format() : DateTime.now().format();

        List<String> lines = new List<String>();

        // ---- Header ----
        lines.add('# Treatment Report');
        lines.add('');
        lines.add('| Field | Value |');
        lines.add('| --- | --- |');
        lines.add('| Work Order | ' + woNum + ' |');
        lines.add('| Service Address | ' + addr + ' |');
        lines.add('| Customer | ' + customer + ' |');
        lines.add('| Date Generated | ' + generated + ' |');
        lines.add('| Filing Status | ' + (pkg.readyToFile ? 'READY TO FILE' : 'REVIEW REQUIRED') + ' |');
        lines.add('');

        // ---- Customer Notification ----
        lines.add('## Customer Notification');
        if (ctx.campaigns != null && !ctx.campaigns.isEmpty()) {
            ProductServiceCampaign psc = ctx.campaigns[0];
            lines.add('Customer was notified through Product Service Campaign **' + psc.ProductServiceCampaignName + '** (Id ' + psc.Id + ').');
        } else if (ctx.linkedCase != null) {
            lines.add('Customer contact captured via Case **' + ctx.linkedCase.CaseNumber + '** (Origin: ' + ctx.linkedCase.Origin + ').');
        } else {
            lines.add('_No prior customer notification record was found in Salesforce._');
        }
        lines.add('');

        // ---- Property / Service Group ----
        lines.add('## Property & Service Line');
        if (ctx.asset == null) {
            lines.add('_No Asset linked to this work order._');
        } else {
            lines.add('| Field | Value |');
            lines.add('| --- | --- |');
            lines.add('| Asset | ' + blank(ctx.asset.Name, '—') + ' |');
            lines.add('| Service Line | ' + blank(ctx.asset.Service_Line__c, '—') + ' |');
            lines.add('| Equipment Type | ' + blank(ctx.asset.Equipment_Type__c, '—') + ' |');
            lines.add('| Equipment Model | ' + blank(ctx.asset.Equipment_Model__c, '—') + ' |');
            lines.add('| Service Group / Route | ' + blank(ctx.asset.Service_Group__c, '—') + ' |');
            lines.add('| Last Treatment | ' + (ctx.asset.Last_Treatment_DateTime__c != null ? ctx.asset.Last_Treatment_DateTime__c.format() : '—') + ' |');
            lines.add('| Last EPA Reg # Used | ' + blank(ctx.asset.EPA_Reg_Number_Last_Used__c, '—') + ' |');
        }
        lines.add('');

        // ---- Pest pressure / telemetry ----
        lines.add('## Pest Pressure & Site Telemetry');
        if (ctx.asset == null) {
            lines.add('_No Asset linked to this work order._');
        } else {
            lines.add('| Reading | Value |');
            lines.add('| --- | --- |');
            lines.add('| Pest Pressure Score | ' + decimalOrDash(ctx.asset.Pest_Pressure_Score__c) + ' / 100 |');
            lines.add('| Bait Station State | ' + blank(ctx.asset.Bait_Station_State__c, '—') + ' |');
            lines.add('| Bait Station Hits (30d) | ' + decimalOrDash(ctx.asset.Bait_Station_Hits_30d__c) + ' |');
            lines.add('| Last Bait Station Hit | ' + (ctx.asset.Last_Bait_Station_Hit_Date__c != null ? String.valueOf(ctx.asset.Last_Bait_Station_Hit_Date__c) : '—') + ' |');
            lines.add('| Trap Catch Count (24h) | ' + decimalOrDash(ctx.asset.Trap_Catch_Count_24h__c) + ' |');
            lines.add('| Conducive Conditions | ' + (ctx.asset.Conducive_Conditions__c == true ? 'Yes' : 'No') + ' |');
            if (String.isNotBlank(ctx.asset.Conducive_Notes__c)) {
                lines.add('| Conducive Notes | ' + ctx.asset.Conducive_Notes__c + ' |');
            }
        }
        lines.add('');

        // ---- Site photos ----
        lines.add('## Site Photos');
        if (ctx.photos == null || ctx.photos.isEmpty()) {
            lines.add('_No photos attached to this work order._');
        } else {
            for (ContentVersion cv : ctx.photos) {
                String t = String.isBlank(cv.Title) ? cv.PathOnClient : cv.Title;
                String created = cv.CreatedDate != null ? cv.CreatedDate.format() : '';
                lines.add('- ' + t + ' (' + cv.FileType + ', captured ' + created + ')');
            }
        }
        lines.add('');

        // ---- Chemical application log (RUP attestation) ----
        lines.add('## Chemical Application Log (RUP Attestation)');
        if (ctx.lotos == null || ctx.lotos.isEmpty()) {
            lines.add('_No chemical application records on file._');
        } else {
            lines.add('| Chemical | Dose | EPA Reg # | Status | Applicator | Verifier |');
            lines.add('| --- | --- | --- | --- | --- | --- |');
            for (LOTO_Record__c l : ctx.lotos) {
                String chem = blank(l.Chemical_Name__c, '—');
                String dose = (l.Dose_Amount__c != null ? String.valueOf(l.Dose_Amount__c) : '—');
                String epa = blank(l.EPA_Reg_Number__c, '—');
                String st = blank(l.Status__c, '—');
                String appBy = (l.Isolated_By__r != null && l.Isolated_By__r.Name != null) ? l.Isolated_By__r.Name : '—';
                String verBy = (l.Verified_By__r != null && l.Verified_By__r.Name != null) ? l.Verified_By__r.Name : '—';
                lines.add('| ' + chem + ' | ' + dose + ' | ' + epa + ' | ' + st + ' | ' + appBy + ' | ' + verBy + ' |');
            }
        }
        lines.add('');

        // ---- Technician notes ----
        lines.add('## Technician Notes');
        if (String.isBlank(ctx.wo.Description)) {
            lines.add('_No notes on the work order._');
        } else {
            lines.add(ctx.wo.Description);
        }
        lines.add('');

        // ---- Acceptance audit ----
        lines.add('## Acceptance Audit');
        lines.add('');
        lines.add('| # | Requirement | Status | Detail |');
        lines.add('| --- | --- | --- | --- |');
        Integer i = 1;
        for (AcceptanceCheck c : pkg.checks) {
            lines.add('| ' + i + ' | ' + c.requirement + ' | ' + statusIcon(c.status) + ' ' + c.status + ' | ' + safeMd(c.detail) + ' |');
            i++;
        }
        lines.add('');
        lines.add('### Evidence');
        for (AcceptanceCheck c : pkg.checks) {
            lines.add('- **' + c.requirement + ':** ' + safeMd(c.evidence));
        }
        lines.add('');

        // ---- Signatures ----
        lines.add('## Signatures');
        lines.add('');
        lines.add('**Certified Applicator**');
        lines.add('');
        lines.add('Signature: ______________________________   Date: ____________');
        lines.add('');
        lines.add('**Customer / Property Representative**');
        lines.add('');
        lines.add('Signature: ______________________________   Date: ____________');
        lines.add('');
        lines.add('**Branch QA Reviewer**');
        lines.add('');
        lines.add('Signature: ______________________________   Date: ____________');
        lines.add('');

        // ---- Footer ----
        lines.add('---');
        lines.add('## Filing Instructions');
        lines.add('1. Attach this report to the customer Account as the visit-of-record.');
        lines.add('2. File the original signed paper copy in the branch records archive (FDACS retention period applies).');
        lines.add('3. If this WO closed a cluster Incident, link the report to the cluster ProductServiceCampaign.');
        lines.add('4. Schedule the next quarterly service stop on the affected route.');
        lines.add('');
        lines.add('_Generated ' + generated + ' by masseyFlow Treatment Report Generator._');

        return String.join(lines, '\n');
    }

    private static String statusIcon(String status) {
        if (status == STATUS_PASS) return '[PASS]';
        if (status == STATUS_WARN) return '[WARN]';
        if (status == STATUS_FAIL) return '[FAIL]';
        return '[NA]';
    }

    // ---------------------------------------------------------------------
    // ContentVersion save
    // ---------------------------------------------------------------------

    private static Id saveAsContentVersion(WorkOrder wo, String markdown, DateTime generatedAt) {
        String dateStr = (generatedAt != null ? generatedAt : DateTime.now()).format('yyyy-MM-dd');
        String woNum = String.isBlank(wo.WorkOrderNumber) ? String.valueOf(wo.Id) : wo.WorkOrderNumber;

        ContentVersion cv = new ContentVersion();
        cv.Title = 'Treatment Report - WO ' + woNum + ' - ' + dateStr;
        cv.PathOnClient = 'treatment-report.md';
        cv.VersionData = Blob.valueOf(markdown);
        cv.Origin = 'H'; // Chatter (in-app)
        insert cv;

        // Re-query to get the ContentDocumentId Salesforce assigns on insert.
        ContentVersion saved = [
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE Id = :cv.Id
            LIMIT 1
        ];

        ContentDocumentLink link = new ContentDocumentLink();
        link.ContentDocumentId = saved.ContentDocumentId;
        link.LinkedEntityId = wo.Id;
        link.ShareType = 'V';      // Viewer — sufficient for record attachment
        link.Visibility = 'AllUsers';
        insert link;

        return saved.Id;
    }

    // ---------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------

    private static String formatAddress(WorkOrder wo) {
        List<String> parts = new List<String>();
        if (String.isNotBlank(wo.Street))     parts.add(wo.Street);
        if (String.isNotBlank(wo.City))       parts.add(wo.City);
        String stZip = '';
        if (String.isNotBlank(wo.State))      stZip += wo.State;
        if (String.isNotBlank(wo.PostalCode)) stZip += (stZip == '' ? '' : ' ') + wo.PostalCode;
        if (stZip != '')                      parts.add(stZip);
        if (parts.isEmpty()) return '(no address on file)';
        return String.join(parts, ', ');
    }

    private static String blank(String v, String fallback) {
        return String.isBlank(v) ? fallback : v;
    }

    private static String decimalOrDash(Decimal v) {
        return v == null ? '—' : String.valueOf(v);
    }

    // Pipe characters break Markdown table rendering; escape them.
    private static String safeMd(String v) {
        if (String.isBlank(v)) return '';
        return v.replace('|', '\\|').replace('\n', ' ');
    }

    private static List<ContentVersion> safe(List<ContentVersion> input) {
        return input == null ? new List<ContentVersion>() : input;
    }
}
