output "namespace" {
  description = "Namespace de la stack monitoring"
  value       = kubernetes_namespace.monitoring.metadata[0].name
}

output "grafana_port_forward_cmd" {
  description = "Commande port-forward Grafana"
  value       = "kubectl port-forward -n ${kubernetes_namespace.monitoring.metadata[0].name} svc/kube-prometheus-stack-grafana 3000:80"
}

output "prometheus_port_forward_cmd" {
  description = "Commande port-forward Prometheus"
  value       = "kubectl port-forward -n ${kubernetes_namespace.monitoring.metadata[0].name} svc/kube-prometheus-stack-prometheus 9090:9090"
}

output "helm_release_status" {
  description = "Statut du Helm release kube-prometheus-stack"
  value       = helm_release.kube_prometheus_stack.status
}
