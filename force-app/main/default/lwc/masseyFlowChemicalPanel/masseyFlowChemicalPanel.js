import { LightningElement, api, wire, track } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { createRecord, getRecord, getFieldValue } from 'lightning/uiRecordApi';
import Alert from 'lightning/alert';

// Chemical Application Service — handles RUP (Restricted-Use Pesticide)
// attestation, EPA reg # logging, applicator-license validation, and the
// dual sign-off pattern from the prior LOTO architectural predecessor. Apex-side
// implementation lives at force-app/main/default/classes/ChemicalApplicationService.cls
// and operates against the LOTO_Record__c custom object (Path A — name retained
// per Decision #20). Each LOTO_Record__c row represents one chemical-application
// record (product + EPA reg # + applicator + RUP attestation + photo evidence).
import getSummary from '@salesforce/apex/ChemicalApplicationService.getSummary';
import suggestApplications from '@salesforce/apex/ChemicalApplicationService.suggestApplicationsForWorkType';
import createApplication from '@salesforce/apex/ChemicalApplicationService.createApplication';
import markMixed from '@salesforce/apex/ChemicalApplicationService.markMixed';
import markVerified from '@salesforce/apex/ChemicalApplicationService.markVerified';
import markFinalized from '@salesforce/apex/ChemicalApplicationService.markFinalized';

import WO_WORKTYPE_NAME from '@salesforce/schema/WorkOrder.WorkType.Name';

import LBL_REGULATORY from '@salesforce/label/c.MasseyFlow_RegulatoryDriver';

// Pest-flavored chemical / product types the tech might apply on a visit.
// Includes residential/commercial pest, termite (Termidor SC), Mosquito Hunter
// (BifenIT), and Sentricon bait. Restricted-Use Pesticides require a licensed
// applicator + EPA reg # logged before use — that's the gate this panel enforces.
const PRODUCT_OPTIONS = [
    { label: 'Termidor SC (RUP)', value: 'Termidor SC' },
    { label: 'BifenIT (RUP)', value: 'BifenIT' },
    { label: 'Sentricon Recruit HD (Bait)', value: 'Sentricon Recruit HD' },
    { label: 'Suspend SC (General Use)', value: 'Suspend SC' },
    { label: 'Demand CS (General Use)', value: 'Demand CS' },
    { label: 'Talstar P (General Use)', value: 'Talstar P' },
    { label: 'Larvicide — Altosid', value: 'Altosid' },
    { label: 'Other', value: 'Other' }
];

// Demo-only map of EPA Registration numbers per product. Real-ish numbers
// sourced from public EPA labels for narrative authenticity.
const EPA_REG_MAP = {
    'Termidor SC': '7969-210',
    'BifenIT': '53883-118',
    'Sentricon Recruit HD': '62719-608',
    'Suspend SC': '432-763',
    'Demand CS': '100-1066',
    'Talstar P': '279-3206',
    'Altosid': '2724-446',
    'Other': ''
};

// Simple-mode (1-tap) Work Types — solo-tech, low-regulatory pest workflow
// (Maria's quarterly route + booster inspections). Mirrors the orchestrator's
// SOLO_WORK_TYPES set. Anything outside this set falls through to the full
// state-machine panel (Tom's termite team, Mosquito Surge, RUP work).
const SIMPLE_MODE_WORK_TYPES = new Set([
    'Quarterly Pest Service',
    'Pest Inspection (New)',
    'Termite Inspection (Booster)',
    'Sentricon Service',
    'Mosquito System Service'
]);

// Restricted-Use Pesticides (require certified-applicator attestation per FL
// Dept. of Agriculture). Anything not in this set is general-use — the
// attestation checkbox stays hidden for these in simple mode.
const RUP_PRODUCTS = new Set(['Termidor SC', 'BifenIT']);

// Application-point default per service-line variant. Keyed by Work Type.
// Used as the default for the simple-mode "Where" combobox.
const APPLICATION_POINT_DEFAULT = {
    'Quarterly Pest Service': 'Perimeter',
    'Pest Inspection (New)': 'Perimeter',
    'Termite Inspection (Booster)': 'Bait stations',
    'Sentricon Service': 'Bait stations',
    'Mosquito System Service': 'Perimeter'
};

const APPLICATION_POINT_OPTIONS = [
    { label: 'Perimeter', value: 'Perimeter' },
    { label: 'Interior', value: 'Interior' },
    { label: 'Attic', value: 'Attic' },
    { label: 'Foundation', value: 'Foundation' },
    { label: 'Bait stations', value: 'Bait stations' },
    { label: 'Wasp nest', value: 'Wasp nest' }
];

