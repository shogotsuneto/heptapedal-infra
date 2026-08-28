# 0000. Use Architecture Decision Records

- **Status:** Accepted
- **Date:** 2026-08-27

## Context

This repository builds the platform that runs [heptapedal](https://github.com/shogotsuneto/heptapedal)
and, later, other applications. Almost every choice here is a trade-off between
cost (a ~100 USD/month ceiling), operational weight (one part-time operator), and
being a legible demonstration of current infrastructure practice.

None of those trade-offs are visible in the resulting Terraform or YAML. A
`helm_release "envoy-gateway"` does not record that ingress-nginx was retired, or
that Traefik was the drop-in alternative and why it was passed over. Without that,
the next revisit re-litigates settled ground.

## Decision

Record each significant decision as a numbered Markdown file in `docs/adr/`.

- One decision per file, `NNNN-kebab-case-title.md`.
- ADRs are **append-only**. A decision that changes gets a *new* ADR whose header
  says what it supersedes; the old file stays and is marked `Superseded by NNNN`.
- Sections: Context, Decision, Consequences, Alternatives considered. The last one
  is mandatory — an ADR with no rejected alternative is usually not a decision.
- Index them in `docs/adr/README.md`.

"Significant" means: it constrains later choices, it costs money, or it is the
kind of thing someone would reasonably ask "why did you do it that way?" about.

## Consequences

- Onboarding (including my own, months later) reads the ADR set rather than
  reverse-engineering intent from HCL.
- Adds a small cost per decision. Accepted deliberately: this repository is as
  much an explanation of an architecture as it is an implementation of one.
- ADRs will go stale relative to the code. That is expected — an ADR is a record
  of what was decided *at a point in time*, not documentation of current state.

## Alternatives considered

- **A single `DECISIONS.md`.** Fewer files, but decisions get edited in place and
  the history dissolves into the diff. The immutability is the whole point.
- **Nothing; rely on git history and PR descriptions.** Commit messages explain
  *changes*, not *choices*, and GitHub PR discussion is not portable out of GitHub.
