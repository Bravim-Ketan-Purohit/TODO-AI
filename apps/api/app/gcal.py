"""Google Calendar REST broker (primary calendar only) with auto token refresh."""
import os
from datetime import date, datetime, timedelta, timezone
from zoneinfo import ZoneInfo

import httpx
from fastapi import HTTPException
from google.auth.transport.requests import Request as GoogleRequest
from google.oauth2.credentials import Credentials

from . import db

EVENTS = "https://www.googleapis.com/calendar/v3/calendars/primary/events"
TOKEN_URL = "https://oauth2.googleapis.com/token"

# design palette → closest Google Calendar colorId
COLOR_IDS = {"deep_work": "9", "health": "10", "meals": "7", "admin": "3", "social": "11"}


def zone(tz: str) -> ZoneInfo:
    try:
        return ZoneInfo(tz)
    except (KeyError, ValueError):
        raise HTTPException(400, f"Unknown time zone: {tz}")


def combine(day: date, hhmm: str, z: ZoneInfo) -> datetime:
    h, m = map(int, hhmm.split(":"))
    return datetime(day.year, day.month, day.day, h, m, tzinfo=z)


def _access_token(user) -> str:
    expiry = datetime.fromisoformat(user["token_expiry"]) if user["token_expiry"] else None
    if expiry and expiry - timedelta(seconds=60) > datetime.now(timezone.utc):
        return user["access_token"]
    if not user["refresh_token"]:
        raise HTTPException(401, "Google session expired — reconnect your account")
    creds = Credentials(
        token=None,
        refresh_token=user["refresh_token"],
        token_uri=TOKEN_URL,
        client_id=os.environ["GOOGLE_CLIENT_ID"],
        client_secret=os.environ["GOOGLE_CLIENT_SECRET"],
    )
    creds.refresh(GoogleRequest())
    new_expiry = (creds.expiry.replace(tzinfo=timezone.utc) if creds.expiry
                  else datetime.now(timezone.utc) + timedelta(minutes=55)).isoformat()
    db.execute("UPDATE users SET access_token=?, token_expiry=? WHERE id=?",
               (creds.token, new_expiry, user["id"]))
    return creds.token


def _headers(user) -> dict:
    return {"Authorization": f"Bearer {_access_token(user)}"}


def list_events(user, day: date, tz: str) -> list[dict]:
    start = combine(day, "00:00", zone(tz))
    resp = httpx.get(EVENTS, headers=_headers(user), params={
        "timeMin": start.isoformat(),
        "timeMax": (start + timedelta(days=1)).isoformat(),
        "singleEvents": "true", "orderBy": "startTime", "maxResults": "50",
    })
    resp.raise_for_status()
    out = []
    for ev in resp.json().get("items", []):
        s, e = ev.get("start", {}).get("dateTime"), ev.get("end", {}).get("dateTime")
        if not s or not e:
            continue  # all-day events don't block hours
        out.append({"id": ev["id"], "title": ev.get("summary", "(untitled)"),
                    "start": s, "end": e, "recurring_id": ev.get("recurringEventId"),
                    "attendees": len(ev.get("attendees", []))})
    return out


def external_events(user, day: date, tz: str) -> list[dict]:
    """Events on the calendar that this app did NOT create — the immovable layer."""
    ours = {r["google_event_id"] for r in db.query(
        "SELECT google_event_id FROM tasks WHERE user_id=? AND google_event_id IS NOT NULL",
        (user["id"],))}
    return [ev for ev in list_events(user, day, tz)
            if ev["id"] not in ours and ev["recurring_id"] not in ours]


def insert_event(user, title: str, start_iso: str, end_iso: str, tz: str,
                 category: str | None = None, location: str | None = None,
                 rrule: str | None = None) -> str:
    body = {"summary": title,
            "start": {"dateTime": start_iso, "timeZone": tz},
            "end": {"dateTime": end_iso, "timeZone": tz}}
    if category:
        body["colorId"] = COLOR_IDS.get(category, "8")
    if location:
        body["location"] = location
    if rrule:
        body["recurrence"] = [rrule]
    resp = httpx.post(EVENTS, headers=_headers(user), json=body)
    resp.raise_for_status()
    return resp.json()["id"]


def get_event(user, event_id: str) -> dict | None:
    """The event as Google sees it now — None if deleted/cancelled."""
    resp = httpx.get(f"{EVENTS}/{event_id}", headers=_headers(user))
    if resp.status_code in (404, 410):
        return None
    resp.raise_for_status()
    ev = resp.json()
    return None if ev.get("status") == "cancelled" else ev


def patch_event(user, event_id: str, start_iso: str, end_iso: str, tz: str) -> None:
    body = {"start": {"dateTime": start_iso, "timeZone": tz},
            "end": {"dateTime": end_iso, "timeZone": tz}}
    httpx.patch(f"{EVENTS}/{event_id}", headers=_headers(user), json=body).raise_for_status()


def delete_event(user, event_id: str) -> None:
    resp = httpx.delete(f"{EVENTS}/{event_id}", headers=_headers(user))
    if resp.status_code not in (200, 204, 404, 410):  # already-gone is fine
        resp.raise_for_status()
