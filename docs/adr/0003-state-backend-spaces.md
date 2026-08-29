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

Bootstrap is explicitly two-step and documented in `terraform/bootstrap/`: create
the bucket with local state, then **migrate the bootstrap stack's own state into
the bucket it just created**. The stack self-hosts; no state file is ever
committed.

The local state produced during that first apply is transient and
`.gitignore`d. State records every resource attribute in plaintext — including
values marked sensitive, and including the Spaces access keys if the stack
creates them — so "it holds nothing sensitive" is not a claim that survives
contact with a real bootstrap. See [0012](0012-treat-the-repository-as-publishable.md).

## Consequences

- 5 USD/month, within the budget in [0004](0004-kubernetes-on-doks.md)'s costing.
- Locking and storage are one service, and that service is the same cloud account
  as everything else — one credential to rotate.
- The chicken-and-egg step is visible rather than hidden. That is intentional; it
  is the honest way to show how a state backend actually gets created.
- **Self-hosting buys exactly one thing: no state in git history.** Under
  [0012](0012-treat-the-repository-as-publishable.md) that is decisive on its own.
  It buys no recovery advantage — see below — and it costs one wart: `tofu destroy`
  on the bootstrap stack cannot finish cleanly, because after deleting the bucket
  Terraform tries to persist the resulting state into it and fails, leaving an
  `errored.tfstate` on disk. Acceptable for a stack that is destroyed
  approximately never.

### The bucket is a single point of failure for all state

This is the risk that matters, and it is unaffected by where the bootstrap stack
keeps its own state.

- Losing the bucket does not orphan the bootstrap stack in any interesting sense:
  the bucket and the state describing it disappear together, so there is nothing
  left dangling. What it **does** orphan is `platform/` and `argocd/` — a DOKS
  cluster, node pool, managed Postgres, VPC, firewall, project, and DNS records
  that all still exist at DigitalOcean with nothing recording them. Recovering
  that is a full re-import of the platform, not the "single `import` block" an
  earlier draft of this ADR claimed.
- A committed bootstrap state would not help. It would let `apply` recreate the
  bucket — an **empty** one. The contents are what mattered, and they are gone
  either way. That is why the recovery argument for self-hosting was dropped: it
  was never true.
- **Bucket versioning does not protect against this.** It protects an object from
  being overwritten or deleted; it does nothing about the bucket itself.
- The protection that actually works is that S3 and Spaces refuse to delete a
  non-empty bucket. So long as `force_destroy` stays `false`, a `destroy` cannot
  take the bucket while any other stack's state is in it. `prevent_destroy` is the
  second belt. **Neither is optional — they are the mitigation.**
- Beyond that: state is backed up out of band, and the restore is exercised as
  part of the rebuild runbook rather than assumed.

## Alternatives considered

- **Postgres (`pg`) backend on the Supabase project.** Free, and locking is real
  (advisory locks). Genuinely tempting and the fallback if the budget tightens.
  Rejected because it couples state to a database that [0008](0008-postgres-do-managed.md)
  keeps on a free tier that pauses on inactivity — a paused project would block
  every apply.
- **HCP Terraform free tier.** Free, managed state, good UI. Rejected: it pulls
  the workflow onto a SaaS control plane, which cuts against [0002](0002-iac-tool-opentofu.md),
  and the run environment becomes another thing to configure.
- **Committed local state for `bootstrap/`.** The original proposal here, and
  wrong. State is plaintext and git history is permanent; a file committed while
  the repository is private is published the day the repository is, retroactively.
  Rejected under [0012](0012-treat-the-repository-as-publishable.md) — and note
  that this is the *only* reason it is rejected. On recovery it is a wash, and on
  clean `destroy` it is marginally better than self-hosting.
- **Creating the bucket by hand (console or `doctl`), outside Terraform.** Honest
  about it being a one-time out-of-band resource, and removes the chicken-and-egg
  entirely. A reasonable choice; passed over because self-hosting keeps the bucket
  under the same review and drift-detection as everything else, at similar cost.
