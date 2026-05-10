# Massey Services Demo — Deployment Instructions

**Status:** Authored in P6.5 (replaces the P0.2 stub).
**Authoritative for:** fresh-org deployment sequence, custom field reference, Quick Action setup, Permission Set assignments, Briefcase Builder configuration, seed-data run order, manual-checkpoint sign-off list.
**Source-of-truth rank:** #3. See `CLAUDE.md` for the hierarchy. Where this doc disagrees with `docs/PEST_NARRATIVE.md` or `ARCHITECTURE_PROPOSAL.md`, those win.
**Owner:** Allen Diaz de Leon.

This is the runbook for deploying the masseyFlow demo into a fresh Salesforce org. Approximately 30% shorter than the telco equivalent — the PMT capital-program package install is dropped, and the upsell + tech-coaching surface is added.

---

## 0. Pre-deploy checklist

Confirm every line below before kicking off step 1.

- [ ] Org edition: **Enterprise**, **Unlimited**, or **Developer** with Service Cloud + Field Service Lightning licensed.
- [x] **Massey brand-use legal sign-off CONFIRMED** (2026-05-10). Demo can be presented externally.
- [ ] Service Cloud Voice number **already provisioned** in target org. Allen owns this; no procurement work in this run. See section 6.
- [ ] Salesforce CLI **2.x** installed; authenticated to target org (`sf org login web --alias <alias>`).
- [ ] Massey FSL package(s) installed in target org (managed FSL package + any AppExchange dependencies the parent org already carries).
- [ ] **Briefcase Builder** enabled (Setup → Mobile Apps → Field Service Mobile → Briefcase).
- [ ] **Knowledge** enabled (Setup → Knowledge Settings → Enable Lightning Knowledge).
- [ ] **Experience Cloud (LWR)** enabled (Setup → Digital Experiences → Settings → Enable Digital Experiences).
- [ ] FLS / record-type setup for `Account`, `Asset`, `WorkOrder`, `Incident`, `LOTO_Record__c`, `Hazard__c` reviewed for the deployment user.

---

## 1. Repository deploy sequence

The repo is structured so that a single deploy of `force-app` resolves cleanly into a fresh org. From the repo root:

```bash
sf project deploy start -d force-app --target-org <alias>
```

This command deploys, in metadata-resolved order:

1. **Custom Objects + Fields** — `Account`, `Asset`, `WorkStep`, `WorkStepTemplate`, `Hazard__c`, `LOTO_Record__c`, `Demo_Reply_Outcome__mdt`, `Service_Boundary__mdt`, `Upsell_Talk_Track__mdt`. (`WorkOrder` and `Incident` field deltas are deployed inline against the standard objects; see section 2.)
2. **Custom Labels** — 80+ labels in `CustomLabels.labels-meta.xml` (P2.1).
3. **Apex classes + tests** — 39 classes total; `UpsellCoachService` is load-bearing (P3.4 target ≥85% coverage).
4. **Lightning Web Components** — 30 LWCs under `force-app/main/default/lwc/`.
5. **Quick Actions** — 9 explicit XML Quick Actions (8 demoMagic + 1 masseyUpsellCoach). The 7 masseyFlow* orchestrator/step components are exposed as Screen Actions via their `lightning__RecordAction` target in the LWC `.js-meta.xml` — no separate Quick Action XML needed.
6. **Custom Metadata Type records** — `Demo_Reply_Outcome__mdt`, `Service_Boundary__mdt`, `Upsell_Talk_Track__mdt` (12 talk-track records authored in P3.4) ship as records under `force-app/main/default/customMetadata/` and deploy with the metadata.
7. **Flows, Layouts, Tabs, Skills, Reports, Dashboards** — remaining metadata.

