output "namespace" {
  description = "Namespace de l'application"
  value       = kubernetes_namespace.demo_app.metadata[0].name
}

output "app_url" {
  description = "URL de l'application (production)"
  value       = "http://demo-app.local"
}

output "preview_url" {
  description = "URL du service preview (nouvelle version en cours de test)"
  value       = "http://preview.demo-app.local"
}
