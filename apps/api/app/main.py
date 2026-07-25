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
    today = datetime.now(gcal.zone(tz)).date()
    since = (today - timedelta(days=days)).isoformat()
    rows = db.query(
        "SELECT date, status, category FROM tasks"
        " WHERE user_id=? AND date>=? AND date<=? AND is_anchor=0 ORDER BY date DESC, start_ts",
        (user["id"], since, today.isoformat()))
    out: dict[str, dict] = {}
    for r in rows:
        d = out.setdefault(r["date"], {"date": r["date"], "done": 0, "total": 0, "categories": []})
        d["total"] += 1
        d["done"] += r["status"] == "completed"
        if r["category"] not in d["categories"]:
            d["categories"].append(r["category"])
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
    """Yesterday's open tasks + where each would fit today."""
    z = gcal.zone(tz)
    today = datetime.now(z).date()
    yesterday = (today - timedelta(days=1)).isoformat()
    rows = db.query(
        "SELECT * FROM tasks WHERE user_id=? AND date=? AND is_anchor=0 ORDER BY start_ts",
        (user["id"], yesterday))
    open_rows = [r for r in rows if r["status"] in ("planned", "rescheduled", "missed")]
    if not open_rows:
        return {"yesterday": yesterday,
                "done": sum(r["status"] == "completed" for r in rows),
                "total": len(rows), "open": []}

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
    return {"yesterday": yesterday,
            "done": sum(r["status"] == "completed" for r in rows),
            "total": len(rows), "open": out}


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

    by_cat: dict[str, dict] = {}
    for r in rows:
        c = by_cat.setdefault(r["category"], {"category": r["category"], "done": 0, "total": 0})
        c["total"] += 1
        c["done"] += r["status"] == "completed"
    categories = sorted(by_cat.values(), key=lambda c: -c["total"])
    for c in categories:
        c["pct"] = round(100 * c["done"] / c["total"]) if c["total"] else 0

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
    return {"done": done, "total": total, "categories": categories,
            "avg_slip_min": avg_slip, "insight": insight}
