# Le cluster minikube est provisionné par Ansible (ansible/playbooks/pre-deploy.yml).
# Terraform utilise le kubeconfig mis à jour par Ansible via config_path.
# Les modules k8s/helm dépendent du module cluster (data source de validation)
# qui garantit la connectivité avant toute opération.

provider "kubernetes" {
  config_path    = pathexpand("~/.kube/config")
  config_context = var.cluster_name
}

provider "helm" {
  kubernetes {
    config_path    = pathexpand("~/.kube/config")
    config_context = var.cluster_name
  }
  # Cache isolé : évite toute interférence avec les repos Helm locaux
  # (ex: bitnami sans cache → crash même sur des charts sans rapport)
  repository_config_path = "${path.cwd}/.terraform-helm/repositories.yaml"
  repository_cache       = "${path.cwd}/.terraform-helm/cache"
}

provider "time" {}
provider "random" {}
