#!/usr/bin/env python3
"""Scrape the public GitHub contribution calendar into data/contributions.json.

No API token required: this parses the same HTML fragment GitHub renders on the
profile page, https://github.com/users/<user>/contributions

Env:
  GITHUB_PROFILE_USER   override the username (default: "Richard7987")
"""
import datetime as dt
import json
import os
import re
import sys
from pathlib import Path

import requests
from bs4 import BeautifulSoup

USER = os.environ.get("GITHUB_PROFILE_USER", "Richard7987")
URL = f"https://github.com/users/{USER}/contributions"
ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "data" / "contributions.json"

HEADERS = {
    "User-Agent": (
        f"Mozilla/5.0 (compatible; profile-readme/1.0; "
        f"+https://github.com/{USER})"
    ),
    "Accept": "text/html",
    "X-Requested-With": "XMLHttpRequest",
}


def fetch() -> str:
    resp = requests.get(URL, headers=HEADERS, timeout=30)
    resp.raise_for_status()
    return resp.text


def parse_days(html_text: str) -> list[dict]:
    soup = BeautifulSoup(html_text, "html.parser")

    # Exact counts live in <tool-tip for="<cell id>">N contributions on ...</>.
    tips: dict[str, str] = {}
    for tip in soup.find_all("tool-tip"):
        target = tip.get("for")
        if target:
            tips[target] = tip.get_text(" ", strip=True)

    days: list[dict] = []
    for td in soup.select("td.ContributionCalendar-day"):
        date = td.get("data-date")
        if not date:
            continue
        level = int(td.get("data-level") or 0)
        count = None
        tip = tips.get(td.get("id", ""))
        if tip:
            match = re.match(r"([\d,]+)\s+contribution", tip)
            count = int(match.group(1).replace(",", "")) if match else 0
        days.append({"date": date, "level": level, "count": count})

    days.sort(key=lambda d: d["date"])
    return days


def is_active(day: dict) -> bool:
    value = day["count"] if day["count"] is not None else day["level"]
    return value > 0


def build_grid(days: list[dict]) -> tuple[list[list[int]], list[list]]:
    by_date = {d["date"]: d for d in days}
    start = dt.date.fromisoformat(days[0]["date"])
    end = dt.date.fromisoformat(days[-1]["date"])
    start -= dt.timedelta(days=(start.weekday() + 1) % 7)  # back to Sunday

    weeks: list[list[int]] = []
    month_labels: list[list] = []
    last_month = None
    cursor = start
    while cursor <= end:
        column = []
        for _ in range(7):
            day = by_date.get(cursor.isoformat())
            column.append(day["level"] if day else -1)
            cursor += dt.timedelta(days=1)
        col_start = start + dt.timedelta(days=7 * len(weeks))
        if col_start.month != last_month and col_start.day <= 7:
            month_labels.append([len(weeks), col_start.strftime("%b")])
            last_month = col_start.month
        weeks.append(column)
    return weeks, month_labels


def compute_stats(days: list[dict]) -> dict:
    total = sum(d["count"] or 0 for d in days)
    active_days = sum(1 for d in days if is_active(d))

    longest = run = 0
    for day in days:
        run = run + 1 if is_active(day) else 0
        longest = max(longest, run)

    today = dt.date.today().isoformat()
    current = 0
    for day in reversed(days):
        if is_active(day):
            current += 1
        elif day["date"] == today and current == 0:
            continue  # today simply has not been counted yet
        else:
            break

    best = max(days, key=lambda d: (d["count"] or 0, d["level"]), default=None)
    return {
        "total": total,
        "active_days": active_days,
        "current_streak": current,
        "longest_streak": longest,
        "best_day": None
        if not best
        else {
            "date": best["date"],
            "count": best["count"] or 0,
            "level": best["level"],
        },
    }


def now_utc() -> str:
    return dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def empty_payload() -> dict:
    return {
        "user": USER,
        "generated_at": now_utc(),
        "range": None,
        "weeks": [],
        "month_labels": [],
        "days": [],
        "stats": {
            "total": 0,
            "active_days": 0,
            "current_streak": 0,
            "longest_streak": 0,
            "best_day": None,
        },
    }


def main() -> int:
    try:
        days = parse_days(fetch())
    except Exception as exc:  # offline / rate-limited: keep the last good file
        print(f"warning: fetch failed ({exc})", file=sys.stderr)
        if OUT.exists():
            print("keeping existing data/contributions.json")
            return 0
        days = []

    if days:
        weeks, month_labels = build_grid(days)
        payload = {
            "user": USER,
            "generated_at": now_utc(),
            "range": {"start": days[0]["date"], "end": days[-1]["date"]},
            "weeks": weeks,
            "month_labels": month_labels,
            "days": days,
            "stats": compute_stats(days),
        }
    else:
        payload = empty_payload()

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    stats = payload["stats"]
    print(
        f"wrote {OUT}: {len(payload['days'])} days, {stats['total']} "
        f"contributions, streak {stats['current_streak']}d "
        f"(longest {stats['longest_streak']}d)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
