terraform {
  required_version = ">= 1.10.0"

  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.100"
    }
  }
}

# DIGITALOCEAN_TOKEN from the environment; see .envrc.example at the repo root.
# This stack touches no Spaces resources, so SPACES_* is not needed — only the
# backend's AWS_* pair, which is the bucket-scoped key.
provider "digitalocean" {}
