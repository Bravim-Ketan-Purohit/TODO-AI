"""POST /chat — the whole state machine: parse → clarify → propose → approve → sync → edit."""
import json
from datetime import date, datetime, timedelta

from fastapi import APIRouter, Depends, HTTPException

from . import db, gcal, llm, scheduler
from .auth import current_user
from .models import (DEFAULT_CATEGORIES, ChatIn, ChatReply, EditInfo, FixOption,
                     PlanItem, Profile, Question, Recurrence)

router = APIRouter(tags=["chat"])


# ── chat_state helpers ──────────────────────────────────────────────

def _load_state(uid: int, today_iso: str | None = None) -> dict:
    rows = db.query("SELECT state_json FROM chat_state WHERE user_id=?", (uid,))
    state = json.loads(rows[0]["state_json"]) if rows else {}
    # stale pending state from a previous day resurfaces old tasks — drop it
    if today_iso and state.get("date") and state["date"] != today_iso:
        return {}
    return state


def _drop_already_scheduled(result, existing_titles: list[str]) -> list[str]:
    """Server-side guard: the model sometimes resurfaces already-synced tasks as
    new ones (they're in its context). A duplicate then collides with its own
    calendar entry. Drop such tasks and their questions; return what was dropped
    so the reply can say so instead of silently shrinking."""
    def is_dup(title: str) -> bool:
        t = title.strip().lower()
        return any(t and e and (t in e or e in t) for e in existing_titles)

    dropped = list(dict.fromkeys(t.title for t in result.tasks if is_dup(t.title)))
    result.tasks = [t for t in result.tasks if not is_dup(t.title)]
    result.questions = [q for q in result.questions if not is_dup(q.task_title)]
    return dropped


def _save_state(uid: int, state: dict) -> None:
    db.execute(
        "INSERT INTO chat_state (user_id, state_json) VALUES (?, ?) "
        "ON CONFLICT(user_id) DO UPDATE SET state_json=excluded.state_json, updated_at=datetime('now')",
        (uid, json.dumps(state)))


def _clear_state(uid: int) -> None:
    db.execute("DELETE FROM chat_state WHERE user_id=?", (uid,))


def _first_on_or_after(start: date, days: list[str]) -> date:
    for i in range(7):
        d = start + timedelta(days=i)
        if db.WEEKDAYS[d.weekday()] in days:
            return d
    return start


def create_recurring_anchor(user, title: str, category: str, rec: Recurrence,
                            tz: str, z, start_date: date, location: str | None = None) -> None:
    """Create a permanent schedule block: recurring gcal event + anchor row.
    Used by chat approve AND the Settings 'add to schedule' endpoint."""
    first = _first_on_or_after(start_date, rec.days)
    start_dt = gcal.combine(first, rec.start_time, z)
    end_dt = gcal.combine(first, rec.end_time, z)
    if end_dt <= start_dt:  # overnight block (e.g. sleep 23:00–07:00)
        end_dt += timedelta(days=1)
    rrule = "RRULE:FREQ=WEEKLY;BYDAY=" + ",".join(rec.days)
    if rec.until:
        rrule += ";UNTIL=" + rec.until.replace("-", "") + "T235959Z"
    event_id = gcal.insert_event(user, title, start_dt.isoformat(), end_dt.isoformat(), tz,
                                 category=category, location=location, rrule=rrule)
    db.execute(
        "INSERT INTO tasks (user_id, date, title, category, start_ts, end_ts, status,"
        " google_event_id, is_anchor, recurrence_json, location)"
        " VALUES (?,?,?,?,?,?,'planned',?,1,?,?)",
        (user["id"], first.isoformat(), title, category,
         start_dt.isoformat(), end_dt.isoformat(), event_id,
         rec.model_dump_json(), location))


def _unknown_categories(tasks, profile: Profile) -> list[str]:
    known = set(DEFAULT_CATEGORIES) | {c.strip().lower().replace(" ", "_")
                                       for c in getattr(profile, "custom_categories", None) or []}
    return sorted({t.category for t in tasks} - known)


# ── the endpoint ────────────────────────────────────────────────────

