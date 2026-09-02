# apps

One directory per application. Empty until #18 adds heptapedal.

Each holds an Argo CD `Application` pointing at the OCI chart the application
repository publishes, pinned to an immutable version, plus its production values
([ADR 0011](../../docs/adr/0011-artifact-distribution-ghcr.md)).

Its `SealedSecret`s live in the same directory, on an earlier sync wave than the
Application that consumes them — the same shape as
[`../platform`](../platform/README.md), and for the same reason: on a rebuild
every seal is stale, and the wave should stop there rather than let the
application deploy into a cluster where its `DATABASE_URL` does not exist.

The failure modes are worth knowing apart:

| Stale | Symptom |
|---|---|
| the application's own `SealedSecret` | wave stops, `SealedSecret` Degraded with the controller's message |
| the GHCR registry credential (#10, in `platform/`) | the Application cannot render its chart — a *source* error, not a health one |

Adding a second service is a directory here — no Terraform, no cloud
credentials. That is the property [ADR 0006](../../docs/adr/0006-gitops-argo-cd-app-of-apps.md)
is buying.