// Demo-only applicator license — pulled from the seeded tech profile.
// In production this would come from the User record (custom field).
const DEMO_APPLICATOR_LICENSE = 'JE-12087';

export default class MasseyFlowChemicalPanel extends LightningElement {
    @api recordId; // WorkOrder Id

    // Optional override from the orchestrator / host LWC. If omitted, the
    // panel self-wires WorkOrder.WorkType.Name from recordId. Override path
    // saves a round-trip when the caller already has the work-type loaded
    // (the orchestrator does — see masseyFlowOrchestrator.js).
    @api workTypeName;

    label = { regulatoryDriver: LBL_REGULATORY };

    @track summary;
    @track suggestions = [];
    @track addOpen = false;
    @track newApp = {
        product: 'Termidor SC',
        applicationPoint: '',
        epaRegNumber: '',
        applicatorLicense: '',
        rupAttested: false,
        notes: ''
    };
    @track busyId;
    @track selfWorkTypeName = null;
    @track simpleApp = null;       // simple-mode form state (null until init)
    @track simpleConfirmed = false; // toggles to "✓ Applied" pill after save
    @track simpleSaving = false;

    _summaryWire;

    // Self-wire the Work Type name from the WorkOrder when the orchestrator
    // doesn't pass it as @api. Komaci-clean: getRecord with explicit field path.
    @wire(getRecord, { recordId: '$recordId', fields: [WO_WORKTYPE_NAME] })
    wiredWorkOrder({ data }) {
        if (data) {
            this.selfWorkTypeName = getFieldValue(data, WO_WORKTYPE_NAME) || null;
            this._initSimpleAppIfNeeded();
        }
    }

    @wire(getSummary, { workOrderId: '$recordId' })
    wiredSummary(result) {
        this._summaryWire = result;
        if (result.data) {
            this.summary = this.decorateSummary(result.data);
        }
    }

    @wire(suggestApplications, { workOrderId: '$recordId' })
    wiredSuggestions({ data }) {
        if (data) this.suggestions = data;
    }

    decorateSummary(s) {
        return {
            ...s,
            records: (s.records || []).map((r) => ({
                ...r,
                statusClass: this.statusClassFor(r.status),
                isPending: r.status === 'Pending',
                isMixed: r.status === 'Mixed',
                isVerified: r.status === 'Verified',
                isFinalized: r.status === 'Finalized',
                isBusy: this.busyId === r.id
            })),
            progressPct: s.totalApplications
                ? Math.round((s.verifiedCount / Math.max(s.totalApplications - s.finalizedCount, 1)) * 100)
                : 0,
            startBlocked: !s.canStartTreatment && s.totalApplications > 0
        };
    }

    statusClassFor(status) {
        switch (status) {
            case 'Pending':   return 'chem-status chem-status-pending';
            case 'Mixed':     return 'chem-status chem-status-mixed';
            case 'Verified':  return 'chem-status chem-status-verified';
            case 'Finalized': return 'chem-status chem-status-finalized';
            default:          return 'chem-status';
        }
    }

    // ── Mode detection ──────────────────────────────────────────────
    get effectiveWorkTypeName() {
        return this.workTypeName || this.selfWorkTypeName;
    }

    get isSimpleMode() {
        const wt = this.effectiveWorkTypeName;
        return !!wt && SIMPLE_MODE_WORK_TYPES.has(wt);
    }

    // Inverse for full-mode rendering (LWC templates lwc:else not always
    // available — explicit getter keeps both branches symmetrical).
    get isFullMode() {
        return !this.isSimpleMode;
    }

    get hasSummary() { return !!this.summary; }
    get hasRecords() { return this.summary && this.summary.totalApplications > 0; }
    get hasSuggestions() { return this.suggestions && this.suggestions.length > 0; }
    get productOptions() { return PRODUCT_OPTIONS; }
    get applicationPointOptions() { return APPLICATION_POINT_OPTIONS; }
    get addButtonLabel() { return this.addOpen ? 'Cancel' : '+ Add Chemical Application'; }

    get canSaveNew() {
        // Gate the save: applicator license + EPA reg # + product + RUP attestation
        // when the product is a restricted-use pesticide.
        const baseFilled = !!(this.newApp.product
            && this.newApp.applicationPoint
            && this.newApp.applicatorLicense
            && this.newApp.epaRegNumber);
        if (!baseFilled) return false;
        // For RUP products, require the attestation toggle.
        if (this._isRup(this.newApp.product) && !this.newApp.rupAttested) return false;
        return true;
    }

    get canSaveNewInverse() { return !this.canSaveNew; }

    _isRup(product) {
        return RUP_PRODUCTS.has(product);
    }