@router.post("/chat", response_model=ChatReply)
def chat(body: ChatIn, user=Depends(current_user)) -> ChatReply:
    z = gcal.zone(body.tz)
    now = datetime.now(z)
    today = now.date()
    state = _load_state(user["id"], today.isoformat())

    if body.delete_decision:
        return _resolve_delete(user, state, body.delete_decision)
    if body.approve:
        return _approve(user, state, body.tz, z, today)
    if not body.message:
        raise HTTPException(400, "Send a message or approve=true")

    profile = Profile.model_validate(json.loads(user["profile_json"] or "{}"))
    fixed = gcal.external_events(user, today, body.tz)
    # today's already-synced app tasks are busy time too — for the LLM AND the scheduler
    existing = db.query(
        "SELECT title, start_ts, end_ts FROM tasks WHERE user_id=? AND date=? AND is_anchor=0"
        " AND status != 'missed'",
        (user["id"], today.isoformat()))
    scheduled = [{"title": r["title"], "start": r["start_ts"][11:16], "end": r["end_ts"][11:16]}
                 for r in existing]
    # A new topic starts a fresh thread: pending tasks only follow the
    # conversation while their clarifying questions are still open. Without
    # this, unapproved tasks from abandoned threads re-merge into every
    # later request (the zombie-graveyard bug). An UNAPPROVED proposal stays
    # live context though — "make it Sunday 10am" must adjust it, not vanish.
    llm_state = state if (state.get("questions") or state.get("proposal")
                          or state.get("recurring")) else {}
    # upcoming synced tasks (next 7 days) — so cross-day edits can name their target
    upcoming = [{"title": r["title"], "date": r["date"], "start": r["start_ts"][11:16]}
                for r in db.query(
                    "SELECT title, date, start_ts FROM tasks WHERE user_id=? AND date>?"
                    " AND date<=? AND is_anchor=0 AND status != 'missed' ORDER BY date, start_ts",
                    (user["id"], today.isoformat(), (today + timedelta(days=7)).isoformat()))]
    # 14-day history aggregates — lets the model answer "how many hours of
    # deep work this week?" / "when did I last work out?" from real data
    stats: dict[str, dict] = {}
    for r in db.query(
            "SELECT date, category, status, start_ts, end_ts FROM tasks"
            " WHERE user_id=? AND date>=? AND date<=? AND is_anchor=0",
            (user["id"], (today - timedelta(days=14)).isoformat(), today.isoformat())):
        s = stats.setdefault(r["category"], {
            "category": r["category"], "completed_minutes": 0,
            "completed_count": 0, "planned_count": 0, "last_completed": None})
        s["planned_count"] += 1
        if r["status"] == "completed":
            mins = int((datetime.fromisoformat(r["end_ts"])
                        - datetime.fromisoformat(r["start_ts"])).total_seconds() // 60)
            s["completed_minutes"] += mins
            s["completed_count"] += 1
            if not s["last_completed"] or r["date"] > s["last_completed"]:
                s["last_completed"] = r["date"]

    result = llm.call(profile.model_dump(), fixed, scheduled, upcoming,
                      list(stats.values()), llm_state,
                      body.message, now.isoformat(), body.tz)

    if result.intent == "edit" and result.edits:
        return _apply_edits(user, result, today, z, body.tz)

    # models sometimes multiply one request into identical copies ("Go to a
    # movie" ×7) — collapse exact repeats (same title, same day) to one
    seen_keys = set()
    unique_tasks = []
    for t in result.tasks:
        key = (t.title.strip().lower(), t.date)
        if key not in seen_keys:
            seen_keys.add(key)
            unique_tasks.append(t)
    result.tasks = unique_tasks

    # recurring anchors count as scheduled too — without them, "block my sleep"
    # twice creates two daily blocks
    anchor_rows = db.query("SELECT title FROM tasks WHERE user_id=? AND is_anchor=1",
                           (user["id"],))
    backlog_rows = db.query("SELECT title FROM backlog WHERE user_id=?", (user["id"],))
    dropped = _drop_already_scheduled(
        result,
        [r["title"].strip().lower() for r in existing]
        + [ev["title"].strip().lower() for ev in fixed]
        + [r["title"].strip().lower() for r in anchor_rows]
        + [u["title"].strip().lower() for u in upcoming]
        + [r["title"].strip().lower() for r in backlog_rows])
    if dropped:
        note = f"(Already on your calendar, skipped: {', '.join(dropped)}.)"
        result.reply = f"{result.reply} {note}".strip() if result.reply else note

    if result.questions:  # never place anything while a time is unknown
        _save_state(user["id"], {"date": today.isoformat(),
                                 "tasks": [t.model_dump() for t in result.tasks],
                                 "questions": [q.model_dump() for q in result.questions]})
        return ChatReply(type="clarify",
                         text=result.reply or "A couple of times before I place anything:",
                         questions=result.questions)

    # someday tasks park in the backlog — never guessed onto a date. Ones with
    # open questions (unknown duration) stay in the thread until answered.
    questioned = {q.task_title.strip().lower() for q in result.questions}
    parked = [t for t in result.tasks if t.someday and not t.recurrence
              and t.title.strip().lower() not in questioned]
    if parked:
        parked_titles = {t.title for t in parked}
        result.tasks = [t for t in result.tasks if t.title not in parked_titles]
        for t in parked:
            db.execute(
                "INSERT INTO backlog (user_id, title, category, duration_minutes)"
                " VALUES (?,?,?,?)",
                (user["id"], t.title, t.category, t.duration_minutes or 30))
        note = "Parked in your backlog: " + ", ".join(t.title for t in parked) + \
               ". I'll offer them when a day has room."
        result.reply = f"{result.reply} {note}".strip() if result.reply else note

    if result.tasks:
        recurring = [t for t in result.tasks if t.recurrence]
        flexible = [t for t in result.tasks if not t.recurrence]
        # multi-day (5c): group by each task's target date; None → today
        by_day: dict[date, list] = {}
        for t in flexible:
            d = date.fromisoformat(t.date) if t.date else today
            by_day.setdefault(max(d, today), []).append(t)

        placed, shown_fixed = [], []
        for d in sorted(by_day):
            day_fixed = fixed if d == today else gcal.external_events(user, d, body.tz)
            day_rows = existing if d == today else db.query(
                "SELECT title, start_ts, end_ts FROM tasks WHERE user_id=? AND date=?"
                " AND is_anchor=0 AND status != 'missed'", (user["id"], d.isoformat()))
            busy = [(datetime.fromisoformat(ev["start"]), datetime.fromisoformat(ev["end"]))
                    for ev in day_fixed]
            busy += [(gcal.combine(d, a["start"], z), gcal.combine(d, a["end"], z))
                     for a in db.anchors_for_date(user["id"], d)]
            busy += [(datetime.fromisoformat(r["start_ts"]), datetime.fromisoformat(r["end_ts"]))
                     for r in day_rows]
            day_start = datetime(d.year, d.month, d.day, tzinfo=z)
            try:
                placed += scheduler.schedule(by_day[d], busy, profile, day_start)
            except scheduler.Conflict as c:
                slots = scheduler.suggest_slots(c.duration_minutes, busy, profile, day_start)
                conflict_q = Question(
                    task_title=c.title,
                    question=f"Pick another time for {c.title} ({c.duration_minutes} min):",
                    suggestions=slots)
                # the open question must be saved, or the user's answer arrives
                # into an empty thread and loses all context
                _save_state(user["id"], {"date": today.isoformat(),
                                         "tasks": [t.model_dump() for t in result.tasks],
                                         "questions": [conflict_q.model_dump()]})
                day_note = "" if d == today else f" on {d.strftime('%a %b %d')}"
                return ChatReply(
                    type="clarify",
                    text=f"{c.title} can't start at {c.hhmm}{day_note} — "
                         "that collides with something already scheduled.",
                    questions=[conflict_q])
            except ValueError:
                # overflow (design 3c): quantify the squeeze, offer concrete fixes
                free_min = scheduler.free_minutes(busy, profile, day_start)
                need_min = sum(t.duration_minutes or 30 for t in by_day[d])
                task_dicts = [t.model_dump() for t in flexible]
                options = llm.fix_options(profile.model_dump(), task_dicts, free_min, need_min, body.tz)
                _save_state(user["id"], {"date": today.isoformat(), "tasks": task_dicts, "questions": []})
                day_note = "Today" if d == today else d.strftime("%a %b %d")
                return ChatReply(
                    type="overflow",
                    text=(f"{day_note} doesn't fit — {need_min / 60:.2g} hrs of new tasks, "
                          f"{free_min / 60:.2g} hrs free around your meetings. Pick a fix:"),
                    options=options)
            shown_fixed += [PlanItem(title=ev["title"], start=ev["start"], end=ev["end"], fixed=True)
                            for ev in day_fixed]
        if not by_day:  # recurring-only proposal still shows today's context
            shown_fixed = [PlanItem(title=ev["title"], start=ev["start"], end=ev["end"], fixed=True)
                           for ev in fixed]

        plan = placed + shown_fixed
        for t in recurring:
            plan.append(PlanItem(title=t.title, category=t.category, location=t.location,
                                 start=gcal.combine(today, t.recurrence.start_time, z).isoformat(),
                                 end=gcal.combine(today, t.recurrence.end_time, z).isoformat(),
                                 recurrence=t.recurrence))
        plan.sort(key=lambda p: p.start)

        _save_state(user["id"], {"date": today.isoformat(),
                                 "proposal": [p.model_dump() for p in placed],
                                 "recurring": [t.model_dump() for t in recurring],
                                 "deadlines": [d.model_dump() for d in result.deadlines]})
        # fragmentation check: 3+ short scattered tasks → offer to batch them
        def _mins(p):
            return int((datetime.fromisoformat(p.end)
                        - datetime.fromisoformat(p.start)).total_seconds() // 60)
        smalls = [p for p in placed if _mins(p) <= 30]
        options = []
        if len(smalls) >= 3:
            options = [FixOption(
                title=f"Batch the {len(smalls)} small tasks into one block",
                subtitle="Fewer context switches")]

        n = len(placed) + len(recurring)
        return ChatReply(type="proposal", plan=plan, options=options,
                         suggested_categories=_unknown_categories(result.tasks, profile),
                         text=result.reply
                         or f"Placed {n} task(s) around {len(fixed)} fixed event(s) — no overlaps. "
                            "Approve to write them to your calendar.")

    return ChatReply(type="info", text=result.reply or "Okay.")


# ── approve → write to Google Calendar ──────────────────────────────

def _approve(user, state: dict, tz: str, z, today: date) -> ChatReply:
    proposal = state.get("proposal") or []
    recurring = state.get("recurring") or []
    if not proposal and not recurring:
        raise HTTPException(400, "Nothing pending to approve")
    plan_date = state.get("date") or today.isoformat()

    # living deadlines: create the goal rows first so blocks can link to them
    deadline_ids: dict[str, int] = {}
    for d in state.get("deadlines") or []:
        deadline_ids[d["title"]] = db.execute(
            "INSERT INTO deadlines (user_id, title, due_date, target_minutes, category)"
            " VALUES (?,?,?,?,?)",
            (user["id"], d["title"], d["due_date"], d["total_minutes"],
             d.get("category") or "deep_work"))

    count = 0
    for p in proposal:
        event_id = gcal.insert_event(user, p["title"], p["start"], p["end"], tz,
                                     category=p.get("category"), location=p.get("location"))
        db.execute(
            "INSERT INTO tasks (user_id, date, title, category, start_ts, end_ts, status,"
            " google_event_id, location, deadline_id)"
            " VALUES (?,?,?,?,?,?,'planned',?,?,?)",
            # each item's own day, not the proposal's day — multi-day plans (5c)
            (user["id"], p["start"][:10], p["title"], p.get("category") or "admin",
             p["start"], p["end"], event_id, p.get("location"),
             deadline_ids.get(p.get("deadline"))))
        count += 1

    for t in recurring:
        rec = Recurrence.model_validate(t["recurrence"])
        create_recurring_anchor(user, t["title"], t.get("category") or "deep_work",
                                rec, tz, z, date.fromisoformat(plan_date),
                                location=t.get("location"))
        count += 1

    _clear_state(user["id"])
    text = f"Synced {count} event(s) to Google Calendar."
    for d in state.get("deadlines") or []:
        text += (f" Tracking: {d['title']} — {d['total_minutes'] / 60:.2g}h "
                 f"by {d['due_date']}. If blocks slip, I'll offer to re-spread.")
    return ChatReply(type="synced", text=text)


# ── chat-driven edits of already-synced events ──────────────────────

def _apply_edits(user, result, today: date, z, tz: str) -> ChatReply:
    """Moves apply instantly (design 3a); deletes ask first (design 3b)."""
    cards, misses = [], []
    for edit in result.edits:
        # today AND upcoming days — week plans (5c) are editable too
        rows = db.query("SELECT * FROM tasks WHERE user_id=? AND date>=? AND is_anchor=0"
                        " ORDER BY date, start_ts",
                        (user["id"], today.isoformat()))
        needle = edit.match_title.lower()
        match = next((r for r in rows
                      if needle in r["title"].lower() or r["title"].lower() in needle), None)
        if not match:
            misses.append(edit.match_title)
            continue

        if edit.cancel:
            # destructive → quick confirm, nothing touched yet
            state = _load_state(user["id"])
            state["pending_delete"] = {"task_id": match["id"]}
            _save_state(user["id"], state)
            return ChatReply(
                type="confirm_delete",
                text="Delete this from your calendar?",
                plan=[PlanItem(title=match["title"], category=match["category"],
                               start=match["start_ts"], end=match["end_ts"])])

        old_start = datetime.fromisoformat(match["start_ts"])
        old_end = datetime.fromisoformat(match["end_ts"])
        duration = (timedelta(minutes=edit.new_duration_minutes)
                    if edit.new_duration_minutes else old_end - old_start)
        base_day = date.fromisoformat(match["date"])
        if edit.move_to_date:
            target_day = date.fromisoformat(edit.move_to_date)
        elif edit.move_to_tomorrow:
            target_day = base_day + timedelta(days=1)
        else:
            target_day = base_day
        if edit.new_start:
            start = gcal.combine(target_day, edit.new_start, z)
        elif target_day != base_day:
            start = gcal.combine(target_day, old_start.strftime("%H:%M"), z)
        else:
            start = old_start
        end = start + duration
        if match["google_event_id"]:
            gcal.patch_event(user, match["google_event_id"], start.isoformat(), end.isoformat(), tz)
        db.execute("UPDATE tasks SET date=?, start_ts=?, end_ts=?, status='rescheduled' WHERE id=?",
                   (target_day.isoformat(), start.isoformat(), end.isoformat(), match["id"]))
        cards.append(EditInfo(title=match["title"], category=match["category"],
                              old_start=match["start_ts"], old_end=match["end_ts"],
                              new_start=start.isoformat(), new_end=end.isoformat()))

    if cards:
        first = cards[0]
        text = result.reply or f"Moved — {first.new_start[11:16]} is clear."
        if misses:
            text += " Couldn't find: " + ", ".join(misses)
        return ChatReply(type="edited", text=text, edits=cards)
    return ChatReply(type="info", text="I couldn't find that on today's plan.")


def _resolve_delete(user, state: dict, decision: str) -> ChatReply:
    pending = state.pop("pending_delete", None)
    _save_state(user["id"], state)
    if not pending:
        raise HTTPException(400, "Nothing pending to delete")
    if decision == "keep":
        return ChatReply(type="info", text="Kept it.")
    rows = db.query("SELECT * FROM tasks WHERE id=? AND user_id=?",
                    (pending["task_id"], user["id"]))
    if not rows:
        return ChatReply(type="info", text="It's already gone.")
    match = rows[0]
    if match["google_event_id"]:
        gcal.delete_event(user, match["google_event_id"])
    db.execute("DELETE FROM tasks WHERE id=?", (match["id"],))
    return ChatReply(
        type="edited",
        text=f"Deleted {match['title']} from your calendar.",
        edits=[EditInfo(title=match["title"], category=match["category"],
                        old_start=match["start_ts"], old_end=match["end_ts"], deleted=True)])
