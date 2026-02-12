# Docker Optimization Cheat Sheet
## Advanced Techniques for Production

---

## Multi-Stage Builds

### Basic Pattern

```dockerfile
# Stage 1: Build
FROM golang:1.21-alpine AS builder
WORKDIR /app
COPY . .
RUN go build -o app

# Stage 2: Runtime
FROM alpine:latest
COPY --from=builder /app/app .
CMD ["./app"]
```

### Named Stages

```dockerfile
FROM node:16-alpine AS dependencies
RUN npm ci --only=production

FROM node:16-alpine AS builder
RUN npm ci && npm run build

FROM node:16-alpine AS runtime
COPY --from=dependencies /app/node_modules ./node_modules
COPY --from=builder /app/dist ./dist
CMD ["node", "dist/server.js"]
```

### Copy from External Image

```dockerfile
FROM scratch
COPY --from=nginx:alpine /usr/share/nginx/html /html
```

---

## Image Size Optimization

### Use Alpine

```dockerfile
# ❌ Large
FROM node:16  # 900MB

# ✓ Optimized
FROM node:16-alpine  # 110MB
```

### Minimize Layers

```dockerfile
# ❌ Many layers
RUN apt-get update
RUN apt-get install -y curl
RUN apt-get install -y git

# ✓ Single layer
RUN apt-get update && \
    apt-get install -y curl git && \
    rm -rf /var/lib/apt/lists/*
```

### Remove Package Manager Cache

```dockerfile
# Alpine
RUN apk add --no-cache python3

# Debian/Ubuntu
RUN apt-get update && \
    apt-get install -y python3 && \
    rm -rf /var/lib/apt/lists/*

# Python
RUN pip install --no-cache-dir -r requirements.txt
```

---

## Build Optimization

### Layer Caching

```dockerfile
# ✓ Dependencies cached separately
COPY package.json package-lock.json ./
RUN npm ci
COPY . .

# ❌ Full rebuild on code change
COPY . .
RUN npm install
```

### .dockerignore

```
node_modules
.git
.env
*.log
dist
coverage
.DS_Store
```

### Build Arguments

```dockerfile
ARG NODE_VERSION=16
FROM node:${NODE_VERSION}-alpine

ARG BUILD_ENV=production
RUN npm run build:${BUILD_ENV}
```

---

## Security Optimization

### Non-Root User

```dockerfile
# Create user
RUN adduser -D -u 1000 appuser

# Switch user
USER appuser

# Verify
RUN whoami  # Should be appuser
```

### Read-Only Filesystem

```bash
docker run --read-only \
  --tmpfs /tmp \
  --tmpfs /var/run \
  myapp
```

### Secrets Management

```dockerfile
# ❌ Never do this
ENV API_KEY=secret123

# ✓ Use runtime secrets
# Pass via environment or secrets file
```

```bash
docker run -e API_KEY=${API_KEY} myapp
```

---

## Resource Optimization

### Memory Limits

```bash
# Docker run
docker run --memory="512m" myapp

# Docker Compose
deploy:
  resources:
    limits:
      memory: 512M
```

### CPU Limits

```bash
# 1 full CPU
docker run --cpus="1.0" myapp

# 50% of one CPU
docker run --cpus="0.5" myapp
```

### Combined Limits

```yaml
deploy:
  resources:
    limits:
      cpus: '1.0'
      memory: 512M
    reservations:
      cpus: '0.5'
      memory: 256M
```

---

## Runtime Optimization

### Health Checks

```dockerfile
HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
  CMD curl -f http://localhost/health || exit 1
```

### Logging

```bash
# JSON logging
docker run --log-driver=json-file \
  --log-opt max-size=10m \
  --log-opt max-file=3 \
  myapp
```

### Restart Policies

```bash
docker run --restart unless-stopped myapp
```

```yaml
restart: unless-stopped  # Compose
```

---

## Build Speed Optimization

### BuildKit

```bash
# Enable BuildKit
export DOCKER_BUILDKIT=1

# Use cache mounts
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install -r requirements.txt
```

### Parallel Builds

```bash
docker compose build --parallel
```

### Build Cache

```bash
# Use cache from registry
docker build --cache-from myapp:latest .

# Export cache
docker build --cache-to type=registry,ref=myapp:cache .
```

---

## Network Optimization

### DNS Caching

```bash
docker run --dns 8.8.8.8 myapp
```

### Host Network (Performance)

```bash
docker run --network host myapp
```

---

## Storage Optimization

### Volume Driver Options

```yaml
volumes:
  data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: /path/to/data
```

### Prune Regularly

```bash
# Remove unused data
docker system prune -a --volumes

# Remove build cache
docker builder prune
```

---

## Monitoring & Profiling

### Stats

```bash
docker stats myapp
```

### Inspect Resource Usage

```bash
docker inspect myapp | grep -A 10 "Memory"
```

### Top Processes

```bash
docker top myapp
```

---

## Quick Reference

### Image Size Targets

| Type | Target Size |
|------|-------------|
| Go binary | 5-20 MB |
| Node.js | 50-150 MB |
| Python | 50-200 MB |
| Java | 100-300 MB |

### Optimization Checklist

- [ ] Multi-stage build
- [ ] Alpine base image
- [ ] Minimal dependencies
- [ ] Layer caching optimized
- [ ] .dockerignore present
- [ ] No root user
- [ ] Health check defined
- [ ] Resource limits set
- [ ] Secrets externalized
- [ ] Logs configured

---

**Remember**: Optimization is about balance - size, speed, and security!
