# masseyFlow — Pest Control Build Tickets

Atomic build tickets to construct the Massey Services pest control demo on top of the domain-neutral architecture inherited from `telcoFlow-neurafiber` (third lifecycle of this architecture: utility → telco → pest).

Architecture, orchestrator, dispatcher console, Agentforce action surface, demo-magic harness, 8-call cluster engine, and offline briefcase priming are domain-neutral and survive the swap. **What's added (not in prior lifecycles):** the upsell + tech-coaching architectural surface — see Phases P3 and P5. **What's dropped:** PMT capital-program bridge — see Phase P1.

## Source-of-truth note

`docs/PEST_NARRATIVE.md` is authoritative for **story** (brand, personas, scenes). `ARCHITECTURE_PROPOSAL.md` (ported from telcoFlow in P0.2) is authoritative for **architecture**. This file is the **execution** plan. Where two artifacts disagree, story > architecture > execution.

## Decisions locked in

- **Brand:** Massey Services (real). Used with permission pending legal sign-off.
- **Geography:** Orlando, FL — Orange + Seminole counties. Single branch operation.
- **Service lines:** GoGreen Pest, Termite Protection, Mosquito Hunter, Lawn Service.
- **Anchor cluster scenario:** post-rainfall mosquito surge, 47 properties, ZIP 32828.
- **Anchor proactive scenario:** pest pressure model — Sentricon hits + soil temp + seasonal multiplier flagging 14 properties for booster termite treatment.
- **Network_Domain__c → Service_Line__c rename:** picklist values Pest / Termite / Mosquito / Lawn.
- **PMT bridge dropped:** all PMT custom fields, `PMTTaskToWorkOrderSpawner.cls`, `dispatch_WOProjectContext` LWC, and the inov8 PMT managed package install are removed. Scenes 5 + 7 are rewritten as a route-board + emergency-reassign without PMT.
- **Upsell + coaching architectural surface added:** new `UpsellCoachService` Apex, new `masseyUpsellCoach` LWC, new Agentforce "Upsell Recommendation" topic, new Manager Coaching dashboard, new Scene 5.
- **LOTO repurpose:** `LOTO_Record__c` becomes `Chemical_Application_Log__c` — same blocking-gate UX, content reframed for Restricted-Use Pesticide attestation.

## Naming conventions

- `masseyFlow*` — orchestrator + step LWCs (renamed from `telcoFlow*`)
- `dispatch_*` — Dispatcher Console customs (kept)
- `demoMagic*` — demo-only mocks and Quick Action wrappers (kept)
- `massey*` — Massey-specific UI (e.g., `masseyUpsellCoach`)
- `fsl_*` — reserved
- Custom fields: snake_case ending in `__c`. Picklist values follow `PEST_NARRATIVE.md` capitalization.

## Reference repo

The source architecture lives at `/Users/allen.diazdeleon/Desktop/telcoFlow-neurafiber`. When implementing a ticket below, reference the equivalent telco ticket in that repo's `docs/BUILD_TICKETS_TELCO.md` for the proven implementation pattern. **Never copy telco content** (labels, picklist values, Apex bodies) — only patterns, signatures, and structure.

---

## Phase P0 — Decisions + brand baseline

### Ticket P0.0 — Initialize masseyFlow scaffold

**Phase:** P0
**Type:** scaffolding
**Status:** ✅ Complete (commit `c9f5415`)

SFDX project skeleton lifted from telcoFlow: `sfdx-project.json`, `package.json`, ESLint, Jest, Prettier, scratch-org config, `.forceignore`. Empty `force-app` tree.

### Ticket P0.1 — Author PEST_NARRATIVE.md

**Phase:** P0
**Type:** documentation
**Status:** ✅ Complete (commit `1b798f0`)

Brand, personas, capital-program-NOT-modeled note, anchor scenarios, upsell architectural surface, 9 scenes including net-new Scene 5 (Maria mid-route upsell pitch).

### Ticket P0.2 — Author CLAUDE.md + README + initial docs structure

**Phase:** P0
**Type:** documentation
**Depends on:** P0.1
**Estimated effort:** 2 hours

**Scope:** Author `CLAUDE.md` (project conventions, source-of-truth hierarchy, naming, manual-checkpoint list, persona block), `README.md` (one-page repo entry point), and stub `docs/SOLUTION_DESIGN.md` + `docs/DEPLOYMENT_INSTRUCTIONS.md` placeholders to fill in P6. Port `ARCHITECTURE_PROPOSAL.md` from telcoFlow with PMT sections deleted (mark with TODO for P6 polish pass).

**Acceptance criteria:**
- `CLAUDE.md` mentions Massey, Orlando, the 4 service lines, the 7 personas, and notes that PMT is not modeled.
- `README.md` describes Massey + Orlando + the 7 personas in their pest roles.
- Both files reference `docs/PEST_NARRATIVE.md` and `docs/BUILD_TICKETS_PEST.md`.
- `ARCHITECTURE_PROPOSAL.md` is present, PMT sections removed (or clearly marked stale).

