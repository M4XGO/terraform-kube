variable "cluster_name" {
  description = "Nom du contexte kubectl (utilisé par les annotations/labels)"
  type        = string
}

variable "enable_cilium" {
  description = "Installe Cilium comme CNI (le cluster doit avoir démarré avec cni=false)"
  type        = bool
  default     = false
}

variable "cilium_version" {
  description = "Version du chart Helm Cilium"
  type        = string
  default     = "1.19.1"
}

variable "ingress_nginx_version" {
  description = "Version du chart Helm Ingress NGINX"
  type        = string
  default     = "4.14.3"
}

variable "cert_manager_version" {
  description = "Version du chart Helm cert-manager"
  type        = string
  default     = "v1.19.4"
}
