.PHONY: help init validate plan deploy destroy status port-forwards \
        ansible-pre ansible-create-vms ansible-k3s ansible-post ansible-teardown \
        tf-k8s-apply tf-k8s-outputs tf-k8s-plan tf-state-purge \
        argocd-password vm-list clean \
        rollout-status rollout-upgrade rollout-promote rollout-abort \
        rollout-retry rollout-undo rollout-history app-url app-hosts

CLUSTER_NAME ?= terraform-kube

# Workspace Terraform (k8s uniquement — VMs gérées par Ansible)
TF_K8S = terraform -chdir=terraform/k8s
TF_K8S_VARS ?= tfvars/local.tfvars

ANSIBLE = ansible-playbook -i ansible/inventory/hosts.yml

# ─── Aide ─────────────────────────────────────────────────────────────────────
help:
	@echo ""
	@echo "  terraform-kube — Cluster k3s sur VMware Fusion (3 VMs Debian ARM)"
	@echo "  Provisionnement : Ansible (VMs + k3s) + Terraform/k8s (Helm)"
	@echo ""
	@echo "  Structure :"
	@echo "    ansible/          Playbooks : create-vms, k3s-install, post-deploy, teardown"
	@echo "    ansible/vars/     vms.yml   : config VMs (vmrest, template_id, specs)"
	@echo "    terraform/k8s/    Helm releases (platform, monitoring, gitops, apps)"
	@echo "    helm/             Charts Helm (demo-app)"
	@echo "    state/            States Terraform (gitignored)"
	@echo ""
	@echo "  Setup initial (one-time) :"
	@echo "    make init         Initialiser Terraform k8s + collections Ansible"
	@echo "    make vm-list      Lister les VMs VMware Fusion (trouver template_vm_id)"
	@echo "    → renseigner ansible/vars/vms.yml (vmrest_user/password, template_vm_id)"
	@echo ""
	@echo "  Déploiement :"
	@echo "    make deploy       Flow complet (6 étapes) :"
	@echo "                        1. ansible-pre        (vmrest check + Helm cache)"
	@echo "                        2. ansible-create-vms (clone + power on + IPs)"
	@echo "                        3. ansible-k3s        (install k3s + kubeconfig)"
	@echo "                        4. tf-k8s-apply       (Helm releases)"
	@echo "                        5. tf-k8s-outputs     (outputs → terraform-outputs.json)"
	@echo "                        6. ansible-post       (ClusterIssuer, demo-app, ArgoCD)"
	@echo "    make destroy      Teardown complet (k3s + VMs + state)"
	@echo ""
	@echo "  Utilitaires :"
	@echo "    make status          État du cluster (nœuds + pods + Helm)"
	@echo "    make port-forwards   Port-forwards Grafana/Prometheus/ArgoCD/Rollouts"
	@echo "    make argocd-password Mot de passe admin ArgoCD"
	@echo "    make clean           Supprimer les fichiers temporaires Terraform"
	@echo ""
	@echo "  Blue/Green — Argo Rollouts :"
	@echo "    make rollout-upgrade  Déployer la version GREEN (v2)"
	@echo "    make rollout-promote  Promouvoir GREEN en production"
	@echo "    make rollout-abort    Revenir sur BLUE"
	@echo "    make rollout-status   Surveiller le Rollout en temps réel"
	@echo ""

# ─── Initialisation ───────────────────────────────────────────────────────────
init: _check-deps
	@echo ">>> [1/3] Initialisation Terraform k8s..."
	$(TF_K8S) init -upgrade
	@echo ">>> [2/3] Installation des collections Ansible..."
	ansible-galaxy collection install -r ansible/requirements.yml
	@echo ">>> [3/3] Lancement de vmrest en arrière-plan..."
	@osascript -e 'tell application "Terminal" to do script "vmrest -C"' 2>/dev/null \
		|| open -a Terminal "vmrest" 2>/dev/null \
		|| echo "  ⚠ Impossible d'ouvrir un terminal. Lancez manuellement : vmrest -C"
	@echo "  vmrest lancé dans un nouveau terminal."
	@echo ""
	@echo ">>> Init terminée. Étapes suivantes :"
	@echo "    make vm-list → récupérer l'ID du template"
	@echo "    → renseigner ansible/vars/vms.yml"
	@echo "    make deploy"

# ─── Validation ───────────────────────────────────────────────────────────────
validate:
	$(TF_K8S) validate

# ─── Plan ─────────────────────────────────────────────────────────────────────
tf-k8s-plan: _check-deps _check-cluster
	$(TF_K8S) plan $(if $(wildcard terraform/k8s/$(TF_K8S_VARS)),-var-file=$(TF_K8S_VARS),)

plan: tf-k8s-plan

