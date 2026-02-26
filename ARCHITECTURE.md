# Architecture — terraform-kube

## Infra — Point de vue DevOps

> Qui tourne quoi, sur quelle couche, avec quelle techno.

```mermaid
graph TB
    subgraph HOST ["💻 Machine locale (macOS Apple Silicon)"]
        direction LR
        subgraph TOOLS ["Outils"]
            MAKE["Make\norchestration"]
            ANSIBLE["Ansible\nprovisioning OS"]
            TF["Terraform\nIaC déclaratif"]
            HELM_CLI["Helm CLI\npackage manager"]
        end
        subgraph REPO ["Repo Git"]
            TF_DIR["tf/\nmodules + tfvars"]
            HELM_DIR["helm/\ncharts (demo-app)"]
            ANS_DIR["ansible/\nplaybooks"]
            STATE["state/\nterraform.tfstate"]
        end
    end

    subgraph DOCKER ["🐳 Docker Desktop"]
        VM["VM Linux\n(kernel)"]
    end

    subgraph MINIKUBE ["☸️ minikube (cluster Kubernetes)"]
        direction TB

        subgraph SYS ["Système cluster"]
            KUBELET["kubelet\nkube-proxy\ncoredns"]
            CSI["StorageClass\nstandard (hostPath)"]
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

    GIT_REMOTE(["☁️ Git remote\n(GitHub/GitLab)"])
    USER(["👤 Trafic\nHTTP"])

    %% Qui provisionne quoi
    ANSIBLE -->|"minikube start\ninstall dépendances"| DOCKER
    DOCKER -->|"crée"| MINIKUBE
    TF -->|"Helm release\ncert-manager"| PLATFORM
    TF -->|"Helm release\nkube-prometheus-stack"| MONITORING
    TF -->|"Helm release\nargocd + argo-rollouts"| GITOPS
    TF -->|"kubernetes_namespace"| APP
    ANSIBLE -->|"helm install\npost-deploy"| ROLLOUT
    ANSIBLE -->|"kubectl apply\nClusterIssuer"| CERT

    %% GitOps
    GIT_REMOTE -->|"git push\n(mode GitOps)"| ARGO
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
        A1["Détecte l'OS\nmacOS / Linux"]
        A2["brew install\nminikube · kubectl · helm"]
        A3["minikube start\n--driver=docker\n--cpus=4 --memory=6144"]
        A4["helm repo add\ncache isolé tf/.terraform-helm/"]
        A1 --> A2 --> A3 --> A4
    end

    subgraph STEP2 ["② Terraform — apply"]
        direction LR
        T0["terraform -chdir=tf apply\n-var-file=tfvars/local.tfvars"]
        subgraph TF_MODS ["Modules (ordre depends_on)"]
            TM1["module.cluster\ndata kubernetes_nodes\n(valide connectivité)"]
            TM2["module.platform\nHelm: ingress-nginx\nHelm: cert-manager"]
            TM3["module.monitoring\nHelm: kube-prometheus-stack"]
            TM4["module.gitops\nHelm: argocd\nHelm: argo-rollouts"]
            TM5["module.apps\nkubernetes_namespace demo-app"]
            TM1 --> TM2 --> TM3 & TM4 --> TM5
        end
        T0 --> TF_MODS
        TF_MODS -->|"state/terraform.tfstate"| STATE_FILE[("state/\nterraform.tfstate")]
    end

    subgraph STEP3 ["③ Ansible — post-deploy"]
        B1["Attente CRDs\ncert-manager"]
        B2["kubectl apply\nClusterIssuer selfsigned\nClusterIssuer CA"]
        B3["brew install\nkubectl-argo-rollouts"]
        B4["kubectl apply\nServiceMonitor ingress-nginx"]
        B5["kubectl apply\nArgoCD AppProject demo"]
        B6{"git_repo_url\ndéfini ?"}
        B7A["helm install\napps/demo-app BLUE v1\n(mode local)"]
        B7B["kubectl apply\nArgoCD Application\n← Git source"]
        B1 --> B2 --> B3 --> B4 --> B5 --> B6
        B6 -->|"Non"| B7A
        B6 -->|"Oui"| B7B
    end

    subgraph STEP4 ["④ Blue/Green — Argo Rollouts"]
        C1["make rollout-upgrade\nhelm upgrade --values values-v2.yaml\n— OU —\ngit push → ArgoCD sync"]
        C2["Argo Rollouts démarre\nGREEN en PREVIEW"]
        C3["AnalysisTemplate\nPrometheus: success rate · P99 · 5xx"]
        C4{"Analyse\nOK ?"}
        C5["make rollout-promote\n🟢 GREEN → production"]
        C6["make rollout-abort\n🔵 BLUE reste actif"]
        C1 --> C2 --> C3 --> C4
        C4 -->|"✅"| C5
        C4 -->|"❌"| C6
    end

    DEV --> STEP1 --> STEP2 --> STEP3 --> STEP4

    style STEP1 fill:#f0f9ff,stroke:#0ea5e9
    style STEP2 fill:#faf5ff,stroke:#a855f7
    style STEP3 fill:#f0fdf4,stroke:#22c55e
    style STEP4 fill:#fff7ed,stroke:#f97316
    style STATE_FILE fill:#fef9c3,stroke:#eab308
```

---

## Infrastructure globale

```mermaid
flowchart TB
    DEV(["💻 Développeur"])
    GIT(["📦 Git Repo\nhelm/demo-app/"])

    subgraph PROV ["🔧 Provisionnement — localhost"]
        direction LR
        A1["1️⃣ Ansible pre-deploy\nminikube start\nHelm repos cache"]
        A2["2️⃣ Terraform apply\nHelm releases"]
        A3["3️⃣ Ansible post-deploy\nClusterIssuer\nhelm install / ArgoCD App"]
        A1 --> A2 --> A3
    end

    DEV -->|"make deploy"| PROV

    subgraph K8S ["☸️ Cluster minikube — Docker · Apple Silicon"]

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

    USER(["👤 Trafic HTTP"])

    A2 -->|"Helm release"| NS_CM
    A2 -->|"Helm release"| NS_NGINX
    A2 -->|"Helm release"| NS_MON
    A2 -->|"Helm release"| NS_ARGO
    A3 -->|"ClusterIssuer"| CI
    A3 -->|"helm install\nmode local"| RO
    A3 -->|"Application CRD\nmode GitOps"| ARGO

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
        T2["Mode GitOps\ngit commit + push\nvalues.yaml image.tag = v2\nArgoCD auto-sync"]
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