**Known ordering pitfalls:**
- `Hazard__c.Work_Order__c` is master-detail on `WorkOrder`. The metadata layer handles forward-references, but if you are pushing piecemeal (NOT recommended), deploy `Hazard__c` after `WorkOrder` field updates.
- `LOTO_Record__c.Work_Order__c` is also master-detail on `WorkOrder` (P2.3 Path A — same name as telco, content swapped). Same pitfall, same mitigation.
- Custom Metadata Type records (`__mdt`) cannot be inserted via Apex DML; they ship in the deploy payload as XML.

**Validate-only run (recommended first pass):**

```bash
sf project deploy validate -d force-app --target-org <alias> --test-level RunLocalTests
```

---

## 2. Custom field reference (full)

~90 custom fields across 10 objects + 3 Custom Metadata Types. Source-of-truth for definitions: `force-app/main/default/objects/<Object>/fields/<Field>.field-meta.xml`. This table summarizes; consult the XML for picklist values and FLS defaults.

### 2.1 Account — 6 fields (P1.7, upsell surface, NEW vs telco)

| API Name | Type | Purpose |
|----------|------|---------|
| `Eligible_Upsells__c` | Multi-select Picklist (Pest / Termite / Mosquito / Lawn) | Which lines this Account is eligible to be pitched |
| `Last_Upsell_Pitched__c` | DateTime | Most recent pitch timestamp |
| `Last_Upsell_Service_Line__c` | Picklist | Which line was last pitched |
| `Last_Upsell_Outcome__c` | Picklist (Yes / NotNow / NotInterested / NoResponse) | Outcome captured by tech / agent |
| `Upsell_Score__c` | Number(3,0) | 0–100 composite from `UpsellCoachService.recommend()` |
| `Upsell_Score_Last_Updated__c` | DateTime | Score recompute timestamp |

### 2.2 WorkOrder — 7 fields (inherited, flow-control + cluster)

| API Name | Type | Purpose |
|----------|------|---------|
| `Current_Step__c` | Number(2,0) | Tracks which step the tech is on (0–5) |
| `Flow_Started_At__c` | DateTime | Timestamp when tech first launched the flow |
| `Flow_Completed_At__c` | DateTime | Timestamp when all 6 steps done |
| `Safety_Gate_Status__c` | Picklist (Locked / Partial / Passed) | Field-history tracked |
| `Safety_Gate_Passed_At__c` | DateTime | Field-history tracked |
| `Outage_Cause__c` | Picklist | Label "Cluster Cause" via P2.1 |
| `Linked_Incident__c` | Lookup(Incident) | Field-history tracked |

### 2.3 WorkStep — 5 fields (inherited, runtime)

| API Name | Type | Purpose |
|----------|------|---------|
| `Step_Category__c` | Picklist | Safety_Critical / Safety_Site / Safety_Admin / Work_DeEnergize / Work_Execute / Work_ReEnergize / Hazard |
| `Is_Critical__c` | Checkbox | Blocks safety gate if unchecked |
| `Completed_At__c` | DateTime | When the tech toggled the item |
| `Completed_By__c` | Text(18) | Text (not Lookup) to avoid offline priming issues |
| `Sort_Order__c` | Number | Display order within category |

### 2.4 WorkStepTemplate — 2 fields (inherited, template)

| API Name | Type | Purpose |
|----------|------|---------|
| `Step_Category__c` | Picklist | Mirrors WorkStep; carried into spawned WorkSteps |
| `Is_Critical__c` | Checkbox | Mirrors WorkStep; carried into spawned WorkSteps |

### 2.5 Incident — 4 fields (inherited; relabeled per Architecture decision #20)

| API Name | Type | Label |
|----------|------|-------|
| `Circuit__c` | Text(50) | "Cluster Identifier" via P2.1 (e.g., `ZIP-32828-Mosquito`) |
| `Affected_Customers__c` | Number | "Affected Properties" via P2.1 |
| `Outage_Latitude__c` | Number(3,7) | "Cluster Latitude" via P2.1 |
| `Outage_Longitude__c` | Number(3,7) | "Cluster Longitude" via P2.1 |

API names preserved to avoid migration churn. New code references them by API name; UI uses the relabeled Custom Labels.

### 2.6 Asset — 19 fields (P1.1 + P1.2, pest schema)

