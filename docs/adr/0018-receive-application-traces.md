# 0018. Receive applications' traces on the metrics collector

- **Status:** Proposed
- **Date:** 2026-11-13

## Context

[0010](0010-observability-grafana-cloud.md) says Alloy's OTLP receiver was
enabled "so the application can export traces later without any platform
change". It never was: the collectors' Services expose only Alloy's own port,
and no traces destination exists. Now an application exports traces, metadata
only, over OTLP/HTTP, and needs somewhere in the cluster to send them.

Two constraints shape where:

- **Container-hours.** Grafana Cloud bills Kubernetes Monitoring by container
  hours, and [0017](0017-nats.md) already puts the cluster slightly over the free
  37,944 a month. Every Alloy pod is two containers, about 1,460 hours a month.
- **Free-tier traces.** 50 GB a month, 14 days' retention: ample for
  traces of a few kilobytes each, but nothing to sample against yet.

## Decision

**An OTLP/HTTP receiver on the existing metrics collector**, through the
chart's Application Observability feature, for traces only.

- Applications send to `http://alloy-alloy-metrics.monitoring.svc:4318`.
- **One new destination, `grafana-cloud-traces`,** to Grafana Cloud's OTLP
  gateway, with traces only. Metrics and logs keep their destinations.
- **Its own access policy token, `traces:write` only,** sealed into the existing
  `grafana-cloud` Secret beside the OTLP instance ID.
- **Span names pass through unchanged.** The chart's default rewrites them to its
  semantic-convention version's; the application names its own.
- No sampling: every trace is kept until volume says otherwise.

## Consequences

- No new pod, so no new container-hours.
- Traces and metric scraping share one process. At kilobytes per trace the load
  is negligible; a burst could still delay scrapes, which is the point to split
  the receiver out.
- A leaked traces token can write traces and nothing else, and revoking it
  leaves metrics and logs running.
- What the traces contain is the application's responsibility. 0010's "no
  application data is exported" holds only as long as applications export
  metadata, as the one using this does.
- gRPC stays off; the collector's Service lists port 4317 anyway, from the
  chart's receiver preset, with nothing listening.

## Alternatives considered

- **A receiver collector of its own.** Isolated from scraping, but two more
  containers, about 1,460 container-hours a month, on a cluster already at the
  free tier's edge.
- **Applications export straight to Grafana Cloud.** No platform change, but each
  application would hold a Grafana Cloud token, and the cluster's Kubernetes
  attributes would not be added to its spans.
- **Adding `traces:write` to the existing token.** No new secret value, but one
  token for all three signals: revoking it for traces would stop metrics and
  logs too.
- **Keeping the chart's span renaming.** Consistent with its conventions, but it
  would rename spans the application chose deliberately, and differently from
  what it shows locally.
