# Every JSON file in dashboards/ becomes a dashboard. Adding one is dropping a
# file in that directory — no Terraform to write, which is the point: a
# dashboard is something you build by looking at it, and the loop of edit,
# apply, look is a bad way to do that. Build it in the UI, export the JSON,
# commit it.
#
# Two placeholders are substituted before upload, so a committed dashboard is
# not pinned to one stack's generated data source UIDs:
#
#   __PROMETHEUS_UID__   __LOKI_UID__
#
# Substitution is literal replacement rather than templating, so a file exported
# straight from the UI works untouched — Grafana's own `${...}` syntax passes
# through, where a template function would try to interpret it and fail.
data "grafana_data_source" "loki" {
  name = local.loki_datasource
}

resource "grafana_dashboard" "committed" {
  for_each = fileset("${path.module}/dashboards", "*.json")

  folder = grafana_folder.heptapedal.uid

  # Named by the file, so a rename is visible in the plan rather than silent.
  message = "terraform: ${each.value}"

  # The dashboard's identity is the `uid` inside its JSON. Overwrite lets a
  # dashboard first drawn in the UI be adopted by committing its export, rather
  # than colliding with itself.
  overwrite = true

  config_json = replace(
    replace(
      file("${path.module}/dashboards/${each.value}"),
      "__PROMETHEUS_UID__", data.grafana_data_source.prometheus.uid,
    ),
    "__LOKI_UID__", data.grafana_data_source.loki.uid,
  )
}