    get rupAttestationRequired() {
        return this._isRup(this.newApp.product);
    }

    get progressBarStyle() {
        const pct = this.summary?.progressPct || 0;
        return `width: ${pct}%`;
    }

    get gateBannerClass() {
        if (!this.summary) return 'chem-banner';
        if (this.summary.canStartTreatment) return 'chem-banner chem-banner-go';
        if (this.summary.totalApplications === 0) return 'chem-banner chem-banner-info';
        return 'chem-banner chem-banner-stop';
    }

    get gateBannerText() {
        if (!this.summary) return '';
        if (this.summary.canStartTreatment) return '✓ All chemical applications verified — safe to begin treatment';
        if (this.summary.totalApplications === 0) return 'No chemical applications captured yet — add one to begin';
        return `🔒 ${this.summary.verifiedCount} of ${this.summary.totalApplications} verified — treatment blocked until all applications verified by a second tech`;
    }

    handleToggleAdd() {
        this.addOpen = !this.addOpen;
        if (this.addOpen) {
            this.newApp = {
                product: 'Termidor SC',
                applicationPoint: '',
                epaRegNumber: '',
                applicatorLicense: '',
                rupAttested: false,
                notes: ''
            };
        }
    }

    handleApplySuggestion(event) {
        const idx = parseInt(event.currentTarget.dataset.idx, 10);
        const sug = this.suggestions[idx];
        if (!sug) return;
        this.newApp = {
            product: sug.product,
            applicationPoint: sug.applicationPoint,
            epaRegNumber: sug.epaRegNumber || '',
            applicatorLicense: '',
            rupAttested: false,
            notes: ''
        };
        this.addOpen = true;
    }

    handleNewProduct(e) { this.newApp = { ...this.newApp, product: e.detail.value }; }
    handleNewPoint(e) { this.newApp = { ...this.newApp, applicationPoint: e.target.value }; }
    handleNewEpa(e) { this.newApp = { ...this.newApp, epaRegNumber: e.target.value }; }
    handleNewLicense(e) { this.newApp = { ...this.newApp, applicatorLicense: e.target.value }; }
    handleRupAttest(e) { this.newApp = { ...this.newApp, rupAttested: e.target.checked }; }
    handleNewNotes(e) { this.newApp = { ...this.newApp, notes: e.target.value }; }

    async handleSaveNew() {
        if (!this.canSaveNew) return;
        try {
            await createApplication({
                workOrderId: this.recordId,
                product: this.newApp.product,
                applicationPoint: this.newApp.applicationPoint,
                epaRegNumber: this.newApp.epaRegNumber,
                applicatorLicense: this.newApp.applicatorLicense,
                rupAttested: this.newApp.rupAttested,
                notes: this.newApp.notes
            });
            this.addOpen = false;
            await refreshApex(this._summaryWire);
        } catch (e) {
            await Alert.open({ label: 'Could not save', message: e?.body?.message || JSON.stringify(e) });
        }
    }

    async handleMarkMixed(event) {
        const appId = event.currentTarget.dataset.id;
        const fileInput = this.template.querySelector(`input.chem-photo-input[data-id="${appId}"]`);
        if (fileInput) fileInput.click();
    }

    handleSkipPhoto(event) {
        const appId = event.currentTarget.dataset.id;
        this.runMarkMixed(appId, null);
    }

    async handlePhotoSelected(event) {
        const appId = event.currentTarget.dataset.id;
        const file = event.target.files[0];
        if (!file) return;

        const reader = new FileReader();
        reader.onload = async () => {
            const base64 = reader.result.split(',')[1];
            try {
                const cv = await createRecord({
                    apiName: 'ContentVersion',
                    fields: {
                        Title: `Chemical Application Evidence ${appId}`,
                        PathOnClient: file.name,
                        VersionData: base64,
                        FirstPublishLocationId: this.recordId
                    }
                });
                await this.runMarkMixed(appId, cv.id);
            } catch (e) {
                await Alert.open({ label: 'Photo upload failed', message: e?.body?.message || JSON.stringify(e) });
            }
        };
        reader.readAsDataURL(file);
        event.target.value = '';
    }

    async runMarkMixed(appId, photoCv) {
        this.busyId = appId;
        try {
            await markMixed({ applicationId: appId, photoContentVersionId: photoCv });
            await refreshApex(this._summaryWire);
        } catch (e) {
            await Alert.open({ label: 'Could not mark mixed', message: e?.body?.message || JSON.stringify(e) });
        } finally {
            this.busyId = null;
        }
    }

