output "project_id" {
  description = "DigitalOcean project ID. Later stacks add their resources to it."
  value       = digitalocean_project.heptapedal.id
}

output "vpc_id" {
  description = "VPC UUID. The managed database in #4 joins this network."
  value       = digitalocean_vpc.heptapedal.id
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

# For `kubectl` by hand. Expires — see the note on cluster_name.
output "kubeconfig" {
  description = "Raw kubeconfig. Credentials expire after 7 days; re-run `tofu output` to refresh."
  value       = digitalocean_kubernetes_cluster.heptapedal.kube_config[0].raw_config
  sensitive   = true
}
