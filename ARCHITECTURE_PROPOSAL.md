# masseyFlow

**FSL Mobile LWC Architecture Proposal**
Massey Services — Residential Pest, Termite, Mosquito & Lawn Field Service
6-Step Field Technician Workflow with Full Offline Support

Prepared for review by Allen Diaz de Leon
2026-05-08
v1 — Ported from telcoFlow v4 (NeuraFiber). PMT capital-program bridge dropped. Upsell + tech-coaching surface added.

> **Port note (2026-05-08):** This document is the third lifecycle of a domain-neutral architecture (utility → telco → pest). The structural decisions — orchestrator + 6 step LWCs, all 7 launchable as Quick Actions, Asset-anchored telemetry, WorkPlan/WorkStep template-driven checklists, briefcase-primed reads, draft-record writes — survive unchanged. What's swapped: schema (telco network telemetry → pest field telemetry), labels, anchor scenario (OLT card swap → quarterly pest service / mosquito surge area treatment), component prefix (`utilityFlow` → `masseyFlow`). What's removed: any PMT capital-program references — this lifecycle does not model PMT. What's added: an upsell + tech-coaching architectural surface (Section 11), driven by Massey's stated revenue-growth priority. Sections marked **TODO P6** will be polished in the P6.4 solution-design pass.

---

# 1. Executive Summary

This document proposes the architecture for converting the inherited domain-neutral field-technician workflow into production Salesforce Lightning Web Components for **Massey Services**, running on the Field Service Mobile app with full offline support.

The workflow covers a residential pest, termite, mosquito, or lawn service visit: the tech arrives on-site, completes a safety gate (PPE + Restricted-Use Pesticide attestation), logs crew (solo or team), takes site telemetry (NFC scan of bait stations / mosquito system controllers, photo capture, pest-pressure score), executes the pre-treatment / treatment / post-treatment sequence, correlates any active cluster Incident (e.g., post-storm mosquito surge), captures any upsell pitch outcome, and closes the work order. All 6 steps must function when the device has no connectivity.

Key design decisions:

- All 6 steps plus the orchestrator are individually exposed as Quick Actions, giving techs maximum flexibility to launch any step independently or resume mid-flow — critical for offline scenarios where a tech may not complete all steps in one session.
- Field telemetry lives on the Asset (not WorkOrder) for scalability. `Asset.Service_Line__c` (Pest / Termite / Mosquito / Lawn) drives variant rendering across all step LWCs.
- WorkPlans and WorkSteps are pre-populated via Work Type template association — same pattern as telco, content swapped per pest narrative.
- The Incident object (standard Service Cloud, no additional SKU) is used for cluster correlation. The marquee cluster scenario is a post-storm *Aedes aegypti* surge in Orlando ZIP 32828 (Avalon Park / Waterford Lakes) — 1 Incident + 1 PSC + 8 Cases + ~47 PSCItems + 1 parent dispatch WO.
- The **upsell + tech-coaching surface** (`UpsellCoachService.cls` + `masseyUpsellCoach` LWC + Agentforce topic + manager dashboard) is a first-class architectural addition vs the inherited telco architecture. See Section 11.

Key numbers: 11 LWC components (10 inherited + 1 net-new `masseyUpsellCoach`), 18 pest Asset custom fields, 7 WorkOrder custom fields, 5 WorkStep custom fields, 4 Incident custom fields, 6 Account custom fields (upsell surface), 7 Quick Actions on WorkOrder + 1 Quick Action on Account.

# 2. Flow Steps

The 6-step sequential flow inherited from prior lifecycles. Each step maps to a distinct child LWC component. The orchestrator manages end-to-end sequencing, but every step is also exposed as its own Quick Action so a technician can launch it independently — critical for offline scenarios where a tech may not complete all steps in one session.

