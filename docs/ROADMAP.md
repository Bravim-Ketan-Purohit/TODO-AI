# TODO_AI — Roadmap

Parked directions, kept so nothing gets lost. Updated 2026-07-25.

## Shipped (was on this roadmap, now live)

- **Backlog** — someday tasks park instead of scheduling; ☰ drawer with
  Auto / pick-date-time / drop; morning drain; anti-rot ("parked 12 days —
  schedule or let go?")
- **Living deadlines** — due date + time budget linked to blocks; behind-ness
  detected each morning; one-tap re-spread into real free slots
- **Weekly budgets** — hours per category, scoreboard in the week review
  (scheduler does NOT yet protect underfunded categories — see Goal Ladder)
- **Ask your calendar** — questions about your own history answered from
  14-day aggregates, never invented
- **Micro-gap filler** — "25 min until Design review — enough for this:"
- **Small-task batching** — 3+ short tasks → offer to fuse into one block
- **Live morning briefing** — 7:15 notification composed from tomorrow's
  actual shape (stale-by-morning caveat: needs push server for fully fresh)
- **Two-way calendar sync** — collisions reflow, gcal deletions ask
  drop/restore, gcal moves followed silently
- Day share card, focus sessions + ambient sound + Live Activity, NOW/NEXT
  widget, app icon, haptics/motion

## Tracks (established, still open)

### Track 1 — Learning depth
Duration learning (planned 30, took 55 → schedule 50 and say so),
auto-buffering after slip-prone hours, realism check at propose time
("you've never completed 6 tasks on a Saturday"). All from data already
collected. Related: Energy-Aware (#7) and Causality Ledger (#8) below.

### Track 2 — Faster to reach
Action button / Siri / Shortcuts via App Intents (rant without opening the
app; approve deep-links in), interactive widget (tap to complete),
block-start nudges, Control Center control. Still the biggest UX unlock.

### Track 3 — Real-time calendar watch
Google Calendar webhooks → disruption push in seconds instead of on-open
polling. Also makes the morning briefing fully fresh.

### Track 4 — Make it shippable
Backend off the Mac (Fly.io/Railway), multi-user auth, TestFlight.

## The big fifteen (added 2026-07-25)

1. **Calendar Archaeology — day-one personalization.** On connect, mine the
   last 90 days of the calendar and infer the real rhythm (wake, energy
   peak, category windows, meeting load by weekday) before onboarding asks
   anything. Play it back as "here's what I think your week looks like —
   correct me." Kills the cold-start valley; one extra Calendar read, zero
   new scopes. *(Absorbs the earlier "cold-start learning" idea.)*

2. **Proof of Work — completion inferred, never asked.** HealthKit workouts,
   Focus state, geofences, screen time, commits via MCP → statuses stop
   depending on manual taps (which decay in two weeks in every tracker).
   Every engine feature is downstream of completion data; this is also the
   native-app moat a web competitor cannot copy.

3. **TODO_AI as an MCP server — agent-writable calendar.** Expose
   find_time / propose_block / park_in_backlog / whats_my_day over MCP so
   Claude, Cursor, any agent can propose time — approval gate intact,
   agent items land as proposals or backlog, never writes. A category
   position (the well-behaved sink for agent commitments), and a thin
   layer over endpoints that already exist.

4. **MCP host — pull obligations in.** Connect Linear / GitHub / Gmail /
   Notion / Canvas; assigned issues, review requests, emailed promises
   surface as backlog candidates ("3 review requests, ~90 min — Tuesday
   afternoon is open"). Never auto-scheduled. One protocol instead of five
   OAuth integrations. *(Extends "capture from everywhere"; the share-sheet
   idea remains the manual sibling.)*

5. **Execution Mode — the block does the work with you.** For digital admin
   blocks: at block start the agent drafts every reply / pre-fills the
   expense report / assembles 1:1 prep, and hands over an approve queue.
   The user spends the block deciding, not composing. Nothing sends
   without a tap. A different category from arranging time.

6. **What-If Simulator — capacity answers before you commit.** "Can I take
   Friday off?" → a real simulation over the next 2–4 weeks with the
   reflowed plan attached, including honest negatives ("4×/week gym only
   fits if deep work drops to 6h — pick one"). Read-only path over
   suggest_slots + reflow machinery. **Demo feature.**

7. **Energy-Aware Scheduling.** Read last night's sleep/recovery from
   HealthKit each morning; on a 5-hour night push deep work later, trim
   load, and say why. Works from day one, creates a daily open that isn't
   nagging, native-only moat.

8. **Causality Ledger — why plans fail.** One-tap reason chips on any miss
   (ran long · interrupted · didn't feel like it · blocked) → after a month,
   falsifiable claims: "Deep work fails on 3+-meeting days 8/10 times —
   cap meeting days at one deep block?" Feeds the scheduler as constraints,
   not a dashboard.

9. **Meeting-Cost Auditor.** Roll up /disruptions history per recurring
   meeting: "Weekly sync displaced 6.5h of deep work in 3 weeks; 2 of 9
   moved blocks completed." Offer the drafted decline / async alternative.
   Byproduct of shipped reflow logic; most shareable artifact. **Demo
   feature.**

10. **Spaced Repetition for Deadlines.** Exam-linked deadlines lay blocks on
    a spacing curve (shorter early contacts, expanding-interval retrieval
    passes, light day before) instead of evenly spreading minutes; each
    block carries its purpose in the title. Student-persona killer feature;
    changes respread layout only.

11. **Burnout Guard.** Budgets blown 3 weeks running + slip climbing +
    sleep down → propose a genuinely lighter week and decline to schedule
    past a healthy-set ceiling (deliberate override only). The app that
    argues for less buys credibility streaks can't.

12. **Goal Ladder — quarter → week → day.** Declare outcomes ("TestFlight
    by Sept 30", "half marathon in October"); the app back-solves weekly
    budgets and defends them daily. Deadlines generalized; gives budgets a
    purpose so they survive week three.

13. **Focus Enforcement.** Deep-work blocks arm Screen Time restrictions
    (DeviceActivity + ManagedSettings), opt-in per category, released at
    block end; overrides logged (feeds #8). *Note: earlier decision was
    "timer only, drop the Focus claim" — this is the real enforcement that
    would earn the claim; revisit that decision before building.*

14. **Transit-Aware Placement.** Tasks with locations get MKDirections
    travel time; physically impossible back-to-backs are refused at propose
    time ("can't leave the gym at 5:00 and be downtown at 5:15 — dinner
    moved to 5:45"). Small, native, protects the never-wrong trust claim.

15. **On-Device Parse Fallback.** Route simple parses/edits ("move gym
    to 9") through Apple's on-device foundation models — instant, offline,
    free, private; reserve the cloud model for multi-day planning and
    overflow reasoning. Cuts latency and free-tier burn on the
    highest-volume traffic; answers spec §9's privacy flag.

## Table stakes (gates, not features)

- **Multi-calendar / work-life contexts** — work + personal as busy layers,
  rules like "no work tasks after 19:00". Required before widening past
  two users.
- **iPad layout** — spec promises iPadOS; currently a stretched iPhone app.

## Sequencing (recommended)

1. **#1 Calendar Archaeology** — cheapest, first plan feels uncanny.
2. **#2 Proof of Work** — everything on this roadmap is downstream of
   completion data that currently rots.
3. **#3 MCP server** — thin layer, category position.
- **#6 What-If** and **#9 Meeting-Cost** are the demo pair ("wait, it can
  do that?") — both mostly read-only over shipped code.
- Track 2 remains the biggest pure-UX unlock and can interleave anywhere.

## Smaller parked ideas

- Plan-tomorrow-tonight (evening recap pill → rant lands dated tomorrow)
- Templates ("make Monday my default", "same as last Tuesday")
- Semester import (photo of timetable → Schedule anchors)
- Monthly report; Apple Watch (rant from wrist, NOW complication);
  Spotlight; scheduler protection of underfunded budget categories;
  deadline respread honoring role block-length preferences
