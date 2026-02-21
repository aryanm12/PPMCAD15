# Docker Training - Session 4
## Golden Base Image Workflow & Troubleshooting Containers

---

## Golden Base Image Workflow

### What is a Golden Base Image?

A **Golden Base Image** is a pre-approved, hardened, and standardized Docker image that serves as the foundation for all application images within an organization.

Think of it as a **company-approved template** - instead of every team picking random images from Docker Hub, everyone builds on top of a verified, secure base.

```
Without Golden Base Image:
┌───────────┐   ┌───────────┐   ┌───────────┐
│  Team A   │   │  Team B   │   │  Team C   │
│ ubuntu:22 │   │ alpine:3  │   │ debian:12 │
│ + random  │   │ + random  │   │ + random  │
│  packages │   │  packages │   │  packages │
└───────────┘   └───────────┘   └───────────┘
     ↓               ↓               ↓
  Different OS, packages, security posture ❌


With Golden Base Image:
                ┌──────────────────────┐
                │   Golden Base Image  │
                │   (Approved, Scanned │
                │    Hardened, Patched)│
                └──────────┬───────────┘
           ┌───────────────┼───────────────┐
           ↓               ↓               ↓
      ┌─────────┐    ┌─────────┐    ┌─────────┐
      │ Team A  │    │ Team B  │    │ Team C  │
      │  App    │    │  App    │    │  App    │
      └─────────┘    └─────────┘    └─────────┘
     
  Same base, consistent security, easy compliance ✅
```

### Why Use a Golden Base Image?

**1. Security** - Pre-scanned for vulnerabilities (CVEs), unnecessary packages removed

**2. Consistency** - All teams use the same OS, libraries, and configurations

**3. Compliance** - Meets organizational and regulatory requirements out of the box

**4. Faster Builds** - Common dependencies are already baked in, reducing build times

**5. Easier Patching** - Update the golden image once, all downstream images benefit on rebuild

---

### The Golden Base Image Workflow

```
┌──────────────────────────────────────────────────────────────────┐
│                  GOLDEN BASE IMAGE PIPELINE                      │
│                                                                  │
│  Step 1          Step 2          Step 3          Step 4          │
│ ┌──────────┐   ┌──────────┐   ┌──────────┐   ┌──────────┐        │
│ │  Select  │   │ Harden & │   │  Scan &  │   │  Push to │        │
│ │  Base OS │--→│ Customize│--→│ Approve  │--→│ Registry │        │
│ │  Image   │   │  Image   │   │  Image   │   │          │        │
│ └──────────┘   └──────────┘   └──────────┘   └──────────┘        │
│  (alpine,       (install        (Trivy,         (ECR, Harbor,    │
│   ubuntu,        packages,       Snyk,           ACR, Docker     │
│   debian)        configs,        manual          Hub private)    │
│                  remove junk)    review)                         │
│                                                                  │
│  Step 5                                                          │
│ ┌──────────────────────────────────────────────────────────┐     │
│ │  Dev teams use golden image as FROM in their Dockerfile  │     │
│ └──────────────────────────────────────────────────────────┘     │
└──────────────────────────────────────────────────────────────────┘
```

---

### Step 1: Select a Base OS Image

Choose an official, minimal base image to start from:

```
Image               │  Size    │  Use Case
────────────────────┼──────────┼────────────────────────────
alpine:3.19         │  ~5 MB   │  Minimal, lightweight apps
ubuntu:24.04        │  ~78 MB  │  General purpose, broad compatibility
debian:12-slim      │  ~80 MB  │  Stable, minimal Debian
amazonlinux:2023    │  ~143 MB │  AWS-native workloads
```

### Step 2: Harden & Customize

Create a Dockerfile for your golden image that installs approved packages, applies security configs, and removes unnecessary components.

```dockerfile
# Golden Base Image - e.g. a Node.js base image
FROM node:18-alpine

LABEL maintainer="platform-team@company.com"
LABEL org.company.image-type="golden-base"
LABEL org.company.approved="true"

# Install only approved system packages
RUN apk update && \
    apk add --no-cache \
      curl \
      tini \
      dumb-init && \
    # Remove package cache to reduce size
    rm -rf /var/cache/apk/*

# Create a non-root user
RUN addgroup -g 1001 -S appgroup && \
    adduser -u 1001 -S appuser -G appgroup

# Set secure defaults
ENV NODE_ENV=production

# Use non-root user by default
USER appuser

WORKDIR /app
```

```dockerfile
# Golden Base Image - e.g. a Python base image
FROM python:3.11-slim

LABEL maintainer="platform-team@company.com"
LABEL org.company.image-type="golden-base"

# Security hardening
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      curl \
      tini && \
    # Remove unnecessary packages and cache
    apt-get purge -y --auto-remove && \
    rm -rf /var/lib/apt/lists/* /tmp/*

# Create non-root user
RUN groupadd -g 1001 appgroup && \
    useradd -u 1001 -g appgroup -s /bin/bash -m appuser

USER appuser
WORKDIR /app
```

