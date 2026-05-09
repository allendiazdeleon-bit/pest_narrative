import { LightningElement, api, wire, track } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import Alert from 'lightning/alert';

import previewForWorkOrder from '@salesforce/apex/ImpactPreviewService.previewForWorkOrder';
import generateNotification from '@salesforce/apex/ImpactPreviewService.generateNotification';

// Incident fields — repurposed for cluster events (e.g., elevated mosquito
// pressure ZIP-32828, ant call cluster on a route). API names retained per
// Decision #20.
import INC_ID from '@salesforce/schema/Incident.Id';
import INC_SUBJECT from '@salesforce/schema/Incident.Subject';
import INC_STATUS from '@salesforce/schema/Incident.StatusCode';
import INC_PRIORITY from '@salesforce/schema/Incident.Priority';
import INC_CREATED_DATE from '@salesforce/schema/Incident.CreatedDate';
import INC_AFFECTED from '@salesforce/schema/Incident.Affected_Customers__c';
import INC_DESCRIPTION from '@salesforce/schema/Incident.Description';

import WO_LINKED_INCIDENT from '@salesforce/schema/WorkOrder.Linked_Incident__c';
import WO_PEST_FINDING from '@salesforce/schema/WorkOrder.Pest_Finding__c';
import WO_ASSET_ID from '@salesforce/schema/WorkOrder.AssetId';
import ASSET_SERVICE_LINE from '@salesforce/schema/Asset.Service_Line__c';

import LBL_PAGE_TITLE from '@salesforce/label/c.MasseyFlow_ServiceImpact_PageTitle';
import LBL_HISTORY from '@salesforce/label/c.MasseyFlow_ServiceImpact_History_Heading';
import LBL_ACTIVE from '@salesforce/label/c.MasseyFlow_ServiceImpact_Active';
import LBL_EMPTY from '@salesforce/label/c.MasseyFlow_Empty_NoIncidents';
import LBL_ANOMALY from '@salesforce/label/c.MasseyFlow_AnomalySignal';
import LBL_AFFECTED_PROPS from '@salesforce/label/c.MasseyFlow_Affected_Properties_Label';
import LBL_CLUSTER_ID from '@salesforce/label/c.MasseyFlow_Cluster_Identifier_Label';

// Pest finding causes — what the tech observed at the property that may
// have triggered or contributed to a route-level cluster signal.
const FINDING_OPTIONS = [
    'Conducive Conditions Found',
    'Active Infestation Confirmed',
    'Sentricon Hit',
    'Bait Station Activity',
    'Standing Water Source Found',
    'Mound / Nest Located',
    'Customer-Reported Sighting',
    'No Pest Activity'
];

const PRIORITY_COLOR_MAP = {
    'Critical': '#DC2626',
    'High': '#DC2626',
    'Major': '#F59E0B',
    'Medium': '#F59E0B',
    'Normal': '#2E7D32',
    'Low': '#2E7D32'
};

const ACTIVE_STATUSES = ['New', 'In Progress', 'Active'];

export default class MasseyFlowServiceImpactStep extends LightningElement {
    @api recordId;
    @api workOrder;
    @api incidents = [];
    @api serviceLineOverride;

    @track selectedIncidentId = null;
    @track linkedIncidentId = null;
    @track selectedFinding = null;
    @track selfAssetId = null;
    @track selfServiceLine = null;

    label = {
        stepTitle: LBL_PAGE_TITLE,
        historyHeading: LBL_HISTORY,
        activeLabel: LBL_ACTIVE,
        emptyMessage: LBL_EMPTY,
        anomalySignal: LBL_ANOMALY,
        affectedProperties: LBL_AFFECTED_PROPS,
        clusterIdentifier: LBL_CLUSTER_ID
    };

    connectedCallback() {
        if (this.workOrder) {
            this.linkedIncidentId = this.workOrder.Linked_Incident__c || null;
            this.selectedFinding = this.workOrder.Pest_Finding__c || null;
        }
    }