---

## Phase P1 — Schema swap (Days 2–7)

Eight tickets. Replace telco data model with pest data model. Drop PMT bridge entirely. Add upsell custom fields on Account.

### Ticket P1.1 — Add `Asset.Service_Line__c` picklist

**Phase:** P1
**Type:** metadata
**Depends on:** P0.2
**Estimated effort:** 3 hours

**Scope:** Add `Service_Line__c` picklist on Asset (Pest / Termite / Mosquito / Lawn, restricted, required, default = Pest). Drives variant rendering across all step LWCs — same pattern as telco's `Network_Domain__c`.

**Acceptance criteria:**
- 4 restricted picklist values.
- Required + default = Pest.
- No `Network_Domain__c` field present (we never deployed it; clean slate).

### Ticket P1.2 — Replace telco Asset fields with pest Asset fields

**Phase:** P1
**Type:** metadata
**Depends on:** P1.1
**Estimated effort:** 8 hours

**Scope:** **Do not deploy** any telco Asset fields (`Optical_Rx_Power_dBm__c`, `PON_Id__c`, `OLT_Port__c`, `Splice_Loss_dB__c`, `OTDR_Distance_M__c`, `Upstream_SNR_dB__c`, `Downstream_Power_dBmV__c`, `Uncorrectable_FEC_Errors__c`, `RSRP_dBm__c`, `RSRQ_dB__c`, `SINR_dB__c`, etc.). **Add** these pest Asset fields:

| Field | Type | Purpose |
|---|---|---|
| `Equipment_Type__c` | Picklist | Property / Sentricon_Station / Mosquito_System / Mosquito_Nozzle / Trap / Treatment_Perimeter |
| `Equipment_Model__c` | Text(80) | Vendor model (e.g., "Sentricon AlwaysActive", "Mosquito Hunter MH-2400") |
| `Bait_Station_State__c` | Picklist | Untouched / Activity / Heavy_Activity / Replaced |
| `Last_Bait_Station_Hit_Date__c` | Date | Last date of bait station termite activity |
| `Bait_Station_Hits_30d__c` | Number(3,0) | Termite hits across all stations on this property in 30d |
| `Soil_Temp_F__c` | Number(4,1) | Soil temperature at last quarterly check |
| `Conducive_Conditions__c` | Checkbox | Set when wood-soil contact, moisture, etc. flagged |
| `Pest_Pressure_Score__c` | Number(3,0) | Composite 0–100 pest pressure score |
| `Trap_Catch_Count_24h__c` | Number(4,0) | Mosquito trap catch over last 24h |
| `Last_Treatment_DateTime__c` | DateTime | Last service treatment timestamp (renamed from `Last_Telemetry_DateTime__c` pattern) |
| `Days_Since_Last_Service__c` | Number(4,0) | Time since last service visit |
| `Is_Pest_Pressure_Candidate__c` | Checkbox | Proactive scenario flag (replaces `Is_Degraded_Candidate__c`) |
| `EPA_Reg_Number_Last_Used__c` | Text(20) | Last EPA registration number applied |
| `Conducive_Notes__c` | Long Text(2000) | Tech-captured notes on conducive conditions |
| `NFC_Tag_Id__c` | Text(100), External ID, Unique | Match physical bait station / system NFC tag (carried over from telco — pattern is identical) |
| `Service_Group__c` | Text(40) | Route group / cluster identifier |
| `Property_Type__c` | Picklist | Single_Family / Townhome / Condo / Multi_Family |
| `Lot_Size_Sqft__c` | Number(8,0) | Lot size for treatment-volume estimation |

**Implementation guidance:** Generate `.field-meta.xml` files in `force-app/main/default/objects/Asset/fields/`. Mirror the file structure pattern from telcoFlow.

**Acceptance criteria:**
- All 18 pest Asset fields deployed.
- No telco-named telemetry fields present.

### Ticket P1.3 — Drop PMT custom fields + delete PMT Apex/LWC references

**Phase:** P1
**Type:** metadata + cleanup
**Depends on:** P0.2
**Estimated effort:** 3 hours

**Scope:** Decide upfront not to port any PMT scaffolding. Specifically: do not deploy `PMT_Task__c`, `PMT_Project__c`, `PMT_Phase__c`, `Project_Day__c`, `Project_Day_Of_Total__c`, `Children_Completed__c`, `Children_Total__c`, `Project_Pct_Complete__c`, `Defer_Reason__c`, or `Work_Order_Coverage_Type__c` on WorkOrder. Do not port `PMTTaskToWorkOrderSpawner.cls` or `dispatch_WOProjectContext` LWC. Document the decision in `docs/SOLUTION_DESIGN.md`.

**Acceptance criteria:**
- WorkOrder has no PMT_* fields.
- Repo has no `PMTTaskToWorkOrderSpawner` references.
- Repo has no `dispatch_WOProjectContext` directory.
- `docs/SOLUTION_DESIGN.md` notes the PMT-not-modeled decision.

### Ticket P1.4 — Replace telco Skills with pest Skills

