# 0013. Run everything in sfo3

- **Status:** Accepted
- **Date:** 2026-08-30

## Context

Every stack has to name a region, and they all have to name the same one: the
DOKS cluster, its Load Balancer, the Managed Postgres it connects to over the
VPC, and the Spaces bucket holding state. Splitting them adds cross-region
latency to the data path and, for the database, breaks the VPC-scoped firewall
in [0008](0008-postgres-do-managed.md).

So it is one decision, made once, that every later stack inherits.

The operator is in Vancouver. Bringing in users is explicitly not a goal, so
there is no user population whose latency competes — the person operating the
platform and using the application is the same person, and the distance that
matters is to them.

DigitalOcean has no Canadian region other than Toronto, and no Pacific Northwest
region at all. Spaces, DOKS, Managed Postgres and Load Balancers are all
available in every active datacenter, so availability does not narrow the field.

## Decision

**`sfo3`.** San Francisco is roughly 1,300 km from Vancouver against Toronto's
3,350 km — very roughly 20 ms round trip against 65 ms.

The region is a variable in every stack, defaulted here, and additionally a
literal in each `backend.tf`, because a backend block cannot reference
variables. Changing it means changing both.

The Supabase project is in US East and stays there. The cross-country hop never
reaches a hot path: the application verifies each request's JWT locally against a
cached JWKS, so Supabase is called on sign-in, sign-up and password reset only,
not per request. Moving it would in any case be worse than pointless — `users.id`
*is* the Supabase user UUID, so a new project re-issues every identity and
orphans the application's rows.

## Consequences

- The lowest latency available for the person actually using the system.
- No effect on [0004](0004-kubernetes-on-doks.md)'s cost model: DigitalOcean
  publishes one price list with no regional dimension. What varies by datacenter
  is which Droplet *plans* exist, not what a plan costs, and sfo3 carries the
  standard shared-CPU line the node pool uses.
- Application data sits in the United States. That is a real consequence and the
  only serious argument for Toronto; it is accepted because this is personal
  data belonging to the operator, on a project with no third-party users to
  make promises to.
- No end-to-end Canadian residency was available anyway without also moving
  Supabase — and authentication is the surface where identity data actually
  lives. Choosing Toronto for the cluster alone would have bought the appearance
  of residency rather than residency.
- Moving later is not free: the cluster, database and bucket would all be
  rebuilt, and the state bucket is the one holding the record of everything
  else. Worth settling now rather than after Phase 1.

## Alternatives considered

- **`tor1` (Toronto).** The choice if Canadian data residency matters. Rejected:
  roughly triple the distance for a benefit this project cannot actually
  complete, since Supabase would have to follow and identity data is the part
  residency would be about.
- **`sgp1` (Singapore).** In the first draft of the bootstrap stack, from a
  stale assumption about where the operator is. Recorded because the mistake is
  instructive: region is exactly the kind of default that gets set once and
  inherited by everything, so it is worth stating rather than defaulting.
- **Multi-region.** Rejected on cost and on there being nothing to make
  available: one operator, one cluster, an availability target
  [0004](0004-kubernetes-on-doks.md) already declines to pay for.
