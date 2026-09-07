# grafana

Alert rules, in git rather than in a console. Four of them, and the count is
deliberate ([ADR 0010](../../docs/adr/0010-observability-grafana-cloud.md)).

This stack touches neither DigitalOcean nor the cluster. It reads the metrics
Alloy already ships and turns four of them into things that will wake somebody.

## Prerequisites

1. **A Grafana service account token.** Grafana Cloud → Administration → Users
   and access → Service accounts. Export as `GRAFANA_AUTH`.

   Basic role **Viewer** (or none), plus these three. Search the role picker by
   the identifier — the display names vary and the identifiers do not.

   | Fixed role | For |
   |---|---|
   | `fixed:alerting.provisioning:writer` | the rule group, contact point and notification policy |
   | `fixed:folders:writer` | `grafana_folder` — alert rules always live in a folder. It also carries the dashboard permissions, so dashboards need no role of their own |
   | `fixed:datasources:reader` | looking up the Prometheus and Loki data source UIDs by name |

   Two of those are easy to get wrong, and both were:

   - **Provisioning, not alerting.** The Terraform provider writes through
     `/api/v1/provisioning/…`, so a role that grants managing alerts by other
     means still returns `403` here. `fixed:alerting.provisioning:writer` is the
     one that covers rules, contact points and notification policies together.
   - **Writer, not creator.** `fixed:folders:creator` grants `folders:create`
     and nothing else, so Terraform creates the folder and then fails reading it
     back. A managed resource needs read, update and delete too.

   Admin is not required. If a contact point ever carries a secret — a Slack
   webhook, say — add `fixed:alerting.provisioning.secrets:reader`, which lets
   the provider read back what it wrote; the email contact point here has no
   secure settings and does not need it.
2. **The stack slug** — the first label of the Grafana URL, so
   `https://<slug>.grafana.net`. `TF_VAR_grafana_stack_slug`.
3. **Where alerts go** — `TF_VAR_alert_email`. No default, because a committed
   one would be an address on an indexed page (ADR 0012).
4. `AWS_*` set to the bucket-scoped Spaces key, for the backend.

In CI the same three arrive as `secrets.GRAFANA_AUTH`,
`vars.GRAFANA_STACK_SLUG` and `secrets.ALERT_EMAIL`. The slug is a variable
rather than a secret because it is half of a URL.

If granting **Data sources: Reader** is not wanted, the lookup is the only
reason for it: set `prometheus_datasource_name` aside and pin the UID directly
instead, at the cost of a value nobody can re-derive after a rebuild.

## Apply

```bash
tofu init
tofu apply
```

## Dashboards

Every `*.json` in `dashboards/` becomes a dashboard in the `heptapedal` folder.
Adding one is dropping a file there.

That indirection exists because a dashboard is something you build by looking at
it, and edit-apply-look is a poor loop for that. Build it in the UI, then:

1. Dashboard settings → **JSON Model**, or Export → **Export as JSON**. Do *not*
   tick "Export for sharing externally" — that rewrites data sources into
   `${DS_*}` inputs this cannot resolve.
2. Save it into `dashboards/`.
3. Replace the data source UIDs with `__PROMETHEUS_UID__` and `__LOKI_UID__` so
   the file is not pinned to one stack's generated IDs. Optional — a literal UID
   works, it is just less portable.

Substitution is literal string replacement, not templating, so Grafana's own
`${...}` syntax passes through untouched. A file exported from the UI applies as
it is.

The dashboard's identity is the `uid` inside its JSON, and `overwrite` is on, so
a dashboard first drawn in the UI is adopted by committing its export rather
than duplicated beside itself. From then on the file is the source of truth: an
edit made in the UI and not exported will be overwritten by the next apply.

### The one that ships

`heptapedal-overview` — memory against limits from cadvisor, and request rate,
latency and status classes **derived from logs** rather than from metrics.

The application exposes no `/metrics`, but v0.2.2 emits structured JSON with
`route`, `status` and `latency_ms` on every completed request, so Loki answers
the same questions with no application change and no new pipeline.

**Extract only the fields a panel uses.** A bare `| json` promotes *every*
parsed field to a label, `trace_id` and `uri` included — which is one series per
request, and Loki refuses past 500 of them. Naming the fields keeps the label
set to what the panel groups by:

```logql
{namespace="hepta", container="app"}
  | json target="target", latency_ms="span.latency_ms"
  | target=`hepta::http`
  | unwrap latency_ms
```

An aggregation hides the problem rather than avoiding it: `sum by (route)`
returns few series whatever it consumed. The latency panel has no outer
aggregation, so it hit the ceiling first — hence the `by (container)` on its
range aggregation as well.

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
issued, and covers DNS and reachability in the same check. **#80.**

**Argo CD out of sync.** Also unscraped, and a weaker signal: out-of-sync means
git and the cluster differ, which is not an outage. If it becomes worth
knowing, `argocd-notifications` reports it directly and costs no series.

## Shape

Each condition is written so the PromQL returns nothing until it is breaching,
which makes every expression stage a uniform `> 0`. The rules are then generated
from one map in `alerts.tf`, so what differs between them is in one place and
the forty lines of Grafana rule scaffolding are not repeated four times.
