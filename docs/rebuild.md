# Rebuilding

Two situations, and they are not the same size.

**Replacing the cluster** is the common one, and most of the platform survives
it. **Building from nothing** is the claim this repository makes about itself,
and it has not been tested end to end.

## What survives a cluster replacement

The boundary is deliberate: the cluster is disposable, and everything with state
in it lives outside.

| Survives | Because |
|---|---|
| Spaces bucket and all Terraform state | its own stack, `force_destroy = false`, `prevent_destroy` |
| DigitalOcean project, VPC | `platform`, untouched by replacing one resource in it |
| DNS zone and every record — CAA, the four email records, the apex | same |
| **Managed Postgres, its data, and its bootstrap grants** | `platform`; the cluster never held the data (ADR 0008) |
| GHCR packages, Supabase project, Grafana Cloud stack, alerts, dashboards | outside DigitalOcean entirely |

| Lost | Consequence |
|---|---|
| The cluster and everything Argo CD put in it | recreated from `gitops/` |
| **The Sealed Secrets keys** | every `SealedSecret` in git becomes undecryptable — five of them |
| **The Load Balancer, and its address** | `apex_ip` is now wrong; DNS points at nothing |
| Argo CD's registration of the deploy key | the private key lived in the cluster |

The last three are the manual work, and none of them is optional.

## Replacing the cluster

### Before

**Check the Droplet limit.** A replace creates the new nodes before destroying
the old, so two nodes need four Droplets. The account allows three, and this
fails partway through with `2 additional nodes exceed the available droplet
limit` — which has happened. Either raise the limit first (#67), or accept a
destroy-then-create and the downtime that comes with it.

**Withdraw the apex record**, so nothing points at an address that is about to
stop existing:

```bash
tofu -chdir=terraform/platform apply -var apex_record=false
```

NXDOMAIN fails immediately where a dead address hangs. Certificate renewal is
unaffected — cert-manager solves DNS-01 with TXT records.

### Replace

```bash
tofu -chdir=terraform/platform apply \
  -replace=digitalocean_kubernetes_cluster.heptapedal
```

**Never a plain `destroy`.** That takes the database and the DNS zone with it,
and those are the two things this whole layout exists to keep.

### Then, in order

```bash
# 1. Credentials for the new cluster
doctl kubernetes cluster kubeconfig save heptapedal

# 2. Argo CD, and the one Application that pulls in everything else
tofu -chdir=terraform/argocd apply
```

**3. Register the repository.** A new Argo CD has no deploy key, and this is not
in Terraform because the private key would land in state. Procedure in
[`../terraform/argocd/README.md`](../terraform/argocd/README.md#register-the-repository--the-handoff-step).
Until it is done, the root Application cannot read `gitops/` and nothing
deploys.

**4. Reseal all five secrets.** New cluster, new sealing keys.

| Secret | Where the value comes from |
|---|---|
| `cert-manager/digitalocean-dns` | DigitalOcean API token, `domain:read/create/delete` |
| `monitoring/grafana-cloud` | Grafana Cloud, both instance IDs and the token |
| `argocd/ghcr-charts` | GitHub classic PAT, `read:packages` |
| `hepta/app-secrets` | `tofu output -raw database_url`, plus Supabase |
| `hepta/ghcr` | the same classic PAT, as a docker-registry secret |

Commands and the reasoning for each are in
[`../gitops/README.md`](../gitops/README.md#where-each-value-comes-from).

**Leave the stale files in git while you work.** They are doing two jobs: they
are the list of what still needs resealing, and they are the gate that stops a
half-working platform coming up. Argo CD reports each undecryptable
`SealedSecret` as Degraded and the wave never completes, so nothing downstream
deploys into a cluster where its `DATABASE_URL` does not exist. Deleting them
removes the gate and lets each consumer fail in its own way instead.

**5. Point DNS at the new Load Balancer.**

```bash
kubectl get gateway heptapedal -n gateway -o jsonpath='{.status.addresses[0].value}'
# set apex_ip in terraform/platform/variables.tf, then:
tofu -chdir=terraform/platform apply
```

There is no way to keep the old address: reserved IPs do not attach to
DigitalOcean Load Balancers, and `do-loadbalancer-ip` wants a BYOIP prefix. The
record's TTL is 300s so the switch costs minutes.

### Verify

```bash
kubectl get applications -n argocd          # all Synced/Healthy
dig +short heptapedal.com A                 # matches the Gateway address
curl -sI https://heptapedal.com/login       # 200, valid certificate
```

The external probe (#80) answers the same question continuously, and the alert
set (#79) will say if it does not.

## Building from nothing

The order is forced by what reads what.

1. **`terraform/bootstrap`** — the state bucket, applied with local state and
   then migrated into itself. Needs the full-access Spaces key.
   [Procedure](../terraform/bootstrap/README.md).
2. **Delegate DNS at the registrar** — nameservers to DigitalOcean. Certificate
   issuance uses DNS-01 and cannot succeed until this has propagated, which is
   why it comes before anything that wants a certificate.
   [Procedure](../terraform/platform/README.md#dns-delegation).
3. **`terraform/platform`** — project, VPC, cluster, database, DNS records.
4. **Bootstrap the database** — extensions and grants, once, as `doadmin`.
   [Procedure](../terraform/platform/README.md#database-bootstrap).
5. **`terraform/argocd`**, then register the repository.
6. **Seal every secret**, as above but for the first time.
7. **`terraform/grafana`** — alerts, dashboards, the external probe. Independent
   of the cluster; can be done at any point.

Outside all of it, and easy to forget because nothing here fails without them:

- **Supabase** — Site URL, the Redirect URLs allowlist, and the `keepalive`
  table with its grant ([procedure](supabase-keepalive.md)).
- **GitHub** — repository secrets and variables, and *Allow GitHub Actions to
  create and approve pull requests*, which is off by default.

**This has not been done end to end.** The claim that it works is a reading of
the parts, not a test of the whole. Doing it into a scratch project, and timing
it, is the remaining item on #24.

## Restoring the database

Backups are daily with point-in-time recovery to any second in the previous
seven days, through WAL archiving. Not managed by Terraform and not
configurable on this plan — DigitalOcean's console does the restore, into a
**new** cluster.

Which means a restore is not a rollback: it produces a second database, and the
application has to be pointed at it. That is `database_url` changing, which is
`hepta/app-secrets` being resealed.

The extension bootstrap is idempotent, so re-running it against a restored
cluster is safe.

## Failures worth expecting

Each of these has happened.

**A blocked sync wave is visible by absence, not by an error.** If the platform
Application shows fewer resources than expected, look for the wave that did not
complete rather than for something red.

**`SkipDryRunOnMissingResource` only matters from nothing.** Argo CD validates
every task before any wave runs, so a `SealedSecret` is checked against a CRD
that wave 0 has not installed yet. On an existing cluster the CRD is already
there and its absence is invisible.

**A restored or replaced cluster changes the Load Balancer address, and nothing
notices.** Terraform compares configuration to state, never to reality, so a
stale `apex_ip` produces no diff at all while the site is unreachable. The
external probe is what catches it.

**Signals to PID 1 from inside a container do nothing.** Relevant when trying to
restart something in place: the kernel ignores them unless the process installed
a handler, and SIGKILL cannot be handled. Delete the pod, or accept that a new
pod resets its restart counter.
