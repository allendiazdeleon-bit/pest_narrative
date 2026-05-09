import { LightningElement, api } from "lwc";

const DEFAULT_COLOR = "#0070d2";

/**
 * sparklineChart — pure-SVG mini chart for trend lines.
 *
 * Domain-neutral. Used across masseyFlow to render pest pressure trends,
 * bait-station hits over a quarterly cycle, soil-temp rolling averages,
 * trap-catch counts, and other small-multiples telemetry displayed
 * inside cards (e.g., Customer 360, Property Hierarchy hover, Branch
 * Operations dashboard).
 *
 * Public API:
 *   @api data            — number[] historical samples (left to right)
 *   @api predictionData  — number[] future predicted samples (rendered dashed)
 *   @api referenceLine   — number; horizontal threshold line (e.g., 70 for "elevated pest pressure")
 *   @api width / height  — SVG dimensions in px
 *   @api color           — line color
 *   @api fillColor       — area fill (defaults to color at 18% alpha)
 *   @api showLastValue   — render the last numeric sample to the right
 *   @api lastValueLabel  — small unit suffix appended to the last value (e.g. "Pest Pressure")
 */
export default class SparklineChart extends LightningElement {
	@api width = 200;
	@api height = 40;
	@api color = DEFAULT_COLOR;
	@api fillColor;
	_showLastValue = true;
	@api
	get showLastValue() {
		return this._showLastValue;
	}
	set showLastValue(value) {
		this._showLastValue = value !== false;
	}
	@api lastValueLabel;

	_data = [];
	_predictionData = [];
	_referenceLine;

	@api
	get data() {
		return this._data;
	}
	set data(value) {
		this._data = Array.isArray(value)
			? value.filter((v) => typeof v === "number" && Number.isFinite(v))
			: [];
	}

	@api
	get predictionData() {
		return this._predictionData;
	}
	set predictionData(value) {
		this._predictionData = Array.isArray(value)
			? value.filter((v) => typeof v === "number" && Number.isFinite(v))
			: [];
	}

	@api
	get referenceLine() {
		return this._referenceLine;
	}
	set referenceLine(value) {
		const num = Number(value);
		this._referenceLine = Number.isFinite(num) ? num : undefined;
	}

	// ---- derived geometry ----

	get viewBox() {
		return `0 0 ${this.width} ${this.height}`;
	}

	get _padY() {
		return 2;
	}

	get _allPoints() {
		// data + prediction sit on the same Y scale
		return [...(this._data || []), ...(this._predictionData || [])];
	}

	get _yRange() {
		const pts = this._allPoints;
		if (this._referenceLine !== undefined) {
			pts.push(this._referenceLine);
		}
		if (pts.length === 0) {
			return { min: 0, max: 1 };
		}
		const min = Math.min(...pts);
		const max = Math.max(...pts);
		if (min === max) {
			return { min: min - 1, max: max + 1 };
		}
		return { min, max };
	}

	_yFor(value) {
		const { min, max } = this._yRange;
		const usable = this.height - this._padY * 2;
		const ratio = (value - min) / (max - min);
		return this.height - this._padY - ratio * usable;
	}

	_xFor(index, totalPoints) {
		if (totalPoints <= 1) return 0;
		// reserve right margin for the value label if visible
		const reserved = this.showLastValue && this._data.length ? 36 : 4;
		const usable = Math.max(1, this.width - reserved);
		return (index / (totalPoints - 1)) * usable;
	}

	get hasData() {
		return this._data && this._data.length > 0;
	}

	get hasPrediction() {
		return this._predictionData && this._predictionData.length > 0;
	}

	get hasReferenceLine() {
		return this._referenceLine !== undefined;
	}

	get totalPoints() {
		return this._data.length + this._predictionData.length;
	}

	get linePath() {
		if (!this.hasData) return "";
		const total = this.totalPoints;
		return this._data
			.map((v, i) => {
				const x = this._xFor(i, total).toFixed(2);
				const y = this._yFor(v).toFixed(2);
				return `${i === 0 ? "M" : "L"}${x},${y}`;
			})
			.join(" ");
	}

	get areaPath() {
		if (!this.hasData) return "";
		const total = this.totalPoints;
		const baselineY = (this.height - this._padY).toFixed(2);
		const firstX = this._xFor(0, total).toFixed(2);
		const lastIdx = this._data.length - 1;
		const lastX = this._xFor(lastIdx, total).toFixed(2);
		const linePart = this._data
			.map((v, i) => {
				const x = this._xFor(i, total).toFixed(2);
				const y = this._yFor(v).toFixed(2);
				return `${i === 0 ? "M" : "L"}${x},${y}`;
			})
			.join(" ");
		return `${linePart} L${lastX},${baselineY} L${firstX},${baselineY} Z`;
	}

	get predictionPath() {
		if (!this.hasPrediction) return "";
		const total = this.totalPoints;
		const lastDataIdx = this._data.length - 1;
		const segments = [];
		// connect last real point to first predicted point
		if (this.hasData) {
			const lx = this._xFor(lastDataIdx, total).toFixed(2);
			const ly = this._yFor(this._data[lastDataIdx]).toFixed(2);
			segments.push(`M${lx},${ly}`);
		}
		this._predictionData.forEach((v, i) => {
			const idx = this._data.length + i;
			const x = this._xFor(idx, total).toFixed(2);
			const y = this._yFor(v).toFixed(2);
			segments.push(
				`${segments.length === 0 && i === 0 ? "M" : "L"}${x},${y}`
			);
		});
		return segments.join(" ");
	}

	get referenceLineY() {
		if (!this.hasReferenceLine) return 0;
		return this._yFor(this._referenceLine).toFixed(2);
	}

	get effectiveFillColor() {
		if (this.fillColor) return this.fillColor;
		return this._toRgba(this.color || DEFAULT_COLOR, 0.18);
	}

	get predictionColor() {
		return this._toRgba(this.color || DEFAULT_COLOR, 0.55);
	}

	_toRgba(hexOrColor, alpha) {
		if (typeof hexOrColor !== "string") return `rgba(0,112,210,${alpha})`;
		const m = hexOrColor.replace("#", "");
		if (m.length !== 6) return `rgba(0,112,210,${alpha})`;
		const r = parseInt(m.slice(0, 2), 16);
		const g = parseInt(m.slice(2, 4), 16);
		const b = parseInt(m.slice(4, 6), 16);
		if ([r, g, b].some(Number.isNaN)) return `rgba(0,112,210,${alpha})`;
		return `rgba(${r},${g},${b},${alpha})`;
	}

	// ---- last-value label ----

	get lastValueDisplay() {
		if (!this.showLastValue || !this.hasData) return "";
		const v = this._data[this._data.length - 1];
		const formatted =
			Math.abs(v) >= 100
				? Math.round(v).toString()
				: (Math.round(v * 10) / 10).toString();
		return this.lastValueLabel
			? `${formatted} ${this.lastValueLabel}`
			: formatted;
	}

	get lastValueX() {
		if (!this.hasData) return 0;
		const total = this.totalPoints;
		const lastIdx = this._data.length - 1;
		return Math.min(this.width - 2, this._xFor(lastIdx, total) + 4).toFixed(2);
	}

	get lastValueY() {
		if (!this.hasData) return 0;
		const v = this._data[this._data.length - 1];
		return this._yFor(v).toFixed(2);
	}

	get rootStyle() {
		return `width:${this.width}px;height:${this.height}px;`;
	}
}
