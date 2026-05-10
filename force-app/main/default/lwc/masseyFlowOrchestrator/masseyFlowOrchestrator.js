import { LightningElement, api, wire, track } from 'lwc';
import { getRecord, getFieldValue, updateRecord } from 'lightning/uiRecordApi';
import { getRelatedListRecords } from 'lightning/uiRelatedListApi';
import Alert from 'lightning/alert';
import USER_ID from '@salesforce/user/Id';

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
import WO_WORKTYPE_NAME from '@salesforce/schema/WorkOrder.WorkType.Name';

// getRelatedListRecords requires string field references, NOT schema tokens
const WORKSTEP_FIELDS = [
  'WorkStep.Id', 'WorkStep.WorkPlanId', 'WorkStep.Name',
  'WorkStep.Description', 'WorkStep.Step_Category__c',
  'WorkStep.Is_Critical__c', 'WorkStep.Completed_At__c',
  'WorkStep.Completed_By__c', 'WorkStep.Sort_Order__c',
  'WorkStep.Status'
];

const WORKORDER_FIELDS = [
  WO_ID, WO_NUMBER, WO_STATUS, WO_ASSET_ID, WO_ACCOUNT_ID, WO_CURRENT_STEP,
  WO_FLOW_STARTED, WO_FLOW_COMPLETED, WO_SAFETY_STATUS,
  WO_SAFETY_PASSED, WO_PEST_FINDING, WO_LINKED_INCIDENT, WO_WORKTYPE_NAME
];

// Solo Work Types — Crew & Route step auto-skips for these. Tom's surge
// area treatment + Sentricon Install + Termite Liquid + Wasp Removal stay
// crew-aware (these are the WTs where the step adds value).
const SOLO_WORK_TYPES = new Set([
  'Quarterly Pest Service',
  'Pest Inspection (New)',
  'Termite Inspection (Booster)',
  'Sentricon Service',
  'Mosquito System Service'
]);

// 5 phases of the Massey field-service treatment flow.
// Service Impact (formerly index 4) was collapsed into the Site step's
// Property Context card — only ~5% of pest visits have a linked cluster
// incident, so the dedicated step was presenter engineering. The
// `masseyFlowServiceImpactStep` LWC is preserved and embedded inline by
// the Site step when WorkOrder.Linked_Incident__c is populated.
const STEP_LABELS = [
  'Pre-Visit Check',
  'Crew & Route',
  'Property Walk-Around',
  'Apply Treatment',
  'Wrap Up & Sign'
];

// Maps each flow step index to the Step_Category__c values on WorkStep records.
// API names retained per Decision #20 — see CLAUDE.md / ARCHITECTURE_PROPOSAL.
const STEP_CATEGORY_MAP = {
  0: ['Safety_Critical', 'Safety_Site', 'Safety_Admin'],
  1: [],  // Crew & Route — no WorkSteps
  2: ['Hazard'],
  3: ['Work_DeEnergize', 'Work_Execute', 'Work_ReEnergize'],
  4: []   // Verify & Close — no WorkSteps
};

const TOTAL_STEPS = 5;

export default class MasseyFlowOrchestrator extends LightningElement {
  @api recordId;

  @track currentStepIndex = 0;
  @track showContextPanel = false;
  @track showStepMenu = false;
  @track isLoading = true;
  @track isReady = false;

  workOrderData = {};
  workOrderNumber = '';
  assetId = '';
  accountId = '';
  @track workPlanId = null;
  workSteps = [];

  @wire(getRecord, { recordId: '$recordId', fields: WORKORDER_FIELDS })
  wiredWorkOrder({ data, error }) {
    if (data) {
      this.workOrderData = data;
      this.workOrderNumber = getFieldValue(data, WO_NUMBER) || '';
      this.assetId = getFieldValue(data, WO_ASSET_ID) || '';
      this.accountId = getFieldValue(data, WO_ACCOUNT_ID) || '';

      const storedStep = getFieldValue(data, WO_CURRENT_STEP);
      if (storedStep !== null && storedStep !== undefined) {
        this.currentStepIndex = parseInt(storedStep, 10);
      }

      if (!getFieldValue(data, WO_FLOW_STARTED)) {
        this.setFlowStartedAt();
      }

      this.isLoading = false;
      this.isReady = true;
    } else if (error) {
      console.error('[Orchestrator] Error loading WorkOrder:', JSON.stringify(error));
      this.isLoading = false;
      this.showAlert('Error', 'Failed to load work order data', 'error');
    }
  }

