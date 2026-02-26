output "ingress_nginx_namespace" {
  description = "Namespace Ingress NGINX"
  value       = kubernetes_namespace.ingress_nginx.metadata[0].name
}

output "cert_manager_namespace" {
  description = "Namespace cert-manager"
  value       = kubernetes_namespace.cert_manager.metadata[0].name
}

output "cilium_enabled" {
  description = "Cilium est-il activé ?"
  value       = var.enable_cilium
}

output "cert_manager_ready" {
  description = "Sentinel : cert-manager est prêt (CRDs disponibles)"
  value       = time_sleep.wait_for_cert_manager_crds.id
}
