# heptapedal-infra

Infrastructure and delivery for [heptapedal](https://github.com/shogotsuneto/heptapedal)
— and, later, other applications on the same platform.

**It is running.** [heptapedal.com](https://heptapedal.com) serves from this
repository: a Rust/Leptos application, an in-cluster embeddings service, and an
MCP endpoint, on managed Kubernetes described in Terraform-compatible HCL and
delivered by Argo CD.

The design target is a platform one person can run for well under 100 USD/month
while still being an honest example of current practice — Gateway API rather
than a retired ingress controller, GitOps rather than imperative applies, and
every trade-off written down rather than implied.

## Architecture

| Layer | Choice | |
|---|---|---|
| IaC | OpenTofu — plain Terraform HCL; `terraform` works against the same tree | [0002](docs/adr/0002-iac-tool-opentofu.md) |
| State | DigitalOcean Spaces, S3-native locking | [0003](docs/adr/0003-state-backend-spaces.md) |
| Cluster | DOKS, non-HA control plane, 2 × `s-2vcpu-4gb` | [0004](docs/adr/0004-kubernetes-on-doks.md) |
| Ingress | Gateway API, using the Cilium implementation DOKS already ships | [0005](docs/adr/0005-gateway-api-envoy-gateway.md), [0014](docs/adr/0014-use-the-provider-gateway-implementation.md) |
| TLS / DNS | cert-manager DNS-01 wildcard + DigitalOcean DNS | [0009](docs/adr/0009-dns-and-tls.md) |
| Delivery | Argo CD, app-of-apps | [0006](docs/adr/0006-gitops-argo-cd-app-of-apps.md) |
| Secrets | Sealed Secrets | [0007](docs/adr/0007-secrets-sealed-secrets.md) |
| Database | DigitalOcean Managed Postgres with pgvector; auth on Supabase | [0008](docs/adr/0008-postgres-do-managed.md) |
| Telemetry | Grafana Alloy → Grafana Cloud, with alerts and an external probe | [0010](docs/adr/0010-observability-grafana-cloud.md) |

## Layout

```
terraform/
  bootstrap/    # the state bucket — local state, applied once by hand
  platform/     # project, VPC, DOKS, DNS, managed Postgres, firewall
  argocd/       # Argo CD, and the single root Application
  grafana/      # alert rules, dashboards, the external probe
gitops/
  root/         # app-of-apps root: two child Applications
  platform/     # cert-manager, Sealed Secrets, the shared Gateway, Alloy
  apps/         # one directory per application
docs/
  adr/                    # architecture decision records
  rebuild.md              # what survives a rebuild, and what it costs
  supabase-keepalive.md   # keeping the free auth project from pausing
```

Terraform's responsibility stops at the root Application. Everything past that
point reconciles from `gitops/`, which is why adding a platform add-on or an
application needs no Terraform and no cloud credentials
([0006](docs/adr/0006-gitops-argo-cd-app-of-apps.md)).

## How a change ships

`check` on every pull request, `apply` on merge to `main`.

**Two workflows, so the boundary is structural rather than conditional.**
`check.yml` declares no secrets and no environment; `terraform.yml` has no
pull-request trigger at all. "Nothing a pull request can trigger can change
anything" is therefore visible in the file list rather than in an `if:`
condition — which matters on a public repository, where anyone can open one.

`check` validates every stack (`fmt`, `init -backend=false`, `validate`) and
every manifest Argo CD syncs (`kubeconform`, strict, CRDs included). It needs no
credentials, so it is also what is safe on a pull request from a fork. It is the
required status check.

**CI does not plan** ([0015](docs/adr/0015-plan-locally.md)). It used to plan
`platform` and nothing else — a gate over a third of the infrastructure that
read like a gate over all of it. Planning is a local step now:

```bash
direnv allow
tofu -chdir=terraform/platform plan -lock=false
tofu -chdir=terraform/argocd   plan -lock=false
tofu -chdir=terraform/grafana  plan -lock=false
```

The cost is stated rather than hidden: this is a habit, and nothing fails if you
skip it.

**Apply is one step per stack, in dependency order** — not a matrix. The stacks
are a chain: `argocd` reads the cluster `platform` creates. A matrix asserts
independence it does not enforce. `terraform/bootstrap` is excluded entirely; it
needs the full-access Spaces key, which is kept out of CI.

Dependency updates come from Renovate, running as a workflow rather than the
hosted app. Its reasoning, and the four permissions it turned out to need, are
in [`.github/workflows/renovate.yml`](.github/workflows/renovate.yml).

## Credentials

One environment, `production`, holding everything that can change something: the
DigitalOcean write token, `readwrite` on the state bucket, and the Grafana
tokens. It requires a reviewer.

`.envrc.example` lists what a local operator needs and, for each, why it is
scoped the way it is. Nothing in CI holds a credential that a pull request can
reach.

## Decisions

Every significant choice is in [`docs/adr/`](docs/adr/README.md), with the
alternatives that were rejected and the reason. They are append-only:
superseded, not edited, so the record includes the times a decision turned out
to be wrong.

Two shape everything else —
[0012](docs/adr/0012-treat-the-repository-as-publishable.md), which forbids any
design that depends on this repository staying private, and
[0007](docs/adr/0007-secrets-sealed-secrets.md), whose rule that a sealed value
is never its own only copy is what makes losing the cluster survivable.

## Reading it

[`docs/reading-guide.md`](docs/reading-guide.md) — how this was built, including
how much of it was written by an AI agent and what that changed, with pull
requests worth reading if you are evaluating the work rather than running it.

## Status

Live and serving. Build-out is tracked in
[issues](https://github.com/shogotsuneto/heptapedal-infra/issues) grouped into
[milestones](https://github.com/shogotsuneto/heptapedal-infra/milestones);
phases 1 through 5 are complete apart from one console setting.
