# 0007. Manage secrets with Sealed Secrets

- **Status:** Accepted
- **Date:** 2026-08-27

## Context

The application needs `DATABASE_URL`, `SUPABASE_URL`, and
`SUPABASE_PUBLISHABLE_KEY` as a Kubernetes Secret. The platform needs a GHCR pull
credential ([0011](0011-artifact-distribution-ghcr.md)) and a Grafana Cloud token
([0010](0010-observability-grafana-cloud.md)).

The application chart is already built for this: `heptapedal-app` **consumes** a
Secret by name (`secretName`) and never creates one. Provenance is a free
variable, and whatever is chosen here can be replaced later without touching the
chart.

The 2026 field splits three ways. External Secrets Operator (ESO) treats the
Kubernetes Secret as a cache in front of a real secret manager — the recommended
choice *when such a manager already exists*. SOPS (CNCF sandbox, age as a
first-class backend) encrypts files in git; with Argo CD it needs a plugin such as
KSOPS or argocd-vault-plugin. Sealed Secrets keeps encrypted manifests in git and
decrypts in-cluster with a controller.

The decisive fact: **there is no external secret manager in this architecture, and
adding one adds a service, an account, and a credential to bootstrap it.**

## Decision

**Sealed Secrets**, installed as part of the platform bundle.

- Encrypted `SealedSecret` manifests are committed under `gitops/`.
- The controller's private key is backed up out-of-band immediately after install;
  losing it means resealing every secret. The backup procedure is documented, not
  assumed.
- Secret *values* originate from the DigitalOcean and Supabase consoles and are
  sealed locally with `kubeseal`. They never enter Terraform state or CI logs.

Reconsider when an external secret manager enters the architecture for another
reason. At that point the migration is: install ESO, point `ExternalSecret` at the
same Secret name, delete the `SealedSecret`. The application chart does not change.

## Consequences

- Zero additional cost, zero additional SaaS, one additional controller.
- Works with Argo CD with no plugin and no custom sync configuration — SOPS's main
  practical cost here.
- Git remains the single source of truth, consistent with [0006](0006-gitops-argo-cd-app-of-apps.md).
- **Safe to publish.** `SealedSecret` manifests are designed to be committed to a
  public repository, which satisfies
  [0012](0012-treat-the-repository-as-publishable.md) with nothing to reconsider.
  Default strict scoping binds each ciphertext to one namespace *and* name, so it
  cannot be replayed into another cluster or another Secret even verbatim.
- The corollary: publishing hands an attacker the ciphertext offline. That does
  not weaken the encryption, but it does raise what a controller-key compromise
  would cost — every sealed value, historical ones included, becomes readable at
  once. It makes the key backup below a confidentiality control, not just an
  availability one: back it up somewhere it cannot leak, and rotate the sealing
  key on any suspicion.
- Rotation is manual: re-seal and commit. Acceptable at this secret count; it is
  the thing ESO would fix.
- Secrets are Kubernetes-only. Nothing outside the cluster can consume them. Fine
  today; a constraint to remember.
- The controller key is a single point of failure until it is backed up. This is
  the main operational risk introduced, and it is why the backup step is part of
  the phase, not an afterthought.

## Alternatives considered

- **External Secrets Operator + a free-tier manager (Infisical, Doppler, Bitwarden
  Secrets Manager).** The strongest signal of the three and the direction the
  ecosystem is moving. Rejected *for now* on the grounds that it inverts the
  dependency: it introduces a third-party service, on a free tier, as a hard
  runtime dependency of every deploy — to solve a problem this project does not
  yet have. Recorded explicitly as the intended successor.
- **SOPS + age.** Elegant, no controller, and the de-facto standard for file-level
  encryption in GitOps. Rejected on Argo CD integration friction: it requires a
  plugin, and a config-management plugin is a durable operational cost.
- **Plain Secrets applied by hand, outside git.** Rejected: breaks GitOps, and
  the cluster becomes unreproducible.
