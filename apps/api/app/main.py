"""TODO_AI API — app wiring + the small read/write routes."""
import json
from datetime import date, datetime, timedelta

from fastapi import Depends, FastAPI, HTTPException
from pydantic import BaseModel

from . import auth, chat, db, gcal
from .auth import current_user
from .models import AnchorIn, Profile, RolloverIn, StatusIn

db.init_db()

app = FastAPI(title="TODO_AI API")
app.include_router(auth.router)
app.include_router(chat.router)


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/me")
def me(user=Depends(current_user)) -> dict:
    anchors = db.query("SELECT recurrence_json FROM tasks WHERE user_id=? AND is_anchor=1",
                       (user["id"],))
    untils = [json.loads(r["recurrence_json"] or "{}").get("until") for r in anchors]
    untils = [u for u in untils if u]
    return {"email": user["email"],
            "profile": json.loads(user["profile_json"] or "{}"),
            "anchors": {"classes": len(anchors), "until": max(untils) if untils else None}}


@app.put("/me/profile")
def update_profile(profile: Profile, user=Depends(current_user)) -> dict:
    db.execute("UPDATE users SET profile_json=? WHERE id=?", (profile.model_dump_json(), user["id"]))
    return {"ok": True}


def _day_payload(user, day: date, tz: str) -> dict:
    z = gcal.zone(tz)
    tasks = db.query("SELECT * FROM tasks WHERE user_id=? AND date=? AND is_anchor=0 ORDER BY start_ts",
                     (user["id"], day.isoformat()))
    anchors = db.anchors_for_date(user["id"], day)
    for a in anchors:  # HH:MM → full ISO for this date, same shape as tasks
        a["start"] = gcal.combine(day, a["start"], z).isoformat()
        a["end"] = gcal.combine(day, a["end"], z).isoformat()
    return {"date": day.isoformat(),
            "tasks": [dict(r) for r in tasks],
            "anchors": anchors,
            "fixed": gcal.external_events(user, day, tz)}


@app.get("/today")
def today_view(tz: str = "UTC", user=Depends(current_user)) -> dict:
    return _day_payload(user, datetime.now(gcal.zone(tz)).date(), tz)


@app.get("/days/{day}")
def day_view(day: date, tz: str = "UTC", user=Depends(current_user)) -> dict:
    return _day_payload(user, day, tz)


@app.get("/history")
def history(days: int = 30, tz: str = "UTC", user=Depends(current_user)) -> list[dict]:
    z = gcal.zone(tz)
    now = datetime.now(z)
    today = now.date()
    since = (today - timedelta(days=days)).isoformat()
    week_since = (today - timedelta(days=6)).isoformat()
    noted = {r["date"] for r in db.query(
        "SELECT date FROM notes WHERE user_id=?", (user["id"],))}
    rows = db.query(
        "SELECT date, status, category, start_ts, end_ts FROM tasks"
        " WHERE user_id=? AND date>=? AND date<=? AND is_anchor=0 ORDER BY date DESC, start_ts",
        (user["id"], since, today.isoformat()))
    out: dict[str, dict] = {}
    for r in rows:
        d = out.setdefault(r["date"], {"date": r["date"], "done": 0, "total": 0,
                                       "categories": [], "dots": [],
                                       "has_note": r["date"] in noted})
        d["total"] += 1
        d["done"] += r["status"] == "completed"
        if r["category"] not in d["categories"]:
            d["categories"].append(r["category"])
        # dot-matrix strip (design 6c): per-task dots for the last 7 days
        if r["date"] >= week_since:
            current = (r["date"] == today.isoformat()
                       and datetime.fromisoformat(r["start_ts"]) <= now
                       < datetime.fromisoformat(r["end_ts"])
                       and r["status"] not in ("completed", "missed"))
            d["dots"].append({"category": r["category"],
                              "done": r["status"] == "completed",
                              "current": current})
    return list(out.values())


@app.get("/anchors")
def list_anchors(user=Depends(current_user)) -> list[dict]:
    """The user's schedule: permanent recurring blocks (settings screen)."""
    out = []
    for r in db.query("SELECT * FROM tasks WHERE user_id=? AND is_anchor=1 ORDER BY id",
                      (user["id"],)):
        rec = json.loads(r["recurrence_json"] or "{}")
        out.append({"id": r["id"], "title": r["title"], "category": r["category"],
                    "days": rec.get("days", []), "start_time": rec.get("start_time"),
                    "end_time": rec.get("end_time"), "until": rec.get("until")})
    return out


@app.post("/anchors")
def add_anchor(body: AnchorIn, tz: str = "UTC", user=Depends(current_user)) -> dict:
    """Add a schedule block: permanently reserves that time on the calendar."""
    z = gcal.zone(tz)
    today = datetime.now(z).date()
    from .models import Recurrence
    rec = Recurrence(days=body.days, start_time=body.start_time, end_time=body.end_time)
    chat.create_recurring_anchor(user, body.title, body.category, rec, tz, z, today)
    return {"ok": True}