`Service_Line__c` is **required** and drives variant rendering across all step LWCs.

| API Name | Type |
|----------|------|
| `Service_Line__c` | Picklist (Pest / Termite / Mosquito / Lawn — restricted, required) |
| `Equipment_Type__c` | Picklist (Property / Sentricon_Station / Mosquito_System / Mosquito_Nozzle / Trap / Treatment_Perimeter) |
| `Equipment_Model__c` | Text(80) |
| `Bait_Station_State__c` | Picklist (Untouched / Activity / Heavy_Activity / Replaced) |
| `Last_Bait_Station_Hit_Date__c` | Date |
| `Bait_Station_Hits_30d__c` | Number(3,0) |
| `Soil_Temp_F__c` | Number(4,1) |
| `Conducive_Conditions__c` | Checkbox |
| `Pest_Pressure_Score__c` | Number(3,0) |
| `Trap_Catch_Count_24h__c` | Number(4,0) |
| `Last_Treatment_DateTime__c` | DateTime |
| `Days_Since_Last_Service__c` | Number(4,0) |
| `Is_Pest_Pressure_Candidate__c` | Checkbox |
| `EPA_Reg_Number_Last_Used__c` | Text(20) |
| `Conducive_Notes__c` | Long Text(2000) |
| `NFC_Tag_Id__c` | Text(100), External ID, Unique |
| `Service_Group__c` | Text(40) |
| `Property_Type__c` | Picklist (Single_Family / Townhome / Condo / Multi_Family) |
| `Lot_Size_Sqft__c` | Number(8,0) |

### 2.7 LOTO_Record__c — 19 fields (P2.3, Path A — repurposed as Chemical Application Log)

13 inherited API names + 6 net-new pest fields. Object renamed via label, API name preserved.

| API Name | Type | Notes |
|----------|------|-------|
| `Work_Order__c` | Master-detail(WorkOrder) | Required; offline-relationship anchor |
| `Status__c` | Picklist | Reused: Locked / Verified / Removed pattern → RUP gate states |
| `Energy_Source__c` | Picklist | Inherited; relabeled as application source via P2.1 |
| `Isolation_Point__c` | Text | Inherited; relabeled |
| `Lock_Tag_Number__c` | Text | Inherited |
| `Isolated_By__c` / `Isolated_At__c` | Text(18) / DateTime | Inherited |
| `Verified_By__c` / `Verified_At__c` | Text(18) / DateTime | Inherited |
| `Removed_By__c` / `Removed_At__c` | Text(18) / DateTime | Inherited |
| `Photo_ContentVersion_Id__c` | Text(18) | Inherited |
| `Notes__c` | Long Text | Inherited |
| `Applicator_License__c` | Text(40) | **NEW** — RUP applicator license # |
| `Chemical_Name__c` | Text(80) | **NEW** — chemical brand name |
| `EPA_Reg_Number__c` | Text(20) | **NEW** — EPA registration # |
| `Dose_Amount__c` | Number(8,2) | **NEW** — applied dose |
| `Dose_Unit__c` | Picklist | **NEW** — fl-oz / oz / lb / gal |
| `Target_Pest__c` | Picklist | **NEW** — Subterranean_Termite / Aedes / Argentine_Ant / etc. |

### 2.8 Hazard__c — 6 fields (P2.2, domain-neutral)

| API Name | Type |
|----------|------|
| `Work_Order__c` | Master-detail(WorkOrder), required |
| `Description__c` | Long Text |
| `Severity__c` | Picklist |
| `Status__c` | Picklist |
| `Reported_By__c` | Text(18) |
| `Reported_At__c` | DateTime |

### 2.9 Demo_Reply_Outcome__mdt — 2 fields (P2.4)

| API Name | Type |
|----------|------|
| `Outcome__c` | Picklist |
| `Person_Account_Name__c` | Text |

### 2.10 Service_Boundary__mdt — 5 fields (P2.4)

