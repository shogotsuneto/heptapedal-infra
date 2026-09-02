# gitops

What Argo CD reconciles. Terraform's responsibility inside the cluster ends at
one root Application; everything here arrives through git
([ADR 0006](../docs/adr/0006-gitops-argo-cd-app-of-apps.md)).

```
root/         two child Applications — the only thing the root Application syncs
platform/     add-ons every cluster gets: cert-manager, Envoy Gateway, Sealed
              Secrets, Alloy
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
with waves on its members: CRDs, then cert-manager, then Envoy Gateway.

## Secrets

Encrypted `SealedSecret` manifests are committed here, alongside whatever
consumes them ([ADR 0007](../docs/adr/0007-secrets-sealed-secrets.md)). The
controller runs in `kube-system` as `sealed-secrets-controller` — kubeseal's
defaults — so sealing needs no flags:

```bash
kubectl create secret generic NAME -n NAMESPACE \
  --dry-run=client -o yaml --from-literal=key=value \
  | kubeseal --format yaml > gitops/.../NAME.yaml
```

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
| _(none yet)_ | | |

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

> This needs no configuration, contrary to a common assumption. Argo CD's health
> checks come from two places: `resource.customizations` in `argocd-cm`, and
> scripts bundled into the binary from its `resource_customizations/` directory
> — `//go:embed all:*`. `GetHealthScript` consults the ConfigMap first and falls
> back to the bundled script "if not found in the ResourceOverrides at all", so
> the ConfigMap is for *overriding* a bundled check, not for enabling one.
> `bitnami.com/SealedSecret/health.lua` is bundled.
>
> Checkable on the cluster rather than in the source: `argocd-cm` here defines no
> `resource.customizations` at all, and a `SealedSecret` still reports a health
> status in `argocd app get platform`. Temporarily corrupting one flips it to
> Degraded with the controller's message, which is the whole mechanism in one
> observation.

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
