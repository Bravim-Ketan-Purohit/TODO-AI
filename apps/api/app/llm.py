"""OpenRouter proxy — turns chat text into a validated LLMResult."""
import json
import os

import httpx
from fastapi import HTTPException
from pydantic import ValidationError

from pydantic import BaseModel

from .models import FixOption, LLMResult

URL = "https://openrouter.ai/api/v1/chat/completions"
DEFAULT_MODEL = "nvidia/nemotron-3-ultra-550b-a55b:free"

SYSTEM = """You are the scheduling brain of TODO_AI, a day planner. Convert the user's \
message into structured JSON. You never write to the calendar yourself — you only parse.

Rules:
- intent "plan": the user is describing tasks for the day (or answering your earlier \
questions). Return the FULL updated task list every turn, merging their answers in.
- NEVER invent a start time or a duration. Any task missing either goes into \
"questions" with 2-3 short suggestions drawn from the profile (e.g. their usual lunch \
time, their admin dip). A task is only complete when it has duration_minutes, and \
either a start or no stated time preference (then leave start null — the scheduler \
places it).
- Times the user states or clearly implies DO go on the task: "after I wake up" → \
their wake time; "an hour" → duration_minutes 60.
- When the user implies a part of day without an exact time ("evening walk", "after \
lunch", "this morning"), set "window" (morning/afternoon/evening) — never invent a \
start for it.
- Categories: deep_work (focus, study, classes), health (gym, walks, sport), meals, \
admin (email, errands, chores), social (friends, family, leisure). Work meetings, \
calls and interviews are admin, not social.
- Time suggestions in "questions" must NOT collide with fixed_events_today or \
already_scheduled_today — check before suggesting.
- Recurring schedules ("every Mon/Wed", "this semester") → set "recurrence" \
(days, start_time, end_time, until). Classes are deep_work.
- intent "edit": the user wants to change or cancel something already scheduled today \
("move gym to 9", "cancel the walk") → fill "edits" (match_title, new_start / \
new_duration_minutes / cancel). "Push X to tomorrow" → move_to_tomorrow true (keep \
new_start null to reuse the same time).
- intent "other": greetings or questions → answer briefly in "reply".
- All time fields ("start", "new_start", "start_time", "end_time") are 24-hour \
"HH:MM" strings like "07:00" or "16:30" — NEVER full ISO dates.
- "reply" may also carry one short conversational sentence for plan/edit turns.

Respond with ONLY a JSON object in this exact shape (no markdown fences):
{schema}
"""

# hand-written — the auto-generated schema wastes ~1500 prefill tokens per call
SCHEMA = """{"intent": "plan"|"edit"|"other", "reply": "one short sentence",
 "tasks": [{"title": str, "category": "deep_work"|"health"|"meals"|"admin"|"social",
   "duration_minutes": int|null, "start": "HH:MM"|null,
   "window": "morning"|"afternoon"|"evening"|null, "location": str|null,
   "recurrence": {"days": ["MO".."SU"], "start_time": "HH:MM", "end_time": "HH:MM",
     "until": "YYYY-MM-DD"|null}|null}],
 "questions": [{"task_title": str, "question": str, "suggestions": [str]}],
 "edits": [{"match_title": str, "new_start": "HH:MM"|null,
   "new_duration_minutes": int|null, "move_to_tomorrow": bool, "cancel": bool}]}"""


def _clean(text: str) -> str:
    text = text.strip()
    if text.startswith("```"):
        text = text.split("\n", 1)[1] if "\n" in text else text
        text = text.rsplit("```", 1)[0]
    return text.strip()


def call(profile: dict, fixed_events: list, scheduled_today: list, state: dict,
         message: str, now_iso: str, tz: str) -> LLMResult:
    key = os.environ.get("OPENROUTER_API_KEY")
    if not key:
        raise HTTPException(500, "OPENROUTER_API_KEY is not configured")

    context = json.dumps({
        "now": now_iso, "timezone": tz, "profile": profile,
        "fixed_events_today": fixed_events,
        "already_scheduled_today": scheduled_today,
        "pending_state": state,
    })
    system = SYSTEM.replace("{schema}", SCHEMA)
    messages = [
        {"role": "system", "content": system + "\nContext:\n" + context},
        {"role": "user", "content": message},
    ]

    for _ in range(2):  # one retry with the validation error fed back
        resp = httpx.post(URL, timeout=90.0,
                          headers={"Authorization": f"Bearer {key}"},
                          json={"model": os.environ.get("OPENROUTER_MODEL", DEFAULT_MODEL),
                                "messages": messages,
                                # structured extraction doesn't need chain-of-thought,
                                # and hidden reasoning tokens were ~90% of latency
                                "reasoning": {"enabled": False},
                                "max_tokens": 2000})
        if resp.status_code != 200:
            raise HTTPException(502, f"LLM call failed ({resp.status_code})")
        data = resp.json()
        if "choices" not in data:  # OpenRouter reports errors inside a 200 body
            detail = (data.get("error") or {}).get("message") or str(data)[:200]
            raise HTTPException(502, f"The model is unavailable right now — {detail}")
        content = data["choices"][0]["message"]["content"]
        try:
            return LLMResult.model_validate_json(_clean(content))
        except ValidationError as err:
            messages += [{"role": "assistant", "content": content},
                         {"role": "user", "content": f"Invalid: {err}. Reply with ONLY corrected JSON."}]
    raise HTTPException(502, "LLM returned unparseable output twice")


class _FixList(BaseModel):
    options: list[FixOption]


def fix_options(profile: dict, tasks: list, free_min: int, need_min: int, tz: str) -> list[FixOption]:
    """Overflow (design 3c): ask the model for 2-3 concrete fixes. Falls back to
    generic options if the call fails — overflow must never crash the chat."""
    fallback = [
        FixOption(title="Shorten the longest task", subtitle="Frees the biggest block"),
        FixOption(title="Move something to tomorrow", subtitle="Keep today realistic"),
        FixOption(title="Drop one task", subtitle="Your call which"),
    ]
    key = os.environ.get("OPENROUTER_API_KEY")
    if not key:
        return fallback
    prompt = (
        "A user's day plan doesn't fit: they asked for "
        f"{need_min} minutes of tasks but only {free_min} free minutes remain. "
        f"Tasks: {json.dumps(tasks)}. Profile: {json.dumps(profile)}. "
        "Suggest 2-3 concrete fixes (shorten X, move Y to tomorrow, drop Z). "
        'Each fix: short imperative "title" (the fix itself, phrased so it can be sent '
        'back as an instruction) and a brief "subtitle" (why it works). '
        'Reply with ONLY JSON: {"options": [{"title": "...", "subtitle": "..."}]}'
    )
    try:
        resp = httpx.post(URL, timeout=45.0,
                          headers={"Authorization": f"Bearer {key}"},
                          json={"model": os.environ.get("OPENROUTER_MODEL", DEFAULT_MODEL),
                                "messages": [{"role": "user", "content": prompt}],
                                "reasoning": {"enabled": False},
                                "max_tokens": 500})
        resp.raise_for_status()
        parsed = _FixList.model_validate_json(_clean(resp.json()["choices"][0]["message"]["content"]))
        return parsed.options[:3] or fallback
    except Exception:
        return fallback
