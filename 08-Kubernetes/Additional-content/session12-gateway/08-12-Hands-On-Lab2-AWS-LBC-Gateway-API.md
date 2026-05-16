# Session 08-12: Kubernetes Gateway API - Hands-On Lab 2 (AWS Load Balancer Controller)

## Overview
Lab 1 used NGINX Gateway Fabric — a portable, in-cluster controller that runs anywhere. **Lab 2 uses the AWS Load Balancer Controller (LBC) you already installed in Session 6**, but exercises its **Gateway API** support instead of the legacy `Ingress` resource. The same `GatewayClass`, `Gateway`, and `HTTPRoute` objects you wrote against NGINX Gateway Fabric in Lab 1 will now be reconciled by the LBC into a real **AWS Application Load Balancer (ALB)**.

This is the recommended path for production EKS workloads that need Gateway API: no extra controller to install, no second LB stack to operate. The LBC simply adds Gateway-API reconciliation alongside its existing Ingress reconciliation.

**How LBC maps Gateway API to AWS:**

| Gateway API resource                     | What LBC provisions in AWS                                  |
|------------------------------------------|-------------------------------------------------------------|
| `GatewayClass` with `controllerName: gateway.k8s.aws/alb` | Marks the class as L7 / ALB-managed                         |
| `GatewayClass` with `controllerName: gateway.k8s.aws/nlb` | Marks the class as L4 / NLB-managed                         |
| `Gateway` referencing the ALB GatewayClass | A new **AWS ALB** in your VPC (one ALB per Gateway)         |
| `Listener` on a `Gateway`                | An **ALB Listener** (HTTP:80, HTTPS:443, etc.)              |
| `HTTPRoute` / `GRPCRoute`                | **ALB Listener Rules** + **Target Groups** for the backend Services |
| `LoadBalancerConfiguration` (LBC CRD)    | Per-Gateway tuning: scheme, subnets, certs, attributes      |
| `TargetGroupConfiguration` (LBC CRD)     | Per-Service tuning: target type, health checks              |

**Targeted versions:**
- AWS Load Balancer Controller: **v3.0.0+ recommended** for production. Gateway API support went GA in **v3.0.0** (early 2026). Earlier versions had Gateway API as Beta — L7 ALB Gateway from v2.14.0 (Beta), L4 NLB Gateway from v2.13.3 (Beta).
- Gateway API CRDs: **v1.5.0** (standard channel)
- Built and tested by AWS against Gateway API v1.5.0
- Always check the official prerequisites: https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/guide/gateway/gateway/

**Prerequisites:**
- A working **EKS cluster**
- **AWS Load Balancer Controller v3.0.0 or newer** already installed (from Session 6).
- `kubectl` v1.27+ pointed at the EKS cluster
- `helm` 3+
- `curl` available locally
- IAM / OIDC for the LBC's ServiceAccount already wired up (done in Session 6)

> All YAML used in this lab is shown inline. When a step says *"Save the following as `foo.yaml`"*, copy the block into a file with that name in your working directory, then run the `kubectl apply -f foo.yaml` that follows.

> **Heads-up on cost.** Each `Gateway` provisioned in this lab is a real AWS ALB billed by the hour plus LCUs. Run the cleanup section (Lab 2-7) when you're done.

---

## Lab 2-1: Verify the LBC Supports Gateway API and Install the CRDs

### Objectives
- Confirm the existing AWS LBC is at a version that reconciles Gateway API
- Install the standard Gateway API CRDs **and** the AWS LBC's Gateway-API-specific CRDs

### Steps

1. **Confirm LBC version:**
   ```bash
   kubectl -n kube-system get deploy aws-load-balancer-controller \
     -o jsonpath='{.spec.template.spec.containers[0].image}'; echo
   ```
   Expect a tag of `v3.0.0` or newer for production-grade Gateway API support. `v2.14.x` will work too but is Beta. If you see `v2.12.x` or older (no L7 Gateway at all), upgrade per the Helm command in Prerequisites before continuing.

