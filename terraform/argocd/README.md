# argocd

Installs Argo CD, and nothing else. From here the root Application (#9) takes
over and the rest of the platform arrives through GitOps rather than Terraform
([ADR 0006](../../docs/adr/0006-gitops-argo-cd-app-of-apps.md)).

State lives in the same bucket as the other stacks, under its own key, so this
can be rebuilt without touching the substrate.

## Prerequisites

- The [`../platform`](../platform/README.md) stack applied — this reads its
  cluster by name.
- `DIGITALOCEAN_TOKEN` with the scopes from
  [`../bootstrap/README.md`](../bootstrap/README.md), including
  `kubernetes:access_cluster`.
- `AWS_*` set to the bucket-scoped Spaces key, for the backend.

No kubeconfig needed. The stack reads the cluster through a
`digitalocean_kubernetes_cluster` **data source**, which is re-read on every
plan and so mints credentials that have not had time to expire. A kubeconfig
captured in state would go stale after seven days and take the `kubernetes` and
`helm` providers with it.

## Apply

```bash
cd terraform/argocd
tofu init
tofu apply
```

Takes a few minutes: the chart installs five workloads and the apply waits for
them.

## Reach the UI

Not exposed. Publishing it is a separate decision with its own authentication
question — until then, port-forward:

```bash
kubectl -n argocd port-forward svc/argocd-server 8080:80
open http://localhost:8080
```

Plain HTTP, because `server.insecure` is set: the only path to this service is
already inside the cluster, and when it is eventually published the Gateway will
terminate TLS ([ADR 0005](../../docs/adr/0005-gateway-api-envoy-gateway.md)).

The initial admin password:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
```

**Rotate it and delete that Secret.** It is generated at install and sits in the
cluster in plaintext until removed:

```bash
argocd login localhost:8080 --username admin --insecure
argocd account update-password
kubectl -n argocd delete secret argocd-initial-admin-secret
```

The password is deliberately not managed by Terraform: doing so would mean a
bcrypt hash in configuration and a credential in state, to replace a Secret that
should simply stop existing.

## What this costs the cluster

| Component | requests | memory limit |
|---|---|---|
| application-controller | 100m / 256Mi | 768Mi |
| repo-server | 50m / 128Mi | 512Mi |
| server | 50m / 128Mi | 256Mi |
| applicationset-controller | 25m / 64Mi | 128Mi |
| redis | 50m / 64Mi | 192Mi |

Roughly **325m CPU and 768Mi requested** in total. The chart's defaults assume a
roomier cluster than [ADR 0004](../../docs/adr/0004-kubernetes-on-doks.md) pays
for, so `values/argocd.yaml` trims:

- **Dex disabled.** No SSO, one operator; it is an identity broker for nobody.
- **Notifications disabled.** Alerting goes to Grafana Cloud
  ([ADR 0010](../../docs/adr/0010-observability-grafana-cloud.md)).
- **ApplicationSet controller stays.** Chart 10.x has no top-level toggle for
  it. It sits idle — [ADR 0006](../../docs/adr/0006-gitops-argo-cd-app-of-apps.md)
  uses app-of-apps until the application count justifies generators — and is
  sized as the near-idle process it is.

The application-controller is the component to watch: its memory tracks the
number of managed objects rather than traffic, so it grows as the platform does.

## Upgrading

`chart_version` is pinned; Renovate proposes bumps once #21 is set up. Read the
chart's release notes before taking a major — Argo CD majors have changed CRDs.
