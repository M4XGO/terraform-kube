# ─── Module cluster ───────────────────────────────────────────────────────────
# Ce module ne provisionne PAS le cluster — c'est le rôle d'Ansible.
# Ansible (ansible/playbooks/pre-deploy.yml) exécute `minikube start` avant
# que Terraform ne soit invoqué (orchestré par `make deploy`).
#
# Ce module valide la connectivité et expose des informations sur le cluster
# que les autres modules utilisent via depends_on.
# ──────────────────────────────────────────────────────────────────────────────

data "kubernetes_nodes" "cluster" {}

# Courte pause pour laisser l'API server se stabiliser si le cluster vient
# d'être démarré par Ansible
resource "time_sleep" "stabilization" {
  create_duration = "10s"
  depends_on      = [data.kubernetes_nodes.cluster]
}
