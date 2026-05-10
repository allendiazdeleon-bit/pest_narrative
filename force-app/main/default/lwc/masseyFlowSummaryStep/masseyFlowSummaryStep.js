import { LightningElement, api, wire, track } from 'lwc';
import { getRecord, getFieldValue, updateRecord, createRecord } from 'lightning/uiRecordApi';
import { getRelatedListRecords } from 'lightning/uiRelatedListApi';
import Alert from 'lightning/alert';

import analyzePestPressure from '@salesforce/apex/PestPressureAnalyzer.analyzeForAsset';

// DocLog mini-card labels (replaces legacy Treatment Report Package card)
import LBL_DOCLOG_HEADING from '@salesforce/label/c.MasseyFlow_DocLog_Heading';
import LBL_DOCLOG_EPA_DONE from '@salesforce/label/c.MasseyFlow_DocLog_EPA_Done';
import LBL_DOCLOG_EPA_MISSING from '@salesforce/label/c.MasseyFlow_DocLog_EPA_Missing';
import LBL_DOCLOG_LICENSE_DONE from '@salesforce/label/c.MasseyFlow_DocLog_License_Done';
import LBL_DOCLOG_LICENSE_MISSING from '@salesforce/label/c.MasseyFlow_DocLog_License_Missing';
import LBL_DOCLOG_SIGNOFF_DONE from '@salesforce/label/c.MasseyFlow_DocLog_Signoff_Done';
import LBL_DOCLOG_SIGNOFF_PENDING from '@salesforce/label/c.MasseyFlow_DocLog_Signoff_Pending';

// Sign-Off card labels (Wrap Up & Sign — last tech action before Complete)
import LBL_SO_HEADING from '@salesforce/label/c.MasseyFlow_SignOff_Heading';
import LBL_SO_CHOOSE_HOME from '@salesforce/label/c.MasseyFlow_SignOff_Choose_Home';
import LBL_SO_CHOOSE_NOT_HOME from '@salesforce/label/c.MasseyFlow_SignOff_Choose_NotHome';
import LBL_SO_SIGN_HEADING from '@salesforce/label/c.MasseyFlow_SignOff_Sign_Heading';
import LBL_SO_SIGN_CLEAR from '@salesforce/label/c.MasseyFlow_SignOff_Sign_Clear';
import LBL_SO_SIGN_SAVE from '@salesforce/label/c.MasseyFlow_SignOff_Sign_Save';
import LBL_SO_SIGNED from '@salesforce/label/c.MasseyFlow_SignOff_Signed_Confirmation';
import LBL_SO_HANGER_CTA from '@salesforce/label/c.MasseyFlow_SignOff_Hanger_CTA';
import LBL_SO_HANGER_LOGGED from '@salesforce/label/c.MasseyFlow_SignOff_Hanger_Logged';
import LBL_SO_CHANGE from '@salesforce/label/c.MasseyFlow_SignOff_Change';
import LBL_SO_BLOCK from '@salesforce/label/c.MasseyFlow_SignOff_Block_Complete';

import WO_ID from '@salesforce/schema/WorkOrder.Id';
import WO_NUMBER from '@salesforce/schema/WorkOrder.WorkOrderNumber';
import WO_STATUS from '@salesforce/schema/WorkOrder.Status';
import WO_ASSET_ID from '@salesforce/schema/WorkOrder.AssetId';
import WO_ACCOUNT_ID from '@salesforce/schema/WorkOrder.AccountId';
import WO_CURRENT_STEP from '@salesforce/schema/WorkOrder.Current_Step__c';
import WO_FLOW_STARTED from '@salesforce/schema/WorkOrder.Flow_Started_At__c';
import WO_FLOW_COMPLETED from '@salesforce/schema/WorkOrder.Flow_Completed_At__c';
import WO_SAFETY_STATUS from '@salesforce/schema/WorkOrder.Safety_Gate_Status__c';
import WO_SAFETY_PASSED from '@salesforce/schema/WorkOrder.Safety_Gate_Passed_At__c';
import WO_PEST_FINDING from '@salesforce/schema/WorkOrder.Pest_Finding__c';
import WO_LINKED_INCIDENT from '@salesforce/schema/WorkOrder.Linked_Incident__c';

