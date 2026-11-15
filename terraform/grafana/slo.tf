# One SLO, and as with the alerts the count is the point
# ([ADR 0019](../../docs/adr/0019-slo-and-error-budget.md)). This one is for
# learning how a budget works in operation before adding others.
#
# The SLI is the external probe in synthetic.tf: the share of probe executions
# that fetched https://heptapedal.com/login successfully. It is the only signal
# here that measures what a visitor sees, and it already exists, so it needs no
# new collection. The cluster has no request-level metrics yet.
#
# Counters, not `probe_success`. `probe_all_success_count` counts executions and
# `probe_all_success_sum` counts the successful ones, per probe location, which
# is the success/total pair a ratio SLI needs. `probe_success` is a gauge of the
# latest result and cannot be summed into a ratio.
#
# Not grouped by probe. A location that fails takes a third of executions with
# it and spends budget, which is accurate: a third of the places checking could
# not reach the site. `site_unreachable` already ignores one flaky location;
# the budget is where it shows up instead.
resource "grafana_slo" "site_availability" {
  name        = "heptapedal.com availability"
  description = "Share of external probe executions that fetched /login successfully."
  folder_uid  = grafana_folder.heptapedal.uid

  query {
    type = "ratio"
    ratio {
      success_metric = "probe_all_success_sum{job=\"heptapedal\"}"
      total_metric   = "probe_all_success_count{job=\"heptapedal\"}"
    }
  }

  # 99.5% over 7 days: 0.5% of 7 days is about 50 minutes of budget. At one
  # check every five minutes, that is roughly ten rounds in which every
  # location fails.
  #
  # Seven days, not the usual 28 or 30, because the free tier keeps metrics for
  # 14 days. A longer window would include days that no longer have data, and
  # the budget would be calculated over 14 days without saying so. Seven days
  # stays within retention with room to spare, and it matches the weekly review
  # in the ADR.
  objectives {
    value  = 0.995
    window = "7d"
  }

  destination_datasource {
    uid = data.grafana_data_source.prometheus.uid
  }

  # Burn-rate alerts, which Grafana SLO generates and routes through the
  # notification policy in main.tf, so they go to the same email.
  alerting {
    fastburn {
      annotation {
        key   = "summary"
        value = "heptapedal.com is spending its error budget fast"
      }
      annotation {
        key   = "description"
        value = "At this rate the week's ~50 minutes of budget runs out within hours. Visitors are failing to load the site now. See docs/adr/0019-slo-and-error-budget.md."
      }
    }

    slowburn {
      annotation {
        key   = "summary"
        value = "heptapedal.com is spending its error budget slowly but steadily"
      }
      annotation {
        key   = "description"
        value = "Not an outage: a small, steady rate of failures that would use up the budget within days. Look for it on the SLO dashboard, then apply the budget policy in docs/adr/0019-slo-and-error-budget.md."
      }
    }

    # Executions come in rounds of three, one per location, every five minutes.
    # One failed round in an hour is 3 of ~36 executions, which is already over
    # the fast-burn threshold, so a single five-minute blip would send an email.
    # Six means at least two rounds' worth, the same ~10 minutes
    # `site_unreachable` waits for.
    advanced_options {
      min_failures = 6
    }
  }
}
