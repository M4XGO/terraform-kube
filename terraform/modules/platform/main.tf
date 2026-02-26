# ─── Module platform ──────────────────────────────────────────────────────────
# Ordre de déploiement :
#   1. Cilium (si enable_cilium=true) — doit être le premier CNI actif
#   2. Ingress NGINX                  — exposition des services HTTP/S
#   3. cert-manager                   — gestion des certificats TLS
#
# Le ClusterIssuer (self-signed / Let's Encrypt) est créé par Ansible
# via le playbook ansible/playbooks/post-deploy.yml
# (kubernetes_manifest nécessite les CRDs cert-manager au moment du plan)
# ──────────────────────────────────────────────────────────────────────────────

# ─── 1. Cilium (CNI optionnel) ────────────────────────────────────────────────

resource "helm_release" "cilium" {
  count = var.enable_cilium ? 1 : 0

  name       = "cilium"
  repository = "https://helm.cilium.io/"
  chart      = "cilium"
  version    = var.cilium_version
  namespace  = "kube-system"

  values = [
    yamlencode({
      # Mode tunnel VXLAN : compatible Docker Desktop sur Apple Silicon
      tunnel               = "vxlan"
      kubeProxyReplacement = "partial"

      operator = {
        replicas = 1
      }

      ipam = {
        mode = "cluster-pool"
        operator = {
          clusterPoolIPv4PodCIDRList = ["10.244.0.0/16"]
        }
      }

      # Cgroup v2 — nécessaire pour Docker Desktop sur macOS
      cgroup = {
        autoMount = {
          enabled = false
        }
        hostRoot = "/sys/fs/cgroup"
      }

      # Désactiver les features nécessitant un eBPF kernel complet
      # (limitations Docker Desktop < 4.15)
      hostServices = {
        enabled = false
      }

      resources = {
        requests = { cpu = "100m", memory = "128Mi" }
        limits   = { cpu = "500m", memory = "512Mi" }
      }
    })
  ]

  timeout = 600
}

# Attente que Cilium soit opérationnel avant d'installer l'Ingress
resource "time_sleep" "wait_for_cilium" {
  count = var.enable_cilium ? 1 : 0

  create_duration = "60s"
  depends_on      = [helm_release.cilium]
}

# ─── 2. Ingress NGINX ─────────────────────────────────────────────────────────

resource "kubernetes_namespace" "ingress_nginx" {
  metadata {
    name = "ingress-nginx"
    labels = {
      "managed-by" = "terraform"
    }
  }

  # Attendre que Cilium soit prêt si activé (dépendance sur liste = vide si count=0)
  depends_on = [time_sleep.wait_for_cilium]
}

resource "helm_release" "ingress_nginx" {
  name       = "ingress-nginx"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  version    = var.ingress_nginx_version
  namespace  = kubernetes_namespace.ingress_nginx.metadata[0].name

  values = [
    yamlencode({
      controller = {
        service = {
          type = "NodePort"
        }
        # Désactiver le webhook d'admission pour simplifier l'environnement local
        admissionWebhooks = {
          enabled = false
        }
        resources = {
          requests = { cpu = "100m", memory = "128Mi" }
          limits   = { cpu = "500m", memory = "512Mi" }
        }
        # Métriques pour Prometheus
        metrics = {
          enabled = true
          serviceMonitor = {
            enabled = false # Activé si monitoring est déployé après
          }
        }
      }
    })
  ]

  timeout = 300
}

# ─── 3. cert-manager ──────────────────────────────────────────────────────────

resource "kubernetes_namespace" "cert_manager" {
  metadata {
    name = "cert-manager"
    labels = {
      "managed-by" = "terraform"
    }
  }
}

resource "helm_release" "cert_manager" {
  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  version    = var.cert_manager_version
  namespace  = kubernetes_namespace.cert_manager.metadata[0].name

  # Installe les CRDs (Certificate, ClusterIssuer, etc.)
  set {
    name  = "installCRDs"
    value = "true"
  }

  values = [
    yamlencode({
      resources = {
        requests = { cpu = "50m", memory = "64Mi" }
        limits   = { cpu = "200m", memory = "256Mi" }
      }
      # Métriques pour Prometheus
      prometheus = {
        enabled = true
        servicemonitor = {
          enabled = false
        }
      }
    })
  ]

  timeout    = 300
  depends_on = [kubernetes_namespace.cert_manager]
}

# Attente que les CRDs cert-manager soient bien enregistrées
# avant que Ansible crée le ClusterIssuer
resource "time_sleep" "wait_for_cert_manager_crds" {
  create_duration = "30s"
  depends_on      = [helm_release.cert_manager]
}
