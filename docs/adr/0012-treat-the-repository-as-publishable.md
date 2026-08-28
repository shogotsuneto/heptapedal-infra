# 0012. Treat this repository as publishable

- **Status:** Accepted
- **Date:** 2026-08-28

## Context

The repository is private today. Making it public later is plausible — it is a
portfolio artifact, and the reasoning in `docs/adr/` is most of its value.

The problem is that "private now, public later" is not a decision you can defer
safely. Publishing is not a toggle: **git history is published too.** A state file
or a `.tfvars` committed under the assumption of privacy stays in the history
after the file is deleted, and a credential that has been pushed to a repository
that later becomes public must be treated as disclosed from the moment of
publication, not from the moment someone notices.

An audit at the point of writing found three places where privacy was doing load
that it should not have been:

- [0001](0001-repository-layout.md) justified co-locating Terraform and GitOps
  manifests partly on the repository being private.
- [0003](0003-state-backend-spaces.md) proposed committing `terraform/bootstrap/`
  state as a checked-in local file, "since it holds nothing sensitive". State
  holds every resource attribute in plaintext, including values marked sensitive.
- `excluded.d/` was ignored only through `.git/info/exclude`, which is local to
  one clone and shared with nobody.

## Decision

**Every choice in this repository must hold with the repository public.** Privacy
is treated as a fact about today, never as a control.

Concretely:

1. **Nothing sensitive is ever committed** — no state, no plan output, no
   `.tfvars`, no kubeconfig, no unsealed secret. Enforced by a committed
   `.gitignore`, not by a per-clone exclude file.
2. **State lives only in Spaces** ([0003](0003-state-backend-spaces.md)), including
   the bootstrap stack's own state.
3. **Encrypted-at-rest material may be committed** — `SealedSecret` manifests are
   designed to be safe in a public repository
   ([0007](0007-secrets-sealed-secrets.md)).
4. **CI must not print infrastructure detail into a public surface.** Plan output
   goes to the workflow run, not to a pull request comment, and workflows holding
   secrets never run against a fork's code.
5. **Secret scanning and push protection stay on**, and are switched on before
   publication rather than after.
6. **Publishing is its own reviewed step**, with a history audit — not a
   side effect of some other change.

What we accept becoming public: topology, sizing, versions, cost, and reasoning.
That is the portfolio. What must never become public: credentials, state, and any
value that grants access.

## Consequences

- One rule to check a change against, rather than a per-file judgement about what
  privacy is currently protecting.
- The bootstrap stack loses its committed state and self-hosts instead
  ([0003](0003-state-backend-spaces.md)) — a better pattern regardless of
  visibility, so the constraint improved the design.
- [0001](0001-repository-layout.md)'s co-location argument had to be re-derived
  without leaning on privacy. It survived, which is the useful outcome: the
  original conclusion was right for the wrong reason.
- Going public becomes cheap, because nothing has to be walked back.
- Publishing the topology of a live system does help an attacker enumerate it.
  Accepted deliberately: the mitigation is that nothing here is a secret in the
  first place — no credential, and no security property that depends on the
  layout being unknown. If a design ever needs the topology hidden to be safe,
  that design is the problem.
- A small ongoing tax on CI ergonomics: plan output is one click away in the run
  log instead of inline on the pull request.

## Alternatives considered

- **Decide at publication time.** Rejected — this is the failure this ADR exists to
  prevent. History cannot be un-published, and an audit performed under time
  pressure at the end is exactly when a committed state file gets missed.
- **Stay private permanently.** Rejected: the ADR set is the most legible thing
  this project produces, and it argues for itself far better in public.
- **Publish a scrubbed mirror.** Rejected: two histories to keep in step, and the
  scrubbing step is a manual gate that will eventually be skipped.