2. **Install the standard Gateway API CRDs (v1.5.0):**
   ```bash
   kubectl apply --server-side=true \
     -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.0/standard-install.yaml
   ```
   `--server-side=true` is **required** here — the LBC docs call this out specifically for Gateway API CRDs.

3. **Install the AWS LBC's Gateway-API-specific CRDs (`LoadBalancerConfiguration`, `TargetGroupConfiguration`, `ListenerRuleConfiguration`):**
   ```bash
   kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/refs/heads/main/config/crd/gateway/gateway-crds.yaml
   ```

4. **Verify all CRDs are present:**
   ```bash
   kubectl get crd | grep -E 'gateway.networking.k8s.io|gateway.k8s.aws'
   ```
   You should see the standard Gateway API CRDs (`gatewayclasses`, `gateways`, `httproutes`, `grpcroutes`, `referencegrants`) **and** the AWS-vended ones (`loadbalancerconfigurations.gateway.k8s.aws`, `targetgroupconfigurations.gateway.k8s.aws`, `listenerruleconfigurations.gateway.k8s.aws`).

5. **Confirm the LBC has enabled its Gateway controllers.** Once the CRDs are present, the LBC auto-detects them. Tail the logs and look for the `ALBGatewayAPI` controller starting:
   ```bash
   kubectl -n kube-system logs deploy/aws-load-balancer-controller \
     | grep -iE 'gateway|albgatewayapi' | head -20
   ```
   You should see lines indicating the ALB Gateway controller has registered. If it didn't pick up the CRDs, restart the deployment:
   ```bash
   kubectl -n kube-system rollout restart deploy/aws-load-balancer-controller
   ```

### Verification
- LBC image tag is `v3.0.0+` (or at minimum `v2.14.x` if running Beta)
- Both standard Gateway API CRDs and `gateway.k8s.aws` CRDs are installed
- LBC logs mention the ALB Gateway controller starting

---

## Lab 2-2: Deploy Sample Applications

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

2. **Verify pods and Services:**
   ```bash
   kubectl get pods -l app=app1
   kubectl get pods -l app=app2
   kubectl get svc app1-service app2-service
   ```
   Both Services should be `ClusterIP` with `Endpoints` populated.

### Verification
- Two pods `Running` for each app
- `app1-service` and `app2-service` exist and have endpoints

---

## Lab 2-3: Create the ALB GatewayClass and a Gateway

### Objectives
- Declare an `aws-alb` `GatewayClass` pointed at controller `gateway.k8s.aws/alb`
- Create an internet-facing `Gateway` with an HTTP listener on port 80
- Watch the LBC provision a real ALB in AWS

### Steps

1. **Create a GatewayClass file `alb-gatewayclass.yaml`:**
   ```yaml
   apiVersion: gateway.networking.k8s.io/v1
   kind: GatewayClass
   metadata:
     name: aws-alb
   spec:
     controllerName: gateway.k8s.aws/alb
   ```
   Apply it:
   ```bash
   kubectl apply -f alb-gatewayclass.yaml
   ```

2. **Confirm the GatewayClass is `Accepted`:**
   ```bash
   kubectl get gatewayclass aws-alb
   ```
   `ACCEPTED` should be `True`. If `False`, re-check that the LBC version is v2.14+ (v3.0+ recommended) and the LBC pods restarted after the CRDs were applied.

3. **Create a `LoadBalancerConfiguration` to make the ALB internet-facing.** Create `alb-lbconfig.yaml`:
   ```yaml
   apiVersion: gateway.k8s.aws/v1beta1
   kind: LoadBalancerConfiguration
   metadata:
     name: alb-public
     namespace: default
   spec:
     scheme: internet-facing
     # Optional: pin to specific subnets if you don't want subnet auto-discovery
     # loadBalancerSubnets:
     #   - subnetID: subnet-xxxxxxxx
     #   - subnetID: subnet-yyyyyyyy
   ```
   Apply it:
   ```bash
   kubectl apply -f alb-lbconfig.yaml
   ```

