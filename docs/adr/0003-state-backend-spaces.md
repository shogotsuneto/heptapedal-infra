# 0003. Store state in DigitalOcean Spaces with native locking

- **Status:** Accepted
- **Date:** 2026-08-27

## Context

Remote state is required as soon as CI applies anything: it has to be shared
between a laptop and a GitHub Actions runner, and concurrent applies have to be
prevented.

Historically the S3 backend needed a companion DynamoDB table for locking, which
made S3-compatible object stores awkward. That changed in Terraform 1.10 /
OpenTofu: `use_lockfile = true` implements locking with an S3 conditional write
(`If-None-Match` on a `.tflock` object next to the state), no second service
involved. DigitalOcean documents Spaces as a supported backend for exactly this.

Spaces is 5 USD/month — the only line item here that buys no runtime capacity.

## Decision

`s3` backend against DigitalOcean Spaces, with:

- `use_lockfile = true` (no DynamoDB, no `dynamodb_table`)
- versioning enabled on the bucket, so a corrupted or overwritten state object can
  be rolled back
- `force_destroy = false` on the bucket, and `lifecycle { prevent_destroy = true }`
- the AWS-isms the provider does not apply to Spaces switched off
  (`skip_credentials_validation`, `skip_metadata_api_check`, `skip_region_validation`,
  `skip_requesting_account_id`)
- one key per stack: `platform/terraform.tfstate`, `argocd/terraform.tfstate`

The bucket is a Terraform resource like everything else, in
`terraform/bootstrap/`, applied once: create it with local state, then migrate
that state into the bucket it just created. The stack self-hosts, and the
transient local state is `.gitignore`d rather than committed.

Managing the bucket in Terraform rather than making it by hand is what puts
`force_destroy = false`, `prevent_destroy`, and versioning under review and drift
detection. On a hand-made bucket those are settings someone selected once, with
nothing re-asserting them.

## Consequences

- 5 USD/month, within the budget in [0004](0004-kubernetes-on-doks.md)'s costing.
- Locking and storage are one service, and that service is the same cloud account
  as everything else — one credential to rotate.
- The chicken-and-egg step is visible rather than hidden. That is intentional; it
  is the honest way to show how a state backend actually gets created.
- The bucket holds every stack's state, so losing it orphans `platform/` and
  `argocd/`: a DOKS cluster, managed Postgres, VPC, firewall and DNS records still
  running at DigitalOcean with nothing recording them. Recovery is a full
  re-import. Worth being precise about what guards that, because versioning does
  not — it protects an object from overwrite or deletion, not the bucket. The real
  guard is that S3 and Spaces refuse to delete a non-empty bucket, so
  `force_destroy = false` means no `destroy` can take it while any other stack's
  state is inside. `prevent_destroy` is the second belt. State is also backed up
  out of band, with the restore exercised in the rebuild runbook.
- `destroy` on the bootstrap stack cannot finish cleanly: after deleting the
  bucket, Terraform tries to persist the resulting state into it and fails,
  leaving an `errored.tfstate`. Expected; the stack is destroyed approximately
  never.

## Alternatives considered

- **Postgres (`pg`) backend on the Supabase project.** Free, and locking is real
  (advisory locks). Genuinely tempting and the fallback if the budget tightens.
  Rejected because it couples state to a database that [0008](0008-postgres-do-managed.md)
  keeps on a free tier that pauses on inactivity — a paused project would block
  every apply.
- **HCP Terraform free tier.** Free, managed state, good UI. Rejected: it pulls
  the workflow onto a SaaS control plane, which cuts against [0002](0002-iac-tool-opentofu.md),
  and the run environment becomes another thing to configure.
- **Creating the bucket by hand (console or `doctl`), outside Terraform.** The
  real alternative: honest that it is a one-time out-of-band resource, and it
  removes the chicken-and-egg entirely. Rejected because the bucket's protections
  are the whole game — `force_destroy = false`, `prevent_destroy`, versioning —
  and by hand they are clicks nobody re-asserts, on the one resource whose loss
  costs the most. Declaring them buys more than the two-step bootstrap costs.
- **Committing `bootstrap/`'s state instead of migrating it.** Rejected under
  [0012](0012-treat-the-repository-as-publishable.md): state is plaintext and git
  history is permanent, so a file committed while the repository is private is
  published the day the repository is.
