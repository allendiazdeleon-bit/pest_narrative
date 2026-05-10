import { LightningElement, api, track, wire } from 'lwc';
import { getRecord, getFieldValue, updateRecord } from 'lightning/uiRecordApi';
import { getRelatedListRecords } from 'lightning/uiRelatedListApi';
import WS_ID from '@salesforce/schema/WorkStep.Id';
import WS_COMPLETED_AT from '@salesforce/schema/WorkStep.Completed_At__c';
import WO_ASSET_ID from '@salesforce/schema/WorkOrder.AssetId';
import WO_PEST_FINDING from '@salesforce/schema/WorkOrder.Pest_Finding__c';
import ASSET_SERVICE_LINE from '@salesforce/schema/Asset.Service_Line__c';

// Walk-Around Findings — variant-aware Asset measurement fields. Captured here
// in Treatment Execution (relocated from masseyFlowSiteStep) since the tech is
// actively recording what was found during the visit.
import ASSET_PEST_PRESSURE from '@salesforce/schema/Asset.Pest_Pressure_Score__c';
import ASSET_CONDUCIVE_CONDITIONS from '@salesforce/schema/Asset.Conducive_Conditions__c';
import ASSET_PERIMETER_LF from '@salesforce/schema/Asset.Treatment_Perimeter_LinearFt__c';
import ASSET_STATION_COUNT from '@salesforce/schema/Asset.Bait_Station_Count__c';
import ASSET_STATION_LAST_INSPECT from '@salesforce/schema/Asset.Last_Station_Inspection__c';
import ASSET_NOZZLE_COUNT from '@salesforce/schema/Asset.Nozzle_Count__c';
import ASSET_STANDING_WATER from '@salesforce/schema/Asset.Standing_Water_Sources__c';
import ASSET_SOIL_TEMP from '@salesforce/schema/Asset.Soil_Temp_F__c';

import suggestForStep from '@salesforce/apex/NextBestActionService.suggestForStep';

// Pest treatment phase labels — three-phase model:
//   Phase 1: Pre-Treatment Setup (PPE on, mix tank, calibrate spray equipment,
//            verify EPA reg # + applicator license, post re-entry signage)
//   Phase 2: Treatment Execution (apply product per label, document amount,
//            inspect bait stations, fog perimeter, drench mounds)
//   Phase 3: Post-Treatment Verification (release perimeter after Re-Entry
//            Interval, photograph treated area, sign-off, customer notice)
import LBL_PRECHECK_TITLE from '@salesforce/label/c.MasseyFlow_PreCheck_Phase_Title';
import LBL_EXECUTE_TITLE from '@salesforce/label/c.MasseyFlow_Execute_Phase_Title';
import LBL_VERIFY_TITLE from '@salesforce/label/c.MasseyFlow_Verify_Phase_Title';
import LBL_PRECHECK_LOCK from '@salesforce/label/c.MasseyFlow_PreCheck_Lock_Message';
import LBL_EXECUTE_LOCK from '@salesforce/label/c.MasseyFlow_Execute_Lock_Message';
import LBL_FINDINGS_HEADING from '@salesforce/label/c.MasseyFlow_Findings_Section_Heading';
import LBL_PEST_FINDING from '@salesforce/label/c.MasseyFlow_PestFinding_Label';
import LBL_READING_PROMPT from '@salesforce/label/c.MasseyFlow_ReadingPrompt';

const WORKSTEP_FIELDS = [
    'WorkStep.Id', 'WorkStep.Name', 'WorkStep.Description',
    'WorkStep.Step_Category__c', 'WorkStep.Is_Critical__c',
    'WorkStep.Completed_At__c', 'WorkStep.Completed_By__c',
    'WorkStep.Sort_Order__c', 'WorkStep.Status'
];

export default class MasseyFlowWorkStep extends LightningElement {
    @api recordId;
    @api workOrder;
    // Service-line override from orchestrator. Falls back to self-wired
    // Asset.Service_Line__c (P1.1).
    @api serviceLineOverride;

