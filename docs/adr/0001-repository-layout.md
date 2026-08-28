# 0001. Keep Terraform and GitOps manifests in one repository

- **Status:** Accepted
- **Date:** 2026-08-27

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
- Argo CD's repository credential grants read access to the Terraform source too.
  Acceptable: the Terraform contains no secret material (state and variables live
  outside git), and the repository is private.
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
