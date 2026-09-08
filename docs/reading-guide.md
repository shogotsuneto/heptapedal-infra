# Reading this repository

Written for someone evaluating the work rather than running it. If you want to
operate it, [`rebuild.md`](rebuild.md) and the stack READMEs are the place to
start instead.

## How it was built

An operator and an AI coding agent, working through pull requests: the agent
proposed and implemented, the operator decided and merged. Everything went
through a pull request, including changes that only touched a comment.

Two effects are visible in the history. Rationale tends to be written at the
moment of the decision, because the alternative had just been argued about. And
the agent was confidently wrong several times — **every correction started with
a question from the operator**, not with the agent noticing. Those exchanges are
listed below rather than tidied away, because they are the part with something
to say.

## What is worth looking at

### The design, before any of it existed

**[#27](https://github.com/shogotsuneto/heptapedal-infra/pull/27) — record the initial architecture decisions.** Twelve ADRs and a
README, no infrastructure code: the design the build-out then followed, opened
so it could be disagreed with before Phase 3 rather than during it. Nine commits
and seven rounds of comments, which is what that disagreement looked like.

Reading it against what shipped is the useful part. Most of it held. Two
decisions did not, and were superseded rather than quietly edited —
[0005 → 0014](adr/0014-use-the-provider-gateway-implementation.md) and
[0012 → 0015](adr/0015-plan-locally.md).

### Where a question found a real defect

**[#34](https://github.com/shogotsuneto/heptapedal-infra/pull/34) — carry the Resend email records across before delegating.** The
previous pull request had said nothing needed migrating. That was wrong: four
records carried Supabase's outbound mail, and sign-up is email-first, so losing
them would have broken the only way to create an account. The sweep that missed
them ran `dig` without a record type, so `_dmarc` looked empty — the operator
remembered the records existed. The runbook now says to reconcile against the
registrar, because querying only probes names you already think to ask for.

**[#79](https://github.com/shogotsuneto/heptapedal-infra/pull/79) — alert rules in git.** A question about why the threshold stage
re-evaluated what the PromQL had already decided. It did not: a bare PromQL
comparison *filters* rather than returning a truth value, so
`replicas_available < 1` breaches with the value `0`, and a `> 0` threshold on
that is false. **The alert for the site being down could never have fired.**

**[#95](https://github.com/shogotsuneto/heptapedal-infra/pull/95) — one schedule, because two disagreed.** "Will the pending update
appear on Monday?" It would not have: the cron fired at 13:00 UTC, which is
06:00 in Vancouver, and the tool's own schedule was `before 6am` — a window that
closes at 06:00. Two schedules set to the same moment never overlap.

**[#102](https://github.com/shogotsuneto/heptapedal-infra/pull/102) / [#103](https://github.com/shogotsuneto/heptapedal-infra/pull/103) — the required check.** "That job only runs on
Terraform paths, doesn't it?" It did, so requiring it would have left every
documentation pull request waiting forever on a status that never arrives.

### Where a measurement overturned an assumption

**[#71](https://github.com/shogotsuneto/heptapedal-infra/pull/71) — the load balancer idle timeout was never ours to set.** A
connection surviving 70 seconds and dying by 610 was read as proof the
600-second setting worked. It bounds the timeout to (70, 610] and proves nothing
about 600 — the number came from the configuration, not the observation. The API
settled it: a `REGIONAL_NETWORK` balancer forwards plain TCP and has no HTTP
layer to hold an HTTP idle timeout.

**[#86](https://github.com/shogotsuneto/heptapedal-infra/pull/86) — projected usage replaced with metered.** Including a question
that straddled a free-tier allowance: are init containers billed? The metered
rate is 971.21 container hours a day, which is 40.5 containers; the cluster runs
40, with 15 init containers beside them. They are not.

**[#83](https://github.com/shogotsuneto/heptapedal-infra/pull/83) — the latency panel asked Loki for a series per request.** A bare
`| json` promotes every parsed field to a label, `trace_id` included. Three
panels survived only because `sum by (...)` discarded the explosion — **they were
never correct, only hidden.**

### Where ordering was the whole problem

**[#55](https://github.com/shogotsuneto/heptapedal-infra/pull/55) — SealedSecrets need `SkipDryRunOnMissingResource` too.** Argo CD
validates every task before any wave runs, so a wave-1 `SealedSecret` is checked
against a CRD the wave-0 controller has not installed yet, and the bundle fails
before wave 0 can run. Only reachable from an empty cluster, which is why it was
found the hard way.

**[#68](https://github.com/shogotsuneto/heptapedal-infra/pull/68) — make room for the application's secret, ahead of PreSync.** The
migration Job is a Helm hook, which Argo CD runs *before* the Application's own
resources exist — so a Secret shipped with the application arrives after the Job
has already tried to read `DATABASE_URL` from it.

### Where the cost of something exceeded its value

**[#72](https://github.com/shogotsuneto/heptapedal-infra/pull/72) — drop the load balancer check block.** A Terraform `check` that
detected a stale DNS record cost 69% of every plan's output and a token scope,
to look only at the moment someone planned. Removed in favour of continuous
external monitoring — and the replacement was then built ([#85](https://github.com/shogotsuneto/heptapedal-infra/pull/85)) rather
than assumed.

**[#88](https://github.com/shogotsuneto/heptapedal-infra/pull/88) — stop planning in CI.** CI planned one stack of four, because
the other three needed credentials a pull-request workflow should not hold. A
gate over a third of the infrastructure that reads like a gate over all of it is
worse than no gate. This adopts an alternative
[ADR 0012](adr/0012-treat-the-repository-as-publishable.md) had explicitly
rejected, so it needed [an ADR of its own](adr/0015-plan-locally.md).

### Where each failure hid the next

**[#89](https://github.com/shogotsuneto/heptapedal-infra/pull/89) → [#96](https://github.com/shogotsuneto/heptapedal-infra/pull/96) → [#97](https://github.com/shogotsuneto/heptapedal-infra/pull/97) → [#98](https://github.com/shogotsuneto/heptapedal-infra/pull/98).** Getting Renovate
to open one pull request took four attempts, because each missing permission was
only reachable once the previous one was granted — and **not one of the errors
named a permission**:

| Missing | Reported as |
|---|---|
| `issues` | a `FORBIDDEN` on a GraphQL field |
| `statuses` (read) | `integration-unauthorized` |
| `statuses` (write) | `repository-changed` |
| *(a repository setting, not a permission)* | `403` on the final call |

Every one of those runs **reported success**, because the tool logs these at
`WARN` and exits non-zero only on `ERROR`.

### Where a decision was made about credentials

**[#77](https://github.com/shogotsuneto/heptapedal-infra/pull/77) — keep Supabase awake from the cluster.** Moved out of GitHub
Actions for two reasons that are both about not keeping a second copy of a
value. The opposite decision was made for Renovate ([#87](https://github.com/shogotsuneto/heptapedal-infra/pull/87)), and the
difference is written down: what a missed run costs, and whether the thing being
automated acts on this repository.

**[#78](https://github.com/shogotsuneto/heptapedal-infra/pull/78) — a grant, not only a policy.** An RLS policy without a table
grant denies everything. Postgres returned the exact statement that fixed it,
which is better than any message written in advance — so the job now points at
the response body instead of competing with it.

### If you want to see the shape of a stack

**[#29](https://github.com/shogotsuneto/heptapedal-infra/pull/29) — bootstrap the Spaces bucket for remote state**, eight commits
of getting the chicken-and-egg right: the bucket that holds the state is created
with local state, then migrated into itself.
**[#43](https://github.com/shogotsuneto/heptapedal-infra/pull/43)** installs Argo CD and **[#44](https://github.com/shogotsuneto/heptapedal-infra/pull/44)** hands it the single root
Application, which is where Terraform's responsibility stops.
**[#59](https://github.com/shogotsuneto/heptapedal-infra/pull/59)** is telemetry, and the first place resource requests were
corrected against measurement rather than guessed.

## Where to start if you only read one thing

[`docs/adr/`](adr/README.md). Sixteen decisions with the alternatives that lost
and why. They are append-only — superseded rather than edited — so the record
includes the two occasions a decision turned out to be wrong
([0005 → 0014](adr/0014-use-the-provider-gateway-implementation.md),
[0012 → 0015](adr/0015-plan-locally.md)).