    @wire(getRecord, { recordId: '$recordId', fields: [WO_ASSET_ID] })
    wiredWorkOrder({ data }) {
        if (data) {
            this.selfAssetId = getFieldValue(data, WO_ASSET_ID) || null;
            if (!this.impactSummary && !this.impactSummaryLoading) {
                this.loadImpactSummary();
            }
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

    get isPest() { return this.effectiveServiceLine === 'GoGreen Pest'; }
    get isTermite() { return this.effectiveServiceLine === 'Termite Protection'; }
    get isMosquito() { return this.effectiveServiceLine === 'Mosquito Hunter'; }
    get isLawn() { return this.effectiveServiceLine === 'Lawn Service'; }

    get hasIncidents() { return this.incidents && this.incidents.length > 0; }

    get incidentList() {
        if (!this.incidents || this.incidents.length === 0) return [];

        return this.incidents.map(incident => {
            const isActive = this._isActiveStatus(incident.StatusCode);
            const priorityClass = this._getPriorityClass(incident.Priority);
            const statusClass = this._getStatusClass(incident.StatusCode);
            const priorityColor = PRIORITY_COLOR_MAP[incident.Priority] || '#2E7D32';

            return {
                id: incident.Id,
                subject: incident.Subject,
                status: incident.StatusCode,
                priority: incident.Priority,
                createdDate: this._formatDate(incident.CreatedDate),
                propertiesAffected: incident.Affected_Customers__c || 0,
                clusterId: incident.Cluster_Identifier__c || 'Unknown',
                description: incident.Description || 'No description provided',
                isActive,
                priorityClass,
                statusClass,
                priorityColor,
                isSelected: incident.Id === this.selectedIncidentId,
                isLinked: incident.Id === this.linkedIncidentId
            };
        });
    }

    get activeIncidentCount() {
        return this.incidents.filter(inc => this._isActiveStatus(inc.StatusCode)).length;
    }

    get totalPropertiesAffected() {
        return this.incidents.reduce((sum, inc) => {
            if (this._isActiveStatus(inc.StatusCode)) {
                return sum + (inc.Affected_Customers__c || 0);
            }
            return sum;
        }, 0);
    }

    get longestDuration() {
        const activeIncidents = this.incidents.filter(inc => this._isActiveStatus(inc.StatusCode));
        if (activeIncidents.length === 0) return 'N/A';

        const oldestDate = new Date(
            Math.min(...activeIncidents.map(inc => new Date(inc.CreatedDate).getTime()))
        );
        const now = new Date();
        const diffMinutes = Math.floor((now - oldestDate) / (1000 * 60));

        if (diffMinutes < 60) return `${diffMinutes}m`;
        const diffHours = Math.floor(diffMinutes / 60);
        if (diffHours < 24) return `${diffHours}h`;
        const diffDays = Math.floor(diffHours / 24);
        return `${diffDays}d`;
    }

    get findingOptions() {
        return FINDING_OPTIONS.map(finding => ({
            label: finding,
            isSelected: finding === this.selectedFinding,
            buttonClass: finding === this.selectedFinding
                ? 'cause-btn cause-btn-selected'
                : 'cause-btn'
        }));
    }

    handleIncidentClick(event) {
        const incidentId = event.currentTarget.dataset.id;
        this.selectedIncidentId = this.selectedIncidentId === incidentId ? null : incidentId;
    }

    handleLinkIncident(event) {
        event.stopPropagation();
        const incidentId = event.currentTarget.dataset.id;
        this.linkedIncidentId = incidentId;

        const payload = { fields: { Linked_Incident__c: incidentId } };
        this.dispatchEvent(new CustomEvent('stepdatasave', { detail: payload }));
    }

    handleFindingSelect(event) {
        const finding = event.currentTarget.dataset.cause;
        this.selectedFinding = finding;

        const payload = { fields: { Pest_Finding__c: finding } };
        this.dispatchEvent(new CustomEvent('stepdatasave', { detail: payload }));
    }

    _isActiveStatus(status) { return ACTIVE_STATUSES.includes(status); }

    _getPriorityClass(priority) {
        const upper = (priority || '').toUpperCase();
        if (upper.includes('CRITICAL') || upper.includes('HIGH')) return 'badge-critical';
        if (upper.includes('MAJOR') || upper.includes('MEDIUM')) return 'badge-major';
        return 'badge-normal';
    }

    _getStatusClass(status) {
        return this._isActiveStatus(status) ? 'badge-active' : 'badge-restored';
    }

    _formatDate(dateStr) {
        if (!dateStr) return 'Unknown';
        const date = new Date(dateStr);
        return date.toLocaleDateString('en-US', {
            month: 'short', day: 'numeric',
            hour: '2-digit', minute: '2-digit'
        });
    }

    // ── Impact preview / customer notification ────────────────────────
    @track impactAction;
    @track impactSummary;
    @track impactSummaryLoading = false;
    @track lastNotificationId;
    @track notifying = false;

    get hasImpactSummary() { return !!this.impactSummary; }

    get impactActionOptions() {
        const actions = [
            'Notify Affected Properties',
            'Schedule Follow-Up Visits',
            'Increase Treatment Frequency',
            'Escalate to Branch Manager'
        ];
        const active = this.impactAction || 'Notify Affected Properties';
        return actions.map((a) => ({
            value: a,
            buttonClass: a === active ? 'impact-action-btn impact-action-active' : 'impact-action-btn'
        }));
    }

    handlePickImpactAction(event) {
        this.impactAction = event.currentTarget.dataset.value;
        this.loadImpactSummary();
    }

    async loadImpactSummary() {
        if (!this.recordId) return;
        const action = this.impactAction || 'Notify Affected Properties';
        this.impactSummaryLoading = true;
        try {
            const s = await previewForWorkOrder({ workOrderId: this.recordId, actionType: action });
            this.impactSummary = {
                ...s,
                propertiesAffected: (s.affectedCustomers || []).map((c) => ({
                    ...c,
                    priorityClass: this.priorityClassFor(c.priority)
                })),
                durationDisplay: this.formatDurationMinutes(s.durationEstimateMinutes)
            };
        } catch (e) {
            console.error('[ServiceImpactStep] impact preview failed:', JSON.stringify(e));
        } finally {
            this.impactSummaryLoading = false;
        }
    }

    priorityClassFor(p) {
        if (p === 'Critical') return 'subs-prio subs-prio-critical';
        if (p === 'Vulnerable') return 'subs-prio subs-prio-vulnerable';
        return 'subs-prio subs-prio-standard';
    }

    formatDurationMinutes(m) {
        if (!m) return '—';
        if (m < 60) return `${m} min`;
        const hrs = Math.floor(m / 60);
        const mins = m % 60;
        return mins ? `${hrs}h ${mins}m` : `${hrs}h`;
    }

    get impactCriticalFlagsList() {
        return this.impactSummary?.criticalFlags || [];
    }

    async handleGenerateNotification() {
        if (!this.recordId) return;
        const action = this.impactAction || 'Notify Affected Properties';
        this.notifying = true;
        try {
            const pscId = await generateNotification({
                workOrderId: this.recordId,
                actionType: action
            });
            this.lastNotificationId = pscId;
            await Alert.open({
                label: 'Notification Drafted',
                message: `A property notification has been drafted for ${this.impactSummary.affectedCount} accounts via ${this.impactSummary.recommendedNotificationChannel}. Lead time: ${this.impactSummary.notificationLeadTimeMinutes} minutes.`
            });
        } catch (e) {
            await Alert.open({ label: 'Notification error', message: e?.body?.message || JSON.stringify(e) });
        } finally {
            this.notifying = false;
        }
    }

    get notifyButtonLabel() {
        if (this.notifying) return 'Drafting…';
        if (this.lastNotificationId) return 'Notification drafted ✓';
        const count = this.impactSummary?.affectedCount || 0;
        return `Notify ${count} properties via Agentic SMS`;
    }

    get notifyDisabled() {
        return this.notifying || !this.impactSummary || this.impactSummary.affectedCount === 0;
    }

    renderedCallback() {
        if (this.recordId && !this.impactSummary && !this.impactSummaryLoading) {
            this.loadImpactSummary();
        }
    }
}