# ─── Déploiement complet ──────────────────────────────────────────────────────
deploy: _check-deps ansible-pre ansible-create-vms ansible-k3s tf-k8s-apply tf-k8s-outputs ansible-post
	@echo ""
	@echo "════════════════════════════════════════════════════════════"
	@echo " Déploiement terminé !"
	@echo " ► make port-forwards  pour accéder aux UIs"
	@echo " ► make status         pour voir l'état du cluster"
	@echo " ► make argocd-password pour le mot de passe ArgoCD"
	@echo "════════════════════════════════════════════════════════════"

# ── Étape 1 : vérifier vmrest + préparer Helm cache
ansible-pre: _check-deps
	@echo ">>> [1/6] Ansible pre-deploy : vérification + Helm cache..."
	$(ANSIBLE) ansible/playbooks/pre-deploy.yml

# ── Étape 2 : créer les VMs + attendre les IPs → vm-outputs.json
ansible-create-vms: _check-deps
	@echo ">>> [2/6] Ansible create-vms : clonage + démarrage + IPs..."
	$(ANSIBLE) ansible/playbooks/create-vms.yml

# ── Étape 3 : installer k3s + kubeconfig
ansible-k3s:
	@echo ">>> [3/6] Ansible k3s : installation du cluster k3s..."
	$(ANSIBLE) ansible/playbooks/k3s-install.yml

# ── Étape 4 : déployer les Helm releases
tf-k8s-apply: _check-deps _check-cluster
	@echo ">>> [4/6] Terraform k8s : déploiement des Helm releases..."
	$(TF_K8S) apply -auto-approve $(if $(wildcard terraform/k8s/$(TF_K8S_VARS)),-var-file=$(TF_K8S_VARS),)

# ── Étape 5 : exporter les outputs k8s
tf-k8s-outputs:
	@echo ">>> [5/6] Export outputs Terraform k8s → terraform-outputs.json..."
	$(TF_K8S) output -json > terraform-outputs.json

# ── Étape 6 : ressources post-deploy (ClusterIssuer, demo-app, ArgoCD App)
ansible-post:
	@echo ">>> [6/6] Ansible post-deploy : ClusterIssuer, demo-app, ArgoCD..."
	$(ANSIBLE) ansible/playbooks/post-deploy.yml

# ─── Destruction ──────────────────────────────────────────────────────────────
destroy: _check-deps ansible-teardown
	@echo ""
	@echo "════════════════════════════════════════════════════════════"
	@echo " Cluster détruit, VMs supprimées, states purgés."
	@echo " Prochain déploiement : make deploy"
	@echo "════════════════════════════════════════════════════════════"

ansible-teardown:
	@echo ">>> Teardown : k3s + VMs + states..."
	$(ANSIBLE) ansible/playbooks/teardown.yml

tf-state-purge:
	@rm -f state/k8s.tfstate state/k8s.tfstate.backup \
	       vm-ids.json vm-outputs.json terraform-outputs.json
	@echo "States purgés."

# ─── VMware Fusion ────────────────────────────────────────────────────────────
vm-list:
	@echo ">>> Liste des VMs VMware Fusion (via vmrest) :"
	@VMREST_URL=$$(grep 'vmrest_url:' ansible/vars/vms.yml | awk '{print $$2}' | tr -d '"') && \
	VMREST_USER=$$(grep 'vmrest_user:' ansible/vars/vms.yml | awk '{print $$2}' | tr -d '"') && \
	VMREST_PASS=$$(grep 'vmrest_password:' ansible/vars/vms.yml | awk '{print $$2}' | tr -d '"') && \
	curl -sk -u "$$VMREST_USER:$$VMREST_PASS" "$$VMREST_URL/api/vms" | jq . \
		|| echo "(vmrest non accessible — activer dans Fusion → Préférences → Enable REST API)"
	@echo ""
	@echo "Renseigner template_vm_id dans : ansible/vars/vms.yml"

# ─── Utilitaires cluster ──────────────────────────────────────────────────────
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
	@echo "=== Running ==="
	@kubectl get pods -A --context=$(CLUSTER_NAME) 2>/dev/null | grep -c Running | xargs -I{} echo "{} pods en Running"

port-forwards: _check-k8s-deps _check-cluster
	@echo ">>> Port-forwards en arrière-plan..."
	@kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80 \
		--context=$(CLUSTER_NAME) > /dev/null 2>&1 & echo "  Grafana      : http://localhost:3000"
	@kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090 \
		--context=$(CLUSTER_NAME) > /dev/null 2>&1 & echo "  Prometheus   : http://localhost:9090"
	@kubectl port-forward -n argocd svc/argocd-server 8080:80 \
		--context=$(CLUSTER_NAME) > /dev/null 2>&1 & echo "  ArgoCD       : http://localhost:8080"
	@kubectl port-forward -n argo-rollouts svc/argo-rollouts-dashboard 3100:3100 \
		--context=$(CLUSTER_NAME) > /dev/null 2>&1 & echo "  Rollouts     : http://localhost:3100"
	@echo "Pour arrêter : pkill -f 'kubectl port-forward'"