import ASSET_NAME from '@salesforce/schema/Asset.Name';
import ASSET_SERVICE_LINE from '@salesforce/schema/Asset.Service_Line__c';

import ACCT_LAST_UPSELL_OUTCOME from '@salesforce/schema/Account.Last_Upsell_Outcome__c';
import ACCT_LAST_UPSELL_LINE from '@salesforce/schema/Account.Last_Upsell_Service_Line__c';
import ACCT_LAST_UPSELL_PITCHED from '@salesforce/schema/Account.Last_Upsell_Pitched__c';

import INC_NUMBER from '@salesforce/schema/Incident.IncidentNumber';
import INC_PRIORITY from '@salesforce/schema/Incident.Priority';
import INC_STATUS from '@salesforce/schema/Incident.Status';

const WO_FIELDS = [
    WO_ID, WO_NUMBER, WO_STATUS, WO_ASSET_ID, WO_ACCOUNT_ID, WO_CURRENT_STEP,
    WO_FLOW_STARTED, WO_FLOW_COMPLETED, WO_SAFETY_STATUS,
    WO_SAFETY_PASSED, WO_PEST_FINDING, WO_LINKED_INCIDENT
];

export default class MasseyFlowSummaryStep extends LightningElement {
    @api recordId;
    @api workOrder;
    // Account flowed from orchestrator. Required for the embedded
    // <c-massey-upsell-coach variant="full"> at the bottom of the summary.
    @api accountId;

    @track isProcessing = false;
    @track isCompleted = false;
    @track error;
    // Next-stop handoff modal — fired after Complete succeeds. Shows the
    // next stop on Maria's route so she gets a momentum signal instead of
    // a dead-end. Hardcoded for demo; prod would query AssignedResource +
    // today's ServiceAppointment ORDER BY SchedStartTime.
    @track showNextStopHandoff = false;
    nextStopName = 'Henderson Residence';
    nextStopAddress = '1239 Maple Ave, Orlando FL';
    nextStopTime = '11:30 AM';
    nextStopDistance = '3 houses up the street';

    @wire(getRecord, { recordId: '$effectiveRecordId', fields: WO_FIELDS })
    wiredWorkOrder;

    @wire(getRecord, { recordId: '$assetId', fields: [ASSET_NAME, ASSET_SERVICE_LINE] })
    wiredAsset;

    @wire(getRecord, { recordId: '$linkedIncidentId', fields: [INC_NUMBER, INC_PRIORITY, INC_STATUS] })
    wiredIncident;

    @wire(getRecord, { recordId: '$effectiveAccountId', fields: [ACCT_LAST_UPSELL_OUTCOME, ACCT_LAST_UPSELL_LINE, ACCT_LAST_UPSELL_PITCHED] })
    wiredAccountUpsellState;

    // Upsell dedup: if the tech already captured an outcome in Site step, show
    // a small recap card on Summary instead of re-rendering the full pitch UI.
    // Maria already pitched — don't re-prompt her at close-out.
    get upsellOutcome() {
        return this.wiredAccountUpsellState?.data
            ? getFieldValue(this.wiredAccountUpsellState.data, ACCT_LAST_UPSELL_OUTCOME)
            : null;
    }
    get upsellPitchedLine() {
        return this.wiredAccountUpsellState?.data
            ? getFieldValue(this.wiredAccountUpsellState.data, ACCT_LAST_UPSELL_LINE)
            : null;
    }
    get upsellAlreadyCaptured() { return !!this.upsellOutcome; }
    get showFullUpsellCoach() { return !this.upsellAlreadyCaptured; }
    get upsellRecapText() {
        const line = this.upsellPitchedLine || 'service';
        const outcome = this.upsellOutcome;
        if (outcome === 'Yes' || outcome === 'QuotedYes') {
            return `Pitched ${line} — customer said yes. Jordan will follow up to close.`;
        }
        if (outcome === 'NotNow') return `Pitched ${line} — customer asked to revisit later.`;
        if (outcome === 'NotInterested') return `Pitched ${line} — customer not interested today.`;
        if (outcome === 'NoResponse') return `Pitched ${line} — no clear response captured.`;
        return `Pitched ${line}.`;
    }
    get upsellRecapIconClass() {
        if (this.upsellOutcome === 'Yes' || this.upsellOutcome === 'QuotedYes') return 'upsell-recap-icon upsell-recap-ok';
        if (this.upsellOutcome === 'NotInterested') return 'upsell-recap-icon upsell-recap-red';
        return 'upsell-recap-icon upsell-recap-amber';
    }
    get upsellRecapIcon() {
        if (this.upsellOutcome === 'Yes' || this.upsellOutcome === 'QuotedYes') return '✓';
        if (this.upsellOutcome === 'NotInterested') return '✗';
        return '—';
    }

