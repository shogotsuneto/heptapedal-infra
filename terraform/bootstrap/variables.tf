variable "bucket_name" {
  description = <<-EOT
    Bucket holding every stack's state. Spaces bucket names are unique across
    the whole service, not just this account, so a generic name will collide.
  EOT
  type        = string
  default     = "heptapedal-tfstate"
}

variable "region" {
  description = <<-EOT
    DigitalOcean region. sgp1 is the closest Spaces region to Japan —
    DigitalOcean has no Tokyo datacenter. Keep it in step with the platform
    stack: DOKS, Managed Postgres and the Load Balancer all live in one region.
  EOT
  type        = string
  default     = "sgp1"
}
