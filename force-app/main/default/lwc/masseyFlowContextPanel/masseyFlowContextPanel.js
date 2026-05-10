import { LightningElement, api, wire } from 'lwc';
import { getRecord } from 'lightning/uiRecordApi';
import { getRelatedListRecords } from 'lightning/uiRelatedListApi';
import ASSET_NAME_FIELD from '@salesforce/schema/Asset.Name';
import ASSET_SERIAL_NUMBER_FIELD from '@salesforce/schema/Asset.SerialNumber';
import ASSET_STATUS_FIELD from '@salesforce/schema/Asset.Status';
import ASSET_INSTALL_DATE_FIELD from '@salesforce/schema/Asset.InstallDate';
import ASSET_LATITUDE_FIELD from '@salesforce/schema/Asset.Latitude';
import ASSET_LONGITUDE_FIELD from '@salesforce/schema/Asset.Longitude';
import ASSET_SERVICE_LINE_FIELD from '@salesforce/schema/Asset.Service_Line__c';
import ASSET_SERVICE_GROUP_FIELD from '@salesforce/schema/Asset.Service_Group__c';
import ASSET_NFC_TAG_FIELD from '@salesforce/schema/Asset.NFC_Tag_Id__c';

const ASSET_FIELDS = [
  ASSET_NAME_FIELD,
  ASSET_SERIAL_NUMBER_FIELD,
  ASSET_STATUS_FIELD,
  ASSET_INSTALL_DATE_FIELD,
  ASSET_LATITUDE_FIELD,
  ASSET_LONGITUDE_FIELD,
  ASSET_SERVICE_LINE_FIELD,
  ASSET_SERVICE_GROUP_FIELD,
  ASSET_NFC_TAG_FIELD
];

const ACTIVE_STATUSES = ['New', 'In Progress', 'Open', 'Dispatched'];
const COMPLETED_STATUSES = ['Completed', 'Closed', 'Canceled'];

export default class MasseyFlowContextPanel extends LightningElement {
  @api workOrderId;
  @api assetId;
  @api isOpen = false;

  // Massey-specific context fields surfaced by the orchestrator. Hidden when
  // not provided. There's no PMT capital-program analogue in pest — see
  // docs/PEST_NARRATIVE.md § Capital Programs for the rationale.
  @api routeName;
  @api branchName;
  @api quarterlyCadence;

  assetData = {};
  workOrders = [];
  isLoadingAsset = false;
  isLoadingWorkOrders = false;

  @wire(getRecord, { recordId: '$assetId', fields: ASSET_FIELDS })
  wiredAsset({ data, error }) {
    this.isLoadingAsset = true;
    if (data) {
      this.assetData = this.formatAssetData(data);
      this.isLoadingAsset = false;
    } else if (error) {
      console.error('[ContextPanel] Error loading asset:', JSON.stringify(error));
      this.assetData = {};
      this.isLoadingAsset = false;
    }
  }

  @wire(getRelatedListRecords, {
    parentRecordId: '$assetId',
    relatedListId: 'WorkOrders',
    fields: ['WorkOrder.Id', 'WorkOrder.WorkOrderNumber', 'WorkOrder.Status', 'WorkOrder.StartDate', 'WorkOrder.EndDate', 'WorkOrder.Subject'],
    sortBy: ['-WorkOrder.StartDate'],
    pageSize: 5
  })
  wiredWorkOrders({ data, error }) {
    this.isLoadingWorkOrders = true;
    if (data) {
      this.workOrders = this.formatWorkOrders(data.records);
      this.isLoadingWorkOrders = false;
    } else if (error) {
      console.error('[ContextPanel] Error loading work orders:', JSON.stringify(error));
      this.workOrders = [];
      this.isLoadingWorkOrders = false;
    }
  }

  formatAssetData(data) {
    return {
      id: data.id,
      name: data.fields.Name?.value || '',
      serialNumber: data.fields.SerialNumber?.value || '',
      status: data.fields.Status?.value || '',
      installDate: data.fields.InstallDate?.value || '',
      latitude: data.fields.Latitude?.value || '',
      longitude: data.fields.Longitude?.value || '',
      serviceLine: data.fields.Service_Line__c?.value || '',
      route: data.fields.Service_Group__c?.value || '',
      branch: '',
      nfcTagId: data.fields.NFC_Tag_Id__c?.value || ''
    };
  }

  formatWorkOrders(records) {
    if (!records || records.length === 0) return [];
    return records.map((record) => {
      const fields = record.fields;
      const status = fields.Status?.value || '';
      return {
        id: fields.Id?.value || '',
        workOrderNumber: fields.WorkOrderNumber?.value || '',
        status,
        startDate: fields.StartDate?.value || '',
        endDate: fields.EndDate?.value || '',
        subject: fields.Subject?.value || '',
        dateRange: this.formatDateRange(fields.StartDate?.value, fields.EndDate?.value),
        statusBadgeClass: this.computeStatusBadgeClass(status)
      };
    });
  }

  handleBackdropClick() {
    this.dispatchEvent(new CustomEvent('close'));
  }

  handleCloseButtonClick() {
    this.dispatchEvent(new CustomEvent('close'));
  }

  handlePanelClick(event) {
    event.stopPropagation();
  }

  get panelClasses() {
    return `panel ${this.isOpen ? 'open' : 'closed'}`;
  }

  get backdropClasses() {
    return `backdrop ${this.isOpen ? 'visible' : 'hidden'}`;
  }

  get hasNfcTag() {
    return !!this.assetData.nfcTagId;
  }

  get hasRouteContext() {
    return !!(this.routeName || this.branchName || this.quarterlyCadence);
  }

  get formattedInstallDate() {
    if (!this.assetData.installDate) return '';
    const date = new Date(this.assetData.installDate);
    return date.toLocaleDateString('en-US', { year: 'numeric', month: 'short', day: 'numeric' });
  }

  get hasWorkOrders() {
    return this.workOrders.length > 0;
  }

  get statusBadgeClass() {
    return this.computeStatusBadgeClass(this.assetData.status);
  }

  computeStatusBadgeClass(status) {
    if (ACTIVE_STATUSES.includes(status)) return 'badge badge-active';
    if (COMPLETED_STATUSES.includes(status)) return 'badge badge-inactive';
    return 'badge badge-default';
  }

  formatDateRange(startDate, endDate) {
    if (!startDate) return '';
    const start = new Date(startDate);
    const startStr = start.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: '2-digit' });
    if (!endDate) return startStr;
    const end = new Date(endDate);
    const endStr = end.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: '2-digit' });
    return `${startStr} - ${endStr}`;
  }
}
