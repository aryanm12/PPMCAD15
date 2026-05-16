# Session 08-12: Kubernetes Gateway API - Hands-On Lab 1 (NGINX Gateway Fabric)

## Overview
In Session 6 you used the `Ingress` resource (with annotations) and AWS Load Balancer Controller. Gateway API is the modern, role-oriented successor: a portable, expressive, and extensible Kubernetes API for L4/L7 routing.

In this Hans-On Lab 1 you will install the Gateway API CRDs, deploy NGINX Gateway Fabric as the controller, and progressively build up GatewayClass, Gateway, and HTTPRoute configurations including path/host/header routing, weighted traffic splitting, TLS termination, and cross-namespace routing with ReferenceGrant.

**Targeted Gateway API version:** `v1.5.x` (standard channel, released Feb 2026 - latest stable at time of writing). All core resources used here (`GatewayClass`, `Gateway`, `HTTPRoute`) are GA at `gateway.networking.k8s.io/v1`. `ReferenceGrant` is at `gateway.networking.k8s.io/v1beta1`. Always check https://github.com/kubernetes-sigs/gateway-api/releases for the newest standard-channel release before running these labs in your environment.

**Prerequisites:**
- Working Kubernetes cluster (minikube, Kind, or EKS - all work)
- `kubectl` v1.27+ configured against the cluster
- `helm` 3+ installed
- `curl` available locally

> All YAML used in this lab is shown inline. When a step says *"Save the following as `foo.yaml`"*, copy the block into a file with that name in your working directory, then run the `kubectl apply -f foo.yaml` that follows.

---

## Lab 1: Install Gateway API CRDs and NGINX Gateway Fabric

### Objectives
- Install the Gateway API CRDs (standard channel)
- Install NGINX Gateway Fabric via Helm as the Gateway controller
- Verify the controller is running and watching for Gateway resources

### Steps

1. **Install the Gateway API CRDs (standard channel, v1.5.0):**
   ```bash
   kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.0/standard-install.yaml
   ```
   This installs the CRDs for `GatewayClass`, `Gateway`, `HTTPRoute`, `GRPCRoute`, `TLSRoute`, and `ReferenceGrant`.

2. **Verify the CRDs are installed:**
   ```bash
   kubectl get crd | grep gateway.networking.k8s.io
   ```
   You should see entries like `gatewayclasses.gateway.networking.k8s.io`, `gateways.gateway.networking.k8s.io`, `httproutes.gateway.networking.k8s.io`, `referencegrants.gateway.networking.k8s.io`.

3. **Install NGINX Gateway Fabric (NGF) in the `nginx-gateway` namespace.** The chart is published as a public OCI image on GHCR - no `helm registry login` is required for the public registry.
   ```bash
   helm install ngf oci://ghcr.io/nginx/charts/nginx-gateway-fabric \
     --create-namespace \
     -n nginx-gateway \
     --version 2.6.0
   ```

   > **Architecture note (NGF v2.x).** Starting with the v2.x line, NGINX Gateway Fabric uses a **split control plane / data plane** model. The Helm install gives you only the **control plane** Deployment in `nginx-gateway`. A separate **data plane** Deployment + Service is provisioned automatically *per Gateway* you create later, in the same namespace as that Gateway.

4. **Verify the control-plane pod is running:**
   ```bash
   kubectl get pods -n nginx-gateway
   ```
   Expected output (single control-plane container, `1/1`):
   ```
   NAME                                       READY   STATUS    RESTARTS   AGE
   ngf-nginx-gateway-fabric-xxxxxxxxx-yyyyy   1/1     Running   0          1m
   ```
   You will *not* see any data-plane pods yet - those appear once a `Gateway` is created in Lab 3.

5. **Confirm the GatewayClass shipped by NGINX Gateway Fabric is `Accepted`:**
   ```bash
   kubectl get gatewayclass
   ```
   You should see a `nginx` GatewayClass with `ACCEPTED=True`. If the chart did not create one, save the following as `gatewayclass.yaml` and apply it:
   ```yaml
   apiVersion: gateway.networking.k8s.io/v1
   kind: GatewayClass
   metadata:
     name: nginx
   spec:
     controllerName: gateway.nginx.org/nginx-gateway-controller
   ```
   ```bash
   kubectl apply -f gatewayclass.yaml
   ```

### Verification
- Gateway API CRDs are installed (`kubectl get crd | grep gateway.networking.k8s.io` returns at least 5 entries)
- NGINX Gateway Fabric control-plane pod is `Running` and `Ready` (1/1) in `nginx-gateway`
- `kubectl get gatewayclass` shows `nginx` with `ACCEPTED=True`

---

## Lab 2: Deploy Sample Applications

### Objectives
- Deploy two simple HTTP applications (`app1`, `app2`) with custom HTML
- Confirm each Service is reachable in-cluster

### Steps

