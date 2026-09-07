# Four alerts, and the count is the point. ADR 0010's note that "an alert nobody
# acts on trains you to ignore the channel" is easier to honour by starting
# below what seems sufficient than by pruning later.
#
# Each condition is written in PromQL so the query returns nothing until it is
# breaching; the expression stage is then a uniform `> 0`. That keeps the
# generated rules identical in shape and the difference between them in one
# readable place.
locals {
  alerts = {
    supabase_keepalive_stale = {
      summary     = "Supabase has not been pinged for two days"
      description = <<-EOT
        The keepalive CronJob in `hepta` has not completed successfully since
        the timestamp below. Free Supabase projects pause after seven days
        without database activity, and authentication lives there — so this
        becomes a login outage with a few days' warning. See
        docs/supabase-keepalive.md.
      EOT
      # Deliberately not `kube_job_failed`. This fires for a failing job, a
      # suspended CronJob, a deleted one, and a CronJob that silently stopped
      # scheduling — the failure modes are different and the consequence is
      # identical.
      expr = <<-EOT
        time() - max(kube_cronjob_status_last_successful_time{namespace="hepta", cronjob="supabase-keepalive"}) > 172800
      EOT
      for  = "15m"
      # Absent metric means the CronJob is gone, which is the outage rather than
      # an absence of evidence about it.
      no_data = "Alerting"
    }

    app_unavailable = {
      summary     = "heptapedal has no available replica"
      description = "The `app` Deployment in `hepta` reports zero available replicas: the site is down."
      expr        = <<-EOT
        kube_deployment_status_replicas_available{namespace="hepta", deployment="app"} < 1
      EOT
      for         = "5m"
      no_data     = "Alerting"
    }

    node_memory_pressure = {
      summary     = "A node is under memory pressure"
      description = <<-EOT
        The kubelet has set MemoryPressure, so it is about to start evicting
        pods. Two 4 GB nodes leave roughly 650 MiB of request headroom (#67).
      EOT
      # The kubelet's own judgement rather than a threshold of ours — it is the
      # thing that acts on it.
      expr = <<-EOT
        max(kube_node_status_condition{condition="MemoryPressure", status="true"}) > 0
      EOT
      for  = "5m"
      # A blip in the metrics pipeline should not read as pressure; the two
      # alerts above already fire if it stops entirely.
      no_data = "OK"
    }

    app_restarting = {
      summary     = "A container in hepta is restarting"
      description = <<-EOT
        Containers do not restart during a deploy — a new pod starts its counter
        at zero — so this is a crash. The likeliest cause is an OOMKill: the
        app's memory limit was set by guess rather than measurement (#18).
      EOT
      expr        = <<-EOT
        increase(kube_pod_container_status_restarts_total{namespace="hepta"}[30m]) > 0
      EOT
      for         = "5m"
      no_data     = "OK"
    }
  }
}

resource "grafana_rule_group" "heptapedal" {
  name             = "heptapedal"
  folder_uid       = grafana_folder.heptapedal.uid
  interval_seconds = 300

  dynamic "rule" {
    for_each = local.alerts
    content {
      name           = rule.key
      for            = rule.value.for
      condition      = "B"
      no_data_state  = rule.value.no_data
      exec_err_state = "Alerting"

      annotations = {
        summary     = rule.value.summary
        description = trimspace(rule.value.description)
      }

      data {
        ref_id         = "A"
        datasource_uid = data.grafana_data_source.prometheus.uid
        relative_time_range {
          from = 600
          to   = 0
        }
        model = jsonencode({
          refId         = "A"
          editorMode    = "code"
          expr          = trimspace(rule.value.expr)
          instant       = true
          range         = false
          intervalMs    = 1000
          maxDataPoints = 43200
        })
      }

      data {
        ref_id         = "B"
        datasource_uid = "__expr__"
        relative_time_range {
          from = 0
          to   = 0
        }
        model = jsonencode({
          refId      = "B"
          type       = "threshold"
          expression = "A"
          conditions = [{
            evaluator = { type = "gt", params = [0] }
            operator  = { type = "and" }
            query     = { params = ["A"] }
            reducer   = { type = "last", params = [] }
          }]
        })
      }
    }
  }
}
