# 0015. Plan locally; CI validates but does not plan

- **Status:** Accepted; supersedes the plan-in-CI half of
  [0012](0012-treat-the-repository-as-publishable.md)
- **Date:** 2026-09-08

> The masking machinery in 0012 exists to make plan output safe to post
> publicly. It is sound, and it is solving a problem this repository can decline
> to have.

## Context

[ADR 0012](0012-treat-the-repository-as-publishable.md) accepted rendered plan
text as public, with best-effort masking, and rejected "withhold plan output
from public CI entirely — plan locally" as a rejected alternative. The reasoning
was that plans stay inline on the pull request, which is where they are read.

What has happened since is that CI never planned more than a third of the
infrastructure, and the fraction has been falling:

| Stack | Planned on a pull request |
|---|---|
| `platform` | yes |
| `argocd` | no — planning it needs `kubernetes:access_cluster`, an administrator kubeconfig, which the read-only `plan` environment exists to avoid holding |
| `grafana` | no — it would need a second, read-only Grafana token |
| `bootstrap` | no — never in CI at all |

Each exclusion was reasoned and each is still right. Together they make "the
plan comment is the review gate" a claim that was true of one stack.

Meanwhile the local position improved. Every credential these stacks need is
now in `.envrc.example`, and planning any of them locally is one command. The
thing CI was providing is available to the reviewer directly, and completely,
where CI provided it partially.

## Decision

**CI does not plan. The reviewer plans locally, and the practice is documented
rather than implied.**

`check` keeps running on every pull request: `fmt`, and
`init -backend=false && validate` over every stack including `bootstrap`. It
needs no credentials, so it remains safe on a pull request from a fork.

`apply` is unchanged.

## Consequences

- **The `plan` environment and its two credentials are no longer needed** — a
  read-only DigitalOcean token and a read-only Spaces key, both of which existed
  only to be held by a workflow anyone could trigger. Removing a credential is
  worth more than most things it could have been protecting.
- The masking script goes with it, and with it the standing question of whether
  best-effort masking is being mistaken for a boundary. 0012's answer was
  careful, but not having the question is better than answering it.
- **The reviewer must actually plan.** This is the real cost: a habit is weaker
  than a workflow, and nothing now fails if it is skipped. It is documented in
  the root README as a step rather than left as an expectation.
- A contributor without credentials cannot see what a change would do. For a
  repository with one operator this is theoretical; if it stops being so, the
  answer is a read-only environment again, and this ADR is the thing to revisit.
- Renovate's pull requests are affected less than it appears. `check` still runs
  on them and still catches a provider constraint that does not resolve — which
  is most of what a bump can get wrong before it is applied.

## Alternatives considered

- **Keep planning `platform` only, as now.** Rejected for the reason this ADR
  exists: partial coverage presented as a gate is worse than no gate, because it
  invites the assumption that a clean pull request has been planned.
- **Extend planning to every stack.** This is the honest version of the status
  quo, and it costs two more credentials in CI — a Grafana read token and,
  worse, an administrator kubeconfig for `argocd`. 0012's clause 5 exists to
  prevent exactly that, so the consistent direction was the other one.
- **Post plans to the workflow run rather than a comment.** Already rejected in
  0012, and it does not address coverage at all.
