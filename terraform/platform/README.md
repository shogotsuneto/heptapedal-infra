# platform

The cloud substrate: the DigitalOcean project, the VPC, and the DOKS cluster.

Grows over Phase 1 — the managed database joins in #4 and the DNS zone in #5,
both into this stack, because they belong to the same VPC and the same project.

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

No override dance here — unlike bootstrap, the bucket already exists.

Cluster creation takes a few minutes. `tofu apply` returns when the control
plane is up; nodes may still be joining.

## kubectl access

Use `doctl`, not the Terraform output:

```bash
doctl kubernetes cluster kubeconfig save heptapedal
kubectl get nodes
```

DigitalOcean issues cluster credentials with a **7 day expiry**. Given no
`--expiry-seconds`, `doctl` writes a kubeconfig that authenticates through an
`exec` credential plugin calling `doctl` itself, so `kubectl` renews on demand
and nothing goes stale.

**`tofu output -raw kubeconfig` does not do this.** `output` reads the state
file and nothing else — it does not contact the API, which is why it needs no
provider credentials — so it returns the kubeconfig captured at the **last
apply**, and that stops working seven days later. Refreshing first would fetch a
new one:

```bash
tofu apply -refresh-only      # re-reads the cluster, rewriting state
tofu output -raw kubeconfig
```

but that rewrites state on every use, needs the write credentials, and gets you
a copy that starts ageing immediately. `doctl` is the answer; this is the
fallback when it is not installed.

The same expiry is why the Argo CD stack does not consume a kubeconfig output:
a token captured in state goes stale and takes the `kubernetes` and `helm`
providers with it. It looks the cluster up by name with a
`digitalocean_kubernetes_cluster` data source instead, which reissues
credentials on every read. `cluster_name` is exported for exactly that.

## Database bootstrap

Terraform creates the cluster, the `hepta` database, the `app_user` role and the
firewall. Preparing the database inside it is a separate, one-time step, for two
reasons.

**Terraform has no connection.** This needs SQL, and the
firewall trusts only the Kubernetes cluster — deliberately, since an operator IP
or a CI runner in that list would be the hole the rule exists to avoid. So the
bootstrap runs from inside the cluster instead.

**And the grants need a privileged connection.** Measured against this cluster
rather than reasoned about:

| | |
|---|---|
| `app_user` creates `vector`, `pgcrypto`, `pg_trgm` | succeeds |
| `app_user` creates a table in `public` | `permission denied for schema public` |
| `has_schema_privilege('app_user', 'public', 'CREATE')` | `f` |
| `has_database_privilege('app_user', 'hepta', 'CREATE')` | `f` |

The extensions were the expected obstacle and turn out not to be one.
DigitalOcean runs `pgextwlist`, which intercepts `CREATE EXTENSION` and executes
allowlisted extensions with elevated rights — so the `trusted` and `superuser`
flags in `pg_available_extension_versions`, which describe pgvector upstream,
do not decide anything here. `doadmin` is not a superuser either (`rolsuper` is
`f`); what distinguishes it is the allowlist, not its role attributes.

What genuinely needs `doadmin` is the **grants**. `app_user` has no `CREATE` on
the schema or the database, so the migration Job cannot create its tables — and
`app_user` cannot grant itself the right to. DigitalOcean exposes no API for
this either, so a privileged SQL connection is the only route.

The extensions could therefore move into the application's migrations. They stay
here because the bootstrap step survives regardless, and splitting database
preparation across two places to save nothing is worse than one file that does
it all.

To re-measure the table above — after a rebuild, or if DigitalOcean's defaults
change:

```bash
kubectl run pg-check --rm -i --restart=Never --image=postgres:17-alpine \
  --env="PGURL=$(tofu output -raw database_admin_url)" \
  -- sh -c 'psql "$PGURL"' <<'SQL'
SELECT name, version, superuser, trusted
  FROM pg_available_extension_versions
 WHERE name IN ('vector', 'pgcrypto', 'pg_trgm')
 ORDER BY name, version;

SELECT rolname, rolsuper, rolcreatedb
  FROM pg_roles WHERE rolname IN ('app_user', 'doadmin');
SQL
```

Note that the extension flags there are **not** the answer — they describe
pgvector upstream, and `pgextwlist` overrides them invisibly. Only attempting
the operation says what this platform actually permits. Attempt it as
`app_user` (`database_url`), not `doadmin`, and without `IF NOT EXISTS`, which
would return success without reaching a privilege check once the extension
exists.

