# ─── Cluster ─────────────────────────────────────────────────────────────────

variable "cluster_name" {
  description = "Nom du contexte kubectl (k3s — défini par ansible/playbooks/k3s-install.yml)"
  type        = string
  default     = "automatisation-ansible-cluster"
}

# ─── Feature flags ────────────────────────────────────────────────────────────

variable "enable_platform" {
  description = "Déploie la couche plateforme : Ingress NGINX + cert-manager"
  type        = bool
  default     = true
}

variable "enable_monitoring" {
  description = "Déploie la stack de monitoring : Prometheus + Grafana + Alertmanager"
  type        = bool
  default     = true
}

variable "enable_gitops" {
  description = "Déploie ArgoCD + Argo Rollouts"
  type        = bool
  default     = true
}

# ─── Credentials ──────────────────────────────────────────────────────────────

variable "grafana_admin_password" {
  description = "Mot de passe admin Grafana"
  type        = string
  default     = "admin"
  sensitive   = true
}

# ─── Application demo ─────────────────────────────────────────────────────────

variable "enable_apps" {
  description = "Déploie l'application demo-app avec Blue/Green Argo Rollouts"
  type        = bool
  default     = true
}

variable "app_namespace" {
  description = "Namespace Kubernetes de l'application demo"
  type        = string
  default     = "demo-app"
}

variable "git_repo_url" {
  description = <<-EOT
    URL du dépôt Git pour ArgoCD GitOps.
    Laisser vide pour Helm direct (démo locale sans Git).
    Exemple : https://github.com/user/terraform-kube.git
  EOT
  type        = string
  default     = ""
}
