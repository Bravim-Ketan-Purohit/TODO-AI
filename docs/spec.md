# Spec — Conversational Day Planner (working title: TODO_AI)

> A persona-aware, conversational day-planner for iOS & iPadOS. You brain-dump
> your day in plain English; the AI asks about anything ambiguous, proposes a
> plan that respects both your personal rhythm *and* your existing Google
> Calendar, then writes color-coded events on approval. The **calendar is your
> history** — not the chat.

---

## 0. Guiding Principle — AI-Native, Chat-Is-Everything

**The user's only job is to type.** Anything that arrives in chat — a daily plan,
a one-off task, a semester of classes, or an *edit to something already scheduled*
— is converted by the AI into a proper task and then a calendar event. There are
no manual forms, time-pickers, or drag-to-reschedule required. Chat is the single
universal interface for creating, changing, and removing anything on the calendar.

---

## 1. Vision

Most calendar apps make *you* do the tedious work: picking exact times, avoiding
conflicts, remembering when you actually focus best. This app flips that:

**You describe intent. The AI handles the logistics.**

You type a messy, natural plan. The app fits that flexible plan into the fixed
skeleton of meetings you already have on Google Calendar, using what it knows about
your energy and preferences — and it *asks* instead of guessing when unclear.

---

## 2. Platform & Tech Stack

**Philosophy:** laziest stack that actually holds. Native + stdlib first, add a
dependency only when a few lines can't do the job. The app is **nearly stateless**
— the backend and Google Calendar are the source of truth.

### Client — iOS / iPadOS

| Need | Choice | Skipped |
|---|---|---|
| UI | **SwiftUI** | — (native) |
| Networking | **URLSession** (`data(for:)`) | Alamofire — it's a one-liner |
| Google login | **ASWebAuthenticationSession** — opens Google's OAuth page, hands the auth code to *our* backend | GoogleSignIn SDK — a whole dep to avoid one web sheet |
| Local storage | **none**; **Keychain** for the single session token | SwiftData/Core Data entirely — a local DB is a sync bug waiting to happen |
| JSON | **Codable** | — (native) |

The app types to the backend and renders what comes back. No local DB, no Google SDK.

### Backend — Python

| Need | Choice | Skipped |
|---|---|---|
| API | **FastAPI + uvicorn** | — |
| LLM calls | **httpx** POST to OpenRouter (OpenAI-compatible REST) | the `openai` SDK — a dep for a single POST |
| LLM output → typed | **pydantic** (ships with FastAPI) validates the model's JSON into `Task` | a custom parser/validation layer |
| Google OAuth exchange + refresh | **google-auth** + **google-auth-oauthlib** | hand-rolling token refresh — a security edge-case path, not a place to be clever |
| Calendar read/write | **httpx** against the Calendar REST API | google-api-python-client discovery bloat |
| Storage (user→token, profile, completions) | **SQLite** (stdlib `sqlite3`); profile stored as a JSON blob | Postgres + SQLAlchemy + Alembic — infra cosplay at 2 users |
| Secrets | **os.environ** / `.env` | pydantic-settings for 2 keys |
| Scheduling engine | **plain greedy interval-packing** (~50 lines: sort anchors, fill gaps) | OR-tools / any solver — YAGNI until a day genuinely can't fit |
| Deploy | one **uvicorn** box on a free tier (Railway / Fly / Render) | Docker Compose, k8s, CI/CD — none needed at 2 users |

**Deliberately NOT lazy** (security/correctness): OAuth refresh uses the real
library; the session token lives in **Keychain, not UserDefaults**.

### LLM (via OpenRouter)
- Model: `nvidia/nemotron-3-ultra-550b-a55b:free`
  - NVIDIA Nemotron 3 Ultra (free) — MoE **55B active / 550B total**, hybrid
    Transformer-Mamba, **1M-token context**, text→text, ~2s P50, ~40 tps. Suited
    for long-running agentic tasks. **Free tier, testing only.**
  - ⚠️ **Free-endpoint caveat (see §9):** NVIDIA logs free-endpoint sessions for
    product improvement (stated *not* linked to identity) and asks users not to
    upload personal data. Fine for a 2-user test; **production must move to a
    paid/private model.**
- All LLM calls run **server-side** (the OpenRouter key never ships in the app).

### Scope
- **Calendars:** **exactly one** — the Google account connected at signup. We tell
  users: *"Connect the account whose calendar you want the app to control."*
- **Time zones:** the **device's** local tz. Travel out of scope.
- **Launch:** **2 users** (private test), then reassess.

---

## 3. Core User Flow

1. **Brain-dump (chat):** morning or night-before, the user types a free-form plan.
   > *"Gym for an hour after I wake up, deep work on the design doc for 2 hrs,
   > lunch with Sam, reply to emails, evening walk, read before bed."*
