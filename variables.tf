# ─── Cluster ─────────────────────────────────────────────────────────────────

variable "cluster_name" {
  description = "Nom du profil minikube et du contexte kubectl"
  type        = string
  default     = "terraform-kube"
}

variable "kubernetes_version" {
  description = "Version de Kubernetes (ex: v1.29.3)"
  type        = string
  default     = "v1.29.3"
}

variable "cpus" {
  description = "Nombre de CPUs alloués au cluster minikube"
  type        = number
  default     = 4
}

variable "memory" {
  description = "Mémoire allouée au cluster minikube en Mo"
  type        = number
  default     = 6144
}

variable "driver" {
  description = "Driver minikube : docker (recommandé macOS), hyperkit, virtualbox, qemu2"
  type        = string
  default     = "docker"

  validation {
    condition     = contains(["docker", "hyperkit", "virtualbox", "qemu2"], var.driver)
    error_message = "Le driver doit être : docker, hyperkit, virtualbox ou qemu2."
  }
}

variable "disk_size" {
  description = "Taille du disque pour minikube (ex: 20g)"
  type        = string
  default     = "20g"
}

# ─── Feature flags ────────────────────────────────────────────────────────────

variable "enable_cilium" {
  description = <<-EOT
    Remplace le CNI par défaut par Cilium (eBPF).
    ATTENTION : sur Apple Silicon avec Docker Desktop, le support eBPF complet
    dépend de la version du kernel dans la VM Docker Desktop (>= 4.15 requis).
    Désactive le CNI par défaut et laisse Cilium prendre en charge le réseau.
  EOT
  type        = bool
  default     = false
}

variable "enable_platform" {
  description = "Déploie la couche plateforme : Ingress NGINX + cert-manager (+ Cilium si enable_cilium=true)"
  type        = bool
  default     = true
}

variable "enable_monitoring" {
  description = "Déploie la stack de monitoring : Prometheus + Grafana + Alertmanager (kube-prometheus-stack)"
  type        = bool
  default     = true
}

variable "enable_gitops" {
  description = "Déploie ArgoCD + Argo Rollouts"
  type        = bool
  default     = true
}

# ─── Application config ───────────────────────────────────────────────────────

variable "grafana_admin_password" {
  description = "Mot de passe admin Grafana (accessible via port-forward sur :3000)"
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
