# terraform-kube

Cluster Kubernetes **k3s** sur 3 VMs Debian ARM dans **VMware Fusion Pro**, entièrement provisionné via **Ansible** + **Terraform/Helm**.

Projet de cours ESGI — showcase IaC + GitOps + Monitoring.

---

## Stack technique

| Couche | Outil | Rôle |
|--------|-------|------|
| VMs | VMware Fusion Pro 13.5+ (vmrest API) | 3 VMs Debian ARM |
| Kubernetes | k3s | Cluster léger 1 master + 2 workers |
| IaC VMs | Ansible (`uri` module) | Clone, configure, démarre les VMs |
| IaC K8s | Terraform + Helm | Déploie toute la stack k8s |
| GitOps | ArgoCD + Argo Rollouts | Déploiement continu + Blue/Green |
| Monitoring | Prometheus + Grafana + Alertmanager | Observabilité complète |
| Ingress | Ingress NGINX | Routage HTTP |
| TLS | cert-manager | Certificats self-signed |
| Demo app | helm/demo-app | Rollout Blue/Green avec AnalysisTemplate |

---

## Prérequis

### Logiciels à installer

```bash
brew install terraform ansible kubectl helm jq
```

### VMware Fusion Pro

- Version **13.5.1** ou supérieure (avec l'API REST `vmrest`)
- Activer l'API REST : **Fusion → Préférences → Enable REST API**
  - Choisir un login/mot de passe pour l'API
  - L'API écoute sur `https://127.0.0.1:8697`

### VM Template Debian ARM

Vous devez avoir une VM Debian ARM **déjà créée** dans Fusion qui servira de template :
- Debian 12 (Bookworm) ARM64
- SSH activé avec un utilisateur `debian` (ou autre) ayant `sudo NOPASSWD`
- **VMware Tools installés** (nécessaire pour que vmrest récupère l'IP)
- Clé SSH publique déposée dans `~/.ssh/authorized_keys` sur la VM

---

## Structure du projet

```
terraform-kube/
├── ansible/
│   ├── inventory/hosts.yml       # Inventaire statique (localhost uniquement)
│   ├── playbooks/
│   │   ├── pre-deploy.yml        # Vérif vmrest + cache Helm
│   │   ├── create-vms.yml        # Clone 3 VMs + attend IPs → vm-outputs.json
│   │   ├── k3s-install.yml       # Installe k3s + configure kubeconfig
│   │   ├── post-deploy.yml       # ClusterIssuer, demo-app, ArgoCD App
│   │   └── teardown.yml          # Désinstalle k3s + supprime VMs + purge states
│   ├── vars/
│   │   └── vms.yml               # ⚠️  Config VMs (à renseigner)
│   └── requirements.yml          # Collections Ansible (ansible.posix, community.general)
├── terraform/
│   └── k8s/                      # Workspace Terraform (Helm releases uniquement)
│       ├── modules/
│       │   ├── cluster/          # Validation connectivité k8s
│       │   ├── platform/         # Ingress NGINX + cert-manager (+ Cilium optionnel)
│       │   ├── monitoring/       # kube-prometheus-stack
│       │   ├── gitops/           # ArgoCD + Argo Rollouts
│       │   └── apps/             # Namespace demo-app
│       └── tfvars/local.tfvars   # Variables Terraform
├── helm/
│   └── demo-app/                 # Chart Helm de l'application de démo (Blue/Green)
├── state/                        # States Terraform (gitignorés)
├── Makefile                      # Point d'entrée principal
└── ARCHITECTURE.md               # Diagrammes Mermaid de l'architecture
```

---

## Configuration initiale (à faire une seule fois)

### 1. Initialiser les dépendances

```bash
make init
```

Cela lance :
- `terraform -chdir=terraform/k8s init`
- `ansible-galaxy collection install -r ansible/requirements.yml`

### 2. Trouver l'ID de votre VM template

Assurez-vous que vmrest est activé dans Fusion, puis :

```bash
make vm-list
```

Vous obtiendrez la liste des VMs avec leurs IDs. Exemple :
```json
[
  {
    "id": "XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX",
    "path": "/Users/you/Virtual Machines/debian-arm-template.vmwarevm/..."
  }
]
```

### 3. Renseigner la configuration

Éditez **`ansible/vars/vms.yml`** :

```yaml
# VMware Fusion REST API
vmrest_url: "https://127.0.0.1:8697"
vmrest_user: "votre-user-vmrest"          # défini dans Fusion → Préférences → REST API
vmrest_password: "votre-password-vmrest"  # idem

# ID de la VM template (récupéré via make vm-list)
template_vm_id: "XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX"

# SSH (doit correspondre à l'utilisateur de votre template)
ssh_user: "debian"
ssh_private_key: "~/.ssh/id_ed25519"

# Cluster
cluster_prefix: "terraform-kube"

# Specs des VMs (ajuster selon votre machine)
master_cpu: 2
master_memory: 4096   # Mo
worker_count: 2
worker_cpu: 2
worker_memory: 2048   # Mo
```

> ⚠️ `ansible/vars/vms.yml` n'est **pas** gitignored par défaut.  
> Ne committez pas vos credentials vmrest. Utilisez un fichier `.vault` ou `ansible-vault` en production.

---

## Déploiement

### Déploiement complet

```bash
make deploy
```

Le flow se déroule en **6 étapes automatiques** :

```
[1/6] ansible-pre        → Vérifie vmrest + prépare le cache Helm local
[2/6] ansible-create-vms → Clone les 3 VMs depuis votre template, configure CPU/RAM,
                           les démarre et attend que chaque VM ait une IP
                           Écrit : vm-ids.json + vm-outputs.json
[3/6] ansible-k3s        → Installe k3s sur le master (--cluster-init),
                           récupère le node-token, installe les agents sur les workers,
                           vérifie que les 3 nœuds sont Ready,
                           fusionne le kubeconfig dans ~/.kube/config
[4/6] tf-k8s-apply       → Déploie via Helm :
                             • Ingress NGINX + cert-manager
                             • kube-prometheus-stack (Grafana + Prometheus + Alertmanager)
                             • ArgoCD + Argo Rollouts
                             • Namespace demo-app
[5/6] tf-k8s-outputs     → Exporte les outputs → terraform-outputs.json
[6/6] ansible-post       → Crée le ClusterIssuer cert-manager,
                           Mode GitOps : crée l'ArgoCD Application (sync depuis Git)
                           Mode local  : déploie la demo-app via helm install
```

### Étapes individuelles

```bash
make ansible-pre         # Étape 1 uniquement
make ansible-create-vms  # Étape 2 : créer les VMs
make ansible-k3s         # Étape 3 : installer k3s
make tf-k8s-apply        # Étape 4 : Helm releases
make tf-k8s-outputs      # Étape 5 : export outputs
make ansible-post        # Étape 6 : post-deploy
```

---

## Vérification du cluster

```bash
# État des nœuds + pods + Helm releases
make status

# Accéder aux UIs (port-forwards en arrière-plan)
make port-forwards
```

| Service | URL locale |
|---------|-----------|
| Grafana | http://localhost:3000 (admin / prom-operator) |
| Prometheus | http://localhost:9090 |
| ArgoCD | http://localhost:8080 |
| Argo Rollouts Dashboard | http://localhost:3100 |

```bash
# Mot de passe ArgoCD admin
make argocd-password
```

---

## Demo app — Blue/Green avec Argo Rollouts

L'application de démo illustre un **déploiement Blue/Green** avec analyse automatique via Prometheus.

### Deux modes de déploiement

| | Mode Local (`git_repo_url = ""`) | Mode GitOps (`git_repo_url` défini) |
|---|---|---|
| **Qui déploie** | Ansible via `helm install` | ArgoCD depuis le repo Git |
| **Déclencher un Blue/Green** | `make rollout-upgrade` | Modifier `helm/demo-app/values.yaml` → commit + push |
| **Sync** | Manuel (Makefile) | Automatique (ArgoCD auto-sync) |
| **Owner du Rollout** | Helm local | ArgoCD |

> **Par défaut, le mode GitOps est activé** (`git_repo_url` est configuré dans `terraform/k8s/tfvars/local.tfvars`).
> Pour revenir en mode local, vider la valeur : `git_repo_url = ""`.

### Mode GitOps (recommandé)

ArgoCD surveille le repo Git et synchronise automatiquement le chart `helm/demo-app/` vers le cluster.

```bash
# 1. Modifier le chart (image, tag, message, replicas...)
vim helm/demo-app/values.yaml

# 2. Commit + push
git add helm/demo-app/values.yaml
git commit -m "feat: update demo-app to v2"
git push

# 3. ArgoCD détecte le changement → sync auto → Argo Rollouts lance le Blue/Green
#    Suivre le déploiement :
make rollout-status

# 4. Promouvoir GREEN → production
make rollout-promote

# 5. Ou annuler
make rollout-abort
```

> `make rollout-upgrade` affiche un rappel du workflow GitOps quand le mode est activé.

### Mode Local (fallback)

```bash
# Déclencher un déploiement GREEN (v2) via Helm local
make rollout-upgrade

# Promouvoir GREEN → production (après analyse OK)
make rollout-promote

# Annuler et revenir sur BLUE
make rollout-abort
```

### Commandes communes (les deux modes)

```bash
make rollout-status    # État du Rollout en temps réel
make rollout-promote   # Promouvoir GREEN → production
make rollout-abort     # Annuler, revenir sur BLUE
make rollout-history   # Historique des révisions
make rollout-undo      # Revenir à la révision précédente
```

### Ajouter les hosts locaux

```bash
make app-hosts
# Copier-coller la commande affichée pour ajouter dans /etc/hosts
```

Accès :
- Production (BLUE) : http://demo-app.local
- Preview (GREEN) : http://preview.demo-app.local

### AnalysisTemplate

Le Rollout valide automatiquement 3 métriques Prometheus avant de promouvoir :
- Taux de succès HTTP ≥ 90%
- Latence P99 ≤ 1s
- Taux d'erreurs 5xx < 5%

---

## Destruction

```bash
make destroy
```

Cela exécute en séquence :
1. Désinstalle k3s sur les workers + le master (SSH)
2. Éteint les 3 VMs via vmrest
3. Supprime les 3 VMs via vmrest (DELETE)
4. Supprime le contexte kubectl
5. Purge les states Terraform et fichiers générés

> Les VMs sont **définitivement supprimées** dans VMware Fusion.

---

## Fichiers générés (gitignorés)

| Fichier | Contenu | Créé par |
|---------|---------|----------|
| `vm-ids.json` | IDs VMware des 3 VMs | `ansible-create-vms` |
| `vm-outputs.json` | IPs + SSH config des VMs | `ansible-create-vms` |
| `terraform-outputs.json` | Outputs des Helm releases | `tf-k8s-outputs` |
| `state/k8s.tfstate` | State Terraform k8s | `tf-k8s-apply` |

---

## Dépannage

### vmrest inaccessible
```
ERREUR: vmrest inaccessible (HTTP 000)
```
→ Ouvrir VMware Fusion Pro → Préférences → activer **Enable REST API**

### IP non récupérée après 5 min
```
ERREUR: timeout pour master — vérifier que la VM est démarrée et que VMware Tools est installé
```
→ VMware Tools (open-vm-tools) doit être installé sur le template :
```bash
# Sur la VM template (avant clonage)
sudo apt install -y open-vm-tools
```

### Nœud k3s non Ready
```bash
kubectl get nodes --context=terraform-kube
# Vérifier les logs sur le master :
ssh debian@<master-ip> "sudo journalctl -u k3s -n 50"
```

### Relancer uniquement k3s
```bash
make ansible-k3s
```

### Relancer uniquement les Helm releases
```bash
make tf-k8s-apply
```
