output "bucket_name" {
  description = "Bucket name, for the backend block of every stack."
  value       = digitalocean_spaces_bucket.tfstate.name
}

output "region" {
  description = "Region the bucket lives in. Every other stack should match it."
  value       = digitalocean_spaces_bucket.tfstate.region
}

output "endpoint" {
  description = "Regional endpoint, e.g. sfo3.digitaloceanspaces.com. The backend wants it with an https:// prefix."
  value       = digitalocean_spaces_bucket.tfstate.endpoint
}

# Paste-ready, so a new stack does not have to rediscover which AWS-isms Spaces
# needs switched off.
output "backend_block" {
  description = "Backend configuration for a new stack — replace STACK with its name."
  value       = <<-EOT
    terraform {
      backend "s3" {
        endpoints = {
          s3 = "https://${digitalocean_spaces_bucket.tfstate.endpoint}"
        }

        bucket = "${digitalocean_spaces_bucket.tfstate.name}"
        key    = "STACK/terraform.tfstate"

        use_lockfile = true

        region                      = "us-east-1"
        skip_credentials_validation = true
        skip_requesting_account_id  = true
        skip_metadata_api_check     = true
        skip_region_validation      = true
        skip_s3_checksum            = true
      }
    }
  EOT
}

# The bucket-scoped key for every other stack's backend. Recoverable from state
# with `tofu output`, so it does not need storing anywhere else.
output "backend_access_key_id" {
  description = "AWS_ACCESS_KEY_ID for the s3 backend of every stack."
  value       = digitalocean_spaces_key.tfstate_backend.access_key
}

output "backend_secret_access_key" {
  description = "AWS_SECRET_ACCESS_KEY for the s3 backend of every stack."
  value       = digitalocean_spaces_key.tfstate_backend.secret_key
  sensitive   = true
}
