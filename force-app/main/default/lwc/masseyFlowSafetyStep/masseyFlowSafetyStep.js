import { LightningElement, api, track, wire } from 'lwc';
import { updateRecord, createRecord } from 'lightning/uiRecordApi';
import { getRelatedListRecords } from 'lightning/uiRelatedListApi';
import briefForWorkOrder from '@salesforce/apex/RiskBriefingService.briefForWorkOrder';
import WS_ID from '@salesforce/schema/WorkStep.Id';
import WS_COMPLETED_AT from '@salesforce/schema/WorkStep.Completed_At__c';
import HAZARD_OBJECT from '@salesforce/schema/Hazard__c';
import HAZARD_DESCRIPTION from '@salesforce/schema/Hazard__c.Description__c';
import HAZARD_SEVERITY from '@salesforce/schema/Hazard__c.Severity__c';
import HAZARD_STATUS from '@salesforce/schema/Hazard__c.Status__c';
import HAZARD_REPORTED_AT from '@salesforce/schema/Hazard__c.Reported_At__c';
import HAZARD_REPORTED_BY from '@salesforce/schema/Hazard__c.Reported_By__c';
import HAZARD_WORK_ORDER from '@salesforce/schema/Hazard__c.Work_Order__c';
import userId from '@salesforce/user/Id';

import LBL_SAFETY_GATE_HEADER from '@salesforce/label/c.MasseyFlow_SafetyGate_Header';

// getRelatedListRecords requires string field references, NOT schema tokens
const WORKSTEP_FIELDS = [
    'WorkStep.Id', 'WorkStep.Name', 'WorkStep.Description',
    'WorkStep.Step_Category__c', 'WorkStep.Is_Critical__c',
    'WorkStep.Completed_At__c', 'WorkStep.Completed_By__c',
    'WorkStep.Sort_Order__c', 'WorkStep.Status'
];

const HAZARD_FIELDS = [
    'Hazard__c.Id', 'Hazard__c.Name', 'Hazard__c.Description__c',
    'Hazard__c.Severity__c', 'Hazard__c.Status__c',
    'Hazard__c.Reported_At__c', 'Hazard__c.Reported_By__c'
];

export default class MasseyFlowSafetyStep extends LightningElement {

    @api recordId;
    @api workOrder;

    label = {
        safetyGateHeader: LBL_SAFETY_GATE_HEADER
    };

    // Orchestrator can pass workSteps/workPlanId; otherwise component self-wires
    _externalWorkSteps = [];
    _selfWiredWorkSteps = [];
    @track selfWorkPlanId = null;

    @api
    get workSteps() {
        return this._externalWorkSteps.length > 0
            ? this._externalWorkSteps
            : this._selfWiredWorkSteps;
    }
    set workSteps(value) { this._externalWorkSteps = value || []; }

    @api
    get workPlanId() {
        return this.selfWorkPlanId;
    }
    set workPlanId(value) { this.selfWorkPlanId = value; }

    @track hazardText = '';
    @track hazardSeverity = 'Medium';
    @track localChecks = {};
    @track localNAs = {};
    @track localHazards = [];
    _wiredHazardRecords = [];

    // Self-wire: WorkOrder → WorkPlans → first WorkPlan ID
    @wire(getRelatedListRecords, {
        parentRecordId: '$recordId',
        relatedListId: 'WorkPlans',
        fields: ['WorkPlan.Id']
    })
    wiredWorkPlans({ data, error }) {
        if (data && data.records && data.records.length > 0) {
            this.selfWorkPlanId = data.records[0].fields.Id?.value || data.records[0].id;
        } else if (error) {
            console.error('[SafetyStep] Error loading WorkPlans:', JSON.stringify(error));
        }
    }

    @wire(getRelatedListRecords, {
        parentRecordId: '$selfWorkPlanId',
        relatedListId: 'WorkSteps',
        fields: WORKSTEP_FIELDS,
        pageSize: 50
    })
    wiredWorkSteps({ data, error }) {
        if (data && this._externalWorkSteps.length === 0) {
            this._selfWiredWorkSteps = (data.records || []).map(r => this._flattenRecord(r));
        } else if (error) {
            console.error('[SafetyStep] Error loading WorkSteps:', JSON.stringify(error));
        }
    }

