variable "region" {
  description = "DigitalOcean region. One region for everything — see ADR 0013."
  type        = string
  default     = "sfo3"
}

variable "project_name" {
  description = "DigitalOcean project grouping every resource, so the bill is legible per-project."
  type        = string
  default     = "heptapedal"
}

variable "vpc_ip_range" {
  description = <<-EOT
    Private network for the VPC. Must not collide with DOKS's own overlay
    ranges, which default to 10.244.0.0/16 for pods and 10.245.0.0/16 for
    services.
  EOT
  type        = string
  default     = "10.20.0.0/16"
}

variable "domain" {
  description = "Registered at Namecheap; DNS served by DigitalOcean. See ADR 0009."
  type        = string
  default     = "heptapedal.com"
}

variable "cluster_name" {
  description = "DOKS cluster name. Also how later stacks look the cluster up for fresh credentials — see outputs.tf."
  type        = string
  default     = "heptapedal"
}

variable "kubernetes_version_prefix" {
  description = <<-EOT
    Minor version to pin; the latest matching patch is selected, and
    auto_upgrade applies newer patches in the maintenance window. Bumping the
    minor is a deliberate one-line change.

    DigitalOcean supports the three most recent minors. As of 2026-08, that is
    1.34 (end of support 2026-10-27), 1.35 (2027-02-28) and 1.36 (2027-06-28).
    List them with `doctl kubernetes options versions`.
  EOT
  type        = string
  default     = "1.36."
}

variable "postgres_version" {
  description = <<-EOT
    Major version of the managed PostgreSQL cluster.

    Note the divergence from local development, which runs
    `pgvector/pgvector:pg16` in docker-compose and Kind. Worth closing by
    bumping the local image rather than holding production back, but it is an
    application-repo change and is not done yet.
  EOT
  type        = string
  default     = "17"
}

variable "database_size" {
  description = "Single node, 1 GiB — 15 USD/month. See ADR 0008."
  type        = string
  default     = "db-s-1vcpu-1gb"
}

variable "database_name" {
  description = "Application database, matching what local development uses."
  type        = string
  default     = "hepta"
}

variable "database_user" {
  description = "Role the application connects as. Not the cluster's doadmin."
  type        = string
  default     = "app_user"
}

variable "agent_auth_database_name" {
  description = <<-EOT
    agent-auth's database, on the same cluster as the application's but
    separate from it: the two services share no database and no secret.
  EOT
  type        = string
  default     = "agent_auth"
}

variable "agent_auth_database_user" {
  description = "Role agent-auth connects as. Can reach its own database and not the application's."
  type        = string
  default     = "agent_auth_user"
}

variable "node_size" {
  description = "Worker Droplet size. 3 of these is 72 USD/month — see ADR 0016's costing."
  type        = string
  default     = "s-2vcpu-4gb"
}

variable "node_count" {
  description = <<-EOT
    Fixed at 3 (ADR 0016): the fewest at which losing one node still leaves
    room for every request, and at which a three-replica Raft group can put each
    member on its own node. Not autoscaled: the budget is already past ADR 0004's
    target, and an autoscaler is exactly the thing that spends more without
    asking.
  EOT
  type        = number
  default     = 3
}

variable "maintenance_window" {
  description = "When patch upgrades are applied, in UTC. Default is 03:00 Sunday Pacific."
  type = object({
    day        = string
    start_time = string
  })
  default = {
    day        = "sunday"
    start_time = "10:00"
  }
}

variable "apex_record" {
  description = <<-EOT
    Whether to publish the apex A record at all. Set false to withdraw
    heptapedal.com during a rebuild — better than parking it on an address that
    answers nothing, since clients then fail immediately instead of hanging.
  EOT
  type        = bool
  default     = true
}

variable "apex_ip" {
  description = <<-EOT
    Where heptapedal.com points. This is the Gateway's Load Balancer address,
    which DigitalOcean assigns when Argo CD reconciles the Gateway — so on a
    rebuilt cluster it changes and this has to change with it. Nothing warns
    when it goes stale — see dns-apex.tf.
  EOT
  type        = string
  default     = "24.199.71.41"
}

variable "apex_ttl" {
  description = "Seconds. Short, because this record is expected to change."
  type        = number
  default     = 300
}
