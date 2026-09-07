# grafana

Alert rules, in git rather than in a console. Four of them, and the count is
deliberate ([ADR 0010](../../docs/adr/0010-observability-grafana-cloud.md)).

This stack touches neither DigitalOcean nor the cluster. It reads the metrics
Alloy already ships and turns four of them into things that will wake somebody.

## Prerequisites

1. **A Grafana service account token.** Grafana Cloud → Administration → Users
   and access → Service accounts. It needs write access to alerting; the
   built-in **Admin** role covers it. Export as `GRAFANA_AUTH`.
2. **The stack slug** — the first label of the Grafana URL, so
   `https://<slug>.grafana.net`. `TF_VAR_grafana_stack_slug`.
3. **Where alerts go** — `TF_VAR_alert_email`. No default, because a committed
   one would be an address on an indexed page (ADR 0012).
4. `AWS_*` set to the bucket-scoped Spaces key, for the backend.

In CI the same three arrive as `secrets.GRAFANA_AUTH`,
`vars.GRAFANA_STACK_SLUG` and `secrets.ALERT_EMAIL`. The slug is a variable
rather than a secret because it is half of a URL.

## Apply

```bash
tofu init
tofu apply
```

## What it alerts on

| Alert | Fires when | Why it is worth waking for |
|---|---|---|
| `supabase_keepalive_stale` | the keepalive CronJob has not succeeded in two days | free Supabase projects pause after seven days, and auth lives there — a login outage with a few days' warning |
| `app_unavailable` | the `app` Deployment has no available replica | the site is down |
| `node_memory_pressure` | a kubelet sets `MemoryPressure` | eviction is imminent, and there is ~650 MiB of headroom to lose (#67) |
| `app_restarting` | a container in `hepta` restarts | containers do not restart during a deploy, so it is a crash — most likely an OOMKill against a limit that was guessed (#18) |

The first is the one that justifies the stack. It is the only failure here whose
symptom is *nothing happening*, and a CronJob that stops emails no one.

`kube_cronjob_status_last_successful_time` is used rather than
`kube_job_failed` on purpose: a failing job, a suspended CronJob, a deleted one
and one that quietly stopped scheduling all produce the same consequence, and
only the staleness check covers all four. Its `no_data_state` is `Alerting` for
the same reason — a missing metric there *is* the outage.

## What is not alerted on, and why

**Certificate expiry.** cert-manager exposes it, but nothing scrapes
cert-manager: Alloy collects `kube-state-metrics`, `kubelet`,
`kubelet_resources` and `cadvisor`, and no application endpoints. Rather than
add a scrape, this belongs to an external probe — which also checks the
certificate actually being served rather than what cert-manager believes it
issued, and covers DNS and reachability in the same check. Tracked on #23.

**Argo CD out of sync.** Also unscraped, and a weaker signal: out-of-sync means
git and the cluster differ, which is not an outage. If it becomes worth
knowing, `argocd-notifications` reports it directly and costs no series.

## Shape

Each condition is written so the PromQL returns nothing until it is breaching,
which makes every expression stage a uniform `> 0`. The rules are then generated
from one map in `alerts.tf`, so what differs between them is in one place and
the forty lines of Grafana rule scaffolding are not repeated four times.
