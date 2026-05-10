# Session 08-11: GitOps with ArgoCD - Hands-On Labs

## Overview
In these labs, you'll set up ArgoCD, deploy applications using Git as the source of truth, and experience the self-healing and automated sync capabilities of GitOps.

**Prerequisites:**
- Working Kubernetes cluster (minikube, Kind, or EKS)
- `kubectl` configured to access your cluster
- `git` installed locally
- A GitHub account and personal access token (for public repos, optional)
- Text editor or IDE for editing YAML files

---

## Lab 1: Install ArgoCD and Access the UI

### Objectives
- Deploy ArgoCD to your Kubernetes cluster
- Retrieve the admin password
- Port-forward to access the ArgoCD UI
- Log in and verify installation

### Steps

1. **Create the argocd namespace:**
   ```bash
   kubectl create namespace argocd
   ```

2. **Install ArgoCD using the official manifest:**
   ```bash
   kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
   ```

3. **Verify all ArgoCD pods are running:**
   ```bash
   kubectl get pods -n argocd
   ```
   You should see: `argocd-server`, `argocd-repo-server`, `argocd-application-controller`, `argocd-redis`.

4. **Get the initial admin password:**
   ```bash
   kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo ""
   ```
   Save this password temporarily.

5. **Port-forward to the ArgoCD API server:**
   ```bash
   kubectl port-forward -n argocd svc/argocd-server 8080:443 &
   ```

6. **Access the UI:**
   - Open your browser to: `http://localhost:8080`
   - Log in with username: `admin` and the password from step 4


### Verification
- You should see the ArgoCD dashboard with "No applications yet"
- The Applications list is empty
- You have admin access to create and manage applications

---

## Lab 2: Create a Git Repository with Kubernetes Manifests

### Objectives
- Set up a Git repository with application manifests
- Create Deployment, Service, and ConfigMap resources
- Prepare manifests for ArgoCD deployment

### Steps

1. **Create a local Git repository (or use an existing GitHub repo):**
   ```bash
   mkdir my-app-repo
   cd my-app-repo
   git init
   git config user.email "you@example.com"
   git config user.name "Your Name"
   ```

2. **Create the manifest directory structure:**
   ```bash
   mkdir -p manifests
   ```

3. **Create a Deployment manifest** (`manifests/deployment.yaml`):
   ```yaml
   apiVersion: apps/v1
   kind: Deployment
   metadata:
     name: nginx-deployment
     labels:
       app: nginx
   spec:
     replicas: 3
     selector:
       matchLabels:
         app: nginx
     template:
       metadata:
         labels:
           app: nginx
       spec:
         containers:
         - name: nginx
           image: nginx:1.21
           ports:
           - containerPort: 80
           resources:
             requests:
               memory: "64Mi"
               cpu: "250m"
             limits:
               memory: "128Mi"
               cpu: "500m"
   ```

4. **Create a Service manifest** (`manifests/service.yaml`):
   ```yaml
   apiVersion: v1
   kind: Service
   metadata:
     name: nginx-service
     labels:
       app: nginx
   spec:
     selector:
       app: nginx
     ports:
     - protocol: TCP
       port: 80
       targetPort: 80
     type: LoadBalancer
   ```

5. **Create a ConfigMap** (`manifests/configmap.yaml`):
   ```yaml
   apiVersion: v1
   kind: ConfigMap
   metadata:
     name: nginx-config
     labels:
       app: nginx
   data:
     app-version: "1.0"
     environment: "production"
   ```
6. **Create a repo on github**

7. **Commit and push to Git:**
   ```bash
   git add manifests/
   git commit -m "Initial application manifests"
   git remote add origin <above-created-git-repo>
   git branch -M main
   git push origin main
   ```

### Verification
- Manifest files are in `manifests/` directory
- Files are valid Kubernetes YAML (no syntax errors)
- Files are committed to Git

---

## Lab 3: Create ArgoCD Application and Deploy

### Objectives
- Create an ArgoCD Application CRD pointing to your Git repo
- Trigger initial sync
- Observe resources being created in your cluster

### Steps

1. **Create the Application CRD** (`application.yaml`):
   ```yaml
   apiVersion: argoproj.io/v1alpha1
   kind: Application
   metadata:
     name: nginx-app
     namespace: argocd
   spec:
     project: default

     source:
       repoURL: https://github.com/<your-username>/my-app-repo
       targetRevision: main
       path: manifests/

     destination:
       server: https://kubernetes.default.svc
       namespace: default

     syncPolicy:
       automated:
         prune: false        # Start with manual sync
         selfHeal: false
   ```

   Update `repoURL` with your actual repository URL. If using a local repo, use `file:///path/to/repo`.

