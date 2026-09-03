# 0004. Run on DOKS with a non-HA control plane

- **Status:** Accepted
- **Date:** 2026-08-29

## Context

The workload is one Rust service (`hepta`: Leptos SSR + `/api` + `/mcp`) plus a
Text Embeddings Inference (TEI) pod serving `intfloat/multilingual-e5-small`.
TEI is the sizing driver: the model is baked into the image, it requests 1Gi, and
its image is **linux/amd64 only**.

Budget is ~100 USD/month, lower being better. Bringing in users is not a goal;
demonstrating competent Kubernetes and IaC practice is.

DigitalOcean pricing, as of 2026: DOKS control plane is free (HA control plane is
+40 USD/month); worker nodes bill as Droplets; a Load Balancer is 12 USD/month.
Billing went per-second on 2026-01-01.

## Decision

- **DOKS, one cluster, non-HA control plane.**
- Node pool: **2 × `s-2vcpu-4gb`** (24 USD/month each).
- One DigitalOcean Load Balancer, fronting the Gateway from [0005](0005-gateway-api-envoy-gateway.md).
- All nodes amd64, so TEI runs natively — no `nodeSelector`, no emulation. Set the
  memory limit the application chart deliberately omits for local Kind
  (`limits.memory: 2Gi`) in the production values.
- A DigitalOcean billing alert at 80 USD.

Monthly cost:

| Item | USD/mo |
|---|---|
| DOKS control plane (non-HA) | 0 |
| 2 × `s-2vcpu-4gb` | 48 |
| Load Balancer | 12 |
| Managed Postgres ([0008](0008-postgres-do-managed.md)) | 15 |
| Spaces for state ([0003](0003-state-backend-spaces.md)) | 5 |
| DNS, GHCR, Grafana Cloud free, Supabase free | 0 |
| **Total** | **80** |

## Consequences

> **Measured, once telemetry existed:** two figures in this ADR's reasoning are
> optimistic. A 4 GB node is **3.0 GiB allocatable** — DigitalOcean reserves
> about a quarter — so the pool is ~6.0 GiB, not 8. And planning by *requests*
> understates reality: `cilium-agent` requests 300 MiB per node and uses ~700,
> with no limit to stop it, leaving ~800 MiB unaccounted across the cluster.
> Real headroom is therefore roughly 800 MiB less than the request arithmetic
> suggests, which matters most for the embeddings server's 1 GiB request and
> 2 GiB ceiling.

- ~20 USD/month of headroom for the second application, without re-architecting.
- Two nodes rather than one, at identical cost to a single `s-4vcpu-8gb`: real
  scheduling constraints, `topologySpreadConstraints` that mean something, and a
  node can be drained. A single node would leave ~3Gi usable after system
  overhead, which TEI (2Gi) plus Argo CD would exhaust.
- A control-plane outage is an outage. Accepted: 40 USD/month is 40% of the budget
  for an availability target this project does not have.
- ~6Gi schedulable across the pool is not generous. Every workload gets explicit
  requests and limits; this is a constraint to design against, not an oversight.
- TEI is the single largest consumer. If it becomes the binding constraint, the
  application's `Embedder` trait already allows swapping to a hosted embedding API
  without a schema change — that is the escape hatch, and it costs no work now.

## Alternatives considered

- **One `s-4vcpu-8gb` node (48 USD/mo).** Same price, more usable RAM after one
  set of system daemons. Rejected: no drain, no eviction story, no spread — the
  parts of Kubernetes worth demonstrating.
- **HA control plane (+40 USD/mo).** Rejected on budget; the trade-off is recorded
  rather than hidden.
- **Skip the Load Balancer** via `hostNetwork` plus a Reserved IP (−12 USD/mo).
  Rejected: DOKS recycles nodes, so the binding is fragile, and it is a trick
  rather than a practice.
- **Managed platforms (Fly.io, Railway, DO App Platform).** Cheaper and less work.
  Rejected on purpose — Kubernetes and IaC are the point of the exercise.
