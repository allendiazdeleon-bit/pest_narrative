import { LightningElement, api, wire, track } from "lwc";
import getTopologyAroundAsset from "@salesforce/apex/PropertyTreatmentHistoryService.getTopologyAroundAsset";

// Equipment type to short on-node glyph (kept inline-SVG, no external icons)
const GLYPH_BY_TYPE = {
	Property: "PRP",
	Sentricon_Station: "STN",
	Mosquito_System: "MSQ",
	Mosquito_Nozzle: "NZL",
	Trap: "TRP",
	Treatment_Perimeter: "PER"
};

// Layout columns by node type — left to right (root → endpoint).
// Property is the root; perimeter/nozzle legs sit one column out;
// stations/systems/traps are the endpoints.
const COLUMN_BY_TYPE = {
	Property: 0,
	Treatment_Perimeter: 1,
	Mosquito_Nozzle: 1,
	Sentricon_Station: 2,
	Mosquito_System: 2,
	Trap: 2
};

// Service-line color tokens (left bar accent on each node)
const COLOR_BY_SERVICE_LINE = {
	Pest: "#0176d3", // SLDS brand blue
	Termite: "#a05a2c", // termite brown
	Mosquito: "#5b21b6", // mosquito purple
	Lawn: "#2e844a" // lawn green
};

// State color tokens (overrides service-line color when escalated)
const COLOR_HEAVY_ACTIVITY = "#ea001e"; // SLDS error red — Bait_Station_State__c = 'Heavy_Activity'
const COLOR_ACTIVITY = "#fe9339"; // SLDS warning amber — 'Activity'
const COLOR_REPLACED = "#9ca3af"; // gray — recently replaced station
const COLOR_UNTOUCHED = "#2e844a"; // green — clean station
const COLOR_UNKNOWN = "#9ca3af";
const COLOR_RING = "#0176d3"; // highlight ring (SLDS brand)

export default class AssetHierarchyVisualizer extends LightningElement {
	@api recordId;
	@api compact = false;
	@api serviceLine; // optional explicit override; otherwise inferred from topology
	_showLegend = true;
	@api
	get showLegend() {
		return this._showLegend;
	}
	set showLegend(value) {
		this._showLegend = value !== false;
	}
	@api highlightAffectedProperties = false;

	topology;
	error;
	selectedNodeId;

	@wire(getTopologyAroundAsset, { assetId: "$recordId" })
	wiredTopology({ data, error }) {
		if (data) {
			this.topology = data;
			this.error = undefined;
		} else if (error) {
			this.topology = undefined;
			this.error = this._formatError(error);
		}
	}

	// --- Derived layout ----------------------------------------------------

	get nodeWidth() {
		return this.compact ? 96 : 140;
	}
	get nodeHeight() {
		return this.compact ? 36 : 52;
	}
	get hSpacing() {
		return this.compact ? 60 : 90;
	}
	get vSpacing() {
		return this.compact ? 12 : 20;
	}

	get hasTopology() {
		return !!this.topology && Array.isArray(this.topology.nodes) && this.topology.nodes.length > 0;
	}
	get hasError() {
		return !!this.error;
	}

	get rootClass() {
		return this.compact ? "tree-root tree-root--compact" : "tree-root";
	}

