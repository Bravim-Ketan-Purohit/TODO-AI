"""Greedy interval packing — fixed events and anchors are immovable; flexible
tasks fill the gaps, preferring each category's time window from the profile.

ponytail: greedy first-fit, no backtracking/optimality — revisit if real days
stop fitting.
"""
from datetime import datetime, timedelta

from .models import ParsedTask, PlanItem, Profile

GRAIN = timedelta(minutes=15)
WINDOWS = {"morning": ("08:00", "12:00"), "afternoon": ("12:00", "17:00"), "evening": ("17:00", "22:00")}


class Conflict(ValueError):
    """An explicit-start task collides with something already scheduled."""

    def __init__(self, title: str, hhmm: str, duration_minutes: int):
        super().__init__(f"'{title}' at {hhmm} collides with an existing event")
        self.title = title
        self.hhmm = hhmm
        self.duration_minutes = duration_minutes


def _at(day: datetime, hhmm: str) -> datetime:
    h, m = map(int, hhmm.split(":"))
    return day.replace(hour=h, minute=m, second=0, microsecond=0)


def _preferred(task: ParsedTask, profile: Profile, day: datetime) -> tuple[datetime, datetime] | None:
    if task.window in WINDOWS:  # what the user implied beats any category default
        lo, hi = WINDOWS[task.window]
        return _at(day, lo), _at(day, hi)
    cat = task.category
    # learned per-category windows (weekly review "shift it" answers)
    learned = (getattr(profile, "category_windows", None) or {}).get(cat)
    if learned in WINDOWS:
        lo, hi = WINDOWS[learned]
        return _at(day, lo), _at(day, hi)
    peak = profile.energy_peak if profile.energy_peak in WINDOWS else "morning"
    if cat == "deep_work":
        name = peak
    elif cat == "admin":  # admin goes in the dips
        name = "afternoon" if peak == "morning" else "morning"
    elif cat == "health":
        name = profile.workout if profile.workout in WINDOWS else "evening"
    elif cat == "social":
        name = "evening"
    else:  # meals etc: no window preference — earliest gap (times usually clarified)
        return None
    lo, hi = WINDOWS[name]
    return _at(day, lo), _at(day, hi)


def suggest_slots(duration_minutes: int, busy: list[tuple[datetime, datetime]],
                  profile: Profile, day: datetime, count: int = 3) -> list[str]:
    """First few conflict-free start times for a task of this length."""
    dur = timedelta(minutes=duration_minutes)
    day_open, day_close = _at(day, profile.wake), _at(day, profile.sleep)
    intervals = sorted(busy)
    out: list[str] = []
    t = day_open
    while t + dur <= day_close and len(out) < count:
        if all(t + dur <= s or t >= e for s, e in intervals):
            out.append(t.strftime("%H:%M"))
            t += max(dur, timedelta(hours=1))  # spread the suggestions out
        else:
            t += GRAIN
    return out


def free_minutes(busy: list[tuple[datetime, datetime]], profile: Profile, day: datetime) -> int:
    """Unbooked minutes between wake and sleep — for the overflow message (3c)."""
    day_open, day_close = _at(day, profile.wake), _at(day, profile.sleep)
    total = int((day_close - day_open).total_seconds() // 60)
    booked = 0
    for s, e in sorted(busy):
        s, e = max(s, day_open), min(e, day_close)
        if e > s:
            booked += int((e - s).total_seconds() // 60)
    return max(0, total - booked)  # ponytail: overlapping busy events double-count; fine for a message


def schedule(tasks: list[ParsedTask], busy: list[tuple[datetime, datetime]],
             profile: Profile, day: datetime) -> list[PlanItem]:
    """Place tasks into free gaps within the wake–sleep window.
    Raises ValueError when a task cannot fit anywhere."""
    day_open, day_close = _at(day, profile.wake), _at(day, profile.sleep)
    intervals = sorted(busy)

    def fits(start: datetime, end: datetime) -> bool:
        return (start >= day_open and end <= day_close
                and all(end <= s or start >= e for s, e in intervals))

    def find(dur: timedelta, window: tuple[datetime, datetime] | None) -> datetime | None:
        lo, hi = window or (day_open, day_close)
        t, hi = max(lo, day_open), min(hi, day_close)
        while t + dur <= hi:
            if fits(t, t + dur):
                return t
            t += GRAIN
        return None

    placed: list[PlanItem] = []
    # explicit times are constraints, not choices — place them first
    for task in sorted(tasks, key=lambda t: t.start is None):
        # ponytail: LLM contract guarantees duration; 30 is a crash guard, not a guess
        dur = timedelta(minutes=task.duration_minutes or 30)
        if task.start:
            start = _at(day, task.start)
            # user-stated times win over preference windows, but never over real events
            if any(not (start + dur <= s or start >= e) for s, e in intervals):
                raise Conflict(task.title, task.start, int(dur.total_seconds() // 60))
        else:
            start = find(dur, _preferred(task, profile, day)) or find(dur, None)
            if start is None:
                raise ValueError(f"No room left for '{task.title}' ({task.duration_minutes} min)")
        intervals = sorted(intervals + [(start, start + dur)])
        placed.append(PlanItem(title=task.title, category=task.category, location=task.location,
                               start=start.isoformat(), end=(start + dur).isoformat()))
    return placed
