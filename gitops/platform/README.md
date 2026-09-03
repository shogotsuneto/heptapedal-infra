# platform

Add-ons every cluster gets, each an Argo CD `Application` ordered by
`argocd.argoproj.io/sync-wave`.

| Wave | Contents | Status |
|---|---|---|
| -1 | namespaces the bundle installs into | in |
| 0 | Sealed Secrets controller | in |
| 1 | every `SealedSecret` this bundle needs | with each add-on |
| 2 | cert-manager; Grafana Alloy | in |
| 3 | `ClusterIssuer`s and the wildcard `Certificate` | in |
| 4 | the shared `Gateway` and the HTTPS redirect | in |

The waves follow real dependencies, not tidiness:

- **Namespaces before anything that goes in one.** Declared rather than left to
  each Application's `CreateNamespace=true`, which creates the namespace during
  *that* Application's sync — too late for a resource scheduled earlier. A
  namespace is a dependency like any other.
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
- **The Gateway last**, because its listeners serve a certificate cert-manager
  has to have issued.

Argo CD assesses each Application's health, so a wave waits for the previous one
to be Healthy rather than merely created.

## The Gateway

One entry point; each application attaches its own `HTTPRoute` from its own
namespace, which `allowedRoutes.namespaces.from: All` is what permits
([ADR 0005](../../docs/adr/0005-gateway-api-envoy-gateway.md)).

**The implementation is DigitalOcean's** — the `cilium` GatewayClass, running
before anything here is deployed ([ADR 0014](../../docs/adr/0014-use-the-provider-gateway-implementation.md)).
Nothing in this bundle installs a controller or owns Gateway API CRDs.

```bash
kubectl get gatewayclass                     # cilium, Accepted
kubectl -n gateway get gateway heptapedal    # PROGRAMMED, and its address
```

**Load balancer settings live in `spec.infrastructure.annotations`**, which
Gateway API caps at eight entries. The idle timeout there is probably
ineffective — the balancer carries TLS-terminated traffic as plain TCP, and
DigitalOcean documents the annotation only for HTTP — and is kept for the cost
of a line. #20's end-to-end test decides it; if MCP sessions drop, the lever is
application-side keepalives.

Two HTTPS listeners, apex and wildcard, rather than one without a hostname: a
hostname-less listener would serve this certificate for arbitrary SNI.

Nothing resolves here yet — the apex `A` record is #20.

## Telemetry

Alloy ships metrics, logs and Kubernetes events to Grafana Cloud
([ADR 0010](../../docs/adr/0010-observability-grafana-cloud.md)). Nothing is
stored in the cluster, so dashboards and history survive a rebuild — which is
also why there is no metrics-server here and `kubectl top` does not work.

**Getting the credentials.** Activate the Kubernetes Monitoring app in Grafana
Cloud, then run its configuration wizard — but do not apply what it generates.
This repository already has the Application; the wizard is only the reliable way
to read off the right values, since it emits a `k8s-monitoring` configuration
containing your stack's endpoints and instance IDs and mints a token for them.

Activation matters on its own: it is what installs the Kubernetes dashboards,
which is most of why this chart was chosen over a hand-written Alloy config.

**Decline the managed discovery pipeline** the wizard offers. That is Fleet
Management: Grafana Cloud pushing collector configuration remotely, which Alloy
polls for and applies. It would be a second source of truth for what
`alloy.yaml` already decides — living outside git, outside review, and not
reproduced by a cluster rebuild. The values here do not opt in, and the rendered
output contains no `remotecfg` block.

Take from the wizard the two endpoint URLs, the two numeric usernames, and the
token.
The URLs go into `alloy.yaml` — they are endpoints, not secrets. The rest is
sealed:

The endpoint URLs are already in `alloy.yaml`. The instance IDs go in the secret
rather than beside them — not because they are sensitive, but because with an
existing secret this chart reads username *and* password from it and ignores a
literal `username:` in the values.

```bash
kubectl create secret generic grafana-cloud -n monitoring \
  --dry-run=client -o yaml \
  --from-literal=prometheus-username=3558878 \
  --from-literal=loki-username=1775114 \
  --from-literal=access-token="$GC_TOKEN" \
  | kubeseal --format yaml \
  | kubectl annotate --local -f - -o yaml \
      argocd.argoproj.io/sync-wave=1 \
      argocd.argoproj.io/sync-options=SkipDryRunOnMissingResource=true \
  > gitops/platform/grafana-cloud.sealed.yaml
```

One token serves both endpoints.

**Not the wizard's token.** The Kubernetes Monitoring wizard configures Fleet
Management, so what it mints is a fleet-management credential and it emits no
destinations at all — which is why it shows a single user ID that belongs to
neither Prometheus nor Loki. Create an access policy token with write scopes for
metrics and logs instead: Cloud Portal → Access Policies.

If the scopes are wrong the failure appears in the Alloy logs and nowhere in
Grafana Cloud.

