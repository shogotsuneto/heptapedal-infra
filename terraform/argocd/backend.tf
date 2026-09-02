# Separate key from the platform stack: this one is applied against the cluster
# rather than the cloud, and it should be possible to rebuild it without
# touching the substrate.
terraform {
  backend "s3" {
    endpoints = {
      s3 = "https://sfo3.digitaloceanspaces.com"
    }

    bucket = "heptapedal-tfstate"
    key    = "argocd/terraform.tfstate"

    use_lockfile = true

    region                      = "us-east-1"
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_s3_checksum            = true
  }
}
