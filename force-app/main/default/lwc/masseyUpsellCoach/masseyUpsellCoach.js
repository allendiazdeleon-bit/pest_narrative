/**
 * masseyUpsellCoach
 *
 * Net-new for the Massey lifecycle (no analogue in prior demos). Load-bearing LWC
 * for the marquee Scene 5 — Maria pitches Mosquito Hunter to the Bennett family
 * because their neighbors signed up.
 *
 * Surfaces in 3 places (per ARCHITECTURE_PROPOSAL § 11):
 *   1. Site step of orchestrator       — variant="compact" (top recommendation, talk-track collapsed)
 *   2. Summary step of orchestrator    — variant="full"    (all recommendations + capture buttons)
 *   3. Account standalone Quick Action — variant="full"    (Jordan / Ray view)
 *
 * Public API:
 *   @api accountId  — required; Account to recommend for
 *   @api variant    — 'compact' (default) | 'full'
 *
 *   Dispatches: 'outcomecaptured' (composed, bubbles)
 *               detail = { accountId, serviceLine, outcome, leadId }
 *
 * Offline contract (ARCHITECTURE_PROPOSAL § 6.2):
 *   - recommend() is @AuraEnabled(cacheable=true) → wired and primable.
 *   - captureOutcome() Apex is invoked imperatively *online only*; if it fails
 *     (offline or other), we fall back to a draft Lead via createRecord and
 *     queue an Account update for Last_Upsell_*__c — both go through the platform
 *     draft queue and sync when back online.
 *   - No platformShowToastEvent, no record-form, no datatable — Komaci-clean.
 */
import { LightningElement, api, wire, track } from 'lwc';
import { createRecord, updateRecord } from 'lightning/uiRecordApi';
import recommend from '@salesforce/apex/UpsellCoachService.recommend';
import captureOutcomeApex from '@salesforce/apex/UpsellCoachService.captureOutcome';

import HEADING from '@salesforce/label/c.MasseyUpsell_Heading';
import EMPTY_ALL_LINES from '@salesforce/label/c.MasseyUpsell_Empty_AllLines';
import LOADING from '@salesforce/label/c.MasseyUpsell_Loading';
import ERROR_LOAD from '@salesforce/label/c.MasseyUpsell_Error';
import TALK_TRACK_HEADING from '@salesforce/label/c.MasseyUpsell_TalkTrack_Heading';
import TALK_TRACK_FALLBACK from '@salesforce/label/c.MasseyUpsell_TalkTrack_Fallback';
import ACTION_YES from '@salesforce/label/c.MasseyUpsell_Action_Yes';
import ACTION_NOT_NOW from '@salesforce/label/c.MasseyUpsell_Action_NotNow';
import ACTION_NOT_INTERESTED from '@salesforce/label/c.MasseyUpsell_Action_NotInterested';
import ACTION_NO_RESPONSE from '@salesforce/label/c.MasseyUpsell_Action_NoResponse';
import ACTION_COPY from '@salesforce/label/c.MasseyUpsell_Action_Copy';
import COPIED_CONFIRMATION from '@salesforce/label/c.MasseyUpsell_Copied_Confirmation';
import CAPTURED_YES from '@salesforce/label/c.MasseyUpsell_Captured_Yes';
import CAPTURED_GENERIC from '@salesforce/label/c.MasseyUpsell_Captured_Generic';
import REASONS_HEADING from '@salesforce/label/c.MasseyUpsell_Reasons_Heading';
import ANNUAL_VALUE_LABEL from '@salesforce/label/c.MasseyUpsell_AnnualValue_Label';
import SCORE_LABEL from '@salesforce/label/c.MasseyUpsell_Score_Label';
import EXPAND_TALK_TRACK from '@salesforce/label/c.MasseyUpsell_Expand_TalkTrack';
import COLLAPSE_TALK_TRACK from '@salesforce/label/c.MasseyUpsell_Collapse_TalkTrack';

// Outcome enum — must match UpsellCoachService.cls validation set exactly.
const OUTCOME_YES = 'Yes';
const OUTCOME_NOT_NOW = 'NotNow';
const OUTCOME_NOT_INTERESTED = 'NotInterested';
const OUTCOME_NO_RESPONSE = 'NoResponse';

