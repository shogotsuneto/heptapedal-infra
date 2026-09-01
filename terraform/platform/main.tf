# Groups every resource so the bill reads per-project rather than per-account.
# The `resources` list is authoritative: anything not named here falls back to
# the default project, so later additions (the database in #4, the domain in #5)
# extend this list rather than living somewhere else.
resource "digitalocean_project" "heptapedal" {
  name        = var.project_name
  description = "Platform for heptapedal, and later applications on the same cluster."
  purpose     = "Web Application"
  environment = "Production"

  resources = [
    digitalocean_kubernetes_cluster.heptapedal.urn,
    digitalocean_domain.heptapedal.urn,
    digitalocean_database_cluster.heptapedal.urn,
  ]
}

# Private network shared by the cluster and, in #4, the managed database — which
# is what lets the database be reachable without exposing it publicly.
resource "digitalocean_vpc" "heptapedal" {
  name        = var.project_name
  region      = var.region
  ip_range    = var.vpc_ip_range
  description = "Private network for the heptapedal platform."
}

# Pin the minor, take the newest patch within it. auto_upgrade then applies
# later patches during the maintenance window, so this does not drift.
data "digitalocean_kubernetes_versions" "pinned" {
  version_prefix = var.kubernetes_version_prefix
}

resource "digitalocean_kubernetes_cluster" "heptapedal" {
  name     = var.cluster_name
  region   = var.region
  version  = data.digitalocean_kubernetes_versions.pinned.latest_version
  vpc_uuid = digitalocean_vpc.heptapedal.id

  # DO NOT REMOVE. On Kubernetes 1.36 and later the provider defaults this to
  # true, which is a 40 USD/month high-availability control plane — 40% of the
  # budget, for an availability target ADR 0004 explicitly declines to buy. It
  # is also irreversible: DigitalOcean cannot disable HA once a cluster has it.
  ha = false

  # Patch upgrades, applied in the window below. Surge upgrades add a temporary
  # node during the roll so pods are not evicted onto a cluster that has no room
  # for them — with two 4 GB nodes there is not much slack to absorb a drain.
  auto_upgrade  = true
  surge_upgrade = true

  maintenance_policy {
    day        = var.maintenance_window.day
    start_time = var.maintenance_window.start_time
  }

  # Left false deliberately. True would delete Load Balancers and volumes the
  # Kubernetes API created when the cluster is destroyed; false leaves them
  # behind, which is recoverable but bills silently. The backstop is the
  # DigitalOcean billing alert in #7 — check for an orphaned Load Balancer after
  # any cluster teardown.
  destroy_all_associated_resources = false

  node_pool {
    name       = "default"
    size       = var.node_size
    node_count = var.node_count
    tags       = ["heptapedal", "worker"]
  }

  tags = ["heptapedal", "terraform"]
}
