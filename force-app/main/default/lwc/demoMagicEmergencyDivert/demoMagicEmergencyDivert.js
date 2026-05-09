import { LightningElement, api, wire } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import Alert from 'lightning/alert';
import divert from '@salesforce/apex/EmergencyDivertOrchestrator.divertFromLwc';
import getDivertCandidates from '@salesforce/apex/EmergencyDivertOrchestrator.getDivertCandidates';

export default class DemoMagicEmergencyDivert extends LightningElement {
  @api recordId;
  @api objectApiName;

  isRunning = false;
  result;
  selectedResourceId;
  selectedIncidentId;
  candidateOptions = [];

  // If we are on an Incident page, pre-fill incidentId; if on a ServiceResource, pre-fill resource.
  connectedCallback() {
    if (this.objectApiName === 'Incident') {
      this.selectedIncidentId = this.recordId;
    } else if (this.objectApiName === 'ServiceResource') {
      this.selectedResourceId = this.recordId;
    }
  }

  @wire(getDivertCandidates)
  wiredCandidates({ data, error }) {
    if (data) {
      this.candidateOptions = data;
    } else if (error) {
      // eslint-disable-next-line no-console
      console.error('candidates error', JSON.stringify(error));
    }
  }

  get resourceOptions() {
    return (this.candidateOptions?.serviceResources || []).map(r => ({
      label: r.name + (r.activeAssignmentCount > 0 ? ' (' + r.activeAssignmentCount + ' active)' : ' (idle)'),
      value: r.id
    }));
  }

  get incidentOptions() {
    return (this.candidateOptions?.incidents || []).map(i => ({
      label: i.subject,
      value: i.id
    }));
  }

  get isResourceLocked() {
    return this.objectApiName === 'ServiceResource';
  }

  get isIncidentLocked() {
    return this.objectApiName === 'Incident';
  }

  handleResourceChange(event) { this.selectedResourceId = event.detail.value; }
  handleIncidentChange(event) { this.selectedIncidentId = event.detail.value; }

  async handleDivert() {
    if (!this.selectedResourceId || !this.selectedIncidentId) {
      await Alert.open({ label: 'Missing input', message: 'Pick both a Service Resource and an Incident.' });
      return;
    }
    this.isRunning = true;
    try {
      const requests = [{
        serviceResourceId: this.selectedResourceId,
        incidentId: this.selectedIncidentId,
        deferReason: 'Emergency Divert'
      }];
      const responses = await divert({ requests });
      this.result = responses[0];
      await Alert.open({
        label: 'Emergency Reassign Complete',
        message: this.result.message
      });
      this.dispatchEvent(new CloseActionScreenEvent());
    } catch (e) {
      await Alert.open({ label: 'Error', message: e?.body?.message || JSON.stringify(e) });
    } finally {
      this.isRunning = false;
    }
  }

  handleClose() {
    this.dispatchEvent(new CloseActionScreenEvent());
  }
}
