# Architecture — automatisation-ansible-cluster

## Infra — Point de vue DevOps

> Qui tourne quoi, sur quelle couche, avec quelle techno.

```mermaid
graph TB
    subgraph HOST ["💻 Machine locale (macOS Apple Silicon)"]
        direction LR
        subgraph TOOLS ["Outils"]
            MAKE["Make\norchestration"]
            ANSIBLE["Ansible\nprovisioning VMs + k3s"]
            TF["Terraform\nIaC déclaratif"]
            HELM_CLI["Helm CLI\npackage manager"]
        end
        subgraph REPO ["Repo Git"]
            TF_DIR["terraform/k8s/\nmodules + tfvars"]
            HELM_DIR["helm/\ncharts (demo-app)"]
            ANS_DIR["ansible/\nplaybooks + vars"]
            STATE["state/\nterraform.tfstate"]
        end
    end

    subgraph VMWARE ["🖥️ VMware Fusion Pro (vmrest API)"]
        direction LR
        VM1["VM master\nDebian ARM"]
        VM2["VM worker-1\nDebian ARM"]
        VM3["VM worker-2\nDebian ARM"]
    end

    subgraph K3S ["☸️ Cluster k3s (3 nœuds)"]
        direction TB

        subgraph SYS ["Système cluster"]
            KUBELET["kubelet\nkube-proxy\ncoredns\nlocal-path-provisioner"]
        end

        subgraph PLATFORM ["Namespace: cert-manager · ingress-nginx"]
            CERT["cert-manager\nTLS automatique"]
            NGINX["Ingress NGINX\nreverse proxy HTTP/S"]
        end

        subgraph MONITORING ["Namespace: monitoring"]
            PROM["Prometheus\nmétrique cluster"]
            GRAF["Grafana\ndashboard"]
            ALERT["Alertmanager"]
        end

        subgraph GITOPS ["Namespace: argocd · argo-rollouts"]
            ARGO["ArgoCD\nGitOps controller"]
            ROLLOUT_CTRL["Argo Rollouts\nBlueGreen controller"]
        end

        subgraph APP ["Namespace: demo-app"]
            ROLLOUT["Rollout\n(remplace Deployment)"]
            SVC_A["Service active\nproduction"]
            SVC_P["Service preview\ncanarien"]
            PODS_B["🔵 Pods BLUE v1"]
            PODS_G["🟢 Pods GREEN v2"]
        end
    end

    GIT_REMOTE(["☁️ GitHub\nM4XGO/terraform-kube"])
    USER(["👤 Trafic\nHTTP"])

    %% Provisionnement VMs
    ANSIBLE -->|"vmrest API\nclone + power on"| VMWARE
    ANSIBLE -->|"SSH\nk3s install"| VM1 & VM2 & VM3
    VM1 & VM2 & VM3 -->|"forment"| K3S

    %% Déploiement k8s
    TF -->|"Helm release\ncert-manager"| PLATFORM
    TF -->|"Helm release\nkube-prometheus-stack"| MONITORING
    TF -->|"Helm release\nargocd + argo-rollouts"| GITOPS
    TF -->|"kubernetes_namespace"| APP
    ANSIBLE -->|"post-deploy\nClusterIssuer + ArgoCD App"| CERT & ARGO

    %% GitOps
    GIT_REMOTE -->|"git push\nhelm/demo-app/"| ARGO
    ARGO -->|"sync Rollout"| ROLLOUT
    ROLLOUT_CTRL -->|"pilote\nBlueGreen"| ROLLOUT

    %% App
    ROLLOUT --> SVC_A --> PODS_B
    ROLLOUT --> SVC_P --> PODS_G
    NGINX -->|"demo-app.local"| SVC_A
    NGINX -->|"preview.demo-app.local"| SVC_P
    USER --> NGINX

    %% Monitoring
    PROM -.->|"scrape"| NGINX
    PROM -.->|"scrape"| ROLLOUT
    GRAF -.-> PROM

    %% Cert
    CERT -.->|"TLS"| NGINX
```

---

## Flow de déploiement — Point de vue DevOps

> Quelle techno déclenche quelle brique, dans quel ordre.