2. **AI parses** the text into structured tasks (title, duration, category,
   time-if-specified).
3. **Clarification loop:** for anything ambiguous, the AI asks — **batched into one
   message**, with smart preference-based suggestions the user can one-tap.
4. **Conflict-aware scheduling:** read existing Google Calendar events first, then
   slot flexible tasks into free gaps around those meetings and the user's anchors.
5. **Proposed plan → approval:** show the full proposed day; user approves/tweaks
   *before* anything is written.
6. **Sync:** on approval, write events to Google Calendar, color-coded by category.
7. **Edit anytime via chat:** *"change my gym to 9am today"* → the app updates the
   already-synced event. (See §4.10.)
8. **Track & learn:** completion is marked, colors update, and completion data
   quietly tunes future scheduling.

---

## 4. Key Features

### 4.1 Natural-language input
Free-text chat is the primary — and only required — input surface.

### 4.2 AI parsing → structured tasks
The LLM converts messy text into structured events: **title, duration, category,
time (if specified), location (if given), recurrence (if implied).**

### 4.3 Clarification loop (no arbitrary times) — *core trust feature*
When a task has no time or duration, the app **asks in chat instead of guessing**:
- **Detect all ambiguities in one pass**, ask them **batched in a single message**.
- **Offer smart, tappable suggestions** from the Preference Profile:
  > *"'Reply to emails' — you're usually admin-focused around 4pm. Put it there for
  > 30 min? [Yes] [Pick another time]"*
- **Never silently place an arbitrary time.** Ambiguity → ask.

### 4.4 Proposed-plan approval
Before writing to Google Calendar, show the **full proposed day** for review.
Approve → sync.

### 4.5 Persona-based onboarding — *(what the user called "RBAC")*
> **Naming note:** This is **role-based *personalization***, not RBAC. RBAC
> (Role-Based Access Control) is a security concept and is **not** this feature.

At signup the user picks a **role**, layering **role-specific questions** on a
**base set** (chronotype/energy peaks, meal times, workout, sleep).

**Initial roles (only two for launch):**
- **Developer (tech engineer):** deep-work blocks, meeting-heavy days, on-call,
  code-review time.
- **Student:** class schedule captured conversationally (see §4.11), study/focus
  windows, assignment deadlines, break patterns.

Answers are stored as the **Preference Profile** — the brain of the scheduler.

### 4.6 Fixed anchors vs. flexible tasks — *core scheduling model*
- **Fixed anchors:** meals, sleep, workout, class — roughly fixed from preferences.
- **Flexible tasks:** the day's typed to-dos, slotted into gaps **around anchors
  AND around real Google Calendar meetings.**

### 4.7 Chat interface
A proper conversational UI for input, clarification, and edits.

### 4.8 Calendar-as-history (the calendar is the record, not the chat UI)
The **user-facing history** is each day's calendar, not a chat transcript. Events
are **color-coded on two dimensions**:
- **Category** (deep work, health, meals, admin, social) → the **hue**.
- **Status** (planned, completed, missed, rescheduled) → **shade/opacity** or a
  checkmark badge.

*(Note: chat content is retained server-side per §9 privacy terms, but it is never
surfaced as the history — the calendar is.)*

### 4.9 Feedback / learning loop
Completion colors are **data**. Repeatedly missing the 6am workout →
> *"Your workouts land better at 7pm — want me to default there?"*

### 4.10 Chat-driven editing of synced events — *AI-native editing*
Already-synced events are fully editable through natural language. Examples:
- *"Change my gym time to 9:00 am for today."* → move today's gym event to 9am.
- *"Cancel my evening walk."* → delete that event.
- *"Push deep work to 2 hours."* → extend duration and reflow the day if needed.

Flow: chat → LLM interprets intent + target event → app locates the matching Google
Calendar event → applies update (with a quick confirm for destructive changes).

### 4.11 Long-term / recurring anchors from chat (e.g. student class schedules)
The user can describe a semester of classes in one message and the app creates
**permanent, recurring events** that are marked as **fixed anchors** for that span.
Example input:
> *"I'm taking three classes this semester. Most are in buildings X, Y, and Z.
> Times are: CS101 Mon/Wed 9–10:30 in X, Math Tue/Thu 11–12 in Y, Physics Fri 2–4
> in Z."*

The app parses this into recurring calendar events (with location) that persist
across the semester and are treated as immovable when scheduling daily tasks.

---

## 5. Data Model (first pass)

### PreferenceProfile
- `role` (developer | student)   *(extensible later)*
- `chronotype` / energy peak windows
- `anchors`: [{ type: meal|sleep|workout|class, defaultTime, defaultDuration }]
- `categoryTimePreferences`: e.g. deepWork → morning, admin → late afternoon
- role-specific fields (per role pack)