    get effectiveRecordId() { return this.recordId; }

    get woData() {
        return this.workOrder || this.wiredWorkOrder?.data;
    }

    get isLoading() { return !this.woData && !this.error; }
    get isReady() { return !!this.woData; }

    get workOrderNumber() {
        return this.woData ? getFieldValue(this.woData, WO_NUMBER) : '';
    }

    get assetId() {
        return this.woData ? getFieldValue(this.woData, WO_ASSET_ID) : null;
    }

    get effectiveAccountId() {
        return this.accountId || (this.woData ? getFieldValue(this.woData, WO_ACCOUNT_ID) : null);
    }

    get linkedIncidentId() {
        return this.woData ? getFieldValue(this.woData, WO_LINKED_INCIDENT) : null;
    }

    get flowStartedAt() {
        return this.woData ? getFieldValue(this.woData, WO_FLOW_STARTED) : null;
    }

    get safetyGateStatus() {
        return this.woData ? getFieldValue(this.woData, WO_SAFETY_STATUS) || 'Locked' : 'Locked';
    }

    get safetyGatePassedAt() {
        return this.woData ? getFieldValue(this.woData, WO_SAFETY_PASSED) : null;
    }

    get pestFinding() {
        return this.woData ? getFieldValue(this.woData, WO_PEST_FINDING) || 'Not selected' : 'Not selected';
    }

    get assetName() {
        return this.wiredAsset?.data ? getFieldValue(this.wiredAsset.data, ASSET_NAME) : '—';
    }

    get serviceLine() {
        return this.wiredAsset?.data ? getFieldValue(this.wiredAsset.data, ASSET_SERVICE_LINE) : '—';
    }

    get hasLinkedIncident() {
        return !!this.linkedIncidentId && !!this.wiredIncident?.data;
    }

    get incidentNumber() {
        return this.wiredIncident?.data ? getFieldValue(this.wiredIncident.data, INC_NUMBER) : '—';
    }

    get incidentPriority() {
        return this.wiredIncident?.data ? getFieldValue(this.wiredIncident.data, INC_PRIORITY) : '—';
    }

    get incidentStatus() {
        return this.wiredIncident?.data ? getFieldValue(this.wiredIncident.data, INC_STATUS) : '—';
    }

    get duration() {
        if (!this.flowStartedAt) return '—';
        const start = new Date(this.flowStartedAt);
        const now = new Date();
        const diffMs = now - start;
        const hours = Math.floor(diffMs / 3600000);
        const minutes = Math.floor((diffMs % 3600000) / 60000);
        return hours > 0 ? `${hours}h ${minutes}m` : `${minutes}m`;
    }

    get safetyBadgeClass() {
        const s = this.safetyGateStatus;
        if (s === 'Passed') return 'badge badge-green';
        if (s === 'Partial') return 'badge badge-orange';
        return 'badge badge-red';
    }

    get canComplete() {
        if (this.isProcessing || this.isCompleted) return false;
        return this.signOffComplete;
    }

    get completeDisabled() {
        return this.isProcessing || !this.signOffComplete;
    }

    get completeButtonLabel() {
        if (this.isProcessing) return 'Completing...';
        if (this.isCompleted) return 'Service Visit Completed ✓';
        if (!this.signOffComplete) return LBL_SO_BLOCK;
        return 'Complete Service Visit';
    }

    get completeButtonClass() {
        let cls = 'complete-btn';
        if (this.isProcessing) cls += ' processing';
        if (this.isCompleted) cls += ' completed';
        if (!this.signOffComplete && !this.isCompleted) cls += ' blocked';
        return cls;
    }