```mermaid
flowchart TD
    DEV(["👨‍💻 make deploy"])

    subgraph STEP1 ["① Ansible — pre-deploy"]
        A1["Vérifie vmrest\naccessible"]
        A2["Prépare le cache Helm\nrepo add + update"]
        A1 --> A2
    end

    subgraph STEP2 ["② Ansible — create-vms"]
        V1["Clone 3 VMs\ndepuis template Debian ARM\nvia vmrest API"]
        V2["Configure CPU/RAM\nmaster: 2C/4G\nworkers: 2C/2G"]
        V3["Power on\n+ attend les IPs"]
        V4["Écrit\nvm-ids.json\nvm-outputs.json"]
        V1 --> V2 --> V3 --> V4
    end

    subgraph STEP3 ["③ Ansible — k3s-install"]
        K1["Installe k3s server\nsur le master"]
        K2["Récupère node-token"]
        K3["Installe k3s agent\nsur les 2 workers"]
        K4["Vérifie 3 nœuds Ready\nfusionne kubeconfig"]
        K1 --> K2 --> K3 --> K4
    end

    subgraph STEP4 ["④ Terraform — apply"]
        direction LR
        T0["terraform -chdir=terraform/k8s apply\n-var-file=tfvars/local.tfvars"]
        subgraph TF_MODS ["Modules (ordre depends_on)"]
            TM1["module.cluster\ndata kubernetes_nodes\n(valide connectivité)"]
            TM2["module.platform\nHelm: ingress-nginx\nHelm: cert-manager"]
            TM3["module.monitoring\nHelm: kube-prometheus-stack"]
            TM4["module.gitops\nHelm: argocd\nHelm: argo-rollouts"]
            TM5["module.apps\nkubernetes_namespace demo-app"]
            TM1 --> TM2 --> TM3 & TM4 --> TM5
        end
        T0 --> TF_MODS
        TF_MODS -->|"state/k8s.tfstate"| STATE_FILE[("state/\nk8s.tfstate")]
    end

    subgraph STEP5 ["⑤ Ansible — post-deploy"]
        B1["Attente CRDs\ncert-manager"]
        B2["kubectl apply\nClusterIssuer selfsigned\nClusterIssuer CA"]
        B3["Install kubectl-argo-rollouts\n(brew / curl)"]
        B4["kubectl apply\nServiceMonitor ingress-nginx"]
        B5["kubectl apply\nArgoCD AppProject demo"]
        B6{"git_repo_url\ndéfini ?"}
        B7A["helm install\nhelm/demo-app BLUE v1\n(mode local)"]
        B7B["kubectl apply\nArgoCD Application\n← Git: helm/demo-app/"]
        B1 --> B2 --> B3 --> B4 --> B5 --> B6
        B6 -->|"Non"| B7A
        B6 -->|"Oui ✅ défaut"| B7B
    end

    subgraph STEP6 ["⑥ Blue/Green — Argo Rollouts"]
        C1["Mode GitOps : git push\n→ ArgoCD sync\nMode local : make rollout-upgrade"]
        C2["Argo Rollouts démarre\nGREEN en PREVIEW"]
        C3["AnalysisTemplate\nPrometheus: success rate · P99 · 5xx"]
        C4{"Analyse\nOK ?"}
        C5["make rollout-promote\n🟢 GREEN → production"]
        C6["make rollout-abort\n🔵 BLUE reste actif"]
        C1 --> C2 --> C3 --> C4
        C4 -->|"✅"| C5
        C4 -->|"❌"| C6
    end

    DEV --> STEP1 --> STEP2 --> STEP3 --> STEP4 --> STEP5 --> STEP6

    style STEP1 fill:#f0f9ff,stroke:#0ea5e9
    style STEP2 fill:#e0f2fe,stroke:#0284c7
    style STEP3 fill:#dbeafe,stroke:#2563eb
    style STEP4 fill:#faf5ff,stroke:#a855f7
    style STEP5 fill:#f0fdf4,stroke:#22c55e
    style STEP6 fill:#fff7ed,stroke:#f97316
    style STATE_FILE fill:#fef9c3,stroke:#eab308
```

---

## Infrastructure globale

