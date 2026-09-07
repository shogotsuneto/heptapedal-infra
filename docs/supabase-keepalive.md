# Keeping the Supabase project awake

Free projects pause after a week without activity. Authentication lives there
([ADR 0008](adr/0008-postgres-do-managed.md)), so a pause is a login outage: the
site keeps serving pages and nobody can sign in.

`gitops/apps/heptapedal/supabase-keepalive.yaml` is a CronJob that queries the
project daily. One thing has to exist for it to query.

## Setup: create the row it queries

Supabase → SQL Editor. This exists to be selected from; it holds nothing.

```sql
create table if not exists public.keepalive (
  id smallint primary key,
  constraint keepalive_single_row check (id = 1)
);

insert into public.keepalive (id) values (1) on conflict (id) do nothing;

-- Two separate layers, and both are needed. The grant decides whether the role
-- may touch the table at all; the policy decides which rows it then sees.
-- Postgres checks the grant first, so a policy without a grant is
-- `permission denied for table keepalive` — which is how this was first
-- written, and how it first failed.
grant select on public.keepalive to anon;

alter table public.keepalive enable row level security;

create policy keepalive_anon_select
  on public.keepalive for select to anon
  using (true);
```

RLS is enabled even though the table holds nothing worth protecting: a table in
`public` without it trips Supabase's own security advisor, and the policy costs
one line.

**Why a table rather than a health check.** The documented rule is *sufficient
user database activity*, and `/auth/v1/health` answers from configuration
without touching Postgres — it would prove the project responds while doing
nothing about the thing that pauses it. A `select` cannot succeed without a
query running.

The RLS policy grants `anon` nothing but the ability to read a row containing
the number 1.

The CronJob needs nothing else. It reads `SUPABASE_URL` and
`SUPABASE_PUBLISHABLE_KEY` from the sealed `app-secrets` the application already
uses, so those values keep one home and a rotation has one place to reach
([ADR 0007](adr/0007-secrets-sealed-secrets.md)).

## Verify

Trigger a run without waiting for the schedule:

```bash
kubectl create job -n hepta --from=cronjob/supabase-keepalive keepalive-check
kubectl logs -n hepta job/keepalive-check
kubectl delete job -n hepta keepalive-check
```

It should print `HTTP 200` and a row.

On anything else it fails loudly and prints the response body, which is where
the useful detail is — Postgres names the missing privilege and the exact
`grant` that fixes it, which no message written in advance could do as well.

The ping is also the check. A paused project cannot answer, so there is no
separate probe that could rot without anyone noticing.

## Why not GitHub Actions

It was written that way first. Two things argued it back into the cluster, and
both are about not keeping a second copy of something:

- **The credentials are already here.** A workflow needs `SUPABASE_URL` and
  `SUPABASE_PUBLISHABLE_KEY` as repository secrets — a second copy of values
  that already live in `app-secrets`, and a second place a rotation has to
  reach.
- **Scheduled workflows are disabled after 60 days without repository
  activity** on
  [public repositories](https://docs.github.com/actions/using-workflows/events-that-trigger-workflows),
  and this one is meant to become public (ADR 0012). That chains quietly:
  workflow stops, project pauses, login breaks — three steps from "nobody
  committed for two months".

What moving it costs: a failing workflow emails the repository owner, and a
failing CronJob does not. The Job's failure does reach Grafana already
(kube-state-metrics is enabled), so what is missing is an alert rule — #23's
work either way, since "alert if the ping fails" was never free.

A cluster outage longer than a week would now also pause the project. That is a
real coupling, and a small one: a cluster down for seven days is a rebuild
(#24), and unpausing is a click.

**A weekly cadence would have no margin.** The window is seven days, so the job
runs daily even though the ADR first sketched it weekly.

## The actual fix

Supabase Pro, 25 USD/month, removes pausing. This is a mitigation and ADR 0008
says so. If login reliability ever matters, the cost is already known.