	get nodes() {
		if (!this.hasTopology) return [];
		const cols = this._groupByColumn(this.topology.nodes);
		const colCount = Object.keys(cols).length;
		const out = [];
		const w = this.nodeWidth;
		const h = this.nodeHeight;
		const hs = this.hSpacing;
		const vs = this.vSpacing;

		const padX = 16;
		const padY = 16;

		const sortedColIdx = Object.keys(cols)
			.map((k) => Number(k))
			.sort((a, b) => a - b);

		sortedColIdx.forEach((colIdx) => {
			const list = cols[colIdx];
			list.forEach((n, rowIdx) => {
				const x = padX + colIdx * (w + hs);
				const y = padY + rowIdx * (h + vs);
				const color = this._colorForNode(n);
				const ring = this.highlightAffectedProperties && this._isPropertyEndpoint(n)
					? COLOR_RING
					: null;
				const selected = this.selectedNodeId && this.selectedNodeId === n.id;
				out.push({
					...n,
					x,
					y,
					cx: x + w / 2,
					cy: y + h / 2,
					rightX: x + w,
					rightY: y + h / 2,
					leftX: x,
					leftY: y + h / 2,
					iconHref: this._iconHref(n.nodeType),
					iconX: x + 10,
					iconY: y + h / 2 - 8,
					labelX: x + 32,
					labelY: y + h / 2 - 4,
					typeX: x + 32,
					typeY: y + h / 2 + 12,
					color,
					ringColor: ring,
					boxClass: selected ? "node-box node-box--selected" : "node-box",
					typeLabel: this._typeLabel(n),
					primaryLabel: this._primaryLabel(n)
				});
			});
		});

		this._lastColCount = colCount;
		this._lastMaxRows = Math.max(1, ...sortedColIdx.map((c) => cols[c].length));

		return out;
	}

	get edges() {
		if (!this.hasTopology) return [];
		const nodeMap = {};
		this.nodes.forEach((n) => (nodeMap[n.id] = n));
		const edgesIn = this.topology.edges || [];
		return edgesIn
			.map((e, idx) => {
				const fromKey = e.fromNodeId || e.fromId;
				const toKey = e.toNodeId || e.toId;
				const from = nodeMap[fromKey];
				const to = nodeMap[toKey];
				if (!from || !to) return null;
				const isPerimeter = e.edgeType === "Perimeter";
				return {
					key: `${e.id || idx}-${fromKey}-${toKey}`,
					x1: from.rightX,
					y1: from.rightY,
					x2: to.leftX,
					y2: to.leftY,
					stroke: isPerimeter ? "#475569" : "#94a3b8",
					dasharray: isPerimeter ? "0" : "4 3",
					strokeWidth: isPerimeter ? 2 : 1.25,
					midX: (from.rightX + to.leftX) / 2,
					midY: (from.rightY + to.leftY) / 2 - 4,
					spec: e.spec || "",
					hasSpec: !!e.spec && !this.compact
				};
			})
			.filter((e) => e !== null);
	}

	@track zoom = 0.5;

	get svgWidth() {
		const cols = this._lastColCount || 3;
		return 32 + cols * (this.nodeWidth + this.hSpacing);
	}
	get svgHeight() {
		const rows = this._lastMaxRows || 1;
		return 32 + rows * (this.nodeHeight + this.vSpacing);
	}
	get svgViewBox() {
		return `0 0 ${this.svgWidth} ${this.svgHeight}`;
	}
	get scaledSvgWidth() { return Math.round(this.svgWidth * this.zoom); }
	get scaledSvgHeight() { return Math.round(this.svgHeight * this.zoom); }
	get zoomLabel() { return Math.round(this.zoom * 100) + "%"; }
	get scrollerStyle() {
		return this.zoom > 1 ? "overflow: auto; -webkit-overflow-scrolling: touch;" : "";
	}

	handleZoomIn() {
		this.zoom = Math.min(3, +(this.zoom + 0.25).toFixed(2));
	}
	handleZoomOut() {
		this.zoom = Math.max(0.5, +(this.zoom - 0.25).toFixed(2));
	}
	handleZoomReset() {
		this.zoom = 0.5;
	}

	get summaryText() {
		return this.topology && this.topology.summary ? this.topology.summary : "";
	}

	get legendItems() {
		if (!this.showLegend) return [];
		return [
			{ key: "untouched", color: COLOR_UNTOUCHED, label: "Untouched" },
			{ key: "activity", color: COLOR_ACTIVITY, label: "Activity" },
			{ key: "heavy", color: COLOR_HEAVY_ACTIVITY, label: "Heavy activity" },
			{ key: "replaced", color: COLOR_REPLACED, label: "Replaced" },
			{ key: "unk", color: COLOR_UNKNOWN, label: "No reading" }
		];
	}

