# 0008. Application data on DO Managed Postgres; auth stays on Supabase

- **Status:** Accepted
- **Date:** 2026-08-29

## Context

Two distinct database needs, currently conflated:

1. **Application data** — prompts, stories, links, and per-entity pgvector
   embedding tables with HNSW indexes. Requires the `vector`, `pgcrypto`, and
   `pg_trgm` extensions. Local dev runs `pgvector/pgvector:pg16` in-cluster; the
   application repo's own README says production should use a managed Postgres.
2. **Authentication** — Supabase GoTrue. The application verifies Supabase JWTs
   against the project JWKS. Replacing this means writing an identity provider,
   which is out of scope.

Supabase could serve both. The obstacle is the free tier: **projects pause after
seven days without API traffic**, capped at 500MB and two active projects. For a
portfolio application with sporadic traffic that is not a limit, it is a recurring
outage. Supabase Pro removes the pause at 25 USD/month per project.

DigitalOcean Managed Postgres starts at 15 USD/month for a single node with 1GiB
RAM, supports pgvector (0.7.2, on PG14–18), and can be firewalled to accept
connections only from a specific DOKS cluster.

## Decision

**Split by concern.**

- Application data → **DigitalOcean Managed Postgres**, single node, 15 USD/month.
  Placed in the same VPC, with a `digitalocean_database_firewall` trusting the
  DOKS cluster by resource type rather than by IP — node IPs are ephemeral.
  Extensions created via migration; `sqlx migrate run` continues to run as the
  chart's PreSync Job.
- Authentication → **Supabase, free tier**, unchanged. A weekly GitHub Actions
  cron pings the project so it never idles into a pause.
- Drop the in-cluster `postgres` chart in production. It stays as-is for local
  Kind, which is what it was built for.

## Consequences

- 15 USD/month rather than 25, and the pause risk is removed from the data path
  entirely.
- Managed backups, and the database is not competing for the cluster's ~6Gi.
- The VPC-scoped firewall rule is a genuinely nice thing to express in Terraform,
  and a better answer than an allowlist of node IPs.
- Auth still depends on a free tier that can pause. The cron is a mitigation, not
  a guarantee — if login reliability ever matters, Supabase Pro is the answer and
  the cost is understood in advance.
- Two databases, two connection strings, two consoles. Accepted: they have
  genuinely different requirements, and the application already treats Supabase as
  an external identity service rather than as its store.
- 1GiB is small. Fine for this data volume; embeddings are 384-dimensional and the
  corpus is personal-scale.

## Alternatives considered

- **Supabase Pro, one project for auth + data (25 USD/mo).** Simplest topology,
  one vendor. Rejected: 10 USD/month more, and it puts the primary datastore on a
  platform chosen for its auth.
- **Keep the in-cluster pgvector StatefulSet (0 USD).** Cheapest, and the chart
  already exists. Rejected: no managed backups, storage lifecycle becomes an
  operational burden, and "I ran my production database as a single-replica
  StatefulSet to save 15 dollars" is the wrong answer to the obvious follow-up
  question.
- **Supabase free for everything (0 USD).** Rejected on the pause behaviour.
