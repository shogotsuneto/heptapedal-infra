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

variable "node_size" {
  description = "Worker Droplet size. 2 of these is 48 USD/month — see ADR 0004's costing."
  type        = string
  default     = "s-2vcpu-4gb"
}

variable "node_count" {
  description = <<-EOT
    Fixed at 2. Not autoscaled: the budget in ADR 0004 has ~20 USD/month of
    headroom, and an autoscaler is exactly the thing that spends it without
    asking.
  EOT
  type        = number
  default     = 2
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
