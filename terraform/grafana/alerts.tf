# Four alerts, and the count is the point. ADR 0010's note that "an alert nobody
# acts on trains you to ignore the channel" is easier to honour by starting
# below what seems sufficient than by pruning later.
#
# Every condition uses PromQL's `bool` modifier, so each query returns 1 when it
# holds and 0 when it does not, and the expression stage is a uniform `> 0`
# meaning "the condition was true". That keeps the generated rules identical in
# shape, with the difference between them in one readable place.
#
# `bool` is load-bearing, not decoration. A bare comparison in PromQL filters
# rather than returning a truth value: matching series keep their original
# value and the rest are dropped. `replicas_available < 1` therefore breaches
# with the value **0**, and a `> 0` threshold on that is false — the alert for
# the site being down would never have fired. With `bool` the breach is 1
# regardless of the underlying number, which is what the uniform threshold
# needs.
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
        time() - max(kube_cronjob_status_last_successful_time{namespace="hepta", cronjob="supabase-keepalive"}) > bool 172800
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
        kube_deployment_status_replicas_available{namespace="hepta", deployment="app"} < bool 1
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
      # thing that acts on it. Not aggregated, so the firing instance names the
      # node instead of saying only that one of them is unhappy.
      expr = <<-EOT
        kube_node_status_condition{condition="MemoryPressure", status="true"} > bool 0
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
        increase(kube_pod_container_status_restarts_total{namespace="hepta"}[30m]) > bool 0
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
