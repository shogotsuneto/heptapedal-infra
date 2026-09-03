# Architecture Decision Records

One file per decision, numbered and immutable: a decision is superseded by a new
ADR rather than edited in place. The point is that six months later — or in an
interview — the *reasoning* is recoverable, not just the result.

Format is a trimmed [MADR](https://adr.github.io/madr/): Context → Decision →
Consequences → Alternatives considered. Short is fine; the "Alternatives
considered" section is the one that earns its keep.

| # | Decision | Status |
|---|---|---|
| [0000](0000-use-architecture-decision-records.md) | Use Architecture Decision Records | Accepted |
| [0001](0001-repository-layout.md) | Keep Terraform and GitOps manifests in one repository | Accepted |
| [0002](0002-iac-tool-opentofu.md) | Use OpenTofu as the IaC CLI | Accepted |
| [0003](0003-state-backend-spaces.md) | Store state in DigitalOcean Spaces with native locking | Accepted |
| [0004](0004-kubernetes-on-doks.md) | Run on DOKS with a non-HA control plane | Accepted |
| [0005](0005-gateway-api-envoy-gateway.md) | Route north-south traffic with Gateway API / Envoy Gateway | Accepted |
| [0006](0006-gitops-argo-cd-app-of-apps.md) | Deliver with Argo CD using the app-of-apps pattern | Accepted |
| [0007](0007-secrets-sealed-secrets.md) | Manage secrets with Sealed Secrets | Accepted |
| [0008](0008-postgres-do-managed.md) | Application data on DO Managed Postgres; auth stays on Supabase | Accepted |
| [0009](0009-dns-and-tls.md) | Delegate DNS to DigitalOcean; wildcard certs via cert-manager DNS-01 | Accepted |
| [0010](0010-observability-grafana-cloud.md) | Ship telemetry to Grafana Cloud with Alloy | Accepted |
| [0011](0011-artifact-distribution-ghcr.md) | Keep GHCR packages private for now | Accepted |
| [0012](0012-treat-the-repository-as-publishable.md) | Treat this repository as publishable | Accepted |
| [0013](0013-region-sfo3.md) | Run everything in sfo3 | Accepted |
| [0014](0014-use-the-provider-gateway-implementation.md) | Use DigitalOcean's Gateway API implementation | Accepted |

## Statuses

- **Proposed** — written, not yet agreed.
- **Accepted** — in force.
- **Superseded by NNNN** — replaced; the file stays for the history.