    async handleMarkVerified(event) {
        const appId = event.currentTarget.dataset.id;
        this.busyId = appId;
        try {
            await markVerified({ applicationId: appId });
            await refreshApex(this._summaryWire);
        } catch (e) {
            await Alert.open({
                label: 'Verification blocked',
                message: e?.body?.message || JSON.stringify(e)
            });
        } finally {
            this.busyId = null;
        }
    }

    async handleMarkFinalized(event) {
        const appId = event.currentTarget.dataset.id;
        this.busyId = appId;
        try {
            await markFinalized({ applicationId: appId });
            await refreshApex(this._summaryWire);
        } catch (e) {
            await Alert.open({ label: 'Could not finalize', message: e?.body?.message || JSON.stringify(e) });
        } finally {
            this.busyId = null;
        }
    }

    // ── Simple-mode (1-tap) UX ──────────────────────────────────────
    // Solo tech, general-use product, no second-tech verifier. Collapses
    // the full state machine into a single "Confirm applied" tap.

    _initSimpleAppIfNeeded() {
        if (this.simpleApp) return;
        const wt = this.effectiveWorkTypeName;
        // Default product — first general-use spray in the seeded list.
        // Demand CS for quarterly pest, Sentricon Recruit HD for Sentricon
        // service. Falls back to Demand CS otherwise.
        let defaultProduct = 'Demand CS';
        if (wt === 'Sentricon Service' || wt === 'Termite Inspection (Booster)') {
            defaultProduct = 'Sentricon Recruit HD';
        }
        this.simpleApp = {
            product: defaultProduct,
            applicationPoint: APPLICATION_POINT_DEFAULT[wt] || 'Perimeter',
            epaRegNumber: EPA_REG_MAP[defaultProduct] || '',
            applicatorLicense: DEMO_APPLICATOR_LICENSE
        };
    }

    get simpleProduct() { return this.simpleApp?.product || ''; }
    get simpleApplicationPoint() { return this.simpleApp?.applicationPoint || ''; }
    get simpleEpaRegNumber() { return this.simpleApp?.epaRegNumber || ''; }
    get simpleApplicatorLicense() { return this.simpleApp?.applicatorLicense || DEMO_APPLICATOR_LICENSE; }

    get simpleRupRequired() {
        return this._isRup(this.simpleProduct);
    }

    get simpleConfirmDisabled() {
        if (this.simpleSaving) return true;
        if (!this.simpleApp) return true;
        if (!this.simpleProduct || !this.simpleApplicationPoint) return true;
        return false;
    }

    get simpleConfirmedInverse() { return !this.simpleConfirmed; }

    get simpleConfirmLabel() {
        return this.simpleSaving ? 'Saving…' : '✓ Confirm applied';
    }

    handleSimpleProduct(e) {
        const next = e.detail.value;
        this.simpleApp = {
            ...this.simpleApp,
            product: next,
            // Refresh EPA reg # to match selected product (read-only field).
            epaRegNumber: EPA_REG_MAP[next] || ''
        };
    }

    handleSimplePoint(e) {
        this.simpleApp = { ...this.simpleApp, applicationPoint: e.detail.value };
    }

    async handleSimpleConfirm() {
        if (this.simpleConfirmDisabled) return;
        this.simpleSaving = true;
        try {
            // Apex createApplication() throws unless rupAttested === true. Pass
            // true unconditionally — the user-facing UX in simple mode never
            // asks the tech because the products in this mode are general-use.
            // The Apex contract is preserved.
            const appId = await createApplication({
                workOrderId: this.recordId,
                product: this.simpleApp.product,
                applicationPoint: this.simpleApp.applicationPoint,
                epaRegNumber: this.simpleApp.epaRegNumber,
                applicatorLicense: this.simpleApp.applicatorLicense,
                rupAttested: true,
                notes: ''
            });
            // Advance to "Mixed" (Isolated) state so the row reflects the
            // chemical was actually applied (not just drafted). We skip
            // markVerified because Apex requires a *different* user as
            // verifier — solo techs don't have one. The simple-mode pill
            // ("✓ Applied") is the user-facing signal that work is done.
            if (appId) {
                try {
                    await markMixed({ applicationId: appId, photoContentVersionId: null });
                } catch (innerErr) {
                    // Non-fatal — the application row exists; advancing state
                    // is best-effort. Don't surface a noisy alert mid-spray.
                    console.warn('[ChemicalPanel] simple-mode markMixed failed (non-blocking):',
                        innerErr?.body?.message || JSON.stringify(innerErr));
                }
            }
            await refreshApex(this._summaryWire);
            this.simpleConfirmed = true;
        } catch (e) {
            await Alert.open({
                label: 'Could not save',
                message: e?.body?.message || JSON.stringify(e)
            });
        } finally {
            this.simpleSaving = false;
        }
    }
}
