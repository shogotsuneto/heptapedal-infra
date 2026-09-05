# gitops

What Argo CD reconciles. Terraform's responsibility inside the cluster ends at
one root Application; everything here arrives through git
([ADR 0006](../docs/adr/0006-gitops-argo-cd-app-of-apps.md)).

```
root/         two child Applications — the only thing the root Application syncs
platform/     add-ons every cluster gets: Sealed Secrets, cert-manager, the
              shared Gateway, Alloy
apps/         one directory per application
```

## Ordering

`root/` carries sync waves, so the tree comes up in dependency order:

| Wave | Application | Why |
|---|---|---|
| 0 | `platform` | certificates and a Gateway must exist first |
| 1 | `apps` | an application with nothing to route to it is not useful |

Argo CD assesses an Application's health, so wave 1 does not start until the
platform Application reports Healthy — not merely until it has been created.

Ordering *within* the platform bundle is the bundle's own business, expressed
with waves on its members: namespaces, then Sealed Secrets, then the values it
decrypts, then cert-manager, then the Gateway.

## Secrets

Encrypted `SealedSecret` manifests are committed here, alongside whatever
consumes them ([ADR 0007](../docs/adr/0007-secrets-sealed-secrets.md)). The
controller runs in `kube-system` as `sealed-secrets-controller` — kubeseal's
defaults — so sealing needs no flags:

```bash
kubectl create secret generic NAME -n NAMESPACE \
  --dry-run=client -o yaml --from-literal=key=value \
  | kubeseal --format yaml \
  | kubectl annotate --local -f - -o yaml \
      argocd.argoproj.io/sync-wave=1 \
      argocd.argoproj.io/sync-options=SkipDryRunOnMissingResource=true \
  > gitops/.../NAME.yaml
```

Annotate **after** `kubeseal`: doing it before puts the annotations in
`spec.template`, where they apply to the decrypted Secret rather than to the
`SealedSecret` Argo CD is scheduling.

Anything the *decrypted* Secret needs takes the opposite route — add it before
`kubeseal`, which copies the input's metadata into `spec.template`. Argo CD's
repository credentials are found by such a label, so `ghcr-registry` below is
labelled first and annotated after.

Both annotations are required. The wave keeps sealed values ahead of what
consumes them. `SkipDryRunOnMissingResource` matters only on a cluster built
from nothing, where Argo CD validates every task before any wave runs — so the
`SealedSecret` is checked against a CRD the wave-0 controller has not installed
yet, and the bundle fails validation before wave 0 can run.

Default scoping binds each ciphertext to one namespace **and** name, so the
`-n` and `NAME` above are part of what is encrypted: renaming either means
resealing.

Two rules carry over from the ADR:

- **The ciphertext is never a value's only copy.** Every sealed value is
  retrievable or reissuable from the service that owns it; anything without such
  a home gets one *before* it is sealed. The table below is where that home is
  written down — the files say *what* to reseal, not *where the value comes
  from*.
- **The sealing keys are not backed up.** Losing them costs a re-seal, not data
  — which is only true while the rule above holds.

### Where each value comes from

