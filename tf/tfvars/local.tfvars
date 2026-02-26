# Copier ce fichier en terraform.tfvars et adapter les valeurs

# ─── Cluster ──────────────────────────────────────────────────────────────────
cluster_name       = "terraform-kube"
kubernetes_version = "v1.29.3"
driver             = "docker" # docker recommandé sur macOS Apple Silicon
cpus               = 4
memory             = 6144 # Mo — Docker Desktop sur macOS est souvent limité à ~7.8GB
disk_size          = "20g"

# ─── Features ─────────────────────────────────────────────────────────────────
enable_cilium     = false # true : remplace kindnet par Cilium (eBPF)
enable_platform   = true  # Ingress NGINX + cert-manager
enable_monitoring = true  # kube-prometheus-stack (Prometheus + Grafana)
enable_gitops     = true  # ArgoCD + Argo Rollouts

# ─── Credentials ──────────────────────────────────────────────────────────────
grafana_admin_password = "admin" # À changer en production

# ─── Application demo (blue/green) ────────────────────────────────────────────
enable_apps   = true
app_namespace = "demo-app"
# Laisser vide pour Helm direct, ou mettre l'URL de votre repo GitHub/GitLab
# pour activer le mode GitOps ArgoCD complet :
# git_repo_url = "https://github.com/VOTRE-USER/terraform-kube.git"
git_repo_url = ""
