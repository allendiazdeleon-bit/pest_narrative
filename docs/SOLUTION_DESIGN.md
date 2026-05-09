# SOLUTION_DESIGN.md — masseyFlow / Massey Services

**Status:** Authored in P6.4 (replaces the P0.2 stub).
**Authoritative for:** long-form solution design — data model rationale, AI surfaces (Agentforce + Sidekick), upsell architecture deep-dive, manager coaching layer, integration points.
**Source-of-truth rank:** #4 (story > architecture > deployment > solution design > execution). See `CLAUDE.md`.
**Sibling docs:** `docs/PEST_NARRATIVE.md` (rank #1, story); `ARCHITECTURE_PROPOSAL.md` (rank #2, architecture); `DEPLOYMENT_INSTRUCTIONS.md` (rank #3, deploy); `docs/BUILD_TICKETS_PEST.md` (rank #5, execution).

This document is the **why** layer. It explains the trade-offs behind the build, names the architectural surfaces a sales engineer must be able to defend in a deep-dive, and threads the revenue-growth lens through every section. Where this doc and `ARCHITECTURE_PROPOSAL.md` overlap, this doc summarizes and cross-references rather than duplicates — when implementing, the architecture proposal is canonical for shapes; this doc is canonical for rationale.

---

## 1. Executive overview

`masseyFlow` is a Salesforce Lightning Web Component suite for the Field Service Mobile app, targeting **Massey Services** — a real, family-owned regional pest, termite, lawn, and mosquito provider headquartered in Orlando, FL. The demo models a single Florida branch operation (Orlando service center, ~20 quarterly pest techs, 1 termite team, 1 mosquito-systems specialist, 1 lawn tech). Brand use is pending legal sign-off — do not present externally without confirmation.

### What this demo shows

The buyer narrative is **revenue growth via cross-sell + attach rate**. Every architectural decision in this build is filtered through that lens (CLAUDE.md § "Revenue-growth lens"):

- Maria the quarterly tech sees an upsell coach card on her tablet at the Bennett residence and pitches Mosquito Hunter — Scene 5, the marquee.
- Jordan the inbound agent sees an upsell card on Sandra's call ("FL termite season starts in 3 weeks; no termite coverage on file") and bundles it with the same-week truck roll — Scene 1.
- Ray the branch ops manager closes the loop on a Manager Coaching dashboard — attach rate by tech, week / month / YTD; "Maria's attach rate is up 18% — Tom's is down — schedule coaching" — Scene 9.

Around that thread, the demo also runs:

- A 6-step offline orchestrator on Work Order, with all 6 child step LWCs separately exposed as Quick Actions so a tech can resume mid-flow when offline.
- A cluster-response anchor scenario — post-storm *Aedes aegypti* surge in ZIP 32828 (Avalon Park / Waterford Lakes), 47 affected properties, 1 Incident + 1 PSC + 8 Cases + ~47 PSCItems + 1 dispatch WO. Pulls Tom's termite team off a Sentricon install and onto an emergency mosquito treatment. Scenes 6–8.
- A proactive pest pressure model — Apex pattern analyzer flags candidate properties from rising Sentricon hits + soil temp + conducive conditions + seasonal multiplier; ProactiveWoGenerator + customer notifications drive Booster Termite Inspection WOs. Out-of-band but seeded.
- A Service Cloud Voice IVR with 8 Agentforce topics + 1 net-new "Upsell Recommendation" topic; an Experience Cloud portal `massey-portal` for new-prospect signup; a Knowledge library of 12 articles authored for Massey topics.

### What this demo does NOT model

- **PMT capital-program bridge — NOT MODELED.** Pest control growth is route-density + attach rate, not multi-month capital builds. The architecture supports it; we explicitly chose not to seed it for this lifecycle. See § 3 below.
- **Wildlife / nuisance animal removal**, **bed bug heat treatment**, **commercial pest control**, **multi-family / HOA contracts**, **real-time route optimization**, **smart bait stations with cellular telemetry**, **lawn precision-application equipment integration** — see `docs/PEST_NARRATIVE.md` § "What's intentionally NOT in the demo." If a prospect asks: "the architecture supports it; we just didn't model it for this demo."

### Third-lifecycle context

This is the **third lifecycle** of a domain-neutral architecture: utility (water + electric LSL replacement) → telco (NeuraFiber FTTH build) → pest (Massey Services). The structural decisions — orchestrator + 6 step LWCs, all 7 launchable as Quick Actions, Asset-anchored telemetry, WorkPlan/WorkStep template-driven checklists, briefcase-primed reads, draft-record writes — survive unchanged across all three. What was swapped each lifecycle: schema, labels, Apex tone, Knowledge articles, Agentforce topics, persona narrative, demo data. The only **net-new architectural surface** in this lifecycle is the upsell + tech-coaching layer (§ 5). The reference repo for inherited patterns lives at `~/Desktop/telcoFlow-neurafiber`.

The first-time reader of this codebase should expect to find:
- ~30 Apex classes whose API names look generic or telco-tinged (`OutageStatusLookup`, `RestorationVerifier`, `LineHealthAnalyzer` → `PestPressureAnalyzer`) — most have been retoned for pest content, a few preserve API names where label swap was cheaper (§ 2).
- An LWC named `masseyFlowServiceImpactStep` whose internal data model still talks about "linked Incident" + "affected count" — that's the Service Impact step, formerly "Outage Step" in telco. Renamed in P5.2 (`a415b0e`).
- A `LOTO_Record__c` object whose label is "Chemical Application Log" — the same blocking-gate UX as utility/telco lock-out/tag-out, repurposed for Restricted-Use Pesticide attestation. § 8.

---

## 2. Data model rationale

### 2.1 Why standard objects, not custom objects

Every transactional entity in this build extends a standard Salesforce object. **No new custom objects** are introduced in this lifecycle — only custom fields on standard objects, plus reused-from-prior-lifecycle custom objects (`LOTO_Record__c`, `Hazard__c`) and Custom Metadata (`Upsell_Talk_Track__mdt`, `Demo_Reply_Outcome__mdt`, `Service_Boundary__mdt`).

Three reasons:

1. **Briefcase priming depth.** Briefcase Builder supports related objects up to 3 levels deep. Custom objects in the relationship chain consume depth quota; standard object reuse keeps the chain shallow (max 3 levels per `ARCHITECTURE_PROPOSAL.md` § 6.4).
2. **FSL Mobile native support.** FSL Mobile's offline runtime, draft record handling, and Komaci priming have first-class support for standard objects (WorkOrder, WorkPlan, WorkStep, Asset, Account, Incident). Custom objects work but require more priming + analyzer ceremony.
3. **Agentforce + Sidekick grounding.** Standard objects come with metadata that Agentforce can ground against without custom topic configuration.

### 2.2 Trade-off vs Communications Cloud / Industry Cloud

We considered Industry Cloud (Service for Field Service vertical templates, pre-built data model). We rejected for this build because:

- Pest control is not a vertical Salesforce ships a template for. The closest fit (Field Service base + Service Cloud) is what we use directly.
- Industry Cloud verticals (Communications, Energy, Utilities) carry schema overhead — extra licensed objects, license-gated APIs — that the demo doesn't earn back.
- The buyer wants to see **Service Cloud Voice + Field Service + Agentforce + Experience Cloud**, all in the standard licensing tier.

If a prospect asks "could you do this in Comms Cloud / Industry Cloud?" — yes; the architecture survives, and the LWC components are domain-neutral enough to slot in.

### 2.3 Per-object decisions

Field counts and full schema live in `ARCHITECTURE_PROPOSAL.md` §§ 4.1–4.5. This section explains **why** each set of fields exists.

#### WorkOrder (7 custom fields, P1.3)

WorkOrder retains only flow-control + cluster-correlation fields. **Telemetry is on Asset**, not WorkOrder, because readings are reusable across visits and support historical trending (a quarterly customer's 30-day Sentricon hit trend is an Asset-level fact, not a WorkOrder-level one).

P1.3 also **dropped** 10 inherited PMT fields (`PMT_Task__c`, `PMT_Project__c`, etc.). § 3 below.

#### WorkPlan / WorkStep / WorkStepTemplate (5 fields on WorkStep, P1.6)

Pre-populated via Work Plan Templates associated to Work Type. The LWC reads + toggles existing WorkStep records — never creates them from scratch. This drastically simplifies the offline story: all checklist data is briefcase-primed. The hierarchy (WorkOrder → WorkPlan → WorkStep) is exactly 2 levels deep — well inside the briefcase 3-level limit.

`Step_Category__c` picklist values were inherited intentionally:
- `Work_DeEnergize` — displayed as **"Pre-Treatment Setup"** via Custom Label
- `Work_ReEnergize` — displayed as **"Post-Treatment Verification"** via Custom Label
- `Safety_Critical`, `Safety_Site`, `Safety_Admin`, `Hazard` — pest-appropriate as-is

API names preserved → no formula churn, no validation rule rewrites, no flow re-deploys downstream. See § 2.4 below.

#### Asset (18 custom fields, P1.2)

Pest-net-new. The full set of telco telemetry fields (`Optical_Rx_Power_dBm__c`, `OTDR_Distance_M__c`, `OLT_Port__c`, `PON_Id__c`, `Network_Domain__c`, etc.) was **dropped** in P1.2 — none deployed in this lifecycle. The pest field set:

- **Service-line discriminant:** `Service_Line__c` (Pest / Termite / Mosquito / Lawn — restricted, required, default Pest). Drives variant rendering across all step LWCs. Replaces telco's `Network_Domain__c` exactly.
- **Termite telemetry:** `Bait_Station_State__c`, `Last_Bait_Station_Hit_Date__c`, `Bait_Station_Hits_30d__c`, `Soil_Temp_F__c`, `Conducive_Conditions__c`, `Conducive_Notes__c`.
- **Mosquito telemetry:** `Trap_Catch_Count_24h__c`.
- **Property characteristics:** `Equipment_Type__c`, `Equipment_Model__c`, `Property_Type__c`, `Lot_Size_Sqft__c`, `Service_Group__c`, `NFC_Tag_Id__c`.
- **Cross-cutting:** `Pest_Pressure_Score__c`, `Last_Treatment_DateTime__c`, `Days_Since_Last_Service__c`, `Is_Pest_Pressure_Candidate__c`, `EPA_Reg_Number_Last_Used__c`.

#### Account (6 custom fields, P1.7) — UPSELL SURFACE, NET-NEW

This is the only Account customization layer that is genuinely net-new vs prior lifecycles. It exists to drive the upsell coaching surface (§ 5):

- `Eligible_Upsells__c` (multi-select picklist: Pest / Termite / Mosquito / Lawn) — the seed-data way to scope which lines the recommender considers.
- `Last_Upsell_Pitched__c`, `Last_Upsell_Service_Line__c`, `Last_Upsell_Outcome__c` — captured on every pitch by `UpsellCoachService.captureOutcome()`. Drives the Manager Coaching dashboard reports.
- `Upsell_Score__c`, `Upsell_Score_Last_Updated__c` — pre-computed score for fast list rendering on dispatcher / agent surfaces. The score is recomputed on demand by `recommend()`; the stamped fields are an optimization.

Briefcase priming path 3 (WorkOrder → Account) is **net-new vs telco** to surface these fields offline on the tech's tablet.

#### Incident (4 custom fields, P1.6)

Standard Service Cloud Incident. Used for cluster correlation. Fields preserved from telco:
- `Circuit__c` (Text 50) — repurposed as cluster identifier (`ZIP-32828-Mosquito`); label "Cluster Identifier".
- `Affected_Customers__c` (Number) — affected property count; label "Affected Properties".
- `Outage_Latitude__c`, `Outage_Longitude__c` (Number 3,7) — GPS centroid for map overlay; labels "Cluster Latitude/Longitude".

API names preserved deliberately. Schema rename would cascade into formula references, validation rules, reports — not worth the churn. New code references API names; UI labels are authoritative. § 2.4 below.

#### ProductServiceCampaign + ProductServiceCampaignItem

Standard Service Cloud — the parent dispatch container for cluster-response. 1 PSC = 47 PSCItems (one per affected property) in the marquee mosquito-surge scenario. No custom fields needed.

#### Case

Standard. 8 cases roll up to 1 Incident in the cluster scenario. No custom fields needed.

#### LOTO_Record__c (Path A — repurposed for RUP attestation, P2.3)

Inherited custom object. Repurposed for Restricted-Use Pesticide attestation. Same blocking-gate UX, different content. § 8 below + § "Locked decisions."

#### Hazard__c (P2.2)

Inherited custom object. Hazard reporting from techs (e.g., aggressive pet on property, locked gate, undisclosed swarm). Pest-appropriate as-is — same shape as utility/telco hazard reports.

### 2.4 Inherited API name preservation policy

Where a label needed to change but a schema migration would be costly, we preserved the API name and swapped the label via Custom Labels in P2.1. Locked-decisions § "Inherited API name preservation" + `ARCHITECTURE_PROPOSAL.md` § 9 (decision #20) are canonical.

Examples:
- `Outage_Latitude__c` / `Outage_Longitude__c` → labels "Cluster Latitude/Longitude"
- `Work_DeEnergize` / `Work_ReEnergize` (Step_Category picklist values) → labels "Pre-Treatment Setup" / "Post-Treatment Verification"
- `Circuit__c` → label "Cluster Identifier"
- `LOTO_Record__c` → label "Chemical Application Log"
- `Energy_Source__c` (on LOTO) → label "Chemical Source", picklist refreshed to chemical products (P2.4)

When reading the code, treat the label as the source of truth for **what the field means in pest** and the API name as a historical artifact.

---

## 3. PMT-not-modeled decision

This is a **load-bearing locked decision** — repeated here for completeness; canonical reference is the "Locked decisions" section at the bottom of this doc + `ARCHITECTURE_PROPOSAL.md` § 9 (decision #17) + `docs/PEST_NARRATIVE.md` § "Capital programs: NOT modeled."

### What was dropped

- All 10 PMT WorkOrder fields: `PMT_Task__c`, `PMT_Project__c`, `PMT_Phase__c`, `Project_Day__c`, `Project_Day_Of_Total__c`, `Children_Completed__c`, `Children_Total__c`, `Project_Pct_Complete__c`, `Defer_Reason__c`, `Work_Order_Coverage_Type__c`.
- `PMTTaskToWorkOrderSpawner.cls` and tests.
- `dispatch_WOProjectContext` LWC.
- The inov8 PMT managed package install in the deployment sequence.

### Why

Pest control growth is **route density + attach rate**, not multi-month capital builds. Telco's PMT was modeling FTTH build projects spawning daily WorkOrders with project-day-of-total context (Day 17 of 60). Pest field service is overwhelmingly recurring quarterly / monthly residential visits — no parent capital project, no day-of-total rollup, no bridge to model. Forcing a PMT analogue would bolt on schema and Apex complexity that does not reinforce Massey's stated revenue-growth priority.

### How Scenes 5 + 7 are rewritten

In telco, Scenes 5 + 7 were PMT-driven (Day-17 fiber-build context, project-aware emergency reassign). In pest:

- **Scene 5 → marquee upsell scene.** Maria pitches Mr. Bennett on Mosquito Hunter while wrapping her quarterly visit. The platform turns every truck roll into a sales conversation. This is now the demo's anchor scene because it maps directly to the buyer priority. See § 5 + `docs/PEST_NARRATIVE.md` Scene 5.
- **Scene 7 → emergency reassign without PMT bridge.** Ray pulls Tom's termite team to mosquito-surge response using straight Field Service reassignment (`EmergencyDivertOrchestrator.divert`). No PMT capital program in the picture. The cluster Incident + PSC structure carries the multi-WO coordination story instead. See `docs/PEST_NARRATIVE.md` Scene 7.

### If a prospect asks

"PMT bridge available — used in our utility and telco demos. Pest control doesn't have a clean capital-program analogue, so for this Massey-targeted demo we focused the architecture on the route + attach-rate motion that maps to your stated priority."

---

## 4. AI surface map

Every place Agentforce / Sidekick / Einstein touches the demo. Per-surface: prompt structure, grounding source, escalation path.

### 4.1 Service Cloud Voice IVR (P4.1, Allen-owned, already provisioned)

Real Voice number, real provisioning (kicked off in P0.0, completed pre-build per commit `f7be0e2`). The IVR routes inbound calls to Agentforce, which:
1. Caller-ID match → Account lookup.
2. Greets caller by name.
3. Invokes the **Pest Inquiry** topic for triage.
4. Hands off to a live agent (Jordan) with structured context attached to the call record.

**What's real:** the Voice number, the IVR routing, the Agentforce greeting. **What's scripted:** topic resolution for the demo flow runs through pre-seeded Demo Reply Outcomes (`Demo_Reply_Outcome.SandraReyes.md-meta.xml` etc.) so the demo is reproducible. § 12 below.

### 4.2 Eight Agentforce topics (P4.2, Allen-owned, admin UI)

Configured in Agentforce Builder, not in code. Each has a system prompt, grounding sources, and escalation criteria. The 8 inherited from prior lifecycles, retoned for pest:

| # | Topic | Purpose | Grounding | Escalation |
|---|-------|---------|-----------|-----------|
| 1 | Pest Inquiry | Triage inbound pest service requests | Knowledge articles K01–K04 + Account history | Agent Sidekick |
| 2 | Service Booking | Suggest available appointment slots | `AppointmentBooker.book` + scheduling policies | Agent if no slot fits |
| 3 | Billing Question | Surface billing summary + recent transactions | Account billing object | Agent for disputes |
| 4 | Technical Escalation | Route to entomology specialist | `EscalationContextBuilder.summarize` output | Entomology queue |
| 5 | Service Status | "Is my tech on the way?" lookup | ServiceAppointment + Asset.Last_Treatment_DateTime__c | Agent if no record |
| 6 | New Prospect Quote | Self-service quote in `massey-portal` | `ServiceAreaValidator.validate` + plan picker | Live agent on bundle questions |
| 7 | Cluster Status Update | Proactive customer notification on cluster Incidents | Linked Incident + PSC | None — read-only |
| 8 | Cancel / Reschedule | `AppointmentRescheduler.reschedule` / `AppointmentCanceler.cancel` | ServiceAppointment | Retention agent if cancellation reason = price |

### 4.3 "Upsell Recommendation" topic — NET-NEW (P4.3, Allen-owned, admin UI)

This is the load-bearing AI addition for this lifecycle. Lets Jordan (or any agent / dispatcher with permission) ask Sidekick from inside any record context:

> "Should I pitch this customer on anything?"

Sidekick invokes `UpsellCoachService.recommend(accountId)` (the `@AuraEnabled(cacheable=true)` method, also invoked by `masseyUpsellCoach` LWC), and renders the top recommendation with talk-track + reason codes + estimated annual value. Sidekick library entry is also configured so Jordan can drag the card into the call summary.

**Grounding:** `Account` (existing service lines via Asset child query), `Upsell_Talk_Track__mdt` (tunable talk-track copy), seasonal logic (FL termite Mar–May, mosquito Apr–Oct), neighborhood signal (same ZIP, mosquito-line count).

**Escalation:** None — the topic is read-only and never auto-pitches. The pitch always happens human-to-customer (Maria says it; Jordan says it). Sidekick suggests, the human delivers.

### 4.4 Sidekick library cards

In addition to the topics above, four Sidekick library cards are pre-seeded for Jordan's Service Console (P4.2 + P4.3):

- **Empathy script card.** "Long-tenure customer, first dispute — open with: 'I see you've been with us 4 years. Let me pull this up right away.'" Grounded on Account tenure + Case history.
- **Retention offer card.** Eligibility computed from `ChurnRiskScorer` output + tenure. One-time service credit suggestion.
- **Photo-ID card.** When Jordan attaches a photo to a Case, Sidekick offers identification via `PhotoAnalysisService.identify` (mocked — § 12).
- **Knowledge suggestion card.** `KnowledgeArticleSuggester.suggest` returns the top-3 articles that match the case description.

### 4.5 Knowledge integration (P2.5, Allen-owned, content authoring)

12 Knowledge articles authored for Massey topics (the article authoring is admin-UI work; the metadata + linkage is in the repo via P2.5 ticket scope). Articles cover:

- **Termite:** subterranean termite signs (K01), Sentricon AlwaysActive overview (K02), Termidor liquid soil treatment (K03), conducive conditions checklist (K04).
- **Mosquito:** *Aedes aegypti* biology + breeding sources (K05), Mosquito Hunter system overview (K06), post-storm surge response (K07).
- **Pest:** ant kitchen-intrusion playbook (K08), German cockroach ID + treatment (K09), wasp / stinging insect handling (K10).
- **Lawn:** chinch bug + sod webworm ID (K11), turf disease (brown patch) (K12).

`KnowledgeArticleSuggester.suggest(caseId)` queries by topic + service line + customer property profile and returns the top-3 ranked articles.

---

## 5. Upsell + tech-coaching architecture deep-dive

This is the load-bearing surface for Massey. If you skip this section, you miss the entire point of the build.

### 5.1 Why a deep architectural surface and not a single feature

The buyer's stated priority is revenue per customer, attach rate per route. A single tacked-on "upsell button" on a screen does not demonstrate platform leverage. Instead, the upsell motion threads across **three personas, three surfaces, one shared service, one shared metadata table, one shared dashboard**:

```
                          UpsellCoachService.cls
                    (recommend + captureOutcome)
                                  │
       ┌──────────────────────────┼──────────────────────────┐
       │                          │                          │
   masseyUpsellCoach LWC    Agentforce "Upsell    Manager Coaching
   (Maria + Tom on tablet)   Recommendation"      dashboard (Ray)
   (Jordan via QA on Acct)    topic (Jordan/Sidekick)  (4 reports)
       │                          │                          │
       └──────────────────────────┼──────────────────────────┘
                                  │
                Account upsell fields (P1.7) — single source of stamped state
                Upsell_Talk_Track__mdt — tunable talk-track copy without redeploy
```

Removing any one surface degrades the demo's revenue story.

### 5.2 `UpsellCoachService.recommend()` — the ranking algorithm

Source: `force-app/main/default/classes/UpsellCoachService.cls` (P3.4, commit `988717d`). Test target ≥85% per CLAUDE.md (load-bearing).

#### Public API

```apex
@AuraEnabled(cacheable=true)
public static List<UpsellRecommendation> recommend(Id accountId)

@AuraEnabled
public static Id captureOutcome(Id accountId, String serviceLine, String outcome)
```

`UpsellRecommendation` DTO: `{ serviceLine, score (0-100), reasonCodes[], suggestedTalkTrack, estimatedAnnualValue }`.

#### Eligibility

1. Load Account + child Assets (one SOQL, with `WITH USER_MODE`).
2. Collect `existingLines` from the Account's Asset records (`Service_Line__c` per Asset).
3. Parse `eligibleLines` from the Account's `Eligible_Upsells__c` multi-select. If blank, default = all 4 lines minus existing lines. Else use the multi-select, minus existing lines.
4. If `eligibleLines` is empty, return empty list.

#### Five scoring inputs

For each eligible line, compute a composite score from (clamped to [0, 100]):

| Component | Weight | Trigger |
|-----------|--------|---------|
| **BASE** | 20 | Every recommendation starts here |
| **NEIGHBOR_HIT** | up to 25 | Mosquito only — count of Accounts in same ZIP with Mosquito Asset, capped at 200. Diminishing returns: 1 neighbor = +9; 3+ neighbors = full +25. |
| **SEASONAL** | 20 | Termite Mar–May / Mosquito Apr–Oct |
| **PROPERTY_FIT** | 15 | Lot size ≥12k sqft for Pest Bifen; lot ≥10k for Mosquito; Trap_Catch_Count_24h__c ≥30 for Mosquito |
| **TENURE_LOYAL** | 10 | `CreatedDate` ≥365 days ago |
| **CONDUCIVE** | 10 | Termite only — `Asset.Conducive_Conditions__c == true` |

Plus cross-sell-matrix nudges (smaller, +8 to +15 each):
- `EXISTING_PEST_CUSTOMER` (Termite or Mosquito recommended when Pest is on Account) → +10
- `TERMITE_ONLY_NO_PEST` (recommend Pest when only Termite is on Account) → +15
- `OUTDOOR_FOCUSED_PROFILE` (Lawn ↔ Mosquito cross) → +8

The reason codes attached to each recommendation drive talk-track resolution (next subsection). Score ties broken alphabetically by service line for deterministic rendering.

#### Talk-track resolution via `Upsell_Talk_Track__mdt`

12 talk-track records seeded in P3.4 (`force-app/main/default/customMetadata/Upsell_Talk_Track.*`). Schema: `{Service_Line__c, Reason_Code__c, Talk_Track__c, Estimated_Annual_Value__c, Active__c}`.

Lookup algorithm: for each recommendation, walk the reason codes in order; first matching `(Service_Line, Reason_Code)` wins. If none match, fall back to any active talk-track for the line. If still none, leave `suggestedTalkTrack = null` and the LWC renders a generic prompt.

Tunability: copy edits do not require redeploying Apex. A presenter can adjust talk-tracks in the metadata layer without touching LWC or class code.

#### Why the score weights sum to >100

The component max (20+25+20+15+10+10 = 100) plus cross-sell nudges (max ~15) plus tenure (10) can push raw score over 100; the clamp catches it. Empirically — across the seeded data set — only top-tier mosquito recommendations in Avalon Park during peak season clamp at 100.

### 5.3 Offline draft-Lead pattern

`captureOutcome` is `@AuraEnabled` (not `cacheable`) → can't run offline. The LWC handles this:

- **Online:** `masseyUpsellCoach` calls `captureOutcome` imperatively. Apex stamps the Account fields, inserts the Lead on `outcome == 'Yes'`, returns the Lead ID.
- **Offline (Maria's path on the route):** the LWC creates a draft Lead via `createRecord` directly + queues `updateRecord` calls for `Account.Last_Upsell_Pitched__c`, `Last_Upsell_Service_Line__c`, `Last_Upsell_Outcome__c`. Server-side `captureOutcome` is skipped offline. When the device reconnects, the FSL Mobile sync layer flushes both the Account update and the draft Lead. The LWC's offline contract is documented in `masseyUpsellCoach.js` (P5.6).

This is the canonical worked example for § 11 (offline strategy).

### 5.4 Cross-persona thread

| Persona | Surface | When |
|---------|---------|------|
| **Maria Lopez** (quarterly tech) | `masseyUpsellCoach` embedded in orchestrator Site step + Summary step | Marquee Scene 5 — Bennett residence, Avalon Park |
| **Tom Walker** (termite team lead) | `masseyUpsellCoach` embedded in Summary step | Scene 8 — opportunistic upsell after cluster response |
| **Jordan Martinez** (agent) | `masseyUpsellCoach` Quick Action on Account + Sidekick "Upsell Recommendation" topic | Scene 1 — Sandra ant call |
| **Ray Garcia** (manager) | Manager Coaching dashboard reports rolled up from `Last_Upsell_Outcome__c` | Scene 9 — day close |

The same Apex service powers all four touchpoints. Stamped state on the Account (`Last_Upsell_*__c`) is the single source of truth for the dashboard rollup.

---

## 6. Manager coaching layer

Ray's day-close surface (Scene 9). Built in P6.1.

### 6.1 The four reports

Located in `force-app/main/default/reports/Massey_Branch_Coaching/`:

1. **`Attach_Rate_by_Tech_MTD.report`** — Month-to-date attach rate by technician. Numerator: count of `WorkOrder` with `Account.Last_Upsell_Outcome__c == 'Yes'` since first of month. Denominator: count of WorkOrders completed in same window. Grouped by `OwnerId` (the tech).
2. **`Top_Performers_YTD.report`** — Year-to-date top-N techs by lead count from upsell capture. Filters `Lead.LeadSource = 'Tech Route Pitch'` joined back to assigned tech via Account → WorkOrder linkage.
3. **`Coaching_Opportunities.report`** — Inverse of #1. Techs with high WO completion volume but low attach rate. The "Tom is down — schedule coaching" signal in Scene 9.
4. **`Leads_from_Route_to_Conversion.report`** — Funnel from `outcome == 'Yes'` capture → Lead created → Lead converted → Opportunity won. Breaks down conversion drop-off by stage.

All four reports are surfaced on a single Manager Coaching dashboard (`force-app/main/default/dashboards/Massey_Branch_Coaching/`).

### 6.2 Attach rate computation

Attach rate = (Yes outcomes) / (completed WOs in window). Captured at WO completion time:

1. Maria taps "Capture Interest: Yes" in `masseyUpsellCoach` Summary step.
2. `captureOutcome` (or offline draft) stamps `Account.Last_Upsell_Outcome__c = 'Yes'`.
3. WO completes; `WOCompletionRollupHelper` runs.
4. End of month, the report aggregates by `WorkOrder.OwnerId`.

The "owner" is the assigned tech (`AssignedResource.ServiceResourceId.RelatedRecordId`). The rollup is best-effort and doesn't try to handle multi-tech crews precisely — for crew jobs (e.g., Tom's termite team), the lead tech gets attribution. This is a known approximation; for a real Massey deployment it'd be tightened.

### 6.3 Leads-from-route → conversion funnel

```
Tech captures Yes  →  Lead (Source = 'Tech Route Pitch')
       ↓                       ↓
  Account stamp        Routed to Jordan's outbound queue
                              ↓
                        Lead contacted (Status moves)
                              ↓
                        Lead Qualified
                              ↓
                        Converted to Opportunity
                              ↓
                        Opportunity Closed Won
```

Each transition is a stage in the funnel report. The demo seeds enough volume that the funnel actually has data (2026-05-08 seeded set shows ~30 leads YTD, ~12 converted, ~7 closed-won — exact numbers in `scripts/apex/seed_demo_data.apex`).

---

## 7. Cluster engine architecture

The 8-call cluster engine that drives Scenes 6–8. Domain-neutral, ported from telco — same record shape, content swapped.

### 7.1 The Mosquito Surge anchor scenario (ZIP 32828)

**Trigger:** heavy overnight rain (3+ inches) hits Avalon Park / Waterford Lakes. Standing water in a clogged municipal storm drain creates a 48-hour *Aedes aegypti* breeding event over 47 nearby properties.

**Cluster shape:** 1 Incident + 1 ProductServiceCampaign (PSC) + 8 Cases (the "loud" customers who called in) + ~47 PSCItems (one per affected property — silent + loud combined) + 1 dispatch WorkOrder (the parent Mosquito Surge Area Treatment WO at the breeding source).

**Resolution:** emergency-reassign Tom's team → identify breeding source → larvicide application → ULV fog perimeter → Cases auto-close → Incident closes → PSC closes → Mosquito Hunter customers receive proactive "we got it before you called" notifications.

### 7.2 `ClusterDetector` (P3.3)

Domain-neutral pattern analyzer. Reads recent inbound Cases + Asset locations, identifies geographic + service-line + temporal correlation, and creates the Incident + PSC + PSCItems shape when correlation crosses a threshold. Inherited from telco's `ClusterDetector` — same algorithm shape, content (location filters, service-line scoping) retoned for pest.

### 7.3 Demo-magic harness

The cluster engine runs **on demand** for the demo, not on a continuous timer (which would be unreliable for live presentations). The harness:

- 9 `demoMagic*` LWCs in `force-app/main/default/lwc/`. Examples: `demoMagicActivateIncident`, `demoMagicClusterDetect`, `demoMagicEmergencyDivert`, `demoMagicNotifyCustomers`, `demoMagicProactiveWoRun`.
- 8 Quick Action wrappers in `force-app/main/default/quickActions/` (e.g., `Incident.DemoMagic_Activate_Mosquito_Surge`, `Incident.DemoMagic_Emergency_Reassign`).
- Backed by `DispatcherScenarioLoader.cls` + `DemoDataLoader.cls` which flip seeded records from Draft → Active state on demand.

Presenter clicks the "Activate Mosquito Surge Cluster" Quick Action on the Incident layout. Within seconds, Ray's `dispatch_ActivePSCDrawer` lights up red, Jordan's queue fills, the room sees real-time platform reaction. Scene 6.

### 7.4 Why we kept the cluster engine when we dropped PMT

Both the cluster engine and the PMT bridge were ports from prior lifecycles. We kept cluster + dropped PMT for one reason: **the cluster scenario carries the multi-WO coordination story** that PMT used to carry. Without cluster, Scenes 6–8 don't exist, and the demo loses the "platform reacts in real time under pressure" beat. With cluster, that beat is intact and PMT becomes redundant. See `docs/PEST_NARRATIVE.md` § Anchor scenarios + § Capital programs.

---

## 8. Restricted-Use Pesticide attestation (Path A)

Reuses the inherited `LOTO_Record__c` object (Path A — see Locked decisions). Same blocking-gate UX as utility lock-out/tag-out + telco LOTO; different content.

### 8.1 What's captured

19 fields on `LOTO_Record__c`. Pest-relevant ones (P2.3 + P2.4):

- **Chemical identification:** `Chemical_Name__c`, `Energy_Source__c` (label "Chemical Source", refreshed picklist below), `EPA_Reg_Number__c`, `Target_Pest__c`.
- **Dose tracking:** `Dose_Amount__c`, `Dose_Unit__c`.
- **Applicator credential:** `Applicator_License__c` (the tech's RUP applicator license number).
- **Workflow state:** `Status__c`, `Verified_At__c`, `Verified_By__c`, `Removed_At__c`, `Removed_By__c`.
- **Photo + notes:** `Photo_ContentVersion_Id__c`, `Notes__c`.
- **Linkage:** `Work_Order__c` (Master-Detail).

The blocking-gate UX is identical to LOTO: a Critical Step on the Work Plan whose `Is_Critical__c = true` blocks the safety gate until the tech submits the attestation.

### 8.2 Chemical Source picklist (P2.4)

`Energy_Source__c` was the inherited utility/telco field name — it's now displayed as **"Chemical Source"** with a refreshed picklist of real Massey-relevant products:

- Termidor SC (fipronil — termite, soil)
- BifenIT (bifenthrin — perimeter, lawn)
- Talstar P (bifenthrin — perimeter, broad spectrum)
- Demand CS (lambda-cyhalothrin — quarterly pest)
- Suspend SC (deltamethrin — interior, void)
- Tempo SC (beta-cyfluthrin — wasp, stinging insect)
- Altosid (methoprene — mosquito larvicide)
- Aqua-Reslin (permethrin — ULV mosquito adulticide)
- Sentricon AlwaysActive (noviflumuron — termite bait)
- Other (specify in Notes)

Each option's label includes the EPA active ingredient + typical use case so the demo presenter can speak credibly to a Massey audience.

### 8.3 REI tracking + SDS linkage

- **Re-Entry Interval** (REI) is a checklist item in the Work Plan Template ("Re-Entry Interval (REI) Confirmed" — Safety Critical) and again in post-treatment ("Confirm Re-Entry Interval Posted" — Work ReEnergize). REI per chemical lives in Massey's reference system (mocked — not modeled in this demo).
- **SDS (Safety Data Sheet) review** is also a Safety Critical step ("Chemical / SDS Reviewed"). SDS docs are linked via the standard Salesforce Knowledge layer (referenced in K01–K12 but not stored as transactional records).

Both are presented to the tech at the Safety Gate; both must be checked to unlock the gate.

---

## 9. Integration points

Per-integration: data flow, offline implications, deployment dependency.

### 9.1 Service Cloud Voice (P4.1, already provisioned)

- **Status:** real number, real provisioning (commit `f7be0e2`). 5–10 business day lead time hit pre-build.
- **Data flow:** inbound call → IVR → Agentforce greeting → Account match → topic invocation → handoff to live agent with structured context attached. Outbound: Jordan's softphone for upsell follow-up.
- **Offline:** N/A (Voice is online-only).
- **Deployment dependency:** Voice number procurement must precede P4.2 Agentforce topic config.

### 9.2 Knowledge (P2.5, content authoring)

- **Status:** 12 articles authored per § 4.5.
- **Data flow:** `KnowledgeArticleSuggester.suggest(caseId)` — Apex queries Knowledge by topic + service line + property profile; returns top-3 ranked articles. Called from Sidekick library card.
- **Offline:** Knowledge articles primed via briefcase (path: WorkOrder → linked Cases → Knowledge). Tech can read them offline.
- **Deployment dependency:** must be authored before P4.2 topic config (topics ground against Knowledge).

### 9.3 Experience Cloud — `massey-portal` (P5.8, admin UI)

- **Status:** LWR site for new-prospect signup. Anchors Scene 4 (David Kim signup).
- **Data flow:** David enters address → `ServiceAreaValidator.validate(address)` confirms branch coverage + classifies property → plan picker (with Pest+Mosquito bundle upsell) → `AppointmentBooker.book` → `ServiceStartOrchestrator.create` provisions Account + initial Property Asset.
- **Offline:** N/A (portal is online-only).
- **Deployment dependency:** site is built post-LWC deploy (P5.8) so the portal LWCs reference deployed components.

### 9.4 Briefcase Builder

- **Status:** configured per `ARCHITECTURE_PROPOSAL.md` § 6.4.
- **Six priming paths** — see arch proposal table. Path 3 (WorkOrder → Account) is net-new vs telco to surface upsell-surface fields offline.
- **Offline:** this IS the offline strategy. Without briefcase, no offline. § 11.
- **Deployment dependency:** briefcase config is in `DEPLOYMENT_INSTRUCTIONS.md` (P6.5).

---

## 10. Scene-by-scene mapping

Brief synopses + architectural surfaces. **Cross-reference `docs/PEST_NARRATIVE.md` for full narrative beats** — this section names which architectural surfaces each scene exercises.

| Scene | Persona(s) | Synopsis | Surfaces touched |
|-------|-----------|----------|------------------|
| **1 — Sandra's ant call** | Sandra → Jordan | Inbound call, GoGreen customer, ant intrusion. Sidekick fires empathy + same-week-service + termite upsell cards. | Service Cloud Voice + Pest Inquiry topic + Sidekick library cards (empathy, upsell) + `AppointmentBooker` + `AppointmentConfirmer` + Lead spawn (termite upsell capture) |
| **2 — Billing escalation** | Jordan | Different customer, billing dispute, Sidekick offers retention card + service credit. | Customer 360 LWC + Billing Question topic + Sidekick retention card + `ChurnRiskScorer` |
| **3 — Entomology escalation** | Jordan | Unusual insect ID call; AI-assisted handoff to entomology queue. | Technical Escalation topic + `EscalationContextBuilder.summarize` + `PhotoAnalysisService.identify` (mocked) |
| **4 — David signs up at portal** | David | New homeowner self-service quote → bundle pick → install booked. | `massey-portal` Experience Cloud + `ServiceAreaValidator` + plan picker + `AppointmentBooker` + `ServiceStartOrchestrator` |
| **5 — Maria pitches Mosquito Hunter** *(MARQUEE)* | Maria | Bennett residence, Avalon Park. `masseyUpsellCoach` fires neighbor signal + seasonal multiplier. Maria pitches; captures Yes; offline draft Lead spawned. | `masseyFlowOrchestrator` Site + Summary steps + `masseyUpsellCoach` LWC + `UpsellCoachService.recommend` + `Upsell_Talk_Track__mdt` + offline draft-Lead pattern |
| **6 — Mosquito surge cluster activates** | Ray (background) | Demo-magic activates. ClusterDetector identifies 32828 correlation. PSC drawer lights up red. Jordan's queue fills. | `demoMagicActivateIncident` Quick Action + `ClusterDetector` + `dispatch_ActivePSCDrawer` + Cluster Status Update topic |
| **7 — Emergency reassign** | Ray | Pulls Tom's team off Sentricon install; routes to Mosquito Surge Area Treatment WO at breeding source. Straight FSL reassignment, no PMT bridge. | Field Service Dispatcher Console + `EmergencyDivertOrchestrator.divert` + `dispatch_SmartSuggester` |
| **8 — Tom on-site** | Tom | Tablet at clogged storm drain. 6-step orchestrator: Safety (PPE + RUP attestation) → Crew → Site (NFC + photo) → Work (treatment) → Service Impact (link Incident) → Summary. | Full `masseyFlowOrchestrator` + 6 step LWCs + `LOTO_Record__c` (RUP) + `masseyFlowChemicalPanel` + `masseyFlowNfcScanner` + `masseyFlowServiceImpactStep` + `VisitSummaryGenerator` |
| **9 — Day close + manager coaching** | Ray | WO close → rollup chain → Incident closes → PSC closes → ETR replaced with "Resolved". Manager Coaching dashboard surfaces attach rate. Sidekick: "Maria up 18%, Tom down — schedule coaching." | `WOCompletionRollupHelper` + Manager Coaching dashboard (4 reports) + Sidekick coaching cue |

The 9-scene flow is demo-presenter-recommended — scenes can be reordered or skipped per audience. Scenes 1, 5, 9 are non-skippable (open, marquee, close). See `docs/DEMO_PRESENTER_NOTES.md` (P6.3) for presenter cues.

---

## 11. Offline strategy

**Anchored to `ARCHITECTURE_PROPOSAL.md` § 6 — do not duplicate.** This section summarizes the three pillars and adds the `masseyUpsellCoach` worked example.

### 11.1 The three pillars (summary)

1. **Read pattern.** `@wire(getRecord)` with explicit field lists, `@wire(getRelatedListRecords)` for collections, `@AuraEnabled(cacheable=true)` Apex (Komaci-priming-eligible). No `getRecord` layout mode. Each step LWC self-wires its own data — enables the standalone Quick Action pattern.
2. **Write pattern.** `updateRecord` for field updates (drafts queue, sync on reconnect). `createRecord` for new hazards, draft AssignedResource, draft ContentVersion (photos), and draft Lead. **No Apex DML on the offline hot path** — Apex cannot enqueue drafts.
3. **Prohibited patterns.** Full table in arch proposal § 6.3. Highlights: no `lightning-record-form` / `lightning-datatable` / `platformShowToastEvent` / `lightning/empApi` / `lightning/messageService`. All forbidden because they have no offline runtime.

### 11.2 Worked example: `masseyUpsellCoach` offline draft-Lead pattern

This is the canonical offline pattern in the build. It illustrates pillars 1 + 2 working together.

**Read (pillar 1):**
```js
@wire(getRecord, { recordId: '$accountId', fields: ACCOUNT_FIELDS })
account;

// UpsellCoachService.recommend is cacheable + Komaci-eligible
@wire(recommend, { accountId: '$accountId' })
recommendations;
```

When the device is offline, both wires return briefcase-primed data. Path 3 (WorkOrder → Account) primes the Account record + upsell fields; the cacheable `recommend()` is primed by Komaci against the seeded set.

**Write (pillar 2):**
```js
async captureYes(serviceLine) {
    // Always stamp the Account locally — works offline via draft queue
    await updateRecord({
        fields: {
            Id: this.accountId,
            Last_Upsell_Pitched__c: new Date().toISOString(),
            Last_Upsell_Service_Line__c: serviceLine,
            Last_Upsell_Outcome__c: 'Yes',
        },
    });

    // Spawn the Lead as a draft record offline (or via Apex online)
    if (this.isOnline) {
        await captureOutcome({ accountId: this.accountId, serviceLine, outcome: 'Yes' });
    } else {
        await createRecord({
            apiName: 'Lead',
            fields: { /* derived from Account */ },
        });
    }
}
```

When the device reconnects, the FSL Mobile sync layer flushes the Account update + the draft Lead. The server-side `captureOutcome` is **skipped offline** because it would otherwise enqueue Apex DML (prohibited offline). The LWC's offline contract is documented in `masseyUpsellCoach.js` (P5.6).

This pattern is repeated for every offline-write surface in the orchestrator (hazard reporting, photo capture, crew add, RUP attestation, summary generation).

---

## 12. What we intentionally fake

Honest disclosure for any sales engineer who runs this demo. The buyer should never be told "this is real" when it's not.

| Surface | Real? | What's faked | Why |
|---------|-------|-------------|-----|
| Service Cloud Voice number + IVR | **Real** | — | Provisioned in P0; real call routing |
| Voice topic resolution for demo flows | Partly | Inbound Sandra call pulls a pre-seeded `Demo_Reply_Outcome.SandraReyes` record so the topic flow is reproducible | Live Voice + live AI is unpredictable for a 90-second demo beat |
| Knowledge articles | Real metadata, **stubbed content** | Article bodies are short / placeholder for some K01–K12 entries | Massey would author full content for a real deployment; demo cares about the linkage shape |
| Agentforce 8 topics + Upsell topic | **Real config**, real grounding | — | All 9 are configured in the target org's Agentforce Builder |
| `masseyFlowOrchestrator` + 6 step LWCs | **Real, end-to-end** | — | Built in P5.2; full offline; real data |
| `masseyUpsellCoach` + `UpsellCoachService` | **Real, end-to-end** | — | Real ranking + real talk-track lookup + real Lead spawn |
| Cluster engine (`ClusterDetector`) | Real algorithm, **demo-magic activation** | The 8 Cases + 1 Incident + 1 PSC + 47 PSCItems are seeded; `demoMagicActivateIncident` flips Draft → Active on presenter cue | Real cluster detection on a live event window is unreliable for live demos |
| Pest pressure model | Real algorithm, **seeded Asset state** | 14 candidate properties pre-flagged with rising bait hits + soil temp | Real telemetry would require real IoT bait stations |
| `PhotoAnalysisService.identify` (insect ID) | **Mocked** | Pre-seeded reply for the entomology escalation scene | Real photo ID would need a vision model integration not in scope |
| Smart bait stations / mosquito system telemetry | **Static records on Asset** | No real device integration | Out of scope per `docs/PEST_NARRATIVE.md` |
| Customer notifications (SMS / email) | Real shape, **mocked send** | `CustomerNotificationService` writes a notification record; doesn't send real SMS | Real telephony cost + carrier setup |
| `massey-portal` Experience Cloud site | **Real LWR site**, real signup flow | — | Deployed in P5.8; real DNS / Auth config in target org |
| Manager Coaching dashboard | **Real reports + real dashboard** | Underlying Lead conversion data is seeded | Real conversion data takes months to accumulate |
| Voice number for outbound (Jordan callbacks) | Real | — | Same provisioned number, outbound capable |
| REI / SDS reference data | **Mocked** | Per-chemical REI is presented as static text in the Safety Gate; no real lookup | Massey has internal references; not modeled here |
| Real chemical inventory integration | **Not modeled** | Truck stock LWC (`masseyFlowTruckStock`) reads a static seed | Real inventory would integrate with a separate WMS |

When a prospect probes a faked surface: the architecture supports the real version; we just didn't model it for this demo.

---

## 13. Open questions / decisions deferred to post-demo

Punted from this build, flagged for future iteration:

- **Multi-tech crew attribution for attach rate.** Current rollup gives the lead tech 100% of the credit on team WOs. For a real Massey deployment, this would be split or credited differently.
- **Real REI lookup table.** Per-chemical REI is currently presenter-static. A real deployment would integrate with a chemical reference DB.
- **Real photo-ID via vision model.** `PhotoAnalysisService.identify` is mocked. A real deployment would integrate Einstein Vision or a domain-trained model.
- **Real-time route optimization.** Standard scheduling policies only. No custom optimizer.
- **HOA / multi-family contract management.** Out of scope; residential focus only.
- **Customer-facing self-service rescheduling via SMS.** Portal + agent only; no SMS reschedule.
- **Real telemetry from smart bait stations.** Asset-stored static readings only; no IoT integration.
- **Lawn precision-application equipment integration.** Not modeled.
- **OutageStep file rename** *(see Locked decisions — addressed in P5.2)*. The user-facing-label rename was paired with a file rename in P5.2; locked-decision text below is updated accordingly.
- **Spanish-language demo path.** All Knowledge articles + talk-tracks are English-only. Massey serves a sizable Hispanic FL customer base; a Spanish locale path is a candidate post-demo polish.
- **PhotoAnalysis training set for pest ID.** If we ever de-mock photo ID, building / sourcing the training set is non-trivial.

---

## Locked decisions (recorded so downstream tickets can cite)

These decisions are **canonical** and must not be revisited without explicit owner sign-off. Append-only — do not remove existing entries.

### PMT capital-program bridge — NOT MODELED

**Decision:** This lifecycle does not model the PMT (Project Management Tool) capital-program bridge that existed in the telco lifecycle.

**What is dropped:**

- All PMT WorkOrder custom fields: `PMT_Task__c`, `PMT_Project__c`, `PMT_Phase__c`, `Project_Day__c`, `Project_Day_Of_Total__c`, `Children_Completed__c`, `Children_Total__c`, `Project_Pct_Complete__c`, `Defer_Reason__c`, `Work_Order_Coverage_Type__c`.
- `PMTTaskToWorkOrderSpawner.cls` and its tests.
- `dispatch_WOProjectContext` LWC.
- Any inov8 PMT managed-package install.

**Why:** Pest control has no clean capital-program analogue. Telco's PMT was modeling multi-day fiber-build projects spawning daily WorkOrders with project-day-of-total context. Pest field service is overwhelmingly recurring quarterly / monthly residential visits — no multi-day capital build, no project-day rollup, no parent project to bridge. Forcing a PMT analogue would add schema and Apex complexity that doesn't reinforce Massey's stated revenue-growth priority.

**Where this is enforced:**

- `ARCHITECTURE_PROPOSAL.md` § 4.1 + § 9 (decision #17)
- `docs/BUILD_TICKETS_PEST.md` ticket **P1.3** acceptance criteria
- `docs/PEST_NARRATIVE.md` § Capital Programs (the original rationale)

**Where the demo carries its weight without PMT:**

- Scenes 5 and 7 (which were PMT-driven in telco) are rewritten:
  - Scene 5 → marquee upsell scene (Maria pitches Mosquito Hunter)
  - Scene 7 → emergency reassign (Ray pulls Tom's termite team to mosquito surge response)
- The cluster-response architecture (Incident + PSC + 8 Cases + 47 PSCItems) carries the multi-WO-coordination story instead.

### Restricted-Use Pesticide attestation — Path A (object name preserved)

**Decision:** Reuse the existing `LOTO_Record__c` object name, swapping labels and content via Custom Labels (P2.1) and a refreshed picklist on `Energy_Source__c` (P2.4 — re-labeled "Chemical Source"). Do not rename the object.

**Why:** Renaming a custom object cascades into permission sets, page layouts, validation rules, formula references, and any inbound triggers. The blocking-gate UX is identical between LOTO (lock-out/tag-out) and RUP (restricted-use pesticide attestation) — same architectural pattern, different content. Schema migration cost > naming-purity benefit.

**Where this is enforced:**

- `docs/BUILD_TICKETS_PEST.md` tickets **P2.3** + **P2.4**
- `ARCHITECTURE_PROPOSAL.md` § 9 (decision #10)
- This doc § 8

### Inherited API name preservation — general policy

**Decision:** Where a label needs to change but a schema migration would be costly (e.g., `Outage_Latitude__c` → "Cluster Latitude" label, `Work_DeEnergize` → "Pre-Treatment Setup" label, `Circuit__c` → "Cluster Identifier" label, `Energy_Source__c` → "Chemical Source" label), preserve the API name and swap the label via Custom Labels in P2.1.

**Why:** Same reasoning as LOTO. Schema renames are expensive; labels are cheap. Treat the label as canonical for "what the field means in pest"; the API name is a historical artifact.

**Where this is enforced:**

- `ARCHITECTURE_PROPOSAL.md` § 4.2, § 4.3, § 9 (decision #20)
- `docs/BUILD_TICKETS_PEST.md` tickets **P1.6**, **P2.1**
- This doc § 2.4

### Step 5 LWC name — RENAMED to `masseyFlowServiceImpactStep` in P5.2

**Decision (UPDATED 2026-05-08, P6.4):** The original P0.2 locked decision deferred the file rename — the inherited file name was `masseyFlowOutageStep` (from `utilityFlowOutageStep`), with the user-facing label "Service Impact" applied via Custom Label.

**Status update:** in **P5.2 (commit `a415b0e`)**, the file rename was executed alongside the orchestrator + step LWC port. The component is now `masseyFlowServiceImpactStep` end-to-end (`.js`, `.html`, `.css`, `.js-meta.xml`, Quick Action XML, orchestrator import paths). The P0.2-era file-rename-deferral is **superseded**.

**Why the rename happened anyway:** during P5.2, the entire orchestrator + 6 step LWCs were ported in a single ticket (`utilityFlow*` → `masseyFlow*`). Renaming the 5 unambiguous components and leaving 1 with the inherited `Outage` name would have been louder than a clean rename across all 6. The metadata-churn cost was paid in a single ticket rather than distributed.

**Where this is enforced:**

- `ARCHITECTURE_PROPOSAL.md` § 2 (the flow-steps table — to be updated in a future polish pass; current text still references `masseyFlowOutageStep` and the rename-deferral note)
- `docs/BUILD_TICKETS_PEST.md` ticket **P5.2** acceptance criteria
- Repo `force-app/main/default/lwc/masseyFlowServiceImpactStep/` (ground truth)

**Note for future doc passes:** `ARCHITECTURE_PROPOSAL.md` § 2 still carries the original "name retains `OutageStep`" note. That text is now stale; a future polish pass (post-P6.4 if scope allows) should update the architecture proposal to match. This solution-design doc supersedes it for "what is" purposes; the architecture proposal still rules for "what shape" purposes.

---

*This document is owned by Allen Diaz de Leon. Authored in P6.4 on 2026-05-08. When making post-build changes, append decisions to "Locked decisions" rather than editing existing ones — downstream tickets cite by section heading.*
