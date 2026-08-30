# 0001. Keep Terraform and GitOps manifests in one repository

- **Status:** Accepted
- **Date:** 2026-08-29

## Context

Three kinds of artifact need a home:

1. Terraform/OpenTofu for the cloud substrate (project, VPC, DOKS, DNS, database).
2. Argo CD `Application` manifests and production values for the platform add-ons
   and the applications.
3. The application Helm charts themselves — which already exist, in the
   application repository, and are published to GHCR as OCI charts.

(3) is settled: charts ship from `heptapedal/deploy/charts` and are consumed by
reference. That leaves the question of whether (1) and (2) share a repository.

The conventional GitOps advice is to split them: Argo CD watches a repository it
can be given narrow read access to, and Terraform CI (which holds cloud
credentials) lives elsewhere. That reasoning is about blast radius across a team.
Here there is one operator, and the manifest set in (2) is small — the charts live
elsewhere, so it is a handful of `Application` objects and their values files.

The read-access half of that argument does not apply here at all, in either
direction: under [0012](0012-treat-the-repository-as-publishable.md) neither
directory contains anything that read access could compromise. Credentials and
state live outside git by rule, not by repository setting. So the question reduces
to workflow ergonomics rather than isolation.

## Decision

One repository, two top-level directories:

```
terraform/    # bootstrap/ platform/ argocd/
gitops/       # root/ platform/ apps/
docs/adr/
```

CI is scoped by path filter: changes under `terraform/**` run plan/apply; Argo CD
watches `gitops/**` only.

Revisit if a second operator joins, or if a cluster ever needs read access to the
manifests without read access to the Terraform.

## Consequences

- One clone, one PR, for changes that genuinely span both layers (adding an app
  means a DNS record *and* an `Application`).
- Argo CD reads the Terraform source as well as the manifests. This is not a
  concern: the Terraform holds no secret material, by the rule in
  [0012](0012-treat-the-repository-as-publishable.md) rather than by convention.
  If the repository is ever made public, Argo CD needs no git credential at all —
  co-location gets *simpler*, not riskier.
- CI is the one place co-location has a real cost, and it is a public-repository
  cost: a workflow that holds cloud credentials sits in the same repository that
  accepts pull requests. Handled in [0012](0012-treat-the-repository-as-publishable.md)
  clause 5 — privileged workflows never run against a fork's code.
- Splitting later is cheap — `git filter-repo` on `gitops/`, then repoint Argo CD.
  Nothing in the design assumes co-location.

## Alternatives considered

- **Three repositories** (app / infra / gitops). The textbook layout, and the
  original plan. Rejected for now: at this size the cross-repo PR choreography
  costs more than the isolation buys. Recorded as the expected end state if the
  project grows.
- **Everything including charts in one repo.** Rejected — the charts are already
  published as versioned OCI artifacts, which is strictly better than path
  references: production pins an immutable version instead of tracking a branch.
