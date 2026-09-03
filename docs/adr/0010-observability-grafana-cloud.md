# 0010. Ship telemetry to Grafana Cloud with Alloy

- **Status:** Accepted
- **Date:** 2026-08-29

## Context

The cluster needs metrics, logs, and ideally traces — both to operate it and
because an infrastructure portfolio without observability is conspicuously
incomplete.

The default answer, `kube-prometheus-stack` (Prometheus + Alertmanager + Grafana +
exporters), wants on the order of 2Gi before storing anything long-term. On a
cluster with roughly 6Gi schedulable ([0004](0004-kubernetes-on-doks.md)), of which
TEI takes 2Gi and Argo CD ~1Gi, that is not a rounding error — it is a second node.

Grafana Cloud's free tier covers 2,232 host-hours and 37,944 container-hours per
month; two nodes is ~1,460 host-hours. Grafana Alloy collects as a DaemonSet at
roughly 100m CPU / 128Mi per node and doubles as an OTLP receiver.

> **Measured, after the fact:** the DaemonSet is indeed 100m/128Mi per node, but
> that is not the whole deployment. Grafana's `k8s-monitoring` chart — the
> supported path, and what produces the metric shape Grafana Cloud's dashboards
> expect — also brings a metrics collector, a singleton for cluster events,
> kube-state-metrics and an operator. **375m CPU / 576Mi requested in total**,
> not the 256Mi this ADR estimated from the DaemonSet alone. The decision below
> is unaffected: it is still roughly a quarter of `kube-prometheus-stack`, which
> is the comparison that mattered.

## Decision

**Grafana Alloy in-cluster, Grafana Cloud free tier as the backend.**

- Alloy as a DaemonSet, deployed through the platform bundle.
- Metrics via remote-write; logs scraped from containers with Kubernetes metadata;
  OTLP receiver enabled so the application can export traces later without any
  platform change.
- Retention, dashboards, and alerting live in Grafana Cloud — nothing to store or
  back up in-cluster.
- The Grafana Cloud token is a Sealed Secret ([0007](0007-secrets-sealed-secrets.md)).
- Alerting starts minimal and specific: node memory pressure, `hepta` pod not
  ready, certificate expiry, Argo CD out-of-sync.

## Consequences

- Roughly 576Mi total for observability instead of ~2Gi — see the measurement
  above; the 256Mi in this ADR's context was an estimate of one component. The
  headroom that remains is still what makes the second application affordable on
  the same node pool.
- Dashboards survive cluster rebuilds, which matters when the cluster is
  disposable by design.
- Telemetry outlives the cluster it describes — a post-mortem is still possible
  after a cluster is destroyed.
- Depends on a third-party free tier. If it disappears, the fallback is
  self-hosting Prometheus at the cost of a node; Alloy is a standard collector and
  can remote-write elsewhere, so the in-cluster half is not locked in.
- Free-tier retention is limited. Fine — this is not a compliance workload.
- Cluster telemetry leaves the account. Acceptable for infrastructure metrics; no
  application data is exported.

## Alternatives considered

- **`kube-prometheus-stack` in-cluster.** Full control, no external dependency,
  the more conventional demonstration. Rejected on footprint: it would consume the
  margin that makes the whole 80 USD/month plan work.
- **VictoriaMetrics.** Materially lighter than Prometheus and a genuine option if
  self-hosting becomes necessary. Rejected for now — still an in-cluster storage
  and retention problem to own.
- **Nothing beyond `kubectl` and metrics-server.** Rejected: the gap would be the
  first thing anyone notices.
