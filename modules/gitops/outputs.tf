output "argocd_namespace" {
  description = "Namespace ArgoCD"
  value       = kubernetes_namespace.argocd.metadata[0].name
}

output "rollouts_namespace" {
  description = "Namespace Argo Rollouts"
  value       = kubernetes_namespace.argo_rollouts.metadata[0].name
}

output "argocd_port_forward_cmd" {
  description = "Commande port-forward ArgoCD UI"
  value       = "kubectl port-forward -n ${kubernetes_namespace.argocd.metadata[0].name} svc/argocd-server 8080:80"
}

output "rollouts_port_forward_cmd" {
  description = "Commande port-forward Argo Rollouts Dashboard"
  value       = "kubectl port-forward -n ${kubernetes_namespace.argo_rollouts.metadata[0].name} svc/argo-rollouts-dashboard 3100:3100"
}

output "argocd_admin_password_cmd" {
  description = "Commande pour récupérer le mot de passe admin ArgoCD"
  value       = "kubectl -n ${kubernetes_namespace.argocd.metadata[0].name} get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d && echo"
}

output "argocd_status" {
  description = "Statut du Helm release ArgoCD"
  value       = helm_release.argocd.status
}

output "rollouts_status" {
  description = "Statut du Helm release Argo Rollouts"
  value       = helm_release.argo_rollouts.status
}
