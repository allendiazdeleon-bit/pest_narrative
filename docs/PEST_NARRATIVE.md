# Massey Services — Demo Narrative

The single source of truth for **who, what, where, why** in the pest control demo. Every downstream ticket — schema, labels, Apex tone, Knowledge articles, Agentforce prompts, presenter notes — refers back to this file. If anything in the build contradicts this doc, this doc wins (unless `ARCHITECTURE_PROPOSAL.md` says otherwise about *architecture*; this doc is about *story*).

This demo is targeted at **Massey Services** as a sales prospect. The brand is real and used with permission (pending legal sign-off — confirm before any external presentation).

---

## Brand

**Massey Services.** Family-owned regional pest, termite, lawn, and mosquito provider headquartered in Orlando, FL. Founded 1985. Operates ~150 service centers across FL, GA, LA, NC, OK, SC, and TX. The demo models a single Florida branch operation centered on Orlando.

- **Tagline (Massey's actual):** "The Quality Service Company"
- **Demo service area:** Orange County + Seminole County, FL. Branch HQ: Orlando service center.
- **Service lines modeled (4 of Massey's actual product lineup):**
  - **GoGreen Pest Prevention** — quarterly residential pest service (ants, roaches, spiders, silverfish). Massey's anchor recurring service. ~70% of demo customers.
  - **Massey Termite Protection** — Sentricon AlwaysActive bait stations + Termidor liquid soil treatment. Higher-ticket, longer-cycle. ~25% of demo customers.
  - **Mosquito Hunter** — perimeter mosquito systems + monthly fogging. Seasonal, FL-heavy. ~15% of demo customers (overlap with the above).
  - **Massey Lawn Service** — turf health, fertilization, weed/insect control. ~10% of demo customers.
- **Branch operation:** Orlando Service Center, 1 dispatch desk, ~20 quarterly pest techs, 1 termite team (3 people), 1 mosquito-systems specialist, 1 lawn tech.

Massey is positioned as a "quality + relationship" pest provider — they win on tech consistency (the same tech visits the same houses) and depth of service (cross-line bundles). That positioning is what *justifies* the demo's heavy emphasis on **upsell coaching, attach rate, and tech-as-advisor** — see Section 4.

---

## Personas

The presenter switches "hats" by navigating to surfaces — there is one underlying admin user. Names carry over from prior demo lifecycles for continuity in seeded data; roles are reframed for pest control.

| Persona | Role | Primary surface | Story role |
|---|---|---|---|
| **Sandra Reyes** | Massey GoGreen subscriber (existing, 4 years) | Inbound Voice → Agentforce (Service Console for Jordan) | Calls about ant intrusion in her kitchen. Drives Scene 1 + the **upsell narrative** (Sandra has no termite coverage; FL termite season starting; Sidekick suggests cross-sell). |
| **David Kim** | New-service prospect | Massey Experience Cloud portal (`massey-portal`) | Lake Nona homeowner. Self-service signup → service area validation → quarterly pest install booking. Plan picker shows Pest+Mosquito bundle pricing. Drives Scene 4. |
| **Lisa Chen** | Mosquito Hunter subscriber (existing) | Affected customer in cluster scenario | One of the 47 customers in the post-rainfall mosquito surge cluster. Walk-on; doesn't drive a scene but appears in Jordan's queue. |
| **Jordan Martinez** | Branch service center agent | Service Console + Agent Sidekick + Voice softphone | Answers Sandra's call (Scene 1), handles a billing escalation (Scene 2), demos Sidekick **upsell + empathy + retention** cards, escalates a complex case to entomology (Scene 3). |
| **Ray Garcia** | Branch operations manager | Field Service Dispatcher Console + Manager Coaching dashboard | Manages the Orlando branch route board (Scene 5'). When the mosquito surge cluster activates (Scene 6), pivots to emergency-reassign mode and pulls Tom's termite team to run area mosquito treatment (Scene 7). Reviews end-of-day attach rates (Scene 9). |
| **Tom Walker** | Termite team lead | telcoFlow-pattern orchestrator on Work Order (FSL Mobile, tablet) | Runs the multi-tech orchestrator on a Mosquito Surge Area Treatment WO during the cluster response (Scene 8). Normally leads Sentricon installs and whole-home tent fumigations. |
| **Maria Lopez** | Quarterly pest tech | telcoFlow-pattern orchestrator on Work Order (FSL Mobile, phone) | Runs the solo-tech orchestrator on her quarterly residential route. **Drives the marquee upsell scene (Scene 5)** — Sidekick prompts her to pitch Mosquito Hunter at a customer's home; she captures the lead; revenue motion completes via Jordan callback. |

---

## Capital programs: NOT modeled

Unlike prior lifecycles of this architecture (utility LSL replacement, telco FTTH build), **the pest demo intentionally drops the PMT capital-program bridge.** Reasoning:

- Pest control growth is driven by **route density + attach rate**, not multi-month capital builds.
- A "pest capital program" (e.g., HOA seasonal contract rollout) would be forced and uninteresting to a Massey buyer.
- The architecture supports it; we just don't model it. If a prospect asks, redirect to "PMT bridge available — used in our utility and telco demos."

What replaces PMT in the demo's value stack: the **Upsell + Coaching surface** (Section 4 below). That's where the buyer's revenue-growth story lives.

---

## Anchor scenarios

### Cluster scenario: Post-rainfall mosquito surge

Replaces the utility "8-call leak cluster / water main break" and the telco "PON outage / OLT card failure". Same record shape (1 Incident + 1 PSC + 8 Cases + ~47 PSCItems + 1 parent dispatch WO).

- **Trigger:** Heavy overnight rain (3+ inches) hits a single Orlando ZIP (32828 — Avalon Park / Waterford Lakes). Standing water in a clogged municipal storm drain creates a massive *Aedes aegypti* breeding event over 48 hours.
- **Customer-visible signal:** Mosquito Hunter customers report systems "not working"; non-Mosquito Hunter neighbors call in for emergency service.
- **Cause:** Clogged storm drain (not a system failure on Massey's side). Fix is larvicide application at the breeding source + ULV fog sweep across the affected radius.
- **8 cases roll up to 1 Incident:** ClusterDetector identifies the geographic + weather-event correlation. Jordan sees the cluster forming in his queue. Ray sees the PSC light up in the Dispatcher Console drawer.
- **Activation:** Demo presenter triggers via the "Activate Mosquito Surge Cluster" Quick Action on the Incident layout.
- **Resolution path:** Emergency-reassign Tom's termite team → Tom's truck has the ULV fogger + larvicide stocks → identify + treat breeding source → ULV fog perimeter → Cases auto-close → Incident closes → PSC closes → Mosquito Hunter customers receive proactive "we got it before you called" notifications.

### Proactive scenario: Pest pressure model

Replaces the utility "AMI continuous-flow leak detection" and the telco "ONT degraded line detection". Same shape (Apex pattern analyzer flags candidates → proactive WO generated → customer outreach → tech visit).

- **Signal:** Combined score from (a) `Bait_Station_State__c` showing rising hits across a property's Sentricon stations over 30 days, (b) `Soil_Temp_F__c` rising into the termite-active range (>70°F), (c) `Conducive_Conditions__c` flag set during last quarterly inspection, (d) seasonal multiplier (FL termite swarm window: March–May).
- **14 candidate properties** flagged via `Is_Pest_Pressure_Candidate__c = true` in the seeded data set.
- **`PestPressureAnalyzer.analyze()`** (renamed from telco's `LineHealthAnalyzer`) reads property + station state and returns a plain-language diagnosis ("Sentricon hits up 60% over 30 days, soil temp rising, swarm season starting — recommend booster termite treatment + neighborhood survey").
- **Customer outreach:** ProactiveWoGenerator + a customer notification service send proactive outreach (SMS / email) offering a no-cost booster inspection. Demo_Reply_Outcome__mdt simulates customer responses.
- **WO creation:** YES replies trigger Booster Termite Inspection WOs auto-scheduled with the right skill match (Termite-Certified Tech).

---

## Upsell + coaching: the new architectural surface

This is the **revenue-growth thread** woven through the demo. It's not a single feature — it surfaces across three personas, three surfaces, and one dedicated scene. It's the part of the demo that maps directly to a Massey buyer's stated priority: grow revenue per customer, grow attach rate per route.

### Cross-sell matrix modeled

| Customer's existing service | Eligible upsells | Trigger logic |
|---|---|---|
| GoGreen Pest only | Termite, Mosquito, Lawn | Property has conducive termite conditions; OR neighborhood has active mosquito complaints; OR customer's lawn shows distress in tech photos |
| Termite only | GoGreen Pest, Mosquito | Sentricon stations active = property already has bug pressure baseline |
| Mosquito only | GoGreen Pest, Lawn | Outdoor-focused customer profile |
| Pest + Termite | Mosquito, Lawn | High-value customer; full-bundle path |

### Where upsell shows up

- **Maria (pest tech) on-site** — `masseyUpsellCoach` LWC inside the Site step + Summary step of the orchestrator. Coach card: "Sandra's neighbor on Maple just signed up for Mosquito Hunter — pitch her on it before you leave. Suggested talk-track: '[empathy + neighborhood social proof + cost framing].'" Capture customer interest (Yes / Not now / Not interested) → spawns Lead → routes to Jordan.
- **Jordan (call center agent)** — Sidekick card on inbound calls: "Sandra has GoGreen but no termite coverage. FL termite season starts in 3 weeks. Suggested offer: free Sentricon inspection." New Agentforce topic "Upsell Recommendation" runs `UpsellCoachService.recommend(accountId)` on demand.
- **Ray (branch ops manager)** — Manager Coaching dashboard. Attach rate by tech (week / month / YTD). Top performers. Coaching opportunities (techs with low attach rate but high route quality). Leads-from-route count + conversion rate.

### Apex driving it

- **`UpsellCoachService.recommend(accountId)`** — returns ranked list of `UpsellRecommendation` DTOs: `{serviceLine, score, reasonCodes[], suggestedTalkTrack, estimatedAnnualValue}`. Uses property history, neighborhood signals, seasonal multipliers, customer tenure.
- **`UpsellCoachService.captureOutcome(accountId, serviceLine, outcome)`** — Yes / NotNow / NotInterested. Yes spawns a Lead linked to the Account; routes to Jordan's queue.

---

## 9 Demo Scenes

One paragraph each. These are the observable beats the presenter walks through. Order is the recommended demo flow; scenes can be reordered or skipped depending on audience.

### Scene 1 — Sandra calls in: ants in the kitchen

Sandra dials the Massey Orlando service number from her home. Service Cloud Voice routes to Agentforce. Agentforce greets her by name (caller-ID match → Account), invokes the **Pest Inquiry** topic, and pulls service history: she's a 4-year GoGreen customer, last serviced 6 weeks ago, no termite coverage. Jordan picks up. Sidekick fires three cards: (a) **Empathy script** for established customer, (b) **Same-week service** offer, (c) **Upsell card — Termite Protection** ("FL termite swarm season starts in 3 weeks; Sandra's home is 22 years old; no termite coverage on file — eligible for free Sentricon inspection"). Jordan offers a same-week truck roll AND mentions the free termite inspection. Sandra accepts both. `AppointmentBooker.book` returns slots; `AppointmentConfirmer.confirm` creates Case + WorkOrder + ServiceAppointment in one transaction. A Lead for Termite Protection is also created and routed to follow-up. Total elapsed: ~90 seconds.

### Scene 2 — Jordan handles a billing escalation

A different customer called in upset about a billing dispute. The Customer 360 LWC renders recent service history (clean), recent cases (one from 4 months ago), recent work orders (last quarterly visit), and bill summary. Sidekick suggests: "Empathy script — long-tenure customer, first dispute" + "Retention offer — eligible for one-time service credit". Jordan reads the script, applies a one-time credit, customer is satisfied. Demonstrates Sidekick context-awareness for retention.

### Scene 3 — Jordan escalates to entomology

A third call comes in — this one needs an entomology specialist (customer reports an unusual insect; Jordan can't ID from photo). Jordan clicks "Escalate". `EscalationContextBuilder.summarize` produces a structured handoff: AI-generated case summary, property service history, photo attachments, suggested next-best actions. The payload is attached to the case and routed to the entomology queue. Demonstrates AI-assisted handoff quality.

### Scene 4 — David signs up at massey-portal

Cut to David's living room in Lake Nona. He's just moved into a new home. He visits the Massey Experience Cloud portal, clicks "Get a Quote". Embedded Agentforce Chat greets him. `ServiceAreaValidator.validate(address)` confirms the address is in Massey's Orlando branch service area + classifies the property type (single-family, ~3,200 sqft, 0.4 acres). David picks a quarterly pest plan. The plan picker prominently surfaces a **Pest + Mosquito Hunter bundle** (10% off vs. à la carte) — the upsell happens in the signup flow itself. David selects the bundle, schedules an install via `AppointmentBooker.book`. `ServiceStartOrchestrator.create` provisions his Account + initial Property Asset. Confirmation page shows install ETA + tracking link. Total elapsed: ~3 minutes.

### Scene 5 — Maria mid-route: Sidekick coaches an upsell *(new — replaces telco's capital-build scene)*

Cut to Maria's tablet at the third stop of her quarterly route — the Bennett residence in Avalon Park. She finishes the perimeter spray and opens the Summary step of the orchestrator. The `masseyUpsellCoach` LWC fires: "Mr. Bennett's neighbor on the same street signed up for Mosquito Hunter last month. Avalon Park mosquito complaints up 40% YoY. Suggested talk-track: 'Hey, while I'm here — your neighbor the Hendersons just had us install a mosquito system. Three of your neighbors on Maple have one. Want me to grab a quote? No commitment.'" Maria reads the talk-track, walks back to the door, pitches Mr. Bennett. He says yes — wants a quote. Maria taps "Capture Interest: Yes" in the LWC. A Lead is spawned, linked to the Bennett Account, routed to Jordan's outbound queue. Maria moves on to her next stop. **This is the marquee scene** — a 90-second demonstration of how the platform turns every truck roll into a sales conversation.

### Scene 6 — Mosquito surge cluster activates

The presenter clicks "Activate Mosquito Surge Cluster" on the Incident layout. Demo magic flips 8 seeded Cases + 1 Incident + 1 PSC from Draft → Active. ClusterDetector identifies the geographic + weather-event correlation (32828 ZIP, post-storm). Within seconds, Ray's `dispatch_ActivePSCDrawer` lights up red — a new PSC at Avalon Park / Waterford Lakes, 47 affected properties, ETR pending. Jordan's queue starts filling with new cases. The room sees the platform reacting in real time.

### Scene 7 — Emergency reassign

Ray must decide: pull Tom's termite team off this morning's Sentricon install to handle the area mosquito treatment. He clicks "Emergency Reassign" on the PSC. `EmergencyDivertOrchestrator.divert` (one transaction): defers Tom's current Sentricon SAs, reassigns Tom's team to the parent Mosquito Surge Area Treatment WO at the breeding source. The dispatcher console reflects all of this in seconds. Demonstrates the keystone bridge action under live stress, **without needing the PMT bridge** — straight Field Service reassignment.

### Scene 8 — Tom runs the orchestrator on-site

Cut to Tom's tablet at the breeding source — the clogged storm drain at the corner of Avalon Park Blvd. He launches the orchestrator Quick Action on the Mosquito Surge Area Treatment WO. **Step 1 (Safety):** PPE confirmed (gloves, respirator, eye protection), weather check (no rain in next 4 hours), permit logged. **Step 2 (Crew):** Tom logs himself + Maria as backup. **Step 3 (Site):** NFC scan on the nearest Mosquito Hunter system controller, photo of standing water source, pest pressure score recorded (high). **Step 4 (Work):** Restricted-Use Pesticide attestation gate (replaces telco's LOTO) — Tom logs chemical name, EPA reg #, target species, dose. Apply larvicide to drain. ULV fog perimeter. **Step 5 (Service Impact):** Confirm linked Incident, capture root cause (clogged municipal storm drain → standing water → Aedes breeding event). **Step 6 (Summary):** Visit summary auto-generated by `VisitSummaryGenerator`. WO closes. Demonstrates offline-capable mobile orchestrator end-to-end.

### Scene 9 — Day close: rollup + manager coaching dashboard

WO close triggers the rollup chain: child WO Completed → parent emergency WO recomputes → all-children-complete flips parent to Completed → `VisitSummaryGenerator` emits a plain-language summary attached to the Incident → Incident closes → PSC closes → ETR replaced with "Resolved" timestamp. Then Ray pivots to the **Manager Coaching dashboard**: today's attach rate (Maria's Bennett pitch shows up — +1 lead), week-to-date by tech, month-to-date branch performance. Sidekick suggests: "Maria's attach rate is up 18% this month. Tom's is down — schedule coaching." Demonstrates that the platform closes the revenue loop, not just the service loop. Roll credits.

---

## What's intentionally NOT in the demo

To keep scope manageable and the storyline tight, these *common* pest control scenarios are out of scope:

- **Wildlife / nuisance animal removal** — Massey offers it; we don't model it (different workflow + permitting).
- **Bed bug treatment** — high heat / canine inspection workflow not modeled.
- **Commercial pest control (food service, healthcare)** — residential focus only.
- **Multi-family / HOA contract management** — single-family residential focus.
- **PMT capital programs** — see Capital Programs section above. Architecture supports it.
- **Real-time route optimization** — we use Salesforce's standard scheduling policies; no custom route-optimizer.
- **Customer self-service rescheduling via SMS** — handled via portal + agent only.
- **Smart bait stations with cellular telemetry** — modeled as static records on Asset; no real device integration.
- **Lawn precision-application equipment integration** — not modeled.

If a prospect asks about any of these, redirect to "the architecture supports it; we just didn't model it for this demo."

---

## Open file references

- `ARCHITECTURE_PROPOSAL.md` — domain-neutral architecture (offline strategy, briefcase, Quick Action surface). Lifted from telcoFlow; PMT bridge sections to be removed.
- `docs/BUILD_TICKETS_PEST.md` — atomic tickets to execute the build (Phases P0–P6).
- `docs/SOLUTION_DESIGN.md` — long-form solution design (data model, AI surfaces, scenes, upsell architecture).
- `docs/DEMO_PRESENTER_NOTES.md` — scene-by-scene presenter cues (authored in P6).
- `CLAUDE.md` — project conventions for Claude Code execution.
- `README.md` — repo entry point.
