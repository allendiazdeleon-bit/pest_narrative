# Massey Services Demo — Presenter Notes

> **Audience:** NeuraFlash sales engineer presenting to Massey Services (Orlando HQ) stakeholders — branch ops leadership, IT, and one or two senior account managers from the parent organization.
> **Total runtime:** 30–40 minutes of demo + 10–15 minutes Q&A.
> **Read on a second screen during the live demo.** Bullets > prose. Bold = a critical click. Numbered steps = exact click order.
> **Source-of-truth alignment:** scenes mirror `docs/PEST_NARRATIVE.md` § 9 Demo Scenes. Surfaces mirror `ARCHITECTURE_PROPOSAL.md` § 10. Do not improvise off-script — Massey brand-use sign-off is scoped to this story.

---

## Pre-demo checklist

Run this 30 minutes before the customer joins. Do not skip.

### Org + data
- [ ] **Seed scripts run in order** (all 5, in this order — order matters because territories must exist before WOs, and work types before plans):
  1. `scripts/apex/seed_service_territory.apex` — Orange + Seminole County territories, Orlando service center.
  2. `scripts/apex/seed_work_types.apex` — Quarterly Pest, Sentricon Install, Mosquito Surge Area Treatment, etc.
  3. `scripts/apex/seed_work_plan_templates.apex` — 10 plans, ~50 WorkSteps total.
  4. `scripts/apex/seed_hazards.apex` — hazard catalog for Safety step.
  5. `scripts/apex/seed_demo_data.apex` — Sandra, David, Lisa, Bennett family, the 47 Avalon Park / Waterford Lakes Mosquito Hunter customers, the 14 Pest Pressure candidates, the 8 seeded cluster Cases (in Draft).
- [ ] (Optional sixth) any anonymous Apex you ran to publish Knowledge articles or stamp dates — re-run if your sandbox has been quiet for >7 days so timestamps stay current.

### Voice + Agentforce
- [ ] **Service Cloud Voice number is live** in the target org (Allen-owned procurement; ~5–10 business day lead time per `CLAUDE.md`). Test-dial it from your phone — confirm IVR answers and Agentforce greets.
- [ ] **8 Agentforce topics deployed** (Pest Inquiry, Billing, Escalation, Service Area, Bundle Quote, Cluster Status, Knowledge Lookup, **Upsell Recommendation**). The new "Upsell Recommendation" topic is the load-bearing one for Scene 1's upsell card.
- [ ] **Agent Sidekick library entry** for "Upsell Recommendation" visible in the Sidekick panel.

### Knowledge
- [ ] **All 12 Knowledge articles published** (P2.5 — manual content authoring). Spot-check three: "What to expect at your first GoGreen visit," "Sentricon AlwaysActive: how the bait stations work," "Why mosquitos surge after heavy rain."

### Mobile
- [ ] **Briefcase synced on the FSL Mobile demo device** (Maria's phone + Tom's tablet — they can be the same physical device flipped between two user logins, but the briefcase must be primed for **both** Maria's quarterly route and Tom's Mosquito Surge Area Treatment WO).
- [ ] **Airplane-mode rehearsal** — toggle airplane mode on Maria's phone, open the orchestrator on the Bennett WO, walk to Step 3, confirm `masseyUpsellCoach` renders without spinner. If it spinners, briefcase priming Path 3 (WorkOrder → Account) didn't catch — re-prime before the customer joins.

### Browser tabs (open in this order, left to right, on the presentation laptop)
1. **Service Console** — pinned to Jordan's queue view. Voice softphone widget visible top-right.
2. **Field Service Dispatcher Console** — Ray's territory: Orlando Service Center. Gantt zoomed to today.
3. **Account record: Bennett family** (Avalon Park) — used by Scene 5 follow-up + the standalone `MasseyUpsellCoach` Quick Action.
4. **`massey-portal`** — Experience Cloud site landing page, logged out (David is a prospect).
5. **Manager Coaching dashboard** — the 4 reports from P6.1.
6. **Incident record** for the Avalon Park / Waterford Lakes mosquito surge — staged in Draft. Has the **DemoMagic_Activate_Mosquito_Surge** Quick Action visible on the layout.

