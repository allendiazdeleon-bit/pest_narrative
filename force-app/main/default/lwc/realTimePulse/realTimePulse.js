import { LightningElement, api } from "lwc";

/**
 * realTimePulse — small "live data" indicator + auto-refresh tick emitter.
 *
 * Renders a pulsing green dot + "Live • updated Xs ago" label. Fires a
 * `tick` CustomEvent on a configurable interval (default 30s) so consumers
 * can call `refreshApex` from their parent.
 *
 * Used across masseyFlow on the Branch Operations dashboard (Ray's
 * Dispatcher Console hat) — online status, route queue size, active
 * cluster events, technician GPS pulse — and on the orchestrator's
 * Service Impact step for the cluster events panel.
 *
 * Public API:
 *   @api lastUpdated — DateTime/timestamp/Date — when consumer last got data
 *   @api intervalSec — refresh tick cadence in seconds (default 30)
 *   @api compact — boolean; render as a small dot only (no label)
 *   @api paused — boolean; suppress tick events while true
 *
 * Events:
 *   tick — fired every intervalSec seconds while not paused
 */
export default class RealTimePulse extends LightningElement {
	@api lastUpdated;
	@api intervalSec = 30;
	@api compact = false;
	@api paused = false;

	_intervalId;
	_clockId;
	_now = Date.now();

	connectedCallback() {
		this._startClock();
		this._startTick();
	}

	disconnectedCallback() {
		this._stopClock();
		this._stopTick();
	}

	renderedCallback() {
		// If paused state flipped, restart timer accordingly.
		if (this.paused && this._intervalId) {
			this._stopTick();
		} else if (!this.paused && !this._intervalId) {
			this._startTick();
		}
	}

	// --- Internal timers ---

	_startClock() {
		// Re-render the relative-time label every second
		this._clockId = setInterval(() => {
			this._now = Date.now();
		}, 1000);
	}

	_stopClock() {
		if (this._clockId) {
			clearInterval(this._clockId);
			this._clockId = null;
		}
	}

	_startTick() {
		if (this.paused) return;
		const ms = Math.max(5, Number(this.intervalSec) || 30) * 1000;
		this._intervalId = setInterval(() => {
			this.dispatchEvent(
				new CustomEvent("tick", {
					detail: { firedAt: new Date().toISOString() },
					bubbles: true,
					composed: true
				})
			);
		}, ms);
	}

	_stopTick() {
		if (this._intervalId) {
			clearInterval(this._intervalId);
			this._intervalId = null;
		}
	}

	// --- Display ---

	get relativeTime() {
		if (!this.lastUpdated) return "—";
		const t =
			typeof this.lastUpdated === "number"
				? this.lastUpdated
				: new Date(this.lastUpdated).getTime();
		if (!t || Number.isNaN(t)) return "—";
		const diffSec = Math.max(0, Math.round((this._now - t) / 1000));
		if (diffSec < 5) return "just now";
		if (diffSec < 60) return `${diffSec}s ago`;
		const mins = Math.round(diffSec / 60);
		if (mins < 60) return `${mins}m ago`;
		const hrs = Math.round(mins / 60);
		return `${hrs}h ago`;
	}

	get dotClass() {
		return this.paused ? "pulse-dot paused" : "pulse-dot";
	}

	get statusLabel() {
		return this.paused ? "Paused" : "Live";
	}

	get rootClass() {
		return this.compact ? "pulse-root compact" : "pulse-root";
	}
}