| API Name | Type |
|----------|------|
| `Address_Pattern__c` | Text |
| `Canonical_Address__c` | Text |
| `In_Service_Area__c` | Checkbox |
| `Latitude__c` | Number |
| `Longitude__c` | Number |

### 2.11 Upsell_Talk_Track__mdt — 5 fields (P3.4, NEW)

| API Name | Type |
|----------|------|
| `Active__c` | Checkbox |
| `Service_Line__c` | Picklist (Pest / Termite / Mosquito / Lawn) |
| `Reason_Code__c` | Text — keys into `UpsellCoachService` ranking |
| `Talk_Track__c` | Long Text — empathetic, low-pressure copy |
| `Estimated_Annual_Value__c` | Currency |

12 talk-track records ship in `force-app/main/default/customMetadata/`.

---

## 3. Quick Actions (10 total)

8 demoMagic + 1 upsell-coach + 1 implicit orchestrator-set:

| Action | Object | XML File |
|--------|--------|----------|
| Run Pest Pressure Analysis | Asset | `Asset.DemoMagic_Run_Pest_Pressure_Analysis.quickAction-meta.xml` |
| Detect Cluster | Case | `Case.DemoMagic_Detect_Cluster.quickAction-meta.xml` |
| Activate Mosquito Surge | Incident | `Incident.DemoMagic_Activate_Mosquito_Surge.quickAction-meta.xml` |
| Dispatch Field | Incident | `Incident.DemoMagic_Dispatch_Field.quickAction-meta.xml` |
| Emergency Reassign (Incident) | Incident | `Incident.DemoMagic_Emergency_Reassign.quickAction-meta.xml` |
| Notify Cluster Customers | Incident | `Incident.DemoMagic_Notify_Cluster_Customers.quickAction-meta.xml` |
| Generate Booster Inspection WOs | RecordsetFilterCriteria | `RecordsetFilterCriteria.DemoMagic_Generate_Booster_Inspection_WOs.quickAction-meta.xml` |
| Emergency Reassign (Resource) | ServiceResource | `ServiceResource.DemoMagic_Emergency_Reassign.quickAction-meta.xml` |
| **Massey Upsell Coach** | Account | `Account.MasseyUpsellCoach.quickAction-meta.xml` (P5.6) |

**Implicit Quick Actions (no XML):** `masseyFlowOrchestrator` plus the 6 step LWCs (`masseyFlowSafetyStep`, `masseyFlowCrewStep`, `masseyFlowSiteStep`, `masseyFlowWorkStep`, `masseyFlowOutageStep`, `masseyFlowSummaryStep`) declare `<target>lightning__RecordAction</target>` and `<actionType>ScreenAction</actionType>` in their `.js-meta.xml`. The platform exposes them as Quick Actions on WorkOrder automatically — admins assign them via Page Layout. This is intentional per Architecture decision #1.

---

## 4. Permission Sets

Four permission sets ship as XML under `force-app/main/default/permissionsets/`. Each is assigned to its persona's user record at install time.

| Permission Set | File | Persona(s) | Object Perms | Field Perms | Apex Class Access | Tabs |
|----------------|------|------------|--------------|-------------|-------------------|------|
| `Massey_FSL_Technician` | `Massey_FSL_Technician.permissionset-meta.xml` | Maria Lopez, Tom Walker | 21 (R+E on FSL ops objects; R+C+E on WorkPlan/WorkStep/Lead/LOTO/Hazard) | 64 (All masseyFlow custom fields, mostly R+E) | 19 (PestPressureAnalyzer, ChemicalApplicationService, UpsellCoachService, etc.) | 0 (mobile only) |
| `Massey_Branch_Agent` | `Massey_Branch_Agent.permissionset-meta.xml` | Jordan Martinez | 11 (R+C+E on Account/Case/Lead/SA/WO; R on Asset/Incident/PSC) | 56 (Account upsell R+E; Asset R; WO R+E; Incident R) | 18 (AppointmentBooker, KnowledgeArticleSuggester, UpsellCoachService, etc.) | 6 (Service Console) |
| `Massey_Branch_Manager` | `Massey_Branch_Manager.permissionset-meta.xml` | Ray Garcia | 12 (R+E on dispatch/cluster objects; R on customer-facing) | 56 (Account upsell R; Asset R; WO R+E; Incident R+E) | 16 (ClusterDetector, EmergencyDivertOrchestrator, dispatch_*, UpsellCoachService) | 6 (Reports/Dashboards/dispatch) |
| `Massey_Demo_Admin` | `Massey_Demo_Admin.permissionset-meta.xml` | Presenter | 22 (R+C+E+D on every demo object) | 78 (every Massey custom field R+E) | 39 (all pest classes) | 13 (all demo tabs) |