### Legal + brand
- [ ] **Massey brand-use sign-off confirmed** (legal — see `CLAUDE.md`). Do not run this demo externally without it.

### Smoke test (5 minutes before kickoff)
- [ ] Click into the Bennett Account → run the **MasseyUpsellCoach** Quick Action → confirm the recommendation card renders within ~1 second. If it spinners, kill it before the customer sees it; restart the seed_demo_data.apex re-run for `Eligible_Upsells__c`.

---

## Persona hat-switching

There is **one underlying admin user**. The presenter switches "hats" by navigating to surfaces. Brief recap so the audience can follow:

| Hat | Surface | Used in scenes |
|---|---|---|
| **Jordan Martinez** — branch service center agent | Service Console + Voice softphone + Agent Sidekick | 1, 2, 3, 5 (Lead receipt) |
| **David Kim** — new-service prospect | `massey-portal` Experience Cloud (logged out → guest) | 4 |
| **Maria Lopez** — quarterly pest tech | FSL Mobile on phone, orchestrator Quick Action on WorkOrder | 5 (marquee) |
| **Ray Garcia** — branch ops manager | FSL Dispatcher Console + Manager Coaching dashboard | 6, 7, 9 |
| **Tom Walker** — termite team lead | FSL Mobile on tablet, orchestrator Quick Action on WorkOrder | 8 |
| **Sandra Reyes / Lisa Chen / Bennett family** | Customer voices only — never log in as them | 1, 5, 6 |

> **Verbal cue when switching hats:** "I'm now going to put on Maria's hat — she's a quarterly pest tech mid-route." Audiences forgive the single-user shortcut as long as you name it.

---

## Demo flow at a glance

| # | Scene | Hat | Surface | Time |
|---|---|---|---|---|
| 1 | Sandra calls in (ants in kitchen) | Jordan | Service Console + Voice | 3–4 min |
| 2 | Billing escalation | Jordan | Service Console + Sidekick | 2–3 min |
| 3 | Entomology escalation | Jordan | Service Console | 2 min |
| 4 | David signs up at portal | David (guest) | `massey-portal` | 3 min |
| 5 | **Maria mid-route — marquee upsell** | Maria | FSL Mobile (phone) | 4–5 min (90 sec on the upsell beat itself) |
| 6 | Mosquito surge cluster activates | Ray | Dispatcher Console | 2 min |
| 7 | Emergency reassign | Ray | Dispatcher Console | 2 min |
| 8 | Tom runs orchestrator on-site | Tom | FSL Mobile (tablet) | 5 min |
| 9 | **Day close — manager coaching** | Ray | Manager Coaching dashboard | 4–5 min |
| — | Q&A | — | — | 10–15 min |

**Total demo budget: ~30–35 minutes.** Leave 10–15 for Q&A.

---

## Scene 1 — Sandra calls in (3–4 min)

**You are:** Jordan Martinez (branch service center agent)
**Surface:** Service Console + Voice softphone + Agent Sidekick
**Setup:** Have a colleague or your own second phone ready to dial the Voice number.

**What to say (opening):**
- "I'm Jordan. I'm the agent on duty at the Orlando service center. The phone's about to ring — let's see what the platform does before I even pick up."