    @wire(getRelatedListRecords, {
        parentRecordId: '$recordId',
        relatedListId: 'Hazards__r',
        fields: HAZARD_FIELDS,
        pageSize: 50
    })
    wiredHazards({ data, error }) {
        if (data) {
            this._wiredHazardRecords = (data.records || []).map(r => this._flattenHazardRecord(r));
        } else if (error) {
            console.error('[SafetyStep] Error loading Hazards:', JSON.stringify(error));
        }
    }

    get criticalSteps() {
        return this.workSteps
            .filter((step) => step.Step_Category__c === 'Safety_Critical')
            .sort((a, b) => (a.Sort_Order__c || 0) - (b.Sort_Order__c || 0))
            .map((step) => this._mapStepToItem(step));
    }

    get siteSteps() {
        return this.workSteps
            .filter((step) => step.Step_Category__c === 'Safety_Site')
            .sort((a, b) => (a.Sort_Order__c || 0) - (b.Sort_Order__c || 0))
            .map((step) => this._mapStepToItem(step));
    }

    get adminSteps() {
        return this.workSteps
            .filter((step) => step.Step_Category__c === 'Safety_Admin')
            .sort((a, b) => (a.Sort_Order__c || 0) - (b.Sort_Order__c || 0))
            .map((step) => this._mapStepToItem(step));
    }

    get hazardSteps() {
        const wiredIds = new Set(this._wiredHazardRecords.map(h => h.Id));
        const localOnly = this.localHazards.filter(h => !wiredIds.has(h.Id));
        return [...this._wiredHazardRecords, ...localOnly].map(h => ({
            id: h.Id,
            name: h.Name,
            description: h.Description__c,
            severity: h.Severity__c,
            severityClass: this._severityClass(h.Severity__c),
            severityLabel: h.Severity__c
        }));
    }

    get allCriticalComplete() {
        return this.criticalSteps.every((step) => step.isResolved);
    }

    get allComplete() {
        const safetySteps = [...this.criticalSteps, ...this.siteSteps, ...this.adminSteps];
        return safetySteps.every((step) => step.isResolved);
    }

    get completedCount() {
        const safetySteps = [...this.criticalSteps, ...this.siteSteps, ...this.adminSteps];
        return safetySteps.filter((step) => step.isResolved).length;
    }

    @api
    get hasCriticalIncomplete() {
        const allItems = [...this.criticalSteps, ...this.siteSteps, ...this.adminSteps];
        return allItems.some(item => item.isCritical && !item.isResolved);
    }

    get totalCount() {
        return this.criticalSteps.length + this.siteSteps.length + this.adminSteps.length;
    }

    get gateStatus() {
        if (this.allComplete) return 'Passed';
        if (this.allCriticalComplete) return 'Partial';
        return 'Locked';
    }

    get gateStatusClass() {
        const baseClass = 'gate-status-card ';
        switch (this.gateStatus) {
            case 'Passed': return baseClass + 'gate-status-passed';
            case 'Partial': return baseClass + 'gate-status-partial';
            default: return baseClass + 'gate-status-locked';
        }
    }

    get gateIcon() {
        switch (this.gateStatus) {
            case 'Passed': return '✅';
            case 'Partial': return '⚠️';
            default: return '🔒';
        }
    }

    get gateLabel() {
        switch (this.gateStatus) {
            case 'Passed': return 'Safety Gate Passed';
            case 'Partial': return 'Critical Items Verified';
            default: return 'Safety Gate Locked';
        }
    }

    get progressPercent() {
        if (this.totalCount === 0) return 0;
        return (this.completedCount / this.totalCount) * 100;
    }

    get progressBarStyle() {
        return `width: ${this.progressPercent}%`;
    }

    get progressBarClass() {
        const baseClass = 'gate-progress-fill ';
        switch (this.gateStatus) {
            case 'Passed': return baseClass + 'gate-progress-passed';
            case 'Partial': return baseClass + 'gate-progress-partial';
            default: return baseClass + 'gate-progress-locked';
        }
    }

    get hasHazards() { return this.hazardSteps.length > 0; }
    get noHazards() { return this.hazardSteps.length === 0; }
    get hasCriticalSteps() { return this.criticalSteps.length > 0; }
    get hasSiteSteps() { return this.siteSteps.length > 0; }
    get hasAdminSteps() { return this.adminSteps.length > 0; }

    get gateLabelClass() {
        switch (this.gateStatus) {
            case 'Passed': return 'gate-label gate-label-passed';
            case 'Partial': return 'gate-label gate-label-partial';
            default: return 'gate-label gate-label-locked';
        }
    }

