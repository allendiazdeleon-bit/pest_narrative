import { LightningElement, api } from "lwc";

const SEVERITY_ICONS = {
	info: "utility:info",
	warning: "utility:warning",
	critical: "utility:error",
	success: "utility:success"
};

const ALLOWED_SEVERITIES = ["info", "warning", "critical", "success"];

/**
 * aiInsightCard — reusable card for an Agentforce / Einstein insight.
 *
 * Domain-neutral. Used by the masseyFlow orchestrator and the Branch
 * Operations dashboard to surface pest-pressure scoring, cluster
 * detection, upsell prompts, and conducive-condition warnings.
 *
 * Sample insights this card renders in the demo:
 *   - "Pest pressure score 72 (up from 41 last visit)"
 *   - "3 of 4 Sentricon stations on north perimeter showing termite activity"
 *   - "Neighboring property added Mosquito Hunter last month — pitch?"
 *
 * Public API:
 *   @api title       — heading
 *   @api summary     — body copy
 *   @api source      — attribution chip (e.g. "PestPressureAnalyzer")
 *   @api timestamp   — ISO datetime; rendered as relative time
 *   @api confidence  — 0-100; drives the bottom progress bar
 *   @api severity    — info / warning / critical / success
 *   @api details     — Array<{label,value}> shown as small chips
 *   @api actions     — Array<{name,label,variant}> rendered as buttons
 *
 * Events:
 *   aiaction — fired with {detail:{name}} when an action button is clicked
 */
export default class AiInsightCard extends LightningElement {
	@api title;
	@api summary;
	@api source;
	@api timestamp;

	_confidence = 80;
	_severity = "info";
	_actions = [];
	_details = [];

	@api
	get confidence() {
		return this._confidence;
	}
	set confidence(value) {
		const num = Number(value);
		if (Number.isFinite(num)) {
			this._confidence = Math.max(0, Math.min(100, num));
		}
	}

	@api
	get severity() {
		return this._severity;
	}
	set severity(value) {
		if (ALLOWED_SEVERITIES.includes(value)) {
			this._severity = value;
		} else {
			this._severity = "info";
		}
	}

	@api
	get actions() {
		return this._actions;
	}
	set actions(value) {
		this._actions = Array.isArray(value) ? value : [];
	}

	@api
	get details() {
		return this._details;
	}
	set details(value) {
		this._details = Array.isArray(value) ? value : [];
	}

	get cardClass() {
		return `ai-card severity-${this._severity}`;
	}

	get severityIcon() {
		return SEVERITY_ICONS[this._severity] || SEVERITY_ICONS.info;
	}

	get hasDetails() {
		return this._details && this._details.length > 0;
	}

	get hasActions() {
		return this._actions && this._actions.length > 0;
	}

	get hasSource() {
		return !!this.source;
	}

	get hasTimestamp() {
		return !!this.timestamp;
	}

	get confidenceStyle() {
		return `width:${this._confidence}%;`;
	}

	get confidenceLabel() {
		return `${Math.round(this._confidence)}% confidence`;
	}

	get decoratedActions() {
		return (this._actions || []).map((a, idx) => ({
			key: `${a.name || "action"}-${idx}`,
			label: a.label,
			name: a.name,
			variant: a.variant || "neutral"
		}));
	}

	get relativeTime() {
		if (!this.timestamp) {
			return "";
		}
		const then = new Date(this.timestamp).getTime();
		if (Number.isNaN(then)) {
			return String(this.timestamp);
		}
		const diffSec = Math.max(0, Math.floor((Date.now() - then) / 1000));
		if (diffSec < 5) return "just now";
		if (diffSec < 60) return `${diffSec} seconds ago`;
		const min = Math.floor(diffSec / 60);
		if (min < 60) return `${min} minute${min === 1 ? "" : "s"} ago`;
		const hr = Math.floor(min / 60);
		if (hr < 24) return `${hr} hour${hr === 1 ? "" : "s"} ago`;
		const day = Math.floor(hr / 24);
		return `${day} day${day === 1 ? "" : "s"} ago`;
	}

	handleActionClick(event) {
		const name = event.currentTarget.dataset.name;
		this.dispatchEvent(
			new CustomEvent("aiaction", {
				detail: { name },
				bubbles: true,
				composed: true
			})
		);
	}
}
