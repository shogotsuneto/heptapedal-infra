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
- Secret *values* originate from the DigitalOcean, Supabase, GitHub and Grafana
  consoles and are sealed locally with `kubeseal`. They never enter Terraform
  state or CI logs.
- **The ciphertext is never a value's only copy.** Every secret here is
  retrievable or reissuable from the service that owns it. Anything that is not —
  a password generated in-cluster — gets its own home first, a password-manager
  entry is enough, and is sealed after. Give it a home, then seal it. A design
  invariant, checkable in review, rather than a duty that gets forgotten.
- Consequently the sealing keys are deliberately **not** backed up: losing them
  costs a re-seal, not data.
- Re-sealing every secret is an explicit step in the cluster rebuild runbook. A
  new cluster means a new controller and new keys, so existing `SealedSecret`
  manifests will not decrypt.

Reconsider when an external secret manager enters the architecture for another
reason — including from this side, since enough values needing their own home
amounts to one. The migration is: install ESO, point `ExternalSecret` at the same
Secret name, delete the `SealedSecret`. The application chart does not change.

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
  not weaken the encryption, but it does raise what a key compromise would cost —
  every sealed value, historical ones included, readable at once. Which is a
  second reason not to keep a backup: the fewer plaintext copies of the private
  keys exist, the fewer ways that compromise happens.
- What "the key" means in practice: the controller generates an RSA-4096 pair on
  first start and keeps it as a `kubernetes.io/tls` Secret in its namespace, then
  **generates a further pair every 30 days by default**, retaining the old ones
  for decryption. So it is a growing set, not one key — which is another thing a
  backup would have to keep chasing.
- Rotation of secret *values* is manual: re-seal and commit. Acceptable at this
  count; it is the thing ESO would fix.
- Secrets are Kubernetes-only. Nothing outside the cluster can consume them. Fine
  today; a constraint to remember.

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
- **Backing up the controller's private keys out of band.** The conventional
  advice, and the first version of this ADR. Rejected on blast radius: to protect
  a value that exists nowhere but its ciphertext, it puts *every* secret behind
  one unmanaged, unrotated plaintext copy — of keys that open ciphertext this
  repository publishes — which must also be re-taken as the controller rolls new
  keys. Giving that one value its own home instead scopes the exposure to it, and
  keeps doing so however many such values there are.
- **Plain Secrets applied by hand, outside git.** Rejected: breaks GitOps, and
  the cluster becomes unreproducible.
