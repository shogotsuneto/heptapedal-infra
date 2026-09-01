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

## Continuous integration

`plan` on every pull request, `apply` on merge to `main`.
`terraform/bootstrap` is excluded: it needs the full-access Spaces key, which is
deliberately kept out of CI.

**Merging applies.** GitHub reserves environment protection rules — required
reviewers, wait timers — for public repositories on this plan, so while this
repository is private there is no approval step between merge and apply. The
review gate is the pull request and the plan comment on it; merging is the
deliberate act. Turning the reviewer on is part of going public (#28).

Nothing hands a plan **artifact** between jobs. `-out` and `show -json` contain
every value unredacted, `sensitive` included, so merging re-plans rather than
replaying the reviewed plan — a small divergence traded for never persisting a
credential-bearing file
([ADR 0012](docs/adr/0012-treat-the-repository-as-publishable.md)). Rendered
plan text is posted to the pull request with identifiers masked, which is
hygiene rather than a boundary; the map is accepted as public.

### Setting it up

Two environments, holding credentials with deliberately different power:

| Environment | Runs | DigitalOcean token | Spaces key | Protection |
|---|---|---|---|---|
| `plan` | pull requests | `*:read` scopes only | `read` on the state bucket | none |
| `production` | merges to `main` | the write token | `readwrite` on the state bucket | `main` only (reviewer when public) |

A workflow that anyone can trigger by opening a pull request therefore holds
credentials that cannot change anything. `plan` runs with `-lock=false` so the
read-only Spaces key suffices — taking a lock would mean writing a `.tflock`
object, and plan writes no state.

Each environment needs `DIGITALOCEAN_TOKEN`, `AWS_ACCESS_KEY_ID` and
`AWS_SECRET_ACCESS_KEY` as environment secrets. Even without protection rules
the `production` environment earns its place: it is what keeps the write
credentials out of the pull-request job.

## Decisions

Every significant choice is recorded in [`docs/adr/`](docs/adr/README.md), with the
alternatives that were rejected and why. Start there — particularly
[ADR 0005](docs/adr/0005-gateway-api-envoy-gateway.md), which is the decision that
drives the most work, and
[ADR 0012](docs/adr/0012-treat-the-repository-as-publishable.md), which constrains
all of them: nothing here may depend on the repository staying private.

## Status

Design agreed; build-out tracked in
[issues](https://github.com/shogotsuneto/heptapedal-infra/issues), grouped by
phase into [milestones](https://github.com/shogotsuneto/heptapedal-infra/milestones).
