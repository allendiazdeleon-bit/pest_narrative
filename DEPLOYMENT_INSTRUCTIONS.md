# DEPLOYMENT_INSTRUCTIONS.md — masseyFlow / Massey Services

**Status:** STUB — to be filled in by ticket **P6.5**.
**Authoritative for:** deployment sequence, custom field definitions, Quick Action setup, Permission Set assignments, Briefcase Builder configuration, manual-checkpoint sign-off list.
**Source-of-truth rank:** #3 (story > architecture > deployment > solution design > execution). See `CLAUDE.md`.

---

## Why this file exists as a stub today

`docs/BUILD_TICKETS_PEST.md` ticket **P0.2** requires this placeholder so that as Phases P1–P5 land, Claude Code can append "deployment notes" inline when a ticket reveals a step that's worth recording (e.g., a metadata gotcha, a dependency ordering, a permission-set requirement). The full deployment runbook is authored in **P6.5** (~6h), once everything has been built and there's a real org to deploy into.

## What goes in here when P6.5 fires

Outline:

1. **Pre-deploy checklist** — org edition + license requirements, confirmed manual-checkpoint sign-offs (brand-use, Voice number provisioned, RUP attestation legal review).
2. **Deployment sequence** — ordered list of `sf project deploy start` invocations or a single bundled deploy, with rollback notes per phase.
3. **Custom field reference** — every custom field deployed, by object: Account (×6 upsell), WorkOrder (×7 flow-control), WorkStep (×5), Incident (×4), Asset (×18 pest), `Upsell_Talk_Track__mdt` (×N). Cross-references `ARCHITECTURE_PROPOSAL.md` § 4.
4. **Quick Action setup** — 7 Quick Actions on WorkOrder + 1 on Account; per-action `actionType`, `target`, page-layout assignments.
5. **Permission Sets** — Massey Tech, Massey Branch Agent, Massey Branch Manager, Massey Demo Admin. Per-permission-set: object/field permissions, Apex class access, Visualforce/LWC access.
6. **Briefcase Builder configuration** — full config for the offline rule supporting all 6 priming paths (`ARCHITECTURE_PROPOSAL.md` § 6.4). Filter logic, refresh frequency, conflict resolution policy.
7. **Service Cloud Voice setup** — IVR routing rules, queue assignments, after-call work configuration. Cross-references P4.1.
8. **Agentforce topic + Sidekick library deploy** — 8 standard topics + 1 Upsell Recommendation topic (P4.2 / P4.3). Sidekick library card payload definitions.
9. **Knowledge article publish list** — 12 articles (P2.5), with publish order + categorization scheme.
10. **Experience Cloud (`massey-portal`) deploy** — site config, theme, embedded Agentforce Chat, page-builder layouts (P5.8).
11. **Seed data run order** — `seed_work_types.apex` → `seed_work_plan_templates.apex` → `seed_demo_data.apex` → `seed_upsell_talk_tracks.apex`. Idempotency guarantees.
12. **Smoke test** — end-to-end demo dry run script (P6.7), 9 scenes, expected pass/fail criteria.
13. **Manual checkpoints** — items not deployable via metadata that an admin must run (Setup UI work). Cross-references `CLAUDE.md` § Manual setup.

## Deployment notes accumulated so far

*(Append-only as Phases P1–P5 land. Each note: ticket ID + one-line gotcha or sequencing requirement. Do not author full procedures here — those go in P6.5.)*

- **P0.2 (this commit, 2026-05-08):** Three doc artifacts now in place — `ARCHITECTURE_PROPOSAL.md` ported from telcoFlow with PMT removed, this stub, and `docs/SOLUTION_DESIGN.md` stub. No metadata deployed yet.

---

## Manual checkpoints (mirrored from CLAUDE.md — single source for a deploying admin)

These must be completed by a human admin; Claude Code will hand them back when encountered:

- [ ] **Massey brand-use legal sign-off** — confirm before any external presentation (`CLAUDE.md`).
- [ ] **Scheduling Policies + Work Rules + Service Objectives** — Field Service Setup admin UI. Two policies: Massey Standard (default) + Cluster Response.
- [ ] **P4.1 — Service Cloud Voice number procurement** — external, ~5–10 business days. **Kick off in P0** so it doesn't block P4.
- [ ] **P4.2 — Voice IVR routing + 8 Agentforce topics** — Voice Setup + Agentforce admin UI.
- [ ] **P4.3 — "Upsell Recommendation" Agentforce topic + Sidekick library entry** — Agentforce admin UI.
- [ ] **P2.5 — Author + publish 12 Knowledge articles** — content authoring.
- [ ] **P5.8 — Build LWR Experience Cloud site for `massey-portal`** — Experience Cloud admin UI.

---

*This file is owned by Allen Diaz de Leon. When P6.5 fires, the stub above is replaced by the full runbook. Until then, only append "Deployment notes accumulated so far" entries; do not edit the outline.*