// Score thresholds for the badge color band.
//   green  >= 70  — confident pitch
//   amber  40–69  — pitch with judgment
//   red    < 40   — Apex would normally not surface, but we render gracefully if it does
const SCORE_GREEN_FLOOR = 70;
const SCORE_AMBER_FLOOR = 40;

// Brief copy-confirmation flash duration.
const COPY_FLASH_MS = 1500;

export default class MasseyUpsellCoach extends LightningElement {
    /** @type {string} Account Id — required */
    @api accountId;

    /**
     * @type {'compact' | 'full'}
     * compact = Site step embed (top rec only, talk-track collapsed)
     * full    = Summary step embed + Account Quick Action (full list, all buttons)
     */
    @api variant = 'compact';

    // ---- internal state ----
    @track _recommendations = [];
    @track _loaded = false;
    @track _error;
    // serviceLine -> { outcome, leadId, capturedAt } once captured locally.
    @track _captured = {};
    // serviceLine that has its talk-track currently expanded (compact mode).
    @track _expandedLine;
    // serviceLine currently flashing "Copied" confirmation.
    @track _copiedLine;

    label = {
        HEADING,
        EMPTY_ALL_LINES,
        LOADING,
        ERROR_LOAD,
        TALK_TRACK_HEADING,
        TALK_TRACK_FALLBACK,
        ACTION_YES,
        ACTION_NOT_NOW,
        ACTION_NOT_INTERESTED,
        ACTION_NO_RESPONSE,
        ACTION_COPY,
        COPIED_CONFIRMATION,
        CAPTURED_YES,
        CAPTURED_GENERIC,
        REASONS_HEADING,
        ANNUAL_VALUE_LABEL,
        SCORE_LABEL,
        EXPAND_TALK_TRACK,
        COLLAPSE_TALK_TRACK
    };

    // ---- wire ----

    @wire(recommend, { accountId: '$accountId' })
    wiredRecommend({ data, error }) {
        if (data) {
            this._recommendations = data;
            this._error = undefined;
            this._loaded = true;
        } else if (error) {
            this._error = this.extractErrorMessage(error);
            this._recommendations = [];
            this._loaded = true;
        }
    }

    // ---- derived state ----

    get isCompact() {
        return this.variant !== 'full';
    }

    get isFull() {
        return this.variant === 'full';
    }

    get isLoading() {
        return !this._loaded;
    }

    get hasError() {
        return !!this._error;
    }

    get hasRecommendations() {
        return Array.isArray(this._recommendations) && this._recommendations.length > 0;
    }

    get showEmpty() {
        return this._loaded && !this._error && !this.hasRecommendations;
    }

    /**
     * Decorate each recommendation for the template:
     *  - score badge color class
     *  - whether captured (and the confirmation copy)
     *  - whether the talk-track is expanded (compact mode)
     *  - per-card key-stable button data
     *  - safe fallback for talk-track when MDT didn't return one
     */
    get decoratedRecommendations() {
        if (!this.hasRecommendations) {
            return [];
        }
        // Compact mode: only the top recommendation. Apex sorts desc by score
        // with deterministic tie-break by serviceLine ASC, so [0] is stable.
        const source = this.isCompact ? this._recommendations.slice(0, 1) : this._recommendations;
        return source.map((r) => this.decorateOne(r));
    }

