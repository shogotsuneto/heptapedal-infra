terraform {
  # use_lockfile — S3-native state locking, no DynamoDB equivalent — needs
  # OpenTofu 1.10 or later. See ADR 0003.
  required_version = ">= 1.10.0"

  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.100"
    }
  }
}

# Credentials come from the environment; see .envrc.example at the repo root.
#   DIGITALOCEAN_TOKEN                             the API token
#   SPACES_ACCESS_KEY_ID / SPACES_SECRET_ACCESS_KEY  the Spaces key
provider "digitalocean" {}