The chart also renders `ca_pem`, `cert_pem` and `key_pem` reading `ca`, `cert`
and `key` from this secret. Leaving them out is correct and is what the chart's
own external-secrets example does: a missing key reads as empty, and Alloy
treats empty TLS fields as unset.

**What it costs.** 375m CPU and 576Mi requested across five components: the
Alloy DaemonSet for logs, a StatefulSet for metrics, a singleton for events,
kube-state-metrics, and the Alloy operator. The chart sets requests on only two
of those, so the rest are set here — without them they would be BestEffort and
first to be evicted under memory pressure.

**It is free, and the margin is measurable.** Grafana Cloud bills Kubernetes
Monitoring as its own dimension — active host hours and container hours — and
the free tier includes 2,232 and 37,944 per month. Enabling it does start
metering, which is what the warning in the console means; it does not start
charging until those are exceeded.

| | projected | allowance | |
|---|---|---|---|
| host hours | 1,460 | 2,232 | 65% |
| container hours | 27,156 | 37,944 | 72% |
| active series | 4,440 | 10,000 | 44% |
| container hours, once the application lands | 29,346 | 37,944 | 77% |

**Init containers are not billed.** That was the open question, and the answer
straddled the allowance — 73% counting only running containers, 102% counting
init containers as well, which the Kubernetes Overview dashboard does.

Settled by arithmetic on the metered figures rather than by argument: 5 host
hours across two nodes is 2.5 hours elapsed, and 93 container hours over 2.5
hours is 37.2 containers. The cluster runs 38, with 15 init containers beside
them. 37.2 is the former — a little under, because the Alloy pods started after
the rest.

Worth re-reading over a longer window, and again once the application lands, but
the shape is settled.

**Host hours effectively cap this cluster at two nodes.** A third would reach
2,190 of 2,232 — 98%, before any margin for a surge upgrade. Growing the node
pool therefore moves two budgets, not one: the 24 USD/month in
[ADR 0004](../../docs/adr/0004-kubernetes-on-doks.md) and this allowance. Neither
ADR noticed it was constraining the other.

**The series count has room.** 4,440 of the 10k allowance, against a worry that
cAdvisor plus kube-state-metrics might approach it. No trimming needed for now.

The lever is `metricsTuning.includeMetrics` / `excludeMetrics`, per source,
under `clusterMetrics` — and `excludeNamespaces` for logs. These filter at the
collector, before anything is sent, so they cut egress and collector CPU as well
as the series count. Nothing about them is server-side: the wizard's "advanced
tuning" screens only write these same values into the file it generates, which
this repository does not use.

Deploy with the defaults, read the actual series count in Grafana Cloud, and
trim from there. Trimming first means dropping metrics without knowing which
were load-bearing.

## cert-manager

### Its DigitalOcean token

DNS-01 needs a token that can write records. **Not the Terraform token** — this
one lives in the cluster, and gets only what solving a challenge requires.

```
domain:read  domain:create  domain:delete
```

**Established, not inferred.** A token without `domain:update` completed a DNS-01
challenge end to end against `letsencrypt-staging`:

```
DomainVerified  Domain "heptapedal.com" verified with "DNS-01" validation
Order completed successfully
```

That covers everything the solver does — `Domains.CreateRecord` to place the
`_acme-challenge` TXT record, a list to find it, and `Domains.DeleteRecord` to
remove it. `domain:update` is not needed.

The staging issuer is what made the question cheap to answer: its limits are
generous, so a real challenge could be run without spending production quota.

Seal it. Note the order: annotate **after** `kubeseal`, or the sync wave lands
in `spec.template` and applies to the Secret rather than to the `SealedSecret`
Argo CD is scheduling.

```bash
kubectl create secret generic digitalocean-dns -n cert-manager \
  --dry-run=client -o yaml --from-literal=access-token="$DO_DNS_TOKEN" \
  | kubeseal --format yaml \
  | kubectl annotate --local -f - -o yaml \
      argocd.argoproj.io/sync-wave=1 \
      argocd.argoproj.io/sync-options=SkipDryRunOnMissingResource=true \
  > gitops/platform/cert-manager-do-token.sealed.yaml
```

`SkipDryRunOnMissingResource` matters only on a cluster built from nothing,
which is why it was missed. Argo CD validates every task before any wave runs,
so a `SealedSecret` is checked against a `bitnami.com/v1alpha1` that the wave-0
controller has not installed yet, and the whole bundle fails validation before
wave 0 gets to run:

```
one or more synchronization tasks are not valid: failed to discover server
resources for group version bitnami.com/v1alpha1
```

On an existing cluster the CRD is already there, so nothing complains.

**Adding it to an existing file does not require resealing.** The annotations
are metadata on the `SealedSecret`, unrelated to the encrypted payload — which
matters, because `kubeseal` fetches its public key from the controller, and the
controller is what the failing validation is blocking. Editing the file is the
only way out of that circle.

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
