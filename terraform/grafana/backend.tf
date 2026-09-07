# Its own key. This stack touches neither the cloud nor the cluster — it
# configures Grafana Cloud — so it should be rebuildable without either.
terraform {
  backend "s3" {
    endpoints = {
      s3 = "https://sfo3.digitaloceanspaces.com"
    }

    bucket = "heptapedal-tfstate"
    key    = "grafana/terraform.tfstate"

    use_lockfile = true

    region                      = "us-east-1"
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_s3_checksum            = true
  }
}
