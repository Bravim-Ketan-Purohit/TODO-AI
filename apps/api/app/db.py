"""SQLite store — stdlib sqlite3, one file, no ORM."""
import json
import sqlite3
from contextlib import closing
from datetime import date
from pathlib import Path

DB_PATH = Path(__file__).resolve().parent.parent / "todo_ai.db"

WEEKDAYS = ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]

SCHEMA = """
CREATE TABLE IF NOT EXISTS users (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  google_sub TEXT UNIQUE NOT NULL,
  email TEXT NOT NULL,
  access_token TEXT NOT NULL,
  refresh_token TEXT,
  token_expiry TEXT,
  session_token TEXT UNIQUE,
  profile_json TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE TABLE IF NOT EXISTS tasks (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id),
  date TEXT NOT NULL,
  title TEXT NOT NULL,
  category TEXT NOT NULL,
  start_ts TEXT NOT NULL,
  end_ts TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'planned',
  google_event_id TEXT,
  is_anchor INTEGER NOT NULL DEFAULT 0,
  recurrence_json TEXT,
  location TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_tasks_user_date ON tasks(user_id, date);
CREATE TABLE IF NOT EXISTS chat_state (
  user_id INTEGER PRIMARY KEY REFERENCES users(id),
  state_json TEXT NOT NULL,
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE TABLE IF NOT EXISTS backlog (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id),
  title TEXT NOT NULL,
  category TEXT NOT NULL,
  duration_minutes INTEGER NOT NULL DEFAULT 30,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE TABLE IF NOT EXISTS deadlines (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id),
  title TEXT NOT NULL,
  due_date TEXT NOT NULL,
  target_minutes INTEGER NOT NULL,
  category TEXT NOT NULL DEFAULT 'deep_work',
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
"""


def _connect() -> sqlite3.Connection:
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    return conn


def init_db() -> None:
    with closing(_connect()) as conn, conn:
        conn.executescript(SCHEMA)
        # migrations (ALTERs are idempotent-by-exception)
        for ddl in ("ALTER TABLE tasks ADD COLUMN completed_at TEXT",
                    "ALTER TABLE tasks ADD COLUMN deadline_id INTEGER"):
            try:
                conn.execute(ddl)
            except sqlite3.OperationalError:
                pass  # column already exists


def query(sql: str, args: tuple = ()) -> list[sqlite3.Row]:
    with closing(_connect()) as conn, conn:
        return conn.execute(sql, args).fetchall()


def execute(sql: str, args: tuple = ()) -> int:
    """Run a write statement; returns lastrowid."""
    with closing(_connect()) as conn, conn:
        return conn.execute(sql, args).lastrowid


def anchors_for_date(user_id: int, day: date) -> list[dict]:
    """Expand recurring anchor tasks (classes etc.) into instances for one day.
    Times are 'HH:MM' strings; the caller localizes them."""
    out = []
    for r in query("SELECT * FROM tasks WHERE user_id=? AND is_anchor=1", (user_id,)):
        rec = json.loads(r["recurrence_json"] or "{}")
        if not rec or WEEKDAYS[day.weekday()] not in rec.get("days", []):
            continue
        if day.isoformat() < r["date"]:
            continue
        if rec.get("until") and day.isoformat() > rec["until"]:
            continue
        out.append({
            "task_id": r["id"], "title": r["title"], "category": r["category"],
            "start": rec["start_time"], "end": rec["end_time"],
            "location": r["location"], "recurring": True,
        })
    return out
