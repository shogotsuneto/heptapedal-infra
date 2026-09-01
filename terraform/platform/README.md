# platform

The cloud substrate: the DigitalOcean project and VPC, the DOKS cluster, the
managed PostgreSQL cluster, and the DNS zone. One region throughout
([ADR 0013](../../docs/adr/0013-region-sfo3.md)).

State lives in the bucket from [`../bootstrap`](../bootstrap/README.md).

## Prerequisites

- `DIGITALOCEAN_TOKEN` with the scopes listed in
  [`../bootstrap/README.md`](../bootstrap/README.md).
- `AWS_*` set to the **bucket-scoped** Spaces key, for the backend. This stack
  manages no Spaces resources, so `SPACES_*` is not needed.

## Apply

```bash
cd terraform/platform
tofu init
tofu apply
```

No override dance here — unlike bootstrap, the bucket already exists. Cluster
creation takes a few minutes; `tofu apply` returns once the control plane is up,
while nodes may still be joining.

## kubectl access

```bash
doctl kubernetes cluster kubeconfig save heptapedal
kubectl get nodes
```

DigitalOcean issues cluster credentials with a **7 day expiry**. Given no
`--expiry-seconds`, `doctl` writes a kubeconfig that authenticates through an
`exec` credential plugin calling `doctl` itself, so `kubectl` renews on demand
and nothing goes stale.

`tofu output -raw kubeconfig` is **not** equivalent. `output` reads the state
file and never contacts the API — which is why it needs no provider
credentials — so it returns whatever the last apply captured, dead seven days
later. `tofu apply -refresh-only` first would fetch a live one, at the cost of
rewriting state and needing the write credentials. Use it only where `doctl` is
unavailable.

The same expiry is why the Argo CD stack takes no kubeconfig from here: a token
captured in state goes stale and takes the `kubernetes` and `helm` providers
with it. It looks the cluster up by name with a
`digitalocean_kubernetes_cluster` **data source**, which is re-read on every
plan and so reissues credentials each time. `cluster_name` is exported for that.

## Database bootstrap

Run once, after the first `apply`. Until it has run, the migration Job cannot
create a single table.

```bash
kubectl run pg-bootstrap --rm -i --restart=Never \
  --image=postgres:17-alpine \
  --env="PGURL=$(tofu output -raw database_admin_url)" \
  -- sh -c 'psql "$PGURL"' < sql/bootstrap.sql
```

Verify:

```bash
kubectl run pg-check --rm -i --restart=Never --image=postgres:17-alpine \
  --env="PGURL=$(tofu output -raw database_admin_url)" \
  -- sh -c 'psql "$PGURL"' <<'SQL'
SELECT extname FROM pg_extension ORDER BY extname;
SQL
```

`vector`, `pgcrypto` and `pg_trgm` should be listed. The whole file is
idempotent, so re-running it after a restore or a rebuild is safe.

> **Keep the single quotes, and pass SQL on stdin.** `-- psql "$PGURL"` would
> expand `$PGURL` in the *local* shell, where it is not set, handing psql an
> empty argument; `sh -c '...'` defers expansion to the pod and keeps the
> credential off the local command line and out of shell history. Passing SQL on
> stdin rather than through `-c` sidesteps a second layer of quoting — `-c \dx`
> arrives at psql as `dx`, because `sh` consumes the backslash.

`database_admin_url` is `doadmin`, for this step and for troubleshooting. The
application connects as `app_user` through `database_url`, which becomes its
sealed `DATABASE_URL` in #17.

> Plans carry a standing `~ user = "doadmin" -> null` under *Objects have
> changed outside of OpenTofu*. It is a provider bug — `user` is assigned from
> the API's connection object unconditionally, while `password` is guarded by a
> non-empty check, and that object reads back with an empty user. Nothing is
> wrong with the cluster. `database_admin_url` no longer reads that attribute,
> so the noise stays noise; see the comment in `database.tf`.

### Getting a psql prompt

`kubectl port-forward` targets a Pod or Service *in the cluster* and cannot
reach an external host, so it does not by itself get you to a managed database.
A relay makes it work — useful when you want your own `psql` rather than one
inside a throwaway pod:

```bash
HOST=$(tofu output -raw database_host)
PORT=$(tofu output database_port)

kubectl run pgproxy --image=alpine/socat --port=5432 \
  -- tcp-listen:5432,fork,reuseaddr tcp-connect:$HOST:$PORT
kubectl port-forward pod/pgproxy 5432:5432

# elsewhere
psql "postgresql://app_user:...@localhost:5432/hepta?sslmode=require"
kubectl delete pod pgproxy
```

`sslmode=require` encrypts without verifying the hostname, so `localhost` works.
`verify-full` would not.

### Why this step exists

**Terraform has no connection to the database.** This needs SQL, and the
firewall trusts only the Kubernetes cluster — deliberately, since an operator IP
or a CI runner in that list would be the hole the rule exists to avoid. Node IPs
are ephemeral anyway, so an address allowlist would rot on the first node
replacement, silently. Hence a pod inside the cluster.

**And `app_user` cannot grant itself what the migrations need.** Measured
against this cluster rather than reasoned about:

| | |
|---|---|
| `app_user` creates `vector`, `pgcrypto`, `pg_trgm` | succeeds |
| `app_user` creates a table in `public` | `permission denied for schema public` |
| `has_schema_privilege('app_user', 'public', 'CREATE')` | `f` |
| `has_database_privilege('app_user', 'hepta', 'CREATE')` | `f` |

The extensions were the expected obstacle and are not one. DigitalOcean runs
`pgextwlist`, which intercepts `CREATE EXTENSION` and executes allowlisted
extensions with elevated rights — so the `trusted` and `superuser` flags in
`pg_available_extension_versions` describe *pgvector upstream* and decide
nothing here. `doadmin` is not a superuser either; the allowlist is what
distinguishes it, not its role attributes. **Only attempting an operation shows
what this platform permits.**

The **grants** are what need `doadmin`, and DigitalOcean exposes no API for
them. The extensions could therefore move into the application's migrations;
they stay here because this file must exist for the grants regardless, and
splitting database preparation across two places buys nothing.

### Why it stays manual

It could be automated: once Argo CD exists, the same SQL runs from a
sync-wave-ordered Job inside the cluster, satisfying the firewall exactly as
this pod does. The price is `doadmin` living permanently in the cluster as a
sealed Secret — a credential that can do anything to the database, resident
forever to cover something that runs about once per database lifetime.

One documented step, alongside the nameserver delegation and the Spaces keys, is
the better trade. Revisit if rebuilds become frequent, or a second database
arrives.

## DNS delegation

`heptapedal.com` stays registered at Namecheap; DigitalOcean serves the zone
([ADR 0009](../../docs/adr/0009-dns-and-tls.md)). Terraform creates the zone and
its records; moving the delegation is a manual step at the registrar.

Certificate issuance in #11 uses a DNS-01 challenge and cannot succeed until
this has taken effect, which is why it runs early.

### 1. Apply first, and check what would break

The zone must exist at DigitalOcean **before** the nameservers move, or they
point at a provider with nothing to answer from.

Four records carry Resend — Supabase's custom SMTP — and therefore the sign-up
confirmation and password-reset links. Sign-up is email-first, so breaking them
breaks the only way to create an account. Confirm DigitalOcean answers for all
four before switching:

```bash
dig +short @ns1.digitalocean.com TXT send.heptapedal.com
dig +short @ns1.digitalocean.com MX  send.heptapedal.com
dig +short @ns1.digitalocean.com TXT resend._domainkey.heptapedal.com
dig +short @ns1.digitalocean.com TXT _dmarc.heptapedal.com
```

**Reconcile against the registrar, not only `dig`.** Querying probes names you
think to ask for; it cannot enumerate a zone. These records were nearly missed
for exactly that reason. Read Namecheap's Advanced DNS page against
`dns-email.tf` before going further.

### 2. Switch the nameservers

Namecheap: **Domain List → Manage → Nameservers**, switch from *Namecheap
BasicDNS* to *Custom DNS*, and enter:

```
ns1.digitalocean.com
ns2.digitalocean.com
ns3.digitalocean.com
```

Also available as `tofu output nameservers`.