### Task
- `id`, `title`, `category`
- `durationMinutes` (nullable → triggers clarification)
- `requestedTime` (nullable → triggers clarification)
- `location` (nullable — e.g. building X)
- `recurrence` (nullable — e.g. Mon/Wed, until semester end)
- `isPermanentAnchor` (bool — true for class schedules etc.)
- `scheduledStart` / `scheduledEnd`
- `status` (planned | completed | missed | rescheduled | inProgress)
- `googleEventId` (after sync)
- `source` (chat message id)

### DayPlan
- `date`, `tasks: [Task]`, `approvalState` (draft | approved | synced)

### CompletionEvent (learning loop)
- `taskCategory`, `plannedTime`, `actualOutcome`, `date`

> Existing Google Calendar events are **read-only inputs** to scheduling — never
> overwritten (except events *this app created*, which chat can edit per §4.10).

---

## 6. Scheduling Logic (outline)

1. **Load fixed layer:** existing Google Calendar events + preference anchors +
   permanent recurring anchors (classes) → immovable/blocked.
2. **Resolve ambiguity:** any task missing time/duration → clarification loop.
3. **Rank flexible tasks** by category → preferred time window (from profile).
4. **Fit** each into free gaps, respecting energy peaks (deep work in peaks, admin
   in low-energy windows).
5. **Detect conflicts / overflow;** surface options (shorten, move day, drop).
6. **Present proposed plan** for approval.
7. **On approve:** write to Google Calendar with category colors.
8. **Post-day:** capture completion → feed learning loop.

---

## 7. Screens (first pass)

- **Onboarding:** role picker (developer / student) → base questions → role pack.
- **Chat / Planner:** conversational input + clarification + proposed-plan card +
  edit commands.
- **Day Calendar:** color-coded timeline (category hue + status shade); tap to mark
  complete/reschedule.
- **History:** scroll back through past days' calendars.
- **Settings / Profile:** edit preferences, role, anchors, Google account.

---

## 8. MVP — Build Order

1. **Backend skeleton** (FastAPI): OpenRouter proxy + Google OAuth token storage.
2. **Google Calendar connect** (single account) + read existing events.
3. **Chat input → LLM parse** into structured tasks.
4. **Clarification loop** for missing time/duration (batched, with suggestions).
5. **Preference Profile** via persona-based onboarding (developer + student).
6. **Scheduling engine** (fixed skeleton + flexible fill), conflict-aware.
7. **Proposed-plan approval → write to Google Calendar.**
8. **Chat-driven editing** of synced events (§4.10).
9. **Long-term recurring anchors** from chat (§4.11 — student classes).
10. **Day calendar view** with category + status color-coding.
11. **Completion tracking.**
12. **Learning loop.** *(post-MVP polish)*

---

## 9. Resolved Decisions

| Question | Decision |
|---|---|
| **LLM & where parsing runs** | OpenRouter, model `nvidia/nemotron-3-ultra-550b-a55b:free` (free, for testing). Parsing runs **server-side** in the FastAPI backend (keeps the API key secret). |
| **Backend?** | Yes — a minimally invasive **Python FastAPI** backend (LLM proxy, OAuth tokens, Calendar broker, learning loop). |
| **Which calendars** | **One only**, from the Google account connected at signup. User connects the account whose calendar they want controlled. |
| **Time zones / travel** | Device local time zone. Travel out of scope. |
| **Editing a synced plan** | Fully editable via chat (§4.10) — natural-language move/extend/cancel. |
| **Privacy of chat** | **Chat is retained** for data purposes and covered by proper **T&Cs**, which must state it is **decoupled from the user's name/identity — we keep the data, not the person.** |
| **Role packs** | Launch with **two**: developer (tech engineer) and student (class schedule captured via chat, §4.11). |
| **Launch size** | **2 users** initially, then reassess. |

### ⚠️ Engineering flags to resolve before/at production
1. **Free-model data logging:** the NVIDIA free endpoint logs sessions for
   improvement and warns against sending personal data. We *will* be sending
   users' plans (personal-ish). Fine for a 2-user test; **before real launch, move
   to a paid/private model** and update the T&C accordingly.
2. **"Unlinked to identity" nuance:** the backend still needs to map a user → their
   Google OAuth tokens to control their calendar, so the *account* is identified.
   What we can honestly promise in the T&C is that **chat content sent to the model
   / retained for product data is decoupled from PII** — not that the app has no
   identity at all. Word the T&C precisely to avoid overclaiming.
3. **OAuth token security:** refresh tokens are highly sensitive — store encrypted,
   never log them, scope Calendar access as narrowly as Google allows.

---

*Status: decisions locked. Next step: MVP step 1 — the FastAPI backend skeleton.*