@app.get("/nudges")
def nudges(tz: str = "UTC", user=Depends(current_user)) -> dict:
    """Learning loop (design 3f): if morning workouts keep missing but evening
    ones stick, suggest moving the default. ponytail: one nudge kind for now."""
    today = datetime.now(gcal.zone(tz)).date()
    since = (today - timedelta(days=7)).isoformat()
    rows = db.query(
        "SELECT date, status, start_ts FROM tasks"
        " WHERE user_id=? AND category='health' AND date>=? AND date<? AND is_anchor=0",
        (user["id"], since, today.isoformat()))
    completed = [r for r in rows if r["status"] == "completed"]
    not_done = [r for r in rows if r["status"] in ("missed", "planned")]
    morning_missed = [r for r in not_done if int(r["start_ts"][11:13]) < 12]
    evening_done = [r for r in completed if int(r["start_ts"][11:13]) >= 17]
    if len(rows) < 3 or len(morning_missed) < 3 or not evening_done:
        return {"nudge": None}

    usual = min(r["start_ts"][11:16] for r in morning_missed)
    worked = evening_done[0]
    worked_time = worked["start_ts"][11:16]
    week = []
    for i in range(7):
        d = today - timedelta(days=7 - i)
        day_rows = [r for r in rows if r["date"] == d.isoformat()]
        status = "none"
        if any(r["status"] == "completed" for r in day_rows):
            status = "done"
        elif day_rows:
            status = "missed"
        week.append({"day": db.WEEKDAYS[d.weekday()], "status": status})
    worked_day = datetime.fromisoformat(worked["start_ts"]).strftime("%A")
    return {"nudge": {
        "kind": "workout_time",
        "text": f"{usual} workouts landed {len(completed)} of {len(rows)} this week. "
                "Evening ones stick.",
        "grid_label": "WORKOUTS · THIS WEEK",
        "week": week,
        "note": f"{worked_day}'s was at {worked_time}",
        "question": f"Default workouts to {worked_time}?",
        "options": [f"Yes, {worked_time}", f"Keep {usual}", "Stop asking"],
        "suggested_workout": "evening",
    }}


@app.get("/recap")
def recap(tz: str = "UTC", user=Depends(current_user)) -> dict:
    """Evening recap (design 4e): today's count + still-open tasks."""
    today = datetime.now(gcal.zone(tz)).date().isoformat()
    rows = db.query(
        "SELECT id, title, category, start_ts, status FROM tasks"
        " WHERE user_id=? AND date=? AND is_anchor=0 ORDER BY start_ts",
        (user["id"], today))
    open_tasks = [r for r in rows if r["status"] in ("planned", "rescheduled")]
    return {"date": today,
            "done": sum(r["status"] == "completed" for r in rows),
            "total": len(rows),
            "open": [{"id": r["id"], "title": r["title"], "category": r["category"],
                      "start": r["start_ts"]} for r in open_tasks]}


@app.post("/tasks/{task_id}/status")
def set_status(task_id: int, body: StatusIn, user=Depends(current_user)) -> dict:
    if not db.query("SELECT id FROM tasks WHERE id=? AND user_id=?", (task_id, user["id"])):
        raise HTTPException(404, "Task not found")
    completed_at = datetime.now().astimezone().isoformat() if body.status == "completed" else None
    db.execute("UPDATE tasks SET status=?, completed_at=? WHERE id=?",
               (body.status, completed_at, task_id))
    return {"ok": True}


# ── morning rollover (design 5a) ────────────────────────────────────

def _today_busy(user, day: date, tz: str, z) -> list:
    busy = [(datetime.fromisoformat(ev["start"]), datetime.fromisoformat(ev["end"]))
            for ev in gcal.external_events(user, day, tz)]
    busy += [(gcal.combine(day, a["start"], z), gcal.combine(day, a["end"], z))
             for a in db.anchors_for_date(user["id"], day)]
    busy += [(datetime.fromisoformat(r["start_ts"]), datetime.fromisoformat(r["end_ts"]))
             for r in db.query(
                 "SELECT start_ts, end_ts FROM tasks WHERE user_id=? AND date=?"
                 " AND is_anchor=0 AND status != 'missed'", (user["id"], day.isoformat()))]
    return busy


