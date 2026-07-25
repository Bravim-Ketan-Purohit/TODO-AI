# TODO_AI API

FastAPI backend: OpenRouter LLM proxy, Google OAuth + Calendar broker, SQLite store.

## Setup

Requires [uv](https://docs.astral.sh/uv/).

```
uv sync
uv run uvicorn app.main:app --reload
```

Check http://127.0.0.1:8000/health → `{"status": "ok"}`.

## Secrets

Copy `.env.example` to `.env` and fill in values. `.env` is gitignored — never commit it.