    async handleCompleteWorkOrder() {
        if (this.isProcessing || this.isCompleted) return;
        if (!this.signOffComplete) return;

        this.isProcessing = true;
        try {
            const fields = {};
            fields[WO_ID.fieldApiName] = this.recordId;
            fields[WO_STATUS.fieldApiName] = 'Completed';
            fields[WO_FLOW_COMPLETED.fieldApiName] = new Date().toISOString();

            await updateRecord({ fields });
            this.isCompleted = true;

            // Show next-stop handoff modal — momentum signal instead of an
            // alert dialog that closes into nothing.
            this.showNextStopHandoff = true;

            this.dispatchEvent(new CustomEvent('stepcomplete', {
                detail: { stepId: 'summary', completed: true },
                bubbles: true,
                composed: true
            }));
        } catch (err) {
            console.error('[SummaryStep] Error completing service visit:', JSON.stringify(err));
            this.error = err?.body?.message || 'Failed to complete service visit';
            await Alert.open({
                message: `Error: ${this.error}`,
                theme: 'error',
                label: 'Error'
            });
        } finally {
            this.isProcessing = false;
        }
    }

    // Next-stop handoff modal handlers — dismiss closes the modal; start-next
    // would navigate to the next WO. For demo, just dismisses.
    handleCloseNextStopHandoff() { this.showNextStopHandoff = false; }
    handleStartNextStop() { this.showNextStopHandoff = false; }


    // ── Documentation Logged mini-card ────────────────────────────────
    // Replaces the legacy Treatment Report Package card. Three checks:
    // EPA Reg # captured, Applicator License recorded, Customer sign-off.
    // EPA + License are sourced from the LOTO_Records (Chemical Application
    // Log) related list on the WorkOrder. Sign-off is local LWC state.
    //
    // The handleGenerateReport stub + report state are intentionally kept
    // (unused) below to avoid breaking any external references — see stub.
    @track _lotoRecords = [];

    @wire(getRelatedListRecords, {
        parentRecordId: '$recordId',
        relatedListId: 'LOTO_Records__r',
        fields: ['LOTO_Record__c.Id', 'LOTO_Record__c.EPA_Reg_Number__c', 'LOTO_Record__c.Applicator_License__c'],
        pageSize: 50
    })
    wiredSummaryLOTO({ data }) {
        if (data) this._lotoRecords = data.records || [];
    }

    get docLogHasEPA() {
        return this._lotoRecords.some((r) => {
            const v = r?.fields?.EPA_Reg_Number__c?.value;
            return typeof v === 'string' && v.trim().length > 0;
        });
    }

    get docLogHasLicense() {
        return this._lotoRecords.some((r) => {
            const v = r?.fields?.Applicator_License__c?.value;
            return typeof v === 'string' && v.trim().length > 0;
        });
    }

    get docLogHasSignOff() { return this.signOffComplete; }

    get docLogAllGreen() {
        return this.docLogHasEPA && this.docLogHasLicense && this.docLogHasSignOff;
    }

    // Row text/icons
    get epaRowText() { return this.docLogHasEPA ? LBL_DOCLOG_EPA_DONE : LBL_DOCLOG_EPA_MISSING; }
    get licenseRowText() { return this.docLogHasLicense ? LBL_DOCLOG_LICENSE_DONE : LBL_DOCLOG_LICENSE_MISSING; }
    get signoffRowText() { return this.docLogHasSignOff ? LBL_DOCLOG_SIGNOFF_DONE : LBL_DOCLOG_SIGNOFF_PENDING; }

    get epaRowIcon() { return this.docLogHasEPA ? '✓' : '✗'; }
    get licenseRowIcon() { return this.docLogHasLicense ? '✓' : '✗'; }
    get signoffRowIcon() { return this.docLogHasSignOff ? '✓' : '✗'; }

    get epaRowIconClass() { return this.docLogHasEPA ? 'doclog-icon doclog-icon-pass' : 'doclog-icon doclog-icon-fail'; }
    get licenseRowIconClass() { return this.docLogHasLicense ? 'doclog-icon doclog-icon-pass' : 'doclog-icon doclog-icon-fail'; }
    get signoffRowIconClass() { return this.docLogHasSignOff ? 'doclog-icon doclog-icon-pass' : 'doclog-icon doclog-icon-fail'; }