Skipping the step does not fail subtly: the migration Job cannot create a single
table.

```bash
kubectl run pg-bootstrap --rm -i --restart=Never \
  --image=postgres:17-alpine \
  --env="PGURL=$(tofu output -raw database_admin_url)" \
  -- sh -c 'psql "$PGURL"' < sql/bootstrap.sql
```

It is idempotent — `CREATE EXTENSION IF NOT EXISTS` and repeated `GRANT`s — so
running it again after a restore or a rebuild is safe.

**Why this stays manual.** It could be automated: once Argo CD exists, the same
SQL runs from a sync-wave-ordered Job inside the cluster, which satisfies the
firewall the same way this pod does. The price is `doadmin` living permanently
in the cluster as a sealed Secret — a credential that can do anything to the
database, resident forever to cover something that runs about once per database
lifetime. Against that, one documented step alongside the nameserver delegation
and the Spaces keys is the better trade. Revisit if rebuilds become frequent, or
if a second database arrives.

DigitalOcean offers no API, `doctl` command or control-panel toggle for
extensions, so SQL from somewhere the firewall trusts is the only route either
way.

Verify:

```bash
kubectl run pg-check --rm -i --restart=Never --image=postgres:17-alpine \
  --env="PGURL=$(tofu output -raw database_admin_url)" \
  -- sh -c 'psql "$PGURL" -c \dx'
```

`vector`, `pgcrypto` and `pg_trgm` should be listed.

Note the `sh -c '...'` with single quotes in both commands. Writing
`-- psql "$PGURL"` instead would expand `$PGURL` in the *local* shell, where it
is not set — so psql would receive an empty argument. Single quotes defer the
expansion to the pod, where the `--env` value lives, and keep the credential off
the local command line and out of shell history.

### Getting a psql prompt another way

`kubectl port-forward` targets a Pod or Service in the cluster and cannot reach
an external host, so it does not by itself get you to a managed database. Put a
relay in the cluster and it does — useful when you want your own `psql` rather
than one inside a throwaway pod:

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

`sslmode=require` encrypts without verifying the hostname, so connecting through
`localhost` works. `verify-full` would not.

`database_admin_url` is `doadmin`. It exists for this step and for
troubleshooting; the application connects as `app_user` through
`database_url`, which is what becomes its sealed `DATABASE_URL` in #17.

Skipping it surfaces as `permission denied for schema public` from the migration
Job, which points at the cause more usefully than a missing type would have. A
guard migration in the application repo is still tracked as a follow-up there,
now checking schema privileges rather than extensions.

### Backups

Daily automatic backups with point-in-time recovery to any second in the
previous seven days, via WAL archiving. Not configurable on this plan, and not
something Terraform manages — but it is the reason
[ADR 0008](../../docs/adr/0008-postgres-do-managed.md) chose a managed database
over the in-cluster StatefulSet that already exists in the application chart.

### Version parity

Production runs PostgreSQL 17; local development runs `pgvector/pgvector:pg16`
in docker-compose and Kind. Worth closing by bumping the local image rather than
holding production back, but that is an application-repo change and is not done
yet.

## DNS delegation

`heptapedal.com` stays registered at Namecheap; DigitalOcean serves the zone
([ADR 0009](../../docs/adr/0009-dns-and-tls.md)). Terraform creates the zone,
but the delegation itself is a manual step at the registrar.

**Apply before switching.** The zone has to exist at DigitalOcean first,
otherwise the nameservers point at a provider with nothing to answer from and
the domain resolves to nothing.

1. `tofu apply` — creates the zone and its CAA records.
2. At Namecheap: **Domain List → Manage → Nameservers**, switch from
   *Namecheap BasicDNS* to *Custom DNS*, and enter:

   ```
   ns1.digitalocean.com
   ns2.digitalocean.com
   ns3.digitalocean.com
   ```

   Also available as `tofu output nameservers`.

   **Not the Advanced DNS tab.** Delegating an apex domain rewrites the `NS`
   records in the *parent* zone — the `.com` registry — which is what the
   registrar's nameserver setting controls. `NS` records added inside the
   Namecheap-hosted zone do nothing, because the parent still points every
   resolver at Namecheap. (Delegating a *subdomain* is the case where in-zone
   `NS` records are the mechanism; that is not this.)

   **Do not delete anything at Namecheap.** Switching to Custom DNS leaves the
   BasicDNS zone stored but unused, so reverting the nameserver setting is a
   working rollback. Keep that available until delegation is verified.

