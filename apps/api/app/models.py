"""Pydantic models — API bodies and the LLM's output contract."""
from typing import Annotated, Literal

from pydantic import BaseModel, BeforeValidator

DEFAULT_CATEGORIES = ["deep_work", "health", "meals", "admin", "social"]
Weekday = Literal["MO", "TU", "WE", "TH", "FR", "SA", "SU"]
ALL_DAYS: list[Weekday] = ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]


def _norm_category(v):
    """Categories are open-ended (users can add their own) — normalize shape."""
    if not isinstance(v, str) or not v.strip():
        return "admin"
    return v.strip().lower().replace(" ", "_")


Category = Annotated[str, BeforeValidator(_norm_category)]


def _to_hhmm(v):
    """LLM output is untrusted: models sometimes return full ISO datetimes where
    'HH:MM' is expected. Normalize; garbage raises and hits the retry loop."""
    if v is None or not isinstance(v, str):
        return v
    s = v.strip()
    if "T" in s:
        s = s.split("T", 1)[1]  # take the wall-time part
    h, m = s.split(":")[:2]
    return f"{int(h):02d}:{int(m[:2]):02d}"


HHMM = Annotated[str, BeforeValidator(_to_hhmm)]


class Recurrence(BaseModel):
    days: list[Weekday]
    start_time: HHMM
    end_time: HHMM
    until: str | None = None  # "YYYY-MM-DD"


class ParsedTask(BaseModel):
    title: str
    category: Category = "admin"
    duration_minutes: int | None = None
    start: HHMM | None = None  # only when the user stated/implied an exact time
    window: Literal["morning", "afternoon", "evening"] | None = None  # user-implied part of day
    location: str | None = None
    recurrence: Recurrence | None = None


class Question(BaseModel):
    task_title: str
    question: str
    suggestions: list[str] = []


class Edit(BaseModel):
    match_title: str
    new_start: HHMM | None = None
    new_duration_minutes: int | None = None
    move_to_tomorrow: bool = False
    cancel: bool = False


class LLMResult(BaseModel):
    """The only shape the model may reply with."""
    intent: Literal["plan", "edit", "other"]
    reply: str = ""
    tasks: list[ParsedTask] = []
    questions: list[Question] = []
    edits: list[Edit] = []


class PlanItem(BaseModel):
    title: str
    category: Category | None = None  # None → external fixed event
    start: str  # ISO datetime (for recurring items: representative first time)
    end: str
    fixed: bool = False
    location: str | None = None
    recurrence: Recurrence | None = None


class EditInfo(BaseModel):
    """Before/after payload for the chat edit card (design 3a/3b)."""
    title: str
    category: Category | None = None
    old_start: str  # ISO
    old_end: str
    new_start: str | None = None  # None → deleted
    new_end: str | None = None
    deleted: bool = False


class FixOption(BaseModel):
    """One overflow fix suggestion (design 3c)."""
    title: str
    subtitle: str = ""


class ChatIn(BaseModel):
    message: str | None = None
    approve: bool = False
    delete_decision: Literal["confirm", "keep"] | None = None
    tz: str = "UTC"


class ChatReply(BaseModel):
    type: Literal["clarify", "proposal", "synced", "edited",
                  "confirm_delete", "overflow", "info"]
    text: str
    questions: list[Question] = []
    plan: list[PlanItem] = []
    edits: list[EditInfo] = []
    options: list[FixOption] = []
    suggested_categories: list[str] = []  # unknown categories the user can add


class AnchorIn(BaseModel):
    """Settings-screen 'add to schedule' form (design: Schedule, née Anchors)."""
    title: str
    category: Category = "admin"
    start_time: HHMM
    end_time: HHMM
    days: list[Weekday] = ALL_DAYS


class Profile(BaseModel, extra="allow"):
    role: str | None = None
    wake: str = "07:00"
    sleep: str = "23:00"
    energy_peak: str = "morning"  # morning | afternoon | evening
    lunch: str = "12:30"
    workout: str | None = None  # morning | afternoon | evening
    custom_categories: list[str] = []  # user-added categories beyond the defaults


class StatusIn(BaseModel):
    status: Literal["planned", "completed", "missed", "rescheduled"]
