# 0012. Treat this repository as publishable

- **Status:** Accepted
- **Date:** 2026-08-29

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
4. **Plan *artifacts* never reach a public surface.** The binary `-out` plan file
   and `show -json` contain every value **unredacted**, `sensitive` marking
   included — passwords, connection URIs, kubeconfigs. They are never uploaded as
   a workflow artifact, never posted, never committed. This is the actual control;
   rendered plan text is a different and much smaller thing.
5. **Workflows holding secrets never run against a fork's code.** A public
   repository accepts pull requests from anyone.
6. **Secret scanning and push protection stay on**, and are switched on before
   publication rather than after.
7. **Publishing is its own reviewed step**, with a history audit — not a
   side effect of some other change.

What we accept becoming public: topology, sizing, versions, cost, and reasoning.
That is the portfolio. What must never become public: credentials, state, and any
value that grants access.

### Rendered plan text: accepted, with best-effort masking

Rendered `plan` output exposes the map — database hostnames, VPC CIDRs, cluster
UUIDs, firewall rules — because provider-marked sensitivity covers credentials
and not much else, and because it renders from state on every plan after the
first. **This is accepted.** It follows directly from the rule above: nothing here
is a secret, the database is firewalled to the cluster rather than hidden, and a
design that needed its hostnames unknown would be the thing to fix. So plan text
stays inline on the pull request, where it is actually read.

On top of that, and **explicitly not as a control**, a best-effort masking filter
sits between rendering the plan and posting it: pattern-match the obvious
identifiers — `*.ondigitalocean.com` hostnames, IP literals, UUIDs — and redact
them. It costs a `sed` step, it removes the incidental copy-paste of a hostname
into an indexed public page, and it is worth having.

Two constraints on it, both of which follow from it being hygiene rather than a
boundary:

- **It must never be described, in code or in review, as making the output safe.**
  A filter that mostly works is exactly the kind of thing that quietly becomes
  load-bearing. Any change that would be unsafe if the filter matched nothing is
  already wrong.
- **Mask conservatively.** The plan is read to catch "why is this changing the
  firewall rule?" — over-redacting the diff defeats the review it exists for.
  Redact identifiers, not structure.

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
- No CI ergonomic tax: plans stay inline on the pull request, which is where they
  get read.
- The masking filter will drift — new resource types will introduce identifiers it
  does not match. That is tolerable precisely because nothing depends on it. It
  would not be tolerable if it were a control, which is the reason for stating so
  plainly that it is not.

## Alternatives considered

- **Decide at publication time.** Rejected — this is the failure this ADR exists to
  prevent. History cannot be un-published, and an audit performed under time
  pressure at the end is exactly when a committed state file gets missed.
- **Stay private permanently.** Rejected: the ADR set is the most legible thing
  this project produces, and it argues for itself far better in public.
- **Publish a scrubbed mirror.** Rejected: two histories to keep in step, and the
  scrubbing step is a manual gate that will eventually be skipped.
- **Route plan output to the workflow run instead of a pull request comment.** The
  first version of this ADR said to do exactly that. It is not a mitigation:
  **on a public repository, Actions run logs are public too.** It moves the text
  without changing who can read it, and costs the inline review. Recorded because
  it is a plausible-sounding move that does nothing.
- **Withhold plan output from public CI entirely** — plan locally, or on a private
  runner. Genuinely prevents the map from being published. Rejected: it removes
  plan-on-PR, which is the main thing making infrastructure changes reviewable,
  in exchange for hiding information that is not sensitive.
