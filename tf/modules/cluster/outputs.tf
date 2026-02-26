output "cluster_name" {
  description = "Nom du cluster / contexte kubectl"
  value       = var.cluster_name
}

output "node_names" {
  description = "Liste des nœuds du cluster"
  value       = [for node in data.kubernetes_nodes.cluster.nodes : node.metadata[0].name]
}

output "node_count" {
  description = "Nombre de nœuds"
  value       = length(data.kubernetes_nodes.cluster.nodes)
}

output "cluster_ready" {
  description = "Sentinel : cluster accessible et stable (utilisé en depends_on)"
  value       = time_sleep.stabilization.id
}
