# apps

One directory per application. Empty until #18 adds heptapedal.

Each holds an Argo CD `Application` pointing at the OCI chart the application
repository publishes, pinned to an immutable version, plus its production values
([ADR 0011](../../docs/adr/0011-artifact-distribution-ghcr.md)).

Adding a second service is a directory here — no Terraform, no cloud
credentials. That is the property [ADR 0006](../../docs/adr/0006-gitops-argo-cd-app-of-apps.md)
is buying.
