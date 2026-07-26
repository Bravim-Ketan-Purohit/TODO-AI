# TODO_AI — Roadmap (parked ideas, documented 2026-07-25)

Everything designed to date is built (all screens through 5a–5i, plus
calendar two-way sync). What follows is the agreed backlog of directions,
kept here so nothing gets lost. Nothing below is committed work.

## Track 1 — Make it smarter about *you* (learning depth)

The moat: a scheduler that measurably improves at the individual user.
All of this runs on data already collected (`completed_at`, slip, status).

- **Duration learning** — planned 30 min for emails, actually took 55, five
  times running → schedule the real duration and say so: "Planning 50 min —
  your last five email blocks ran long."
- **Auto-buffering** — afternoons slip +38 min on average → stop packing
  back-to-back after 14:00, leave 10-min gaps automatically.
- **Realism check at propose-time** — "You've never completed 6 tasks on a
  Saturday. Plan 4 and hold 2 in reserve?" (never-guess applied to ambition)

## Track 2 — Make it faster to reach (chosen next build)

The core loop is 10 seconds of talking; getting into the app is the friction.

- **Action button / Siri / Shortcuts** (App Intents): press → rant → plan
  proposed without opening the app. Turns voice (5i) into the primary input.
  Constraint: the approve step deep-links into the app (one tap) — consistent
  with "nothing syncs without approval".
- **Interactive widget** — tap a block in the widget to mark it done.
- **Block-start nudges** — optional "Deep work in 5 min" notification,
  per-category opt-in. The calendar defending itself *before* the block.
- **Control Center control** — one-tap rant for non-Action-button phones.

## Track 3 — Real-time calendar watch

Google Calendar push notifications (webhooks) → backend learns of changes in
seconds → instant disruption push instead of on-app-open polling. Needs the
public URL (ngrok now, real host later).

## Track 4 — Make it shippable

Backend off the Mac onto a real host (Fly.io/Railway), proper multi-user
auth, TestFlight. The gate between "my app" and "an app". No new features.

## Engine features (beyond connectivity)

- **The Backlog** — tasks without a day ("renew passport sometime"). Parked,
  never lost, never guessed onto a date. The engine drains it: light day
  detected → "90 free minutes this afternoon — knock out 'call dentist'?"
  GTD inbox where the AI does the weekly review.
- **Deadlines as living objects** — track hours-remaining vs days-remaining.
  Miss a prep block → automatic re-spread offer: "1.5h behind on Physics —
  recover Wed evening + Thu morning?" The reflow engine pointed at goals.
- **Capture from everywhere** — share sheet (email/message/link → scheduled
  block with the link attached), Apple Watch (rant from wrist, NOW
  complication, mark-done), Spotlight.
- **Time budgets** — user declares "10h deep work, 3h health per week";
  weekly review becomes a scoreboard; scheduler protects underfunded
  categories. Descriptive → normative.
- **Semester import (student role)** — photo of a timetable/syllabus →
  classes become Schedule anchors.
- **Templates** — "make Monday my default", "same as last Tuesday".
- **Monthly report** — where the hours actually went, by category.
