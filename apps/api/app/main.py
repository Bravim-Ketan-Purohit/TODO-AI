"""TODO_AI API — app wiring + the small read/write routes."""
import json
from datetime import date, datetime, timedelta

from fastapi import Depends, FastAPI, HTTPException

from . import auth, chat, db, gcal
from .auth import current_user
from .models import Profile, StatusIn

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
    db.execute("UPDATE tasks SET status=? WHERE id=?", (body.status, task_id))
    return {"ok": True}
