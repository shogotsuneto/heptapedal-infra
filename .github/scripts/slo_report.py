"""Write last week's SLO review file (ADR 0019).

Run by .github/workflows/slo-review.yml, and runnable by hand with the same
environment:

    GRAFANA_STACK_SLUG=<slug> GRAFANA_SLO_READ_TOKEN=<token> \
        python3 .github/scripts/slo_report.py docs/slo/reviews

SLO_WEEK_END=YYYY-MM-DD selects an earlier week (see below).

Prints the path of the file it wrote. Standard library only, so the workflow
needs no install step.

The numbers come from the probe counters the SLO is defined on
(terraform/grafana/slo.tf), not from Grafana SLO's own recording rules. Their
names are the plugin's implementation detail; the counters are the definition.
OBJECTIVE and WINDOW_DAYS must match slo.tf.
"""

import datetime as dt
import json
import os
import sys
import urllib.parse
import urllib.request

OBJECTIVE = 0.995
WINDOW_DAYS = 7
SELECTOR = '{job="heptapedal"}'
DATASOURCE_UID = "grafanacloud-prom"


def last_monday_midnight_utc(now: dt.datetime) -> dt.datetime:
    # The week ends at the most recent Monday 00:00 UTC, whenever the scheduled
    # run actually starts: GitHub delays cron runs, sometimes by an hour or
    # more, and the window should not move with the delay.
    midnight = now.replace(hour=0, minute=0, second=0, microsecond=0)
    return midnight - dt.timedelta(days=midnight.weekday())


class Prometheus:
    def __init__(self, slug: str, token: str):
        self.base = (
            f"https://{slug}.grafana.net/api/datasources/proxy/uid/"
            f"{DATASOURCE_UID}/api/v1"
        )
        self.token = token

    def _get(self, path: str, params: dict) -> list:
        url = f"{self.base}/{path}?{urllib.parse.urlencode(params)}"
        req = urllib.request.Request(
            url, headers={"Authorization": f"Bearer {self.token}"}
        )
        with urllib.request.urlopen(req, timeout=30) as resp:
            body = json.load(resp)
        if body.get("status") != "success":
            raise RuntimeError(f"query failed: {body}")
        return body["data"]["result"]

    def instant(self, query: str, at: dt.datetime) -> list:
        return self._get("query", {"query": query, "time": at.timestamp()})

    def scalar(self, query: str, at: dt.datetime) -> float:
        result = self.instant(query, at)
        return float(result[0]["value"][1]) if result else 0.0

    def daily(self, query: str, start: dt.datetime, end: dt.datetime) -> list:
        # Each step's value covers the day ending at that step, so the first
        # step is start + 1d.
        result = self._get(
            "query_range",
            {
                "query": query,
                "start": (start + dt.timedelta(days=1)).timestamp(),
                "end": end.timestamp(),
                "step": 86400,
            },
        )
        return result[0]["values"] if result else []


def ratio(success: float, total: float) -> float | None:
    return success / total if total > 0 else None


