# ─── Cluster k3s (connectivité) ───────────────────────────────────────────────
# Les VMs sont créées par terraform/vms/, k3s est installé par Ansible.
# Ce module valide uniquement que le cluster est accessible.
module "cluster" {
  source = "./modules/cluster"

  cluster_name = var.cluster_name
}

# ─── Couche plateforme : Cilium (opt.) + Ingress NGINX + cert-manager ─────────
# Note : le ClusterIssuer cert-manager est créé par Ansible (post-deploy)
#        car kubernetes_manifest nécessite les CRDs au moment du plan.
module "platform" {
  source = "./modules/platform"
  count  = var.enable_platform ? 1 : 0

  cluster_name = var.cluster_name

  depends_on = [module.cluster]
}

# ─── Stack monitoring : kube-prometheus-stack ─────────────────────────────────
module "monitoring" {
  source = "./modules/monitoring"
  count  = var.enable_monitoring ? 1 : 0

  cluster_name           = var.cluster_name
  grafana_admin_password = var.grafana_admin_password

  depends_on = [module.cluster, module.platform]
}

# ─── GitOps : ArgoCD + Argo Rollouts ─────────────────────────────────────────
module "gitops" {
  source = "./modules/gitops"
  count  = var.enable_gitops ? 1 : 0

  cluster_name = var.cluster_name

  depends_on = [module.cluster, module.platform]
}

# ─── Application demo : Blue/Green avec Argo Rollouts ─────────────────────────
# Déploie demo-app via Helm (chart local apps/demo-app/).
# ArgoCD Application + AppProject créés par Ansible (post-deploy).
# Requires : module.gitops (CRDs Argo Rollouts)
module "apps" {
  source = "./modules/apps"
  count  = var.enable_apps ? 1 : 0

  cluster_name  = var.cluster_name
  app_namespace = var.app_namespace
  git_repo_url  = var.git_repo_url

  depends_on = [module.gitops, module.platform]
}
