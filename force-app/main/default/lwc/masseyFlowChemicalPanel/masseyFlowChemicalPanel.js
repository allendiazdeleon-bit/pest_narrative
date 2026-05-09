import { LightningElement, api, wire, track } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { createRecord } from 'lightning/uiRecordApi';
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
    { label: 'Demand CS (RUP)', value: 'Demand CS' },
    { label: 'Talstar P (General Use)', value: 'Talstar P' },
    { label: 'Larvicide — Altosid', value: 'Altosid' },
    { label: 'Other', value: 'Other' }
];

export default class MasseyFlowChemicalPanel extends LightningElement {
    @api recordId; // WorkOrder Id

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

    _summaryWire;

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

    get hasSummary() { return !!this.summary; }
    get hasRecords() { return this.summary && this.summary.totalApplications > 0; }
    get hasSuggestions() { return this.suggestions && this.suggestions.length > 0; }
    get productOptions() { return PRODUCT_OPTIONS; }
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
        return ['Termidor SC', 'BifenIT', 'Demand CS'].includes(product);
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
}
