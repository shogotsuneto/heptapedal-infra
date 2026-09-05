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
   tag:create         tag:read         tag:delete
   load_balancer:read
   ```

   The two easy to miss are `kubernetes:access_cluster` (retrieves the
   kubeconfig) and `database:view_credentials` (retrieves the connection URI);
   without them the platform stack cannot produce its outputs.

   `droplet:*` is **not** needed — DOKS creates nodes with its own credentials —
   and neither is any `load_balancer` scope beyond **read**. Nothing here
   *manages* a Load Balancer; the read is for the `check` block in
   `../platform/dns-apex.tf`, which compares the apex A record against the
   address the Gateway's Load Balancer actually has. Omit it and every plan
   carries a warning. It is a read scope, so the pull-request `plan` environment
   gets it too.

   cert-manager gets its **own, separate** token later — `domain:read`,
   `domain:create`, `domain:delete` — because a token living in the cluster
   should not carry infrastructure-wide rights. Note the absence of
   `domain:update`: a DNS-01 challenge writes a TXT record and removes it, and
   never edits one, so the scope it would be natural to grant is one it does not
   use.

2. **A full-access Spaces key** — Control panel → Spaces Object Storage →
   Access Keys.

   This, not the API token, is what creates the bucket: Spaces bucket CRUD goes
   over the S3 API, which is why DigitalOcean publishes no `spaces:create` scope
   at all. It has to be **full access**, because only a full-access key can
   create a bucket or set its versioning and lifecycle configuration — a
   bucket-limited key cannot, however permissive its grant.

   Used only to apply this stack, by hand, roughly never.

3. **A bucket-scoped Spaces key** — same screen, Limited Access, granting
   Read/Write/Delete on the state bucket and nothing else. Create it after step
   1, once the bucket exists.

   This is the one that does the work: every stack's backend uses it on every
   plan, and it is what will sit in GitHub Actions secrets. Scoping it means a
   leak of the credential in CI reaches one bucket rather than the account.

   Both keys are created by hand. Terraform can manage Spaces keys, but doing so
   would mean granting the API token `spaces_key:create` and
   `create_credentials` — the ability to mint a full-access key — which would
   undo the scoping for anyone holding the token.

   Neither secret needs storing. Both are shown once, and both are reissuable
   from the control panel, which satisfies
   [ADR 0007](../../docs/adr/0007-secrets-sealed-secrets.md)'s invariant without
   a copy. Nothing binds to a key's ID: the backend reads `AWS_*` from the
   environment rather than naming a key, and DigitalOcean does not accept
   bucket policies against limited-access keys. Losing one costs a reissue and
   an edit to `.envrc` — and, later, the GitHub Actions secret.

   Created **by hand, deliberately**: this key is what reads the state, so it
   must not live only inside that state. Terraform can create Spaces keys, but a
   credential whose only copy is the object it unlocks is not recoverable. Same
   reasoning as [ADR 0007](../../docs/adr/0007-secrets-sealed-secrets.md) — never
   let the ciphertext be the only copy.

4. Copy `.envrc.example` from the repository root to `.envrc` and
   `direnv allow`. `SPACES_*` is the full-access key, `AWS_*` the scoped one.

## Step 1 — create the bucket, with local state

`backend.tf` is committed and active, and the bucket it names does not exist
yet. Override it for this one pass: OpenTofu merges `*_override.tf` over the
main configuration, replacing the backend block wholesale.

```bash
cd terraform/bootstrap
printf 'terraform {\n  backend "local" {}\n}\n' > local_override.tf
tofu init
tofu apply
```

`local_override.tf` is gitignored, so `main` never holds a stack whose backend
is commented out or missing — the deviation is local and temporary.

The state file this leaves behind is transient and gitignored. Do not commit it.

> `tofu init -backend=false` does **not** work here. It skips backend
> *initialisation*, but `apply` still sees the backend block in the
> configuration and refuses to run against an uninitialised backend.

Now create the bucket-scoped key (prerequisite 3) and put it in `.envrc` as
`AWS_*` — the backend, not the provider, is what uses it.

## Step 2 — move the state into the bucket

Drop the override and migrate:

```bash
rm local_override.tf
tofu init -migrate-state    # detects local -> s3; answer yes to copy the state
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

**Bucket names are unique across all of Spaces**, not just this account. If
`apply` fails on a name collision, change `bucket_name` — and `backend.tf`, which
cannot reference variables.

**Region** is `sfo3` — see
[ADR 0013](../../docs/adr/0013-region-sfo3.md). Every other stack stays in the
same region.
