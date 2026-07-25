"""Google OAuth (single account = the calendar we control) + bearer sessions."""
import os
import secrets
from datetime import datetime, timedelta, timezone
from urllib.parse import urlencode

import httpx
from fastapi import APIRouter, Header, HTTPException
from fastapi.responses import RedirectResponse
from google.auth.transport import requests as google_requests
from google.oauth2 import id_token as google_id_token

from . import db

router = APIRouter(prefix="/auth/google", tags=["auth"])

SCOPES = "openid email https://www.googleapis.com/auth/calendar"
TOKEN_URL = "https://oauth2.googleapis.com/token"
APP_REDIRECT = "todoai://auth"  # ASWebAuthenticationSession callbackURLScheme


def _env(name: str) -> str:
    val = os.environ.get(name)
    if not val:
        raise HTTPException(500, f"{name} is not configured")
    return val


@router.get("/start")
def start() -> RedirectResponse:
    """The app opens this URL in ASWebAuthenticationSession; we bounce to Google."""
    params = urlencode({
        "client_id": _env("GOOGLE_CLIENT_ID"),
        "redirect_uri": _env("GOOGLE_REDIRECT_URI"),
        "response_type": "code",
        "scope": SCOPES,
        "access_type": "offline",  # we need a refresh token
        "prompt": "consent",       # always reissue one (2-user test, keeps re-login simple)
    })
    # ponytail: no OAuth state param — nothing pre-auth to bind it to; fine for a
    # 2-user invite-only test, add state+PKCE before any public launch
    return RedirectResponse(f"https://accounts.google.com/o/oauth2/v2/auth?{params}")


@router.get("/callback")
def callback(code: str) -> RedirectResponse:
    resp = httpx.post(TOKEN_URL, data={
        "code": code,
        "client_id": _env("GOOGLE_CLIENT_ID"),
        "client_secret": _env("GOOGLE_CLIENT_SECRET"),
        "redirect_uri": _env("GOOGLE_REDIRECT_URI"),
        "grant_type": "authorization_code",
    })
    if resp.status_code != 200:
        raise HTTPException(400, "Google token exchange failed")
    tok = resp.json()

    claims = google_id_token.verify_oauth2_token(
        tok["id_token"], google_requests.Request(), _env("GOOGLE_CLIENT_ID"))
    email = (claims.get("email") or "").lower()

    allowed = {e.strip().lower() for e in os.environ.get("ALLOWED_EMAILS", "").split(",") if e.strip()}
    if allowed and email not in allowed:
        raise HTTPException(403, "This private test is invite-only")

    expiry = (datetime.now(timezone.utc) + timedelta(seconds=tok.get("expires_in", 3600))).isoformat()
    session = secrets.token_hex(32)  # rotated on every login
    if db.query("SELECT id FROM users WHERE google_sub=?", (claims["sub"],)):
        db.execute(
            "UPDATE users SET email=?, access_token=?, refresh_token=COALESCE(?, refresh_token),"
            " token_expiry=?, session_token=? WHERE google_sub=?",
            (email, tok["access_token"], tok.get("refresh_token"), expiry, session, claims["sub"]))
    else:
        db.execute(
            "INSERT INTO users (google_sub, email, access_token, refresh_token, token_expiry, session_token)"
            " VALUES (?,?,?,?,?,?)",
            (claims["sub"], email, tok["access_token"], tok.get("refresh_token"), expiry, session))
    return RedirectResponse(f"{APP_REDIRECT}?token={session}")


def current_user(authorization: str = Header(default="")):
    token = authorization.removeprefix("Bearer ").strip()
    rows = db.query("SELECT * FROM users WHERE session_token=?", (token,)) if token else []
    if not rows:
        raise HTTPException(401, "Invalid or missing session token")
    return rows[0]