**Phase:** P1
**Type:** metadata
**Depends on:** P0.2
**Estimated effort:** 2 hours

**Scope:** Author 10 new `.skill-meta.xml` files for pest:

- `Quarterly_Pest_Service` — residential GoGreen route work
- `Termite_Sentricon_Certified` — Sentricon AlwaysActive install + service
- `Termite_Liquid_Soil_Treatment` — Termidor liquid application
- `Mosquito_System_Service` — Mosquito Hunter system install + maintenance
- `ULV_Fogging_Certified` — area mosquito fogging
- `Lawn_Turf_Care` — lawn fertilization + weed/insect control
- `Wasp_Bee_Removal` — stinging-insect removal (PPE-intensive)
- `RUP_Licensed_Applicator` — Restricted-Use Pesticide license required
- `Bilingual_English_Spanish` — customer-facing communication skill
- `Customer_De_escalation` — keep this generic skill from telco

**Implementation guidance:** Skills metadata uses `<label>` not `<masterLabel>` and rejects `<description>`. Match the minimal accepted format from telcoFlow's `.skill-meta.xml` files.

**Acceptance criteria:**
- 10 skill records exist post-deploy.

### Ticket P1.5 — Replace Work Types via seed script

**Phase:** P1
**Type:** Apex / data
**Reference:** `scripts/apex/seed_work_types.apex`
**Depends on:** P1.4
**Estimated effort:** 3 hours

**Scope:** Author `scripts/apex/seed_work_types.apex`. Define 10 pest Work Types:

| Work Type | Default Duration | Notes |
|---|---|---|
| Quarterly Pest Service | 0.5h | Standard residential GoGreen route stop |
| Pest Inspection (New) | 1h | Pre-service home assessment |
| Termite Inspection (Booster) | 1h | Proactive scenario inspection |
| Sentricon Install | 2.5h | Bait station perimeter install |
| Sentricon Service | 1h | Quarterly station check |
| Termite Liquid Treatment | 4h | Termidor soil treatment, full perimeter |
| Mosquito System Install | 3h | Perimeter system + first charge |
| Mosquito System Service | 1h | Monthly system charge + nozzle check |
| Mosquito Surge Area Treatment | 2h | Cluster-response area larvicide + ULV fog |
| Wasp / Stinging Insect Removal | 1.5h | PPE-required emergency response |

