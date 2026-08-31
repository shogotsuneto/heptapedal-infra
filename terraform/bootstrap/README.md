# bootstrap

Creates the DigitalOcean Spaces bucket that every stack keeps its state in.

This is the one apply that cannot start from remote state — the remote state
does not exist yet. So it runs twice: once with local state to create the
bucket, then again to move its own state into the bucket it just made. After
that the stack self-hosts and no state file is ever committed
([ADR 0012](../../docs/adr/0012-treat-the-repository-as-publishable.md)).

Run approximately once, by hand, before anything else.

## Prerequisites

1. **A DigitalOcean API token** — Control panel → API → Tokens. Not Full Access;
   the scopes below are what Phase 1 needs, and the token is long-lived because
   DigitalOcean has no OIDC federation, so give it an expiry and diarise the
   rotation.

   ```
   account:read  regions:read  sizes:read  spaces:read
   project:create     project:read     project:update     project:delete
   project:assign_resource
   vpc:create         vpc:read         vpc:update         vpc:delete
   kubernetes:create  kubernetes:read  kubernetes:update  kubernetes:delete
   kubernetes:access_cluster
   database:create    database:read    database:update    database:delete
   database:view_credentials
   domain:create      domain:read      domain:update      domain:delete
   tag:create         tag:read          tag:delete
   spaces_key:create  spaces_key:read   spaces_key:update  spaces_key:delete
   spaces_key:create_credentials
   ```

   The two easy to miss are `kubernetes:access_cluster` (retrieves the
   kubeconfig) and `database:view_credentials` (retrieves the connection URI);
   without them the platform stack cannot produce its outputs.
   `load_balancer:*` and `droplet:*` are **not** needed — DOKS creates both with
   its own credentials.

   cert-manager gets its **own, separate** token later (`domain:read`,
   `domain:update`), because a token living in the cluster should not carry
   infrastructure-wide rights.

2. **A full-access Spaces key** — Control panel → Spaces Object Storage →
   Access Keys.

   This, not the API token, is what creates the bucket: Spaces bucket CRUD goes
   over the S3 API, which is why DigitalOcean publishes no `spaces:create` scope
   at all. It has to be **full access**, because only a full-access key can
   create a bucket or set its versioning and lifecycle configuration — a
   bucket-limited key cannot, however permissive its grant.

   That is why this stack also **issues a second, bucket-scoped key** for
   everything else. The full-access key applies this stack, by hand, roughly
   never. The scoped key is what every stack's backend uses on every plan, and
   what ends up in GitHub Actions secrets — so it is limited to the state bucket
   and cannot reach the rest of the account.

   Created **by hand, deliberately**: this key is what reads the state, so it
   must not live only inside that state. Terraform can create Spaces keys, but a
   credential whose only copy is the object it unlocks is not recoverable. Same
   reasoning as [ADR 0007](../../docs/adr/0007-secrets-sealed-secrets.md) — never
   let the ciphertext be the only copy.

3. Copy `.envrc.example` from the repository root to `.envrc` and
   `direnv allow`. Set `DIGITALOCEAN_TOKEN` and the full-access key as
   `SPACES_*`; the `AWS_*` pair comes from step 1's output.

## Step 1 — create the bucket, with local state

`backend.tf` is already committed, so skip backend initialisation for this pass:

```bash
cd terraform/bootstrap
tofu init -backend=false
tofu apply
```

The state file this leaves behind is transient and gitignored. Do not commit it.

This also issues the bucket-scoped backend key. Put it in `.envrc` before
continuing — the backend, not the provider, is what uses it:

```bash
tofu output backend_access_key_id
tofu output -raw backend_secret_access_key
```

## Step 2 — move the state into the bucket

With `AWS_*` now set to the scoped key:

```bash
tofu init -migrate-state    # answer yes when asked to copy the existing state
rm terraform.tfstate*       # the local copy, now superseded
```

If the migration fails on permissions, the scoped key is the thing to suspect —
it is deliberately the narrowest credential in the system.

Confirm it took:

```bash
tofu plan                   # no changes
tofu output backend_block   # paste-ready config for the next stack
```

## Notes

**`destroy` cannot finish cleanly.** After deleting the bucket, Terraform tries
to write the resulting state into it and fails, leaving an `errored.tfstate`.
Expected, not a bug — and it will not get that far anyway while other stacks
have state in the bucket, because `force_destroy = false` means a non-empty
bucket cannot be deleted. That is deliberate: see the comments in `main.tf`.

**If only this stack's state is lost** but the bucket still exists, re-import it
rather than recreating it:

```bash
tofu import digitalocean_spaces_bucket.tfstate sfo3,heptapedal-tfstate
```

**The scoped key is recoverable, not shown-once.** It lives in this stack's
state, so `tofu output -raw backend_secret_access_key` retrieves it whenever CI
or another machine needs it. Reading that state uses the key itself — or the
full-access key, if it is the scoped one you have lost.

**Bucket names are unique across all of Spaces**, not just this account. If
`apply` fails on a name collision, change `bucket_name` — and `backend.tf`, which
cannot reference variables.

**Region** is `sfo3` — see
[ADR 0013](../../docs/adr/0013-region-sfo3.md). Every other stack stays in the
same region.
