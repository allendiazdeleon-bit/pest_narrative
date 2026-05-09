import { LightningElement, api } from 'lwc';

const ICON_MAP = {
    shield: '🛡️', people: '👥', location: '📍',
    spray: '🧪', signal: '📡', check: '✅'
};

export default class MasseyFlowStepHeader extends LightningElement {
    @api currentStepIndex = 0;
    @api totalSteps = 6;
    @api stepLabel = '';
    @api stepIcon = '';
    @api workOrderNumber = '';
    @api workOrderSubject = '';

    get stepNumber() {
        return this.currentStepIndex + 1;
    }

    get progressPercent() {
        return this.totalSteps > 0
            ? ((this.currentStepIndex + 1) / this.totalSteps) * 100
            : 0;
    }

    get progressStyle() {
        return `width: ${this.progressPercent}%`;
    }

    get progressText() {
        return `Step ${this.stepNumber} of ${this.totalSteps}`;
    }

    get percentText() {
        return `${Math.round(this.progressPercent)}%`;
    }

    get iconEmoji() {
        return ICON_MAP[this.stepIcon] || '📋';
    }

    handleToggleStepMenu() {
        this.dispatchEvent(new CustomEvent('togglestepmenu', { bubbles: true, composed: true }));
    }

    handleToggleContext() {
        this.dispatchEvent(new CustomEvent('togglecontextpanel', { bubbles: true, composed: true }));
    }
}
