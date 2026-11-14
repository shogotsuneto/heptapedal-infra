# SLO reviews

The record of [ADR 0019](../adr/0019-slo-and-error-budget.md)'s error budget:
one file per week in [`reviews/`](reviews/), named by ISO week
(`2026-W47.md`).

## How a review happens

Every Monday at 00:00 UTC, [`slo-review`](../../.github/workflows/slo-review.yml)
opens a pull request with the previous week's file. The numbers in it are
generated from the same probe counters the SLO is defined on. The PR body also
lists the pull requests merged that week.

To review:

1. Approve the `check` workflow on the pull request. It was opened with
   `GITHUB_TOKEN`, so the check waits for approval, as Renovate's do.
2. Read the numbers and the policy line.
3. Fill in the two **Review** lines on the PR branch: what spent the budget,
   and what changes because of it. "Nothing" is a valid answer to both.
4. Merge.

An unmerged review stays open, so a skipped week is visible. Review weeks in
order; a later week does not replace an earlier one.

To regenerate or backfill by hand (Grafana keeps 14 days, so at most last week
and the one before):

```bash
GRAFANA_STACK_SLUG=<slug> GRAFANA_SLO_READ_TOKEN=<token> \
  python3 -I .github/scripts/slo_report.py docs/slo/reviews
```

## Setup

Once, in this order:

1. **A read-only Grafana token.** Grafana Cloud → Administration → Users and
   access → Service accounts → new account `slo-review`, basic role
   **Viewer**, then add a token. Viewer can query data sources and change
   nothing. It is a separate account from the Terraform one, so the report
   never holds write access to alerting.
2. **An environment for it.** Settings → Environments → new environment
   `slo-review`, restricted to the `main` branch. Then:

   ```bash
   gh secret set GRAFANA_SLO_READ_TOKEN --env slo-review
   gh variable set GRAFANA_STACK_SLUG --env slo-review --body <slug>
   ```

3. Run the workflow once by hand (Actions → slo-review → Run workflow) to
   check the setup, or wait for Monday.

Opening pull requests also needs **Allow GitHub Actions to create and approve
pull requests**, which is already on for Renovate.
