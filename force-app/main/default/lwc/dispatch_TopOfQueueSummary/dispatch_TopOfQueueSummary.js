import { LightningElement, wire } from 'lwc';
import getSummary from '@salesforce/apex/DispatcherSummaryService.getSummary';
import LBL_ACTIVE_CLUSTER_EVENTS from '@salesforce/label/c.MasseyFlow_ServiceImpact_Active';
import LBL_AFFECTED_PROPERTIES from '@salesforce/label/c.MasseyFlow_Affected_Properties_Label';

export default class DispatchTopOfQueueSummary extends LightningElement {
  summary;
  error;

  labelActiveClusters = LBL_ACTIVE_CLUSTER_EVENTS;
  labelAffectedProperties = LBL_AFFECTED_PROPERTIES;

  @wire(getSummary)
  wiredSummary({ data, error }) {
    if (data) {
      this.summary = data;
      this.error = null;
    } else if (error) {
      this.error = JSON.stringify(error);
    }
  }

  get marginClass() {
    return `margin-pill margin-${this.summary?.marginIndicator || 'green'}`;
  }

  get openSaCount() { return this.summary?.openSaCount ?? '—'; }
  get activeIncidents() { return this.summary?.activeIncidentCount ?? '—'; }
  get affected() { return this.summary?.affectedCustomersTotal ?? '—'; }
  get capacityPct() { return this.summary?.capacityPctUsed ?? '—'; }
}
