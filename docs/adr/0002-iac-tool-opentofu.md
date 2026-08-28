# 0002. Use OpenTofu as the IaC CLI

- **Status:** Accepted
- **Date:** 2026-08-27

## Context

The infrastructure is declarative HCL against the `digitalocean`, `helm`, and
`kubernetes` providers. The only real question is which CLI executes it.

Since HashiCorp relicensed Terraform under the BSL (and was subsequently acquired
by IBM), OpenTofu has existed as the MPL-2.0, Linux Foundation-governed fork. By
2026 it has genuinely diverged rather than merely tracking upstream — native state
encryption and provider-defined functions landed there first — while remaining
HCL- and provider-compatible.

Counterweight: name recognition. "Terraform" is what job postings and recruiters
search for; OpenTofu is still a minority (~12% of IaC practitioners, with roughly
a quarter of teams evaluating it). This repository is partly a portfolio, so that
matters.

## Decision

Use **OpenTofu** as the CLI. Keep the source as ordinary `.tf` HCL with no
OpenTofu-only syntax, so `terraform plan` works against the same tree unchanged.
State the compatibility explicitly in the repository README.

Pin the version in CI and in a `.tool-versions` file.

## Consequences

- No licensing question to answer, and OSI-licensed tooling throughout.
- The recognition gap is closed by wording, not by tool choice: the source *is*
  Terraform HCL and says so. Both keywords are legitimately present.
- Switching costs a CI line change in either direction, as long as the
  no-OpenTofu-only-syntax rule holds. That rule is the actual commitment here.
- Forgoes HCP Terraform's managed workflow. Not needed — see [0003](0003-state-backend-spaces.md).

## Alternatives considered

- **Terraform CLI (BSL).** Maximum recognition, no functional loss at this scale.
  A defensible choice; passed over because for a greenfield project with no
  existing Terraform investment there is no cost to taking the open-source fork,
  and being able to explain *why* is worth more than the keyword.
- **Pulumi / CDKTF.** Real advantages for teams that would rather write a
  programming language. Rejected: it trades away the thing HCL is good at here —
  a diff a reader can audit — and is a smaller signal in this market.
