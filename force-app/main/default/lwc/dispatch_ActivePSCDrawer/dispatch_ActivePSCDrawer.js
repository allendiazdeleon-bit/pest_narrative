import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getActiveIncidents from '@salesforce/apex/DispatcherSummaryService.getActiveIncidents';
import LBL_ACTIVE_CLUSTER_EVENTS from '@salesforce/label/c.MasseyFlow_ServiceImpact_Active';
import LBL_AFFECTED_PROPERTIES from '@salesforce/label/c.MasseyFlow_Affected_Properties_Label';
import LBL_EMPTY_NO_CLUSTERS from '@salesforce/label/c.MasseyFlow_Empty_NoIncidents';

export default class DispatchActivePscDrawer extends NavigationMixin(LightningElement) {
  incidents = [];

  labelDrawerHeader = LBL_ACTIVE_CLUSTER_EVENTS;
  labelEmpty = LBL_EMPTY_NO_CLUSTERS;
  labelAffected = LBL_AFFECTED_PROPERTIES;

  @wire(getActiveIncidents)
  wiredIncidents({ data }) {
    if (data) {
      this.incidents = data.map(i => ({
        ...i,
        priorityClass: this._priorityClass(i.priority),
        createdDateFmt: this._formatDate(i.createdDate),
        affectedDisplay: `${i.affectedCustomers ?? 0} ${this.labelAffected.toLowerCase()}`
      }));
    }
  }

  get hasIncidents() {
    return this.incidents.length > 0;
  }

  handleIncidentClick(event) {
    const incidentId = event.currentTarget.dataset.id;
    this[NavigationMixin.Navigate]({
      type: 'standard__recordPage',
      attributes: {
        recordId: incidentId,
        objectApiName: 'Incident',
        actionName: 'view'
      }
    });
  }

  _priorityClass(p) {
    const u = (p || '').toUpperCase();
    if (u.includes('CRITICAL') || u.includes('HIGH')) return 'pill pill-critical';
    if (u.includes('MEDIUM') || u.includes('MAJOR')) return 'pill pill-major';
    return 'pill pill-normal';
  }

  _formatDate(dt) {
    if (!dt) return '';
    const d = new Date(dt);
    return d.toLocaleString('en-US', { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' });
  }
}
