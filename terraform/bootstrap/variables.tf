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
    DigitalOcean region — see ADR 0013. Every stack lives in one region, so
    changing this means changing the platform stack too, and the literal in
    backend.tf that a backend block cannot take from a variable.
  EOT
  type        = string
  default     = "sfo3"
}