1. **Save the following as `app1-deployment.yaml`:**
   ```yaml
   apiVersion: v1
   kind: ConfigMap
   metadata:
     name: app1-config
     namespace: default
   data:
     index.html: |
       <!DOCTYPE html>
       <html>
       <body>
           <h1>Hello, World, I am serving from app1!</h1>
       </body>
       </html>
   ---
   apiVersion: apps/v1
   kind: Deployment
   metadata:
     name: app1
     namespace: default
   spec:
     replicas: 2
     selector:
       matchLabels:
         app: app1
     template:
       metadata:
         labels:
           app: app1
       spec:
         containers:
           - name: app1
             image: nginx
             ports:
               - containerPort: 80
             volumeMounts:
               - name: app1-volume
                 mountPath: /usr/share/nginx/html
         volumes:
           - name: app1-volume
             configMap:
               name: app1-config
   ---
   apiVersion: v1
   kind: Service
   metadata:
     name: app1-service
     namespace: default
   spec:
     type: ClusterIP
     selector:
       app: app1
     ports:
       - protocol: TCP
         port: 80
         targetPort: 80
   ```

   **Save the following as `app2-deployment.yaml`** (identical, with `app1` → `app2`):
   ```yaml
   apiVersion: v1
   kind: ConfigMap
   metadata:
     name: app2-config
     namespace: default
   data:
     index.html: |
       <!DOCTYPE html>
       <html>
       <body>
           <h1>Hello, World, I am serving from app2!</h1>
       </body>
       </html>
   ---
   apiVersion: apps/v1
   kind: Deployment
   metadata:
     name: app2
     namespace: default
   spec:
     replicas: 2
     selector:
       matchLabels:
         app: app2
     template:
       metadata:
         labels:
           app: app2
       spec:
         containers:
           - name: app2
             image: nginx
             ports:
               - containerPort: 80
             volumeMounts:
               - name: app2-volume
                 mountPath: /usr/share/nginx/html
         volumes:
           - name: app2-volume
             configMap:
               name: app2-config
   ---
   apiVersion: v1
   kind: Service
   metadata:
     name: app2-service
     namespace: default
   spec:
     type: ClusterIP
     selector:
       app: app2
     ports:
       - protocol: TCP
         port: 80
         targetPort: 80
   ```

   Apply both:
   ```bash
   kubectl apply -f app1-deployment.yaml
   kubectl apply -f app2-deployment.yaml
   ```

2. **Verify pods and services:**
   ```bash
   kubectl get pods -l app=app1
   kubectl get pods -l app=app2
   kubectl get svc app1-service app2-service
   ```

### Verification
- 2 pods running for each app
- Both `app1-service` and `app2-service` are `ClusterIP` and reachable from inside the cluster

---

## Lab 3: Create a Gateway and Basic HTTPRoute (Path-Based Routing)

### Objectives
- Create a `Gateway` listening on port 80
- Attach an `HTTPRoute` that path-routes `/app1` and `/app2` to the two backends
- Send real HTTP traffic via the Gateway data plane

### Steps

1. **Save the following as `gateway.yaml`** and apply it:
   ```yaml
   apiVersion: gateway.networking.k8s.io/v1
   kind: Gateway
   metadata:
     name: demo-gateway
     namespace: default
   spec:
     gatewayClassName: nginx
     listeners:
       - name: http
         port: 80
         protocol: HTTP
         allowedRoutes:
           namespaces:
             from: Same
   ```
   ```bash
   kubectl apply -f gateway.yaml
   ```

2. **Confirm the Gateway is `Programmed`** and check that NGF provisioned its per-Gateway data-plane Deployment + Service:
   ```bash
   kubectl get gateway demo-gateway -o wide
   kubectl describe gateway demo-gateway
   kubectl get deploy,svc -n default -l app.kubernetes.io/managed-by=nginx-gateway-fabric
   ```
   Look for `Programmed: True` in conditions. With NGF v2.x, the data-plane Deployment and Service are created **in the same namespace as the Gateway** (`default` here) and are named after the Gateway (`demo-gateway-nginx`). The `ADDRESS` column on the Gateway may be a Service IP/hostname or empty depending on the platform.

3. **Save the following as `httproute-basic.yaml`** and apply it:
   ```yaml
   apiVersion: gateway.networking.k8s.io/v1
   kind: HTTPRoute
   metadata:
     name: demo-route-basic
     namespace: default
   spec:
     parentRefs:
       - name: demo-gateway
     hostnames:
       - "demo.example.com"
     rules:
       - matches:
           - path:
               type: PathPrefix
               value: /app1
         backendRefs:
           - name: app1-service
             port: 80
       - matches:
           - path:
               type: PathPrefix
               value: /app2
         backendRefs:
           - name: app2-service
             port: 80
   ```
   ```bash
   kubectl apply -f httproute-basic.yaml
   ```

4. **Inspect the route:**
   ```bash
   kubectl get httproute demo-route-basic
   kubectl describe httproute demo-route-basic
   ```
   Under `Status.Parents.Conditions` you should see `Accepted=True` and `ResolvedRefs=True`.

5. **Send traffic through the Gateway.** The per-Gateway data-plane Service is `demo-gateway-nginx` in the same namespace as the Gateway (`default`). On minikube/kind, port-forward:
   ```bash
   kubectl -n default port-forward svc/demo-gateway-nginx 8080:80 &
   ```
   On EKS / a managed cluster with LoadBalancer:
   ```bash
   GW_HOST=$(kubectl -n default get svc demo-gateway-nginx \
     -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
   echo "$GW_HOST"
   ```

6. **Test path routing.** With port-forward:
   ```bash
   curl -H "Host: demo.example.com" http://localhost:8080/app1/
   curl -H "Host: demo.example.com" http://localhost:8080/app2/
   ```
   Or with the LB hostname:
   ```bash
   curl -H "Host: demo.example.com" http://$GW_HOST/app1/
   curl -H "Host: demo.example.com" http://$GW_HOST/app2/
   ```
   Each path should return the matching app's HTML.

7. **Hit a non-existent path** to see a 404 from NGINX Gateway Fabric:
   ```bash
   curl -i -H "Host: demo.example.com" http://localhost:8080/nope
   ```

### Verification
- `Gateway` shows `Programmed=True`
- `HTTPRoute` shows `Accepted=True` and `ResolvedRefs=True`
- `/app1` and `/app2` paths return the right backend responses

---