2. **Apply the Application CRD:**
   ```bash
   kubectl apply -f application.yaml
   ```

3. **Verify the Application was created:**
   ```bash
   kubectl get application -n argocd
   ```

4. **Check the application status (initially OutOfSync):**
   ```bash
   kubectl describe application nginx-app -n argocd
   ```

5. **Trigger a manual sync via Argo Console:**
   - Go to Applications → nginx-app
   - Click "SYNC" button
   - Confirm the sync

6. **Watch resources being created:**
   ```bash
   kubectl get all
   kubectl get deployment
   kubectl get service
   kubectl get configmap
   ```

7. **Check the application status (now Synced and Healthy):**
   ```bash
   kubectl get application -n argocd
   argocd app get nginx-app
   ```

### Verification
- Application status shows "Synced" and "Healthy"
- 3 nginx pods are running in the default namespace
- Service and ConfigMap are created
- ArgoCD UI shows the application with green status and resource tree

---

## Lab 4: GitOps in Action - Auto-Sync and Self-Healing

### Objectives
- Enable automated sync and self-heal
- Modify manifests in Git and observe auto-sync
- Make manual cluster changes and observe self-healing revert them
- Understand the GitOps continuous sync loop

### Steps

#### Part A: Enable Automated Sync

1. **Update the Application to enable automation:**
   ```yaml
   syncPolicy:
     automated:
       prune: true         # Delete cluster resources not in Git
       selfHeal: true      # Revert manual changes automatically
   ```


2. **Verify sync policy is enabled:**
   ```bash
   kubectl get application nginx-app -n argocd -o yaml | grep -A 5 syncPolicy
   ```

#### Part B: Modify Git and Observe Auto-Sync

1. **Change replicas in your local Git repo:**
   ```bash
   # Edit manifests/deployment.yaml
   # Change replicas: 3 to replicas: 5
   ```

2. **Commit and push to Git:**
   ```bash
   git add manifests/deployment.yaml
   git commit -m "Scale to 5 replicas"
   git push origin main
   ```

3. **Watch ArgoCD automatically sync (wait 3-5 seconds):**
   ```bash
   watch "kubectl get deployment nginx-deployment -o wide"
   ```
   You should see replicas scale to 5 automatically.

4. **Verify in the UI:**
   - ArgoCD automatically detects the Git change
   - Deployment scales to 5 pods
   - Application remains "Synced"

#### Part C: Self-Healing - Manual Changes Reverted

1. **Make a manual cluster change (scale down):**
   ```bash
   kubectl scale deployment nginx-deployment --replicas=1
   kubectl get deployment
   ```

   You should see 1 replica running (out of sync with Git).

2. **Watch ArgoCD revert the change within seconds:**
   ```bash
   watch "kubectl get deployment nginx-deployment -o wide"
   ```

   ArgoCD detects the drift and scales back to 5 replicas to match Git.

3. **Verify in the UI:**
   - Application shows "Synced" (not "OutOfSync")
   - Manual change was auto-reverted
   - Resource tree shows correct desired state

4. **Try another manual change (update image tag):**
   ```bash
   kubectl set image deployment/nginx-deployment nginx=nginx:latest
   kubectl describe deployment nginx-deployment | grep Image
   ```

5. **Watch self-heal revert it:**
   Within a few seconds, the image should revert back to `nginx:1.21` from Git.

#### Part D: Prune - Removing Resources from Git

1. **Remove the ConfigMap from Git:**
   ```bash
   rm manifests/configmap.yaml
   git add -A
   git commit -m "Remove ConfigMap"
   git push origin main
   ```

2. **Observe the ConfigMap being deleted:**
   ```bash
   watch "kubectl get configmap nginx-config"
   ```

   With `prune: true`, ArgoCD automatically deletes the ConfigMap since it's no longer in Git.

3. **Verify in the UI:**
   - ConfigMap is removed from resource tree
   - Application remains "Synced"

### Verification
- Git changes automatically trigger cluster updates (auto-sync)
- Manual cluster changes are automatically reverted (self-heal)
- Resources removed from Git are auto-deleted from cluster (prune)
- All changes are visible in ArgoCD UI in real-time

---

## Lab 5: ArgoCD with Helm Charts

### Objectives
- Use ArgoCD to deploy a Helm chart
- Override values using ArgoCD Application CRD
- Manage environment-specific configurations