| Step | Name | LWC Component | Purpose |
|------|------|--------------|---------|
| 1 | Safety Gate | masseyFlowSafetyStep | PPE verification, Restricted-Use Pesticide attestation, hazard reporting |
| 2 | Crew Check-In | masseyFlowCrewStep | Log crew members (solo on quarterly routes, team for area treatments) |
| 3 | Site Assessment | masseyFlowSiteStep | NFC scan of bait stations / mosquito systems, telemetry, photo capture, pest-pressure score, top upsell recommendation |
| 4 | Work Execution | masseyFlowWorkStep | Pre-treatment → treatment → post-treatment sequence with EPA reg # + dose capture |
| 5 | Service Impact | masseyFlowOutageStep | Link to active cluster Incident (e.g., mosquito surge), affected-property count |
| 6 | Summary & Close | masseyFlowSummaryStep | Auto-generated visit summary, full upsell capture surface, complete work order |

**Naming note:** Step 5's component name retains `OutageStep` (inherited from telco) for a clean port. The user-facing label is "Service Impact" via Custom Label (P2.1). Renaming the file is deferred — file rename has metadata churn cost and the offline architecture is identical.

# 3. Component Hierarchy

All components share the prefix `masseyFlow` (orchestrator + 6 steps + 2 internal shared) plus one net-new pest-specific LWC `masseyUpsellCoach`. All 6 step components plus the orchestrator are exposed as individual Quick Actions on the WorkOrder record page (target: `lightning__RecordAction`, actionType: `ScreenAction`) — 7 Quick Actions on WorkOrder. `masseyUpsellCoach` is additionally exposed as a Quick Action on Account for Jordan / Ray (1 Quick Action on Account). `StepHeader` and `ContextPanel` remain internal (shared child components, not launched independently).

```
masseyFlowOrchestrator (Quick Action — parent container)
├── masseyFlowStepHeader (shared — progress bar, step title)
├── masseyFlowContextPanel (shared — WO summary, asset info)
├── masseyFlowSafetyStep (Quick Action — standalone capable)
├── masseyFlowCrewStep (Quick Action — standalone capable)
├── masseyFlowSiteStep (Quick Action — standalone capable)
│   └── masseyUpsellCoach (embedded — top recommendation, talk-track collapsed)
├── masseyFlowWorkStep (Quick Action — standalone capable)
├── masseyFlowOutageStep (Quick Action — standalone capable)
└── masseyFlowSummaryStep (Quick Action — standalone capable)
    └── masseyUpsellCoach (embedded — full recommendation list, capture-outcome buttons)

masseyUpsellCoach (Quick Action on Account — standalone for Jordan / Ray)
```

# 4. Data Model

The architecture extends standard Salesforce objects rather than creating custom objects. This minimizes briefcase priming complexity and keeps relationships shallow (max 3 levels). No new custom objects are proposed. The Custom Metadata `Upsell_Talk_Track__mdt` (Section 11) is metadata, not a transactional object — it does not affect briefcase priming.

## 4.1 WorkOrder Custom Fields (7 fields)

WorkOrder retains only flow-control and cluster-correlation fields. Telemetry is on Asset (Section 4.4).

| Field | API Name | Type | Purpose |
|-------|----------|------|---------|
| Current Step | Current_Step__c | Number(2,0) | Tracks which step the tech is on (0-5) |
| Flow Started At | Flow_Started_At__c | DateTime | Timestamp when technician first launched the flow |
| Flow Completed At | Flow_Completed_At__c | DateTime | Timestamp when all 6 steps done |
| Safety Gate Status | Safety_Gate_Status__c | Picklist | Locked / Partial / Passed (field history tracked) |
| Safety Gate Passed At | Safety_Gate_Passed_At__c | DateTime | Timestamp when gate passed (field history tracked) |
| Outage Cause | Outage_Cause__c | Picklist | Root cause for cluster Incident (label: "Cluster Cause" via P2.1) |
| Linked Incident | Linked_Incident__c | Lookup(Incident) | Links WO to correlated cluster (field history tracked) |

**PMT fields are not deployed.** No `PMT_Task__c`, `PMT_Project__c`, `PMT_Phase__c`, `Project_Day__c`, `Project_Day_Of_Total__c`, `Children_Completed__c`, `Children_Total__c`, `Project_Pct_Complete__c`, `Defer_Reason__c`, or `Work_Order_Coverage_Type__c`. See `docs/SOLUTION_DESIGN.md` (P1.3) for the rationale.

