# ─── Module GitOps : ArgoCD + Argo Rollouts ───────────────────────────────────
# ArgoCD  : UI sur http://localhost:8080 (après port-forward)
# Rollouts: Dashboard sur http://localhost:3100
#
# Mot de passe admin ArgoCD (auto-généré par ArgoCD) :
#   kubectl -n argocd get secret argocd-initial-admin-secret \
#     -o jsonpath="{.data.password}" | base64 -d && echo
# ──────────────────────────────────────────────────────────────────────────────

# ─── ArgoCD ───────────────────────────────────────────────────────────────────

resource "kubernetes_namespace" "argocd" {
  metadata {
    name = var.argocd_namespace
    labels = {
      "managed-by" = "terraform"
    }
  }
}

resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_version
  namespace  = kubernetes_namespace.argocd.metadata[0].name

  timeout         = 600
  cleanup_on_fail = true

  values = [
    yamlencode({
      configs = {
        params = {
          # Désactiver TLS en local (pas de cert-manager nécessaire pour ArgoCD)
          "server.insecure" = "true"
        }
      }

      server = {
        service = {
          type = "ClusterIP"
        }
        resources = {
          requests = { memory = "128Mi", cpu = "100m" }
          limits   = { memory = "256Mi", cpu = "300m" }
        }
        # Métriques Prometheus
        metrics = {
          enabled = true
          serviceMonitor = {
            enabled = false # Activer si kube-prometheus-stack est déployé
          }
        }
      }

      repoServer = {
        resources = {
          requests = { memory = "128Mi", cpu = "100m" }
          limits   = { memory = "512Mi", cpu = "500m" }
        }
      }

      applicationSet = {
        resources = {
          requests = { memory = "64Mi", cpu = "50m" }
          limits   = { memory = "128Mi", cpu = "200m" }
        }
      }

      controller = {
        resources = {
          requests = { memory = "256Mi", cpu = "250m" }
          limits   = { memory = "512Mi", cpu = "500m" }
        }
      }

      redis = {
        resources = {
          requests = { memory = "64Mi", cpu = "50m" }
          limits   = { memory = "128Mi", cpu = "200m" }
        }
      }

      dex = {
        enabled = false # SSO non nécessaire en local
      }

      # Notifications désactivées en local
      notifications = {
        enabled = false
      }
    })
  ]

  depends_on = [kubernetes_namespace.argocd]
}

# ─── Argo Rollouts ────────────────────────────────────────────────────────────

resource "kubernetes_namespace" "argo_rollouts" {
  metadata {
    name = var.rollouts_namespace
    labels = {
      "managed-by" = "terraform"
    }
  }
}

resource "helm_release" "argo_rollouts" {
  name       = "argo-rollouts"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-rollouts"
  version    = var.rollouts_version
  namespace  = kubernetes_namespace.argo_rollouts.metadata[0].name

  timeout         = 300
  cleanup_on_fail = true

  values = [
    yamlencode({
      # Dashboard UI pour visualiser les Rollouts
      dashboard = {
        enabled = true
        service = {
          type = "ClusterIP"
          port = 3100
        }
      }

      controller = {
        resources = {
          requests = { memory = "128Mi", cpu = "100m" }
          limits   = { memory = "256Mi", cpu = "300m" }
        }
        # Métriques Prometheus
        metrics = {
          enabled = true
          serviceMonitor = {
            enabled = false
          }
        }
      }
    })
  ]

  depends_on = [kubernetes_namespace.argo_rollouts]
}
