# State lives in the bucket created by terraform/bootstrap. A backend block
# cannot reference variables, so these are literals; keep them in step with
# variables.tf and with ADR 0013's region.
terraform {
  backend "s3" {
    endpoints = {
      s3 = "https://sfo3.digitaloceanspaces.com"
    }

    bucket = "heptapedal-tfstate"
    key    = "platform/terraform.tfstate"

    use_lockfile = true

    region                      = "us-east-1"
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_s3_checksum            = true
  }
}
