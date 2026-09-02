# Read-only access to this repository, for a private one.
#
# Created only when a key is supplied. Making the repository public deletes the
# need for it entirely — Argo CD reads a public repository with no credential —
# which is the simplification ADR 0012 was written to make available and #28
# gates. Leave repo_ssh_private_key empty and this resource disappears.
#
# Sealed Secrets cannot carry this one: it is what lets Argo CD read the
# repository the sealed manifests live in, so it has to exist before GitOps can
# start. Bootstrap material, like the Spaces keys.
resource "kubernetes_secret_v1" "repository" {
  count = var.repo_ssh_private_key == "" ? 0 : 1

  metadata {
    name      = "heptapedal-infra"
    namespace = var.namespace
    labels = {
      "argocd.argoproj.io/secret-type" = "repository"
    }
  }

  data = {
    type          = "git"
    url           = var.repo_url
    sshPrivateKey = var.repo_ssh_private_key
  }

  lifecycle {
    precondition {
      condition     = startswith(var.repo_url, "git@")
      error_message = "A deploy key authenticates SSH, so repo_url must be the SSH form (git@github.com:owner/repo.git). The HTTPS form would make Argo CD ignore this credential and fail to read a private repository."
    }
  }

  depends_on = [helm_release.argocd]
}
