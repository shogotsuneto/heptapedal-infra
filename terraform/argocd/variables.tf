variable "cluster_name" {
  description = "DOKS cluster to install into. Matches the platform stack's cluster_name output."
  type        = string
  default     = "heptapedal"
}

variable "namespace" {
  description = "Namespace for the Argo CD release."
  type        = string
  default     = "argocd"
}

variable "chart_version" {
  description = <<-EOT
    argo-proj/argo-cd chart version. Pinned deliberately; Renovate proposes
    bumps (#21). Chart 10.6.0 carries Argo CD v3.5.2.
  EOT
  type        = string
  default     = "10.6.0"
}