    _externalWorkSteps = [];
    _selfWiredWorkSteps = [];
    @track selfWorkPlanId = null;
    @track selfAssetId = null;
    @track selfServiceLine = null;

    @api
    get workSteps() {
        return this._externalWorkSteps.length > 0
            ? this._externalWorkSteps
            : this._selfWiredWorkSteps;
    }
    set workSteps(value) { this._externalWorkSteps = value || []; }

    @track localChecks = {};
    @track localNAs = {};

    // Walk-Around Findings — variant-aware live measurements captured during
    // the visit. Each service line populates its own subset; rest stay null.
    @track measurements = {
        // Pest (residential GoGreen)
        pestPressureScore: null,
        conduciveConditions: '',
        perimeterLinearFeet: null,
        // Termite (Sentricon + Termidor)
        baitStationsActive: null,
        soilTreatmentDepthInches: null,
        // Mosquito Hunter
        standingWaterSources: null,
        nozzlesInspected: null,
        // Lawn Service
        soilTempF: null,
        weedCoveragePct: null
    };

    @track isSavingFindings = false;
    @track pestFinding = null;

    label = {
        findingsHeading: LBL_FINDINGS_HEADING,
        pestFinding: LBL_PEST_FINDING,
        readingPrompt: LBL_READING_PROMPT
    };

    // Self-wire: WorkOrder → AssetId for service-line detection + Pest_Finding picker.
    @wire(getRecord, { recordId: '$recordId', fields: [WO_ASSET_ID, WO_PEST_FINDING] })
    wiredWorkOrder({ data }) {
        if (data) {
            this.selfAssetId = getFieldValue(data, WO_ASSET_ID) || null;
            this.pestFinding = getFieldValue(data, WO_PEST_FINDING) || 'None';
        }
    }

    @wire(getRecord, { recordId: '$selfAssetId', fields: [ASSET_SERVICE_LINE] })
    wiredAsset({ data }) {
        if (data) {
            this.selfServiceLine = getFieldValue(data, ASSET_SERVICE_LINE) || null;
        }
    }

    get effectiveServiceLine() {
        return this.serviceLineOverride
            || this.workOrder?.Asset?.Service_Line__c
            || this.selfServiceLine;
    }

    // 4-way branching on Service_Line__c. Treatment phases share the same
    // three-phase shape across all service lines; the per-line variation
    // shows up via the WorkStep records (Step_Category__c filtering) and the
    // chemical panel inputs (RUP attestation).
    // Asset.Service_Line__c picklist API values per P1.1: Pest / Termite / Mosquito / Lawn.
    get isPest() { return this.effectiveServiceLine === 'Pest'; }
    get isTermite() { return this.effectiveServiceLine === 'Termite'; }
    get isMosquito() { return this.effectiveServiceLine === 'Mosquito'; }
    get isLawn() { return this.effectiveServiceLine === 'Lawn'; }

    get phase1Title() { return LBL_PRECHECK_TITLE; }
    get phase2Title() { return LBL_EXECUTE_TITLE; }
    get phase3Title() { return LBL_VERIFY_TITLE; }
    get phase1LockMessage() { return LBL_PRECHECK_LOCK; }
    get phase2LockMessage() { return LBL_EXECUTE_LOCK; }

    @wire(getRelatedListRecords, {
        parentRecordId: '$recordId',
        relatedListId: 'WorkPlans',
        fields: ['WorkPlan.Id']
    })
    wiredWorkPlans({ data, error }) {
        if (data && data.records && data.records.length > 0) {
            this.selfWorkPlanId = data.records[0].fields.Id?.value || data.records[0].id;
        } else if (error) {
            console.error('[WorkStep] Error loading WorkPlans:', JSON.stringify(error));
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
            this._initLocalChecks(this._selfWiredWorkSteps);
        } else if (error) {
            console.error('[WorkStep] Error loading WorkSteps:', JSON.stringify(error));
        }
    }