def main() -> None:
    out_dir = sys.argv[1]
    prom = Prometheus(
        os.environ["GRAFANA_STACK_SLUG"], os.environ["GRAFANA_SLO_READ_TOKEN"]
    )

    # SLO_WEEK_END backfills a week a failed run missed: any date in the week
    # after it, usually that Monday. Grafana keeps 14 days, so only the last
    # two weeks can be backfilled, and only until the data ages out.
    week_end = os.environ.get("SLO_WEEK_END")
    if week_end:
        anchor = dt.datetime.fromisoformat(week_end).replace(tzinfo=dt.timezone.utc)
    else:
        anchor = dt.datetime.now(dt.timezone.utc)
    end = last_monday_midnight_utc(anchor)
    if end > dt.datetime.now(dt.timezone.utc):
        sys.exit(f"{end.date()} is in the future; that week has not ended.")
    start = end - dt.timedelta(days=WINDOW_DAYS)
    window = f"[{WINDOW_DAYS}d]"

    # `increase` extrapolates, so these are not whole numbers; they are rounded
    # for display only.
    total_q = f"sum(increase(probe_all_success_count{SELECTOR}{window}))"
    success_q = f"sum(increase(probe_all_success_sum{SELECTOR}{window}))"
    total = prom.scalar(total_q, end)
    success = prom.scalar(success_q, end)
    failed = max(total - success, 0.0)
    sli = ratio(success, total)

    budget_minutes = (1 - OBJECTIVE) * WINDOW_DAYS * 24 * 60
    if sli is None:
        spent_minutes = None
        remaining = None
    else:
        spent_minutes = (1 - sli) * WINDOW_DAYS * 24 * 60
        remaining = 1 - (1 - sli) / (1 - OBJECTIVE)

    per_probe = {}
    for kind, metric in (("total", "count"), ("success", "sum")):
        for row in prom.instant(
            f"sum by (probe) (increase(probe_all_success_{metric}{SELECTOR}{window}))",
            end,
        ):
            per_probe.setdefault(row["metric"].get("probe", "?"), {})[kind] = float(
                row["value"][1]
            )

    day_totals = prom.daily(
        f"sum(increase(probe_all_success_count{SELECTOR}[1d]))", start, end
    )
    day_success = dict(
        prom.daily(f"sum(increase(probe_all_success_sum{SELECTOR}[1d]))", start, end)
    )

    year, week, _ = start.isocalendar()
    name = f"{year}-W{week:02d}"
    last_day = (end - dt.timedelta(days=1)).date()

    if remaining is None:
        verdict = (
            "**No data.** The probe recorded no executions this week, so the "
            "SLO measured nothing. Check Synthetic Monitoring before anything "
            "else: this is an outage of the measurement."
        )
    elif remaining <= 0:
        verdict = (
            "**Exhausted.** No risky changes until it recovers. Write a short "
            "note below on what spent it."
        )
    elif remaining < 0.5:
        verdict = "**Under 50%.** The next piece of work is whatever caused the spend."
    else:
        verdict = "**50% or more.** Work as usual, risky changes included."

    def pct(x: float | None, digits: int = 3) -> str:
        return "n/a" if x is None else f"{x * 100:.{digits}f}%"

    lines = [
        f"# SLO review {name}",
        "",
        f"{start.date()} to {last_day} (UTC). "
        f"`heptapedal.com availability`, objective {pct(OBJECTIVE, 1)} "
        f"over {WINDOW_DAYS} days ([ADR 0019](../../adr/0019-slo-and-error-budget.md)).",
        "",
        "## Numbers",
        "",
        "Generated; do not edit.",
        "",
        "| | |",
        "|---|---|",
        f"| SLI | {pct(sli)} |",
        f"| Probe executions | {total:.0f} ({failed:.0f} failed) |",
        f"| Budget | {budget_minutes:.0f} min |",
        "| Spent | "
        + ("n/a" if spent_minutes is None else f"{spent_minutes:.1f} min")
        + " |",
        f"| Remaining | {pct(remaining, 1)} |",
        "",
        f"Policy: {verdict}",
        "",
        "### By day",
        "",
        "| Day (UTC) | SLI | Failed |",
        "|---|---|---|",
    ]
    for ts, day_total in day_totals:
        day_total = float(day_total)
        day_ok = float(day_success.get(ts, 0))
        day = (dt.datetime.fromtimestamp(float(ts), dt.timezone.utc) - dt.timedelta(days=1)).date()
        lines.append(
            f"| {day} | {pct(ratio(day_ok, day_total))} | {max(day_total - day_ok, 0):.0f} |"
        )

    lines += [
        "",
        "### By probe location",
        "",
        "| Location | SLI | Failed |",
        "|---|---|---|",
    ]
    for probe, v in sorted(per_probe.items()):
        t, s = v.get("total", 0.0), v.get("success", 0.0)
        lines.append(f"| {probe} | {pct(ratio(s, t))} | {max(t - s, 0):.0f} |")

    lines += [
        "",
        "## Review",
        "",
        "Written by hand before merging. Merging this file is the review.",
        "",
        "- **What spent the budget:** <!-- an incident, a deploy, a flaky probe location, or nothing -->",
        "- **What changes because of it:** <!-- a fix, an issue, a change to the SLO itself, or nothing -->",
        "",
    ]

    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, f"{name}.md")
    with open(path, "w") as f:
        f.write("\n".join(lines))
    print(path)


if __name__ == "__main__":
    main()
