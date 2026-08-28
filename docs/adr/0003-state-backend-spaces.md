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
- versioning enabled on the bucket, so a corrupted state can be rolled back
- the AWS-isms the provider does not apply to Spaces switched off
  (`skip_credentials_validation`, `skip_metadata_api_check`, `skip_region_validation`,
  `skip_requesting_account_id`)
- one key per stack: `platform/terraform.tfstate`, `argocd/terraform.tfstate`

Bootstrap is explicitly two-step and documented in `terraform/bootstrap/`: create
the bucket with local state, then migrate. `terraform/bootstrap/` keeps its own
state committed as a checked-in local file, since it holds nothing sensitive and
is applied roughly once.

## Consequences

- 5 USD/month, within the budget in [0004](0004-kubernetes-on-doks.md)'s costing.
- Locking and storage are one service, and that service is the same cloud account
  as everything else — one credential to rotate.
- The chicken-and-egg step is visible rather than hidden. That is intentional; it
  is the honest way to show how a state backend actually gets created.
- Spaces has no cross-region replication here. State loss would mean re-importing;
  bucket versioning is the mitigation, and the resource count is small enough that
  re-import is a bad afternoon, not a disaster.

## Alternatives considered

- **Postgres (`pg`) backend on the Supabase project.** Free, and locking is real
  (advisory locks). Genuinely tempting and the fallback if the budget tightens.
  Rejected because it couples state to a database that [0008](0008-postgres-do-managed.md)
  keeps on a free tier that pauses on inactivity — a paused project would block
  every apply.
- **HCP Terraform free tier.** Free, managed state, good UI. Rejected: it pulls
  the workflow onto a SaaS control plane, which cuts against [0002](0002-iac-tool-opentofu.md),
  and the run environment becomes another thing to configure.
- **Committed local state.** Fine for `bootstrap/`, not for anything CI applies.