Set `AutoCreateServiceAppointment = true` on all except Termite Liquid Treatment (parent + child SA pattern, similar to telco's Tower Climb).

**Acceptance criteria:**
- 10 pest Work Types exist post-script-run.
- Re-running the script is idempotent.

### Ticket P1.6 — Replace WorkPlan + WorkStep templates per Work Type

**Phase:** P1
**Type:** Apex / data
**Depends on:** P1.5
**Estimated effort:** 8 hours

**Scope:** Author 10 WorkPlan records and ~50 WorkStep records covering the standard step categories: `Safety_Critical`, `Safety_Site`, `Safety_Admin`, `Hazard`, `Work_DeEnergize`, `Work_Execute`, `Work_ReEnergize`. **Keep API names** — only displayed labels swap via Custom Labels in P2.1. In pest context: `Work_DeEnergize` → "Pre-Treatment Setup" label; `Work_ReEnergize` → "Post-Treatment Verification" label.

Examples:
- **Quarterly Pest Service:** PPE check (Safety_Critical) → Vehicle/site brief (Safety_Site) → Customer ID confirmed (Safety_Admin) → Pre-treatment perimeter walk (Work_DeEnergize) → Apply treatment (Work_Execute) → Verify coverage + customer sign-off (Work_ReEnergize)
- **Mosquito Surge Area Treatment:** PPE confirmed incl. respirator (Safety_Critical) → Weather check, no-rain window (Safety_Site) → Permit-to-treat logged (Safety_Admin) → Locate breeding source (Work_DeEnergize) → Apply larvicide + ULV fog perimeter (Work_Execute) → Verify nozzle output + perimeter coverage (Work_ReEnergize)
- **Sentricon Install:** PPE check (Safety_Critical) → Locate property boundary + utilities (Safety_Site) → Customer signed install agreement (Safety_Admin) → Mark station locations (Work_DeEnergize) → Drill + insert stations (Work_Execute) → Verify station spacing + register in system (Work_ReEnergize)

**Implementation guidance:** Same two-substep path as telco — deploy WorkStepTemplate field-mirror first, then seed via Apex. New script: `scripts/apex/seed_work_plan_templates.apex`.

**Acceptance criteria:**
- 10 WorkPlan records exist.
- ~50 WorkStep records exist with correct `Step_Category__c` values.
- Each Work Type's plan has at least one Safety_Critical step.

### Ticket P1.7 — Add upsell custom fields on Account

**Phase:** P1
**Type:** metadata
**Depends on:** P0.2
**Estimated effort:** 2 hours

**Scope:** Add three custom fields on Account driving the upsell coaching surface (Phase P3 and P5):

| Field | Type | Purpose |
|---|---|---|
| `Eligible_Upsells__c` | Multi-select picklist (Pest, Termite, Mosquito, Lawn) | Which service lines this customer is eligible for upsell on |
| `Last_Upsell_Pitched__c` | DateTime | Most recent upsell pitch timestamp |
| `Last_Upsell_Service_Line__c` | Picklist (Pest / Termite / Mosquito / Lawn) | Which line was last pitched |
| `Last_Upsell_Outcome__c` | Picklist (Yes / NotNow / NotInterested / NoResponse) | Outcome of last pitch |
| `Upsell_Score__c` | Number(3,0) | 0–100 composite score from `UpsellCoachService` |
| `Upsell_Score_Last_Updated__c` | DateTime | Score recompute timestamp |

**Acceptance criteria:**
- 6 fields deployed on Account.
- Multi-select picklist allows all 4 service lines.
- Page layout updated to surface them on a "Revenue Coaching" section.

### Ticket P1.8 — Update ServiceTerritory + brand naming

**Phase:** P1
**Type:** Apex / data
**Reference:** `scripts/apex/seed_service_territory.apex`
**Depends on:** P0.1
**Estimated effort:** 1 hour

**Scope:** Author `seed_service_territory.apex` with single ServiceTerritory: "Massey Orlando Service Center". OperatingHours templates: Day Shift, Mosquito Season Extended Hours (Apr–Oct), Emergency Standby. US federal + Florida state holidays.

**Acceptance criteria:**
- Single Massey-named ServiceTerritory exists.
- 3 OperatingHours templates seeded.

---

## Phase P2 — Content swap: labels, knowledge, custom metadata (Days 5–10)

Five tickets. Replace telco-flavored content with pest content.

### Ticket P2.1 — Author Custom Labels for pest

**Phase:** P2
**Type:** metadata
**Reference:** `force-app/main/default/labels/CustomLabels.labels-meta.xml`
**Depends on:** P0.1
**Estimated effort:** 4 hours

**Scope:** Author the full Custom Labels file from scratch — every user-visible string in the demo. Keep the same label-name convention as telco (e.g., `ServiceImpact_PageTitle`, `SafetyGate_Header`, `Step_PreEnergize_Label` → "Pre-Treatment Setup"). Anchor the vocabulary to pest: "treatment", "service visit", "infestation", "swarm", "perimeter", "bait station", "applicator", "customer".

**Acceptance criteria:**
- All user-visible strings sourced from Custom Labels.
- No hardcoded "fiber", "ONT", "OLT", "circuit", "subscriber", or other telco vocabulary in labels.

### Ticket P2.2 — Refresh Hazard__c records for pest

**Phase:** P2
**Type:** Apex / data
**Reference:** `scripts/apex/seed_hazards.apex`
**Depends on:** P0.1
**Estimated effort:** 2 hours

**Scope:** Author `seed_hazards.apex` with pest-relevant hazards: chemical exposure (RUP), wasp/bee sting, dog bite (residential), ladder fall (overhead treatment), attic heat/confined space, fire ant exposure, snake (Florida wildlife), tick exposure, allergen reaction.

**Acceptance criteria:**
- ~9 Hazard__c records seeded.

### Ticket P2.3 — Repurpose `LOTO_Record__c` as Chemical Application Log

**Phase:** P2
**Type:** metadata + content
**Depends on:** P0.1
**Estimated effort:** 3 hours

**Scope:** Decide between two paths:

**Path A (recommended — minimal risk):** Keep object name `LOTO_Record__c`. Swap labels + field labels via Custom Labels and field-level `<label>` overrides. Add new fields: `EPA_Reg_Number__c`, `Chemical_Name__c`, `Target_Pest__c`, `Dose_Amount__c`, `Dose_Unit__c`, `Applicator_License__c`. Hide telco-era fields (Lockout_Source__c, etc.) via page layout, don't delete them.

**Path B (cleaner — more work):** Create new object `Chemical_Application_Log__c`, migrate every Apex/LWC reference, delete `LOTO_Record__c`. ~6 hours additional effort.

**Default to Path A** unless P3 owner pushes for B.

**Acceptance criteria:**
- Object renders with Restricted-Use Pesticide attestation UX.
- `LotoService.cls` (renamed in P3.1 to `ChemicalApplicationService.cls`) gates Step 4 of the orchestrator before chemical application.

### Ticket P2.4 — Refresh `Service_Boundary__mdt` + `Demo_Reply_Outcome__mdt`

**Phase:** P2
**Type:** custom metadata / data
**Depends on:** P0.1
**Estimated effort:** 3 hours

**Scope:** Service_Boundary__mdt records cover Orlando-area service zones: Avalon Park (32828), Lake Nona (32827), Winter Park (32789), Oviedo (32765), Apopka (32703). Demo_Reply_Outcome__mdt simulates customer responses to proactive outreach + upsell pitches.

**Acceptance criteria:**
- 5 Orlando service boundaries seeded.
- Reply outcomes cover Yes / NotNow / NotInterested / NoResponse with weighted distributions.

### Ticket P2.5 — Author 12 Knowledge articles for pest topics

**Phase:** P2
**Type:** content / manual
**Depends on:** P0.1
**Estimated effort:** 6 hours (mostly content writing)

**Scope:** Author 12 Knowledge articles to back Agentforce topic resolutions:

1. Identifying common Florida ants (sugar ant vs. carpenter vs. fire)
2. Termite swarm vs. flying ant — how to tell the difference
3. Sentricon AlwaysActive — how it works, expected timeline
4. Mosquito breeding sites in your yard — what to look for
5. Florida termite season (March–May): what to expect
6. Restricted-Use Pesticide safety — what your tech is doing and why
7. After-treatment expectations: when will I see results?
8. Pet + child safety on treatment day
9. Lawn fungus vs. drought stress — visual ID guide
10. Wasp / yellow-jacket nest removal: timing + safety
11. Mosquito Hunter system maintenance — what we cover
12. Quarterly pest service: what's included, what's not

**Acceptance criteria:**
- 12 articles published in Knowledge.
- Each tagged to the corresponding Agentforce topic.

---

## Phase P3 — Apex renames + UpsellCoachService (Days 8–12)

Four tickets. Rename telco-specific Apex, delete dead Apex, build the new upsell engine.

### Ticket P3.1 — Rename + retone telco-specific Apex classes

**Phase:** P3
**Type:** Apex
**Depends on:** P1.2, P1.7
**Estimated effort:** 6 hours

**Scope:** Rename + rewrite analyzer/service classes for pest semantics:

- `LineHealthAnalyzer` → `PestPressureAnalyzer` — input: Account + lookback days; output: composite pest pressure score + plain-language diagnosis
- `NetworkTopologyService` → `PropertyTreatmentHistoryService` — returns property service history, station states, prior treatments
- `FiberAcceptancePackageGenerator` → `TreatmentReportGenerator` — emits a treatment report with chemical + dose + EPA reg log
- `LotoService` → `ChemicalApplicationService` — gate logic for RUP attestation
- `AmiReadingService` → `BaitStationReadingService` — fetches bait station state + history

Rewrite each class body with pest-relevant logic. Keep method signatures stable so callers don't break.

**Acceptance criteria:**
- 5 class renames complete with `<ClassName>Test.cls` test classes updated.
- ≥75% coverage on each renamed class.

### Ticket P3.2 — Delete telco-only Apex classes

**Phase:** P3
**Type:** cleanup
**Depends on:** P1.3
**Estimated effort:** 2 hours

**Scope:** Delete classes that have no pest analogue:

- `PMTTaskToWorkOrderSpawner` (PMT bridge)
- `PoleAttachmentService` (telco-specific)
- `LocateTicketService` (telco/utility-specific — pest doesn't dig)
- `NorsReportGenerator` (telco regulatory report — replaced by `TreatmentReportGenerator` from P3.1)
- `DeviceCommandService` (remote ONT commands — no pest equivalent)

**Acceptance criteria:**
- Classes deleted via destructive package.
- No remaining references in surviving Apex / LWCs.

### Ticket P3.3 — Sweep + retone surviving Apex for pest context

**Phase:** P3
**Type:** Apex
**Depends on:** P3.1, P3.2
**Estimated effort:** 6 hours

**Scope:** Audit every surviving Apex class for telco strings (subscriber, ONT, OLT, fiber, splice, network, circuit, port, MNO). Retone diagnostic strings + comments + log messages for pest. Classes to sweep:
`AppointmentBooker`, `AppointmentCanceler`, `AppointmentConfirmer`, `AppointmentRescheduler`, `ChurnRiskScorer`, `ClusterDetector`, `DemoDataLoader`, `DispatcherScenarioLoader`, `DispatcherSummaryService`, `EmergencyDivertOrchestrator`, `EscalationContextBuilder`, `ImpactPreviewService`, `IncidentDispatchService`, `IncidentNotifyService`, `KnowledgeArticleSuggester`, `NextBestActionService`, `NocMapService`, `OrgBootstrap`, `OutageStatusLookup`, `PhotoAnalysisService`, `PlanChangeService`, `PredictiveFailureForecaster`, `ProactiveWoGenerator`, `RemoteRemediationService`, `RestorationVerifier`, `RiskBriefingService`, `SafetyBriefService`, `ServiceAreaValidator`, `ServiceStartOrchestrator`, `SmartDispatchSuggester`, `SubscriberNotificationService`, `TruckStockService`, `VisitSummaryGenerator`, `WOCompletionRollupHelper`.

Note: `SubscriberNotificationService` should be renamed `CustomerNotificationService`.

**Acceptance criteria:**
- `grep -rEi "subscriber|onts?|olt|fiber|splice|telco|coax|docsis|smallcell"` returns zero hits in `force-app/main/default/classes/`.
- All test classes still pass with ≥75% coverage.

### Ticket P3.4 — Build `UpsellCoachService.cls` + tests *(NEW)*

**Phase:** P3
**Type:** Apex
**Depends on:** P1.7, P3.1
**Estimated effort:** 8 hours

**Scope:** Net-new Apex class implementing the upsell coaching surface:

```apex
public with sharing class UpsellCoachService {
    public class UpsellRecommendation {
        @AuraEnabled public String serviceLine;       // Pest/Termite/Mosquito/Lawn
        @AuraEnabled public Integer score;            // 0–100
        @AuraEnabled public List<String> reasonCodes; // e.g., 'NEIGHBOR_BOUGHT_MOSQUITO'
        @AuraEnabled public String suggestedTalkTrack;
        @AuraEnabled public Decimal estimatedAnnualValue;
    }

    @AuraEnabled(cacheable=true)
    public static List<UpsellRecommendation> recommend(Id accountId) { /* ... */ }

    @AuraEnabled
    public static Id captureOutcome(Id accountId, String serviceLine, String outcome) { /* spawns Lead on Yes */ }
}
```

Ranking inputs: existing service lines on Account, neighborhood signals (other Massey customers in same ZIP/street), seasonal multipliers (FL termite Mar–May, mosquito Apr–Oct), property characteristics (lot size, age, conducive conditions), customer tenure.

Talk-tracks should be empathetic + low-pressure ("While I'm here..." framing) — populated from a Custom Metadata table `Upsell_Talk_Track__mdt` to allow content tuning without code changes.

**Acceptance criteria:**
- `recommend()` returns ranked list, top result first.
- `captureOutcome()` with outcome='Yes' creates Lead linked to Account, returns Lead Id.
- ≥85% test coverage (this is a load-bearing class).
- `Upsell_Talk_Track__mdt` Custom Metadata seeded with ~12 talk-track records.

---

## Phase P4 — Agentforce + Voice (Days 10–13)

Three tickets. Mostly admin UI; Claude Code hands these back.

### Ticket P4.1 — Provision Service Cloud Voice number + IVR routing

**Phase:** P4
**Type:** manual / external procurement
**Depends on:** none
**Estimated effort:** 5–10 business days lead time

**Scope:** Procure Voice number for the Massey Orlando branch. Configure IVR routing for inbound calls → Agentforce. **Kick off in P0** to absorb lead time.

### Ticket P4.2 — Rewrite 8 Agentforce topics + refresh Sidekick library

**Phase:** P4
**Type:** config (admin UI)
**Depends on:** P2.5
**Estimated effort:** 6 hours

**Scope:** 8 topics:

1. Pest Inquiry (ants, roaches, spiders, etc.)
2. Termite Concern (swarm sighting, damage report)
3. Mosquito Surge (post-storm cluster handling)
4. New Service Inquiry
5. Billing Dispute
6. Reschedule / Cancel Appointment
7. Service Complaint (efficacy concern)
8. Entomology Specialist Escalation

Sidekick library cards: Empathy scripts, Same-week service offer, Retention credit eligibility, Photo-ID assist, Knowledge article suggestion.

### Ticket P4.3 — Build "Upsell Recommendation" Agentforce topic *(NEW)*

**Phase:** P4
**Type:** config (admin UI)
**Depends on:** P3.4
**Estimated effort:** 3 hours

**Scope:** New Agentforce topic invokes `UpsellCoachService.recommend(accountId)` and renders top recommendation as a conversational suggestion. Sidekick library entry surfaces the top recommendation as a card on inbound calls.

**Acceptance criteria:**
- Topic invocable by Jordan via "Run upsell pitch" button on Account record page.
- Sidekick auto-suggests upsell card on inbound calls when `Upsell_Score__c > 60`.

---

## Phase P5 — LWCs + scenes + portal (Days 11–18)

Eight tickets. The bulk of the build.

### Ticket P5.1 — Delete telco-only LWCs

**Phase:** P5
**Type:** cleanup
**Depends on:** P0.2
**Estimated effort:** 1 hour

**Scope:** Do not port these telco-specific LWCs:

- `poleAttachmentTracker`
- `locateTicketChecker`
- `fiber_AcceptanceReportViewer`
- `nocOutageMap` (replace with a simpler mosquito surge map in P5.5 if desired)
- `nocMajorIncidentManager` (replace with `branchIncidentManager` in P5.5)
- `serviceResourceCertCheck` (RUP license check is implicit in Skills — no LWC needed)
- `dispatch_WOProjectContext` (PMT-specific)
- `deviceCommandPanel` (no remote pest equipment commands)

**Acceptance criteria:**
- 8 telco LWCs absent from `force-app/main/default/lwc/`.

### Ticket P5.2 — Port orchestrator + 6 step LWCs as `masseyFlow*`

**Phase:** P5
**Type:** LWC
**Depends on:** P1.1, P1.2, P2.1, P3.1
**Estimated effort:** 12 hours

**Scope:** Port 7 LWCs from `telcoFlow*` namespace to `masseyFlow*`:

- `telcoFlowOrchestrator` → `masseyFlowOrchestrator`
- `telcoFlowStepHeader` → `masseyFlowStepHeader`
- `telcoFlowContextPanel` → `masseyFlowContextPanel`
- `telcoFlowSafetyStep` → `masseyFlowSafetyStep`
- `telcoFlowCrewStep` → `masseyFlowCrewStep`
- `telcoFlowSiteStep` → `masseyFlowSiteStep` *(integrates `masseyUpsellCoach` from P5.6)*
- `telcoFlowWorkStep` → `masseyFlowWorkStep` *(includes RUP attestation gate)*
- `telcoFlowOutageStep` → `masseyFlowServiceImpactStep`
- `telcoFlowSummaryStep` → `masseyFlowSummaryStep` *(integrates `masseyUpsellCoach`)*
- `telcoFlowLotoPanel` → `masseyFlowChemicalPanel`
- `telcoFlowNfcScanner` → `masseyFlowNfcScanner`
- `telcoFlowTruckStock` → `masseyFlowTruckStock`

Variant rendering driven by `Service_Line__c`. Pest variant: spray equipment + treatment perimeter. Termite variant: bait stations + soil treatment. Mosquito variant: nozzles + larvicide. Lawn variant: turf inputs + soil temp.

**Acceptance criteria:**
- All 12 LWCs render in the orchestrator end-to-end.
- Variant rendering switches correctly by `Service_Line__c`.
- 9 Quick Actions registered (orchestrator + 6 steps + standalones).

### Ticket P5.3 — Port `dispatch_*` LWCs

**Phase:** P5
**Type:** LWC
**Depends on:** P3.3
**Estimated effort:** 4 hours

**Scope:** Port 3 LWCs (`dispatch_ActivePSCDrawer`, `dispatch_SmartSuggester`, `dispatch_TopOfQueueSummary`) with pest-context labels + content. Drop `dispatch_WOProjectContext` (PMT — already deleted in P5.1).

**Acceptance criteria:**
- 3 LWCs render in Dispatcher Console.
- Mosquito Surge cluster lights up the PSC drawer correctly.

### Ticket P5.4 — Port `demoMagic*` LWCs

**Phase:** P5
**Type:** LWC
**Depends on:** P3.3
**Estimated effort:** 6 hours

**Scope:** Port 7 demoMagic LWCs:

- `demoMagicActivateIncident` → "Activate Mosquito Surge Cluster" Quick Action
- `demoMagicAssetProactiveRun` → "Run Pest Pressure Analysis" Quick Action
- `demoMagicClusterDetect` → "Detect Cluster" Quick Action
- `demoMagicDispatchField` → keep generic
- `demoMagicEmergencyDivert` → "Emergency Reassign Tom's Team" Quick Action
- `demoMagicNotifyCustomers` → keep generic
- `demoMagicProactiveWoRun` → "Generate Booster Inspection WOs" Quick Action
- `demoMagicSubscriber360` → `demoMagicCustomer360`
- `demoControlPanel` → keep generic

**Acceptance criteria:**
- All Quick Actions trigger the correct demo-magic flow.
- Customer 360 LWC renders pest service history.

### Ticket P5.5 — Port remaining LWCs

**Phase:** P5
**Type:** LWC
**Depends on:** P3.3
**Estimated effort:** 4 hours

**Scope:** Port 4 LWCs with pest content swap: `assetHierarchyVisualizer`, `aiInsightCard`, `sparklineChart`, `realTimePulse`. The hierarchy visualizer should render Property → Sentricon Stations / Mosquito Nozzles / Treatment Perimeters.

**Acceptance criteria:**
- All 4 LWCs render with pest-context data.

### Ticket P5.6 — Build `masseyUpsellCoach` LWC + integrate into orchestrator *(NEW)*

**Phase:** P5
**Type:** LWC
**Depends on:** P3.4, P5.2
**Estimated effort:** 8 hours

**Scope:** Net-new LWC. Surfaces in:
- Site step of orchestrator (top recommendation, talk-track collapsed)
- Summary step of orchestrator (full recommendation list, capture-outcome buttons)
- Standalone Quick Action on Account record page (Jordan / Ray view)

Wires `UpsellCoachService.recommend()` via `@wire`. Capture outcome calls `UpsellCoachService.captureOutcome()` imperatively. Renders talk-track in a presenter-friendly card with copy-to-clipboard. Tracks pitch outcome locally for offline support; syncs when back online.

**Acceptance criteria:**
- Renders in 3 surfaces.
- Outcome capture spawns Lead on Yes.
- Works offline (draft Lead syncs when back online).
- Komaci static analysis clean for offline use.

### Ticket P5.7 — Author seed data scripts

**Phase:** P5
**Type:** Apex / data
**Reference:** `scripts/apex/seed_demo_data.apex`
**Depends on:** P1.*, P3.*
**Estimated effort:** 12 hours

**Scope:** Comprehensive seed script for the demo dataset:

- ~120 Massey customer Accounts in Orange + Seminole counties
- ~120 Property Assets (one per Account) with realistic FL addresses
- ~280 child Assets: Sentricon stations on termite-protected properties, mosquito nozzles on Mosquito Hunter properties, treatment perimeters on all
- 47 properties in ZIP 32828 (Avalon Park) flagged for the cluster scenario
- 14 properties flagged `Is_Pest_Pressure_Candidate__c = true` for the proactive scenario
- ~50 historical WorkOrders with realistic completion patterns
- Sandra Reyes Account (4-year GoGreen tenure, no termite, kitchen ant call ready)
- David Kim signup pre-stage (Lake Nona address, eligible)
- Lisa Chen (Mosquito Hunter, Avalon Park, in cluster)
- ~12 entries in `Upsell_Talk_Track__mdt`

**Acceptance criteria:**
- Script idempotent (safe re-runs).
- All scenes have their seed data ready post-script.

### Ticket P5.8 — Massey Experience Cloud portal (`massey-portal`)

**Phase:** P5
**Type:** config (admin UI)
**Depends on:** P1.7, P3.3
**Estimated effort:** 8 hours (admin UI work)

**Scope:** Build LWR Experience Cloud site `massey-portal` for prospect/customer self-service. Pages: Home, Get a Quote, Plan Picker (with bundle pricing emphasis), Schedule Service, Account Portal. Embedded Agentforce Chat. Branded with Massey colors + logo (pending legal sign-off).

**Acceptance criteria:**
- Site reachable + David Kim signup flow works end-to-end (Scene 4).
- Bundle pricing visible on plan picker.

---

## Phase P6 — Manager dashboard + polish + docs (Days 18–22)

Five tickets. Close out the build.

### Ticket P6.1 — Build Manager Coaching dashboard + 4 reports *(NEW)*

**Phase:** P6
**Type:** dashboard + reports
**Depends on:** P3.4, P5.6, P5.7
**Estimated effort:** 6 hours

**Scope:** New dashboard "Massey Branch Coaching" with 4 reports:

1. **Attach Rate by Tech (MTD)** — leads created / WOs completed, by tech
2. **Top Performers (YTD)** — leaderboard with attach rate + revenue impact
3. **Coaching Opportunities** — techs with high route quality but low attach rate
4. **Leads from Route → Conversion** — how many Maria-style pitches close to revenue

Surfaces in Scene 9. Sidekick can suggest coaching nudges based on these numbers.

**Acceptance criteria:**
- Dashboard renders with seeded data.
- All 4 reports return non-empty results.

### Ticket P6.2 — Robustness sweep: telco-string audit + offline regression

**Phase:** P6
**Type:** QA
**Depends on:** P5.*
**Estimated effort:** 6 hours

**Scope:** Sweep entire repo for residual telco vocabulary using grep:

```bash
grep -rEi "subscriber|ont|olt|fiber|splice|telco|coax|docsis|smallcell|nora|circuit__c|pon__c" force-app/ docs/ scripts/
```

Any remaining hits get fixed or flagged. Then offline regression test on FSL Mobile: install briefcase, go airplane mode, run orchestrator end-to-end on a seeded WO, verify all 6 steps work + Lead capture works offline.

**Acceptance criteria:**
- grep returns 0 hits (or only intentional historical-context hits in narrative docs).
- Full offline orchestrator run completes without errors.

### Ticket P6.3 — Author DEMO_PRESENTER_NOTES.md

**Phase:** P6
**Type:** documentation
**Depends on:** P5.*
**Estimated effort:** 4 hours

**Scope:** Scene-by-scene presenter cues for the 9 scenes. What to say, what to click, what to highlight. Especially detailed for Scene 5 (the marquee upsell scene) and Scene 9 (manager coaching dashboard).

### Ticket P6.4 — Author SOLUTION_DESIGN.md (pest version)

**Phase:** P6
**Type:** documentation
**Depends on:** P1.*, P3.*, P5.*
**Estimated effort:** 6 hours

**Scope:** Long-form solution design — data model, AI surfaces, scenes, upsell architecture, manager coaching layer, offline strategy. Replaces the telco solution design.

### Ticket P6.5 — Author DEPLOYMENT_INSTRUCTIONS.md

**Phase:** P6
**Type:** documentation
**Depends on:** all prior phases
**Estimated effort:** 4 hours

**Scope:** Fresh-org deployment sequence. Drops PMT package install. Adds Massey portal setup, Voice number config, Agentforce topic config, Knowledge article import. ~30% shorter than the telco equivalent.

---

## Manual / config / external checkpoints

These tickets cannot be completed by Claude Code — admin UI or external procurement.

- **P4.1** — Voice number procurement (kick off in P0; 5–10 business day lead)
- **P4.2** — Agentforce topic config (admin UI)
- **P4.3** — New Upsell Recommendation topic config (admin UI)
- **P2.5** — Knowledge article authoring (content)
- **P5.8** — Experience Cloud portal config (admin UI)
- **Massey brand-use sign-off** — confirm with legal before any external presentation

When Claude Code hits one of these, stop and report.

---

## Status tracking

`git log` is authoritative for ticket completion. Each ticket merges as one commit with `[Pn.x]` prefix in the subject line. External tracker (Notion / Linear / GitHub Issues) optional for the human builder.
