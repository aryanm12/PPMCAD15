# Class Discussion - Session 8-11

---

## How Teams Actually Work in Git

You have an application checked into a Git repo. Alongside the application code, you also keep your **Kubernetes manifests or Helm charts** in the same (or a sibling) repo.

A typical branching strategy:

```
main          ←  what's running in production
release       ←  release candidates, ready for prod
develop       ←  integration branch - where features come together
feature/*     ←  individual work-in-progress branches
hotfix/*      ←  emergency fixes
```

### Who works where

- **Developers** make application code changes in `feature/*` branches
- **DevOps / Platform team** make changes to K8s manifests or Helm charts - also in `feature/*` branches
- After validation, changes merge **into `develop`**
- After release cycle, changes flow **from `develop` → `release` → `main`**

So far, this is just standard Git workflow. The question is: **how does code in `main` actually get deployed to the cluster?**

---

## What GitOps Says

GitOps is a set of principles. Two of them matter most:

### Principle 1 - Everything as Code, in Git

> **Anything that defines the state of your system must be persisted as code in a Git repo.**

This includes:

- Application source code
- Kubernetes manifests / Helm charts
- Infrastructure (Terraform, CloudFormation)
- Configuration changes
- RBAC policies, network policies, ingress rules
- Even cluster bootstrap configs

**No clicking in consoles. No `kubectl apply` from a laptop. No manual edits.** If it's not in Git, it doesn't exist.

### Principle 2 - Git Is the Source of Truth, and It's Always Deployable

> **Whatever is in certain branches (`main`, `pre-prod`, etc.) should always be in a deployable state - and ideally, automatically deployed.**

A controller running inside the cluster continuously watches the Git repo and reconciles the cluster's state to match what's in Git.

```
Developer commits to main
     ↓
GitOps controller detects change (within seconds/minutes)
     ↓
Controller pulls the new manifests
     ↓
Controller applies them to the cluster
     ↓
Cluster state now matches Git
```

---

## What This Looks Like in Reality

If you fully adopt GitOps:

- A merge to `main` shows up in **production within ~5 minutes**
- You achieve **continuous deployment** in the truest sense
- You get **zero-touch deployments** - no human runs `kubectl` or `helm` manually
- Even **infrastructure changes** (via Terraform/Atlantis-style flows) deploy the same way
- Rollback is trivial: `git revert` → controller reconciles backwards

---

## The Practical Challenges

GitOps sounds amazing. But "merge → 5 minutes → prod" raises real concerns:

| Concern | What it means |
|---|---|
| **Untested code in production** | What if a bug slipped past CI? It's live in 5 minutes. |
| **Release timing** | "I want to ship this on June 10, 2026 - not the moment it's merged." |
| **Compliance / change management** | Some industries legally require change approval boards |
| **No human in the loop** | Removing humans removes a safety net |
| **Coordinated releases** | Multiple services need to ship together with a feature toggle |

These aren't reasons to *avoid* GitOps - they're reasons your **organization needs to be ready** for it.

---

## How an Org Becomes GitOps-Ready

Before you flip the switch on continuous deployment, you need:

### 1. Multiple Lower Environments
dev → qa → uat → stg → pre-prod → prod. Code earns its way to prod by passing through each.

### 2. Rigorous Automated Testing
- **Functional tests** running on every PR
- **Integration tests** in lower envs
- **Critical user journey tests** (also called **synthetic monitoring**) - automated bots that continuously simulate real user flows in prod (login, search, add-to-cart, checkout)
- If any of these fail, the pipeline halts the promotion

### 3. Feature Flags
- Code can ship to prod **disabled**
- Business decides *when* to turn the feature on, independent of deployment
- Solves the "don't release until June 10" problem cleanly - merge whenever, flip the flag on the date

### 4. Strong Observability & Fast Rollback
- Logs, metrics, traces in place
- Auto-rollback on error rate spikes
- One-command (or one-commit) revert

> **The rule of thumb: if you want to ship fast, adopt GitOps. But adopt the safety nets first.**

---

## How to Adopt GitOps - The Tools

Two main players in the Kubernetes world:

| Tool | Origin |
|---|---|
| **ArgoCD** | CNCF graduated project, originally from Intuit |
| **FluxCD** | CNCF graduated project, originally from Weaveworks |

Both follow the same core idea - a controller running in the cluster watches Git and reconciles state. They differ in UX, scope, and conventions.

---

## ArgoCD - The Mental Model

ArgoCD is installed **inside your Kubernetes cluster** as a set of pods. It introduces its own **CRDs (Custom Resource Definitions)** - most importantly the `Application` CRD, which represents "deploy this Git path to this cluster namespace."

### The Pods That Run

When you install ArgoCD, you get roughly these components running as pods:

| Component | Job |
|---|---|
| **argocd-repo-server** | Clones Git repos, renders manifests (runs `helm template`, `kustomize build`, etc.), returns rendered YAML |
| **argocd-application-controller** | The brain. Watches `Application` CRDs, compares Git state vs cluster state, performs sync (apply) operations |
| **argocd-server (API server)** | Serves the Web UI, CLI, and gRPC/REST API |
| **argocd-dex-server** | Handles SSO / OIDC integration for user login |
| **argocd-redis** | Caches rendered manifests and state for performance |

### The Flow

```
1. You create an Application CRD pointing to a Git repo + path
2. repo-server clones the repo, renders manifests
3. application-controller compares rendered manifests vs live cluster state
4. If drift detected → controller applies the manifests (auto-sync) or shows "Out of Sync" (manual sync)
5. Status surfaces in the UI
```

You see all of this in the ArgoCD UI - a tree view of every resource, sync status, health status, and a diff between Git and cluster.

---

## Class Question - Restricting Access to a URL Path

> **I want to allow my testing team to access only `mywebsite.com/testing` from their static IP. The main site `mywebsite.com/` should remain open to everyone. Can I just add a second SG rule to my ALB?**

### The Architecture

```
Internet  →  ALB (SG)  →  EC2
              ↓
              Routes:
                /         → public
                /testing  → only testing team's IP
```

### Why You Can't Solve This With Security Groups

Security groups operate at **Layer 4** - IP and port only. An SG inbound rule on the ALB can say:

- "Allow port 443 from `0.0.0.0/0`" - public
- "Allow port 443 from `203.0.113.42/32`" - testing team's static IP

But an SG **cannot distinguish between `/` and `/testing`** - that's URL path information, which lives at **Layer 7 (HTTP)**. SGs are blind to it.

So adding "a second SG" doesn't help. Both rules apply to all traffic on port 443 regardless of path.

### Three Real Solutions

**Option 1 - Separate the infra completely**

Run a **separate ALB + EC2 stack** for the testing environment, locked down by SG to the testing team's IP. Cleanest separation, highest cost.

**Option 2 - Use AWS WAF in front of the ALB**

WAF (Web Application Firewall) operates at **Layer 7**. It can read HTTP requests and apply rules based on URL path, headers, query strings, etc.

```
Internet  →  WAF  →  ALB  →  EC2
```

WAF rule:
- **IF** request URI starts with `/testing`
- **AND** source IP is NOT in the testing-team-IPs allowlist
- **THEN** block the request (return 403)

Everything else passes through normally. This is the **right** answer for the use case described.

**Option 3 - Application-level auth**

Have the application itself check the source IP or require auth on `/testing`. Works, but pushes security concerns into application code - not ideal.

### The Takeaway

> **Layer 4 controls (Security Groups) protect ports. Layer 7 controls (WAF, ALB listener rules with auth) protect URLs. Pick the layer that matches the granularity you need.**

---