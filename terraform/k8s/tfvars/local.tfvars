# ─── Cluster ──────────────────────────────────────────────────────────────────
# Doit correspondre au nom du contexte kubectl généré par ansible/k3s-install.yml
cluster_name = "automatisation-ansible-cluster"

# ─── Features ─────────────────────────────────────────────────────────────────
enable_platform   = true  # Ingress NGINX + cert-manager
enable_monitoring = true  # kube-prometheus-stack (Prometheus + Grafana)
enable_gitops     = true  # ArgoCD + Argo Rollouts

# ─── Credentials ──────────────────────────────────────────────────────────────
grafana_admin_password = "admin"

# ─── Application demo (blue/green) ────────────────────────────────────────────
enable_apps   = true
app_namespace = "demo-app"
git_repo_url  = "https://github.com/M4XGO/terraform-kube.git"