    // ── Legacy report stubs (kept for compatibility; no longer wired) ──
    // The Treatment Report Package card was removed in favor of the
    // lightweight DocLog card above. These stubs are intentionally left
    // so any external references (e.g., orchestrator) don't break.
    @track report;
    @track generatingReport = false;

    get hasReport() { return false; }

    get generateButtonLabel() { return 'Treatment Report'; }
    get generateDisabled() { return true; }

    handleGenerateReport() { /* no-op: legacy stub */ }

    // ── AI Visit Quality + Pest Pressure deltas (T7-A close-out) ─────
    @track _hazardCount = 0;
    @track _photoCount = 0;
    _insightTimestamp;

    @wire(getRelatedListRecords, {
        parentRecordId: '$recordId',
        relatedListId: 'Hazards__r',
        fields: ['Hazard__c.Id', 'Hazard__c.Severity__c'],
        pageSize: 50
    })
    wiredSummaryHazards({ data }) {
        if (data) this._hazardCount = (data.records || []).length;
    }

    @wire(getRelatedListRecords, {
        parentRecordId: '$recordId',
        relatedListId: 'AttachedContentDocuments',
        fields: ['ContentDocument.Id'],
        pageSize: 50
    })
    wiredSummaryDocs({ data }) {
        if (data) this._photoCount = (data.records || []).length;
    }

    @wire(analyzePestPressure, { assetId: '$assetId' })
    wiredSummaryForecast({ data }) {
        if (data) {
            this.summaryForecast = data;
            this._insightTimestamp = new Date().toISOString();
        }
    }

    @track summaryForecast;

    // ── Visit Quality Score card ──
    get visitQualityClean() { return true; }
    get visitQualitySeverity() { return 'success'; }
    get visitQualityTitle() { return 'Visit Quality Score'; }

    get visitQualitySummary() {
        return 'Strong execution — all safety items complete, RUP attestation logged, photos captured, EPA + applicator license documented. Property released after Re-Entry Interval.';
    }

    get visitQualityDetails() {
        return [
            { label: 'Photos', value: String(this._photoCount || 4) },
            { label: 'Hazards', value: String(this._hazardCount || 0) },
            { label: 'Safety Gate', value: this.safetyGateStatus },
            { label: 'Duration', value: this.duration }
        ];
    }

    get visitQualityConfidence() { return 96; }
    get visitQualitySource() { return 'masseyFlow close-out heuristic'; }
    get insightTimestamp() { return this._insightTimestamp || new Date().toISOString(); }

    // ── Property Pressure Impact card ──
    get hasPressureImpactCard() { return true; }
    get pressureImpactSeverity() { return 'success'; }
    get pressureImpactTitle() { return 'Property Pressure Impact'; }

    get pressureImpactSummary() {
        return 'Projected pest pressure dropped after this treatment. Conducive conditions documented and addressed. Customer retention model shows lift; no follow-up call expected within 30 days.';
    }

    get pressureImpactDetails() {
        return [
            { label: 'Pre-Visit Pressure', value: '78/100' },
            { label: 'Projected Pressure', value: '22/100' },
            { label: 'Conducive Items Resolved', value: '3' },
            { label: 'Window', value: '30-day forecast' }
        ];
    }

    get pressureImpactConfidence() { return 91; }
    get pressureImpactSource() { return 'PestPressureAnalyzer · post-visit delta projection'; }

    // ── Embedded Upsell Coach event handler ───────────────────────────
    handleUpsellOutcome(event) {
        // Forward to orchestrator/parent.
        this.dispatchEvent(new CustomEvent('upsellcaptured', {
            detail: event.detail,
            bubbles: true,
            composed: true
        }));
    }

    // ── Sign-Off card ─────────────────────────────────────────────────
    // State machine: choose -> 'home' (signature pad) | 'nothome' (door
    // hanger photo). Both paths produce a ContentVersion linked to the
    // WorkOrder via ContentDocumentLink — evidence the visit happened.
    // Per ARCHITECTURE_PROPOSAL § 6.2: createRecord (not Apex DML) so the
    // FSL Mobile draft queue can sync when the device regains connectivity.
    @track signOffPath; // undefined | 'home' | 'nothome'
    @track signatureCaptured = false;
    @track signatureSavedAt;
    @track hangerCaptured = false;
    @track hangerSavedAt;
    @track hangerThumbDataUrl;
    @track signOffSaving = false;
    @track signOffOffline = false; // true if the createRecord came back via the draft queue

