"""POST /chat — the whole state machine: parse → clarify → propose → approve → sync → edit."""
import json
from datetime import date, datetime, timedelta

from fastapi import APIRouter, Depends, HTTPException

from . import db, gcal, llm, scheduler
from .auth import current_user
from .models import (DEFAULT_CATEGORIES, ChatIn, ChatReply, EditInfo, PlanItem,
                     Profile, Question, Recurrence)

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

    dropped = [t.title for t in result.tasks if is_dup(t.title)]
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
    # later request (the zombie-graveyard bug).
    llm_state = state if state.get("questions") else {}
    result = llm.call(profile.model_dump(), fixed, scheduled, llm_state,
                      body.message, now.isoformat(), body.tz)

    if result.intent == "edit" and result.edits:
        return _apply_edits(user, result, today, z, body.tz)

    # recurring anchors count as scheduled too — without them, "block my sleep"
    # twice creates two daily blocks
    anchor_rows = db.query("SELECT title FROM tasks WHERE user_id=? AND is_anchor=1",
                           (user["id"],))
    dropped = _drop_already_scheduled(
        result,
        [r["title"].strip().lower() for r in existing]
        + [ev["title"].strip().lower() for ev in fixed]
        + [r["title"].strip().lower() for r in anchor_rows])
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

    if result.tasks:
        recurring = [t for t in result.tasks if t.recurrence]
        flexible = [t for t in result.tasks if not t.recurrence]
        day_start = datetime(today.year, today.month, today.day, tzinfo=z)
        busy = [(datetime.fromisoformat(ev["start"]), datetime.fromisoformat(ev["end"])) for ev in fixed]
        busy += [(gcal.combine(today, a["start"], z), gcal.combine(today, a["end"], z))
                 for a in db.anchors_for_date(user["id"], today)]
        busy += [(datetime.fromisoformat(r["start_ts"]), datetime.fromisoformat(r["end_ts"]))
                 for r in existing]
        try:
            placed = scheduler.schedule(flexible, busy, profile, day_start)
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
            return ChatReply(
                type="clarify",
                text=f"{c.title} can't start at {c.hhmm} — that collides with something already scheduled.",
                questions=[conflict_q])
        except ValueError:
            # overflow (design 3c): quantify the squeeze, offer concrete fixes
            free_min = scheduler.free_minutes(busy, profile, day_start)
            need_min = sum(t.duration_minutes or 30 for t in flexible)
            task_dicts = [t.model_dump() for t in flexible]
            options = llm.fix_options(profile.model_dump(), task_dicts, free_min, need_min, body.tz)
            _save_state(user["id"], {"date": today.isoformat(), "tasks": task_dicts, "questions": []})
            return ChatReply(
                type="overflow",
                text=(f"That doesn't fit — {need_min / 60:.2g} hrs of new tasks, "
                      f"{free_min / 60:.2g} hrs free around your meetings. Pick a fix:"),
                options=options)

        plan = placed + [PlanItem(title=ev["title"], start=ev["start"], end=ev["end"], fixed=True)
                         for ev in fixed]
        for t in recurring:
            plan.append(PlanItem(title=t.title, category=t.category, location=t.location,
                                 start=gcal.combine(today, t.recurrence.start_time, z).isoformat(),
                                 end=gcal.combine(today, t.recurrence.end_time, z).isoformat(),
                                 recurrence=t.recurrence))
        plan.sort(key=lambda p: p.start)

        _save_state(user["id"], {"date": today.isoformat(),
                                 "proposal": [p.model_dump() for p in placed],
                                 "recurring": [t.model_dump() for t in recurring]})
        n = len(placed) + len(recurring)
        return ChatReply(type="proposal", plan=plan,
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

    count = 0
    for p in proposal:
        event_id = gcal.insert_event(user, p["title"], p["start"], p["end"], tz,
                                     category=p.get("category"), location=p.get("location"))
        db.execute(
            "INSERT INTO tasks (user_id, date, title, category, start_ts, end_ts, status, google_event_id, location)"
            " VALUES (?,?,?,?,?,?,'planned',?,?)",
            (user["id"], plan_date, p["title"], p.get("category") or "admin",
             p["start"], p["end"], event_id, p.get("location")))
        count += 1

    for t in recurring:
        rec = Recurrence.model_validate(t["recurrence"])
        create_recurring_anchor(user, t["title"], t.get("category") or "deep_work",
                                rec, tz, z, date.fromisoformat(plan_date),
                                location=t.get("location"))
        count += 1

    _clear_state(user["id"])
    return ChatReply(type="synced", text=f"Synced {count} event(s) to Google Calendar.")


# ── chat-driven edits of already-synced events ──────────────────────

def _apply_edits(user, result, today: date, z, tz: str) -> ChatReply:
    """Moves apply instantly (design 3a); deletes ask first (design 3b)."""
    cards, misses = [], []
    for edit in result.edits:
        rows = db.query("SELECT * FROM tasks WHERE user_id=? AND date=? AND is_anchor=0",
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
        target_day = today + timedelta(days=1) if edit.move_to_tomorrow else today
        if edit.new_start:
            start = gcal.combine(target_day, edit.new_start, z)
        elif edit.move_to_tomorrow:
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
