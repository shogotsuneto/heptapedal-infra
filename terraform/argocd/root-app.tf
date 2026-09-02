# The single Application Terraform manages. Everything else — the platform
# bundle, the applications — is declared in git under gitops/ and reconciled by
# Argo CD from here (ADR 0006).
#
# Declared through the official argocd-apps chart rather than a
# kubernetes_manifest resource, which would need Argo CD's CRDs to already
# exist at *plan* time and so could not describe a cluster being built from
# nothing. depends_on gives the ordering instead: helm_release waits for the
# Argo CD release to be ready before this one installs.
resource "helm_release" "root" {
  name       = "argocd-root"
  namespace  = var.namespace
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-apps"
  version    = var.apps_chart_version

  values = [yamlencode({
    applications = {
      root = {
        namespace = var.namespace
        # Deleting this Application takes its children with it, rather than
        # orphaning a tree of Applications nothing manages any more.
        finalizers = ["resources-finalizer.argocd.argoproj.io"]
        project    = "default"

        source = {
          repoURL        = var.repo_url
          targetRevision = var.target_revision
          path           = "gitops/root"
          directory      = { recurse = false }
        }

        destination = {
          server    = "https://kubernetes.default.svc"
          namespace = var.namespace
        }

        syncPolicy = {
          automated = {
            prune    = true
            selfHeal = true
          }
        }
      }
    }
  })]

  depends_on = [helm_release.argocd]
}
