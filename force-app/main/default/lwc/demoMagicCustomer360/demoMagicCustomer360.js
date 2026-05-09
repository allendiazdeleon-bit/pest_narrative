import { LightningElement, api, track, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { getRelatedListRecords } from 'lightning/uiRelatedListApi';

import ACCOUNT_NAME from '@salesforce/schema/Account.Name';
import ACCOUNT_PHONE from '@salesforce/schema/Account.Phone';
import ACCOUNT_EMAIL from '@salesforce/schema/Account.PersonEmail';
import ACCOUNT_CITY from '@salesforce/schema/Account.BillingCity';
import ACCOUNT_CREATED from '@salesforce/schema/Account.CreatedDate';
import ACCOUNT_LAST_UPSELL_LINE from '@salesforce/schema/Account.Last_Upsell_Service_Line__c';
import ACCOUNT_LAST_UPSELL_OUTCOME from '@salesforce/schema/Account.Last_Upsell_Outcome__c';
import ACCOUNT_UPSELL_SCORE from '@salesforce/schema/Account.Upsell_Score__c';
import ACCOUNT_UPSELL_SCORE_AT from '@salesforce/schema/Account.Upsell_Score_Last_Updated__c';

const ACCOUNT_FIELDS = [
  ACCOUNT_NAME, ACCOUNT_PHONE, ACCOUNT_EMAIL, ACCOUNT_CITY, ACCOUNT_CREATED,
  ACCOUNT_LAST_UPSELL_LINE, ACCOUNT_LAST_UPSELL_OUTCOME,
  ACCOUNT_UPSELL_SCORE, ACCOUNT_UPSELL_SCORE_AT
];

const CASE_FIELDS = [
  'Case.Id', 'Case.CaseNumber', 'Case.Subject', 'Case.Status',
  'Case.Priority', 'Case.CreatedDate'
];

const WO_FIELDS = [
  'WorkOrder.Id', 'WorkOrder.WorkOrderNumber', 'WorkOrder.Subject',
  'WorkOrder.Status', 'WorkOrder.StartDate', 'WorkOrder.WorkType.Name'
];

const ASSET_FIELDS = [
  'Asset.Id', 'Asset.Name', 'Asset.Service_Line__c',
  'Asset.Bait_Station_State__c', 'Asset.Last_Bait_Station_Hit_Date__c',
  'Asset.Soil_Temp_F__c', 'Asset.Conducive_Conditions__c',
  'Asset.Conducive_Notes__c', 'Asset.Last_Quarterly_Service_Date__c'
];

const SERVICE_TIERS = [
  { name: 'GoGreen Pest',          cls: 'tier-pill tier-pest' },
  { name: 'Termite Protection',    cls: 'tier-pill tier-termite' },
  { name: 'Mosquito Hunter',       cls: 'tier-pill tier-mosquito' },
  { name: 'Lawn Service',          cls: 'tier-pill tier-lawn' }
];

// Map an Asset.Service_Line__c value to a display tier pill.
function _tierForLine(line) {
  if (line === 'Termite') return SERVICE_TIERS[1];
  if (line === 'Mosquito') return SERVICE_TIERS[2];
  if (line === 'Lawn') return SERVICE_TIERS[3];
  return SERVICE_TIERS[0]; // Pest / GoGreen default
}

export default class DemoMagicCustomer360 extends LightningElement {
  @api recordId;

  account = {};
  cases = [];
  workOrders = [];
  assets = [];

  @track upsellHistory;

  // ---- Wires ----------------------------------------------------------------

  @wire(getRecord, { recordId: '$recordId', fields: ACCOUNT_FIELDS })
  wiredAccount({ data, error }) {
    if (data) {
      this.account = {
        name: getFieldValue(data, ACCOUNT_NAME),
        phone: getFieldValue(data, ACCOUNT_PHONE),
        email: getFieldValue(data, ACCOUNT_EMAIL),
        city: getFieldValue(data, ACCOUNT_CITY),
        createdDate: getFieldValue(data, ACCOUNT_CREATED)
      };
      this.upsellHistory = {
        lastLine: getFieldValue(data, ACCOUNT_LAST_UPSELL_LINE),
        lastOutcome: getFieldValue(data, ACCOUNT_LAST_UPSELL_OUTCOME),
        score: getFieldValue(data, ACCOUNT_UPSELL_SCORE),
        scoredAt: this._formatDate(getFieldValue(data, ACCOUNT_UPSELL_SCORE_AT))
      };
    } else if (error) {
      // eslint-disable-next-line no-console
      console.error('[Customer360] Account error', JSON.stringify(error));
    }
  }

  @wire(getRelatedListRecords, {
    parentRecordId: '$recordId',
    relatedListId: 'Cases',
    fields: CASE_FIELDS,
    sortBy: ['-Case.CreatedDate'],
    pageSize: 3
  })
  wiredCases({ data }) {
    if (data && data.records) {
      this.cases = data.records.map(r => ({
        id: r.id,
        caseNumber: r.fields.CaseNumber?.value,
        subject: r.fields.Subject?.value,
        status: r.fields.Status?.value,
        priority: r.fields.Priority?.value,
        createdDate: this._formatDate(r.fields.CreatedDate?.value)
      }));
    }
  }

  @wire(getRelatedListRecords, {
    parentRecordId: '$recordId',
    relatedListId: 'WorkOrders',
    fields: WO_FIELDS,
    sortBy: ['-WorkOrder.StartDate'],
    pageSize: 5
  })
  wiredWorkOrders({ data }) {
    if (data && data.records) {
      this.workOrders = data.records.map(r => ({
        id: r.id,
        woNumber: r.fields.WorkOrderNumber?.value,
        subject: r.fields.Subject?.value,
        status: r.fields.Status?.value,
        startDate: this._formatDate(r.fields.StartDate?.value),
        workType: r.fields.WorkType?.displayValue
      }));
    }
  }

  @wire(getRelatedListRecords, {
    parentRecordId: '$recordId',
    relatedListId: 'Assets',
    fields: ASSET_FIELDS,
    pageSize: 5
  })
  wiredAssets({ data }) {
    if (data && data.records) {
      this.assets = data.records.map(r => {
        const f = r.fields;
        const line = f.Service_Line__c?.value || 'Pest';
        const tier = _tierForLine(line);
        return {
          id: r.id,
          name: f.Name?.value,
          serviceLine: line,
          tierName: tier.name,
          tierClass: tier.cls,
          baitState: f.Bait_Station_State__c?.value,
          lastBaitHit: this._formatDate(f.Last_Bait_Station_Hit_Date__c?.value),
          soilTempF: f.Soil_Temp_F__c?.value,
          conducive: f.Conducive_Conditions__c?.value === true,
          conduciveNotes: f.Conducive_Notes__c?.value,
          lastQuarterly: this._formatDate(f.Last_Quarterly_Service_Date__c?.value)
        };
      });
    }
  }

  // ---- Header KPI tiles -----------------------------------------------------

  get tenureLabel() {
    if (!this.account?.createdDate) return '-';
    const created = new Date(this.account.createdDate);
    const yrs = (Date.now() - created.getTime()) / (1000 * 60 * 60 * 24 * 365.25);
    return yrs.toFixed(1) + ' yrs';
  }

  // Distinct service lines this customer is on, e.g. "GoGreen Pest, Termite".
  get serviceTierSummary() {
    if (!this.assets.length) return '-';
    const lines = [...new Set(this.assets.map(a => a.serviceLine).filter(Boolean))];
    return lines.map(l => _tierForLine(l).name).join(', ');
  }

  get serviceLineCount() {
    if (!this.assets.length) return 0;
    return new Set(this.assets.map(a => a.serviceLine).filter(Boolean)).size;
  }

  // ---- Upsell history card --------------------------------------------------

  get hasUpsellHistory() {
    if (!this.upsellHistory) return false;
    return !!(this.upsellHistory.lastLine || this.upsellHistory.lastOutcome
      || this.upsellHistory.score != null);
  }

  get upsellScoreDisplay() {
    const s = this.upsellHistory?.score;
    return (s == null) ? '-' : Math.round(s);
  }

  get upsellScoreClass() {
    const s = Number(this.upsellHistory?.score || 0);
    if (s >= 70) return 'upsell-score upsell-score-hot';
    if (s >= 40) return 'upsell-score upsell-score-warm';
    return 'upsell-score upsell-score-cold';
  }

  get upsellScoreTier() {
    const s = Number(this.upsellHistory?.score || 0);
    if (s >= 70) return 'Hot';
    if (s >= 40) return 'Warm';
    return 'Cold';
  }

  get upsellOutcomeClass() {
    const o = (this.upsellHistory?.lastOutcome || '').toLowerCase();
    if (o === 'yes') return 'outcome-pill outcome-yes';
    if (o === 'notnow') return 'outcome-pill outcome-notnow';
    if (o === 'notinterested') return 'outcome-pill outcome-no';
    return 'outcome-pill outcome-noresp';
  }

  get upsellOutcomeLabel() {
    const o = this.upsellHistory?.lastOutcome;
    if (o === 'NotNow') return 'Not Now';
    if (o === 'NotInterested') return 'Not Interested';
    if (o === 'NoResponse') return 'No Response';
    return o || '-';
  }

  // ---- Asset / property pest health ----------------------------------------

  get hasAssets() { return this.assets.length > 0; }
  get hasCases() { return this.cases.length > 0; }
  get hasWorkOrders() { return this.workOrders.length > 0; }

  // Banner if any property has rising bait pressure or conducive conditions.
  get hasPressureAlert() {
    return this.assets.some(a =>
      a.baitState === 'Heavy_Activity' || a.baitState === 'Activity' || a.conducive === true
    );
  }

  get pressureAlertCopy() {
    const heavy = this.assets.filter(a => a.baitState === 'Heavy_Activity').length;
    const conducive = this.assets.filter(a => a.conducive === true).length;
    const parts = [];
    if (heavy > 0) parts.push(heavy + ' propert' + (heavy === 1 ? 'y' : 'ies') + ' with heavy Sentricon bait station activity');
    if (conducive > 0) parts.push(conducive + ' propert' + (conducive === 1 ? 'y' : 'ies') + ' with conducive termite conditions');
    if (parts.length === 0) return '';
    return 'Elevated pest pressure on this account: ' + parts.join('; ') + '. Recommend a Booster Inspection.';
  }

  // ---- Misc helpers --------------------------------------------------------

  _formatDate(dateStr) {
    if (!dateStr) return '';
    const d = new Date(dateStr);
    if (isNaN(d.getTime())) return '';
    return d.toLocaleDateString('en-US', {
      month: 'short', day: 'numeric', year: 'numeric'
    });
  }
}
