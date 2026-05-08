# CLAUDE.md — masseyFlow / pest_narrative project conventions

This file is the entry point for Claude Code working on this repo. Read it first.

## What this project is

`pest_narrative` (LWC namespace `masseyFlow`) is a Salesforce Lightning Web Component suite for the Field Service Mobile app, targeting **Massey Services**, a real regional pest, termite, lawn, and mosquito provider headquartered in Orlando, FL. Single-vertical pest control demo: residential GoGreen Pest, Termite Protection (Sentricon + Termidor), Mosquito Hunter, and Lawn Service.

This repo is the **third lifecycle** of a domain-neutral architecture originally built for a utility (water + electric) demo, then converted to telco (NeuraFiber) at `~/Desktop/telcoFlow-neurafiber`. The architecture survives unchanged: orchestrator + 6 step LWCs, dispatcher console widgets, demo-magic harness, 8-call cluster engine, and offline briefcase priming. What's swapped: schema, labels, Apex tone, Knowledge articles, Agentforce topics, persona narrative, demo data.

**What's net-new in this lifecycle (not in prior demos):** an upsell + tech-coaching architectural surface — `UpsellCoachService.cls`, `masseyUpsellCoach` LWC, an "Upsell Recommendation" Agentforce topic, and a Manager Coaching dashboard. This maps directly to Massey's stated business priority: revenue growth via cross-sell + attach rate.

**What's intentionally dropped:** the PMT capital-program bridge has no clean pest analogue and is not modeled. See `docs/PEST_NARRATIVE.md` § Capital Programs for the rationale.

The orchestrator (`masseyFlowOrchestrator`) runs as a Screen Action on Work Order, and per the inherited v4 architecture, each of the 6 child step LWCs is also exposed as its own Quick Action so techs can resume mid-flow when offline.

## Source-of-truth hierarchy

When two artifacts disagree, this is the resolution order:

1. **`docs/PEST_NARRATIVE.md`** — authoritative for brand, personas, anchor scenarios, upsell architectural surface, and the 9 demo scenes. Story always wins.
2. **`ARCHITECTURE_PROPOSAL.md`** (ported from telcoFlow in P0.2; PMT sections removed) — authoritative for architecture (offline strategy, briefcase config, Quick Action surface). Domain-neutral.
3. **`DEPLOYMENT_INSTRUCTIONS.md`** (authored in P6.5) — authoritative for deployment sequence, custom field definitions, Quick Action setup, briefcase config.
4. **`docs/SOLUTION_DESIGN.md`** (authored in P6.4) — long-form solution design covering data model, AI surfaces, upsell architecture, manager coaching layer.
5. **`docs/BUILD_TICKETS_PEST.md`** — 35 atomic tickets that operationalize the build (Phases P0–P6).

## Reference repo

The source architecture lives at `/Users/allen.diazdeleon/Desktop/telcoFlow-neurafiber`. When implementing a ticket, reference the equivalent telco ticket in that repo's `docs/BUILD_TICKETS_TELCO.md` for the proven implementation pattern. **Pull patterns; never pull content** — telco labels, picklist values, Apex bodies, and demo seed data are all wrong for pest.

## Project status

Mid-Phase-P0. Completed:
- ✅ P0.0 — Repo scaffold (commit `c9f5415`)
- ✅ P0.1 — `docs/PEST_NARRATIVE.md` (commit `1b798f0`)
- ✅ P0.2 prep — `docs/BUILD_TICKETS_PEST.md` (commit `8098322`)

Next up: complete P0.2 (this file + README + ARCHITECTURE_PROPOSAL port), then begin Phase P1 (schema swap).

`git log` is authoritative for ticket completion.

## Conventions

### Deploy

```
sfdx force:source:deploy -p force-app
# or
sf project deploy start -d force-app --target-org <alias>
```

### LWC naming

- `masseyFlow*` — orchestrator + step LWCs
- `dispatch_*` — Dispatcher Console customs
- `demoMagic*` — demo-only mocks and Quick Action wrappers
- `massey*` — Massey-specific UI not in the orchestrator (e.g., `masseyUpsellCoach`)
- `fsl_*` — reserved

