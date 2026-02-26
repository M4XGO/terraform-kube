variable "cluster_name" {
  description = "Nom du contexte kubectl"
  type        = string
}

variable "app_namespace" {
  description = "Namespace de l'application demo-app"
  type        = string
  default     = "demo-app"
}

variable "argocd_namespace" {
  description = "Namespace ArgoCD"
  type        = string
  default     = "argocd"
}

variable "git_repo_url" {
  description = <<-EOT
    URL du dépôt Git pour ArgoCD GitOps.
    Si vide : l'application est déployée via Helm direct (sans GitOps).
    Si défini : ArgoCD synchronise depuis ce repo (créé par Ansible post-deploy).
    Exemple : https://github.com/user/terraform-kube.git
  EOT
  type        = string
  default     = ""
}

variable "git_revision" {
  description = "Branch / tag Git à synchroniser (HEAD = branche courante)"
  type        = string
  default     = "HEAD"
}

variable "app_values_file" {
  description = "Fichier values à utiliser (values.yaml = blue, values-v2.yaml = green)"
  type        = string
  default     = "values.yaml"
}
