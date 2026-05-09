import { LightningElement, api, wire } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { NavigationMixin } from 'lightning/navigation';
import Alert from 'lightning/alert';
import previewDispatch from '@salesforce/apex/IncidentDispatchService.previewDispatch';
import dispatch from '@salesforce/apex/IncidentDispatchService.dispatch';

const STRATEGIES = [
  {
    label: 'Single Response - 1 root-cause WO',
    value: 'SINGLE_RESPONSE',
    hint: 'Best when the cluster points to one upstream source (clogged storm drain, single breeding site, neighborhood-wide swarm). Sends one crew to the suspected source instead of dispatching to every affected property.'
  },
  {
    label: 'Bundled by Street - 1 WO per street',
    value: 'BUNDLED_BY_SEGMENT',
    hint: 'Groups affected properties by street. Good for phased treatment where different crews work different segments in parallel.'
  },
  {
    label: 'Per-Property Inspection - 1 WO per home',
    value: 'PER_ASSET',
    hint: 'Storm / wide-area mode. Each property gets its own Booster Inspection. Use only when each location truly needs its own visit.'
  }
];

export default class DemoMagicDispatchField extends NavigationMixin(LightningElement) {
  @api recordId;  // Incident Id

  preview;
  strategy = 'SINGLE_RESPONSE';
  workTypeId;
  priority = 'High';
  isDispatching = false;
  phase = 'idle';   // idle | planning | scheduling | done

  @wire(previewDispatch, { incidentId: '$recordId' })
  wiredPreview({ data }) {
    if (data) {
      this.preview = data;
      if (data.workTypes && data.workTypes.length && !this.workTypeId) {
        const main = data.workTypes.find((w) => w.name === 'Mosquito Surge Area Treatment');
        this.workTypeId = main ? main.workTypeId : data.workTypes[0].workTypeId;
      }
    }
  }

  get strategyOptions() {
    return STRATEGIES.map((s) => ({ label: s.label, value: s.value }));
  }
  get strategyHint() {
    return (STRATEGIES.find((s) => s.value === this.strategy) || STRATEGIES[0]).hint;
  }

  get workTypeOptions() {
    if (!this.preview || !this.preview.workTypes) return [];
    return this.preview.workTypes.map((w) => ({ label: w.name, value: w.workTypeId }));
  }

  get priorityOptions() {
    return [
      { label: 'Emergency', value: 'Emergency' },
      { label: 'High', value: 'High' },
      { label: 'Medium', value: 'Medium' },
      { label: 'Low', value: 'Low' }
    ];
  }

  get affectedCount() { return this.preview ? this.preview.affectedAssets.length : 0; }
  get segmentCount() { return this.preview ? this.preview.segmentCount : 0; }

  get woCountPreview() {
    if (this.strategy === 'SINGLE_RESPONSE') return 1;
    if (this.strategy === 'BUNDLED_BY_SEGMENT') return this.segmentCount;
    return this.affectedCount;
  }
  get woCountPreviewText() {
    return 'Will create ' + this.woCountPreview + ' Work Order'
      + (this.woCountPreview === 1 ? '' : 's')
      + ' covering ' + this.affectedCount + ' affected propert'
      + (this.affectedCount === 1 ? 'y' : 'ies') + '.';
  }

  get isPlanning() { return this.phase === 'planning'; }
  get isScheduling() { return this.phase === 'scheduling'; }

  handleStrategy(e) { this.strategy = e.detail.value; }
  handleWorkType(e) { this.workTypeId = e.detail.value; }
  handlePriority(e) { this.priority = e.detail.value; }

  sleep(ms) { return new Promise((r) => setTimeout(r, ms)); }

  async handleDispatch() {
    if (!this.workTypeId) {
      await Alert.open({ label: 'Pick a Work Type', message: 'A Work Type is required.' });
      return;
    }
    this.isDispatching = true;
    try {
      const apiCall = dispatch({
        incidentId: this.recordId,
        strategy: this.strategy,
        workTypeId: this.workTypeId,
        priority: this.priority
      });
      this.phase = 'planning';
      await this.sleep(700);
      this.phase = 'scheduling';
      await this.sleep(700);
      const r = await apiCall;
      this.phase = 'done';

      const msg = 'Dispatched ' + r.workOrdersCreated + ' Work Order'
        + (r.workOrdersCreated === 1 ? '' : 's') + ' and '
        + r.serviceAppointmentsCreated + ' Service Appointment'
        + (r.serviceAppointmentsCreated === 1 ? '' : 's')
        + ' under the ' + this.strategyLabelFor(r.strategy) + ' strategy.\n\n'
        + 'Opening the first Work Order.';
      await Alert.open({ label: 'Field Crew Dispatched', message: msg });

      if (r.workOrderIds && r.workOrderIds.length) {
        this[NavigationMixin.Navigate]({
          type: 'standard__recordPage',
          attributes: {
            recordId: r.workOrderIds[0],
            objectApiName: 'WorkOrder',
            actionName: 'view'
          }
        });
      }
      this.dispatchEvent(new CloseActionScreenEvent());
    } catch (e) {
      await Alert.open({ label: 'Dispatch error', message: e?.body?.message || JSON.stringify(e) });
    } finally {
      this.isDispatching = false;
    }
  }

  strategyLabelFor(value) {
    const s = STRATEGIES.find((x) => x.value === value);
    return s ? s.label.split(' - ')[0] : value;
  }

  handleClose() {
    this.dispatchEvent(new CloseActionScreenEvent());
  }
}