    decorateOne(rec) {
        const captured = this._captured[rec.serviceLine];
        const expanded = !this.isCompact || this._expandedLine === rec.serviceLine;
        const score = Number.isFinite(rec.score) ? rec.score : 0;
        const talkTrack = rec.suggestedTalkTrack && rec.suggestedTalkTrack.trim().length > 0
            ? rec.suggestedTalkTrack
            : this.label.TALK_TRACK_FALLBACK;

        let scoreBandClass = 'score-badge score-red';
        if (score >= SCORE_GREEN_FLOOR) {
            scoreBandClass = 'score-badge score-green';
        } else if (score >= SCORE_AMBER_FLOOR) {
            scoreBandClass = 'score-badge score-amber';
        }

        const reasonChips = (rec.reasonCodes || []).map((code, idx) => ({
            key: `${rec.serviceLine}-reason-${idx}`,
            // Reason codes are SCREAMING_SNAKE — humanize for display.
            label: this.humanizeReason(code)
        }));

        const annualValueDisplay = (rec.estimatedAnnualValue !== null
                                    && rec.estimatedAnnualValue !== undefined)
            ? this.formatCurrency(rec.estimatedAnnualValue)
            : null;

        return {
            key: rec.serviceLine,
            serviceLine: rec.serviceLine,
            score,
            scoreBandClass,
            reasonChips,
            hasReasons: reasonChips.length > 0,
            talkTrack,
            annualValueDisplay,
            hasAnnualValue: !!annualValueDisplay,
            expanded,
            // Compact-mode toggle visibility: always show the toggle in compact;
            // full mode auto-expands and hides the toggle.
            showToggle: this.isCompact,
            toggleLabel: expanded ? this.label.COLLAPSE_TALK_TRACK : this.label.EXPAND_TALK_TRACK,
            // Capture state.
            captured: !!captured,
            capturedMessage: captured
                ? (captured.outcome === OUTCOME_YES ? this.label.CAPTURED_YES : this.label.CAPTURED_GENERIC)
                : '',
            // Copy-confirmation flash state.
            copied: this._copiedLine === rec.serviceLine,
            // Stable button keys to avoid template warnings.
            yesKey: `${rec.serviceLine}-yes`,
            notNowKey: `${rec.serviceLine}-notnow`,
            notInterestedKey: `${rec.serviceLine}-notint`,
            noResponseKey: `${rec.serviceLine}-noresp`
        };
    }

    // ---- handlers ----

    handleToggleTalkTrack(event) {
        const line = event.currentTarget.dataset.line;
        if (!line) {
            return;
        }
        this._expandedLine = (this._expandedLine === line) ? undefined : line;
    }

