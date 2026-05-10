# Class Discussion - Session 8-10

---

## The Reality of Software Delivery

No app goes from a developer's laptop straight to production. It travels through a series of environments, each with a specific job:

```
dev          →  developers write and integrate code
qa           →  QA team runs functional and regression tests
uat          →  business users do user acceptance testing
stg          →  staging - mirror of prod for final validation
pre-prod     →  pre-production smoke testing
certification →  compliance / certification testing (in regulated industries)
prod         →  the real thing
```

Same application, **7+ environments**. This is where the deployment problem starts.

---

## The Problem

You've written your application and created the full set of Kubernetes manifests for it:

```
deployment.yaml
hpa.yaml
service.yaml
ingress.yaml
configmap.yaml
secret.yaml
pvc.yaml
```

Now the question:

> **Can the same manifest files with the same content be applied to dev, uat, and prod?**

**Absolute NO.**

### Why the same files don't work everywhere

| What changes between environments | Example |
|---|---|
| **Database connection** | dev points to a dev MongoDB; prod points to a clustered prod MongoDB |
| **Replica count** | dev: 1 replica; prod: 10 replicas |
| **Resource requests/limits** | dev: 100m CPU / 128Mi RAM; prod: 1 CPU / 2Gi RAM |
| **HPA** | Often not needed in non-prod environments at all |
| **Certificates** | Different cert names and paths per environment |
| **Image tags** | dev: `myapp:dev-latest`; prod: `myapp:v1.4.7` |
| **Ingress hostnames** | `dev.shopnow.com` vs `shopnow.com` |
| **Log levels** | dev: `DEBUG`; prod: `INFO` or `WARN` |

So the question becomes — **what's the right way to handle this variation?**

---

## Why Plain YAML Doesn't Help

> **Can't I just use variables or dynamic values inside Kubernetes manifests?**

**No.** Kubernetes YAML is *static*. There's no built-in `${VAR}` substitution, no `if/else`, no loops. The API server expects fully-rendered YAML. It doesn't care where the values came from - but it won't compute them for you.

So we need a solution **outside** the YAML itself.

---

## Solution Attempt #1 — Environment-Specific Files

> "Let me just create one set of manifest files per environment."

```
k8s-manifests/
├── dev/
│   ├── deployment.yaml
│   ├── configmap.yaml
│   ├── secret.yaml
│   └── ... (7 files)
├── qa/
│   └── ... (7 files)
├── uat/
│   └── ... (7 files)
├── stg/
│   └── ... (7 files)
└── prod/
    └── ... (7 files)
```

### Why this falls apart

- **7 files × 5 environments = 35 files** to maintain
- Add a new env variable? Edit it in **5 places**
- A bug fix in `deployment.yaml` has to be copy-pasted into 5 directories - hope you don't miss one
- Files drift apart over time. The dev `deployment.yaml` slowly stops looking like the prod one.
- This is classic **technical debt** - you're paying interest on every change forever

This doesn't scale. Even at 1 app × 5 envs it's painful. Now imagine 30 microservices.

---

## Solution Attempt #2 — Placeholders + Shell Scripts

> "Let me put placeholders inside my manifests and replace them with `sed` before applying."

### Example: `secret.yaml` with a placeholder

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: backend-secret
  namespace: shopnow-demo
type: Opaque
stringData:
  MONGODB_URI: MONGODB_ACTUAL_URI    # ← placeholder
```

Applying this directly with `kubectl apply -f secret.yaml` would push the literal string `MONGODB_ACTUAL_URI` into the cluster, which is incorrect.

So before applying, run a `sed` substitution:

```bash
cd k8s-manifests/

# Replace placeholder with the actual dev value
sed 's|MONGODB_ACTUAL_URI|mongodb://shopuser:ShopNowPass123@mongo-0.mongo-headless.shopnow-demo.svc.cluster.local:27017/shopnow?authSource=admin|g' \
    secret.yaml > rendered/secret.yaml

kubectl apply -f rendered/secret.yaml
```

Then repeat the whole sed dance for qa, uat, prod with different values.

### Why this is also bad

- Shell scripts become a tangled mess as the number of placeholders grows
- No type safety - typo in a placeholder name? Silent failure
- Escaping special characters in `sed` (slashes, ampersands, quotes) is a nightmare - look at the URI above
- No way to do conditional logic ("include HPA only in prod")
- No way to loop ("create 5 similar configmaps")
- No versioning, no rollback, no concept of a "release"
- Every team reinvents this wheel slightly differently

We need a **proper templating engine** that understands Kubernetes manifests.

---

## Enter Helm

> **Helm gives you native templating for Kubernetes manifests.**

- Written in **Go**
- Often called the **"package manager for Kubernetes"** (like `apt` for Ubuntu or `npm` for Node.js)
- Uses Go's `text/template` engine under the hood

### What Helm Solves

| Problem | Helm's Answer |
|---|---|
| Same manifests, different env values | Templates with `{{ .Values.foo }}` placeholders |
| One values file per environment | `values-dev.yaml`, `values-prod.yaml`, etc. |
| Conditional resources (HPA only in prod) | `{{ if .Values.hpa.enabled }}` blocks |
| Repeated patterns | `range` loops, named templates (`_helpers.tpl`) |
| Tracking what's deployed | Helm releases - named, versioned, rollback-able |
| Sharing apps with others | Helm charts published to repositories |

### The Mental Model

```
Chart (templates + default values)   +   values-<env>.yaml   →   Helm renders   →   Plain k8s YAML   →   kubectl applies
```

You write the manifests **once** as templates. You maintain **one small values file per environment**. Helm fills in the blanks at install time.

### A Quick example

**Template (`templates/deployment.yaml`):**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Values.app.name }}
spec:
  replicas: {{ .Values.replicaCount }}
  template:
    spec:
      containers:
      - name: {{ .Values.app.name }}
        image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
```

**`values-dev.yaml`:**
```yaml
replicaCount: 1
image:
  tag: dev-latest
```

**`values-prod.yaml`:**
```yaml
replicaCount: 10
image:
  tag: v1.4.7
```

**Install commands:**
```bash
helm upgrade --install shopnow ./shopnow-chart -f values-dev.yaml   # dev
helm upgrade --install shopnow ./shopnow-chart -f values-prod.yaml  # prod
```

Same chart. Different values. Same outcome philosophy as Solution #2 - but engineered properly.

---