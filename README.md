# pest_narrative

**Salesforce Field Service demo for Massey Services**
LWC namespace: `masseyFlow`
Orlando, FL — pest, termite, lawn, mosquito control

---

## What this is

A Salesforce + Field Service Mobile demo built on top of a domain-neutral architecture (third lifecycle: utility → telco → pest). Showcases:

- **AI-assisted call center** — Agentforce + Sidekick handle inbound pest inquiries, surface retention offers, and **prompt agents to pitch eligible upsells**.
- **Self-service prospect signup** — Experience Cloud portal with embedded Agentforce Chat and bundle-pricing plan picker.
- **Field-tech orchestrator with offline support** — 6-step Lightning Web Component flow (Safety → Crew → Site → Work → Service Impact → Summary) running on FSL Mobile, with a Restricted-Use Pesticide attestation gate.
- **Tech-as-advisor upsell coaching** — `masseyUpsellCoach` LWC inside the orchestrator surfaces neighborhood-based upsell pitches with talk-tracks; tech captures customer interest → spawns Lead → routes to call center for follow-up.
- **Cluster response** — post-rainfall mosquito surge triggers an 8-call cluster; emergency-reassign pulls the termite team to area treatment.
- **Manager coaching dashboard** — branch ops manager sees attach rate by tech, leads-from-route, conversion rate.

## Personas (demo)

| Name | Role | Surface |
|---|---|---|
| Sandra Reyes | Existing GoGreen subscriber | Voice → Agentforce |
| David Kim | New-service prospect | `massey-portal` Experience Cloud |
| Lisa Chen | Mosquito Hunter customer (cluster walk-on) | Service Console |
| Jordan Martinez | Branch service center agent | Service Console + Sidekick |
| Ray Garcia | Branch operations manager | Dispatcher Console + Coaching dashboard |
| Tom Walker | Termite team lead | `masseyFlow` orchestrator (tablet) |
| Maria Lopez | Quarterly pest tech | `masseyFlow` orchestrator (phone) |

## Documentation

- **[`docs/PEST_NARRATIVE.md`](docs/PEST_NARRATIVE.md)** — story source of truth: brand, personas, scenarios, 9 demo scenes
- **[`docs/BUILD_TICKETS_PEST.md`](docs/BUILD_TICKETS_PEST.md)** — 35 atomic build tickets across Phases P0–P6
- **[`CLAUDE.md`](CLAUDE.md)** — project conventions for Claude Code execution
- **`ARCHITECTURE_PROPOSAL.md`** *(pending P0.2)* — domain-neutral architecture spec
- **`docs/SOLUTION_DESIGN.md`** *(pending P6.4)* — long-form solution design
- **`DEPLOYMENT_INSTRUCTIONS.md`** *(pending P6.5)* — fresh-org deployment sequence

## Reference repo

Architectural patterns are inherited from [`telcoFlow-neurafiber`](../telcoFlow-neurafiber/) (the second lifecycle of this architecture, targeting telco). Pull patterns from there; do not pull content.

## Status

Phase P0 — Decisions + brand baseline. See `git log` for ticket completion.

## Brand-use note

**Massey Services is a real company.** Their brand is used in this demo with permission pending legal sign-off. Do not present this demo externally until sign-off is confirmed.

## Questions

Allen Diaz de Leon (allen.diazdeleon@neuraflash.com)
