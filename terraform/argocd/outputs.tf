output "namespace" {
  description = "Namespace Argo CD runs in."
  value       = helm_release.argocd.namespace
}

output "chart_version" {
  description = "argo-cd chart version actually deployed."
  value       = helm_release.argocd.version
}

output "app_version" {
  description = "Argo CD version the chart carries."
  value       = helm_release.argocd.metadata.app_version
}
