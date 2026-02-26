variable "cluster_name" {
  description = "Nom du profil minikube et du contexte kubectl"
  type        = string
}

variable "kubernetes_version" {
  description = "Version de Kubernetes"
  type        = string
}

variable "cpus" {
  description = "Nombre de CPUs"
  type        = number
}

variable "memory" {
  description = "Mémoire en Mo"
  type        = number
}

variable "driver" {
  description = "Driver minikube"
  type        = string
}

variable "disk_size" {
  description = "Taille du disque"
  type        = string
}

variable "enable_cilium" {
  description = "Désactive le CNI par défaut pour laisser Cilium prendre en charge le réseau"
  type        = bool
}
