# bootstrap

Creates the DigitalOcean Spaces bucket that every stack keeps its state in.

This is the one apply that cannot start from remote state — the remote state
does not exist yet. So it runs twice: once with local state to create the
bucket, then again to move its own state into the bucket it just made. After
that the stack self-hosts and no state file is ever committed
([ADR 0012](../../docs/adr/0012-treat-the-repository-as-publishable.md)).

Run approximately once, by hand, before anything else.

## Prerequisites

1. **A DigitalOcean API token** — Control panel → API → Tokens, with write scope.
2. **A Spaces access key** — Control panel → Spaces Object Storage → Access Keys.

   Created **by hand, deliberately**: this key is what reads the state, so it
   must not live only inside that state. Terraform can create Spaces keys, but a
   credential whose only copy is the object it unlocks is not recoverable. Same
   reasoning as [ADR 0007](../../docs/adr/0007-secrets-sealed-secrets.md) — never
   let the ciphertext be the only copy.

3. Copy `.envrc.example` from the repository root to `.envrc`, fill both in, and
   `direnv allow`. The Spaces key is exported under two names because the
   provider reads `SPACES_*` and the backend reads `AWS_*`.

## Step 1 — create the bucket, with local state

`backend.tf` is already committed, so skip backend initialisation for this pass:

```bash
cd terraform/bootstrap
tofu init -backend=false
tofu apply
```

The state file this leaves behind is transient and gitignored. Do not commit it.

## Step 2 — move the state into the bucket

```bash
tofu init -migrate-state    # answer yes when asked to copy the existing state
rm terraform.tfstate*       # the local copy, now superseded
```

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
tofu import digitalocean_spaces_bucket.tfstate sgp1,heptapedal-tfstate
```

**Bucket names are unique across all of Spaces**, not just this account. If
`apply` fails on a name collision, change `bucket_name` — and `backend.tf`, which
cannot reference variables.

**Region** is `sgp1`: DigitalOcean has no Tokyo datacenter, and Singapore is the
closest one that offers Spaces, DOKS, Managed Postgres and Load Balancers. Every
other stack should stay in the same region.
