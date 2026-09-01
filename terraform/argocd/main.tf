# Argo CD itself. This is the last thing Terraform installs into the cluster:
# from here the root Application (#9) takes over and everything else arrives
# through GitOps. See ADR 0006.
resource "helm_release" "argocd" {
  name       = "argocd"
  namespace  = var.namespace
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.chart_version

  create_namespace = true

  values = [file("${path.module}/values/argocd.yaml")]

  # The chart installs several controllers; give them room to become ready
  # before calling the apply a failure.
  timeout = 900
}
