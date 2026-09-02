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

variable "apps_chart_version" {
  description = <<-EOT
    argoproj/argocd-apps chart version — the official chart for declaring
    Applications. Used for the root Application only; every other Application is
    declared in git and reconciled by Argo CD.
  EOT
  type        = string
  default     = "2.0.5"
}

variable "repo_url" {
  description = <<-EOT
    Repository Argo CD reconciles from.

    SSH form, because a read-only deploy key authenticates SSH and Argo CD
    matches credentials to repositories by URL prefix — an HTTPS URL would
    simply not find the key. Keep it in step with the child Applications in
    gitops/root/.

    Publishing the repository would let all of these become HTTPS again, and the
    credential disappear (#28).
  EOT
  type        = string
  default     = "git@github.com:shogotsuneto/heptapedal-infra.git"
}

variable "target_revision" {
  description = "Branch or tag Argo CD tracks."
  type        = string
  default     = "main"
}
