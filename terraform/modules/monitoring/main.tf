# ─── Module monitoring : kube-prometheus-stack ────────────────────────────────
# Déploie : Prometheus + Grafana + Alertmanager + node-exporter + kube-state-metrics
# Accès via port-forward :
#   kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
# ──────────────────────────────────────────────────────────────────────────────

resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = var.namespace
    labels = {
      "managed-by" = "terraform"
    }
  }
}

resource "helm_release" "kube_prometheus_stack" {
  name       = "kube-prometheus-stack"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = var.chart_version
  namespace  = kubernetes_namespace.monitoring.metadata[0].name

  # Évite un timeout sur les CRDs volumineuses du chart
  timeout         = 600
  cleanup_on_fail = true

  values = [
    yamlencode({
      # ── Prometheus ───────────────────────────────────────────────────────────
      prometheus = {
        prometheusSpec = {
          retention = var.prometheus_retention
          resources = {
            requests = { memory = "512Mi", cpu = "250m" }
            limits   = { memory = "1Gi", cpu = "500m" }
          }
          # PVC pour la persistance des métriques
          storageSpec = {
            volumeClaimTemplate = {
              spec = {
                storageClassName = "standard"
                accessModes      = ["ReadWriteOnce"]
                resources = {
                  requests = { storage = var.prometheus_storage_size }
                }
              }
            }
          }
          # Scraping de tous les namespaces
          podMonitorNamespaceSelector     = {}
          serviceMonitorNamespaceSelector = {}
          ruleNamespaceSelector           = {}
        }
      }

      # ── Grafana ───────────────────────────────────────────────────────────────
      grafana = {
        adminPassword = var.grafana_admin_password
        service = {
          type = "ClusterIP"
        }
        resources = {
          requests = { memory = "128Mi", cpu = "100m" }
          limits   = { memory = "256Mi", cpu = "200m" }
        }
        # Dashboards supplémentaires pré-chargés
        defaultDashboardsEnabled = true
        persistence = {
          enabled          = true
          storageClassName = "standard"
          size             = "1Gi"
        }
        # Grafana ini : désactiver les news/télémétrie en local
        grafana = {
          "server.root_url" = "http://localhost:3000"
        }
      }

      # ── Alertmanager ──────────────────────────────────────────────────────────
      alertmanager = {
        alertmanagerSpec = {
          resources = {
            requests = { memory = "64Mi", cpu = "50m" }
            limits   = { memory = "128Mi", cpu = "100m" }
          }
        }
      }

      # ── node-exporter ─────────────────────────────────────────────────────────
      nodeExporter = {
        resources = {
          requests = { memory = "32Mi", cpu = "50m" }
          limits   = { memory = "64Mi", cpu = "100m" }
        }
      }

      # ── kube-state-metrics ────────────────────────────────────────────────────
      kubeStateMetrics = {
        resources = {
          requests = { memory = "64Mi", cpu = "50m" }
          limits   = { memory = "128Mi", cpu = "100m" }
        }
      }

      # Compatibilité Apple Silicon / minikube : désactiver les composants
      # qui peuvent causer des problèmes sur un cluster mono-nœud local
      kubeControllerManager = { enabled = false }
      kubeScheduler         = { enabled = false }
      kubeProxy             = { enabled = false }
      kubeEtcd              = { enabled = false }
    })
  ]

  depends_on = [kubernetes_namespace.monitoring]
}