argocd-password: _check-k8s-deps
	@kubectl -n argocd get secret argocd-initial-admin-secret \
		--context=$(CLUSTER_NAME) \
		-o jsonpath="{.data.password}" | base64 -d && echo

# ─── Blue/Green — Argo Rollouts ───────────────────────────────────────────────
APP_NS ?= demo-app

rollout-status: _check-k8s-deps
	kubectl argo rollouts get rollout demo-app -n $(APP_NS) --context=$(CLUSTER_NAME) --watch

rollout-upgrade: _check-k8s-deps
	@if grep -q 'git_repo_url.*=.*"https' terraform/k8s/tfvars/local.tfvars 2>/dev/null; then \
		echo ""; \
		echo "════════════════════════════════════════════════════════════"; \
		echo " Mode GitOps activé — ArgoCD gère le déploiement."; \
		echo ""; \
		echo " Pour déclencher un blue/green :"; \
		echo "   1. Modifier helm/demo-app/values.yaml (image, tag, message...)"; \
		echo "   2. git add + git commit + git push"; \
		echo "   3. ArgoCD sync automatique → Argo Rollouts blue/green"; \
		echo "   4. make rollout-promote   pour valider"; \
		echo "════════════════════════════════════════════════════════════"; \
	else \
		echo ">>> Déploiement de la version GREEN (v2)..."; \
		helm upgrade demo-app helm/demo-app \
			--namespace $(APP_NS) \
			--kube-context $(CLUSTER_NAME) \
			--values helm/demo-app/values.yaml \
			--values helm/demo-app/values-v2.yaml \
			--wait; \
		echo ">>> GREEN en PREVIEW — make rollout-status | make rollout-promote"; \
	fi

rollout-promote: _check-k8s-deps
	kubectl argo rollouts promote demo-app -n $(APP_NS) --context=$(CLUSTER_NAME)

rollout-abort: _check-k8s-deps
	kubectl argo rollouts abort demo-app -n $(APP_NS) --context=$(CLUSTER_NAME)

rollout-retry: _check-k8s-deps
	kubectl argo rollouts retry rollout demo-app -n $(APP_NS) --context=$(CLUSTER_NAME)

rollout-undo: _check-k8s-deps
	kubectl argo rollouts undo demo-app -n $(APP_NS) --context=$(CLUSTER_NAME)

rollout-history: _check-k8s-deps
	kubectl argo rollouts history rollout demo-app -n $(APP_NS) --context=$(CLUSTER_NAME)

app-url:
	@echo "  Production : http://demo-app.local"
	@echo "  Preview    : http://preview.demo-app.local"

app-hosts: _check-k8s-deps
	@MASTER_IP=$$(jq -r '.master_ip.value // "127.0.0.1"' vm-outputs.json 2>/dev/null || echo "127.0.0.1") && \
	echo "Ajoutez dans /etc/hosts :" && \
	echo "$$MASTER_IP  demo-app.local preview.demo-app.local" && \
	echo "" && \
	echo "Commande :" && \
	echo "echo \"$$MASTER_IP  demo-app.local preview.demo-app.local\" | sudo tee -a /etc/hosts"

clean:
	rm -f terraform-outputs.json vm-outputs.json vm-ids.json
	rm -rf terraform/k8s/.terraform terraform/k8s/.terraform.lock.hcl
	rm -rf terraform/k8s/.terraform-helm

# ─── Vérifications ────────────────────────────────────────────────────────────
_check-cluster:
	@kubectl config get-contexts $(CLUSTER_NAME) >/dev/null 2>&1 \
		|| { echo "ERREUR: contexte kubectl '$(CLUSTER_NAME)' introuvable."; \
		     echo "       Lancez d'abord : make ansible-k3s"; exit 1; }

_check-deps:
	@command -v terraform        >/dev/null 2>&1 || { echo "ERREUR: terraform non trouvé.      brew install terraform"; exit 1; }
	@command -v ansible-playbook >/dev/null 2>&1 || { echo "ERREUR: ansible non trouvé.        brew install ansible"; exit 1; }
	@command -v jq               >/dev/null 2>&1 || { echo "ERREUR: jq non trouvé.             brew install jq"; exit 1; }

_check-k8s-deps:
	@command -v kubectl >/dev/null 2>&1 || { echo "ERREUR: kubectl non trouvé. Lancez : make ansible-pre"; exit 1; }
	@command -v helm    >/dev/null 2>&1 || { echo "ERREUR: helm non trouvé.    Lancez : make ansible-pre"; exit 1; }