    get criticalSectionClass() { return 'section-card section-critical'; }
    get siteSectionClass() { return 'section-card section-site'; }
    get adminSectionClass() { return 'section-card section-admin'; }
    get criticalTitleClass() { return 'section-title section-title-critical'; }
    get siteTitleClass() { return 'section-title section-title-site'; }
    get adminTitleClass() { return 'section-title section-title-admin'; }
    get lockButtonDisabled() { return this.gateStatus === 'Locked'; }

    get severityOptions() {
        return [
            { label: 'Low', value: 'Low' },
            { label: 'Medium', value: 'Medium' },
            { label: 'High', value: 'High' },
            { label: 'Critical', value: 'Critical' }
        ];
    }

    _mapStepToItem(step) {
        // localChecks is the source of truth once the user taps. Falls back to
        // the server-side Completed_At__c when no local override exists.
        const localOverride = this.localChecks[step.Id];
        const isChecked = localOverride !== undefined
            ? !!localOverride
            : !!step.Completed_At__c;
        const localNAOverride = this.localNAs[step.Id];
        const isNA = localNAOverride !== undefined
            ? !!localNAOverride
            : step.Status === 'Not Applicable';
        const isResolved = isChecked || isNA;
        return {
            id: step.Id,
            name: step.Name,
            description: step.Description,
            isChecked,
            isNA,
            isResolved,
            isCritical: !!step.Is_Critical__c,
            showBlocksGate: !!step.Is_Critical__c && !isResolved,
            showSkipBtn: !step.Is_Critical__c && !isResolved,
            itemClass: `checklist-item ${isResolved ? 'checked' : 'unchecked'}${isNA ? ' item-na' : ''}`,
            toggleClass: isChecked ? 'check-btn check-btn-on' : 'check-btn check-btn-off',
            textClass: isNA ? 'item-text item-text-na' : (isChecked ? 'item-text item-text-checked' : 'item-text item-text-unchecked')
        };
    }

    handleCheckToggle(event) {
        const workStepId = event.target.dataset.id || event.currentTarget.dataset.id;
        if (!workStepId) return;
        const allItems = [...this.criticalSteps, ...this.siteSteps, ...this.adminSteps];
        const item = allItems.find(i => i.id === workStepId);
        const wasChecked = !!(item && item.isChecked);
        const isNowChecked = !wasChecked;

        this.localChecks = { ...this.localChecks, [workStepId]: isNowChecked };

        if (isNowChecked && this.localNAs[workStepId]) {
            const next = { ...this.localNAs };
            delete next[workStepId];
            this.localNAs = next;
        }

        const recordInput = { fields: { [WS_ID.fieldApiName]: workStepId } };

        if (isNowChecked) {
            recordInput.fields[WS_COMPLETED_AT.fieldApiName] = new Date().toISOString();
            recordInput.fields.Status = 'Completed';
        } else {
            recordInput.fields[WS_COMPLETED_AT.fieldApiName] = null;
            recordInput.fields.Status = 'New';
        }

        updateRecord(recordInput)
            .then(() => {
                const previousStatus = this.gateStatus;
                const eventDetail = { Safety_Gate_Status__c: this.gateStatus };

                if (this.gateStatus === 'Passed' && previousStatus !== 'Passed') {
                    eventDetail.Safety_Gate_Passed_At__c = new Date().toISOString();
                }

                this.dispatchEvent(
                    new CustomEvent('stepdatasave', {
                        detail: { fields: eventDetail },
                        bubbles: true,
                        composed: true
                    })
                );
            })
            .catch((error) => {
                // Keep optimistic UI even if save fails — demo continuity matters.
                console.warn('[SafetyStep] WorkStep save failed (visual kept):', workStepId,
                    error?.body?.message || error?.message || JSON.stringify(error));
            });
    }

    handleHazardTextChange(event) {
        this.hazardText = event.target.value;
    }

    handleSeverityChange(event) {
        this.hazardSeverity = event.detail.value;
    }

