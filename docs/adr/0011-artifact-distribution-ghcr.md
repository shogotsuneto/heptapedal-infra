# 0011. Keep GHCR packages private for now

- **Status:** Accepted
- **Date:** 2026-08-29

## Context

The application repository already publishes to GHCR: the container image
`ghcr.io/shogotsuneto/heptapedal-app` and the OCI Helm chart
`ghcr.io/shogotsuneto/charts/heptapedal-app` (likewise for the embeddings
component). The application repository is private, and so are the packages.

Package visibility is independent of the visibility of *either* repository: this
infrastructure repository may become public ([0012](0012-treat-the-repository-as-publishable.md))
while the packages and the application source stay private, and that combination
works — the credentials that reach them are sealed, not committed in the clear.

Private packages mean two credentials in the cluster:

1. An `imagePullSecret` so nodes can pull the images.
2. A registry credential for Argo CD, so it can pull the private OCI charts.

Making the packages public removes both. It would also make the build artifacts
publicly inspectable — arguably a plus for a portfolio, and independent of whether
the source stays private.

## Decision

**Keep the packages private for now.** Provision both credentials from a single
GitHub PAT with `read:packages`, stored as a Sealed Secret
([0007](0007-secrets-sealed-secrets.md)).

Revisit during or after application onboarding. The decision is deliberately
reversible and expected to be re-examined; publishing later is a visibility toggle
plus deleting two secrets.

Independently of visibility: **production pins immutable versions.** The publish
workflow emits both a sha-pinned chart (`0.1.0-dev.<sha>`) and a moving `0.1.0-dev`
pointer. Production references the sha-pinned one; upgrades arrive as Renovate
pull requests.

## Consequences

- Nothing about the current repository visibility has to change to make progress.
- Two credentials to create, seal, and eventually rotate — the concrete cost of
  this choice, and the thing to weigh when revisiting.
- A single PAT is a single point of failure and needs an expiry policy. Prefer a
  fine-grained token scoped to the packages.
- The credentials are a real bootstrap ordering constraint: Argo CD cannot render
  the application chart until its registry credential exists. That ordering belongs
  in the onboarding phase, not discovered during it.
- Immutable version pinning means a deploy is always a reviewable diff, and
  rollback is reverting a commit.

## Alternatives considered

- **Make the packages public.** Removes both credentials, makes artifacts
  inspectable, and is orthogonal to whether either repository is public. Not
  rejected on merit — deferred, to avoid bundling a visibility decision into the
  initial build-out. The most likely future change, and the natural companion to
  publishing this repository.
- **DigitalOcean Container Registry.** Would put images in the same account and
  integrate with DOKS's pull-secret provisioning. Rejected: the publish pipeline
  already targets GHCR, the free tier is one repository, and it would split
  artifacts across two registries.
- **Track the moving `-dev` tag in production.** Rejected: no reproducibility, no
  rollback, and no review step.
