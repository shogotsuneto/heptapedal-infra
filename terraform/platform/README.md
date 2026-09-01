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

```bash
tofu output -raw kubeconfig > ~/.kube/heptapedal.yaml
KUBECONFIG=~/.kube/heptapedal.yaml kubectl get nodes
```

**These credentials expire after 7 days.** Re-run the command to mint fresh
ones. This is also why the Argo CD stack does not consume a kubeconfig output:
a token captured in state goes stale and takes the `kubernetes` and `helm`
providers with it. It looks the cluster up by name with a
`digitalocean_kubernetes_cluster` data source instead, which reissues
credentials on every read. `cluster_name` is exported for exactly that.

## DNS delegation

`heptapedal.com` stays registered at Namecheap; DigitalOcean serves the zone
([ADR 0009](../../docs/adr/0009-dns-and-tls.md)). Terraform creates the zone,
but the delegation itself is a manual step at the registrar.

**Apply before switching.** The zone has to exist at DigitalOcean first,
otherwise the nameservers point at a provider with nothing to answer from and
the domain resolves to nothing.

1. `tofu apply` — creates the zone and its CAA records.
2. At Namecheap, set the domain to custom nameservers:

   ```
   ns1.digitalocean.com
   ns2.digitalocean.com
   ns3.digitalocean.com
   ```

   Also available as `tofu output nameservers`.

3. Wait, then verify:

   ```bash
   dig NS heptapedal.com +short          # expect the three above
   dig CAA heptapedal.com +short         # expect letsencrypt.org
   ```

Propagation is usually well under an hour but the registrar's TTL governs it.
Certificate issuance in #11 uses a DNS-01 challenge and cannot succeed until
this has taken effect, which is why it runs early.

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

Everything else in the Namecheap zone is a parking placeholder: an apex `A` to
Namecheap's parking IP and a `www` CNAME into it, both deliberately dropped.

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