    handleAddHazard() {
        if (!this.hazardText || this.hazardText.trim() === '') return;

        const now = new Date().toISOString();
        const fields = {
            [HAZARD_DESCRIPTION.fieldApiName]: this.hazardText,
            [HAZARD_SEVERITY.fieldApiName]: this.hazardSeverity,
            [HAZARD_STATUS.fieldApiName]: 'Open',
            [HAZARD_REPORTED_AT.fieldApiName]: now,
            [HAZARD_REPORTED_BY.fieldApiName]: userId,
            [HAZARD_WORK_ORDER.fieldApiName]: this.recordId
        };

        const recordInput = { apiName: HAZARD_OBJECT.objectApiName, fields };

        const savedText = this.hazardText;
        const savedSeverity = this.hazardSeverity;
        this.hazardText = '';
        this.hazardSeverity = 'Medium';

        createRecord(recordInput)
            .then((result) => {
                const newHazard = {
                    Id: result.id,
                    Name: result.id,
                    Description__c: savedText,
                    Severity__c: savedSeverity,
                    Status__c: 'Open',
                    Reported_At__c: now,
                    Reported_By__c: userId
                };
                this.localHazards = [...this.localHazards, newHazard];

                this.dispatchEvent(
                    new CustomEvent('hazardcreated', {
                        detail: { hazardText: savedText, severity: savedSeverity },
                        bubbles: true,
                        composed: true
                    })
                );
            })
            .catch((error) => {
                console.error('[SafetyStep] Error creating hazard:', JSON.stringify(error));
                this.hazardText = savedText;
                this.hazardSeverity = savedSeverity;
            });
    }

    handleMarkNA(event) {
        const workStepId = event.currentTarget.dataset.id;

        this.localNAs = { ...this.localNAs, [workStepId]: true };

        const recordInput = {
            fields: {
                [WS_ID.fieldApiName]: workStepId,
                Status: 'Not Applicable',
                [WS_COMPLETED_AT.fieldApiName]: new Date().toISOString()
            }
        };

        updateRecord(recordInput)
            .then(() => {
                this.dispatchEvent(
                    new CustomEvent('stepdatasave', {
                        detail: { fields: { Safety_Gate_Status__c: this.gateStatus } },
                        bubbles: true,
                        composed: true
                    })
                );
            })
            .catch((error) => {
                console.error('[SafetyStep] Error marking N/A:', workStepId, JSON.stringify(error));
                const next = { ...this.localNAs };
                delete next[workStepId];
                this.localNAs = next;
            });
    }

    handleUndoNA(event) {
        const workStepId = event.currentTarget.dataset.id;

        const nextNAs = { ...this.localNAs };
        delete nextNAs[workStepId];
        this.localNAs = nextNAs;

        const nextChecks = { ...this.localChecks };
        delete nextChecks[workStepId];
        this.localChecks = nextChecks;

        const recordInput = {
            fields: {
                [WS_ID.fieldApiName]: workStepId,
                Status: 'New',
                [WS_COMPLETED_AT.fieldApiName]: null
            }
        };

        updateRecord(recordInput)
            .catch((error) => {
                console.error('[SafetyStep] Error undoing N/A:', workStepId, JSON.stringify(error));
                this.localNAs = { ...this.localNAs, [workStepId]: true };
            });
    }

    handleStepComplete() {
        this.dispatchEvent(
            new CustomEvent('stepcomplete', {
                detail: { stepId: 'safety', completed: this.allComplete },
                bubbles: true,
                composed: true
            })
        );
    }

    _flattenRecord(record) {
        const f = record.fields;
        return {
            Id: record.id,
            Name: f.Name?.value,
            Description: f.Description?.value,
            Step_Category__c: f.Step_Category__c?.value,
            Is_Critical__c: f.Is_Critical__c?.value,
            Completed_At__c: f.Completed_At__c?.value,
            Completed_By__c: f.Completed_By__c?.value,
            Sort_Order__c: f.Sort_Order__c?.value,
            Status: f.Status?.value
        };
    }

    _flattenHazardRecord(record) {
        const f = record.fields;
        return {
            Id: record.id,
            Name: f.Name?.value,
            Description__c: f.Description__c?.value,
            Severity__c: f.Severity__c?.value,
            Status__c: f.Status__c?.value,
            Reported_At__c: f.Reported_At__c?.value,
            Reported_By__c: f.Reported_By__c?.value
        };
    }

    _severityClass(severity) {
        switch (severity) {
            case 'Critical': return 'severity-badge severity-critical';
            case 'High': return 'severity-badge severity-high';
            case 'Medium': return 'severity-badge severity-medium';
            case 'Low': return 'severity-badge severity-low';
            default: return 'severity-badge severity-medium';
        }
    }

    // ── AI Pre-Visit Risk Briefing ──────────────────────────────────────
    // Pulls a route + property risk briefing — pet-on-property flag, conducive
    // conditions, weather, applicator-license validity. Renders as an insight
    // card at the top of the safety step.
    @track riskBriefing;
    @track riskBriefingTimestamp;