4. **Create the Gateway. Save as `alb-gateway.yaml`:**
   ```yaml
   apiVersion: gateway.networking.k8s.io/v1
   kind: Gateway
   metadata:
     name: demo-alb-gateway
     namespace: default
   spec:
     gatewayClassName: aws-alb
     infrastructure:
       parametersRef:
         group: gateway.k8s.aws
         kind: LoadBalancerConfiguration
         name: alb-public
     listeners:
       - name: http
         protocol: HTTP
         port: 80
         allowedRoutes:
           namespaces:
             from: Same
   ```
   Apply it:
   ```bash
   kubectl apply -f alb-gateway.yaml
   ```

5. **Watch the LBC provision the ALB.** It usually takes 2–4 minutes for the ALB to be active and the Gateway status to populate:
   ```bash
   kubectl get gateway demo-alb-gateway -w
   ```
   Once `PROGRAMMED` is `True`, an `ADDRESS` (the ALB DNS name) will appear.

6. **Inspect the full status, including the ARN:**
   ```bash
   kubectl describe gateway demo-alb-gateway
   ```
   Under `Status` you'll see conditions `Accepted=True`, `Programmed=True`, and the addresses list with the ALB hostname. The LBC also surfaces the ALB ARN there.

7. **Confirm in AWS** (optional but recommended the first time):
   ```bash
   aws elbv2 describe-load-balancers \
     --query 'LoadBalancers[?contains(LoadBalancerName,`k8s-default-demoalbg`)].[LoadBalancerName,DNSName,Scheme,State.Code]' \
     --output table
   ```

   or via the console

### Verification
- `kubectl get gatewayclass aws-alb` shows `ACCEPTED=True`
- `kubectl get gateway demo-alb-gateway` shows `PROGRAMMED=True` and an ALB DNS name in `ADDRESS`
- The ALB exists in the AWS console / `aws elbv2 describe-load-balancers`

---

## Lab 2-4: Path-Based Routing with HTTPRoute

### Objectives
- Attach an `HTTPRoute` to the Gateway that path-routes `/app1` → `app1-service` and `/app2` → `app2-service`
- See the LBC create ALB Listener Rules and Target Groups
- Drive real traffic through the ALB

### Steps

1. **Create `alb-httproute-basic.yaml`:**
   ```yaml
   apiVersion: gateway.networking.k8s.io/v1
   kind: HTTPRoute
   metadata:
     name: demo-alb-route
     namespace: default
   spec:
     parentRefs:
       - group: gateway.networking.k8s.io
         kind: Gateway
         name: demo-alb-gateway
         sectionName: http
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
   Apply it:
   ```bash
   kubectl apply -f alb-httproute-basic.yaml
   ```

2. **Verify the route is accepted and refs are resolved:**
   ```bash
   kubectl describe httproute demo-alb-route
   ```
   Look for `Accepted=True` and `ResolvedRefs=True` under each parent's conditions. If `ResolvedRefs=False / BackendNotFound`, the Service name or namespace is wrong.

3. **Grab the ALB DNS name:**
   ```bash
   ALB_DNS=$(kubectl get gateway demo-alb-gateway \
     -o jsonpath='{.status.addresses[0].value}')
   echo "$ALB_DNS"
   ```

4. **Send traffic through the ALB:**
   ```bash
   curl -i  http://$ALB_DNS/app1/
   curl -i  http://$ALB_DNS/app2/
   ```
   You should get HTML from `app1` and `app2` respectively.

5. **Hit a non-existent path** to confirm the ALB returns the default 404:
   ```bash
   curl -i  http://$ALB_DNS/nope
   ```

6. **Inspect the AWS side** (optional):
   ```bash
   aws elbv2 describe-target-groups \
     --query 'TargetGroups[?contains(TargetGroupName,`k8s-default`)].[TargetGroupName,Protocol,Port,TargetType]' \
     --output table
   ```
   You should see two target groups, one per backend Service.

### Verification
- `HTTPRoute` shows `Accepted=True` and `ResolvedRefs=True`
- `curl http://$ALB_DNS/app1/` and `/app2/` return the right backend HTML
- AWS shows two target groups created by the LBC

---