"""The one check for the packing logic. Run from apps/api:  uv run python test_scheduler.py"""
from datetime import datetime
from zoneinfo import ZoneInfo

from app.models import ParsedTask, Profile
from app.scheduler import schedule


def main() -> None:
    day = datetime(2026, 7, 24, tzinfo=ZoneInfo("America/Los_Angeles"))
    at = lambda h, m=0: day.replace(hour=h, minute=m)
    busy = [(at(9, 30), at(9, 45)), (at(13, 30), at(14, 30))]  # standup, design sync
    profile = Profile(wake="07:00", sleep="23:00", energy_peak="morning", workout="morning")
    tasks = [
        ParsedTask(title="Gym", category="health", duration_minutes=60, start="07:00"),
        ParsedTask(title="Deep work", category="deep_work", duration_minutes=120),
        ParsedTask(title="Reply to emails", category="admin", duration_minutes=30),
    ]

    placed = schedule(tasks, busy, profile, day)
    assert len(placed) == 3
    by_title = {p.title: p for p in placed}

    # explicit time respected verbatim
    assert by_title["Gym"].start == at(7).isoformat()

    # deep work lands inside the morning peak window
    deep_start = datetime.fromisoformat(by_title["Deep work"].start)
    deep_end = datetime.fromisoformat(by_title["Deep work"].end)
    assert at(8) <= deep_start and deep_end <= at(12), f"deep work at {deep_start}"

    # nothing overlaps (placed + fixed), everything within wake–sleep
    spans = sorted(busy + [(datetime.fromisoformat(p.start), datetime.fromisoformat(p.end)) for p in placed])
    for (s1, e1), (s2, e2) in zip(spans, spans[1:]):
        assert e1 <= s2, f"overlap at {e1} / {s2}"
    assert all(at(7) <= s and e <= at(23) for s, e in spans)

    print("scheduler ok:", ", ".join(f"{p.title} @ {datetime.fromisoformat(p.start):%H:%M}" for p in placed))


if __name__ == "__main__":
    main()