**Safety:** none of the four permsets grant `ModifyAllData`, `CustomizeApplication`, `<modifyAllRecords>true>`, or `<viewAllRecords>true>`. Demo Admin grants only `ViewSetup` (navigation, non-elevating).

---

## 5. Briefcase Builder configuration

Per `ARCHITECTURE_PROPOSAL.md` § 6.4. Setup → Briefcase Builder → New Briefcase: **"Massey FSL Mobile"**.

| # | Root | Path | Depth | Filter |
|---|------|------|-------|--------|
| 1 | WorkOrder | → WorkPlan → WorkStep | 2 | `Status IN ('New','Scheduled','In Progress','Dispatched')` AND assigned to current resource within next 7 days |
| 2 | WorkOrder | → Asset (via `AssetId`) | 1 | follows path 1 |
| 3 | WorkOrder | → Account (via `AccountId`) | 1 | **NEW vs telco** — needed for offline upsell surface |
| 4 | WorkOrder | → AssignedResource → ServiceResource | 2 | follows path 1 |
| 5 | WorkOrder | → ServiceCrew → ServiceCrewMember | 2 | follows path 1 |
| 6 | Incident | (direct) | 0 | `Status = 'Active'` AND `ServiceTerritory IN (resource territories)` AND `Circuit__c LIKE 'ZIP-%'` |

- **Refresh frequency:** every 4 hours when online; manual refresh on-demand from FSL Mobile.
- **Conflict resolution:** server wins on `WorkOrder.Status`, `Safety_Gate_Status__c`; client wins on `WorkStep.Completed_At__c`, draft Lead inserts (created offline).
- **Briefcase size budget:** target < 25 MB primed per resource. Each resource gets ~30 WOs × 3 levels deep.

---

## 6. Service Cloud Voice — ALREADY PROVISIONED

Per the project memory `project_voice_already_provisioned.md`, the Voice number plus IVR routing has **already been provisioned** in the target demo org. Allen owns this. **No procurement work needed** for this deploy.

If deploying into a brand-new org without Voice provisioned: that's a 5–10 business day external lead-time and is out of scope for this runbook. Kick off via Salesforce Voice Setup before starting any P4 work.

---

## 7. Agentforce topics + Sidekick library — Allen-owned

Admin UI work (Agentforce / Sidekick admin). **Owner: Allen.** Topic specs live in P4.2 / P4.3 of `docs/BUILD_TICKETS_PEST.md`.

**8 standard topics (P4.2):**

1. Pest Inquiry
2. Termite Concern
3. Mosquito Surge
4. New Service Inquiry
5. Billing Dispute
6. Reschedule
7. Service Complaint
8. Entomology Escalation

**1 NEW topic (P4.3):**

9. **Upsell Recommendation** — invoked from Sidekick on demand by Jordan; calls `UpsellCoachService.recommend(accountId)` and surfaces the top recommendation + talk-track inside the Sidekick chat.

**Sidekick library cards:**

- Empathy opener
- Same-week service offer
- Retention credit
- Photo-ID assist (knowledge linkout)
- Knowledge article suggestion (links into the published 12)
- **Talk-track suggestion** (NEW; reads from `Upsell_Talk_Track__mdt`)

---

## 8. Knowledge articles — Allen-owned (P2.5)

