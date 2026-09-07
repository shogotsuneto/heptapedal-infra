terraform {
  required_version = ">= 1.10.0"

  required_providers {
    grafana = {
      source  = "grafana/grafana"
      version = "~> 4.45"
    }
  }
}

# `auth` comes from GRAFANA_AUTH in the environment, never from configuration —
# it is a service account token with write access to alerting. The URL is
# derived rather than given, because a Grafana Cloud stack is always
# https://<slug>.grafana.net.
provider "grafana" {
  url = "https://${var.grafana_stack_slug}.grafana.net"
}