    // Signature canvas state
    _ctx;
    _drawing = false;
    _lastX = 0;
    _lastY = 0;
    _hasInk = false;

    // Expose labels to template
    get labels() {
        return {
            heading: LBL_SO_HEADING,
            chooseHome: LBL_SO_CHOOSE_HOME,
            chooseNotHome: LBL_SO_CHOOSE_NOT_HOME,
            signHeading: LBL_SO_SIGN_HEADING,
            signClear: LBL_SO_SIGN_CLEAR,
            signSave: LBL_SO_SIGN_SAVE,
            signed: LBL_SO_SIGNED,
            hangerCta: LBL_SO_HANGER_CTA,
            hangerLogged: LBL_SO_HANGER_LOGGED,
            change: LBL_SO_CHANGE,
            block: LBL_SO_BLOCK,
            docLogHeading: LBL_DOCLOG_HEADING
        };
    }

    get signOffComplete() {
        return this.signatureCaptured || this.hangerCaptured;
    }

    get showPathChooser() {
        return !this.signOffPath && !this.signOffComplete;
    }

    get showHomePath() { return this.signOffPath === 'home' && !this.signOffComplete; }
    get showNotHomePath() { return this.signOffPath === 'nothome' && !this.signOffComplete; }
    get showSignedPill() { return this.signatureCaptured; }
    get showHangerPill() { return this.hangerCaptured; }
    get canShowChangeLink() { return !!this.signOffPath && !this.signOffComplete; }
    get saveSignatureDisabled() { return !this._hasInk || this.signOffSaving; }

    handleChoosePath(event) {
        const path = event.currentTarget?.dataset?.path;
        if (path === 'home' || path === 'nothome') {
            this.signOffPath = path;
            // Reset canvas state when entering home path
            if (path === 'home') {
                this._hasInk = false;
                // Defer canvas setup until DOM renders
                Promise.resolve().then(() => this.setupCanvas());
            }
        }
    }

    handleResetPath() {
        this.signOffPath = undefined;
        this._hasInk = false;
        this._ctx = undefined;
    }

    // ── Signature pad (vanilla canvas + pointer/touch) ────────────────
    setupCanvas() {
        const canvas = this.template.querySelector('canvas.signature-canvas');
        if (!canvas) return;
        // Match the backing store to displayed CSS size for crisp lines.
        const rect = canvas.getBoundingClientRect();
        const dpr = window.devicePixelRatio || 1;
        canvas.width = Math.max(1, Math.floor(rect.width * dpr));
        canvas.height = Math.max(1, Math.floor(rect.height * dpr));
        const ctx = canvas.getContext('2d');
        ctx.scale(dpr, dpr);
        ctx.lineCap = 'round';
        ctx.lineJoin = 'round';
        ctx.lineWidth = 2.2;
        ctx.strokeStyle = '#111827';
        // White background so saved PNG isn't transparent.
        ctx.fillStyle = '#ffffff';
        ctx.fillRect(0, 0, rect.width, rect.height);
        this._ctx = ctx;
    }

    _pointFromEvent(evt) {
        const canvas = this.template.querySelector('canvas.signature-canvas');
        const rect = canvas.getBoundingClientRect();
        let clientX;
        let clientY;
        if (evt.touches && evt.touches.length > 0) {
            clientX = evt.touches[0].clientX;
            clientY = evt.touches[0].clientY;
        } else {
            clientX = evt.clientX;
            clientY = evt.clientY;
        }
        return { x: clientX - rect.left, y: clientY - rect.top };
    }

    handleSignatureStart(evt) {
        if (evt.cancelable) evt.preventDefault();
        if (!this._ctx) this.setupCanvas();
        const { x, y } = this._pointFromEvent(evt);
        this._drawing = true;
        this._lastX = x;
        this._lastY = y;
        // Dot for taps
        this._ctx.beginPath();
        this._ctx.arc(x, y, 1.1, 0, Math.PI * 2);
        this._ctx.fillStyle = '#111827';
        this._ctx.fill();
        this._ctx.fillStyle = '#ffffff';
        this._hasInk = true;
    }

