.PHONY: help init validate plan deploy destroy status port-forwards \
        ansible-pre ansible-post ansible-teardown tf-state-purge argocd-password clean \
        rollout-status rollout-upgrade rollout-promote rollout-abort \
        rollout-retry rollout-history app-url app-hosts

CLUSTER_NAME ?= terraform-kube
# tfvars/local.tfvars est le fichier de variables par défaut du repo.
# Surcharger via : make deploy TF_VARS=terraform.tfvars
TF_VARS     ?= tfvars/local.tfvars

# ─── Aide ─────────────────────────────────────────────────────────────────────
help:
	@echo ""
	@echo "  terraform-kube — Cluster Kubernetes local"
	@echo "  Provisionnement : Ansible (minikube) + Terraform (Helm/K8s)"
	@echo ""
	@echo "  Commandes principales :"
	@echo "    make init          Initialiser Terraform + collections Ansible"
	@echo "    make validate      Valider la configuration Terraform"
	@echo "    make plan          Plan Terraform (nécessite un cluster actif)"
	@echo "    make deploy        Déploiement complet :"
	@echo "                         1. Ansible pre-deploy  (minikube start)"
	@echo "                         2. Terraform apply     (Helm releases)"
	@echo "                         3. Ansible post-deploy (ClusterIssuer, etc.)"
	@echo "    make destroy       Destruction rapide :"
	@echo "                         1. Ansible teardown    (minikube delete)"
	@echo "                         2. Purge du state Terraform"
	@echo ""
	@echo "  Commandes utilitaires :"
	@echo "    make status          État du cluster et des pods"
	@echo "    make port-forwards   Lance tous les port-forwards en arrière-plan"
	@echo "    make argocd-password Affiche le mot de passe admin ArgoCD"
	@echo "    make clean           Supprime les fichiers temporaires Terraform"
	@echo ""
	@echo "  Blue/Green — Argo Rollouts :"
	@echo "    make rollout-status  Surveiller le Rollout en temps réel"
	@echo "    make rollout-upgrade Déclencher le déploiement de la version GREEN (v2)"
	@echo "    make rollout-promote Promouvoir la version GREEN en production"
	@echo "    make rollout-abort   Abandonner et revenir sur la version BLUE"
	@echo "    make rollout-retry   Relancer un rollout en échec"
	@echo "    make rollout-history Historique des révisions"
	@echo "    make app-url         Afficher les URLs de l'application"
	@echo "    make app-hosts       Afficher la ligne à ajouter dans /etc/hosts"
	@echo ""
	@echo "  Variables :"
	@echo "    CLUSTER_NAME     Nom du cluster (défaut: $(CLUSTER_NAME))"
	@echo "    TF_VARS          Fichier tfvars  (défaut: $(TF_VARS))"
	@echo ""

# ─── Initialisation ───────────────────────────────────────────────────────────
init:
	@echo ">>> Initialisation Terraform..."
	terraform init -upgrade
	@echo ">>> Installation des collections Ansible..."
	ansible-galaxy collection install -r ansible/requirements.yml
	@test -f $(TF_VARS) && echo ">>> Fichier de variables : $(TF_VARS)" || echo ">>> ATTENTION : $(TF_VARS) non trouvé. Créez-le depuis tfvars/local.tfvars"
	@echo ""
	@echo ">>> Initialisation terminée. Lancez : make deploy"

# ─── Validation ───────────────────────────────────────────────────────────────
validate:
	terraform validate
	terraform fmt -check -recursive

# ─── Plan ─────────────────────────────────────────────────────────────────────
# PRÉREQUIS : le cluster doit être actif (make ansible-pre d'abord).
# Les providers kubernetes/helm se connectent pendant le plan.
plan: _check-deps _check-k8s-deps _check-cluster
	terraform plan $(if $(wildcard $(TF_VARS)),-var-file=$(TF_VARS),)

# ─── Déploiement complet ──────────────────────────────────────────────────────
deploy: _check-deps ansible-pre tf-apply tf-outputs ansible-post
	@echo ""
	@echo "════════════════════════════════════════════════════════════"
	@echo " Déploiement terminé !"
	@echo " ► make port-forwards  pour accéder aux UIs"
	@echo " ► make status         pour voir l'état du cluster"
	@echo " ► make argocd-password pour le mot de passe ArgoCD"
	@echo "════════════════════════════════════════════════════════════"