    handleCopyTalkTrack(event) {
        const line = event.currentTarget.dataset.line;
        const text = event.currentTarget.dataset.text;
        if (!text) {
            return;
        }
        // Prefer the modern async clipboard API; fall back to a hidden textarea
        // for environments (incl. some FSL Mobile webviews) that block it.
        // Both paths are local-only — no network I/O — so they work offline.
        const flash = () => {
            this._copiedLine = line;
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => {
                if (this._copiedLine === line) {
                    this._copiedLine = undefined;
                }
            }, COPY_FLASH_MS);
        };
        try {
            if (navigator && navigator.clipboard && navigator.clipboard.writeText) {
                navigator.clipboard.writeText(text).then(flash).catch(() => {
                    this.copyFallback(text);
                    flash();
                });
                return;
            }
        } catch (e) {
            // fall through
        }
        this.copyFallback(text);
        flash();
    }

    copyFallback(text) {
        try {
            const ta = document.createElement('textarea');
            ta.value = text;
            ta.setAttribute('readonly', '');
            ta.style.position = 'absolute';
            ta.style.left = '-9999px';
            document.body.appendChild(ta);
            ta.select();
            document.execCommand('copy');
            document.body.removeChild(ta);
        } catch (e) {
            // Last-resort silent fail — copy is a presenter convenience, not load-bearing.
        }
    }

    handleCaptureYes(event) {
        this.captureOutcome(event.currentTarget.dataset.line, OUTCOME_YES);
    }

    handleCaptureNotNow(event) {
        this.captureOutcome(event.currentTarget.dataset.line, OUTCOME_NOT_NOW);
    }

    handleCaptureNotInterested(event) {
        this.captureOutcome(event.currentTarget.dataset.line, OUTCOME_NOT_INTERESTED);
    }

    handleCaptureNoResponse(event) {
        this.captureOutcome(event.currentTarget.dataset.line, OUTCOME_NO_RESPONSE);
    }

    /**
     * Capture an outcome.
     * Online path: imperative Apex call. Stamps Account + spawns Lead on Yes.
     * Offline path (Apex throws): write a draft Lead via createRecord and
     * queue an Account update via updateRecord — both flow through the FSL
     * Mobile draft queue and sync on reconnect.
     */
    captureOutcome(serviceLine, outcome) {
        if (!serviceLine || !outcome || !this.accountId) {
            return;
        }
        // Optimistic local capture — render the confirmation immediately so
        // the tech can move on. We reconcile leadId after the apex/draft path resolves.
        this._captured = {
            ...this._captured,
            [serviceLine]: { outcome, leadId: null, capturedAt: Date.now() }
        };

        captureOutcomeApex({ accountId: this.accountId, serviceLine, outcome })
            .then((leadId) => {
                this._captured = {
                    ...this._captured,
                    [serviceLine]: { outcome, leadId, capturedAt: Date.now() }
                };
                this.fireOutcomeCaptured(serviceLine, outcome, leadId);
            })
            .catch(() => {
                // Offline (or any apex failure): fall back to draft writes.
                this.captureOutcomeOffline(serviceLine, outcome);
            });
    }

    /**
     * Offline fallback. Mirrors UpsellCoachService.captureOutcome's side effects
     * via uiRecordApi:
     *   1. Stamp Account.Last_Upsell_* fields  → updateRecord (draft)
     *   2. If Yes, spawn a draft Lead          → createRecord (draft)
     * Both are enqueued in the platform draft queue and sync when online.
     */
    captureOutcomeOffline(serviceLine, outcome) {
        const nowIso = new Date().toISOString();

        // 1. Account stamp — best effort; if this fails we still try to spawn the Lead.
        const stampFields = {
            Id: this.accountId,
            Last_Upsell_Pitched__c: nowIso,
            Last_Upsell_Service_Line__c: serviceLine,
            Last_Upsell_Outcome__c: outcome,
            Upsell_Score_Last_Updated__c: nowIso
        };
        updateRecord({ fields: stampFields }).catch(() => {
            // Non-fatal — the draft will retry when online.
        });

        if (outcome !== OUTCOME_YES) {
            this.fireOutcomeCaptured(serviceLine, outcome, null);
            return;
        }

        // 2. Draft Lead. We can't read the Account via Apex offline, so we
        // build a minimal Lead with the data we have. Description carries the
        // service line + Account Id so Jordan can hydrate context on follow-up.
        const leadInput = {
            apiName: 'Lead',
            fields: {
                LastName: 'Massey Customer',
                Company: 'Massey Customer',
                Status: 'Open - Not Contacted',
                LeadSource: 'Upsell from Tech Visit',
                Description:
                    'Upsell pitch captured offline. Service line: ' + serviceLine
                    + '. Source Account: ' + this.accountId
                    + '. Talk-track suggested while tech was on-site. Follow up via outbound call queue.'
            }
        };

        createRecord(leadInput)
            .then((rec) => {
                const leadId = rec && rec.id ? rec.id : null;
                this._captured = {
                    ...this._captured,
                    [serviceLine]: { outcome, leadId, capturedAt: Date.now() }
                };
                this.fireOutcomeCaptured(serviceLine, outcome, leadId);
            })
            .catch(() => {
                // Even the draft create failed — surface the error but keep the
                // optimistic captured state so the tech sees their action persisted.
                this._error = this.label.ERROR_LOAD;
                this.fireOutcomeCaptured(serviceLine, outcome, null);
            });
    }

    fireOutcomeCaptured(serviceLine, outcome, leadId) {
        this.dispatchEvent(new CustomEvent('outcomecaptured', {
            detail: {
                accountId: this.accountId,
                serviceLine,
                outcome,
                leadId
            },
            bubbles: true,
            composed: true
        }));
    }

    // ---- helpers ----

    humanizeReason(code) {
        if (!code) {
            return '';
        }
        // SCREAMING_SNAKE → Title Case With Spaces.
        return String(code)
            .toLowerCase()
            .split('_')
            .filter((p) => p.length > 0)
            .map((p) => p.charAt(0).toUpperCase() + p.slice(1))
            .join(' ');
    }

    formatCurrency(num) {
        if (num === null || num === undefined) {
            return null;
        }
        // Intl is available in FSL Mobile webview; fall back to fixed decimal.
        try {
            return new Intl.NumberFormat('en-US', {
                style: 'currency',
                currency: 'USD',
                maximumFractionDigits: 0
            }).format(num);
        } catch (e) {
            return '$' + Math.round(Number(num)).toString();
        }
    }

    extractErrorMessage(error) {
        if (!error) {
            return this.label.ERROR_LOAD;
        }
        if (error.body && error.body.message) {
            return error.body.message;
        }
        if (error.message) {
            return error.message;
        }
        return this.label.ERROR_LOAD;
    }
}
