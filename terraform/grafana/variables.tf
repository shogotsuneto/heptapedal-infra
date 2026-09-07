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

variable "alert_email" {
  description = <<-EOT
    Where alerts go. Deliberately without a default: the repository is written
    to be publishable (ADR 0012), and an address in a committed default is an
    address on an indexed page. Set TF_VAR_alert_email.
  EOT
  type        = string
}