# Étape 1 — Ansible : démarrer minikube
ansible-pre: _check-deps
	@echo ">>> [1/3] Ansible pre-deploy : démarrage du cluster minikube..."
	ansible-playbook -i ansible/inventory.yml ansible/playbooks/pre-deploy.yml

# Étape 2a — Terraform apply
tf-apply: _check-deps
	@echo ">>> [2/3] Terraform apply : déploiement des Helm releases..."
	terraform apply -auto-approve $(if $(wildcard $(TF_VARS)),-var-file=$(TF_VARS),)

# Étape 2b — Export des outputs pour Ansible
tf-outputs:
	@echo ">>> Export des outputs Terraform pour Ansible..."
	terraform output -json > terraform-outputs.json

# Étape 3 — Ansible : ressources post-deploy (ClusterIssuer, etc.)
ansible-post:
	@echo ">>> [3/3] Ansible post-deploy : ClusterIssuer cert-manager..."
	ansible-playbook -i ansible/inventory.yml ansible/playbooks/post-deploy.yml

# ─── Destruction rapide ───────────────────────────────────────────────────────
# minikube delete supprime tout le cluster (et donc toutes les ressources Helm/K8s).
# On purge ensuite le state Terraform pour que le prochain `make deploy` reparte propre.
destroy: _check-deps ansible-teardown tf-state-purge
	@echo ""
	@echo "════════════════════════════════════════════════════════════"
	@echo " Cluster supprimé — state Terraform purgé."
	@echo " Prochain déploiement : make deploy"
	@echo "════════════════════════════════════════════════════════════"

ansible-teardown:
	@echo ">>> [1/2] Ansible teardown : suppression du cluster minikube..."
	ansible-playbook -i ansible/inventory.yml ansible/playbooks/teardown.yml

tf-state-purge:
	@echo ">>> [2/2] Purge du state Terraform..."
	@rm -f terraform.tfstate terraform.tfstate.backup terraform-outputs.json
	@echo ">>> State purgé."

# ─── Utilitaires ──────────────────────────────────────────────────────────────
status: _check-k8s-deps
	@echo "=== Nœuds ==="
	@kubectl get nodes --context=$(CLUSTER_NAME) -o wide 2>/dev/null || echo "(cluster non accessible)"
	@echo ""
	@echo "=== Helm releases ==="
	@helm list -A --kube-context=$(CLUSTER_NAME) 2>/dev/null || echo "(helm non disponible)"
	@echo ""
	@echo "=== Pods (hors Running/Completed) ==="
	@kubectl get pods -A --context=$(CLUSTER_NAME) 2>/dev/null | grep -v "Running\|Completed\|NAMESPACE" || echo "(tous les pods sont sains)"
	@echo ""
	@echo "=== Pods Running ==="
	@kubectl get pods -A --context=$(CLUSTER_NAME) 2>/dev/null | grep Running | wc -l | xargs -I{} echo "{} pods en Running"

port-forwards: _check-k8s-deps _check-cluster
	@echo ">>> Lancement des port-forwards en arrière-plan..."
	@echo "  Grafana      : http://localhost:3000"
	@kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80 \
		--context=$(CLUSTER_NAME) > /dev/null 2>&1 & echo "  PID Grafana : $$!"
	@echo "  Prometheus   : http://localhost:9090"
	@kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090 \
		--context=$(CLUSTER_NAME) > /dev/null 2>&1 & echo "  PID Prometheus : $$!"
	@echo "  ArgoCD       : http://localhost:8080  (admin / make argocd-password)"
	@kubectl port-forward -n argocd svc/argocd-server 8080:80 \
		--context=$(CLUSTER_NAME) > /dev/null 2>&1 & echo "  PID ArgoCD : $$!"
	@echo "  Rollouts     : http://localhost:3100"
	@kubectl port-forward -n argo-rollouts svc/argo-rollouts-dashboard 3100:3100 \
		--context=$(CLUSTER_NAME) > /dev/null 2>&1 & echo "  PID Rollouts : $$!"
	@echo ""
	@echo "Pour arrêter les port-forwards : pkill -f 'kubectl port-forward'"

argocd-password: _check-k8s-deps
	@kubectl -n argocd get secret argocd-initial-admin-secret \
		--context=$(CLUSTER_NAME) \
		-o jsonpath="{.data.password}" | base64 -d && echo

