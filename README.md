# heptapedal-infra

Infrastructure and delivery for [heptapedal](https://github.com/shogotsuneto/heptapedal)
— and, later, other applications on the same platform.

Managed Kubernetes on DigitalOcean, described in Terraform-compatible HCL and
delivered with Argo CD. The design target is a platform that a single operator can
run for well under 100 USD/month while still being an honest example of current
practice — Gateway API rather than a retired ingress controller, GitOps rather
than imperative applies, and every trade-off written down.

## Architecture

| Layer | Choice |
|---|---|
| IaC | OpenTofu (plain Terraform HCL; `terraform` works against the same tree) |
| State | DigitalOcean Spaces, S3-native locking (`use_lockfile`) |
| Cluster | DOKS, non-HA control plane, 2 × `s-2vcpu-4gb` |
| Ingress | Gateway API via Envoy Gateway |
| TLS / DNS | cert-manager (DNS-01, wildcard) + DigitalOcean DNS |
| Delivery | Argo CD, app-of-apps |
| Secrets | Sealed Secrets |
| Database | DigitalOcean Managed Postgres (pgvector); auth on Supabase |
| Telemetry | Grafana Alloy → Grafana Cloud |

Target run cost: **~80 USD/month**. The breakdown, and why each line is what it
is, is in [ADR 0004](docs/adr/0004-kubernetes-on-doks.md).

## Layout

```
terraform/
  bootstrap/    # the state bucket — local state, applied once
  platform/     # project, VPC, DOKS, DNS, managed Postgres, firewall
  argocd/       # Argo CD install + the single root Application
gitops/
  root/         # app-of-apps root
  platform/     # cert-manager, Envoy Gateway, Sealed Secrets, Alloy
  apps/         # per-application Argo CD Applications + production values
docs/adr/       # architecture decision records
```

Terraform's responsibility stops at the root Application; everything past that
point reconciles from `gitops/`. See [ADR 0006](docs/adr/0006-gitops-argo-cd-app-of-apps.md).

## Decisions

Every significant choice is recorded in [`docs/adr/`](docs/adr/README.md), with the
alternatives that were rejected and why. Start there — particularly
[ADR 0005](docs/adr/0005-gateway-api-envoy-gateway.md), which is the decision that
drives the most work.

## Status

Design agreed; build-out tracked in
[issues](https://github.com/shogotsuneto/heptapedal-infra/issues), grouped by
phase into [milestones](https://github.com/shogotsuneto/heptapedal-infra/milestones).
