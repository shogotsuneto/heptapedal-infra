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

**[#102](https://github.com/shogotsuneto/heptapedal-infra/pull/102) / [#103](https://github.com/shogotsuneto/heptapedal-infra/pull/103) — the required check.** "That job only runs on
Terraform paths, doesn't it?" It did, so requiring it would have left every
documentation pull request waiting forever on a status that never arrives.

### Where a decision was made about credentials

**[#77](https://github.com/shogotsuneto/heptapedal-infra/pull/77) — keep Supabase awake from the cluster.** Moved out of GitHub
Actions for two reasons that are both about not keeping a second copy of a
value. The opposite decision was made for Renovate ([#87](https://github.com/shogotsuneto/heptapedal-infra/pull/87)), and the
difference is written down: what a missed run costs, and whether the thing being
automated acts on this repository.

**And the one that shaped the rest, back in [#27](https://github.com/shogotsuneto/heptapedal-infra/pull/27).** The first draft of
[ADR 0007](adr/0007-secrets-sealed-secrets.md) took the conventional advice and
backed up the Sealed Secrets controller's private keys. It was reversed during
review — the commit is `drop the Sealed Secrets key backup for an invariant
instead` — because a backup protects ciphertext by creating one unmanaged
plaintext copy of the keys that open all of it, this repository's published
ciphertext included.

What replaced it is a rule rather than a duty: **the ciphertext is never a
value's only copy.** Every sealed value is reissuable from the service that owns
it, and anything that is not gets a home before it is sealed — checkable in
review, where "remember to take a backup" is not.

It still carries weight three layers down. Losing the cluster makes every sealed
value in git undecryptable at once, and only that rule is why
[`rebuild.md`](rebuild.md) describes resealing as a step rather than a disaster.

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
