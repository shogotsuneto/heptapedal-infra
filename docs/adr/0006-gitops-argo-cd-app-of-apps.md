# 0006. Deliver with Argo CD using the app-of-apps pattern

- **Status:** Accepted
- **Date:** 2026-08-29

## Context

Two layers need continuous delivery: platform add-ons (cert-manager, Envoy
Gateway, Sealed Secrets, the telemetry collector) and applications (heptapedal
today, a voice-agent service later).

Terraform can install Helm releases via `helm_release`, so it *could* do all of
it. But then cluster state drifts silently between applies, there is no
reconciliation loop, and every application change requires cloud credentials.

Within Argo CD, the choice is app-of-apps versus ApplicationSet. As of the 2026
Argo CD user survey, app-of-apps remains in production use by ~82% of respondents.
It gives explicit, hand-curated ordering; ApplicationSet generates fleets from a
generator but was never designed to order what it generates.

## Decision

**Argo CD, bootstrapped by Terraform, then self-governing.**

The boundary is sharp and deliberate:

- Terraform owns the substrate *and* installs Argo CD itself (`helm_release`) plus
  **exactly one** root `Application`. Then Terraform's job in the cluster is done.
- The root Application points at `gitops/root/`, which declares child Applications
  for `gitops/platform/*` and `gitops/apps/*`. Everything else flows from there.
- Sync waves order the platform bundle: CRDs and cert-manager before Envoy Gateway
  before applications.
- Applications reference the **OCI charts published to GHCR** by the application
  repository, pinned to an immutable version — never the moving `-dev` tag.

Migrate to ApplicationSet (git directory generator) when the application count
passes roughly a dozen, not before.

## Consequences

- One reconciliation loop and one UI showing what is actually running.
- Cloud credentials are needed only for substrate changes. Deploying an
  application is a pull request against YAML.
- The two-stage bootstrap is a genuine ordering constraint and has to be
  documented, not just implemented: cluster → Argo CD → root app → everything.
- Argo CD is itself a workload on a small cluster (~1Gi with defaults). Its Helm
  values get trimmed — no HA, notifications and ApplicationSet controllers only if
  used. Budgeted for in [0004](0004-kubernetes-on-doks.md).
- Argo CD needs a GHCR credential to pull the private OCI charts — see
  [0011](0011-artifact-distribution-ghcr.md).
- Helm hooks work under Argo CD: `heptapedal-app`'s `pre-install`/`pre-upgrade`
  migration Job maps to the PreSync phase. It needs an explicit
  `hook-delete-policy`, or the second sync fails on a duplicate Job name.

## Alternatives considered

- **Flux.** Smaller footprint and a tighter blast radius (a dead controller does
  not stop reconciliation) — a real argument on a 4Gi-per-node cluster. Rejected:
  Argo CD's UI is worth disproportionately much for a single operator and for
  demonstrating the system to someone else, and it is the more commonly requested
  of the two.
- **ApplicationSet from the start.** Rejected: it solves toil this project does
  not have yet, and does not solve the ordering this project does have.
- **Terraform `helm_release` for everything.** Rejected: no drift detection, no
  reconciliation, and it puts cloud credentials in the path of every deploy.