3. Wait, then verify:

   ```bash
   dig NS heptapedal.com +short          # expect the three above
   dig CAA heptapedal.com +short         # expect letsencrypt.org
   ```

### How long, and what happens meanwhile

The registry push is quick — minutes — but the `.com` zone publishes this
domain's delegation with a **48 hour TTL**:

```
$ dig @a.gtld-servers.net NS heptapedal.com
heptapedal.com.  172800  IN  NS  dns1.registrar-servers.com.
```

So a resolver that already cached the old delegation may keep asking Namecheap
for up to two days. Most refresh sooner, but plan for 48 hours rather than
treating a stale answer as a failure.

During that window **both zones are live**, each serving whichever resolvers
still point at it. That is survivable precisely because the two agree on the
records that matter: the four email records are replicated verbatim, so mail
authentication holds no matter which nameserver answers. It is also the reason
not to delete anything at Namecheap yet — doing so would make the transition a
cliff instead of an overlap.

The apex is the one place they disagree: Namecheap answers with a parking page,
DigitalOcean with nothing until #20. Nobody depends on either.

Certificate issuance in #11 uses a DNS-01 challenge and cannot succeed until the
delegation has taken effect, which is why this runs early.

**Email authentication is migrated, and it is load-bearing.** Four records in
`dns-email.tf` carry Resend — Supabase's custom SMTP — and therefore the
sign-up confirmation and password-reset links. Sign-up is email-first, so
breaking them breaks the only way to create an account.

| Name | Type | Purpose |
|---|---|---|
| `send` | TXT | SPF for the custom MAIL FROM domain |
| `send` | MX | SES bounce and complaint handling |
| `resend._domainkey` | TXT | DKIM public key |
| `_dmarc` | TXT | DMARC policy |

They are replicated verbatim, TTLs included. **Apply before switching**, then
confirm DigitalOcean answers for all four (see the verification step above) —
the switch is only safe once it does.

Everything else in the Namecheap zone is deliberately not carried across:

| Record | Why not |
|---|---|
| apex `A` → `192.64.119.97` | Namecheap's parking page |
| `www` → `parkingpage.namecheap.com` | the same parking page |
| `NS`, `SOA` | belong to whoever hosts the zone; DigitalOcean creates its own |

**Confirm against the registrar, not only `dig`.** Querying can only probe names
you think to ask for; it cannot enumerate a zone. The email records above were
nearly missed for exactly that reason. Read Namecheap's Advanced DNS page and
reconcile it against `dns-email.tf` before changing nameservers.

**The domain stops resolving until #20.** After delegation the zone has CAA
records and nothing else — no apex `A` — because there is no Load Balancer to
point at yet. Expected, not a fault. It replaces a parking page, so nothing of
value is lost in the interval.

## Things that will cost money if changed carelessly

- **`ha = false` is load-bearing.** On Kubernetes 1.36 and later the provider
  defaults it to `true`, which is a 40 USD/month high-availability control
  plane — 40% of the budget, for an availability target
  [ADR 0004](../../docs/adr/0004-kubernetes-on-doks.md) declines to buy. It is
  irreversible: DigitalOcean cannot turn HA off once a cluster has it. Deleting
  that line is a silent, permanent price rise.
- **Node count is fixed at 2, not autoscaled.** The budget has roughly 20
  USD/month of headroom and an autoscaler is what spends it without asking. If
  the cluster genuinely needs to grow, do it deliberately.
- **`destroy_all_associated_resources` is false.** Destroying the cluster
  therefore leaves behind any Load Balancer or volume the Kubernetes API
  created — recoverable, but it bills silently. After any teardown, check for
  an orphaned Load Balancer. The billing alert in #7 is the backstop.

## Kubernetes version

`kubernetes_version_prefix` pins the minor; the newest patch within it is
selected, and `auto_upgrade` applies later patches during the maintenance
window (Sundays 10:00 UTC, which is 03:00 Pacific).

DigitalOcean supports the three most recent minors. As of 2026-08: 1.34 (end of
support 2026-10-27), 1.35 (2027-02-28), 1.36 (2027-06-28). Pinned to 1.36 for
the longest runway. List what is actually offered with:

```bash
doctl kubernetes options versions
```

Bumping the minor is a one-line change, but read the upstream changelog first —
minor upgrades are not automatic for a reason.
