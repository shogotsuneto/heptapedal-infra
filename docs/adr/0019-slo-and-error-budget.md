# 0019. Start with one availability SLO, measured by the external probe

- **Status:** Accepted
- **Date:** 2026-11-14

## Context

Alerting so far ([0010](0010-observability-grafana-cloud.md), `terraform/grafana/alerts.tf`)
answers "is something broken right now?". It does not answer "how reliable has
the site been?", and it gives nothing to decide with, such as whether a risky
change can go ahead this week or reliability work should come first. An error
budget does both. The aim here is to learn to work with one, so the first
version should be small and easy to follow.

What is available:

- **Synthetic Monitoring** already probes `https://heptapedal.com/login` from
  three locations every five minutes. It exposes `probe_all_success_count`
  (executions) and `probe_all_success_sum` (successful executions) as counters.
- **No request-level metrics.** Neither Envoy Gateway nor the applications are
  scraped for request counts or latency.
- **Grafana SLO** is enabled on the stack (plugin 1.103.0). It is billed as the
  metrics its recording rules produce, about 10–12 series per SLO. The stack
  peaked at about 5,200 of the free tier's 10,000 active series in the last
  day.
- **The free tier keeps metrics for 14 days.**

## Decision

**One SLO, `heptapedal.com availability`, through Grafana SLO in
`terraform/grafana/slo.tf`.**

- **SLI:** successful probe executions ÷ all probe executions, across all
  locations.
- **Objective:** 99.5% over a rolling **7 days**, about 50 minutes of budget.
  - 7 days rather than 28 or 30 because of the 14-day retention: a longer
    window would quietly be calculated over 14 days.
  - 99.5% rather than 99.9%, which would be about 10 minutes a week, less than
    a single node replacement. Starting loose means the budget actually gets
    spent and the policy below gets used. Tighten it once a few weeks show what
    the site really achieves.
- **Alerts:** Grafana SLO's fast-burn and slow-burn alerts, to the existing
  email. They need at least six failed executions (about ten minutes of full
  outage), so a single failed round does not send an email.

**Budget policy.** The budget is only useful if it changes what gets done.

| Budget remaining (7 days) | What to do |
|---|---|
| 50% or more | Work as usual, including risky changes: node pool changes, major chart upgrades, a new application |
| Under 50% | The next piece of work is whatever caused the spend |
| Exhausted | No risky changes until it recovers. Write a short note on what spent it |

**Review, weekly, as a pull request.** Every Monday a scheduled workflow opens
a pull request with the previous week's numbers in `docs/slo/reviews/`. The
review is filling in what spent the budget and what changes because of it, then
merging. An unreviewed week stays visible as an open pull request. See
[`docs/slo/README.md`](../slo/README.md).

The existing alerts stay for now. `site_unreachable` and `app_unavailable`
overlap with the burn-rate alerts. Remove them once the burn-rate alerts have
shown, over a few weeks, that they catch the same outages. The cause alerts
(memory pressure, certificate expiry, keepalive, restarts) are early warnings
that come before budget is spent, and stay.

## Consequences

- The SLO tracks what a visitor sees, end to end: DNS, Load Balancer,
  certificate and application all count, as they do for `site_unreachable`.
- It is coarse. A check every five minutes cannot see a two-minute outage, and
  one failed round counts as five minutes. That is enough for learning to work
  with a budget, and not enough for latency or for anything behind `/login`.
- `/login` touches no database, so a database outage does not spend budget.
  That is a gap in the SLI, not an assumption that the database never fails.
- About a dozen more active series, well within the free tier.
- The Terraform token needs one more role, SLO Writer (see
  `terraform/grafana/README.md`).
- One more Grafana credential, a Viewer token for the weekly report, kept in
  its own GitHub environment, away from `production`'s write credentials.
- The report recalculates the SLI from the probe counters rather than reading
  Grafana SLO's recording rules, whose names belong to the plugin. Its
  objective and window are a copy of `slo.tf`'s and must change with it.

## Alternatives considered

- **Request-based SLI from Envoy Gateway metrics** (5xx rate, latency). The
  standard approach, and the next step. Deferred: it means scraping the
  gateway, which adds active series and possibly collector load, and that
  deserves its own decision.
- **SLI from orderassist's traces** through span metrics. Covers an
  application rather than the site, and traces arrived only a day ago.
- **Hand-written recording rules and burn-rate alerts.** Teaches more about how
  burn rates work, but is the part most likely to be done wrong first, and
  Grafana SLO generates it.
- **A 28-day window.** The common default, but not supported by 14-day
  retention.