### Step 3: Scan & Approve

Before pushing, scan the image for vulnerabilities:

```bash
# Scan with Trivy
trivy image --severity HIGH,CRITICAL company/golden-node:18-v1.0

# Fail if any critical vulnerabilities found
trivy image --exit-code 1 --severity CRITICAL company/golden-node:18-v1.0
```

This step is typically automated in a **CI/CD pipeline** - the image only gets pushed if the scan passes.

### Step 4: Push to a Private Registry

```bash
# Tag with version
docker tag golden-node:latest company-registry.com/golden/node:18-v1.0
docker tag golden-node:latest company-registry.com/golden/node:18-latest

# Push
docker push company-registry.com/golden/node:18-v1.0
docker push company-registry.com/golden/node:18-latest
```

### Step 5: Dev Teams Use the Golden Image

Application teams reference the golden image as their `FROM`:

```dockerfile
# Application Dockerfile
FROM company-registry.com/golden/node:18-v1.0

COPY package*.json ./
RUN npm ci --only=production

COPY . .
EXPOSE 3000
CMD ["node", "server.js"]
```

---

### Golden Image Maintenance Cycle

The golden image is **not a one-time thing**. It needs regular updates:

```
┌──────────────────────────────────────────────────────────┐
│              Monthly / On-Demand Update Cycle            │
│                                                          │
│  New CVE found or monthly schedule triggers              │
│       ↓                                                  │
│  Update base OS + packages in golden Dockerfile          │
│       ↓                                                  │
│  Run vulnerability scan                                  │
│       ↓                                                  │
│  Push new version (e.g., 18-v1.1)                        │
│       ↓                                                  │
│  Notify teams to rebuild their app images                │
│       ↓                                                  │
│  Old version (18-v1.0) deprecated after grace period     │
└──────────────────────────────────────────────────────────┘
```

---

## Docker Troubleshooting Inside a Running Container

When a container is running but something isn't working right - the app is crashing, a service isn't connecting, files are missing - you need to **get inside the container** and debug.

### Getting Shell Access

The primary tool for troubleshooting is `docker exec`:

```bash
# Get an interactive shell inside a running container
docker exec -it <container_name> /bin/bash

# If bash is not available (e.g., Alpine-based images)
docker exec -it <container_name> /bin/sh

# Run a single command without entering the shell
docker exec <container_name> cat /etc/os-release
```

```
What docker exec does:
┌──────────────────────────────────────────────┐
│            Running Container                 │
│                                              │
│   PID 1: Your app (node, python, nginx...)   │
│                                              │
│   docker exec starts a NEW process:          │
│   PID X: /bin/bash  ← You are here           │
│                                              │
│   Your app keeps running normally!           │
└──────────────────────────────────────────────┘
```

> **Key Point:** `docker exec` does NOT restart the container. It spawns a new process alongside the running app. The app is unaffected.

---

### Checking Logs

Before going inside the container, always check logs first:

```bash
# View all logs
docker logs <container_name>

# Follow logs in real-time (like tail -f)
docker logs -f <container_name>

# Last 50 lines with timestamps
docker logs --tail 50 -t <container_name>

# Logs since a specific time
docker logs --since "2025-02-21T10:00:00" <container_name>
```

---

### Inspecting the Container

```bash
# Full container details (JSON output)
docker inspect <container_name>

# Check container status and exit code
docker inspect --format='{{.State.Status}}' <container_name>
docker inspect --format='{{.State.ExitCode}}' <container_name>

# Check environment variables
docker inspect --format='{{.Config.Env}}' <container_name>

# Check network settings
docker inspect --format='{{json .NetworkSettings.Networks}}' <container_name>

# Get container IP address
docker inspect --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' <container_name>

# Check port mappings
docker port <container_name>
```

---

### Checking Processes and Resource Usage

```bash
# View running processes inside the container
docker top <container_name>

# Live resource usage (CPU, memory, network I/O)
docker stats <container_name>

# View filesystem changes made since container started
docker diff <container_name>
# Output: A = Added, C = Changed, D = Deleted
```

---

### Debugging Inside the Container

Once you're inside the container (`docker exec -it <name> sh`), here are the common checks:

#### Check if a process is running

```bash
ps aux
# or
ps -ef
```

#### Check if a service is listening on a port

```bash
netstat -tulpn
# or (if netstat is not available)
ss -tulpn
```

#### Test network connectivity

```bash
# Ping another container or external host
ping -c 3 google.com
ping -c 3 db-container

# DNS resolution
nslookup google.com
nslookup db-container

# Test if a port is reachable
curl -f http://backend:8080/health

# If curl is not available, use wget (common in Alpine)
wget -qO- http://backend:8080/health
```

#### Check files and permissions

```bash
# Check if config files exist and have correct content
cat /app/config.yml
ls -la /app/

# Check disk usage
df -h

# Check who you're running as
whoami
id
```

#### Check environment variables

```bash
# List all environment variables
env

# Check a specific one
echo $DATABASE_URL
```

---