    @wire(briefForWorkOrder, { workOrderId: '$recordId' })
    wiredRiskBriefing({ data, error }) {
        if (data) {
            this.riskBriefing = data;
            this.riskBriefingTimestamp = new Date().toISOString();
        } else if (error) {
            // Graceful degradation — no error spam, just no card.
            console.error('[SafetyStep] RiskBriefing unavailable:', JSON.stringify(error));
            this.riskBriefing = null;
        }
    }

    get hasRiskBriefing() {
        return !!this.riskBriefing;
    }

    get riskBriefingSeverity() {
        if (!this.riskBriefing) return 'info';
        if (this.riskBriefing.assetHistoryRisk === 'High'
            || (this.riskBriefing.nearbyHazards && this.riskBriefing.nearbyHazards > 0)) {
            return 'critical';
        }
        if (this.riskBriefing.assetHistoryRisk === 'Medium') return 'warning';
        return 'info';
    }

    get riskBriefingDetails() {
        if (!this.riskBriefing) return [];
        return [
            { label: 'Weather', value: this.riskBriefing.weatherRisk || 'Unknown' },
            { label: 'Pets on Property', value: this.riskBriefing.petsOnProperty || 'Unknown' },
            { label: 'Nearby Hazards', value: String(this.riskBriefing.nearbyHazards ?? 0) },
            { label: 'Property History', value: this.riskBriefing.assetHistoryRisk || 'Low' }
        ];
    }

    // Compact risk chips — at-a-glance only. Each chip = one icon + one short
    // value. Verbose narrative (the Apex `summary` paragraph) is intentionally
    // NOT rendered — it competed with the chips for the tech's eye.
    get riskChips() {
        if (!this.riskBriefing) return [];
        const weatherLevel = this.riskBriefing.weatherRisk || 'Unknown';
        const weatherDetail = this.riskBriefing.weatherDetail || '';
        const hazards = this.riskBriefing.nearbyHazards ?? 0;
        const history = this.riskBriefing.assetHistoryRisk || 'Low';
        const rupAuth = this.riskBriefing.locateTicketStatus || 'N/A';

        // Pull a short weather summary from the verbose forecast string —
        // first clause only ("sunny, 82F" not the whole paragraph).
        let weatherShort = weatherDetail;
        if (weatherDetail) {
            const firstSentence = weatherDetail.split(/[.•]/)[0].trim();
            const afterColon = firstSentence.includes(':')
                ? firstSentence.split(':').slice(1).join(':').trim()
                : firstSentence;
            weatherShort = afterColon.length < 32 ? afterColon : afterColon.slice(0, 30) + '…';
        }
        if (!weatherShort) weatherShort = weatherLevel;

        const weatherIcon = /rain|storm/i.test(weatherDetail) ? '🌧️'
            : /cloud/i.test(weatherDetail) ? '⛅'
            : /sun|clear/i.test(weatherDetail) ? '☀️'
            : '🌤️';
        const hazardsIcon = hazards > 0 ? '⚠️' : '✓';
        const historyIcon = history === 'High' ? '🔴' : history === 'Medium' ? '🟡' : '🟢';
        const rupIcon = rupAuth === 'Verified' ? '✓' : rupAuth === 'Pending' ? '⏳' : '—';

        const chip = (icon, label, value, severity) => ({
            key: label, icon, label, value,
            chipClass: 'risk-chip risk-chip-' + severity
        });
        const weatherSev = /rain|storm/i.test(weatherDetail) ? 'warning'
            : weatherLevel === 'Severe' ? 'critical' : 'ok';
        const hazardsSev = hazards > 0 ? 'critical' : 'ok';
        const historySev = history === 'High' ? 'critical' : history === 'Medium' ? 'warning' : 'ok';
        const rupSev = rupAuth === 'Verified' ? 'ok' : rupAuth === 'Pending' ? 'warning' : 'ok';
        return [
            chip(weatherIcon, 'Weather', weatherShort, weatherSev),
            chip(hazardsIcon, 'Hazards', hazards + ' nearby', hazardsSev),
            chip(historyIcon, 'Property History', history, historySev),
            chip(rupIcon, 'RUP Auth', rupAuth, rupSev)
        ];
    }

    get riskBriefingConfidence() {
        return this.riskBriefing ? this.riskBriefing.confidence : 80;
    }

    get riskBriefingSource() {
        return this.riskBriefing ? this.riskBriefing.source : '';
    }

    get riskBriefingSummary() {
        return this.riskBriefing ? this.riskBriefing.summary : '';
    }
}