# ─── Blue/Green — Argo Rollouts ───────────────────────────────────────────────
APP_NS ?= demo-app

rollout-status: _check-k8s-deps
	kubectl argo rollouts get rollout demo-app -n $(APP_NS) --context=$(CLUSTER_NAME) --watch

rollout-upgrade: _check-k8s-deps
	@echo ">>> Déploiement de la version GREEN (v2.0.0)..."
	helm upgrade demo-app apps/demo-app \
		--namespace $(APP_NS) \
		--kube-context $(CLUSTER_NAME) \
		--values apps/demo-app/values.yaml \
		--values apps/demo-app/values-v2.yaml \
		--wait
	@echo ">>> GREEN en PREVIEW. Tester: http://preview.demo-app.local"
	@echo "    Surveiller : make rollout-status"
	@echo "    Promouvoir : make rollout-promote  |  Annuler : make rollout-abort"

rollout-promote: _check-k8s-deps
	@echo ">>> Promotion GREEN → production..."
	kubectl argo rollouts promote demo-app -n $(APP_NS) --context=$(CLUSTER_NAME)

rollout-abort: _check-k8s-deps
	@echo ">>> Abandon — retour sur BLUE..."
	kubectl argo rollouts abort demo-app -n $(APP_NS) --context=$(CLUSTER_NAME)

rollout-retry: _check-k8s-deps
	kubectl argo rollouts retry rollout demo-app -n $(APP_NS) --context=$(CLUSTER_NAME)

rollout-undo: _check-k8s-deps
	kubectl argo rollouts undo demo-app -n $(APP_NS) --context=$(CLUSTER_NAME)

rollout-history: _check-k8s-deps
	kubectl argo rollouts history rollout demo-app -n $(APP_NS) --context=$(CLUSTER_NAME)

app-url:
	@echo ""
	@echo "  Production : http://demo-app.local"
	@echo "  Preview    : http://preview.demo-app.local"
	@echo ""
	@echo "  Port-forward direct :"
	@echo "  kubectl port-forward -n $(APP_NS) svc/demo-app-active 8888:80"
	@echo "  kubectl port-forward -n $(APP_NS) svc/demo-app-preview 8889:80"

app-hosts: _check-k8s-deps
	@MINIKUBE_IP=$$(minikube ip --profile $(CLUSTER_NAME) 2>/dev/null || echo "127.0.0.1") && \
	echo "Ajoutez dans /etc/hosts :" && \
	echo "$$MINIKUBE_IP  demo-app.local preview.demo-app.local" && \
	echo "" && \
	echo "Commande sudo :" && \
	echo "echo \"$$MINIKUBE_IP  demo-app.local preview.demo-app.local\" | sudo tee -a /etc/hosts"

clean:
	rm -f terraform-outputs.json
	rm -rf .terraform
	rm -f .terraform.lock.hcl

# ─── Vérification du cluster ──────────────────────────────────────────────────
_check-cluster:
	@kubectl config get-contexts $(CLUSTER_NAME) >/dev/null 2>&1 \
		|| { echo "ERREUR: contexte kubectl '$(CLUSTER_NAME)' introuvable."; \
		     echo "       Lancez d'abord : make ansible-pre"; exit 1; }

# ─── Vérification des dépendances ─────────────────────────────────────────────
# _check-deps : vérifie uniquement les prérequis nécessaires AVANT Ansible.
#               minikube / kubectl / helm sont installés par ansible-pre.
# _check-k8s-deps : vérifie les outils k8s (post ansible-pre).
_check-deps:
	@command -v terraform        >/dev/null 2>&1 || { echo "ERREUR: terraform non trouvé.      brew install terraform"; exit 1; }
	@command -v ansible-playbook >/dev/null 2>&1 || { echo "ERREUR: ansible non trouvé.        brew install ansible"; exit 1; }

_check-k8s-deps:
	@command -v minikube >/dev/null 2>&1 || { echo "ERREUR: minikube non trouvé. Lancez : make ansible-pre"; exit 1; }
	@command -v kubectl  >/dev/null 2>&1 || { echo "ERREUR: kubectl non trouvé.  Lancez : make ansible-pre"; exit 1; }
	@command -v helm     >/dev/null 2>&1 || { echo "ERREUR: helm non trouvé.     Lancez : make ansible-pre"; exit 1; }
