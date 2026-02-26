# ─── Module apps ──────────────────────────────────────────────────────────────
# Crée le namespace de l'application demo-app.
#
# Le déploiement de l'application est géré par Ansible (post-deploy.yml) :
#   - Mode local  (git_repo_url = "") : helm install via Ansible → Argo Rollouts
#   - Mode GitOps (git_repo_url défini) : ArgoCD Application → Argo Rollouts
#
# Pourquoi Terraform ne déploie plus le chart ?
# → Éviter le conflit Terraform/ArgoCD sur les mêmes ressources.
# → ArgoCD doit être le seul owner du Rollout pour que les syncs déclenchent
#   bien le Blue/Green via Argo Rollouts.
# ──────────────────────────────────────────────────────────────────────────────

resource "kubernetes_namespace" "demo_app" {
  metadata {
    name = var.app_namespace
    labels = {
      "managed-by"                 = "terraform"
      "argocd.argoproj.io/managed" = "true"
    }
  }
}
