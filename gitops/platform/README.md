# platform

Add-ons every cluster gets, each an Argo CD `Application` ordered by
`argocd.argoproj.io/sync-wave`.

| Wave | Add-on | Status |
|---|---|---|
| 0 | Sealed Secrets | in |
| 1 | cert-manager, and a DNS-01 `ClusterIssuer` | #11 |
| 1 | Grafana Alloy | #15 |
| 2 | Envoy Gateway, and the shared `Gateway` | #13 |

The waves follow real dependencies, not tidiness:

- **Sealed Secrets first**, because cert-manager's DigitalOcean token, Alloy's
  Grafana Cloud token and the GHCR registry credential (#10) all arrive as
  `SealedSecret`s, which are undecryptable until its controller runs.
- **Envoy Gateway last**, because the shared `Gateway` references a certificate
  cert-manager has to have issued.

Argo CD assesses each Application's health, so a wave waits for the previous one
to be Healthy rather than merely created.
