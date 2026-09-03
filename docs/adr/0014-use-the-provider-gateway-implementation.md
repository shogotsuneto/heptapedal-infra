# 0014. Use DigitalOcean's Gateway API implementation

- **Status:** Accepted
- **Date:** 2026-09-03
- **Supersedes:** the implementation half of [0005](0005-gateway-api-envoy-gateway.md)

## Context

[0005](0005-gateway-api-envoy-gateway.md) made two decisions at once: route
north-south traffic through **Gateway API** rather than the retired Ingress
controller, and implement it with **Envoy Gateway**. The first stands. The
second was made without checking what the platform already had.

DOKS ships a managed Gateway API implementation backed by Cilium, enabled by
default on VPC-native clusters from Kubernetes 1.33. It was running before we
installed anything:

```
NAME         CONTROLLER                                      ACCEPTED
cilium       io.cilium/gateway-controller                    True
heptapedal   gateway.envoyproxy.io/gatewayclass-controller   False
```

DigitalOcean also installs and manages the Gateway API CRDs. Installing Envoy
Gateway meant a second implementation competing for them, which is how a CRD
ended up stranded mid-upgrade between channels and the whole bundle stopped
progressing.

0005 did consider Cilium, and got it backwards:

> **Cilium Gateway API.** Would fold in CNI and network policy. Rejected:
> replacing DOKS's CNI is a large change with a real chance of breaking the
> managed integration, for capability this cluster does not need.

There is nothing to replace. DOKS *is* running Cilium, and already exposes its
Gateway API. The rejection described work that does not exist.

## Decision

Use the `cilium` GatewayClass. Remove Envoy Gateway — its Application, its CRDs,
its control plane, its `EnvoyProxy`, and the `GatewayClass` pointing at it.

The Gateway API resources are unchanged in shape: a `Gateway` in `gateway` with
the same listeners and certificate, and `HTTPRoute`s attached from application
namespaces. Only `gatewayClassName` differs. Load balancer settings move from
`EnvoyProxy.provider.kubernetes.envoyService.annotations` to the Gateway's own
`spec.infrastructure.annotations`, which DigitalOcean documents and caps at
eight entries.

## Consequences

- **The CRD conflict disappears**, because there is only one implementation and
  the provider owns the CRDs.
- **Roughly 320Mi and 128m of requests come back** — no Envoy Gateway control
  plane, no Envoy fleet. On a cluster with about 6Gi schedulable
  ([0004](0004-kubernetes-on-doks.md)), that is not rounding.
- One less chart, namespace and upgrade path to own. DigitalOcean maintains the
  implementation and its integration with their load balancers.
- **Less tuning surface.** `EnvoyProxy` offered replica counts, resource limits
  and scheduling. Replicas and limits stop being ours to set; the load balancer
  annotations have an equivalent. Nothing we were actually using is lost.
- Data plane availability improves rather than degrades: Cilium already runs as
  a DaemonSet on every node, where our Envoy fleet was two replicas we had to
  ask for — and DigitalOcean has since moved their Gateway services from
  `externalTrafficPolicy: Local` to `Cluster`, which removes the health-check
  asymmetry that made one node appear down.
- **Portability is unaffected**, which is the point of having chosen Gateway API
  in the first place. Moving to another implementation is a `gatewayClassName`
  change plus that implementation's own parameters, not a rewrite of every
  route.
- The cluster has to be rebuilt to get out of the half-upgraded CRD state. Cheap
  now — nothing resolves to it and no application is deployed — and it exercises
  the rebuild runbook (#24), which has so far only been asserted to work.

## Alternatives considered

- **Keep Envoy Gateway, stop fighting over CRDs** by setting `crds.enabled:
  false` and letting DigitalOcean's stand. Rejected: the chart's switch is
  all-or-nothing, so Envoy Gateway's own CRDs would need a separate source, and
  the result is still two implementations where one suffices. It also leaves
  Envoy Gateway pinned against whatever Gateway API version the provider
  happens to ship.
- **Keep Envoy Gateway and disable the safe-upgrade policy.** Unblocks the
  immediate failure and keeps every underlying problem.
- **Traefik or NGINX Gateway Fabric.** Same objection as Envoy Gateway now has:
  a second implementation on a platform that already provides one.
