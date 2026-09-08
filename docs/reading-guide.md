# Reading this repository

Written for someone evaluating the work rather than running it. If you want to
operate it, [`rebuild.md`](rebuild.md) and the stack READMEs are the place to
start instead.

## How it was built

An operator and an AI coding agent, working through pull requests. The agent
proposed and implemented; the operator decided, questioned, and merged. Every
change here went through a pull request, including the ones that only touched a
comment.

Two things that arrangement changed, and one it did not.

**Rationale gets written at the moment of the decision.** Most of these commit
messages explain why the alternative was rejected, because the alternative had
just been argued about. That is hard to reconstruct a week later and easy to
capture at the time.

**Claims get checked more often than they get asserted.** Not reliably — see
below — but the habit shows: `docs/rebuild.md` says which parts are observed and
which are only derived; `gitops/platform/README.md` distinguishes projected
figures from metered ones and gives the arithmetic for both.

**Judgement did not move.** The agent was confidently wrong several times, and
in every case the correction started with a question from the operator rather
than from the agent noticing. Those exchanges are the most interesting part of
the history, so they are listed below rather than tidied away.

## What is worth looking at

### Where a question found a real defect

**[#79](https://github.com/shogotsuneto/heptapedal-infra/pull/79) — alert rules in git.** The operator asked why the
threshold stage re-evaluated what the PromQL had already decided. It did not: a
bare PromQL comparison *filters* rather than returning a truth value, so
`replicas_available < 1` breaches with the value `0`, and a `> 0` threshold on
that is false. The alert for **the site being down could never have fired**. The
fix is the `bool` modifier, in the commit named `app_unavailable would never
have fired`.

**[#95](https://github.com/shogotsuneto/heptapedal-infra/pull/95) — one schedule, because two disagreed.** "Will the
pending update appear on Monday?" It would not have. The workflow cron fired at
13:00 UTC, which is 06:00 in Vancouver, and Renovate's own schedule was
`before 6am` — a window that closes at 06:00. Two schedules set to the same
moment never overlap. The fix removes one of them rather than adjusting a
number.

**[#102](https://github.com/shogotsuneto/heptapedal-infra/pull/102) / [#103](https://github.com/shogotsuneto/heptapedal-infra/pull/103) — the required check.** "That
job only runs on Terraform paths, doesn't it?" It did, so requiring it would
have left every documentation pull request waiting forever on a status that
never arrives.

### Where a measurement overturned an assumption

**[#71](https://github.com/shogotsuneto/heptapedal-infra/pull/71) — the load balancer idle timeout was never ours to set.**
A connection surviving 70 seconds and dying by 610 was read as proof that the
600-second setting worked. It bounds the timeout to (70, 610] and proves nothing
about 600 — the number came from the configuration, not the observation. The API
settled it: a `REGIONAL_NETWORK` balancer forwards plain TCP and has no HTTP
layer to hold an HTTP idle timeout. The comment that had guessed "probably
ineffective" was right all along.

**[#86](https://github.com/shogotsuneto/heptapedal-infra/pull/86) — projected usage replaced with metered.** Including the
question that straddled a free-tier allowance: are init containers billed? The
metered rate is 971.21 container hours a day, which is 40.5 containers; the
cluster runs 40, with 15 init containers beside them. They are not.

**[#83](https://github.com/shogotsuneto/heptapedal-infra/pull/83) — the latency panel asked Loki for a series per
request.** A bare `| json` promotes every parsed field to a label, `trace_id`
included. Three panels survived only because `sum by (...)` discarded the
explosion — **they were never correct, only hidden**.

### Where the cost of something turned out to exceed its value

**[#72](https://github.com/shogotsuneto/heptapedal-infra/pull/72) — drop the load balancer check block.** A Terraform
`check` that detected a stale DNS record cost 69% of every plan's output and a
token scope, to look only at the moment someone planned. Removed in favour of
continuous external monitoring — and the replacement was built
([#85](https://github.com/shogotsuneto/heptapedal-infra/pull/85)) rather than assumed.

**[#88](https://github.com/shogotsuneto/heptapedal-infra/pull/88) — stop planning in CI.** CI planned one stack of four,
because the other three needed credentials that a pull-request workflow should
not hold. A gate over a third of the infrastructure that reads like a gate over
all of it is worse than no gate. This adopts an alternative
[ADR 0012](adr/0012-treat-the-repository-as-publishable.md) had explicitly
rejected, so it needed [an ADR of its own](adr/0015-plan-locally.md) rather than
a quiet edit.

### Where each failure hid the next

**[#89](https://github.com/shogotsuneto/heptapedal-infra/pull/89) → [#96](https://github.com/shogotsuneto/heptapedal-infra/pull/96) → [#97](https://github.com/shogotsuneto/heptapedal-infra/pull/97) →
[#98](https://github.com/shogotsuneto/heptapedal-infra/pull/98).** Getting Renovate to open one pull request took four
attempts, because each missing permission was only reachable after the previous
one was granted — and **not one of the errors named a permission**:

| Missing | Reported as |
|---|---|
| `issues` | a `FORBIDDEN` on a GraphQL field |
| `statuses` (read) | `integration-unauthorized` |
| `statuses` (write) | `repository-changed` |
| *(a repository setting, not a permission)* | `403` on the final call |

Every one of those runs **reported success**, because Renovate logs them at
`WARN` and exits non-zero only on `ERROR`.

### Where a decision was made about credentials

**[#77](https://github.com/shogotsuneto/heptapedal-infra/pull/77) — keep Supabase awake from the cluster.** Moved out of
GitHub Actions for two reasons that are both about not keeping a second copy of
a value. The opposite decision was made for Renovate
([#87](https://github.com/shogotsuneto/heptapedal-infra/pull/87)) — and the difference is written down: what a missed run
costs, and whether the thing being automated acts on this repository.

**[#78](https://github.com/shogotsuneto/heptapedal-infra/pull/78) — a grant, not only a policy.** An RLS policy without a
table grant denies everything. Postgres returned the exact statement that fixed
it, which is better than any message written in advance — so the job now points
at the response body instead of competing with it.

## Where to start if you only read one thing

[`docs/adr/`](adr/README.md). Sixteen decisions with the alternatives that lost
and why. They are append-only — superseded rather than edited — so the record
includes the two occasions a decision turned out to be wrong
([0005 → 0014](adr/0014-use-the-provider-gateway-implementation.md),
[0012 → 0015](adr/0015-plan-locally.md)).