| Sealed Secret | Namespace / name | Value from |
|---|---|---|
| `platform/cert-manager-do-token.sealed.yaml` | `cert-manager` / `digitalocean-dns` | DigitalOcean → API → Tokens. Scoped to `domain:read`, `domain:create`, `domain:delete` — see [platform/README](platform/README.md#its-digitalocean-token) |
| `platform/grafana-cloud.sealed.yaml` | `monitoring` / `grafana-cloud` | Grafana Cloud's Kubernetes Monitoring configuration wizard, which emits both instance IDs and mints the token — see [platform/README](platform/README.md#telemetry) |
| `platform/ghcr-registry.sealed.yaml` | `argocd` / `ghcr-charts` | GitHub → Settings → Developer settings → Tokens (classic), `read:packages` — see [platform/README](platform/README.md#the-ghcr-registry-credential) |
| `apps/heptapedal/app-secrets.sealed.yaml` | `hepta` / `app-secrets` | `DATABASE_URL` from `tofu -chdir=terraform/platform output -raw database_url`; the Supabase values from the Supabase console — see [apps/README](apps/README.md#sealing-it) |

Every `SealedSecret` committed here gets a row. A row without a recoverable
source is the invariant being broken.

### What a rebuilt cluster does

A new cluster has new sealing keys, so every `SealedSecret` in this repository
becomes undecryptable at once. That is handled, not merely survived.

Argo CD assesses `SealedSecret` health: the controller sets `Synced=False` when
it cannot decrypt, which Argo CD reports as **Degraded** with the controller's
own message. Because the sealed values sit in their own sync wave, ahead of
everything that consumes them, the wave never completes and **nothing after it
deploys at all**.

#### Where that behaviour comes from

It needs no configuration, contrary to a common assumption — but the chain has
two halves, and reading only the Argo CD half does not explain it. Links pinned
to the versions actually deployed.

**1. The controller writes the condition.** On a failed unseal it sets `Synced`
to `False` with the error as the message:

```go
} else {
    status = corev1.ConditionFalse
    cond.Message = unsealError.Error()
}
```

[`updateSealedSecretStatus`, sealed-secrets v0.39.1](https://github.com/bitnami-labs/sealed-secrets/blob/v0.39.1/pkg/controller/controller.go)
· [`Synced` condition type](https://github.com/bitnami-labs/sealed-secrets/blob/v0.39.1/pkg/apis/sealedsecrets/v1alpha1/types.go)

That is gated on `--update-status`, which
[defaults to true](https://github.com/bitnami-labs/sealed-secrets/blob/v0.39.1/cmd/controller/main.go)
("stable; enabled by default since v0.17.0"). The chart's `updateStatus` is set
explicitly in `platform/sealed-secrets.yaml` rather than left to that default,
because turning it off would silently cost the Degraded signal.

**2. Argo CD reads it**, through a check bundled in its binary rather than
configured:

[`bitnami.com/SealedSecret/health.lua`, Argo CD v3.5.2](https://github.com/argoproj/argo-cd/blob/v3.5.2/resource_customizations/bitnami.com/SealedSecret/health.lua)
· [its tests](https://github.com/argoproj/argo-cd/blob/v3.5.2/resource_customizations/bitnami.com/SealedSecret/health_test.yaml)
— which assert the Degraded case with `no key could decrypt secret`, so this
behaviour is fixed upstream rather than incidental.

Bundled, not configured:
[`//go:embed all:*`](https://github.com/argoproj/argo-cd/blob/v3.5.2/resource_customizations/embed.go)
and [`GetHealthScript`](https://github.com/argoproj/argo-cd/blob/v3.5.2/util/lua/lua.go),
which consults `argocd-cm` first and falls back to the bundled script "if not
found in the ResourceOverrides at all". The ConfigMap *overrides* a bundled
check; it does not enable one.

Note the embedding means there is no file to find on the pod — only source, or
behaviour.

**Checking it on the cluster instead:** `argocd-cm` here defines no
`resource.customizations` at all, and a `SealedSecret` still reports health in
`argocd app get platform`. Corrupting one temporarily flips it to Degraded with
the controller's message — both halves of the chain in one observation.

So a rebuild stops exactly where a human is needed, naming each secret that
needs attention — rather than bringing up a platform whose pieces quietly do not
work.

**Do not clear the stale `SealedSecret`s before rebuilding.** They are doing two
jobs: they are the list of what must be resealed, and they are the gate that
stops a half-working platform from coming up. Removing them removes the gate and
leaves each consumer to fail in its own way — a missing Secret surfaces as a Pod
stuck on `CreateContainerConfigError`, or a controller that starts cleanly and
silently cannot do its work.

Reseal each file in place — same namespace, same name, so the scoping still
matches — commit, and the stall clears itself.

## Adding to it

A platform add-on is a file in `platform/`. An application is a directory in
`apps/`. Neither needs a Terraform change, and neither needs cloud credentials —
which is most of the point.

Both directories sync with `recurse: true`, so subdirectories are picked up
without editing the parent.