## 4.2 WorkPlan & WorkStep (5 custom fields on WorkStep)

WorkPlan is the parent container; WorkSteps are the individual checklist items. The hierarchy is: WorkOrder → WorkPlan → WorkStep.

WorkPlan creation: Work Plan Templates are defined per Work Type (e.g., "Plan: Quarterly Pest Service", "Plan: Sentricon Install", "Plan: Mosquito Surge Area Treatment" — full set in P1.6's `scripts/apex/seed_work_plan_templates.apex`). When a Work Order is created from a given Work Type, the WorkPlan and its WorkSteps are auto-generated. The LWC reads and updates these existing records — it does not create them from scratch. This simplifies the offline story significantly, as all checklist data is pre-primed via the briefcase.

| Field | API Name | Type | Purpose |
|-------|----------|------|---------|
| Step Category | Step_Category__c | Picklist | Safety_Critical / Safety_Site / Safety_Admin / Work_DeEnergize / Work_Execute / Work_ReEnergize / Hazard |
| Is Critical | Is_Critical__c | Checkbox | Blocks safety gate if unchecked |
| Completed At | Completed_At__c | DateTime | When the tech toggled this item |
| Completed By | Completed_By__c | Text(18) | Who completed it. Text field to avoid Lookup priming issues offline. |
| Sort Order | Sort_Order__c | Number | Display order within category |

**Picklist API names are inherited from telco intentionally.** `Work_DeEnergize` displays as "Pre-Treatment Setup" and `Work_ReEnergize` displays as "Post-Treatment Verification" — label swap via Custom Labels in P2.1, no schema churn. See P1.6 for the mapping rationale.

## 4.3 Incident Fields (4 custom fields)

The Incident object is standard Service Cloud (available in Professional, Enterprise, Unlimited, and Developer editions since Winter '22 at no additional cost — no separate ITSM SKU required).

For pest, the Incident represents a **cluster event** (post-storm mosquito surge, area termite swarm, etc.) rather than a network outage. Location fields support the dispatcher console map overlay for cluster geography.

| Field | API Name | Type | Purpose |
|-------|----------|------|---------|
| Circuit | Circuit__c | Text(50) | Repurposed as cluster / route group identifier (e.g., `ZIP-32828-Mosquito`). Label: "Cluster Identifier" via P2.1. |
| Affected Properties | Affected_Customers__c | Number | Property count for this cluster (e.g., 47 for the marquee scenario). Label: "Affected Properties" via P2.1. |
| Cluster Latitude | Outage_Latitude__c | Number(3,7) | GPS centroid for map overlay. Label updated via P2.1; API name unchanged. |
| Cluster Longitude | Outage_Longitude__c | Number(3,7) | GPS centroid for map overlay. Label updated via P2.1; API name unchanged. |

**Naming policy:** Inherited Incident field API names (`Circuit__c`, `Affected_Customers__c`, `Outage_Latitude__c`, `Outage_Longitude__c`) are preserved to avoid migration churn. Pest-appropriate labels are applied via Custom Labels in P2.1. New code should reference these fields by API name and treat the labels as authoritative for UI.

## 4.4 Asset Fields — Property & Pest Telemetry

Standard Asset fields used: Name (property identifier — e.g., "Bennett Residence — 1247 Maple Ave"), SerialNumber (Sentricon station serial / mosquito system serial, where applicable), Latitude, Longitude, Status, InstallDate. Field telemetry is stored on the Asset for scalability — readings are reusable across work orders and support historical trending.

### Asset Custom Fields (18)

`Service_Line__c` (Pest / Termite / Mosquito / Lawn, restricted, required, default = Pest) drives variant rendering across all step LWCs — same pattern as telco's `Network_Domain__c`.

| Field | API Name | Type |
|-------|----------|------|
| Service Line | Service_Line__c | Picklist (Pest / Termite / Mosquito / Lawn — restricted, required) |
| Equipment Type | Equipment_Type__c | Picklist (Property / Sentricon_Station / Mosquito_System / Mosquito_Nozzle / Trap / Treatment_Perimeter) |
| Equipment Model | Equipment_Model__c | Text(80) |
| Bait Station State | Bait_Station_State__c | Picklist (Untouched / Activity / Heavy_Activity / Replaced) |
| Last Bait Station Hit Date | Last_Bait_Station_Hit_Date__c | Date |
| Bait Station Hits 30d | Bait_Station_Hits_30d__c | Number(3,0) |
| Soil Temp (°F) | Soil_Temp_F__c | Number(4,1) |
| Conducive Conditions | Conducive_Conditions__c | Checkbox |
| Pest Pressure Score | Pest_Pressure_Score__c | Number(3,0) |
| Trap Catch Count (24h) | Trap_Catch_Count_24h__c | Number(4,0) |
| Last Treatment | Last_Treatment_DateTime__c | DateTime |
| Days Since Last Service | Days_Since_Last_Service__c | Number(4,0) |
| Is Pest Pressure Candidate | Is_Pest_Pressure_Candidate__c | Checkbox |
| EPA Reg # Last Used | EPA_Reg_Number_Last_Used__c | Text(20) |
| Conducive Notes | Conducive_Notes__c | Long Text(2000) |
| NFC Tag ID | NFC_Tag_Id__c | Text(100), External ID, Unique |
| Service Group | Service_Group__c | Text(40) |
| Property Type | Property_Type__c | Picklist (Single_Family / Townhome / Condo / Multi_Family) |
| Lot Size (sqft) | Lot_Size_Sqft__c | Number(8,0) |

**Telco telemetry fields not deployed:** `Optical_Rx_Power_dBm__c`, `Optical_Tx_Power_dBm__c`, `Splice_Loss_dB__c`, `OTDR_Distance_M__c`, `Upstream_SNR_dB__c`, `Downstream_Power_dBmV__c`, `Uncorrectable_FEC_Errors__c`, `RSRP_dBm__c`, `RSRQ_dB__c`, `SINR_dB__c`, `OLT_Port__c`, `PON_Id__c`, `Network_Domain__c`. None are deployed in this lifecycle.

## 4.5 Account Custom Fields — Upsell Surface (6 fields, NEW)

Net-new vs prior lifecycles. Drives the upsell coaching surface (Section 11). Authored in ticket P1.7.

| Field | API Name | Type | Purpose |
|-------|----------|------|---------|
| Eligible Upsells | Eligible_Upsells__c | Multi-select Picklist (Pest / Termite / Mosquito / Lawn) | Which lines this Account is eligible to be pitched |
| Last Upsell Pitched At | Last_Upsell_Pitched__c | DateTime | Most recent pitch timestamp |
| Last Upsell Service Line | Last_Upsell_Service_Line__c | Picklist (Pest / Termite / Mosquito / Lawn) | Which line was last pitched |
| Last Upsell Outcome | Last_Upsell_Outcome__c | Picklist (Yes / NotNow / NotInterested / NoResponse) | Outcome captured by tech / agent |
| Upsell Score | Upsell_Score__c | Number(3,0) | 0–100 composite score from `UpsellCoachService.recommend()` |
| Upsell Score Last Updated | Upsell_Score_Last_Updated__c | DateTime | Score recompute timestamp |

# 5. Photo Capture & NFC Scanning

## 5.1 Photo Capture

Photo capture uses the Nimbus camera plugin (available in FSL Mobile). Photos are saved as draft ContentVersion records that sync to the WorkOrder when the device regains connectivity. FSL Mobile's native annotation feature (Release 242+) handles markup — no custom Canvas-based annotation is needed.

Pest-specific use cases:

- **Conducive conditions:** wood-soil contact, moisture damage, mulch-on-foundation
- **Bait station evidence:** termite activity, station damage, station replacement
- **Mosquito breeding source:** standing water, clogged drains, untreated areas
- **Pre/post treatment:** before-and-after coverage validation
- **Customer sign-off proof:** signed service ticket / digital acknowledgment

## 5.2 NFC Tag Scanning

NFC scanning uses the Nimbus NFCService plugin to read NFC tags affixed to physical assets. When a tag is scanned, the LWC matches the tag ID to an Asset record's `NFC_Tag_Id__c` field and auto-populates infrastructure details in the Site Assessment step.

Pest-specific tagged assets:

- **Sentricon AlwaysActive bait stations** — perimeter-installed termite stations
- **Mosquito Hunter system controllers** — central manifold for nozzle network
- **Mosquito Hunter nozzles** — individual perimeter nozzles
- **Property treatment perimeter markers** — for lawn / lot-boundary verification

Operational notes:

- **Plugin:** NFCService (Nimbus) — supports read, write, erase
- **Match:** NFC tag payload → `Asset.NFC_Tag_Id__c` lookup
- **Offline:** Works fully offline — Asset must be primed in briefcase
- **Fallback:** Manual asset search/selection if device lacks NFC or tag is damaged

# 6. Offline Strategy

Every component is designed to work when the mobile device has zero connectivity. The strategy rests on three pillars: how we read data, how we write data, and what the briefcase must prime.

## 6.1 Read Pattern

- `@wire(getRecord)` with explicit field lists for WorkOrder, Asset, Account, and Incident. No layout-mode queries (not supported offline).
- `@wire(getRelatedListRecords)` for WorkSteps (via WorkPlan), AssignedResources, ServiceCrewMembers, and service history.
- `UpsellCoachService.recommend()` is `@AuraEnabled(cacheable=true)` and Komaci-priming-eligible — the `masseyUpsellCoach` LWC wires it like any other cacheable Apex method.
- All data must be pre-primed via Briefcase Builder to be available offline.
- Each step component is self-contained — it wires its own data independently. This enables the standalone Quick Action pattern.

## 6.2 Write Pattern

- `updateRecord` (from `lightning/uiRecordApi`) for all WorkOrder, WorkStep, Asset, and Account field updates. Changes go to the draft queue and sync when online.
- `createRecord` for new hazard WorkSteps, draft AssignedResource (Add Crew Member), draft ContentVersion (photos) with dual ContentDocumentLink to both WorkOrder and Asset, and **draft Lead** (spawned when `masseyUpsellCoach` captures outcome = "Yes"). Draft records get temporary IDs and sync on reconnection.
- `UpsellCoachService.captureOutcome()` is invoked imperatively when online. **Offline path:** the LWC creates a draft Lead via `createRecord` and queues an Account update for `Last_Upsell_*__c` fields; the service-side `captureOutcome` is skipped offline (it would otherwise enqueue Apex DML, which is prohibited offline). This is documented in the LWC's offline contract.
- No Apex for write operations on the offline path — Apex cannot enqueue drafts.

## 6.3 Prohibited Patterns

The following are explicitly prohibited in all components to ensure offline compatibility:

| Prohibited | Reason | Alternative |
|-----------|--------|-------------|
| `lightning-record-form` | Not supported offline | `@wire(getRecord)` + manual UI |
| `lightning-record-edit-form` | Not supported offline | `updateRecord` + custom form |
| `lightning-record-view-form` | Not supported offline | `@wire(getRecord)` + display |
| `lightning-datatable` | Not supported offline | Custom `for:each` table |
| `lightning-file-upload` | Not supported offline | Nimbus camera + `createRecord` |
| `platformShowToastEvent` | Not supported offline | `lightning/alert` |
| `lightning/empApi` | Requires server connection | N/A — no push notifications |
| `lightning/messageService` | Not supported offline | `CustomEvent` bubbling |
| Apex DML on hot path | Cannot enqueue drafts | `updateRecord` / `createRecord` |
| `getRecord` layout mode | Not supported offline | Explicit field lists |

## 6.4 Briefcase Priming Paths

Briefcase Builder supports related objects up to 3 levels deep. The following paths must be configured (see `DEPLOYMENT_INSTRUCTIONS.md` P6.5 for the full briefcase config):

| # | Root Object | Path | Depth |
|---|------------|------|-------|
| 1 | WorkOrder | → WorkPlan → WorkStep | 2 |
| 2 | WorkOrder | → Asset | 1 |
| 3 | WorkOrder | → Account (for upsell surface) | 1 |
| 4 | WorkOrder | → AssignedResource → ServiceResource | 2 |
| 5 | WorkOrder | → ServiceCrew → ServiceCrewMember | 2 |
| 6 | Incident | (direct — filtered by ServiceTerritory + active cluster) | 0 |

**Path 3 is net-new vs telco** — required to prime upsell-surface fields on Account so `masseyUpsellCoach` renders offline.

# 7. Work Plan Template: Checklist Items

Work Plan Templates are defined per Work Type and associated with the relevant Work Type record. When a Work Order is dispatched from a given Work Type, the platform auto-generates a WorkPlan with the corresponding WorkSteps across 7 categories. The LWC reads and toggles these — it never creates them. The full template set is seeded via `scripts/apex/seed_work_plan_templates.apex` (P1.6).

The example below uses **Mosquito Surge Area Treatment** — the marquee cluster-response scenario from `docs/PEST_NARRATIVE.md` Scene 8 (Tom's tablet at the Avalon Park storm drain).

### Safety Critical (4 items — all block the safety gate)

- PPE Verification (gloves, respirator, eye protection)
- Restricted-Use Pesticide License Verified (RUP attestation — replaces telco's LOTO; same blocking-gate UX, different content)
- Chemical / SDS Reviewed
- Re-Entry Interval (REI) Confirmed

### Safety Site (3 items)

- Weather Check — No Rain in Next 4 Hours
- Work Zone Perimeter Set (cones, signage)
- Property Conditions Assessed (pets, children, neighbors)

### Safety Admin (2 items)

- Tailboard Briefing Complete
- Permit-to-Treat / Customer Notification Logged

### Work DeEnergize (3 items — pre-treatment setup, label "Pre-Treatment Setup" via P2.1)

- Locate Breeding Source / Treatment Area
- Mix / Calibrate Application Equipment
- Verify EPA Reg # + Target Species Match

### Work Execute (4 items)

- Apply Larvicide to Standing Water Source
- ULV Fog Perimeter
- Treat Identified Harborage Areas
- Capture Treatment Photo + Coverage Notes

### Work ReEnergize (3 items — post-treatment verification, label "Post-Treatment Verification" via P2.1)

- Verify Nozzle Output / Coverage Pattern
- Confirm Re-Entry Interval Posted
- Customer Sign-Off (or Door-Hanger Left if Not Home)

**Other plans seeded in P1.6:** Quarterly Pest Service, Sentricon Install, Sentricon Service, Termite Liquid Treatment (Termidor), Mosquito System Install, Mosquito System Service, Wasp / Stinging Insect Removal, Pest Inspection (New), Termite Inspection (Booster). 10 plans, ~50 steps total.

# 8. Cluster Map Integration (Data Architecture)

The Incident data model includes `Outage_Latitude__c` and `Outage_Longitude__c` (label: Cluster Lat/Long) specifically to enable an offline map overlay for cluster events. This architecture supports a separate map LWC (built independently — out of scope for this proposal) that can:

- Query Incident records primed in the briefcase by service group / cluster identifier or service territory
- Plot cluster centroids on an offline-capable map (Leaflet.js with cached tiles via static resource)
- Use Nimbus geolocation plugin for the technician's current position
- Display cluster severity, affected-property count, and status as map markers

For Massey, the canonical cluster shape is the post-storm mosquito surge in ZIP 32828 (Avalon Park / Waterford Lakes) — 47 affected properties, ETR-pending until the parent dispatch WO completes ULV fog of the breeding source.

> **Note:** The map LWC itself is not part of this build. This architecture ensures the data model and briefcase priming are ready for it. The Service Impact step (Step 5) and the dispatcher console drawer (`dispatch_ActivePSCDrawer`, P5.x) leverage this same data.

# 9. Resolved Decisions

| # | Decision | Resolution |
|---|----------|-----------|
| 1 | Quick Action scope | All 7 (orchestrator + 6 steps) on WorkOrder + 1 (`masseyUpsellCoach`) on Account = 8 total |
| 2 | Telemetry storage | Asset fields (Option A default), with design attribute toggle for AssetAttribute (Option B) preserved from telco |
| 3 | WorkStep creation | Pre-populated via Work Plan Template — LWC never creates checklist steps |
| 4 | Cluster object | Standard Incident (Service Cloud) — swappable via design attribute, repurposed from outage |
| 5 | Photo annotation | Native FSL Mobile markup (Release 242+) — no custom Canvas build |
| 6 | NFC fallback | Manual asset search if NFC unavailable |
| 7 | Component prefix | `masseyFlow` for orchestrator + steps; `massey*` for pest-specific UI (e.g., `masseyUpsellCoach`); `dispatch_*` for dispatcher console widgets; `demoMagic*` for demo harness |
| 8 | Crew management | AssignedResource + ServiceCrew (standard objects). Solo on quarterly routes (Maria), team for area treatments (Tom + backup) |
| 9 | Safety gate logic | All `Is_Critical__c` WorkSteps must be checked to unlock gate |
| 10 | Restricted-Use Pesticide attestation | Reuses the telco LOTO architectural pattern (same `LOTO_Record__c` object name per P2.3 Path A; labels swapped to "RUP Attestation" via Custom Labels). Same blocking-gate UX, different content. |
| 11 | Error handling | `lightning/alert` for user-facing errors (replaces toast) |
| 12 | Offline detection | None — all components assume offline-first, no online/offline branching |
| 13 | Hazard reporting | Creates new WorkStep with `Step_Category__c = 'Hazard'` via `createRecord` |
| 14 | Step data persistence | Each step dispatches `stepdatasave` CustomEvent; orchestrator calls `updateRecord` |
| 15 | Briefcase depth | Max 3 levels — all priming paths verified within limit |
| 16 | Server-side safety gate enforcement | Validation rule prevents `Safety_Gate_Status__c` from being set to Passed without transitioning through Partial first |
| 17 | PMT capital-program bridge | **Not modeled.** No PMT custom fields on WorkOrder, no `PMTTaskToWorkOrderSpawner.cls`, no `dispatch_WOProjectContext` LWC. Pest has no clean capital-program analogue. See `docs/PEST_NARRATIVE.md` § Capital Programs. |
| 18 | Upsell + tech-coaching surface | **Net-new architectural surface** — see Section 11. Driven by Massey's revenue-growth priority; surfaced across Maria (tech), Jordan (agent), Ray (manager). |
| 19 | Service-line variant rendering | `Asset.Service_Line__c` (Pest / Termite / Mosquito / Lawn) drives variant logic in step LWCs — replaces telco's `Network_Domain__c` |
| 20 | Inherited API name preservation | Where labels need to change but schema migration would be costly (e.g., `Outage_Latitude__c`, `Work_DeEnergize`, `Circuit__c`), API names are preserved and labels are swapped via Custom Labels in P2.1 |

# 10. Personas Touching This Architecture

Per `docs/PEST_NARRATIVE.md`. Each persona's surface is informed by — but not limited to — the architecture in this document.

- **Maria Lopez** (quarterly pest tech) — `masseyFlowOrchestrator` on phone, drives marquee upsell scene (Scene 5)
- **Tom Walker** (termite team lead) — `masseyFlowOrchestrator` on tablet, runs cluster-response area treatment (Scene 8)
- **Jordan Martinez** (branch service center agent) — Service Console + Agent Sidekick + Voice softphone; uses `masseyUpsellCoach` Quick Action on Account for inbound-call upsells (Scene 1)
- **Ray Garcia** (branch operations manager) — Field Service Dispatcher Console; views Manager Coaching dashboard (Scene 9) which surfaces attach-rate and leads-from-route metrics derived from `masseyUpsellCoach` outcome capture
- **Sandra Reyes** / **David Kim** / **Lisa Chen** — customer personas, do not touch the FSL Mobile architecture directly

# 11. Upsell + Tech-Coaching Surface (NEW)

This section captures the architectural addition that distinguishes the Massey lifecycle from prior telco/utility lifecycles. Per memory and `CLAUDE.md`'s revenue-growth lens, upsell + coaching is a thread woven across multiple personas — not a single tacked-on feature.

## 11.1 Components

| Component | Type | Ticket | Purpose |
|-----------|------|--------|---------|
| `UpsellCoachService.cls` | Apex | P3.4 | `recommend(accountId)` returns ranked `UpsellRecommendation` list (`@AuraEnabled(cacheable=true)`); `captureOutcome(accountId, serviceLine, outcome)` spawns Lead on `Yes` |
| `Upsell_Talk_Track__mdt` | Custom Metadata | P3.4 | ~12 talk-track records, tunable without code deploy |
| `masseyUpsellCoach` | LWC | P5.6 | Surfaces in Site step + Summary step + standalone Account Quick Action; offline-capable via draft Lead |
| Account upsell fields | Metadata (×6) | P1.7 | `Eligible_Upsells__c`, `Last_Upsell_Pitched__c`, `Last_Upsell_Service_Line__c`, `Last_Upsell_Outcome__c`, `Upsell_Score__c`, `Upsell_Score_Last_Updated__c` |
| Agentforce "Upsell Recommendation" topic | Config | P4.3 | Lets Jordan ask Sidekick to run a pitch on demand for an inbound caller |
| Manager Coaching dashboard | Reports | P6.1 | 4 reports: Attach Rate by Tech (MTD), Top Performers (YTD), Coaching Opportunities, Leads from Route → Conversion |

## 11.2 Ranking Inputs (informational — TODO P6 polish)

`UpsellCoachService.recommend()` ranks recommendations using:

- Existing service lines on Account (cross-sell matrix from `project_massey_revenue_focus.md`)
- Neighborhood signals (other Massey customers in same ZIP / street)
- Seasonal multipliers (FL termite Mar–May, mosquito Apr–Oct)
- Property characteristics (`Lot_Size_Sqft__c`, `Conducive_Conditions__c`, `Property_Type__c`)
- Customer tenure

Talk-tracks are empathetic + low-pressure ("While I'm here..." framing). Content lives in `Upsell_Talk_Track__mdt` so the demo can tune copy without redeploy.

## 11.3 Cross-Persona Thread

The upsell surface is intentionally not one feature in one place. It threads across:

- **Maria (tech, on-site):** `masseyUpsellCoach` embedded in orchestrator Site step + Summary step. Captures outcome → spawns draft Lead offline.
- **Jordan (agent, inbound call):** `masseyUpsellCoach` Quick Action on Account; "Upsell Recommendation" Agentforce topic on demand from Sidekick.
- **Ray (manager, EOD review):** Manager Coaching dashboard reports rolled up from `Last_Upsell_Outcome__c` capture across the route.

Removing any one surface degrades the demo's revenue-growth story. See `docs/PEST_NARRATIVE.md` Scene 5 (marquee) and Scene 9 (close).

# 12. Next Steps

This proposal is the architectural source-of-truth for Phases P1–P6. Once Allen approves (or redlines):

- **Phase P1 (schema swap):** Author all field XML, drop PMT scaffolding, add upsell fields, swap skills + work types + work-plan templates. 8 tickets.
- **Phase P2 (custom labels + RUP attestation + knowledge):** Swap labels per pest narrative, build RUP attestation, author 12 Knowledge articles. 5 tickets.
- **Phase P3 (Apex):** Port domain-neutral classes; build `UpsellCoachService.cls` with ≥85% coverage. 4 tickets.
- **Phase P4 (Agentforce + Voice):** Procure Voice number (kicked off in P0), rewrite 8 topics, add Upsell Recommendation topic. 3 tickets.
- **Phase P5 (LWC + dispatcher + portal + seed data):** Port all step LWCs, build `masseyUpsellCoach`, refresh dispatcher widgets, build `massey-portal` Experience site. 8 tickets.
- **Phase P6 (cluster engine + dashboards + docs polish + smoke test):** Cluster engine for Scene 6, Manager Coaching dashboard, polish this doc + `SOLUTION_DESIGN.md`, full deployment instructions, end-to-end demo smoke test. 7 tickets.

Sections marked **TODO P6** in this document (notably Section 11.2 ranking-inputs detail) will be polished in P6.4 alongside `docs/SOLUTION_DESIGN.md`.

---

*This is the architectural source-of-truth (rank #2 in the source-of-truth hierarchy in `CLAUDE.md`). Story (`docs/PEST_NARRATIVE.md`) outranks architecture; architecture outranks execution (`docs/BUILD_TICKETS_PEST.md`). Where two artifacts disagree, story wins, then architecture, then execution.*