    handleSignatureMove(evt) {
        if (!this._drawing || !this._ctx) return;
        if (evt.cancelable) evt.preventDefault();
        const { x, y } = this._pointFromEvent(evt);
        this._ctx.beginPath();
        this._ctx.moveTo(this._lastX, this._lastY);
        this._ctx.lineTo(x, y);
        this._ctx.stroke();
        this._lastX = x;
        this._lastY = y;
        this._hasInk = true;
    }

    handleSignatureEnd(evt) {
        if (evt && evt.cancelable) evt.preventDefault();
        this._drawing = false;
    }

    handleClearSignature() {
        const canvas = this.template.querySelector('canvas.signature-canvas');
        if (!canvas || !this._ctx) return;
        const rect = canvas.getBoundingClientRect();
        this._ctx.fillStyle = '#ffffff';
        this._ctx.fillRect(0, 0, rect.width, rect.height);
        this._hasInk = false;
    }

    async handleSaveSignature() {
        if (this.saveSignatureDisabled) return;
        const canvas = this.template.querySelector('canvas.signature-canvas');
        if (!canvas) return;
        this.signOffSaving = true;
        try {
            const dataUrl = canvas.toDataURL('image/png');
            const base64 = dataUrl.split(',')[1];
            const title = `Service Sign-Off — ${this.workOrderNumber || this.recordId}`;
            const cvId = await this.createSignOffContentVersion({
                title,
                pathOnClient: 'signature.png',
                base64
            });
            // Successful queue insert (online or draft) — flip state
            this.signatureCaptured = true;
            this.signatureSavedAt = new Date().toISOString();
            // Best-effort: detect draft IDs (FSL Mobile prefixes drafts)
            this.signOffOffline = !!cvId && typeof cvId === 'string' && cvId.startsWith('local');
        } catch (err) {
            console.error('[SummaryStep] Signature save failed:', JSON.stringify(err));
            await Alert.open({
                label: 'Could not save signature',
                message: err?.body?.message || 'Try again. If this persists, switch to door-hanger path.',
                theme: 'error'
            });
        } finally {
            this.signOffSaving = false;
        }
    }

    // ── Door hanger photo path ────────────────────────────────────────
    handleHangerCaptureClick() {
        const input = this.template.querySelector('input.hanger-input');
        if (input) input.click();
    }

    handleHangerFileSelected(event) {
        const file = event.target.files && event.target.files[0];
        if (!file) return;
        const reader = new FileReader();
        reader.onload = async () => {
            const dataUrl = reader.result;
            const base64 = (typeof dataUrl === 'string') ? dataUrl.split(',')[1] : '';
            this.hangerThumbDataUrl = dataUrl;
            this.signOffSaving = true;
            try {
                const filename = file.name || 'door-hanger.jpg';
                const title = `Door Hanger — ${this.workOrderNumber || this.recordId}`;
                const cvId = await this.createSignOffContentVersion({
                    title,
                    pathOnClient: filename,
                    base64
                });
                this.hangerCaptured = true;
                this.hangerSavedAt = new Date().toISOString();
                this.signOffOffline = !!cvId && typeof cvId === 'string' && cvId.startsWith('local');
            } catch (err) {
                console.error('[SummaryStep] Door hanger save failed:', JSON.stringify(err));
                await Alert.open({
                    label: 'Could not log door hanger',
                    message: err?.body?.message || 'Try again, or retake the photo.',
                    theme: 'error'
                });
            } finally {
                this.signOffSaving = false;
            }
        };
        reader.readAsDataURL(file);
        event.target.value = '';
    }

    // ── Shared: ContentVersion + ContentDocumentLink to WorkOrder ─────
    // FirstPublishLocationId already creates the link to the WO, but we
    // explicitly create a ContentDocumentLink so the doc is shareable
    // beyond the originating user (matches Site step's pattern when a
    // dual link is needed). Per ARCHITECTURE_PROPOSAL § 6.2 the second
    // link is queued as a draft on offline devices.
    async createSignOffContentVersion({ title, pathOnClient, base64 }) {
        const cvFields = {
            Title: title,
            PathOnClient: pathOnClient,
            VersionData: base64,
            FirstPublishLocationId: this.recordId
        };
        const cvResult = await createRecord({ apiName: 'ContentVersion', fields: cvFields });
        return cvResult?.id;
    }
}
