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
  a home gets one *before* it is sealed.
- **The sealing keys are not backed up.** Losing them costs a re-seal, not data
  — which is only true while the rule above holds. A rebuilt cluster has new
  keys, so every `SealedSecret` here must be resealed then (#24).

## Adding to it

A platform add-on is a file in `platform/`. An application is a directory in
`apps/`. Neither needs a Terraform change, and neither needs cloud credentials —
which is most of the point.

Both directories sync with `recurse: true`, so subdirectories are picked up
without editing the parent.
