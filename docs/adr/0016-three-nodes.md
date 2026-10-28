# 0016. Grow the node pool to three nodes

- **Status:** Accepted
- **Date:** 2026-10-27
- **Supersedes:** the node count in [0004](0004-kubernetes-on-doks.md)

## Context

[0004](0004-kubernetes-on-doks.md) chose 2 × `s-2vcpu-4gb`. Measured on
2026-10-27, requests against allocatable:

| | Requested | Allocatable (2 nodes) | Left if one node is lost |
|---|---|---|---|
| CPU | 2609m | 3800m | 1900m |
| Memory | 4404Mi | 6005Mi | 3003Mi |

Actual use was far lower — ~320m CPU and ~3.1Gi of pod working set — but the
scheduler places by requests, and most of those requests are either measured
(Argo CD's controller, the embeddings server) or not ours to change. DOKS's own
`cilium`, `coredns` and `do-node-agent` take 512m / 582Mi of requests on every
node before anything of ours runs.

Two consequences followed:

- **Grafana Cloud's `KubeCPUOvercommit` and `KubeMemoryOvercommit` fired
  permanently.** They ask whether the cluster's requests still fit after losing
  its largest node. At two nodes that means keeping each under half full, which
  the DaemonSets and the embeddings server's 1Gi alone make impossible. The
  alert was not wrong: a drain or an upgrade really could leave Pods Pending. It
  was just never going to clear, so it had stopped carrying information.
- **The next project brings a NATS JetStream cluster.** A three-member Raft
  group on two nodes puts two members on one of them; losing that node loses
  quorum, which is the failure clustering exists to survive.

The other blocker is gone: the account's Droplet limit, 3 when 0004 was written,
is now 10.

## Decision

- **3 × `s-2vcpu-4gb`.** Same size, one more node.
- Changed through `node_count`, which plans as an in-place update of the
  inline pool — not the cluster replacement a `size` change forces.

## Consequences

- Losing a node leaves 3800m / ~6.0Gi for requests, against 2609m + ~520m and
  4404Mi + ~590Mi once the third node's own DaemonSets are counted. Both
  overcommit alerts should clear, which turns them back into a signal.
- Room for the next project is ~650m CPU and ~1Gi of requests before the
  alerts return. That is enough for a modest NATS cluster (e.g. 3 × 100m /
  256Mi) and a small service, not for much more. Past that, the answer is
  either larger nodes — through a separate node pool, since `size` on the
  inline one forces replacement — or a fourth node.
- Surge upgrades want `n + min(10, num_nodes)` = 6 Droplets, within the limit
  of 10, so upgrades get a full surge rather than 0004's partial one.
- **Cost:** nodes go from 48 to 72 USD/month, and 0004's total from 80 to
  **104 USD/month** — past the "well under 100" target. Accepted: the
  alternative is a cluster that cannot lose a node, hosting a project that is
  clustered precisely so that it can. If the excess matters, 0004's escape
  hatch still applies — swapping the in-cluster embeddings server for a hosted
  API frees a 1Gi request.
- **Grafana Cloud's free tier is now nearly exhausted.**
  [0010](0010-observability-grafana-cloud.md) cites 2,232 host-hours a month;
  three nodes use 2,232 in a 31-day month and 2,160 in a 30-day one. A surge
  upgrade's temporary nodes, or any fourth node, goes over. Container-hours
  (37,944) are at roughly 34,000 with today's workloads, so the next project's
  containers will likely go over too. Check the usage page after the first
  month and before adding the next project.

## Alternatives considered

- **2 × `s-4vcpu-8gb` (96 USD/mo).** More headroom per Droplet and less
  per-node overhead, but still two failure domains — the Raft problem above is
  unchanged — and resizing the inline pool replaces the cluster.
- **Stay at two nodes and trim requests until the alerts clear.** Each node
  would have to be under half full. The trims available (mostly Alloy's CPU)
  are worth ~200m; the gap is ~700m CPU and ~1.4Gi memory.
- **Silence the overcommit alerts.** Cheap, and honest about the two-node
  trade-off, but does nothing for NATS quorum.
- **`s-2vcpu-2gb` as the third node.** After DigitalOcean's reserve and the
  per-node DaemonSets, a 2 GB node has very little left for workloads.
