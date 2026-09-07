locals {
  prometheus_datasource = coalesce(
    var.prometheus_datasource_name,
    "grafanacloud-${var.grafana_stack_slug}-prom",
  )
  loki_datasource = coalesce(
    var.loki_datasource_name,
    "grafanacloud-${var.grafana_stack_slug}-logs",
  )
}

# Looked up rather than hardcoded: the UID is generated per stack, so a literal
# would be a value nobody could re-derive after a rebuild.
data "grafana_data_source" "prometheus" {
  name = local.prometheus_datasource
}

resource "grafana_folder" "heptapedal" {
  title = "heptapedal"
}

# Email, because it is the channel actually read. ADR 0010 chose Grafana Cloud
# partly for having alerting at all on the free tier; routing somewhere nobody
# checks would waste that.
resource "grafana_contact_point" "email" {
  name = "heptapedal-email"

  email {
    addresses = [var.alert_email]
    # Grafana's default template names the alert but not why it fired.
    message = "{{ range .Alerts }}{{ .Annotations.summary }}\n{{ .Annotations.description }}\n{{ end }}"
  }
}

# Everything from this folder goes to that address. One route, because there is
# one person: a policy tree would be structure without a decision behind it.
resource "grafana_notification_policy" "root" {
  group_by      = ["alertname"]
  contact_point = grafana_contact_point.email.name

  # Long enough that a flapping alert cannot become a mailing list.
  group_wait      = "1m"
  group_interval  = "10m"
  repeat_interval = "12h"
}