@app.get("/rollover")
def rollover(tz: str = "UTC", user=Depends(current_user)) -> dict:
    """Yesterday's open tasks + where each would fit today, plus backlog items
    that fit today's free time (the backlog drain)."""
    z = gcal.zone(tz)
    today = datetime.now(z).date()
    yesterday = (today - timedelta(days=1)).isoformat()
    rows = db.query(
        "SELECT * FROM tasks WHERE user_id=? AND date=? AND is_anchor=0 ORDER BY start_ts",
        (user["id"], yesterday))
    open_rows = [r for r in rows if r["status"] in ("planned", "rescheduled", "missed")]

    from .scheduler import suggest_slots
    profile = Profile.model_validate(json.loads(user["profile_json"] or "{}"))
    day_start = datetime(today.year, today.month, today.day, tzinfo=z)
    busy = _today_busy(user, today, tz, z)

    out = []
    for r in open_rows:
        start = datetime.fromisoformat(r["start_ts"])
        end = datetime.fromisoformat(r["end_ts"])
        dur = max(15, int((end - start).total_seconds() // 60))
        slots = suggest_slots(dur, busy, profile, day_start, count=1)
        out.append({"id": r["id"], "title": r["title"], "category": r["category"],
                    "duration_minutes": dur, "missed_time": r["start_ts"][11:16],
                    "fits_today": slots[0] if slots else None})

    # anti-rot: parked 10+ days → time to decide, not to keep drifting
    stale = []
    for b in db.query("SELECT * FROM backlog WHERE user_id=? ORDER BY id", (user["id"],)):
        age = (today - date.fromisoformat(b["created_at"][:10])).days
        if age >= 10:
            stale.append({"id": b["id"], "title": b["title"], "category": b["category"],
                          "duration_minutes": b["duration_minutes"], "days_parked": age})
        if len(stale) >= 2:
            break
    stale_ids = {s["id"] for s in stale}

    # backlog drain: oldest parked items that genuinely fit today's gaps
    backlog = []
    for b in db.query("SELECT * FROM backlog WHERE user_id=? ORDER BY id LIMIT 10",
                      (user["id"],)):
        if b["id"] in stale_ids:  # stale items get their own decide-now card
            continue
        slots = suggest_slots(b["duration_minutes"], busy, profile, day_start, count=1)
        if slots:
            fit = gcal.combine(today, slots[0], z)
            busy.append((fit, fit + timedelta(minutes=b["duration_minutes"])))
            backlog.append({"id": b["id"], "title": b["title"], "category": b["category"],
                            "duration_minutes": b["duration_minutes"], "fits_at": slots[0]})
        if len(backlog) >= 3:  # a gentle offer, not a flood
            break

    return {"yesterday": yesterday,
            "done": sum(r["status"] == "completed" for r in rows),
            "total": len(rows), "open": out, "backlog": backlog, "stale": stale,
            "deadlines": _deadline_alerts(user, today, tz, z, profile)}


def _dur_min(r) -> int:
    return max(15, int((datetime.fromisoformat(r["end_ts"])
                        - datetime.fromisoformat(r["start_ts"])).total_seconds() // 60))


def _deadline_alerts(user, today: date, tz: str, z, profile: Profile) -> list[dict]:
    """Living deadlines: hours-remaining vs days-remaining. When behind (blocks
    missed or dropped), propose concrete recovery blocks before the due date."""
    from .scheduler import suggest_slots
    alerts = []
    for d in db.query("SELECT * FROM deadlines WHERE user_id=? AND due_date>=?",
                      (user["id"], today.isoformat())):
        linked = db.query("SELECT * FROM tasks WHERE deadline_id=? AND user_id=?",
                          (d["id"], user["id"]))
        done = sum(_dur_min(r) for r in linked if r["status"] == "completed")
        booked = sum(_dur_min(r) for r in linked
                     if r["status"] in ("planned", "rescheduled")
                     and today.isoformat() <= r["date"] <= d["due_date"])
        behind = d["target_minutes"] - done - booked
        if behind < 15:
            continue  # on track — stay quiet
        block_title = linked[0]["title"] if linked else d["title"]
        recovery, remaining = [], behind
        day = today
        while remaining >= 15 and day.isoformat() <= d["due_date"]:
            day_start = datetime(day.year, day.month, day.day, tzinfo=z)
            busy = _today_busy(user, day, tz, z)
            if day == today:
                busy.append((day_start, datetime.now(z)))  # nothing in the past
            chunk = min(90, remaining)
            slots = suggest_slots(chunk, busy, profile, day_start, count=1)
            if slots:
                start = gcal.combine(day, slots[0], z)
                recovery.append({"start": start.isoformat(), "minutes": chunk,
                                 "title": block_title})
                remaining -= chunk
            else:
                day += timedelta(days=1)
                continue
            day += timedelta(days=1)
        alerts.append({"id": d["id"], "title": d["title"], "due_date": d["due_date"],
                       "category": d["category"], "target_minutes": d["target_minutes"],
                       "done_minutes": done, "booked_minutes": booked,
                       "behind_minutes": behind, "recovery": recovery,
                       "recoverable": behind - remaining})
    return alerts


class RespreadIn(BaseModel):
    blocks: list[dict]  # [{start ISO, minutes, title}]


@app.post("/deadlines/{deadline_id}/respread")
def respread(deadline_id: int, body: RespreadIn, tz: str = "UTC",
             user=Depends(current_user)) -> dict:
    rows = db.query("SELECT * FROM deadlines WHERE id=? AND user_id=?",
                    (deadline_id, user["id"]))
    if not rows:
        raise HTTPException(404, "Unknown deadline")
    d = rows[0]
    created = 0
    for b in body.blocks:
        start = datetime.fromisoformat(b["start"])
        end = start + timedelta(minutes=int(b["minutes"]))
        title = b.get("title") or d["title"]
        event_id = gcal.insert_event(user, title, start.isoformat(), end.isoformat(),
                                     tz, category=d["category"])
        db.execute(
            "INSERT INTO tasks (user_id, date, title, category, start_ts, end_ts, status,"
            " google_event_id, deadline_id) VALUES (?,?,?,?,?,?,'planned',?,?)",
            (user["id"], start.date().isoformat(), title, d["category"],
             start.isoformat(), end.isoformat(), event_id, d["id"]))
        created += 1
    return {"created": created}


@app.post("/rollover")
def apply_rollover(body: RolloverIn, tz: str = "UTC", user=Depends(current_user)) -> dict:
    """Carry chosen tasks into today's free slots; mark the rest missed."""
    z = gcal.zone(tz)
    today = datetime.now(z).date()
    from .scheduler import suggest_slots
    profile = Profile.model_validate(json.loads(user["profile_json"] or "{}"))
    day_start = datetime(today.year, today.month, today.day, tzinfo=z)
    busy = _today_busy(user, today, tz, z)
    carried = []
    for task_id in body.carry:
        rows = db.query("SELECT * FROM tasks WHERE id=? AND user_id=?", (task_id, user["id"]))
        if not rows:
            continue
        r = rows[0]
        start = datetime.fromisoformat(r["start_ts"])
        end = datetime.fromisoformat(r["end_ts"])
        dur = max(15, int((end - start).total_seconds() // 60))
        slots = suggest_slots(dur, busy, profile, day_start, count=1)
        if not slots:
            continue
        new_start = gcal.combine(today, slots[0], z)
        new_end = new_start + timedelta(minutes=dur)
        event_id = gcal.insert_event(user, r["title"], new_start.isoformat(),
                                     new_end.isoformat(), tz, category=r["category"])
        db.execute(
            "INSERT INTO tasks (user_id, date, title, category, start_ts, end_ts, status,"
            " google_event_id) VALUES (?,?,?,?,?,?,'planned',?)",
            (user["id"], today.isoformat(), r["title"], r["category"],
             new_start.isoformat(), new_end.isoformat(), event_id))
        busy.append((new_start, new_end))
        db.execute("UPDATE tasks SET status='missed' WHERE id=? AND status != 'completed'",
                   (task_id,))
        carried.append({"title": r["title"], "start": slots[0]})
    for task_id in body.drop:
        db.execute("UPDATE tasks SET status='missed' WHERE id=? AND user_id=?"
                   " AND status != 'completed'", (task_id, user["id"]))
    return {"carried": carried, "dropped": len(body.drop)}


# ── backlog (engine: park now, drain when a day has room) ───────────

@app.get("/backlog")
def list_backlog(user=Depends(current_user)) -> list[dict]:
    return [dict(r) for r in db.query(
        "SELECT id, title, category, duration_minutes, created_at FROM backlog"
        " WHERE user_id=? ORDER BY id", (user["id"],))]


class ScheduleBacklogIn(BaseModel):
    start: str | None = None  # ISO — user-picked date+time; None → auto


@app.post("/backlog/{item_id}/schedule")
def schedule_backlog(item_id: int, body: ScheduleBacklogIn | None = None,
                     tz: str = "UTC", user=Depends(current_user)) -> dict:
    """Sync one parked item: auto → first free slot in the next 7 days;
    manual → the user's picked time, refused if it collides."""
    rows = db.query("SELECT * FROM backlog WHERE id=? AND user_id=?", (item_id, user["id"]))
    if not rows:
        raise HTTPException(404, "Not in the backlog")
    b = rows[0]
    z = gcal.zone(tz)
    now = datetime.now(z)
    today = now.date()
    dur = timedelta(minutes=b["duration_minutes"])

    if body and body.start:
        start = datetime.fromisoformat(body.start).astimezone(z)
        if start < now:
            raise HTTPException(409, "That time is in the past")
        end = start + dur
        for s, e in _today_busy(user, start.date(), tz, z):
            if start < e and s < end:
                raise HTTPException(409, "That time collides with something "
                                         "already on your calendar")
    else:
        from .scheduler import suggest_slots
        profile = Profile.model_validate(json.loads(user["profile_json"] or "{}"))
        start = None
        for offset in range(7):
            day = today + timedelta(days=offset)
            day_start = datetime(day.year, day.month, day.day, tzinfo=z)
            busy = _today_busy(user, day, tz, z)
            if day == today:
                busy.append((day_start, now))  # not in the past
            slots = suggest_slots(b["duration_minutes"], busy, profile, day_start, count=1)
            if slots:
                start = gcal.combine(day, slots[0], z)
                break
        if start is None:
            raise HTTPException(409, "No room in the next 7 days — it stays parked")
        end = start + dur

    event_id = gcal.insert_event(user, b["title"], start.isoformat(), end.isoformat(),
                                 tz, category=b["category"])
    db.execute(
        "INSERT INTO tasks (user_id, date, title, category, start_ts, end_ts, status,"
        " google_event_id) VALUES (?,?,?,?,?,?,'planned',?)",
        (user["id"], start.date().isoformat(), b["title"], b["category"],
         start.isoformat(), end.isoformat(), event_id))
    db.execute("DELETE FROM backlog WHERE id=?", (b["id"],))
    return {"title": b["title"], "start": start.isoformat()}


@app.delete("/backlog/{item_id}")
def drop_backlog(item_id: int, user=Depends(current_user)) -> dict:
    db.execute("DELETE FROM backlog WHERE id=? AND user_id=?", (item_id, user["id"]))
    return {"ok": True}


# ── micro-gap filler: the 25 minutes before your next thing ─────────

@app.get("/gapfill")
def gapfill(tz: str = "UTC", user=Depends(current_user)) -> dict:
    """If a modest free gap sits between now and the next scheduled thing,
    offer one backlog item that genuinely fits it."""
    z = gcal.zone(tz)
    now = datetime.now(z)
    today = now.date()
    upcoming: list[tuple[datetime, str]] = []
    for ev in gcal.external_events(user, today, tz):
        upcoming.append((datetime.fromisoformat(ev["start"]), ev["title"]))
    for a in db.anchors_for_date(user["id"], today):
        upcoming.append((gcal.combine(today, a["start"], z), a["title"]))
    for r in db.query(
            "SELECT title, start_ts FROM tasks WHERE user_id=? AND date=? AND is_anchor=0"
            " AND status IN ('planned','rescheduled')", (user["id"], today.isoformat())):
        upcoming.append((datetime.fromisoformat(r["start_ts"]), r["title"]))
    future = sorted((s, t) for s, t in upcoming if s > now)
    if not future:
        return {"gap": None}
    next_start, next_title = future[0]
    gap_min = int((next_start - now).total_seconds() // 60)
    if not 20 <= gap_min <= 120:  # too tight to bother / big enough for real planning
        return {"gap": None}
    candidates = [b for b in db.query(
        "SELECT * FROM backlog WHERE user_id=? ORDER BY id", (user["id"],))
        if b["duration_minutes"] <= gap_min - 5]
    if not candidates:
        return {"gap": None}
    b = candidates[0]
    start_at = now + timedelta(minutes=(5 - now.minute % 5) % 5 or 5)
    return {"gap": {"minutes": gap_min, "until_title": next_title,
                    "until_time": next_start.strftime("%H:%M"),
                    "start": start_at.replace(second=0, microsecond=0).isoformat(),
                    "item": {"id": b["id"], "title": b["title"], "category": b["category"],
                             "duration_minutes": b["duration_minutes"]}}}


# ── morning briefing: a notification worth opening ──────────────────

@app.get("/briefing")
def briefing(tz: str = "UTC", user=Depends(current_user)) -> dict:
    """Composed the evening before (on app-background / bg refresh) for the
    next 7:15 notification: tomorrow's shape, today's loose ends, backlog."""
    z = gcal.zone(tz)
    today = datetime.now(z).date()
    tomorrow = today + timedelta(days=1)
    fixed = gcal.external_events(user, tomorrow, tz)
    parts = []
    if fixed:
        first = min(datetime.fromisoformat(ev["start"]) for ev in fixed)
        parts.append(f"{len(fixed)} meeting{'s' if len(fixed) > 1 else ''}, "
                     f"first at {first.strftime('%H:%M')}")
    else:
        parts.append("No meetings")
    open_count = len(db.query(
        "SELECT id FROM tasks WHERE user_id=? AND date=? AND is_anchor=0"
        " AND status IN ('planned','rescheduled')", (user["id"], today.isoformat())))
    if open_count:
        parts.append(f"{open_count} open from today")
    parked = len(db.query("SELECT id FROM backlog WHERE user_id=?", (user["id"],)))
    if parked:
        parts.append(f"{parked} parked item{'s' if parked > 1 else ''} waiting")
    return {"title": "Ready to plan your day?",
            "body": ". ".join(parts) + ". Brain-dump when ready."}


# ── meeting prep (design 5e) — offered, never auto-added ────────────

@app.get("/prep")
def prep_offer(tz: str = "UTC", user=Depends(current_user)) -> dict:
    """A 15-min prep slot before the next multi-person meeting, if one is free."""
    z = gcal.zone(tz)
    now = datetime.now(z)
    today = now.date()
    meetings = [ev for ev in gcal.external_events(user, today, tz)
                if ev.get("attendees", 0) >= 2
                and now < datetime.fromisoformat(ev["start"]) <= now + timedelta(hours=3)]
    if not meetings:
        return {"prep": None}
    meeting = meetings[0]
    m_start = datetime.fromisoformat(meeting["start"])
    already = db.query(
        "SELECT id FROM tasks WHERE user_id=? AND date=? AND title LIKE 'Prep — %'",
        (user["id"], today.isoformat()))
    if already:
        return {"prep": None}
    start = m_start - timedelta(minutes=15)
    if start < now:
        return {"prep": None}
    # the slot must be genuinely free
    for s, e in _today_busy(user, today, tz, z):
        if not (m_start <= s or start >= e):
            return {"prep": None}
    return {"prep": {"meeting_title": meeting["title"], "meeting_start": meeting["start"],
                     "attendees": meeting["attendees"],
                     "start": start.isoformat(), "minutes": 15}}


class PrepIn(BaseModel):
    meeting_title: str
    start: str  # ISO
    minutes: int = 15


@app.post("/prep")
def add_prep(body: PrepIn, tz: str = "UTC", user=Depends(current_user)) -> dict:
    start = datetime.fromisoformat(body.start)
    end = start + timedelta(minutes=body.minutes)
    title = f"Prep — {body.meeting_title}"
    event_id = gcal.insert_event(user, title, start.isoformat(), end.isoformat(), tz,
                                 category="deep_work")
    db.execute(
        "INSERT INTO tasks (user_id, date, title, category, start_ts, end_ts, status,"
        " google_event_id) VALUES (?,?,?,'deep_work',?,?,'planned',?)",
        (user["id"], start.date().isoformat(), title,
         start.isoformat(), end.isoformat(), event_id))
    return {"ok": True}


# ── disruption reflow (design 5d) ───────────────────────────────────

@app.get("/disruptions")
def disruptions(tz: str = "UTC", user=Depends(current_user)) -> dict:
    """The calendar changed under us: an external event now overlaps a synced
    task. Propose moving each colliding task into a free slot later today."""
    z = gcal.zone(tz)
    now = datetime.now(z)
    today = now.date()
    fixed = gcal.external_events(user, today, tz)

    # reconcile the next 7 days against Google Calendar: deletions surface as a
    # question; moves/resizes made directly in gcal are followed silently — the
    # calendar is the source of truth.
    scan = db.query(
        "SELECT * FROM tasks WHERE user_id=? AND date>=? AND date<=? AND is_anchor=0"
        " AND status IN ('planned','rescheduled') ORDER BY date, start_ts",
        (user["id"], today.isoformat(), (today + timedelta(days=7)).isoformat()))
    alive: dict[str, dict] = {}
    for d in sorted({r["date"] for r in scan}):
        for ev in gcal.list_events(user, date.fromisoformat(d), tz):
            alive[ev["id"]] = ev

    deleted, followed = [], []
    for t in scan:
        eid = t["google_event_id"]
        if not eid or datetime.fromisoformat(t["end_ts"]) <= now:
            continue
        ev = alive.get(eid)
        if ev is None:
            raw = gcal.get_event(user, eid)
            if raw is None:
                deleted.append({"task_id": t["id"], "title": t["title"],
                                "category": t["category"], "start": t["start_ts"]})
                continue
            s = raw.get("start", {}).get("dateTime")
            e = raw.get("end", {}).get("dateTime")
            if not s or not e:
                continue
            ev = {"start": s, "end": e}
        # Google may answer in UTC — store in the user's tz or the date/wall
        # time columns lie (19:30 CDT is 00:30Z "tomorrow")
        ns = datetime.fromisoformat(ev["start"]).astimezone(z).isoformat()
        ne = datetime.fromisoformat(ev["end"]).astimezone(z).isoformat()
        if (datetime.fromisoformat(ns) != datetime.fromisoformat(t["start_ts"])
                or datetime.fromisoformat(ne) != datetime.fromisoformat(t["end_ts"])):
            db.execute("UPDATE tasks SET date=?, start_ts=?, end_ts=? WHERE id=?",
                       (ns[:10], ns, ne, t["id"]))
            followed.append({"title": t["title"], "category": t["category"],
                             "old_start": t["start_ts"], "old_end": t["end_ts"],
                             "new_start": ns, "new_end": ne,
                             "deleted": False})

    # collision check runs on post-sync truth
    tasks = db.query(
        "SELECT * FROM tasks WHERE user_id=? AND date=? AND is_anchor=0"
        " AND status IN ('planned','rescheduled') ORDER BY start_ts",
        (user["id"], today.isoformat()))

    def overlaps(t):
        ts, te = datetime.fromisoformat(t["start_ts"]), datetime.fromisoformat(t["end_ts"])
        if te <= now:  # already in the past — nothing to save
            return None
        for ev in fixed:
            es, ee = datetime.fromisoformat(ev["start"]), datetime.fromisoformat(ev["end"])
            if ts < ee and es < te:
                return ev
        return None

    gone_ids = {d["task_id"] for d in deleted}
    colliding = [(t, overlaps(t)) for t in tasks if t["id"] not in gone_ids]
    colliding = [(t, ev) for t, ev in colliding if ev]
    if not colliding:
        return {"disruption": None, "deleted": deleted, "followed": followed}

    from .scheduler import suggest_slots
    profile = Profile.model_validate(json.loads(user["profile_json"] or "{}"))
    day_start = datetime(today.year, today.month, today.day, tzinfo=z)
    moving_ids = {t["id"] for t, _ in colliding}
    busy = [(datetime.fromisoformat(ev["start"]), datetime.fromisoformat(ev["end"]))
            for ev in fixed]
    busy += [(gcal.combine(today, a["start"], z), gcal.combine(today, a["end"], z))
             for a in db.anchors_for_date(user["id"], today)]
    busy += [(datetime.fromisoformat(t["start_ts"]), datetime.fromisoformat(t["end_ts"]))
             for t in tasks if t["id"] not in moving_ids]
    busy.append((day_start, now))  # nothing lands in the past

    moves, unplaced = [], []
    for t, ev in colliding:
        dur = max(15, int((datetime.fromisoformat(t["end_ts"])
                           - datetime.fromisoformat(t["start_ts"])).total_seconds() // 60))
        slots = suggest_slots(dur, busy, profile, day_start, count=1)
        if not slots:
            unplaced.append(t["title"])
            continue
        new_start = gcal.combine(today, slots[0], z)
        new_end = new_start + timedelta(minutes=dur)
        busy.append((new_start, new_end))
        moves.append({"task_id": t["id"], "title": t["title"], "category": t["category"],
                      "old_start": t["start_ts"], "old_end": t["end_ts"],
                      "new_start": new_start.isoformat(), "new_end": new_end.isoformat(),
                      "cause": ev["title"]})
    if not moves and not unplaced:
        return {"disruption": None, "deleted": deleted, "followed": followed}
    return {"disruption": {"cause": colliding[0][1]["title"],
                           "moves": moves, "unplaced": unplaced},
            "deleted": deleted, "followed": followed}


class MoveIn(BaseModel):
    task_id: int
    new_start: str
    new_end: str


class ReflowIn(BaseModel):
    moves: list[MoveIn] = []


class DeletedIn(BaseModel):
    task_ids: list[int]
    action: str  # "remove" (accept the deletion) | "restore" (put it back)


@app.post("/disruptions/deleted")
def resolve_deleted(body: DeletedIn, tz: str = "UTC", user=Depends(current_user)) -> dict:
    count = 0
    for tid in body.task_ids:
        rows = db.query("SELECT * FROM tasks WHERE id=? AND user_id=?", (tid, user["id"]))
        if not rows:
            continue
        r = rows[0]
        if body.action == "restore":
            event_id = gcal.insert_event(user, r["title"], r["start_ts"], r["end_ts"], tz,
                                         category=r["category"], location=r["location"])
            db.execute("UPDATE tasks SET google_event_id=? WHERE id=?", (event_id, r["id"]))
        else:
            db.execute("DELETE FROM tasks WHERE id=?", (r["id"],))
        count += 1
    return {"ok": True, "count": count}


@app.post("/disruptions")
def apply_reflow(body: ReflowIn, tz: str = "UTC", user=Depends(current_user)) -> dict:
    count = 0
    for m in body.moves:
        rows = db.query("SELECT * FROM tasks WHERE id=? AND user_id=?",
                        (m.task_id, user["id"]))
        if not rows:
            continue
        r = rows[0]
        if r["google_event_id"]:
            gcal.patch_event(user, r["google_event_id"], m.new_start, m.new_end, tz)
        db.execute("UPDATE tasks SET date=?, start_ts=?, end_ts=?, status='rescheduled'"
                   " WHERE id=?", (m.new_start[:10], m.new_start, m.new_end, r["id"]))
        count += 1
    return {"moved": count}


# ── weekly review (design 5b) ───────────────────────────────────────

@app.get("/week-review")
def week_review(tz: str = "UTC", user=Depends(current_user)) -> dict:
    """Last 7 days: completion by category, average slip, one insight."""
    today = datetime.now(gcal.zone(tz)).date()
    since = (today - timedelta(days=7)).isoformat()
    rows = db.query(
        "SELECT category, status, start_ts, end_ts, completed_at FROM tasks"
        " WHERE user_id=? AND date>=? AND date<=? AND is_anchor=0",
        (user["id"], since, today.isoformat()))
    total = len(rows)
    done = sum(r["status"] == "completed" for r in rows)

    budgets = (Profile.model_validate(json.loads(user["profile_json"] or "{}"))
               .weekly_budgets or {})
    by_cat: dict[str, dict] = {}
    for r in rows:
        c = by_cat.setdefault(r["category"], {"category": r["category"], "done": 0,
                                              "total": 0, "done_min": 0})
        c["total"] += 1
        if r["status"] == "completed":
            c["done"] += 1
            c["done_min"] += _dur_min(r)
    # budgeted categories with zero activity still belong on the scoreboard
    for cat, hours in budgets.items():
        by_cat.setdefault(cat, {"category": cat, "done": 0, "total": 0, "done_min": 0})
    categories = sorted(by_cat.values(), key=lambda c: -c["total"])
    for c in categories:
        c["pct"] = round(100 * c["done"] / c["total"]) if c["total"] else 0
        c["done_hours"] = round(c.pop("done_min") / 60, 1)
        c["budget_hours"] = budgets.get(c["category"])

    # average slip: planned end vs actual completion, same-day completions only
    slips = []
    for r in rows:
        if r["status"] == "completed" and r["completed_at"]:
            try:
                diff = (datetime.fromisoformat(r["completed_at"])
                        - datetime.fromisoformat(r["end_ts"])).total_seconds() / 60
                if 0 < diff < 24 * 60:
                    slips.append(diff)
            except ValueError:
                pass
    avg_slip = round(sum(slips) / len(slips)) if slips else None

    # one insight: a struggling category whose completions cluster late in the day
    insight = None
    for c in categories:
        if c["total"] >= 4 and c["pct"] <= 60:
            cat_rows = [r for r in rows if r["category"] == c["category"]]
            done_hours = [int(r["start_ts"][11:13]) for r in cat_rows
                          if r["status"] == "completed"]
            miss_hours = [int(r["start_ts"][11:13]) for r in cat_rows
                          if r["status"] in ("missed", "planned")]
            if done_hours and miss_hours and \
                    sum(done_hours) / len(done_hours) >= 15 > sum(miss_hours) / len(miss_hours):
                name = c["category"].replace("_", " ")
                insight = {
                    "category": c["category"],
                    "suggested_window": "evening",
                    "text": f"{name.capitalize()} tasks land far more often later in the day "
                            "than in the morning. Shift the default window?",
                    "options": ["Shift to 16:00+", "Keep as is"],
                }
                break
    # Sunday ritual (design 7b-7e) extras: best day, budget seeds, dropped list
    by_day: dict[str, list] = {}
    for r in rows:
        by_day.setdefault(r["date"], []).append(r)
    best_day = None
    best_rate = -1.0
    for d, rs in by_day.items():
        if len(rs) >= 3:
            rate = sum(r["status"] == "completed" for r in rs) / len(rs)
            if rate > best_rate:
                best_rate, best_day = rate, d
    if best_day:
        best_day = datetime.fromisoformat(best_day + "T00:00:00").strftime("%A")

    # first-run budget seeds: last week's actual completed hours per category
    for c in categories:
        if c["budget_hours"] is None:
            c["suggested_budget"] = max(1, round(c["done_hours"] or 0))

    today_iso = today.isoformat()
    dropped = [{"id": r["id"], "title": r["title"], "category": r["category"],
                "date": r["date"]}
               for r in db.query(
                   "SELECT id, title, category, date FROM tasks WHERE user_id=?"
                   " AND date>=? AND date<? AND is_anchor=0"
                   " AND status IN ('missed','planned','rescheduled')"
                   " ORDER BY date", (user["id"], since, today_iso))]

    return {"done": done, "total": total, "categories": categories,
            "avg_slip_min": avg_slip, "insight": insight,
            "best_day": best_day, "dropped": dropped}


class ReviewResolveIn(BaseModel):
    carry: list[int] = []    # → next week's first free slots
    backlog: list[int] = []  # → park
    letgo: list[int] = []    # → mark missed, move on


@app.post("/week-review/resolve")
def resolve_review(body: ReviewResolveIn, tz: str = "UTC",
                   user=Depends(current_user)) -> dict:
    """Step 4 of the Sunday ritual: what happens to the week's dropped tasks."""
    z = gcal.zone(tz)
    today = datetime.now(z).date()
    from .scheduler import suggest_slots
    profile = Profile.model_validate(json.loads(user["profile_json"] or "{}"))
    carried = []
    for tid in body.carry:
        rows = db.query("SELECT * FROM tasks WHERE id=? AND user_id=?", (tid, user["id"]))
        if not rows:
            continue
        r = rows[0]
        dur = _dur_min(r)
        for offset in range(1, 8):  # tomorrow onward — next week's room
            day = today + timedelta(days=offset)
            day_start = datetime(day.year, day.month, day.day, tzinfo=z)
            slots = suggest_slots(dur, _today_busy(user, day, tz, z), profile,
                                  day_start, count=1)
            if slots:
                start = gcal.combine(day, slots[0], z)
                end = start + timedelta(minutes=dur)
                event_id = gcal.insert_event(user, r["title"], start.isoformat(),
                                             end.isoformat(), tz, category=r["category"])
                db.execute(
                    "INSERT INTO tasks (user_id, date, title, category, start_ts, end_ts,"
                    " status, google_event_id) VALUES (?,?,?,?,?,?,'planned',?)",
                    (user["id"], day.isoformat(), r["title"], r["category"],
                     start.isoformat(), end.isoformat(), event_id))
                carried.append({"title": r["title"],
                                "when": f"{day.strftime('%a')} {slots[0]}"})
                break
        db.execute("UPDATE tasks SET status='missed' WHERE id=? AND status != 'completed'",
                   (tid,))
    for tid in body.backlog:
        rows = db.query("SELECT * FROM tasks WHERE id=? AND user_id=?", (tid, user["id"]))
        if rows:
            r = rows[0]
            db.execute("INSERT INTO backlog (user_id, title, category, duration_minutes)"
                       " VALUES (?,?,?,?)",
                       (user["id"], r["title"], r["category"], _dur_min(r)))
            db.execute("UPDATE tasks SET status='missed' WHERE id=? AND status != 'completed'",
                       (tid,))
    for tid in body.letgo:
        db.execute("UPDATE tasks SET status='missed' WHERE id=? AND user_id=?"
                   " AND status != 'completed'", (tid, user["id"]))
    return {"carried": carried, "parked": len(body.backlog), "let_go": len(body.letgo)}


# ── day notes (design 7o-7r): the calendar becomes a journal ────────

class NoteIn(BaseModel):
    mood: str  # good | ok | rough
    text: str = ""
    has_photo: bool = False


@app.put("/notes/{day}")
def put_note(day: date, body: NoteIn, user=Depends(current_user)) -> dict:
    db.execute(
        "INSERT INTO notes (user_id, date, mood, text, has_photo) VALUES (?,?,?,?,?)"
        " ON CONFLICT(user_id, date) DO UPDATE SET mood=excluded.mood,"
        " text=excluded.text, has_photo=excluded.has_photo",
        (user["id"], day.isoformat(), body.mood, body.text, int(body.has_photo)))
    return {"ok": True}


@app.get("/notes")
def list_notes(user=Depends(current_user)) -> list[dict]:
    out = []
    for r in db.query("SELECT * FROM notes WHERE user_id=? ORDER BY date DESC",
                      (user["id"],)):
        day_tasks = db.query(
            "SELECT status FROM tasks WHERE user_id=? AND date=? AND is_anchor=0",
            (user["id"], r["date"]))
        out.append({"date": r["date"], "mood": r["mood"], "text": r["text"],
                    "has_photo": bool(r["has_photo"]),
                    "done": sum(t["status"] == "completed" for t in day_tasks),
                    "total": len(day_tasks)})
    return out


# ── wrapped (design 7i-7m): the month, as a story ───────────────────

@app.get("/wrapped")
def wrapped(tz: str = "UTC", user=Depends(current_user)) -> dict:
    """Last calendar month's story: big number, weekly rhythm, one change."""
    z = gcal.zone(tz)
    today = datetime.now(z).date()
    first_this = today.replace(day=1)
    last_month_end = first_this - timedelta(days=1)
    start = last_month_end.replace(day=1)
    prev_start = (start - timedelta(days=1)).replace(day=1)

    def month_rows(a, b):
        return db.query(
            "SELECT * FROM tasks WHERE user_id=? AND date>=? AND date<=? AND is_anchor=0",
            (user["id"], a.isoformat(), b.isoformat()))

    rows = month_rows(start, last_month_end)
    prev_rows = month_rows(prev_start, start - timedelta(days=1))
    if not rows:
        return {"wrapped": None}

    def deep_hours(rs):
        return round(sum(_dur_min(r) for r in rs
                         if r["category"] == "deep_work"
                         and r["status"] == "completed") / 60)

    total = len(rows)
    done = sum(r["status"] == "completed" for r in rows)
    deep = deep_hours(rows)
    deep_prev = deep_hours(prev_rows)

    # weekly rhythm: planned-Monday flag + completion pct per week
    weeks = []
    wk_start = start - timedelta(days=start.weekday())
    while wk_start <= last_month_end:
        wk_end = wk_start + timedelta(days=6)
        wrs = [r for r in rows if wk_start.isoformat() <= r["date"] <= wk_end.isoformat()]
        if wrs:
            monday = wk_start.isoformat()
            planned_monday = any(r["date"] == monday
                                 and int(r["start_ts"][11:13]) < 12 for r in wrs)
            weeks.append({"planned_monday": planned_monday,
                          "pct": round(100 * sum(r["status"] == "completed"
                                                 for r in wrs) / len(wrs))})
        wk_start += timedelta(days=7)

    # the one change: category whose completion improved most, half vs half
    mid = start + timedelta(days=15)
    change = None
    best_delta = 14  # only report a real shift (>=15 points)
    for cat in {r["category"] for r in rows}:
        h1 = [r for r in rows if r["category"] == cat and r["date"] < mid.isoformat()]
        h2 = [r for r in rows if r["category"] == cat and r["date"] >= mid.isoformat()]
        if len(h1) >= 3 and len(h2) >= 3:
            p1 = round(100 * sum(r["status"] == "completed" for r in h1) / len(h1))
            p2 = round(100 * sum(r["status"] == "completed" for r in h2) / len(h2))
            if p2 - p1 > best_delta:
                best_delta = p2 - p1
                change = {"category": cat, "before_pct": p1, "after_pct": p2}

    return {"wrapped": {
        "month": start.strftime("%B"),
        "range_label": f"{start.strftime('%b %-d').upper()} — {last_month_end.strftime('%b %-d').upper()}",
        "month_key": start.strftime("%Y-%m"),
        "planned_days": len({r["date"] for r in rows}),
        "total_tasks": total,
        "landed_pct": round(100 * done / total),
        "deep_hours": deep,
        "deep_delta": deep - deep_prev if prev_rows else None,
        "weeks": weeks,
        "change": change,
    }}
