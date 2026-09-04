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

# Pin the minor and take the newest patch within it — but only when the cluster
# is built. After that DigitalOcean owns the version; see `lifecycle` below.
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

  # Patch upgrades, applied in the window below. surge_upgrade asks for
  # replacements to be stood up before draining, which wants a Droplet limit of
  # n + min(10, num_nodes) — 4 at two nodes, against an account limit of 3. So
  # it currently degrades to a partial surge and finishes node-by-node. That is
  # a documented fallback, not a failure; see README, "The Droplet limit".
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

  # DigitalOcean owns the version once the cluster exists, because auto_upgrade
  # is on. Without this, the data source above resolves to a new patch the
  # moment one is published while the cluster stays on the old one until its
  # maintenance window — so every plan in between carries a version diff, and
  # any merge that reaches `apply` converts that diff into an unscheduled
  # upgrade that recycles every node. The workflow watches `terraform/**`, so a
  # README edit is enough to set it off.
  #
  # The cost is that a *minor* bump is ignored too: changing
  # kubernetes_version_prefix means removing this line, applying, and putting it
  # back. That is the right amount of friction for a once-a-year change, and the
  # wrong amount for a patch nobody chose.
  lifecycle {
    ignore_changes = [version]
  }
}