  // Step 1: Get WorkPlans from WorkOrder
  @wire(getRelatedListRecords, {
    parentRecordId: '$recordId',
    relatedListId: 'WorkPlans',
    fields: ['WorkPlan.Id']
  })
  wiredWorkPlans({ data, error }) {
    if (data && data.records && data.records.length > 0) {
      this.workPlanId = data.records[0].fields.Id?.value || data.records[0].id;
    } else if (error) {
      console.error('[Orchestrator] Error loading WorkPlans:', JSON.stringify(error));
      this.showAlert('Warning', 'Failed to load work plan data. Some steps may not display correctly.', 'error');
    }
  }

  // Step 2: Get WorkSteps from WorkPlan (reactive via $workPlanId)
  @wire(getRelatedListRecords, {
    parentRecordId: '$workPlanId',
    relatedListId: 'WorkSteps',
    fields: WORKSTEP_FIELDS,
    pageSize: 50
  })
  wiredWorkSteps({ data, error }) {
    if (data) {
      this.workSteps = (data.records || []).map(r => this._flattenRecord(r));
    } else if (error) {
      console.error('[Orchestrator] Error loading WorkSteps:', JSON.stringify(error));
      this.showAlert('Warning', 'Failed to load work steps. Checklist data may be incomplete.', 'error');
    }
  }

  connectedCallback() {
    // Additional initialization can happen here
  }

  // GETTERS
  get totalSteps() {
    return TOTAL_STEPS;
  }

  get currentStepLabel() {
    return STEP_LABELS[this.currentStepIndex] || '';
  }

  get nextButtonLabel() {
    return this.isLastStep ? 'Complete' : 'Next';
  }

  get isFirstStep() {
    return this.currentStepIndex === 0;
  }

  get isLastStep() {
    return this.currentStepIndex === TOTAL_STEPS - 1;
  }

  get isStep0() { return this.currentStepIndex === 0; }
  get isStep1() { return this.currentStepIndex === 1; }
  get isStep2() { return this.currentStepIndex === 2; }
  get isStep3() { return this.currentStepIndex === 3; }
  get isStep4() { return this.currentStepIndex === 4; }

  get stepMenuItems() {
    // Pest-flavored step icons: shield (safety), people (crew), pin (property),
    // spray-bottle (treatment), check (close-out).
    const icons = ['🛡️', '👥', '📍', '🧪', '✅'];
    return STEP_LABELS.map((label, index) => {
      const categories = STEP_CATEGORY_MAP[index] || [];
      const categorySteps = this.workSteps.filter(w => categories.includes(w.Step_Category__c));
      const isCompleted = categorySteps.length > 0 && categorySteps.every(w => !!w.Completed_At__c || w.Status === 'Not Applicable');
      return {
        index,
        label,
        icon: icons[index],
        isCurrent: index === this.currentStepIndex,
        isCompleted,
        itemClass: 'step-menu-item' +
          (index === this.currentStepIndex ? ' step-menu-item-current' : '') +
          (isCompleted ? ' step-menu-item-completed' : '')
      };
    });
  }

  // EVENT HANDLERS
  handleToggleStepMenu(event) {
    event.stopPropagation();
    this.showStepMenu = !this.showStepMenu;
  }

  handleStepMenuSelect(event) {
    event.stopPropagation();
    const stepIndex = parseInt(event.currentTarget.dataset.index, 10);
    this.showStepMenu = false;
    this.navigateToStep(stepIndex);
  }

  handleCloseStepMenu() {
    this.showStepMenu = false;
  }

  handleStepComplete(event) {
    event.stopPropagation();
    if (!this.isLastStep) {
      this.handleNext();
    } else {
      this.completeFlow();
    }
  }

  handleStepDataSave(event) {
    event.stopPropagation();
    const { fields } = event.detail || {};
    if (fields && Object.keys(fields).length > 0) {
      this.persistFieldUpdates(fields);
    }
  }

  handleToggleContextPanel(event) {
    event.stopPropagation();
    this.showContextPanel = !this.showContextPanel;
  }

  handleNavigateToStep(event) {
    event.stopPropagation();
    const { stepIndex } = event.detail || {};
    if (stepIndex !== null && stepIndex !== undefined) {
      this.navigateToStep(stepIndex);
    }
  }

