output "project_id" {
  description = "DigitalOcean project ID. Later stacks add their resources to it."
  value       = digitalocean_project.heptapedal.id
}

output "vpc_id" {
  description = "VPC UUID. The managed database in #4 joins this network."
  value       = digitalocean_vpc.heptapedal.id
}

output "domain_name" {
  description = "The DNS zone DigitalOcean serves once delegation has propagated."
  value       = digitalocean_domain.heptapedal.name
}

# Fixed for every DigitalOcean zone, so this is a convenience rather than a
# lookup: it is what goes into Namecheap's custom-nameserver fields.
output "nameservers" {
  description = "Set these as the domain's nameservers at the registrar."
  value       = ["ns1.digitalocean.com", "ns2.digitalocean.com", "ns3.digitalocean.com"]
}

output "cluster_id" {
  description = "DOKS cluster UUID — what a database firewall rule trusts by resource type."
  value       = digitalocean_kubernetes_cluster.heptapedal.id
}

# How later stacks should reach the cluster. NOT the kubeconfig: DigitalOcean
# issues its credentials with a 7-day expiry, so a kubeconfig captured in this
# stack's state goes stale and takes the kubernetes/helm providers with it.
#
# The Argo CD stack looks the cluster up by name with a
# `digitalocean_kubernetes_cluster` data source instead, which mints fresh
# credentials on every read.
output "cluster_name" {
  description = "Look the cluster up by this name for fresh, unexpired credentials."
  value       = digitalocean_kubernetes_cluster.heptapedal.name
}

output "cluster_endpoint" {
  description = "Kubernetes API server URL. Stable, unlike the credentials."
  value       = digitalocean_kubernetes_cluster.heptapedal.endpoint
}

output "cluster_version" {
  description = "The patch version actually selected within the pinned minor."
  value       = digitalocean_kubernetes_cluster.heptapedal.version
}

# A snapshot, not a live credential: `tofu output` reads state and never calls
# the API, so this is whatever the last apply captured and it stops working
# seven days after that. `doctl kubernetes cluster kubeconfig save heptapedal`
# is the way to get working credentials — it writes an exec-plugin kubeconfig
# that renews itself. Kept only as the fallback when doctl is unavailable; see
# README.md.
output "kubeconfig" {
  description = "Kubeconfig as of the last apply. Stale 7 days later — prefer `doctl kubernetes cluster kubeconfig save`."
  value       = digitalocean_kubernetes_cluster.heptapedal.kube_config[0].raw_config
  sensitive   = true
}

# --- database ---------------------------------------------------------------

output "database_host" {
  description = "Private hostname. Reachable only from inside the VPC."
  value       = digitalocean_database_cluster.heptapedal.private_host
}

output "database_port" {
  value = digitalocean_database_cluster.heptapedal.port
}

# What becomes DATABASE_URL in the application's sealed Secret (#17). Built by
# hand rather than taken from the cluster's `private_uri`, because that one
# carries doadmin and the default database.
output "database_url" {
  description = "DATABASE_URL for the application, as app_user over the private network."
  value = format(
    "postgresql://%s:%s@%s:%d/%s?sslmode=require",
    digitalocean_database_user.app.name,
    digitalocean_database_user.app.password,
    digitalocean_database_cluster.heptapedal.private_host,
    digitalocean_database_cluster.heptapedal.port,
    digitalocean_database_db.hepta.name,
  )
  sensitive = true
}

# doadmin, for the one-time bootstrap in README.md — creating extensions needs
# more than the application's role has. Not for the application to use.
output "database_admin_url" {
  description = "doadmin connection URL, for the one-time extension bootstrap only."
  value = format(
    "postgresql://%s:%s@%s:%d/%s?sslmode=require",
    digitalocean_database_cluster.heptapedal.user,
    digitalocean_database_cluster.heptapedal.password,
    digitalocean_database_cluster.heptapedal.private_host,
    digitalocean_database_cluster.heptapedal.port,
    digitalocean_database_db.hepta.name,
  )
  sensitive = true
}