12 articles per `docs/BUILD_TICKETS_PEST.md` P2.5. Content authoring task; **owner Allen**. Publish in the order below and tag each to its corresponding Agentforce topic so Sidekick can return them during a call.

1. "What to expect on your first quarterly pest service" → Pest Inquiry
2. "Sentricon AlwaysActive: how monitoring works" → Termite Concern
3. "Termidor liquid treatment: 7-day re-entry FAQ" → Termite Concern
4. "Mosquito Hunter system maintenance" → New Service Inquiry
5. "After-storm mosquito surge: what we're doing in your neighborhood" → Mosquito Surge
6. "Lawn service: when to schedule first cut" → New Service Inquiry
7. "Reschedule windows + cancellation policy" → Reschedule
8. "Restricted-Use Pesticides: why your tech wears that gear" → Service Complaint
9. "Entomology escalation: how Massey investigates uncommon pests" → Entomology Escalation
10. "GoGreen vs traditional pest: the difference" → New Service Inquiry
11. "Billing: how quarterly auto-pay works" → Billing Dispute
12. "Pets, kids, and pesticide application: our safety policy" → Service Complaint

---

## 9. Experience Cloud — `massey-portal` — Allen-owned (P5.8)

LWR site. **Owner: Allen.** Setup → Digital Experiences → All Sites → New → LWR template.

**Pages:**

- Home (hero + value props)
- Get a Quote (lead capture form)
- Plan Picker (with bundled pricing for Pest + Mosquito + Lawn)
- Schedule Service (anonymous booking with `AppointmentBooker.cls`)
- Account Portal (authenticated; visit history, upsell offers, reschedule)

**Branding:** Massey colors + logo. Legal sign-off confirmed 2026-05-10.

**Embedded Agentforce Chat** on every page; chat config inherits from the org-level Agentforce setup (section 7).

---

## 10. Seed data execution order (CRITICAL)

5 anonymous Apex scripts under `scripts/apex/`. Run in **exact order** — `seed_hazards.apex` MUST run after `seed_demo_data.apex` because `Hazard__c.Work_Order__c` is master-detail and the hazards anchor on the oldest WorkOrder, which `seed_demo_data` creates.

```bash
sf apex run --file scripts/apex/seed_service_territory.apex --target-org <alias>
sf apex run --file scripts/apex/seed_work_types.apex          --target-org <alias>
sf apex run --file scripts/apex/seed_work_plan_templates.apex --target-org <alias>
sf apex run --file scripts/apex/seed_demo_data.apex           --target-org <alias>
sf apex run --file scripts/apex/seed_hazards.apex             --target-org <alias>
```

**All scripts are idempotent** — they SOQL-match a sentinel string (`[MSY-DEMO]`, `[HZ-...]`, etc.) and skip records that already exist. Reruns are safe.

**Custom Metadata Type records** (`Demo_Reply_Outcome__mdt`, `Service_Boundary__mdt`, `Upsell_Talk_Track__mdt`) ship via the metadata deploy in section 1 — **not seeded by Apex.** Do not attempt to insert `__mdt` records via DML.

---

## 11. Smoke test

Reference `docs/DEMO_PRESENTER_NOTES.md` (P6.3) for full scene-by-scene cues. Recommended fast smoke flow:

1. Open Sandra Reyes Account → confirm 4-year tenure visible on the record page header.
2. Open the Bennett Account → run **Massey Upsell Coach** Quick Action → verify Mosquito recommendation surfaces with the "neighbor on Maple Ave just enrolled" signal.
3. Open the Mosquito Surge Incident (Avalon Park 32828) → click **Activate Mosquito Surge Cluster** → verify the dispatcher PSC drawer lights up.
4. Open the Dispatcher Console → run **Emergency Reassign Tom's Team** → verify Tom's ServiceAppointments reassign to the backup resource.
5. On FSL Mobile (offline-mode ON): open a WO on Maria's tablet → run `masseyFlowOrchestrator` end-to-end → confirm draft Lead persists offline and syncs on reconnect.
6. Open the Manager Coaching dashboard (P6.1) → verify all 4 reports render: Attach Rate by Tech (MTD), Top Performers (YTD), Coaching Opportunities, Leads from Route → Conversion.

