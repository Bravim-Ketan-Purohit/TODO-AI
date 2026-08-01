<div align="center">

<img src="docs/screenshots/icon.png" width="120" alt="TODO-AI app icon" />

# TODO-AI

### Talk about your day. Get a calendar.

**The planner that schedules for you — around everything already on your calendar.**

No lists. No drag-and-drop. No "when would you like to do this?" dropdowns.
Type what's on your mind and it becomes real, color-coded, conflict-free time
on your Google Calendar.

<br />

![Platform](https://img.shields.io/badge/platform-iOS%20%7C%20iPadOS-08090a?style=flat-square&labelColor=0f1011)
![Swift](https://img.shields.io/badge/SwiftUI-native-e4f222?style=flat-square&labelColor=0f1011)
![Backend](https://img.shields.io/badge/FastAPI-Python%203.12-08090a?style=flat-square&labelColor=0f1011)
![Calendar](https://img.shields.io/badge/Google%20Calendar-two--way%20sync-08090a?style=flat-square&labelColor=0f1011)
![License](https://img.shields.io/badge/license-MIT-08090a?style=flat-square&labelColor=0f1011)

</div>

<br />

---

<br />

> **"gym tomorrow morning, 2 hours of thesis prep, and dinner with Sam at 8"**
>
> ↓
>
> Four questions answered, one tap on **Approve**, and your Tuesday is built —
> workout at your energy peak, deep work protected, dinner locked, and nothing
> touching the standup that was already there.

<br />

## Screenshots

<div align="center">

| Chat — your only input | Proposal — approve before it syncs | Today's timeline |
|:---:|:---:|:---:|
| <img src="docs/screenshots/01-chat.png" width="230" /> | <img src="docs/screenshots/02-proposal.png" width="230" /> | <img src="docs/screenshots/03-timeline.png" width="230" /> |

| Focus session | Week review | Wrapped |
|:---:|:---:|:---:|
| <img src="docs/screenshots/04-focus.png" width="230" /> | <img src="docs/screenshots/05-week-review.png" width="230" /> | <img src="docs/screenshots/06-wrapped.png" width="230" /> |

</div>

<br />

---

<br />

## What makes it different

### 🗣 Chat is the only thing you have to learn
There is no form, no date picker you're forced through, no task list to groom.
You type — or hold the mic and ramble — and the app does the structuring. Every
other screen in the app is optional; the chat alone can run your entire week.

### 🤔 It never guesses. It asks.
Most AI planners invent a start time and a duration, and you spend your day
fixing them. This one refuses to. If it doesn't know how long your gym session
runs or when your call is, it asks — with two smart suggestions pulled from your
own profile and a native time picker as the third. **A wrong guess costs more
trust than a question costs patience.**

### ✅ Nothing reaches your calendar without a tap
Every plan arrives as a **proposal**: placed, conflict-checked, and fully
visible — but not yet real. You approve it, or you adjust it in the same
sentence ("make the prep 90 minutes and push dinner to 8:30"). Only then does
anything get written to Google Calendar.

### 🧩 It schedules *around* your life, not on top of it
Meetings, classes, and anything else already on your calendar are treated as
immovable. Your flexible tasks fill the gaps between them — deep work lands in
your stated energy peak, admin goes in the dips, workouts follow your habit.
The app learns these windows from how you actually reschedule things.

<br />

## Features

<table>
<tr><td width="50%" valign="top">

#### 🎙 Voice Rant
Hold the button, describe your day out loud, let go. On-device speech
recognition turns a 40-second ramble into a structured plan. The fastest path
from *thought* to *scheduled*.

</td><td width="50%" valign="top">

#### 📥 Backlog
Say "sometime next week" and it parks instead of scheduling. Drain it each
morning, auto-place it into a real gap, or let it go. Items that rot get called
out — *"parked 12 days — schedule it or drop it?"*

</td></tr>
<tr><td width="50%" valign="top">

#### ⏳ Living Deadlines
*"6 hours of prep before Friday's exam"* becomes real blocks across real days,
weighted heavier as the date approaches. Fall behind and it notices — then
re-spreads the remaining hours into slots that actually exist.

</td><td width="50%" valign="top">

#### 🔁 Two-Way Calendar Sync
Move a block in Google Calendar and the app follows silently. Delete one and it
asks whether to drop or restore. A new meeting that collides with your deep work
triggers an automatic reflow with the change explained.

</td></tr>
<tr><td width="50%" valign="top">

#### 🕳 Micro-Gap Filler
*"25 minutes until Design review — enough for this:"* Dead time between meetings
gets matched against your backlog, so the awkward gaps stop evaporating.

</td><td width="50%" valign="top">

#### 📊 Weekly Budgets
Set hours per category — 12h deep work, 4h health — and get a real scoreboard
every week. Combined with slip tracking, it shows where your time actually
went versus where you said it would.

</td></tr>
<tr><td width="50%" valign="top">

#### 💬 Ask Your Calendar
*"How many hours of deep work this week?"* · *"When did I last work out?"* ·
*"What does Thursday look like?"* — answered from your real 14-day history,
with real numbers. It will say "I can't tell from your data" rather than
invent a figure.

</td><td width="50%" valign="top">

#### 🎯 Focus Sessions
Start a block and get a full-screen timer with layered ambient sound and a
Live Activity on the Lock Screen. The block ends, the status writes itself,
and the calendar records what actually happened.

</td></tr>
<tr><td width="50%" valign="top">

#### 🌅 Morning Briefing
A 7:15 notification composed from your day's actual shape — not a generic
"good morning," but *what's fixed, what's flexible, and what's at risk*.

</td><td width="50%" valign="top">

#### 🧠 Meeting Prep
Spots meetings that need preparation and offers to schedule the prep block
before them — instead of letting you walk in cold at 9:59.

</td></tr>
<tr><td width="50%" valign="top">

#### 📦 Small-Task Batching
Three or more short tasks in one proposal? It offers to fuse them into a
single admin block. Fewer, bigger blocks beat a calendar shredded into
fifteen-minute confetti.

</td><td width="50%" valign="top">

#### 🔄 Rollover
Unfinished tasks don't silently vanish at midnight. The next morning you
decide: reschedule, park in the backlog, or let go — deliberately.

</td></tr>
<tr><td width="50%" valign="top">

#### 📝 Day Notes
A mood, a line, and a photo per day. The lightest possible journal, attached
to the day it belongs to — so the calendar remembers how it felt, not just
what was on it.

</td><td width="50%" valign="top">

#### 🎬 Wrapped & Sunday Review
A guided end-of-week ritual, and a Spotify-Wrapped-style story of your month —
hours by category, your best streak, your most productive day. Built to be
screenshotted.

</td></tr>
<tr><td width="50%" valign="top">

#### 📱 Home Screen Widget
A NOW / NEXT widget showing the block you're in and the one coming up, so the
plan is visible without opening anything.

</td><td width="50%" valign="top">

#### 🎨 Share Card
Turn any day into a clean, dark, shareable card — your schedule as an artifact
worth posting.

</td></tr>
</table>

<br />

## How it works

```
   You type                  Backend                    Google Calendar
   ────────                  ───────                    ───────────────

  "gym at 7,           ┌──────────────────┐
   2h of thesis   ───▶ │  LLM parse       │  structured tasks
   prep"               │  (never invents) │  + open questions
                       └────────┬─────────┘
                                │
                       ┌────────▼─────────┐
   answers        ───▶ │  Clarify loop    │  asks until every task
                       │                  │  has a real duration
                       └────────┬─────────┘
                                │
                       ┌────────▼─────────┐  reads your existing
                       │  Scheduler       │◀── events as immovable
                       │  greedy packing  │    busy intervals
                       └────────┬─────────┘
                                │
                       ┌────────▼─────────┐
   ✓ Approve      ───▶ │  Sync            │───▶  color-coded events
                       └──────────────────┘      written for real
```

**The calendar is your history, not the chat.** The app stores almost nothing
locally — your Google Calendar is the source of truth, and the transcript is
disposable.

<br />

## Tech

| Layer | Choice | Why |
|:---|:---|:---|
| **App** | SwiftUI (iOS + iPadOS) | Native gestures, widgets, Live Activities, on-device speech |
| **Backend** | FastAPI + `uvicorn` | Async, tiny, typed by Pydantic |
| **Store** | stdlib `sqlite3`, no ORM | One file, zero migration tooling, plenty for this |
| **LLM** | OpenRouter proxy | Swappable model, hand-written JSON schema, one retry with the validation error fed back |
| **Calendar** | Google Calendar REST v3 | Auto token refresh, category → `colorId` mapping |
| **Auth** | `ASWebAuthenticationSession` + Keychain | Real OAuth, session token never touches `UserDefaults` |

Design language: a midnight-precision dark system — near-black canvas
(`#08090a`), hairline `0.5px` borders, and exactly **one** acid-lime accent
(`#e4f222`) reserved for the action you're meant to take. Full tokens in
[`docs/DESIGN.md`](docs/DESIGN.md).

<br />

## Getting started

**Requirements:** Xcode with an iOS 27 SDK · Python 3.12+ · a Google Cloud
project with the Calendar API enabled · an [OpenRouter](https://openrouter.ai)
key (the default model is free).

```bash
# 1. Backend
cd apps/api
cp .env.example .env          # fill in your Google + OpenRouter credentials
uv sync
uv run uvicorn app.main:app --reload

# 2. iOS app
open apps/ios/TODO_AI/TODO_AI.xcodeproj
# set your backend URL, then ⌘R
```

Detailed setup: [`apps/api/README.md`](apps/api/README.md) ·
[`apps/ios/README.md`](apps/ios/README.md)

> **Note** — `GOOGLE_CLIENT_SECRET`, your OpenRouter key, and the SQLite
> database are all git-ignored. Never commit them; the database holds live
> OAuth refresh tokens.

<br />

## Repo layout

```
apps/
  ios/     SwiftUI app — Chat, History, Settings, widgets, Live Activity
  api/     FastAPI backend
    app/
      chat.py        conversation state machine (propose → approve → sync)
      scheduler.py   greedy interval packing around fixed events
      llm.py         OpenRouter proxy + the behavioral contract prompt
      gcal.py        Google Calendar broker with token refresh
      db.py          SQLite schema
docs/
  spec.md      product + technical spec
  DESIGN.md    design system tokens
  ROADMAP.md   what's shipped, what's next
```

<br />

## Roadmap

Shipped and parked work lives in [`docs/ROADMAP.md`](docs/ROADMAP.md). The
directions being explored next:

- **Calendar Archaeology** — mine 90 days of history on connect, so the very
  first plan already knows your rhythm
- **Proof of Work** — infer completion from HealthKit, Focus state, and
  geofences instead of asking for a tap
- **MCP server** — expose `find_time` / `propose_block` so any agent can
  request time, approval gate intact
- **What-If Simulator** — *"can I take Friday off?"* answered with a real
  reflowed plan attached
- **Energy-Aware Scheduling** — a five-hour night pushes deep work later, and
  says why

<br />

## Design principles

1. **The user's only job is to type.** Everything else is the app's problem.
2. **Never guess — always ask.** One question beats one wrong assumption.
3. **Nothing syncs without approval.** The calendar is sacred.
4. **The laziest stack that holds.** Native and stdlib before dependencies.
5. **The calendar is your history, not the chat.**

<br />

---

<div align="center">
<sub>Built with SwiftUI and FastAPI · MIT licensed</sub>
</div>
