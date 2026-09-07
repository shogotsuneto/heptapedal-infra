variable "grafana_stack_slug" {
  description = <<-EOT
    The Grafana Cloud stack's slug — the first label of its URL. Also names the
    Prometheus data source by default, which alert queries are evaluated
    against.
  EOT
  type        = string
}

variable "prometheus_datasource_name" {
  description = <<-EOT
    Overrides the derived data source name. Grafana Cloud names it
    `grafanacloud-<slug>-prom`, which is right whenever the stack and
    organization slugs agree; set this when they do not.
  EOT
  type        = string
  default     = null
}

variable "loki_datasource_name" {
  description = "As above, for logs. Grafana Cloud names it `grafanacloud-<slug>-logs`."
  type        = string
  default     = null
}

variable "sm_url" {
  description = <<-EOT
    The Synthetic Monitoring API for the stack's region. Read off the installed
    plugin's settings rather than guessed; it must match the region the stack
    lives in.
  EOT
  type        = string
  default     = "https://synthetic-monitoring-api-ca-east-0.grafana.net"
}

variable "probe_locations" {
  description = <<-EOT
    Public probe names. Three is the recommended number — executions are billed
    per probe, so each one multiplies the cost of the check.
  EOT
  type        = list(string)
  default     = ["NorthCalifornia", "NewYork", "Frankfurt"]
}

variable "alert_email" {
  description = <<-EOT
    Where alerts go. Deliberately without a default: the repository is written
    to be publishable (ADR 0012), and an address in a committed default is an
    address on an indexed page. Set TF_VAR_alert_email.
  EOT
  type        = string
}