---

## 12. Manual checkpoints summary

Mirrored from `CLAUDE.md` and the P0.2 stub. Single source for a deploying admin.

- [x] **P4.1** — Voice number + IVR routing — ALREADY PROVISIONED in target org (2026-05-08). Owner: **Allen**.
- [ ] **P4.2** — 8 Agentforce topics + Sidekick library — Agentforce admin UI. Owner: **Allen**.
- [ ] **P4.3** — "Upsell Recommendation" Agentforce topic + Sidekick library entry — Agentforce admin UI. Owner: **Allen**.
- [ ] **P2.5** — 12 Knowledge articles — content authoring + publishing. Owner: **Allen**.
- [ ] **P5.8** — `massey-portal` Experience Cloud (LWR) site — Experience Cloud admin UI. Owner: **Allen**.
- [x] **Massey brand-use legal sign-off** — confirmed 2026-05-10. Owner: **Allen** (with legal).
- [ ] **P6.2 offline regression test** — manual device test on FSL Mobile (iPad + iPhone). Owner: **Allen**.
- [ ] **Scheduling Policies + Work Rules + Service Objectives** — Field Service Setup admin UI. Two policies recommended: Massey Standard (default) + Cluster Response. Owner: **Allen**.
- [x] **Permission Set authoring** — 4 permsets ship as XML in `force-app/main/default/permissionsets/`. Assign to each persona's user record at install time (section 4).

---

## 13. Rollback notes

The metadata-layer deploy is **non-destructive** — every object, field, label, Apex class, LWC, and Quick Action introduced is NEW; nothing overwrites stock Salesforce metadata. A failed deploy can be safely re-run.

Seed-script DML inserts can be rolled back via deletion of records carrying the `[MSY-DEMO]` sentinel in `Description` (Accounts, Assets, Cases, Incidents, Leads), `Subject` (WorkOrders), or the `[HZ-...]` prefix on `Hazard__c.Description__c`. Anonymous Apex cleanup pattern:

```apex
delete [SELECT Id FROM Account     WHERE Description LIKE '%[MSY-DEMO]%'];
delete [SELECT Id FROM WorkOrder   WHERE Subject     LIKE '%[MSY-DEMO]%'];
delete [SELECT Id FROM Incident    WHERE Subject     LIKE '%[MSY-DEMO]%'];
delete [SELECT Id FROM Hazard__c   WHERE Description__c LIKE '[HZ-%'];
```

Custom Metadata records are wiped by re-deploying with the records removed from the source XML — Salesforce does not support `__mdt` deletion via Apex DML.

---

## 14. Known limitations

- **Real device telemetry is mocked.** `Asset.Bait_Station_Hits_30d__c`, `Trap_Catch_Count_24h__c`, `Soil_Temp_F__c`, etc. are seeded statically. No real Sentricon / Mosquito Hunter telemetry pipeline.
- **Voice IVR resolution is scripted, not free-form.** The Sandra Reyes call (Scene 1) follows a deterministic path; ad-hoc utterances may not resolve cleanly.
- **Chemical inventory is taxonomy-only.** `LOTO_Record__c.Chemical_Name__c` and `EPA_Reg_Number__c` are picklist-style demo values; no real ERP integration.
- **No real entomology specialist queue.** The escalation in the "Entomology Escalation" Agentforce topic is staged for demo — Cases route to a pre-seeded queue but no live specialist is paged.
- **PMT capital-program bridge is not modeled.** Pest has no clean capital-program analogue. See `docs/PEST_NARRATIVE.md` § Capital Programs and Architecture decision #17.

---

*Owned by Allen Diaz de Leon. When a ticket reveals a deployment-relevant gotcha, edit this file directly — the P0.2 append-only "Deployment notes" pattern is retired now that the full runbook exists.*