	get hasLegend() {
		return this.showLegend && this.hasTopology;
	}

	// --- Interactions ------------------------------------------------------

	handleNodeClick(event) {
		const id = event.currentTarget.dataset.id;
		const nodeType = event.currentTarget.dataset.type;
		const assetId = event.currentTarget.dataset.assetid || null;
		this.selectedNodeId = id;
		this.dispatchEvent(
			new CustomEvent("nodeselect", {
				detail: { nodeId: id, assetId, nodeType },
				bubbles: true,
				composed: true
			})
		);
	}

	handleNodeKey(event) {
		if (event.key === "Enter" || event.key === " ") {
			event.preventDefault();
			this.handleNodeClick(event);
		}
	}

	// --- Helpers -----------------------------------------------------------

	_groupByColumn(nodes) {
		const cols = {};
		nodes.forEach((n) => {
			const idx = COLUMN_BY_TYPE[n.nodeType];
			const c = Number.isInteger(idx) ? idx : 2;
			if (!cols[c]) cols[c] = [];
			cols[c].push(n);
		});
		// Stable sort: endpoints by accountName, others by label
		Object.keys(cols).forEach((k) => {
			cols[k].sort((a, b) => {
				const la = (a.accountName || a.label || a.id || "").toString();
				const lb = (b.accountName || b.label || b.id || "").toString();
				return la.localeCompare(lb);
			});
		});
		return cols;
	}

	_iconHref(nodeType) {
		return GLYPH_BY_TYPE[nodeType] || "·";
	}

	_typeLabel(n) {
		// Friendly labels for the small uppercase line under the node name
		switch (n.nodeType) {
			case "Property": return "PROPERTY";
			case "Sentricon_Station": return "SENTRICON";
			case "Mosquito_System": return "MOSQUITO";
			case "Mosquito_Nozzle": return "NOZZLE";
			case "Trap": return "TRAP";
			case "Treatment_Perimeter": return "PERIMETER";
			default: return (n.nodeType || "").toUpperCase();
		}
	}

	_primaryLabel(n) {
		if (this._isPropertyEndpoint(n) && n.accountName) {
			return n.accountName;
		}
		return n.label || n.id || n.nodeType;
	}

	_isPropertyEndpoint(n) {
		return n.nodeType === "Sentricon_Station"
			|| n.nodeType === "Mosquito_System"
			|| n.nodeType === "Trap"
			|| n.nodeType === "Property";
	}

	_colorForNode(n) {
		// Bait_Station_State__c is carried on `n.state` for stations.
		// 'Heavy_Activity' must render red per ticket spec.
		const state = (n.state || "").toString();
		if (state === "Heavy_Activity") return COLOR_HEAVY_ACTIVITY;
		if (state === "Activity") return COLOR_ACTIVITY;
		if (state === "Replaced") return COLOR_REPLACED;
		if (state === "Untouched") return COLOR_UNTOUCHED;

		// Non-station states: 'Active', 'Available', 'Inactive', or empty.
		const lower = state.toLowerCase();
		if (lower === "inactive" || lower === "down" || lower === "fail") return COLOR_HEAVY_ACTIVITY;
		if (lower === "degraded" || lower === "warn") return COLOR_ACTIVITY;
		if (lower === "active" || lower === "available") {
			// fall through to service-line color so the visual reads service-line at a glance
			return COLOR_BY_SERVICE_LINE[this.serviceLine] || COLOR_BY_SERVICE_LINE.Pest;
		}
		return COLOR_UNKNOWN;
	}

	_formatError(err) {
		if (!err) return "Unknown error";
		if (err.body && err.body.message) return err.body.message;
		if (typeof err.message === "string") return err.message;
		return JSON.stringify(err);
	}
}