### Steps

1. **Create a Helm chart directory structure:**
   ```bash
   mkdir -p helm-chart/templates
   cd helm-chart
   ```

2. **Create Chart.yaml:**
   ```yaml
   apiVersion: v2
   name: my-nginx
   description: Nginx Helm chart for ArgoCD
   type: application
   version: 1.0.0
   appVersion: "1.0"
   ```

3. **Create values.yaml (base config):**
   ```yaml
   replicaCount: 2

   image:
     repository: nginx
     tag: "1.21"
     pullPolicy: IfNotPresent

   service:
     type: LoadBalancer
     port: 80

   resources:
     requests:
       memory: "64Mi"
       cpu: "250m"
     limits:
       memory: "128Mi"
       cpu: "500m"
   ```

4. **Create values-prod.yaml (production overrides):**
   ```yaml
   replicaCount: 5

   image:
     tag: "latest"

   resources:
     requests:
       memory: "256Mi"
       cpu: "500m"
     limits:
       memory: "512Mi"
       cpu: "1000m"
   ```

5. **Create a simple Deployment template** (`templates/deployment.yaml`):
   ```yaml
   apiVersion: apps/v1
   kind: Deployment
   metadata:
     name: {{ .Chart.Name }}
     labels:
       app: {{ .Chart.Name }}
   spec:
     replicas: {{ .Values.replicaCount }}
     selector:
       matchLabels:
         app: {{ .Chart.Name }}
     template:
       metadata:
         labels:
           app: {{ .Chart.Name }}
       spec:
         containers:
         - name: {{ .Chart.Name }}
           image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
           imagePullPolicy: {{ .Values.image.pullPolicy }}
           ports:
           - containerPort: 80
           resources:
             requests:
               memory: "{{ .Values.resources.requests.memory }}"
               cpu: "{{ .Values.resources.requests.cpu }}"
             limits:
               memory: "{{ .Values.resources.limits.memory }}"
               cpu: "{{ .Values.resources.limits.cpu }}"
   ```

6. **Create a Service template** (`templates/service.yaml`):
   ```yaml
   apiVersion: v1
   kind: Service
   metadata:
     name: {{ .Chart.Name }}
   spec:
     type: {{ .Values.service.type }}
     selector:
       app: {{ .Chart.Name }}
     ports:
     - protocol: TCP
       port: {{ .Values.service.port }}
       targetPort: 80
   ```

7. **Commit to Git:**
   ```bash
   git add helm-chart/
   git commit -m "Add Helm chart"
   git push origin main
   ```

8. **Create an ArgoCD Application for Helm deployment** (`helm-application.yaml`):
   ```yaml
   apiVersion: argoproj.io/v1alpha1
   kind: Application
   metadata:
     name: nginx-helm-app
     namespace: argocd
   spec:
     project: default

     source:
       repoURL: https://github.com/<your-username>/my-app-repo
       targetRevision: main
       path: helm-chart/
       helm:
         valueFiles:
         - values-prod.yaml  # Use production values
         parameters:
         - name: replicaCount
           value: "3"        # Override replicas to 3

     destination:
       server: https://kubernetes.default.svc
       namespace: helm-ns

     syncPolicy:
       automated:
         prune: true
         selfHeal: true
   ```

9. **Create namespace and apply the Application:**
   ```bash
   kubectl create namespace helm-ns
   kubectl apply -f helm-application.yaml
   ```

10. **Watch the Helm chart deployment:**
    ```bash
    kubectl get pods -n helm-ns
    kubectl get all -n helm-ns
    ```

11. **Verify Helm values were applied:**
    ```bash
    # Check replicas (should be 3 from parameters override)
    kubectl get deployment -n helm-ns -o yaml | grep replicas

    # Check image (should be nginx:latest from values-prod.yaml)
    kubectl get deployment -n helm-ns -o yaml | grep image
    ```

12. **Update Helm values in Git and observe auto-sync:**
    ```bash
    # Edit helm-chart/values-prod.yaml
    # Change replicaCount: 5
    git add helm-chart/values-prod.yaml
    git commit -m "Scale prod to 5 replicas"
    git push
    ```

    Watch replicas scale to 5 (with parameter override still taking 3... clarify if param wins or value wins).

### Verification
- Helm chart deploys successfully
- ArgoCD applies values files and parameters
- replicas match the configured value
- Image tags are correct from values files
- Git changes to values files trigger re-renders and auto-sync

---