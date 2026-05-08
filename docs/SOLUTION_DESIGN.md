# SOLUTION_DESIGN.md — masseyFlow / Massey Services

**Status:** STUB — to be filled in by ticket **P6.4**.
**Authoritative for:** long-form solution design — data model rationale, AI surfaces (Agentforce + Sidekick), upsell architecture deep-dive, manager coaching layer, integration points.
**Source-of-truth rank:** #4 (story > architecture > deployment > solution design > execution). See `CLAUDE.md`.

---

## Why this file exists as a stub today

`docs/BUILD_TICKETS_PEST.md` ticket **P0.2** requires this placeholder so downstream tickets (notably **P1.3** — drop PMT scaffolding) have a target file in which to record the *PMT-not-modeled* decision. The rest of this document is intentionally a stub; the full design pass happens in **P6.4** (~8h), after the schema (P1), Apex (P3), and LWC (P5) work is in place and the design can describe what was actually built.

## What goes in here when P6.4 fires

Outline (subject to refinement during P6.4):

1. **Executive overview** — one-page recap of the demo, written for a sales-engineering audience (not a developer).
2. **Data model rationale** — why we extended standard objects (Account, WorkOrder, WorkPlan, WorkStep, Asset, Incident) rather than creating custom objects; trade-offs vs Communications Cloud / Industry Cloud equivalents.
3. **PMT-not-modeled decision** — see § "Locked decisions" below; expanded in P6.4 with stakeholder context.
4. **AI surface map** — every place Agentforce / Sidekick / Einstein touches the demo. 8 Agentforce topics (P4.2) + Upsell Recommendation topic (P4.3) + Sidekick library cards. Per-topic prompt structure, grounding sources, and Knowledge article linkage.
5. **Upsell + tech-coaching architecture deep-dive** — `UpsellCoachService` ranking algorithm, `Upsell_Talk_Track__mdt` content model, cross-persona thread (Maria → Jordan → Ray), offline draft-Lead pattern. Cross-references `ARCHITECTURE_PROPOSAL.md` § 11.
6. **Manager coaching layer** — Ray's dashboard (P6.1), the 4 reports, attach-rate computation, leads-from-route → conversion funnel.
7. **Cluster engine architecture** — 8-call cluster engine reuse (domain-neutral, ported from telco), the post-storm mosquito surge anchor scenario (ZIP 32828), demo-magic harness.
8. **Restricted-Use Pesticide attestation** — reuses telco LOTO architecture (Path A from ticket P2.3); expanded with EPA reg # capture flow, REI tracking, and SDS linkage.
9. **Integration points** — Voice (Service Cloud Voice), Knowledge, Experience Cloud (`massey-portal`), Briefcase Builder. Per-integration: data flow, offline implications, deployment dependencies.
10. **Open questions / decisions deferred to post-demo** — anything the demo intentionally fakes (e.g., real device telemetry, real Voice IVR routing in production volumes).

## Locked decisions (recorded now so downstream tickets can cite)

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

**Decision:** Reuse the existing `LOTO_Record__c` object name, swapping labels and content via Custom Labels (P2.1). Do not rename the object.

**Why:** Renaming a custom object cascades into permission sets, page layouts, validation rules, formula references, and any inbound triggers. The blocking-gate UX is identical between LOTO (lock-out/tag-out) and RUP (restricted-use pesticide attestation) — same architectural pattern, different content. Schema migration cost > naming-purity benefit.

**Where this is enforced:**

- `docs/BUILD_TICKETS_PEST.md` ticket **P2.3**
- `ARCHITECTURE_PROPOSAL.md` § 9 (decision #10)

### Inherited API name preservation — general policy

**Decision:** Where a label needs to change but a schema migration would be costly (e.g., `Outage_Latitude__c` → "Cluster Latitude" label, `Work_DeEnergize` → "Pre-Treatment Setup" label, `Circuit__c` → "Cluster Identifier" label), preserve the API name and swap the label via Custom Labels in P2.1.

**Why:** Same reasoning as LOTO. Schema renames are expensive; labels are cheap.

**Where this is enforced:**

- `ARCHITECTURE_PROPOSAL.md` § 4.2, § 4.3, § 9 (decision #20)
- `docs/BUILD_TICKETS_PEST.md` tickets **P1.6**, **P2.1**

### Step 5 LWC name retains `OutageStep`

**Decision:** Component file is `masseyFlowOutageStep` (inherited from `utilityFlowOutageStep`). User-facing label is "Service Impact" via Custom Label.

**Why:** File rename has metadata churn cost across `.js`, `.html`, `.css`, `.js-meta.xml`, Quick Action XML, and orchestrator import paths. The offline architecture and step semantics are identical (link to a cluster Incident, capture root cause, count affected entities). Defer rename until/unless a future polish pass justifies it.

**Where this is enforced:**

- `ARCHITECTURE_PROPOSAL.md` § 2 (note under the flow-steps table)

---

*This file is owned by Allen Diaz de Leon. When P6.4 fires, replace this stub in full. Until then, only append additional locked decisions; do not edit the outline above.*
