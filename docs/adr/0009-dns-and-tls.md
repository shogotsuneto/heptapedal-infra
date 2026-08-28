# 0009. Delegate DNS to DigitalOcean; wildcard certs via cert-manager DNS-01

- **Status:** Accepted
- **Date:** 2026-08-27

## Context

`heptapedal.com` is registered at Namecheap. The platform is expected to host more
than one application — heptapedal now, a voice-agent service later — which points
at per-application subdomains and therefore at a wildcard certificate.

Namecheap's DNS API is awkward to automate: it requires IP allowlisting and an
account balance or domain-count threshold. That is a poor foundation for both
Terraform-managed records and ACME DNS-01 challenges.

## Decision

- **Registrar stays Namecheap.** Delegate nameservers to **DigitalOcean DNS**
  (free), so records are managed as `digitalocean_domain` /
  `digitalocean_record` alongside the rest of the infrastructure.
- **cert-manager** with a Let's Encrypt `ClusterIssuer` using the **DNS-01**
  solver against DigitalOcean, issuing `*.heptapedal.com` (plus the apex).
- The wildcard certificate is referenced by the shared `Gateway` from
  [0005](0005-gateway-api-envoy-gateway.md), so a new application needs a DNS
  record and an `HTTPRoute` — no certificate work at all.

## Consequences

- One provider credential covers DNS records and ACME challenges.
- Adding an application costs one A record; TLS is already solved. This is the
  main reason for choosing wildcard over per-host certificates.
- DNS delegation is a manual, one-time step at Namecheap that Terraform cannot
  perform. It gets its own documented step, and propagation has to complete before
  the first certificate can issue.
- DNS-01 works before any traffic reaches the cluster, which decouples certificate
  issuance from the Gateway being reachable — useful during bootstrap.
- A wildcard is one certificate and therefore one blast radius. Acceptable for a
  single-tenant platform.
- Namecheap remains a second console for registration and renewal only.

## Alternatives considered

- **HTTP-01 through the Gateway.** Simpler, no DNS credential. Rejected: it cannot
  issue wildcards, so every new subdomain becomes a certificate event, and it
  requires the Gateway to be publicly reachable before issuance.
- **Cloudflare DNS (free).** Also excellent Terraform and cert-manager support,
  and it would open the door to CDN and WAF later. Rejected for now to keep the
  provider count at one — and because proxying is separately deferred in
  [0005](0005-gateway-api-envoy-gateway.md) over MCP streaming behaviour. Moving
  here later is a nameserver change.
- **Namecheap DNS with manual records.** Rejected: not automatable, and DNS-01
  would not work cleanly.
- **external-dns.** Would generate records from `Gateway`/`HTTPRoute` objects
  automatically. Deferred, not rejected — at two or three records, Terraform is
  clearer. Revisit as the application count grows.
