# An external probe. Everything else here watches the cluster from inside it,
# which cannot answer the question a user asks: is the site reachable, and is
# what it serves valid?
#
# One check covers four failures that are hard to see from within:
#
#   * the apex A record pointing at nothing — the detector removed in #72, on
#     the argument that continuous outside-in monitoring covers it better
#   * a certificate that failed to renew, judged by what is *served* rather than
#     by what cert-manager believes it issued
#   * the Load Balancer or Gateway not answering the internet
#   * the application being down
#
# Synthetic Monitoring is already enabled on the stack, so there is no
# `grafana_synthetic_monitoring_installation` here — the token comes from
# Synthetics → Config instead, which is the documented alternative and avoids a
# Cloud Access Policy token entirely.
provider "grafana" {
  alias = "sm"

  # `sm_access_token` comes from GRAFANA_SM_ACCESS_TOKEN in the environment.
  sm_url = var.sm_url
}

data "grafana_synthetic_monitoring_probes" "all" {
  provider = grafana.sm
}

resource "grafana_synthetic_monitoring_check" "site" {
  provider = grafana.sm

  job    = "heptapedal"
  target = "https://heptapedal.com/login"

  # Named rather than numeric: the IDs are Grafana's, the names are ours to
  # read. A name that does not exist fails at plan time with the map in the
  # error, which is the good failure.
  probes = [
    for name in var.probe_locations :
    data.grafana_synthetic_monitoring_probes.all.probes[name]
  ]

  # Executions are billed per probe, not per check: three probes at five minutes
  # is ~26k a month against the free tier's 100k. One minute would be ~130k and
  # over.
  frequency = 300000
  timeout   = 10000

  settings {
    http {
      # /login is server-rendered and touches no database, so a failure here is
      # the site being unreachable rather than a slow query.
      valid_status_codes = [200]

      # Follow nothing. A redirect would mean the request did not land where it
      # was aimed, which is the thing being tested.
      no_follow_redirects = true
    }
  }
}
