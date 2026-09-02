# platform

Add-ons every cluster gets, each an Argo CD `Application` ordered by
`argocd.argoproj.io/sync-wave`.

| Wave | Contents | Status |
|---|---|---|
| -1 | namespaces the bundle installs into | in |
| 0 | Sealed Secrets controller | in |
| 1 | every `SealedSecret` this bundle needs | with each add-on |
| 2 | cert-manager; Grafana Alloy | in, #15 |
| 3 | `ClusterIssuer`s, the `gateway` namespace, the wildcard `Certificate` | in |
| 4 | Envoy Gateway and the shared `Gateway` | #13 |

The waves follow real dependencies, not tidiness:

- **Namespaces before anything that goes in one.** Declared rather than left to
  each Application's `CreateNamespace=true`, which creates the namespace during
  *that* Application's sync — too late for a resource scheduled earlier. The
  cert-manager token is a wave-1 `SealedSecret` in `cert-manager`, and the
  Application that would have created that namespace runs at wave 2: wave 1
  fails, wave 2 never starts, and the bundle deadlocks on `namespaces
  "cert-manager" not found`. A namespace is a dependency like any other.
- **Controller first**, because a `SealedSecret` cannot be decrypted before it
  runs, and its CRD has to exist to be applied at all.
- **Sealed values in a wave of their own**, ahead of everything that consumes
  them. Sharing a wave with a consumer would race — and on a rebuild, where
  every seal is stale, this is the wave that stops the bundle rather than
  letting broken components deploy. See
  [the rebuild note](../README.md#what-a-rebuilt-cluster-does).
- **Issuers after cert-manager**, because their CRDs arrive with it. Those
  resources carry `SkipDryRunOnMissingResource=true` so Argo CD does not fail
  validating a kind it has not seen yet on a cluster built from nothing.
- **Envoy Gateway last**, because the shared `Gateway` references a certificate
  cert-manager has to have issued.

Argo CD assesses each Application's health, so a wave waits for the previous one
to be Healthy rather than merely created.

## cert-manager

### Its DigitalOcean token

DNS-01 needs a token that can write records. **Not the Terraform token** — this
one lives in the cluster, so it gets only what solving a challenge requires:

```
domain:read  domain:create  domain:delete
```

cert-manager adds a `_acme-challenge` TXT record and removes it afterwards. If a
challenge fails with a 403, add `domain:update` — whether record writes count as
updating the parent domain is not something DigitalOcean's scope documentation
settles.

Seal it. Note the order: annotate **after** `kubeseal`, or the sync wave lands
in `spec.template` and applies to the Secret rather than to the `SealedSecret`
Argo CD is scheduling.

```bash
kubectl create secret generic digitalocean-dns -n cert-manager \
  --dry-run=client -o yaml --from-literal=access-token="$DO_DNS_TOKEN" \
  | kubeseal --format yaml \
  | kubectl annotate --local -f - -o yaml argocd.argoproj.io/sync-wave=1 \
  > gitops/platform/cert-manager-do-token.sealed.yaml
```

Commit that file. The name and namespace are part of what is sealed, so
`digitalocean-dns` in `cert-manager` has to match what the `ClusterIssuer`s
reference.

**Why `cert-manager` and not the issuer's namespace** — a `ClusterIssuer` has no
namespace, so cert-manager reads solver credentials from its *cluster resource
namespace*. Two values are in play and they disagree: the binary defaults
`--cluster-resource-namespace` to `kube-system`, while the chart passes
`--cluster-resource-namespace=$(POD_NAMESPACE)`, which resolves to wherever
cert-manager is installed. Reading only the source would put this Secret in the
wrong place. If issuance fails with `error getting digitalocean token`, this is
the thing to check.

**DigitalOcean is a built-in solver**, not a webhook — `digitalocean` is a field
on `ACMEChallengeSolverDNS01` alongside Route53, Cloudflare and the rest, with
its implementation shipped in cert-manager. Nothing extra to deploy. A provider
outside that list, such as Namecheap, would have needed the `webhook` solver and
a webhook deployment of its own — a quiet argument for having moved DNS to
DigitalOcean in [ADR 0009](../../docs/adr/0009-dns-and-tls.md).

The scopes above come from what the solver actually calls: `Domains.CreateRecord`
to place the `_acme-challenge` TXT record, a list to find it again, and
`Domains.DeleteRecord` to remove it.

### Staging first, then production

The `Certificate` points at `letsencrypt-staging`. Production counts **failures**
against a limit of five duplicate certificates per week, so debugging against it
is how a week's quota disappears.

Once staging issues cleanly:

```bash
kubectl -n gateway get certificate heptapedal-wildcard
# READY should be True

kubectl -n gateway describe certificate heptapedal-wildcard
# the events narrate the DNS-01 challenge, which is where a token scope
# problem shows up
```

then change `issuerRef.name` to `letsencrypt-production` in
`gateway-certificate.yaml` and commit. cert-manager reissues; the Secret keeps
its name, so nothing downstream changes.

**Done** — the certificate is issued by production. The staging issuer stays
declared, because it is where to point anything whose issuance is not yet
proven. Reach for it whenever the DNS names, the solver or the token change.

Confirm which one signed the live certificate:

```bash
kubectl -n gateway get secret heptapedal-wildcard-tls \
  -o jsonpath='{.data.tls\.crt}' | base64 -d \
  | openssl x509 -noout -issuer -dates
```

`(STAGING)` anywhere in the issuer means it is still the untrusted root, which
proves the pipeline and cannot serve traffic.
