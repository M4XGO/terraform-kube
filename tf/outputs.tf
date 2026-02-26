output "cluster_name" {
  description = "Nom du cluster / contexte kubectl"
  value       = module.cluster.cluster_name
}

output "cluster_nodes" {
  description = "Nœuds du cluster"
  value       = module.cluster.node_names
}

output "access_commands" {
  description = "Commandes d'accès aux services (via port-forward)"
  value       = <<-EOT

    ════════════════════════════════════════════════
     CLUSTER
    ════════════════════════════════════════════════
    kubectl config use-context ${var.cluster_name}
    kubectl get nodes -o wide
    minikube status --profile ${var.cluster_name}

    %{if var.enable_monitoring~}
    ════════════════════════════════════════════════
     MONITORING
    ════════════════════════════════════════════════
    # Grafana  — http://localhost:3000
    kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
    # login: admin / (terraform output -raw grafana_admin_password)

    # Prometheus — http://localhost:9090
    kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090

    # Alertmanager — http://localhost:9093
    kubectl port-forward -n monitoring svc/kube-prometheus-stack-alertmanager 9093:9093

    %{endif~}
    %{if var.enable_gitops~}
    ════════════════════════════════════════════════
     ARGOCD
    ════════════════════════════════════════════════
    # UI — http://localhost:8080
    kubectl port-forward -n argocd svc/argocd-server 8080:80
    # Récupérer le mot de passe admin :
    kubectl -n argocd get secret argocd-initial-admin-secret \
      -o jsonpath="{.data.password}" | base64 -d && echo

    # Argo Rollouts Dashboard — http://localhost:3100
    kubectl port-forward -n argo-rollouts svc/argo-rollouts-dashboard 3100:3100

    %{endif~}
    ════════════════════════════════════════════════
     DÉMARRAGE RAPIDE
    ════════════════════════════════════════════════
    make port-forwards   # Lance tous les port-forwards en arrière-plan
    make status          # État des pods par namespace

  EOT
}

output "argocd_admin_password_cmd" {
  description = "Commande pour récupérer le mot de passe ArgoCD"
  value       = var.enable_gitops ? "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d && echo" : "GitOps non activé"
}

output "grafana_admin_password" {
  description = "Mot de passe admin Grafana"
  value       = var.grafana_admin_password
  sensitive   = true
}

# ─── Outputs pour Ansible post-deploy ────────────────────────────────────────
# Lus depuis terraform-outputs.json par ansible/playbooks/post-deploy.yml

output "app_namespace" {
  description = "Namespace de l'application demo (lu par Ansible post-deploy)"
  value       = var.app_namespace
}

output "git_repo_url" {
  description = "URL du dépôt Git ArgoCD (lu par Ansible post-deploy, vide = mode Helm direct)"
  value       = var.git_repo_url
}
