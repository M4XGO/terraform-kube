# ─── Module cluster ───────────────────────────────────────────────────────────
# Ce module ne provisionne PAS le cluster — c'est le rôle de Terraform/vms +
# Ansible (k3s-install.yml).
#
# Ce module valide la connectivité au cluster k3s et sert de point d'ancrage
# (depends_on) pour les autres modules.
# ──────────────────────────────────────────────────────────────────────────────

data "kubernetes_nodes" "cluster" {}

# Courte pause pour laisser l'API server se stabiliser si le cluster vient
# d'être démarré par Ansible
resource "time_sleep" "stabilization" {
  create_duration = "10s"
  depends_on      = [data.kubernetes_nodes.cluster]
}