### Apex naming

- Action classes go in `force-app/main/default/classes/`
- One class per logical action (e.g., `AppointmentBooker`, `PestPressureAnalyzer`, `UpsellCoachService`)
- Tests in `<ClassName>Test.cls` colocated with the class

### Custom field naming

- snake_case ending in `__c`
- Picklist values follow the narrative doc's exact capitalization
- `Service_Line__c` on Asset is required and drives all variant rendering

### Commits

- Reference the ticket ID: `[P1.2] Add pest Asset fields`
- One ticket per commit (or per logically grouped set of tickets)

### Tests

- Apex: target ≥75% coverage on new classes; ≥85% on `UpsellCoachService` (load-bearing)
- LWC: jest tests in `__tests__/` next to the component

## Manual setup steps (NOT automatable)

These tickets in `docs/BUILD_TICKETS_PEST.md` are flagged `Type: config` (admin UI), `Type: manual` (external procurement), or `Type: data` (content authoring). A human admin runs these.

- **Massey brand-use sign-off** — confirm with legal before any external presentation. Do not show this demo externally without sign-off.
- **Scheduling Policies + Work Rules + Service Objectives** — admin UI in Field Service Setup. Two policies recommended: Massey Standard (default) + Cluster Response.
- **P4.1 — Provision Service Cloud Voice number** — external procurement, ~5–10 business days. Kick off in P0.
- **P4.2 — Configure Voice IVR routing + 8 Agentforce topics** — Voice Setup + Agentforce admin UI.
- **P4.3 — Configure new "Upsell Recommendation" Agentforce topic + Sidekick library entry** — Agentforce admin UI.
- **P2.5 — Author + publish 12 Knowledge articles** — content authoring.
- **P5.8 — Build LWR Experience Cloud site for `massey-portal`** — Experience Cloud admin UI.

When Claude Code hits one of these, stop and report — do not attempt admin-UI work via code.

## How to run a ticket with Claude Code

Pattern (mirrors telcoFlow's proven workflow):

1. **First session:** read `docs/PEST_NARRATIVE.md`, `docs/BUILD_TICKETS_PEST.md`, this file. Begin on the next pending ticket.
2. **Every session after:** open with the next ticket number (e.g., `P1.4`). Claude picks up where it left off via `git log`.
3. **Parallel work in middle phases:** dispatch parallel subagents for independent tickets (e.g., P3.1 + P3.4 are independent).
4. **Manual checkpoints:** end of every phase, pause, review, run any `manual`/`config` tickets, then continue.

## Personas (narrative only)

The demo presenter switches "hats" by navigating to surfaces — there is one underlying admin user. Full persona arcs in `docs/PEST_NARRATIVE.md`.

- **Sandra Reyes** (existing GoGreen subscriber, ant-call scenario) — Voice → Agentforce
- **David Kim** (new-service prospect) — `massey-portal` Experience Cloud site
- **Lisa Chen** (Mosquito Hunter customer affected by cluster) — walk-on
- **Jordan Martinez** (branch service center agent) — Service Console + Agent Sidekick
- **Ray Garcia** (branch operations manager) — Field Service Dispatcher Console + Manager Coaching dashboard
- **Tom Walker** (termite team lead) — `masseyFlow` orchestrator on Work Order (tablet)
- **Maria Lopez** (quarterly pest tech) — `masseyFlow` orchestrator on Work Order (phone) — **drives the marquee upsell scene**

## Revenue-growth lens

Massey is focused on growing revenue per customer. Every demo decision should reinforce this. When in doubt:
- Surface upsell coaching wherever a tech, agent, or manager touches a customer.
- Don't reduce upsell to a single feature — it's a thread across personas.
- Manager view should show attach rate + leads-from-route + conversion, not just dispatch metrics.

If you propose an architectural decision that doesn't reinforce this lens, flag it explicitly so the team can weigh the trade-off.

## Questions / unknowns

When in doubt, escalate to Allen Diaz de Leon. Don't deviate from `PEST_NARRATIVE.md` without explicit approval. Surface architectural questions before implementing — better to ask than to build the wrong thing and revert.
