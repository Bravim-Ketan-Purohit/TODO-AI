# TODO_AI API

FastAPI backend: OpenRouter LLM proxy, Google OAuth + Calendar broker, SQLite store.

## Setup

Requires [uv](https://docs.astral.sh/uv/).

```
uv sync
cp .env.example .env        # fill in keys (see below)
uv run uvicorn app.main:app --reload --env-file .env
```

Check http://127.0.0.1:8000/health → `{"status": "ok"}` · interactive docs at `/docs`.

Test the scheduler: `uv run python test_scheduler.py`

## Keys you need

1. **OpenRouter** — create a key at openrouter.ai → `OPENROUTER_API_KEY`.
2. **Google Cloud** — create a project, enable the **Google Calendar API**, create an
   **OAuth client (Web application)** with redirect URI
   `http://127.0.0.1:8000/auth/google/callback` → `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET`.
3. Optionally set `ALLOWED_EMAILS` (comma-separated) to lock sign-in to the 2 test users.

## Endpoints

| Route | What |
|---|---|
| `GET /auth/google/start` | Open in ASWebAuthenticationSession; ends at `todoai://auth?token=…` |
| `GET /me` · `PUT /me/profile` | Profile (role, rhythm, anchors) |
| `POST /chat` `{message?, approve?, tz}` | The state machine: clarify / proposal / synced / edited / info |
| `GET /today?tz=` | Today's tasks + anchors + external events |
| `GET /days/{YYYY-MM-DD}?tz=` | Any day (timeline screen) |
| `GET /history?days=30&tz=` | Per-day done/total/categories |
| `POST /tasks/{id}/status` | Mark completed / missed |

All routes except `/health` and `/auth/*` need `Authorization: Bearer <session token>`.

## Secrets

`.env` is gitignored — never commit it. The SQLite DB (`todo_ai.db`) holds OAuth
refresh tokens; it is gitignored too.