    connectedCallback() {
        // localChecks is the user's optimistic override; absence of an entry
        // means "fall back to server-side Completed_At__c" in the getters.
    }

    // WorkStep.Step_Category__c picklist values (Work_DeEnergize / Work_Execute /
    // Work_ReEnergize) are kept stable as the API names per Decision #20 — they
    // map 1:1 to "Pre-Treatment Setup / Treatment Execution / Post-Treatment
    // Verification" in the user-facing labels (Custom Labels).
    get preCheckSteps() { return this.getStepsByCategory('Work_DeEnergize'); }
    get workExecuteSteps() { return this.getStepsByCategory('Work_Execute'); }
    get verifySteps() { return this.getStepsByCategory('Work_ReEnergize'); }

    get preCheckComplete() { return this.areAllStepsChecked(this.preCheckSteps); }
    get workExecuteComplete() { return this.areAllStepsChecked(this.workExecuteSteps); }
    get verifyComplete() { return this.areAllStepsChecked(this.verifySteps); }

    get allPhasesComplete() {
        return this.preCheckComplete && this.workExecuteComplete && this.verifyComplete;
    }

    get preCheckCount() { return this.preCheckSteps.filter((s) => s.isChecked).length; }
    get preCheckTotal() { return this.preCheckSteps.length; }
    get workExecuteCount() { return this.workExecuteSteps.filter((s) => s.isChecked).length; }
    get workExecuteTotal() { return this.workExecuteSteps.length; }
    get verifyCount() { return this.verifySteps.filter((s) => s.isChecked).length; }
    get verifyTotal() { return this.verifySteps.length; }

    get isWorkExecuteLocked() { return !this.preCheckComplete; }
    get isVerifyLocked() { return !this.workExecuteComplete; }

