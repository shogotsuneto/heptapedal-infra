# platform

Add-ons every cluster gets. Empty until Phase 3 fills it:

| # | Add-on |
|---|---|
| 11 | cert-manager, and a DNS-01 `ClusterIssuer` for the wildcard certificate |
| 12 | Sealed Secrets |
| 13 | Envoy Gateway, and the shared `Gateway` |
| 15 | Grafana Alloy |

Order them with `argocd.argoproj.io/sync-wave` annotations — CRDs before what
uses them, cert-manager before the Gateway that references its certificate.

An empty directory is a valid source: Argo CD reports the Application Synced
with nothing to do, which is what lets wave 1 proceed today.
