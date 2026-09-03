# 0005. Route north-south traffic with Gateway API / Envoy Gateway

- **Status:** Accepted; the choice of Envoy Gateway is superseded by
  [0014](0014-use-the-provider-gateway-implementation.md)
- **Date:** 2026-08-29

> Moving off the retired ingress controller to Gateway API stands. Implementing
> it with Envoy Gateway does not: DOKS already ships a Gateway API
> implementation, which the "Cilium Gateway API" alternative below rejected on
> reasoning that does not apply.

## Context

The application repository's local Kind stack uses **ingress-nginx** — pinned at
chart 4.11.2 in `deploy/helmfile.yaml.gotmpl`, with `heptapedal-app` shipping a
`networking.k8s.io/v1` Ingress hardcoded to `ingressClassName: nginx`.

That project is gone. Kubernetes SIG Network announced ingress-nginx's retirement
in November 2025 (maintainer burnout, accumulated technical debt) and it reached
end of life in **March 2026**. There are no further releases, bug fixes, or CVE
patches. InGate, the intended successor, never matured and was retired alongside
it. Carrying ingress-nginx into production now means running an unpatched,
internet-facing component.

What is *not* retired: the Ingress API itself (supported, feature-frozen), the
NGINX server, and F5's separate `nginxinc/kubernetes-ingress` controller.

Relevant workload constraint: `/mcp` is MCP Streamable HTTP — long-lived,
streaming connections. Whatever sits in front must not buffer them.

## Decision

Adopt **Gateway API** with **Envoy Gateway** as the implementation.

- One `Gateway` in a platform namespace, terminating TLS with the wildcard
  certificate from [0009](0009-dns-and-tls.md).
- Each application attaches its own `HTTPRoute` from its own namespace — which is
  the delegation model Ingress never had, and the reason this scales to the second
  application cleanly.
- Envoy Gateway's control plane is sized down for a small cluster (defaults are
  10m/64Mi requests, 700m/128Mi limits).
- Raise the DO Load Balancer idle timeout via
  `service.beta.kubernetes.io/do-loadbalancer-http-idle-timeout-seconds`
  (default 60s, max 600) or MCP sessions are cut mid-stream.

This requires a change in the **application** repository: `heptapedal-app` needs an
`HTTPRoute` template behind a toggle alongside the existing Ingress, so local Kind
and production render from one chart rather than diverging.

## Consequences

- Supported, patched ingress path.
- Role separation is expressed in the API: platform owns `Gateway`, application
  owns `HTTPRoute`. Multi-app onboarding becomes "add a route", not "edit the
  shared Ingress".
- Costs a cross-repo PR before the application can be deployed. Tracked as its own
  issue rather than discovered mid-phase.
- Gateway API is a new resource model to learn, and its annotations do not map
  one-to-one from nginx. Here the entire Ingress is a single catch-all rule, so
  there is nothing to translate — the migration cost is near zero, which is
  precisely why doing it *now* is right.
- `ingress2gateway` (v1.0 since March 2026) exists if translation is ever needed.

## Alternatives considered

- **Traefik.** The realistic drop-in: its NGINX Ingress provider reads
  `nginx.ingress.kubernetes.io` annotations, so existing Ingress objects mostly
  keep working. Rejected because this project has zero annotation investment to
  preserve — the compatibility layer is the entire advantage, and it does not
  apply.
- **`nginxinc/kubernetes-ingress` (F5).** Actively maintained, keeps the Ingress
  API and the current chart unchanged — the smallest possible diff. Rejected:
  it preserves a feature-frozen API and forgoes the per-namespace route
  delegation that the second application will want.
- **Cilium Gateway API.** Would fold in CNI and network policy. Rejected: replacing
  DOKS's CNI is a large change with a real chance of breaking the managed
  integration, for capability this cluster does not need.
- **Cloudflare in front (free tier).** Attractive for CDN and DDoS. Rejected for
  now specifically because of `/mcp`: free-tier proxy buffering behaviour with SSE
  and streaming is unpredictable. Revisit when static assets (`/pkg/*`) are split
  onto their own path, and route only those through it.
