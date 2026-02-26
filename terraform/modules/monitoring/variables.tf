variable "cluster_name" {
  description = "Nom du contexte kubectl"
  type        = string
}

variable "namespace" {
  description = "Namespace Kubernetes pour la stack monitoring"
  type        = string
  default     = "monitoring"
}

variable "chart_version" {
  description = "Version du chart kube-prometheus-stack"
  type        = string
  default     = "82.4.0"
}

variable "grafana_admin_password" {
  description = "Mot de passe admin Grafana"
  type        = string
  sensitive   = true
}

variable "prometheus_retention" {
  description = "Durée de rétention des métriques Prometheus"
  type        = string
  default     = "24h"
}

variable "prometheus_storage_size" {
  description = "Taille du PersistentVolumeClaim Prometheus"
  type        = string
  default     = "10Gi"
}
