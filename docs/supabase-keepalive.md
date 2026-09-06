# Keeping the Supabase project awake

Free projects pause after a week without activity. Authentication lives there
([ADR 0008](adr/0008-postgres-do-managed.md)), so a pause is a login outage: the
site keeps serving pages and nobody can sign in.

`.github/workflows/supabase-keepalive.yml` queries the project daily. Setup is
two steps, both one-time.

## 1. Create the row it queries

Supabase → SQL Editor. This exists to be selected from; it holds nothing.

```sql
create table if not exists public.keepalive (
  id smallint primary key,
  constraint keepalive_single_row check (id = 1)
);

insert into public.keepalive (id) values (1) on conflict (id) do nothing;

alter table public.keepalive enable row level security;

create policy keepalive_anon_select
  on public.keepalive for select to anon
  using (true);
```

**Why a table rather than a health check.** The documented rule is *sufficient
user database activity*, and `/auth/v1/health` answers from configuration
without touching Postgres — it would prove the project responds while doing
nothing about the thing that pauses it. A `select` cannot succeed without a
query running.

The RLS policy grants `anon` nothing but the ability to read a row containing
the number 1.

## 2. Add two repository secrets

`SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY`, the same values as the sealed
`app-secrets`.

Secrets rather than variables, though the publishable key is already in every
visitor's browser. That is hygiene rather than a boundary — the same reasoning
as the plan-comment masking in ADR 0012: no reason to copy an identifier onto an
indexed page.

## Verify

Run the workflow by hand — **Actions → supabase-keepalive → Run workflow**. It
should print `HTTP 200` and a row. It fails loudly on anything else, and the
message names the three things it can be: a paused project, a missing table, or
a rotated key.

The ping is also the check. A paused project cannot answer, so there is no
separate probe that could rot without anyone noticing.

## Two ways this quietly stops working

**Scheduled workflows are disabled after 60 days without repository activity**,
[on public repositories](https://docs.github.com/actions/using-workflows/events-that-trigger-workflows).
This repository is meant to become public (ADR 0012), so the trap arms then, and
it chains: the workflow stops, the project pauses, login breaks — three silent
steps from "nobody committed for two months". Renovate (#21) helps by keeping a
trickle of pull requests, which counts as activity; that is a side effect worth
knowing rather than a plan.

**A weekly cadence would have no margin.** The window is seven days and GitHub
delays scheduled runs under load, so the job runs daily even though the ADR
first sketched it weekly.

## The actual fix

Supabase Pro, 25 USD/month, removes pausing. This is a mitigation and ADR 0008
says so. If login reliability ever matters, the cost is already known.
