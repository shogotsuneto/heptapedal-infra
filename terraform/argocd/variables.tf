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
    Repository Argo CD reconciles from. Use the HTTPS form for a public
    repository, or the SSH form (git@github.com:owner/repo.git) together with
    repo_ssh_private_key for a private one.
  EOT
  type        = string
  default     = "https://github.com/shogotsuneto/heptapedal-infra.git"
}

variable "target_revision" {
  description = "Branch or tag Argo CD tracks."
  type        = string
  default     = "main"
}

variable "repo_ssh_private_key" {
  description = <<-EOT
    Read-only deploy key for a private repository, from the environment as
    TF_VAR_repo_ssh_private_key. Never committed.

    Leave empty when the repository is public — Argo CD then needs no credential
    at all, and none is created. See ADR 0011.
  EOT
  type        = string
  default     = ""
  sensitive   = true
}