**What to click:**
1. Have your colleague dial the Voice number now. **Wait for the caller-ID match toast** to appear — you should see "Sandra Reyes — 4-year GoGreen customer."
2. **Click the green "Answer" button** in the Voice softphone.
3. Service Console pops the Account record for Sandra automatically.
4. **Point at the Agent Sidekick panel on the right.** Three cards stack in:
   - Empathy script (long-tenure GoGreen subscriber — pause: do **not** say "subscriber" out loud, that's a forbidden word; the card label is "Long-tenure customer").
   - Same-week service offer — three appointment slots already proposed.
   - **Upsell card: Termite Protection.** Reason codes: "FL termite swarm season starts in 3 weeks" + "Home is 22 years old" + "No termite coverage on file."

**What to highlight:**
- Sidekick suggesting same-week truck **AND** the upsell card together — the platform doesn't make Jordan choose between empathy and revenue.
- The talk-track is pre-written. Jordan reads it; he doesn't improvise.
- "Free Sentricon inspection" is the offer — frames as service, not sales.

**What to say (mid-call):**
- "Hi Sandra, I see you've been with us four years — I'm sorry about the ants, we'll get a tech out this week. While I have you — I noticed you don't have termite coverage, and FL swarm season starts in three weeks. Want me to get a free Sentricon inspection on the calendar?"
- Beat. "She says yes."

**What to click (close):**
1. **Click "Book Same-Week Truck"** in the Sidekick same-week card → `AppointmentBooker.book` returns slots → pick the first.
2. **Click "Confirm"** → `AppointmentConfirmer.confirm` creates Case + WorkOrder + ServiceAppointment in one transaction. Show the Case → WO → SA chain on screen.
3. **Click "Capture Termite Lead"** in the upsell card → spawns Lead linked to Sandra's Account, routed to follow-up queue.

**Time budget:** 3–4 min. **Do not exceed 4** — Scene 5 is the marquee, save the time.

**Common gotchas:**
- If Voice doesn't ring through, **fall back to clicking the simulated inbound Case from Jordan's queue** — same Sidekick cards fire from the Account context, you just lose the Voice routing demo. Acknowledge it ("on a real call this would route via Voice — let me show you the agent surface").
- If Sidekick takes >5 sec to render cards, talk through it — "the platform's pulling Sandra's 4 years of service history."

---

## Scene 2 — Jordan handles a billing escalation (2–3 min)

**You are:** Still Jordan.
**Surface:** Service Console + Customer 360 LWC + Sidekick.

**What to say:**
- "Different customer just landed in the queue — billing dispute. Watch what the agent sees before they even open the case."

**What to click:**
1. **Click the next case in Jordan's queue** (seeded Case `Billing Dispute — Mr. Reilly`).
2. The **Customer 360 LWC** renders: recent service history (clean), recent cases (one from 4 months ago), recent WOs (last quarterly visit), bill summary.
3. **Point at Sidekick:** two cards now —
   - Empathy: "Long-tenure customer, first dispute."
   - Retention: "Eligible for one-time service credit."

**What to highlight:**
- Sidekick differentiates retention context from upsell context. It is **not** pitching termite to an angry customer.
- One-time credit is pre-authorized — no manager approval needed for this tier.

**What to click (close):**
1. **Click "Apply One-Time Credit"** → credit applied → Case status flips to Resolved.
2. Audio: "Customer is satisfied. Next call."

**Time budget:** 2–3 min.

**Common gotchas:**
- If the Sidekick retention card doesn't render, you can manually narrate it ("Sidekick would suggest a credit here") — but it should fire reliably from the seeded data.

---

## Scene 3 — Jordan escalates to entomology (2 min)

**You are:** Still Jordan.
**Surface:** Service Console.

**What to say:**
- "Third call. This one Jordan can't solve at L1 — customer sent a photo of an unusual insect, Jordan can't ID it. Watch the AI handoff."

**What to click:**
1. **Click the next case** (seeded Case `Unidentified Insect — Mrs. Alvarez`).
2. Click the photo attachment to enlarge it briefly.
3. **Click "Escalate to Entomology"** Quick Action.
4. `EscalationContextBuilder.summarize` runs. A modal shows the structured handoff: AI-generated case summary, property service history, photo attachments, suggested next-best actions.
5. **Click "Send to Entomology Queue"**.

**What to highlight:**
- The entomologist receives a one-page brief, not a transcript dump. That's hours saved per escalation across the branch.

**Time budget:** 2 min.

---

## Scene 4 — David signs up at massey-portal (3 min)

**You are:** David Kim (prospect, guest user).
**Surface:** `massey-portal` (logged out).

**What to say:**
- "Cut to David's living room in Lake Nona — he just moved in. He's never spoken to Massey before. Watch the self-service path."

**What to click:**
1. **Switch tab to `massey-portal`.**
2. **Click "Get a Quote".**
3. Embedded **Agentforce Chat** greets David.
4. Type / paste David's address (Lake Nona — seeded). `ServiceAreaValidator.validate(address)` runs.
5. Confirms: in-territory, single-family, ~3,200 sqft, 0.4 acres.
6. **Plan picker renders.** Point at the **Pest + Mosquito Hunter bundle** badge — "10% off vs. à la carte."
7. **Click the bundle.**
8. **Click "Schedule Install"** → `AppointmentBooker.book` returns next-week slots → pick one.
9. **Click "Confirm".** `ServiceStartOrchestrator.create` provisions David's Account + initial Property Asset. Confirmation page shows install ETA + tracking link.

**What to highlight:**
- The upsell is in the signup flow itself — bundle pricing is the default visible offer, not buried under "Add a service."
- David never spoke to a human. The whole motion is digital + Agentforce-mediated.

**Time budget:** 3 min. **Hard cap.**

---

## Scene 5 — Maria mid-route: Sidekick coaches an upsell (MARQUEE — 4–5 min, with a 90-second hero beat)

> **This is the load-bearing scene.** Per `CLAUDE.md`'s revenue-growth lens and `PEST_NARRATIVE.md`, this is the single demo moment that maps Massey's stated priority — grow revenue per customer — to a concrete platform behavior. **Do not rush it. Do not skip the verbatim talk-track read.**

**You are:** Maria Lopez (quarterly pest tech, solo, mid-route).
**Surface:** FSL Mobile on phone. WorkOrder = quarterly visit at the **Bennett residence, Avalon Park**.
**Pre-stage:** Maria has just finished the perimeter spray. Steps 1 and 2 are already complete — show this so the audience doesn't sit through PPE checks again.

**What to say (setup, ~30 sec):**
- "Switching hats — I'm Maria now. I'm a quarterly pest tech. I just sprayed the perimeter at the Bennett family's house in Avalon Park. I'm in the middle of my route — I have four more stops today. Watch what the platform shows me on Step 3."

**What to click:**
1. **Switch to FSL Mobile** on the demo phone (or screen-mirror it).
2. The orchestrator is already open on the Bennett WO. Steps 1 (Safety) and 2 (Crew) are green-checked.
3. **Tap Step 3 — Site Assessment.**
4. The Site step renders. NFC scan area, photo capture, pest-pressure score field.
5. **Quickly tap through:** scan the bait station QR (or "Manual Asset Search" fallback), tap "Capture Photo" → use one of the seeded photos, set pest-pressure score = "Low — routine."
6. **Scroll down. The `masseyUpsellCoach` panel renders.** Pause here.

**What the audience sees in the Upsell Coach panel:**
- Header: "Recommended for the Bennett family"
- Service Line: **Mosquito Hunter**
- Reason codes (chips): `NEIGHBOR_BOUGHT_MOSQUITO`, `AVALON_PARK_COMPLAINTS_UP_40_PCT`, `OUTDOOR_PROPERTY_PROFILE`
- Estimated annual value: **$540**
- Talk-track box (verbatim from `Upsell_Talk_Track__mdt`):

> **"Hey, while I'm here — your neighbors the Hendersons just had us install a Mosquito Hunter system last month, and three other families on this street already have one. Avalon Park complaints are up about 40 percent this year. Want me to grab a quick quote before I head out? No commitment — I can text it to you tonight and you can sleep on it."**

**What to say (the 90-second hero beat — read this OUT LOUD as if you are Maria reading her tablet):**
- "OK — so Maria reads this. She walks back to the door."
- *(Read the talk-track verbatim, in Maria's voice. Slow down. This is the moment. Do not summarize it.)*
- "Mr. Bennett says 'sure, send me the quote.'"
- "Maria taps **Yes**."

**What to click (the capture):**
1. **Tap "Capture Interest: Yes"** in the panel.
2. **A draft Lead spawns offline** — show the green confirmation toast: "Lead drafted — will sync when online."
3. **Switch hats verbally:** "Maria moves on to her next stop. She doesn't call Jordan, she doesn't email anyone, she doesn't fill out a form. She just keeps driving. The platform handles the rest."

**The closing beat (~30 sec — do not cut this):**
- **Switch tab back to Service Console.** (You are Jordan again, briefly.)
- **Show the Lead** in Jordan's outbound queue, linked to the Bennett Account, with all the talk-track context attached.
- "Maria's still on her route. The Lead is already in Jordan's queue. Tomorrow morning Jordan calls Mr. Bennett with the quote already prepared. **Every truck roll is now a sales conversation.**"

**Pause for questions here.** This is the natural breath point in the demo.

**What to highlight:**
- The talk-track is curated copy from `Upsell_Talk_Track__mdt` — Massey's marketing team owns it, can tune without code deploy.
- Capture is **offline-capable** — Maria's truck has bad reception in half her route; the Lead is a draft until reconnect.
- "Three of your neighbors on Maple have one" is real social proof generated from neighborhood signal data on the Account, not a generic line.

**Time budget:** 4–5 min total, with **90 sec on the hero talk-track read + Yes-tap + Lead-in-Jordan's-queue beat.** The hero beat is the load-bearing 90 seconds of the entire demo.

**Common gotchas:**
- If the Upsell Coach panel renders empty, the Account's `Eligible_Upsells__c` field didn't seed correctly — abort to a screenshot fallback rather than improvise; recovery costs more time than the screenshot.
- If the audience is engaged and asking questions during the read, **let them interrupt** — that's the demo working. Pick up the read after they finish.
- Do not say "subscriber" — the Bennett family are GoGreen **customers**.

---

## Scene 6 — Mosquito surge cluster activates (2 min)

**You are:** Ray Garcia (branch ops manager).
**Surface:** Field Service Dispatcher Console.

**What to say:**
- "Switching hats — I'm Ray, the branch ops manager at Orlando. It's mid-morning, my Gantt looks normal. Then this happens."

**What to click:**
1. **Switch tab to the Incident record** (Avalon Park / Waterford Lakes mosquito surge — staged in Draft).
2. **Click the "Activate Mosquito Surge Cluster" Quick Action** (`Incident.DemoMagic_Activate_Mosquito_Surge`).
3. Demo magic flips 8 seeded Cases + 1 Incident + 1 PSC from Draft → Active.
4. **Switch tab to the Dispatcher Console.**
5. Within ~2 seconds, **`dispatch_ActivePSCDrawer` lights up red.** Point at it.
6. New PSC: Avalon Park / Waterford Lakes, 47 affected properties, ETR pending.

**What to highlight:**
- ClusterDetector identified the geographic + weather-event correlation automatically (32828 ZIP, post-storm overnight rain).
- Ray didn't get paged. The platform paged him.
- "47 properties" — point at it. That's a lot of customers. Without this, Ray's next signal is the phones lighting up at the call center.

**Time budget:** 2 min.

---

## Scene 7 — Emergency reassign (2 min)

**You are:** Still Ray.
**Surface:** Dispatcher Console.

**What to say:**
- "Ray has a decision. The breeding source is a clogged municipal storm drain. He needs the right truck — Tom's termite team carries the ULV fogger and larvicide. But Tom's mid-Sentricon-install. Watch."

**What to click:**
1. **Click "Emergency Reassign" Quick Action on the PSC** (`Incident.DemoMagic_Emergency_Reassign`).
2. `EmergencyDivertOrchestrator.divert` runs. **One transaction:**
   - Defers Tom's current Sentricon ServiceAppointments (rescheduled to tomorrow, customer notification queued).
   - Reassigns Tom's team to the parent Mosquito Surge Area Treatment WO at the breeding source.
3. **Watch the Gantt re-render.** Tom's bar moves from the Sentricon job to the Mosquito Surge WO. The two deferred SAs slide to tomorrow.

**What to highlight:**
- One click. One transaction. No swivel-chair across calendar + dispatch + customer-notification systems.
- "This is keystone Field Service reassignment under live stress — no PMT bridge, no custom plumbing. **Standard Field Service primitives.**"

**Time budget:** 2 min.

**Common gotchas:**
- If the Gantt doesn't re-render visibly, force a refresh (cmd-R on the Dispatcher Console tab) — the data is updated, the UI cache lags occasionally.

---

## Scene 8 — Tom runs the orchestrator on-site (5 min)

**You are:** Tom Walker (termite team lead).
**Surface:** FSL Mobile on tablet. WorkOrder = Mosquito Surge Area Treatment, location = clogged storm drain at the corner of Avalon Park Blvd.

**What to say:**
- "Last hat-switch on the field side. I'm Tom — I just got reassigned. I'm pulling up to the storm drain. Briefcase synced before I left this morning, so even if I'm in a dead zone here, I have everything I need."

**What to click (move briskly — 6 steps in 5 minutes):**

**Step 1 — Safety Gate (~60 sec):**
1. Tap the orchestrator Quick Action on the WO.
2. PPE checks: **gloves, respirator, eye protection** — tap each.
3. Weather check: "No rain in next 4 hours" — confirm.
4. Permit-to-Treat / Customer Notification logged — tap.
5. **Restricted-Use Pesticide attestation** — gate fires. Tom enters his license #. Highlight: this is a Florida-statute regulatory gate, captured digitally instead of on paper.
6. Safety gate flips green.

**Step 2 — Crew (~30 sec):**
1. Tom logs himself + Maria as backup (Maria's been pulled off her route too). AssignedResource records created.

**Step 3 — Site (~45 sec):**
1. **NFC scan** the nearest Mosquito Hunter system controller (or "Manual Asset Search" fallback).
2. Photo of standing water source — Nimbus camera plugin.
3. Pest pressure score = **"High."**

**Step 4 — Work (~60 sec):**
1. Restricted-Use Pesticide attestation gate. Chemical = larvicide. EPA Reg # entered. Target species = *Aedes aegypti*. Dose logged.
2. **Tap "Apply Larvicide to Standing Water Source"** → checked.
3. **Tap "ULV Fog Perimeter"** → checked.
4. **Tap "Treat Identified Harborage Areas"** → checked.

**Step 5 — Service Impact (~30 sec):**
1. Confirm linked Incident (Avalon Park / Waterford Lakes mosquito surge).
2. Capture root cause: **"Clogged municipal storm drain → standing water → *Aedes* breeding event."**

**Step 6 — Summary & Close (~45 sec):**
1. `VisitSummaryGenerator` emits a plain-language summary — read the first 2 sentences aloud so the audience hears the AI quality.
2. **Tap "Complete Work Order."**

**What to highlight:**
- The whole 5-minute flow can run **fully offline.** Briefcase priming covers WorkOrder → WorkPlan → WorkSteps → Asset → Account → AssignedResource → Incident.
- RUP attestation is a **regulatory requirement** for Massey — Florida statute requires logging EPA Reg #, target species, and dose. The platform captures it without paper.
- Photo + chemical record auto-link to **both** the WorkOrder and the Asset (the Mosquito Hunter system controller).

**Time budget:** 5 min. Move briskly — do not linger on Step 1's PPE checks; the audience gets the idea.

**Common gotchas:**
- If the NFC scan fails, **use the "Manual Asset Search" fallback** — do not waste demo time troubleshooting tap-zones on a phone.
- If `VisitSummaryGenerator` is slow, narrate over it ("the platform's drafting the visit summary in plain language").

---

## Scene 9 — Day close: rollup + manager coaching dashboard (4–5 min)

> **This is the closing scene. It ties the entire demo back to Massey's stated priority: grow revenue per customer.** Do not rush. End on the dashboard, not the rollup.

**You are:** Ray Garcia (branch ops manager), end of day.
**Surface:** Dispatcher Console (briefly) → Manager Coaching dashboard.

**What to say (rollup — ~60 sec):**
- "Tom closed the WO. Watch the rollup chain fire."

**What to click (the rollup):**
1. **Switch tab to the Dispatcher Console.**
2. Point at the parent Mosquito Surge Area Treatment WO — child WO Completed → parent recomputes → all-children-complete flips parent to Completed → `VisitSummaryGenerator` emits a plain-language summary attached to the Incident → Incident closes → PSC closes.
3. The PSC drawer flips from red → green. ETR replaced with "Resolved" timestamp.

**What to say (the pivot — ~30 sec):**
- "Service loop closed. Now watch the **revenue loop** close."

**What to click (the dashboard — this is the close):**
1. **Switch tab to the Manager Coaching dashboard.**
2. **Walk through the 4 reports in this exact order:**

   **Report 1 — Attach Rate by Tech (MTD).**
   - Point at Maria's row. **"Maria's attach rate is up 18% this month."**
   - Note that today's Bennett pitch is reflected — +1 lead, captured ~3 hours ago, source = quarterly route.
   - Tom's row is lower — he's been on cluster response, not quarterly routes.

   **Report 2 — Top Performers (YTD).**
   - Highlight 2–3 names — these are the techs Massey would want to celebrate at the next branch meeting.

   **Report 3 — Coaching Opportunities.**
   - Techs with **low attach rate but high route quality** — they're doing the service well, they just aren't asking. **This is the coachable cohort.**
   - "Sidekick suggests: schedule a coaching session for Tom — his route quality is excellent, attach rate is below median."

   **Report 4 — Leads from Route → Conversion.**
   - Point at the funnel: leads spawned (Maria's Bennett pitch + others) → contacted by Jordan → converted.
   - **Conversion rate.** This is the number Massey leadership cares about.

**What to say (the close — verbatim suggested):**
- "Massey wins on quality service and customer relationships. That's the brand. What you just saw is the platform doing **three things at once on every truck roll**:"
  1. "Closing the service ticket."
  2. "Capturing the revenue conversation Maria already had at the door."
  3. "Showing Ray the coaching signal he can act on in tomorrow's standup."
- "**Every truck roll is a sales conversation. Every route is a coaching opportunity. Every cluster is a chance to be proactive instead of reactive.** That's what we'd build with you."
- Pause. "Questions?"

**Time budget:** 4–5 min. The dashboard walk-through is the close — do not cut it short.

**Common gotchas:**
- If Maria's Bennett lead doesn't show in the Attach Rate report, the Lead-to-Account-rollup hasn't fired yet — narrate around it ("if you check this dashboard tomorrow morning, Maria's Bennett pitch will be reflected here") rather than refreshing in front of the audience.

---

## Q&A prep

### Common buyer questions (one-line answers)

- **"What's the Voice number cost?"** — Standard Service Cloud Voice licensing; Allen can quote.
- **"How long does briefcase priming take?"** — 30–90 seconds depending on data volume; runs in background on app launch and on a schedule.
- **"Does Sidekick learn from outcomes?"** — Yes — `Last_Upsell_Outcome__c` feeds back into ranking; full ML personalization is a roadmap item, not a Day-1 feature.
- **"Can the talk-tracks be edited by marketing without code?"** — Yes. `Upsell_Talk_Track__mdt` is Custom Metadata; non-developer admins can edit.
- **"What if a customer says 'don't pitch me again'?"** — Captured as outcome = "Not Interested" with a cooldown period before re-pitch.
- **"How does the platform know it's termite season?"** — Seasonal multipliers in `UpsellCoachService.recommend()` — FL termite Mar–May, mosquito Apr–Oct. Tunable.
- **"Is the cluster detection real-time?"** — Within 2-minute latency; ClusterDetector runs scheduled.
- **"Does this work on Android?"** — Yes — FSL Mobile is iOS + Android.
- **"What about commercial customers?"** — Architecture supports it; we modeled residential single-family for this demo. Roadmap item.

### Discovery follow-ups (what we'd want to learn next)

- Massey's current attach rate baseline by branch + tech — to size the coaching opportunity.
- Marketing team's appetite to own the talk-track copy in Custom Metadata.
- Branch ops manager workflow — does Ray's workday already include a coaching ritual we'd plug into?
- Knowledge article volume + ownership — to scope P2.5-style content authoring.
- Sentricon / Termidor application logging — current paper vs digital state.

### Known limitations honest to call out

- **Smart bait stations with cellular telemetry are mocked** — we model station state on the Asset, no real device integration.
- **Real-time route optimization is standard SF scheduling, not custom.** If a prospect asks about ML route optimization, redirect to roadmap.
- **Customer self-service rescheduling via SMS is not modeled** — portal + agent only.
- **Bed bug + wildlife removal not modeled** — different workflows + permitting.
- **PMT capital programs not modeled** — pest doesn't have a clean capital-program analogue. Architecture supports it; redirect to "we use it in our utility and telco demos."

---

## What to NOT click during the demo

These are seed-script Quick Actions or demo-magic buttons that should NOT fire mid-presentation. **Pre-stage before the customer joins; do not trigger live unless the scene calls for it.**

- **`Asset.DemoMagic_Run_Pest_Pressure_Analysis`** — pre-stage so the 14 candidates already exist; if you click it live you'll watch a spinner and lose the room.
- **`Case.DemoMagic_Detect_Cluster`** — pre-stage; otherwise you'll race the cluster activation and the audience sees inconsistent state.
- **`Incident.DemoMagic_Dispatch_Field`** — only used in the cluster scenes (6, 7, 8); do not fire during Scenes 1–4.
- **`Incident.DemoMagic_Notify_Cluster_Customers`** — fires real notification records; only click if Scene 6 audience explicitly asks "what do affected customers see?"
- **`RecordsetFilterCriteria.DemoMagic_Generate_Booster_Inspection_WOs`** — proactive Pest Pressure scenario; **not part of the 9 scenes** in this script. Skip unless a buyer asks for the proactive demo specifically.
- **`ServiceResource.DemoMagic_Emergency_Reassign`** — alternate entrypoint for Scene 7; the canonical entry is the Incident-level Quick Action. Don't confuse the two on stage.

### Demo-magic buttons that need pre-staging
- The 8 cluster Cases must be in **Draft** before the demo starts. If they're already Active, the activation in Scene 6 is anticlimactic.
- The Bennett WO must be on Step 3, with Steps 1 and 2 pre-checked. Do not run the orchestrator from Step 1 live — Scenes 5 and 8 handle PPE separately.

---

## What to NOT mention (vocabulary discipline)

The demo audience is Massey. Forbidden vocabulary from prior lifecycles **must not appear** in your speech, on screen, or in any narration:

- "subscriber" → say **customer** or **GoGreen customer**
- "fiber" / "OLT" / "ONT" / "splice" / "PON" / "DOCSIS" → these are telco artifacts; never utter
- "circuit" → if a UI label slipped, narrate as "service line"
- "lead service line replacement" / "AMI" → utility artifacts
- "PMT" / "capital program" / "capital build" → not modeled in this demo; redirect to "available in our utility and telco demos" if a prospect asks

If a forbidden word appears on screen (residual from the inherited architecture), **acknowledge it once and move on** — "ignore that label, P6.2 is the cleanup ticket" — do not stop and explain.

---

## If something breaks

1. **Voice doesn't ring through (Scene 1).** Fall back to clicking the simulated inbound Case from Jordan's queue. Acknowledge: "on a real call this routes via Voice — let me show you the agent surface."
2. **Briefcase didn't sync / orchestrator spinners on Maria's phone (Scene 5).** Switch the FSL Mobile screen-mirror to a pre-recorded 90-second video of the Bennett upsell beat. **Have this video pre-loaded** before the demo starts. Do not try to re-prime briefcase live.
3. **Cluster activation Quick Action errors (Scene 6).** Manually flip the Incident record to Active in the record edit. The dispatcher console will catch up within 2 seconds.
4. **`UpsellCoachService.recommend()` times out (Scenes 1, 5, or standalone Quick Action).** Refresh once. If it errors twice, narrate around it ("the recommendation engine is computing — here's what it would surface") and screenshot-fallback. This is the load-bearing service; do not improvise the talk-track from memory.
5. **Manager Coaching dashboard reports show stale data (Scene 9).** Click the report's refresh icon once. If still stale, narrate over it ("you'd see Maria's lead reflected here tomorrow morning after the rollup batch runs").
6. **The org times out / loses session.** Apologize once. Re-login. Resume at the scene boundary, not mid-scene. Do not try to recover within a scene.
7. **A prospect interrupts with a forbidden-word UI artifact.** Acknowledge once, move on. Do not derail.

### Last-resort fallback
If two scenes break in a row, **stop the live demo and pivot to the recorded video walkthrough** (kept on the presenter laptop in `~/demos/massey/recorded/full-walkthrough.mp4`). The recording is 22 minutes — you have time.

---

## End-of-demo posture

- Close on Scene 9's revenue-loop language. Do not add new material after the dashboard.
- Open Q&A. Let the buyer drive.
- Do not say "and one more thing" — there isn't one.

> **The story is: Massey wins on relationships. The platform makes every relationship a revenue conversation. Every truck roll. Every call. Every cluster. End on that.**