**Not the Advanced DNS tab.** Delegating an apex domain rewrites the `NS`
records in the *parent* zone — the `.com` registry — which is what the
registrar's nameserver setting controls. `NS` records added inside the
Namecheap-hosted zone do nothing, because the parent still points every resolver
at Namecheap. (In-zone `NS` records *are* the mechanism for delegating a
subdomain; that is not this.)

**Delete nothing at Namecheap.** Switching to Custom DNS leaves the BasicDNS
zone stored but unused, so reverting the setting is a working rollback.

### 3. Verify

```bash
dig NS heptapedal.com +short          # expect the three above
dig CAA heptapedal.com +short         # expect letsencrypt.org
```

### What to expect meanwhile

The registry push takes minutes, but `.com` publishes this delegation with a
**48 hour TTL**:

```
$ dig @a.gtld-servers.net NS heptapedal.com
heptapedal.com.  172800  IN  NS  ns1.digitalocean.com.
```

A resolver holding the old answer may keep asking Namecheap for two days. Most
refresh sooner; plan for 48 hours rather than reading a stale answer as failure.

During that window **both zones are live**, each serving whichever resolvers
still point at it. That is survivable because they agree on what matters — the
email records are replicated verbatim, so mail authentication holds either way.
It is also the stronger reason not to delete anything at Namecheap: doing so
turns the transition from an overlap into a cliff.

The apex is the one disagreement. Namecheap answers with a parking page,
DigitalOcean with nothing until #20 adds an `A` record for the Load Balancer.
Nothing depends on either.

### What the zone holds

| Name | Type | Purpose |
|---|---|---|
| `@` | CAA | restricts issuance to Let's Encrypt, for #11 |
| `send` | TXT | SPF for the custom MAIL FROM domain |
| `send` | MX | SES bounce and complaint handling |
| `resend._domainkey` | TXT | DKIM public key |
| `_dmarc` | TXT | DMARC policy |

The email records are replicated verbatim from Namecheap, TTLs included.
Deliberately not carried across:

| Record | Why not |
|---|---|
| apex `A` → `192.64.119.97` | Namecheap's parking page |
| `www` → `parkingpage.namecheap.com` | the same parking page |
| `NS`, `SOA` | belong to whoever hosts the zone; DigitalOcean creates its own |

## Operational notes

### Changes that cost money

- **`ha = false` is load-bearing.** On Kubernetes 1.36 and later the provider
  defaults it to `true`, a 40 USD/month high-availability control plane — 40% of
  the budget, for an availability target
  [ADR 0004](../../docs/adr/0004-kubernetes-on-doks.md) declines to buy. It is
  irreversible: DigitalOcean cannot turn HA off once a cluster has it. Deleting
  that line is a silent, permanent price rise.
- **Node count is fixed at 2, not autoscaled.** The budget has roughly 20
  USD/month of headroom, and an autoscaler is what spends it without asking.
- **`destroy_all_associated_resources` is false.** Destroying the cluster leaves
  behind any Load Balancer or volume the Kubernetes API created — recoverable,
  but it bills silently. Check for an orphan after any teardown; the billing
  alert in #7 is the backstop.

### Kubernetes version

`kubernetes_version_prefix` pins the minor; the newest patch within it is
selected, and `auto_upgrade` applies later patches during the maintenance window
(Sundays 10:00 UTC, 03:00 Pacific).

DigitalOcean supports the three most recent minors. As of 2026-08: 1.34 (end of
support 2026-10-27), 1.35 (2027-02-28), 1.36 (2027-06-28) — pinned to 1.36 for
the longest runway. List what is offered with `doctl kubernetes options
versions`. Bumping the minor is a one-line change, but read the upstream
changelog first.

### Database

**Backups** are daily with point-in-time recovery to any second in the previous
seven days, via WAL archiving. Not configurable on this plan and not managed by
Terraform — but it is the reason
[ADR 0008](../../docs/adr/0008-postgres-do-managed.md) chose a managed database
over the in-cluster StatefulSet the application chart already ships.

**Version parity** is unfinished: production runs PostgreSQL 17, local
development runs `pgvector/pgvector:pg16` in docker-compose and Kind. Worth
closing by bumping the local image rather than holding production back — an
application-repo change, tracked there.