  handleCloseContextPanel() {
    this.showContextPanel = false;
  }

  handleBack() {
    if (!this.isFirstStep) {
      this.currentStepIndex--;
      // Skip Crew & Route (idx 1) on the way back too if solo Work Type
      if (this.currentStepIndex === 1 && this._isSoloWorkType()) {
        this.currentStepIndex--;
      }
      this.updateCurrentStep();
    }
  }

  async handleNext() {
    if (this._isCurrentStepBlocked()) {
      await this.showAlert('Cannot Advance', 'Complete all required items before proceeding.', 'error');
      return;
    }
    if (!this.isLastStep) {
      this.currentStepIndex++;
      // Skip Crew & Route (idx 1) for solo Work Types — Maria's quarterly
      // route doesn't need a crew step (one tech, one truck).
      if (this.currentStepIndex === 1 && this._isSoloWorkType()) {
        this.currentStepIndex++;
      }
      this.updateCurrentStep();
    }
  }

  _isCurrentStepBlocked() {
    const child = this.template.querySelector(
      'c-massey-flow-safety-step, c-massey-flow-work-step'
    );
    if (child && child.hasCriticalIncomplete) {
      return true;
    }
    return false;
  }

  _isSoloWorkType() {
    const wtName = getFieldValue(this.workOrderData, WO_WORKTYPE_NAME);
    return SOLO_WORK_TYPES.has(wtName);
  }

  // PRIVATE METHODS
  async updateCurrentStep() {
    try {
      const fields = {};
      fields[WO_ID.fieldApiName] = this.recordId;
      fields[WO_CURRENT_STEP.fieldApiName] = this.currentStepIndex;
      await updateRecord({ fields });
    } catch (error) {
      console.warn('[Orchestrator] updateCurrentStep non-blocking failure:', error?.body?.message || error?.message || JSON.stringify(error));
    }
  }

  async navigateToStep(stepIndex) {
    if (stepIndex >= 0 && stepIndex < TOTAL_STEPS) {
      this.currentStepIndex = stepIndex;
      await this.updateCurrentStep();
    }
  }

  async setFlowStartedAt() {
    try {
      const fields = {};
      fields[WO_ID.fieldApiName] = this.recordId;
      fields[WO_FLOW_STARTED.fieldApiName] = new Date().toISOString();
      await updateRecord({ fields });
    } catch (error) {
      console.error('[Orchestrator] Error setting Flow_Started_At__c:', JSON.stringify(error));
    }
  }

  async completeFlow() {
    if (this._isCurrentStepBlocked()) {
      await this.showAlert('Cannot Complete', 'Complete all required items before finishing.', 'error');
      return;
    }
    try {
      const fields = {};
      fields[WO_ID.fieldApiName] = this.recordId;
      fields[WO_FLOW_COMPLETED.fieldApiName] = new Date().toISOString();
      await updateRecord({ fields });
      this.showAlert('Success', 'Service visit completed', 'success');
    } catch (error) {
      console.error('[Orchestrator] Error completing flow:', JSON.stringify(error));
      this.showAlert('Error', 'Failed to complete flow', 'error');
    }
  }

  async markWorkStepCompleted(stepIndex) {
    const categories = STEP_CATEGORY_MAP[stepIndex] || [];
    if (categories.length === 0) return;

    const matchingSteps = this.workSteps.filter(ws =>
      categories.includes(ws.Step_Category__c) && !ws.Completed_At__c
    );

    if (matchingSteps.length === 0) return;

    const now = new Date().toISOString();
    const updates = matchingSteps.map(ws => updateRecord({
      fields: {
        Id: ws.Id,
        Status: 'Completed',
        Completed_At__c: now,
        Completed_By__c: USER_ID
      }
    }));

    try {
      await Promise.all(updates);
    } catch (error) {
      console.error('[Orchestrator] Error marking WorkSteps complete:', JSON.stringify(error));
    }
  }

  async persistFieldUpdates(fieldUpdates) {
    try {
      const fields = { ...fieldUpdates };
      fields[WO_ID.fieldApiName] = this.recordId;
      await updateRecord({ fields });
    } catch (error) {
      console.error('[Orchestrator] Error persisting field updates:', JSON.stringify(error));
      this.showAlert('Error', 'Failed to save data', 'error');
    }
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

  async showAlert(label, message, theme = 'info') {
    await Alert.open({ label, message, theme });
  }
}
