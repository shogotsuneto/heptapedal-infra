# Application data. Auth stays on Supabase — see ADR 0008 for why they are split.
#
# Single node, 1 GiB, 15 USD/month. Not highly available: a single-node cluster
# has automatic failover but no standby, which is the same availability bargain
# the cluster makes in ADR 0004.
resource "digitalocean_database_cluster" "heptapedal" {
  name       = var.project_name
  engine     = "pg"
  version    = var.postgres_version
  size       = var.database_size
  region     = var.region
  node_count = 1

  # Puts the cluster on the VPC, which is what gives it a private_host the
  # workload can reach without the traffic leaving DigitalOcean's network.
  private_network_uuid = digitalocean_vpc.heptapedal.id

  # An hour after the cluster's window, so a bad night does not move both at
  # once.
  maintenance_window {
    day  = var.maintenance_window.day
    hour = "11:00"
  }

  tags = ["heptapedal", "terraform"]

  # Project membership is set through digitalocean_project.resources rather
  # than the project_id argument here: that list is authoritative, so two
  # sources of truth would fight on every apply.
}

resource "digitalocean_database_db" "hepta" {
  cluster_id = digitalocean_database_cluster.heptapedal.id
  name       = var.database_name
}

# The application's own role. DigitalOcean generates the password; it never
# appears in the configuration, only in state and in the sealed Secret built
# from these outputs.
resource "digitalocean_database_user" "app" {
  cluster_id = digitalocean_database_cluster.heptapedal.id
  name       = var.database_user
}

# Trusts the Kubernetes cluster as a resource, not as a set of addresses. Node
# IPs are ephemeral — an allowlist of them would rot on the first node
# replacement, and silently, since the symptom is the application failing to
# connect rather than anything shouting.
#
# This list is exhaustive: no operator IP, no CI runner. Anything that needs a
# psql prompt gets one from inside the cluster, which is what the README's
# bootstrap step does.
resource "digitalocean_database_firewall" "heptapedal" {
  cluster_id = digitalocean_database_cluster.heptapedal.id

  rule {
    type  = "k8s"
    value = digitalocean_kubernetes_cluster.heptapedal.id
  }
}
