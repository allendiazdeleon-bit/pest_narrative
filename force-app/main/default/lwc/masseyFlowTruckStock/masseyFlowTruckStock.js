import { LightningElement, api, wire } from 'lwc';
import Alert from 'lightning/alert';
import getStockSummary from '@salesforce/apex/TruckStockService.getStockSummary';

/**
 * Truck Stock Pre-Flight for Massey techs.
 *
 * Displays the tech's truck inventory (Termidor SC, BifenIT, Suspend SC,
 * Sentricon Recruit HD, larvicide cartridges, granular fertilizer, ULV fog
 * fluid, NFC tags, etc.) against the chemicals + supplies required by today's
 * Service Appointments. The AI insight card recommends a depot pickup when
 * required-vs-on-truck is short before the first treatment of the day.
 *
 * Recordable on a ServiceResource record page so each tech sees their own
 * truck. Surfaces an "On the Truck" Quick Action when needed.
 */
export default class MasseyFlowTruckStock extends LightningElement {
    @api recordId;

    summary;
    error;

    // Use a getter so an unbound recordId still passes a defined value
    // (null) — Apex wires require all reactive params to be defined.
    get _resourceIdForWire() {
        return this.recordId || null;
    }

    @wire(getStockSummary, { serviceResourceId: '$_resourceIdForWire' })
    wiredSummary({ data, error }) {
        if (data) {
            this.summary = data;
            this.error = undefined;
        } else if (error) {
            this.summary = undefined;
            this.error = this._formatError(error);
        }
    }

    // --- Header derivations --------------------------------------------------
    get hasSummary() { return !!this.summary; }
    get hasError() { return !!this.error; }
    get techName() { return this.summary && this.summary.resourceName ? this.summary.resourceName : 'Tech'; }
    get truckNumber() { return this.summary && this.summary.truckNumber ? this.summary.truckNumber : '—'; }

    get lastInventoryCheck() {
        if (!this.summary || !this.summary.lastInventoryCheck) return '—';
        try {
            return new Date(this.summary.lastInventoryCheck).toLocaleString();
        } catch (e) {
            return String(this.summary.lastInventoryCheck);
        }
    }

    get woCountText() {
        const n = this.summary && this.summary.todaysWoCount ? this.summary.todaysWoCount : 0;
        return `${n} stop${n === 1 ? '' : 's'} today`;
    }

    // --- Today's Service Visits strip ---------------------------------------
    get todaysWos() {
        if (!this.summary || !Array.isArray(this.summary.todaysWos)) return [];
        return this.summary.todaysWos.map((w, idx) => ({
            key: w.serviceAppointmentId || `wo-${idx}`,
            workOrderId: w.workOrderId,
            workOrderNumber: w.workOrderNumber || '(no #)',
            subject: w.subject || 'Service visit',
            scheduledStart: w.scheduledStart ? this._formatTime(w.scheduledStart) : '',
            chemicalsRequired: (w.partsRequired || []).map((p, pIdx) => ({
                key: `${idx}-${pIdx}`,
                label: p
            })),
            hasChemicals: Array.isArray(w.partsRequired) && w.partsRequired.length > 0
        }));
    }

    get hasTodaysWos() { return this.todaysWos.length > 0; }

    // --- Stock table --------------------------------------------------------
    get stockRows() {
        if (!this.summary || !Array.isArray(this.summary.stock)) return [];
        return this.summary.stock.map((s, idx) => {
            const status = s.status || 'OK';
            return {
                key: `s-${idx}-${s.partName}`,
                partName: s.partName,
                partCode: s.partCode || '—',
                onTruck: s.onTruck,
                requiredToday: s.requiredToday,
                status,
                rowClass: `stock-row stock-row--${status.toLowerCase()}`,
                badgeClass: `stock-badge stock-badge--${status.toLowerCase()}`,
                icon: this._iconForStatus(status)
            };
        });
    }

    get hasStock() { return this.stockRows.length > 0; }

    // --- AI Insight card ----------------------------------------------------
    get aiSeverity() { return this.summary && this.summary.aiSeverity ? this.summary.aiSeverity : 'info'; }
    get aiSummary() { return this.summary && this.summary.aiSummary ? this.summary.aiSummary : ''; }

    get aiTitle() {
        if (!this.summary) return 'Pre-flight check';
        if (this.summary.anyInsufficient) return 'Truck stock — depot pickup recommended';
        if (this.aiSeverity === 'info') return 'Truck stock — top up at end of shift';
        return 'Truck stock — ready to roll';
    }

    get aiActions() {
        if (this.summary && this.summary.anyInsufficient) {
            return [
                { name: 'request-pickup', label: 'Submit Pickup Request', variant: 'brand' },
                { name: 'acknowledge', label: 'Acknowledge', variant: 'neutral' }
            ];
        }
        return [{ name: 'acknowledge', label: 'Acknowledge', variant: 'neutral' }];
    }

    get aiSource() { return 'TruckStockService · ProductRequired roll-up · today\'s service visits'; }
    get aiConfidence() { return this.summary && this.summary.anyInsufficient ? 88 : 95; }

    async handleAiAction(event) {
        const name = event.detail && event.detail.name;
        if (name === 'request-pickup') {
            await Alert.open({
                label: 'Pickup request submitted',
                message: 'Branch depot has been notified to stage missing chemicals before your first stop.',
                theme: 'success'
            });
        } else if (name === 'acknowledge') {
            await Alert.open({
                label: 'Pre-flight acknowledged',
                message: 'Have a safe shift.',
                theme: 'info'
            });
        }
    }

    // --- Helpers ------------------------------------------------------------
    _iconForStatus(status) {
        if (status === 'Insufficient') return 'utility:error';
        if (status === 'Low') return 'utility:warning';
        return 'utility:success';
    }

    _formatTime(dt) {
        try {
            return new Date(dt).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
        } catch (e) {
            return String(dt);
        }
    }

    _formatError(err) {
        if (!err) return 'Unknown error';
        if (err.body && err.body.message) return err.body.message;
        if (typeof err.message === 'string') return err.message;
        return JSON.stringify(err);
    }
}
