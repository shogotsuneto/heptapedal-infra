# platform

Add-ons every cluster gets, each an Argo CD `Application` ordered by
`argocd.argoproj.io/sync-wave`.

| Wave | Contents | Status |
|---|---|---|
| 0 | Sealed Secrets controller | in |
| 1 | every `SealedSecret` this bundle needs | with each add-on |
| 2 | cert-manager and its DNS-01 `ClusterIssuer`; Grafana Alloy | #11, #15 |
| 3 | Envoy Gateway and the shared `Gateway` | #13 |

The waves follow real dependencies, not tidiness:

- **Controller first**, because a `SealedSecret` cannot be decrypted before it
  runs, and its CRD has to exist to be applied at all.
- **Sealed values in a wave of their own**, ahead of everything that consumes
  them. Sharing a wave with a consumer would race — and on a rebuild, where
  every seal is stale, this is the wave that stops the bundle rather than
  letting broken components deploy. See
  [the rebuild note](../README.md#what-a-rebuilt-cluster-does).
- **Envoy Gateway last**, because the shared `Gateway` references a certificate
  cert-manager has to have issued.

Argo CD assesses each Application's health, so a wave waits for the previous one
to be Healthy rather than merely created.
