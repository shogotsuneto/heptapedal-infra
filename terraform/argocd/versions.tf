terraform {
  required_version = ">= 1.10.0"

  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.100"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.2"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.2"
    }
  }
}

provider "digitalocean" {}

# Credentials come from a data source, never from the platform stack's
# kubeconfig output. DigitalOcean issues them with a 7 day expiry, so a token
# captured in state goes stale and takes both providers below with it; a data
# source is re-read on every plan and reissues instead.
data "digitalocean_kubernetes_cluster" "heptapedal" {
  name = var.cluster_name
}

locals {
  kube = {
    host  = data.digitalocean_kubernetes_cluster.heptapedal.endpoint
    token = data.digitalocean_kubernetes_cluster.heptapedal.kube_config[0].token
    ca    = base64decode(data.digitalocean_kubernetes_cluster.heptapedal.kube_config[0].cluster_ca_certificate)
  }
}

provider "kubernetes" {
  host                   = local.kube.host
  token                  = local.kube.token
  cluster_ca_certificate = local.kube.ca
}

# helm provider 3.x takes `kubernetes` as an attribute, not a nested block.
provider "helm" {
  kubernetes = {
    host                   = local.kube.host
    token                  = local.kube.token
    cluster_ca_certificate = local.kube.ca
  }
}