    getStepsByCategory(category) {
        return this.workSteps
            .filter((step) => step.Step_Category__c === category)
            .sort((a, b) => (a.Sort_Order__c || 0) - (b.Sort_Order__c || 0))
            .map((step) => {
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
                    name: step.Name || '',
                    description: step.Description || '',
                    isChecked,
                    isNA,
                    isResolved,
                    isCritical: !!step.Is_Critical__c,
                    showSkipBtn: !step.Is_Critical__c && !isResolved,
                    toggleClass: isChecked ? 'check-btn check-btn-on' : 'check-btn check-btn-off',
                    textClass: isNA ? 'item-text-na' : (isChecked ? 'item-text-checked' : 'item-text-unchecked'),
                };
            });
    }

    areAllStepsChecked(steps) {
        if (!steps || steps.length === 0) return false;
        return steps.every((step) => step.isResolved);
    }

    getPhaseForStepId(stepId) {
        const step = this.workSteps.find((s) => s.Id === stepId);
        return step ? step.Step_Category__c : null;
    }

    handleCheckToggle(event) {
        const stepId = event.target.dataset.id || event.currentTarget.dataset.id;
        if (!stepId) return;
        const phase = this.getPhaseForStepId(stepId);

        if ((phase === 'Work_Execute' && this.isWorkExecuteLocked) ||
            (phase === 'Work_ReEnergize' && this.isVerifyLocked)) {
            return;
        }

        const localPrev = this.localChecks[stepId];
        const serverPrev = !!(this.workSteps.find(s => s.Id === stepId) || {}).Completed_At__c;
        const wasChecked = localPrev !== undefined ? !!localPrev : serverPrev;
        const isNowChecked = !wasChecked;

        this.localChecks = { ...this.localChecks, [stepId]: isNowChecked };

        if (isNowChecked && this.localNAs[stepId]) {
            const next = { ...this.localNAs };
            delete next[stepId];
            this.localNAs = next;
        }

        this.updateWorkStep(stepId, isNowChecked);
    }

    async updateWorkStep(stepId, explicitChecked) {
        const isChecked = explicitChecked !== undefined ? explicitChecked : this.localChecks[stepId];

        const fields = {
            [WS_ID.fieldApiName]: stepId,
            [WS_COMPLETED_AT.fieldApiName]: isChecked ? new Date().toISOString() : null,
            Status: isChecked ? 'Completed' : 'New',
        };

        try {
            await updateRecord({ fields });

            if (this.allPhasesComplete) {
                this.dispatchEvent(
                    new CustomEvent('stepdatasave', {
                        detail: {
                            allComplete: true,
                            workOrderId: this.workOrder?.Id,
                        },
                    })
                );
            }
        } catch (error) {
            console.warn('[WorkStep] WorkStep save failed (visual kept):', stepId,
                error?.body?.message || error?.message || JSON.stringify(error));
        }
    }

    @api
    get hasCriticalIncomplete() {
        const allSteps = [...this.preCheckSteps, ...this.workExecuteSteps, ...this.verifySteps];
        return allSteps.some(step => step.isCritical && !step.isResolved);
    }

    handleMarkNA(event) {
        const stepId = event.currentTarget.dataset.id;
        const phase = this.getPhaseForStepId(stepId);

        if ((phase === 'Work_Execute' && this.isWorkExecuteLocked) ||
            (phase === 'Work_ReEnergize' && this.isVerifyLocked)) {
            return;
        }

        this.localNAs = { ...this.localNAs, [stepId]: true };

        const fields = {
            [WS_ID.fieldApiName]: stepId,
            Status: 'Not Applicable',
            [WS_COMPLETED_AT.fieldApiName]: new Date().toISOString(),
        };

        updateRecord({ fields })
            .then(() => {
                if (this.allPhasesComplete) {
                    this.dispatchEvent(
                        new CustomEvent('stepdatasave', {
                            detail: { allComplete: true, workOrderId: this.workOrder?.Id },
                        })
                    );
                }
            })
            .catch((error) => {
                console.error('[WorkStep] Error marking N/A:', stepId, JSON.stringify(error));
                const next = { ...this.localNAs };
                delete next[stepId];
                this.localNAs = next;
            });
    }

    handleUndoNA(event) {
        const stepId = event.currentTarget.dataset.id;

        const nextNAs = { ...this.localNAs };
        delete nextNAs[stepId];
        this.localNAs = nextNAs;

        const nextChecks = { ...this.localChecks };
        delete nextChecks[stepId];
        this.localChecks = nextChecks;

        const fields = {
            [WS_ID.fieldApiName]: stepId,
            Status: 'New',
            [WS_COMPLETED_AT.fieldApiName]: null,
        };

        updateRecord({ fields })
            .catch((error) => {
                console.error('[WorkStep] Error undoing N/A:', stepId, JSON.stringify(error));
                this.localNAs = { ...this.localNAs, [stepId]: true };
            });
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

    _initLocalChecks(steps) {
        const updated = { ...this.localChecks };
        steps.forEach(step => {
            if (updated[step.Id] === undefined) {
                updated[step.Id] = !!step.Completed_At__c;
            }
        });
        this.localChecks = updated;
    }

    // ── Walk-Around Findings — variant-aware measurement capture ──────
    // Relocated from masseyFlowSiteStep. Persisted via updateRecord on the
    // Asset (Property) — same Komaci-clean offline path as before.

    get saveFindingsLabel() {
        return this.isSavingFindings ? 'Saving...' : 'Save Walk-Around Findings';
    }

    handlePestPressureChange(event) {
        this.measurements.pestPressureScore = event.target.value
            ? parseInt(event.target.value, 10) : null;
    }
    handleConduciveChange(event) {
        this.measurements.conduciveConditions = event.target.value || '';
    }
    handlePerimeterChange(event) {
        this.measurements.perimeterLinearFeet = event.target.value
            ? parseInt(event.target.value, 10) : null;
    }
    handleBaitStationsChange(event) {
        this.measurements.baitStationsActive = event.target.value
            ? parseInt(event.target.value, 10) : null;
    }
    handleSoilDepthChange(event) {
        this.measurements.soilTreatmentDepthInches = event.target.value
            ? parseFloat(event.target.value) : null;
    }
    handleStandingWaterChange(event) {
        this.measurements.standingWaterSources = event.target.value
            ? parseInt(event.target.value, 10) : null;
    }
    handleNozzlesChange(event) {
        this.measurements.nozzlesInspected = event.target.value
            ? parseInt(event.target.value, 10) : null;
    }
    handleSoilTempChange(event) {
        this.measurements.soilTempF = event.target.value
            ? parseFloat(event.target.value) : null;
    }
    handleWeedCoverageChange(event) {
        this.measurements.weedCoveragePct = event.target.value
            ? parseInt(event.target.value, 10) : null;
    }

    // Pest_Finding__c picklist options. Mirrors the field metadata and is
    // rendered as a <select> next to the Walk-Around inputs.
    get pestFindingOptions() {
        const current = this.pestFinding || 'None';
        return [
            { value: 'None',                    label: 'None / no finding' },
            { value: 'Pest_Pressure_Elevated',  label: 'Pest pressure elevated' },
            { value: 'Mosquito_Hotspot',        label: 'Mosquito hotspot' },
            { value: 'Sentricon_Activity',      label: 'Sentricon activity / hits' },
            { value: 'Termite_Swarmer_Sighting',label: 'Termite swarmer sighting' },
            { value: 'Conducive_Conditions',    label: 'Conducive conditions flagged' },
            { value: 'Wildlife_Encounter',      label: 'Wildlife encounter' },
            { value: 'Lawn_Distress',           label: 'Lawn distress / disease' },
            { value: 'Other',                   label: 'Other (see notes)' }
        ].map(o => ({ ...o, selected: o.value === current }));
    }

    handlePestFindingChange(event) {
        const next = event.target.value || 'None';
        this.pestFinding = next;
        const fields = {
            Id: this.recordId,
            [WO_PEST_FINDING.fieldApiName]: next === 'None' ? null : next
        };
        updateRecord({ fields }).catch((error) => {
            console.error('[WorkStep] Pest_Finding__c save failed:',
                error?.body?.message || error?.message || JSON.stringify(error));
        });
    }

    async handleSaveFindings() {
        const targetAssetId = this.selfAssetId
            || this.workOrder?.AssetId
            || this.workOrder?.Asset?.Id;
        if (!targetAssetId) return;
        this.isSavingFindings = true;
        try {
            const fields = { Id: targetAssetId };
            if (this.isPest) {
                if (this.measurements.pestPressureScore != null) {
                    fields[ASSET_PEST_PRESSURE.fieldApiName] = this.measurements.pestPressureScore;
                }
                if (this.measurements.conduciveConditions) {
                    fields[ASSET_CONDUCIVE_CONDITIONS.fieldApiName] = this.measurements.conduciveConditions;
                }
                if (this.measurements.perimeterLinearFeet != null) {
                    fields[ASSET_PERIMETER_LF.fieldApiName] = this.measurements.perimeterLinearFeet;
                }
            } else if (this.isTermite) {
                if (this.measurements.baitStationsActive != null) {
                    fields[ASSET_STATION_COUNT.fieldApiName] = this.measurements.baitStationsActive;
                }
                fields[ASSET_STATION_LAST_INSPECT.fieldApiName] = new Date().toISOString();
            } else if (this.isMosquito) {
                if (this.measurements.standingWaterSources != null) {
                    fields[ASSET_STANDING_WATER.fieldApiName] = this.measurements.standingWaterSources;
                }
                if (this.measurements.nozzlesInspected != null) {
                    fields[ASSET_NOZZLE_COUNT.fieldApiName] = this.measurements.nozzlesInspected;
                }
            } else if (this.isLawn) {
                if (this.measurements.soilTempF != null) {
                    fields[ASSET_SOIL_TEMP.fieldApiName] = this.measurements.soilTempF;
                }
            }
            await updateRecord({ fields });
        } catch (error) {
            console.error('[WorkStep] Walk-Around save failed:',
                error?.body?.message || error?.message || JSON.stringify(error));
        } finally {
            this.isSavingFindings = false;
        }
    }

    // ── AI Next Best Actions ─────────────────────────────────────────
    @track _nbaCache = {};
    @track _nbaOrder = [];
    @track _activeNbaCategory;
    @track _nbaLoading = false;
    _nbaTimestamp;

    /**
     * Pick which category's NBAs to show. Bias toward the phase the tech
     * is most likely working in: the first phase that isn't fully complete.
     */
    get activeNbaCategory() {
        if (!this.preCheckComplete && this.preCheckTotal > 0) return 'Work_DeEnergize';
        if (!this.workExecuteComplete && this.workExecuteTotal > 0) return 'Work_Execute';
        if (!this.verifyComplete && this.verifyTotal > 0) return 'Work_ReEnergize';
        return 'Work_Execute';
    }

    get activeNbaCategoryLabel() {
        switch (this.activeNbaCategory) {
            case 'Work_DeEnergize': return 'Pre-Treatment Setup';
            case 'Work_Execute':    return 'Treatment Execution';
            case 'Work_ReEnergize': return 'Post-Treatment Verification';
            default:                return 'Current Phase';
        }
    }

    renderedCallback() {
        const cat = this.activeNbaCategory;
        if (!this.recordId || !cat) return;
        if (this._activeNbaCategory === cat && this._nbaCache[cat]) return;
        this._activeNbaCategory = cat;
        if (this._nbaCache[cat]) {
            this._touchNbaCache(cat);
            return;
        }
        this._loadNbaForCategory(cat);
    }

    async _loadNbaForCategory(category) {
        this._nbaLoading = true;
        try {
            const result = await suggestForStep({
                workOrderId: this.recordId,
                stepCategory: category
            });
            this._nbaCache = {
                ...this._nbaCache,
                [category]: {
                    suggestions: Array.isArray(result) ? result : [],
                    fetchedAt: new Date().toISOString()
                }
            };
            this._touchNbaCache(category);
            this._nbaTimestamp = new Date().toISOString();
        } catch (e) {
            console.error('[WorkStep] NBA load failed:', JSON.stringify(e));
            this._nbaCache = {
                ...this._nbaCache,
                [category]: { suggestions: [], fetchedAt: new Date().toISOString() }
            };
        } finally {
            this._nbaLoading = false;
        }
    }

    _touchNbaCache(category) {
        const next = this._nbaOrder.filter((c) => c !== category);
        next.push(category);
        while (next.length > 3) {
            const evicted = next.shift();
            const cache = { ...this._nbaCache };
            delete cache[evicted];
            this._nbaCache = cache;
        }
        this._nbaOrder = next;
    }

    get nbaSuggestions() {
        const cat = this.activeNbaCategory;
        const entry = this._nbaCache[cat];
        if (!entry || !entry.suggestions || entry.suggestions.length === 0) return [];
        return entry.suggestions.map((s, idx) => {
            let severity = 'info';
            if (s.priority === 'Recommended' && s.category === 'Safety') {
                severity = 'warning';
            }
            return {
                key: `nba-${cat}-${idx}`,
                title: s.title,
                summary: s.rationale,
                severity,
                confidence: s.confidence,
                source: s.source || 'NextBestActionService',
                details: [
                    { label: 'Category', value: s.category || '—' },
                    { label: 'Priority', value: s.priority || '—' }
                ]
            };
        });
    }

    get hasNbaSuggestions() { return this.nbaSuggestions.length > 0; }
    get nbaTimestamp() { return this._nbaTimestamp; }
}