```mermaid
flowchart TB
    DEV(["💻 Développeur"])
    GIT(["📦 GitHub\nM4XGO/terraform-kube\nhelm/demo-app/"])

    subgraph PROV ["🔧 Provisionnement — localhost"]
        direction LR
        A1["1️⃣ Ansible\npre-deploy + create-vms + k3s"]
        A2["2️⃣ Terraform apply\nHelm releases"]
        A3["3️⃣ Ansible post-deploy\nClusterIssuer + ArgoCD App"]
        A1 --> A2 --> A3
    end

    DEV -->|"make deploy"| PROV

    subgraph VMWARE ["🖥️ VMware Fusion Pro · macOS Apple Silicon"]
        direction LR
        VM_M["VM master\nDebian ARM"]
        VM_W1["VM worker-1\nDebian ARM"]
        VM_W2["VM worker-2\nDebian ARM"]
    end

    A1 -->|"vmrest API + SSH"| VMWARE

    subgraph K8S ["☸️ Cluster k3s — 3 nœuds Debian ARM"]

        subgraph NS_CM ["cert-manager"]
            CM["cert-manager + webhook"]
            CI["ClusterIssuer\nselfsigned · CA"]
            CM --> CI
        end

        subgraph NS_NGINX ["ingress-nginx"]
            NGINX["Ingress NGINX\n:80 / :443"]
            SM["ServiceMonitor"]
        end

        subgraph NS_MON ["monitoring"]
            PROM["Prometheus :9090"]
            GRAF["Grafana :3000"]
            ALRT["Alertmanager :9093"]
            GRAF -.-> PROM
            ALRT -.-> PROM
        end

        subgraph NS_ARGO ["argocd · argo-rollouts"]
            ARGO["ArgoCD :8080"]
            RCTL["Rollouts Controller"]
            RDSH["Rollouts Dashboard :3100"]
        end

        subgraph NS_APP ["demo-app"]
            direction TB
            RO["Rollout — BlueGreen\ndemo-app"]
            SA["Service active"]
            SP["Service preview"]
            BLUE["🔵 Pods BLUE v1\nnginx:1.25-alpine"]
            GREEN["🟢 Pods GREEN v2\nnginx:1.25-alpine"]
            ING_A["Ingress\ndemo-app.local"]
            ING_P["Ingress\npreview.demo-app.local"]
            RO --> SA & SP
            SA --> BLUE
            SP --> GREEN
            ING_A --> SA
            ING_P --> SP
        end

    end

    VMWARE -->|"k3s cluster"| K8S

    USER(["👤 Trafic HTTP"])

    A2 -->|"Helm release"| NS_CM
    A2 -->|"Helm release"| NS_NGINX
    A2 -->|"Helm release"| NS_MON
    A2 -->|"Helm release"| NS_ARGO
    A3 -->|"ClusterIssuer"| CI
    A3 -->|"ArgoCD Application\nmode GitOps ✅"| ARGO

    GIT -->|"git push"| ARGO
    ARGO -->|"sync → Rollout"| RO
    RCTL -->|"pilote"| RO

    USER --> NGINX
    NGINX -->|"demo-app.local"| ING_A
    NGINX -->|"preview.demo-app.local"| ING_P
    CI -.->|"TLS cert"| NGINX

    PROM -->|"scrape"| SM
    SM -->|"métriques"| NGINX
```

---

## Cycle Blue/Green — Argo Rollouts

```mermaid
flowchart TD
    START(["make deploy\nBLUE v1 actif"])

    subgraph STABLE ["🔵 Production BLUE"]
        B_PODS["Pods v1 — active\ndemo-app.local"]
    end

    subgraph TRIGGER ["Déclenchement GREEN"]
        direction LR
        T1["Mode local\nmake rollout-upgrade\nhelm upgrade --values values-v2.yaml"]
        T2["Mode GitOps ✅ défaut\ngit commit + push\nhelm/demo-app/values.yaml\nArgoCD auto-sync"]
    end

    subgraph PREVIEW ["🟢 Preview GREEN"]
        G_PODS["Pods v2 — preview\npreview.demo-app.local"]
        subgraph ANALYSIS ["AnalysisTemplate — Prometheus"]
            M1["✅ HTTP success rate ≥ 90%"]
            M2["✅ Latence P99 ≤ 1s"]
            M3["✅ Taux 5xx < 5%"]
        end
        G_PODS --> ANALYSIS
    end

    DECISION{"Résultat\nanalyse"}

    subgraph PROMOTE ["✅ Promotion"]
        PR["make rollout-promote\nou analyse auto-OK\nGREEN → active\nBLUE scale down"]
    end

    subgraph ABORT ["❌ Rollback"]
        AB["make rollout-abort\nou analyse KO\nGREEN supprimé\nBLUE reste actif"]
    end

    NEW_STABLE(["🟢 Production GREEN\ndemo-app.local = v2"])
    BACK(["🔵 Production BLUE\ndemo-app.local = v1 inchangé"])

    START --> STABLE
    STABLE --> TRIGGER
    T1 --> PREVIEW
    T2 --> PREVIEW
    PREVIEW --> DECISION
    DECISION -->|"OK / make rollout-promote"| PROMOTE
    DECISION -->|"KO / make rollout-abort"| ABORT
    PROMOTE --> NEW_STABLE
    ABORT --> BACK

    style STABLE fill:#1a6cf522,stroke:#1a6cf5
    style PREVIEW fill:#16a34a22,stroke:#16a34a
    style PROMOTE fill:#16a34a33,stroke:#16a34a
    style ABORT fill:#dc262633,stroke:#dc2626
    style NEW_STABLE fill:#16a34a33,stroke:#16a34a
    style BACK fill:#1a6cf533,stroke:#1a6cf5
```
