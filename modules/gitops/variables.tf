variable "cluster_name" {
  description = "Nom du contexte kubectl"
  type        = string
}

variable "argocd_namespace" {
  description = "Namespace ArgoCD"
  type        = string
  default     = "argocd"
}

variable "rollouts_namespace" {
  description = "Namespace Argo Rollouts"
  type        = string
  default     = "argo-rollouts"
}

variable "argocd_version" {
  description = "Version du chart Helm ArgoCD"
  type        = string
  default     = "9.4.5"
}

variable "rollouts_version" {
  description = "Version du chart Helm Argo Rollouts"
  type        = string
  default     = "2.40.6"
}
