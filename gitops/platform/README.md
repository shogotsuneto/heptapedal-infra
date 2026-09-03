# platform

Add-ons every cluster gets, each an Argo CD `Application` ordered by
`argocd.argoproj.io/sync-wave`.

| Wave | Contents | Status |
|---|---|---|
| -1 | namespaces the bundle installs into | in |
| 0 | Sealed Secrets controller | in |
| 1 | every `SealedSecret` this bundle needs | with each add-on |
| 2 | cert-manager; Grafana Alloy | in, #15 |
| 3 | `ClusterIssuer`s and the wildcard `Certificate` | in |
| 4 | Envoy Gateway | in |
| 5 | `GatewayClass`, `EnvoyProxy`, the shared `Gateway`, the HTTPS redirect | in |

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
- **Envoy Gateway after cert-manager**, because the `Gateway` it serves
  references a certificate that has to have been issued; and the `Gateway`
  itself after Envoy Gateway, whose CRDs define it.

Argo CD assesses each Application's health, so a wave waits for the previous one
to be Healthy rather than merely created.

## The Gateway

One entry point; each application attaches its own `HTTPRoute` from its own
namespace, which `allowedRoutes.namespaces.from: All` is what permits
([ADR 0005](../../docs/adr/0005-gateway-api-envoy-gateway.md)).

**The data plane is not in `gateway`.** Envoy Gateway creates the Envoy
`Deployment` and its `LoadBalancer` `Service` in its own namespace:

```bash
kubectl -n gateway get gateway heptapedal          # the Gateway and its address
kubectl -n envoy-gateway-system get deploy,svc     # the Envoy fleet it provisioned
```

**The load balancer's idle timeout is probably ineffective**, and kept for the
cost of one line. MCP holds long-lived connections against a 60-second default,
so the `EnvoyProxy` sets `do-loadbalancer-http-idle-timeout-seconds: "600"` —
but Envoy terminates TLS, so the balancer carries plain TCP, and DOKS
provisioned it as `REGIONAL_NETWORK`, a layer-4 load balancer with no HTTP layer
to time out. #20's end-to-end test answers it; if sessions drop, the lever is
application-side keepalives.

**Gateway API CRDs come from two places.** DOKS pre-installs them — standard
channel, bundle v1.2.1 — and the Envoy Gateway chart replaces them with
experimental v1.6.1, which is what it ships. We are on experimental
deliberately; there is no toggle for the standard channel short of managing
these CRDs ourselves.

The same subchart installs a `ValidatingAdmissionPolicy`,
`safe-upgrades.gateway.networking.k8s.io`, which forbids installing experimental
CRDs over standard ones. Its rule allows creates (`oldObject == null`) and
updates where the *existing* object is already experimental — so once a CRD is
on experimental it upgrades freely, but one left on standard is stuck.

If a CRD is stranded that way, **delete it and let Argo CD recreate it**: a
create passes the policy, and the guard stays in place for the future.

```bash
kubectl get crd httproutes.gateway.networking.k8s.io \
  -o jsonpath='{.metadata.annotations.gateway\.networking\.k8s\.io/channel}{"\n"}'
kubectl delete crd httproutes.gateway.networking.k8s.io     # takes its HTTPRoutes with it
argocd app sync envoy-gateway
```

Deleting a CRD deletes every object of that kind. Check what would go first —
everything under `gitops/` is recreated by the next sync, anything else is not.

Disabling the policy through `crds.gatewayAPI.safeUpgradePolicy.enabled` would
also unblock it, at the cost of the guard, and unreliably: the policy would have
to be pruned before the CRD is applied, and both happen in one sync.

**Large CRDs need server-side apply.** The Envoy Gateway Application sets
`ServerSideApply=true` because Argo CD's default client-side apply writes the
whole manifest into an annotation with a 262144-byte limit, which several of
these CRDs exceed. Worth knowing before adding another chart with big CRDs: the
rejection names an annotation, and the symptoms appear somewhere else entirely.

Two Envoy replicas, so a node drain in the upgrade window does not take the only
ingress path with it.

Nothing resolves here yet — the apex `A` record is #20.

## cert-manager

### Its DigitalOcean token

DNS-01 needs a token that can write records. **Not the Terraform token** — this
one lives in the cluster, and gets only what solving a challenge requires.

Everything under `domain`, and nothing else. The **minimum within that is not
established**: the token in use also carries `domain:update`, so a successful
issuance does not prove `read`/`create`/`delete` alone would have sufficed.

What the solver actually calls is `Domains.CreateRecord`, a list, and
`Domains.DeleteRecord`. DigitalOcean documents `create` as covering "additive
actions" within a resource and `delete` as covering actions that remove
information from it, which points at `read`/`create`/`delete` being enough — but
that is reading the documentation's analogous examples, not a test.

To settle it cheaply, without spending production quota: issue a throwaway
`Certificate` for some other subdomain against `letsencrypt-staging`, with a
token that lacks `update`. Staging's limits are generous, and the answer is
immediate. Until then this is inference.

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
