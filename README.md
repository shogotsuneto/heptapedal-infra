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

`check` on every pull request, `apply` on merge to `main`. **Planning is a local
step, not a CI one** ([ADR 0015](docs/adr/0015-plan-locally.md)).
`terraform/bootstrap` is excluded from apply too: it needs the full-access
Spaces key, which is deliberately kept out of CI.

**Merging applies.** GitHub reserves environment protection rules — required
reviewers, wait timers — for public repositories on this plan, so while this
repository is private there is no approval step between merge and apply.
Merging is the deliberate act. Turning the reviewer on is part of going public
(#28).

### Review a change by planning it

Before merging anything under `terraform/`, plan the stacks it touches:

```bash
direnv allow                      # or: set -a; . ./.envrc; set +a
tofu -chdir=terraform/platform plan -lock=false
tofu -chdir=terraform/argocd   plan -lock=false
tofu -chdir=terraform/grafana  plan -lock=false
```

`-lock=false` because a plan does not write state, and taking the lock would
write a lock object for nothing.

This used to run in CI for `platform`, and only `platform` — `argocd` needs an
administrator kubeconfig and `grafana` a second token, neither of which belongs
in a workflow anyone can trigger. A gate over one stack that reads like a gate
over all of them is worse than no gate, so it was removed rather than extended
([ADR 0015](docs/adr/0015-plan-locally.md)). The cost is that this is a habit
rather than a check: nothing fails if you skip it.

### Setting it up

One environment, holding the credentials that can change things:

| Environment | Runs | Holds | Protection |
|---|---|---|---|
| `production` | merges to `main` | the write DigitalOcean token, `readwrite` on the state bucket, the Grafana tokens | `main` only (reviewer when public) |

**No workflow that a pull request can trigger holds any infrastructure
credential.** `check` needs none, so it is also the part that is safe on a pull
request from a fork. That is simpler than the read-only `plan` environment it
replaces, and it is the same guarantee without a second set of tokens to keep
narrow.

The Renovate workflow needs no secret at all. It runs on `GITHUB_TOKEN`, which
reaches GitHub and nothing else, and its pull requests arrive with `check`
**held for approval** — the documented exception to GITHUB_TOKEN raising no
events. One click per pull request, in exchange for not keeping a credential
that can write to this repository.

That token cannot write files under `.github/workflows/`, and no permission
exists to let it: the `permissions:` block has no `workflows` scope. So **action
versions are bumped by hand.** Renovate still watches them and lists them on its
dependency dashboard; it just never opens the pull request. Do not approve one
from the dashboard — it would try, and fail. Edit the version, and the entry
clears itself on the next run.

Three actions are in scope, which is why this is a reasonable trade rather than
a hole. If that number grows, a GitHub App token can carry `workflows` without a
long-lived secret, and that is the thing to reach for.

`check` runs `fmt` and `init -backend=false && validate` over **every** stack,
including `bootstrap`, which CI never applies. It needs no secrets, so it is
also the part that is safe on a pull request from a fork.

Apply is a single job with one **step per stack, in dependency order** — not a
matrix. The stacks are a chain rather than a set: `argocd` reads the cluster
`platform` creates. A matrix asserts independence, does not guarantee ordering,
and with `fail-fast` disabled would apply `argocd` against a cluster whose own
apply had just failed. Steps run in file order and stop at the first failure. A
new stack is a new step, placed by what it depends on. The `plan` job takes its environment
with `deployment: false`, so it gets the secrets without recording a deployment
— planning is not deploying, and the environment history stays a list of things
that actually changed. `plan` runs with `-lock=false` so the
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
