# Docker Security Best Practices
## Production-Grade Container Security

---

## Image Security

### 1. Use Official Base Images

```dockerfile
# ✓ Official, verified
FROM python:3.9-alpine
FROM node:16-alpine
FROM postgres:14-alpine

# ❌ Avoid unknown sources
FROM random-user/python
```

### 2. Pin Specific Versions

```dockerfile
# ❌ Unstable
FROM python:latest
FROM node:16

# ✓ Specific, predictable
FROM python:3.9.18-alpine3.18
FROM node:16.20.2-alpine3.18
```

### 3. Scan for Vulnerabilities

```bash
# Scan images
docker scan myapp:latest

# Scan during build (CI/CD)
docker build -t myapp .
docker scan myapp
```

---

## Runtime Security

### 1. Never Run as Root

```dockerfile
# Create non-root user
RUN addgroup -S appgroup && \
    adduser -S appuser -G appgroup

# Switch to non-root
USER appuser

# Verify
RUN whoami  # Should output: appuser
```

### 2. Read-Only Root Filesystem

```bash
docker run --read-only \
  --tmpfs /tmp:rw,noexec,nosuid \
  --tmpfs /var/run:rw,noexec,nosuid \
  myapp
```

```yaml
# Docker Compose
services:
  app:
    read_only: true
    tmpfs:
      - /tmp
      - /var/run
```

### 3. Drop Capabilities

```bash
docker run --cap-drop=ALL \
  --cap-add=NET_BIND_SERVICE \
  myapp
```

### 4. Limit Resources

```bash
docker run \
  --memory="512m" \
  --memory-swap="512m" \
  --cpus="1.0" \
  --pids-limit=100 \
  myapp
```

---

## Network Security

### 1. Isolate Networks

```yaml
services:
  frontend:
    networks:
      - public

  backend:
    networks:
      - public
      - private

  database:
    networks:
      - private  # Not exposed to frontend

networks:
  public:
  private:
    internal: true  # No external access
```

### 2. Don't Expose Unnecessary Ports

```dockerfile
# ❌ Exposes database to host
EXPOSE 5432

# ✓ Only expose application
EXPOSE 8080
```

### 3. Use TLS

```yaml
services:
  app:
    ports:
      - "443:443"
    volumes:
      - ./certs:/certs:ro
    environment:
      TLS_CERT: /certs/server.crt
      TLS_KEY: /certs/server.key
```

---

## Secrets Management

### 1. Never Hardcode Secrets

```dockerfile
# ❌ NEVER do this
ENV DB_PASSWORD=mysecret
RUN echo "password=mysecret" > config.ini

# ✓ Use runtime injection
ENV DB_PASSWORD_FILE=/run/secrets/db_password
```

### 2. Use Docker Secrets (Swarm)

```bash
echo "mypassword" | docker secret create db_password -

docker service create \
  --secret db_password \
  --env DB_PASSWORD_FILE=/run/secrets/db_password \
  myapp
```

### 3. Environment Variables (Compose)

```yaml
services:
  app:
    environment:
      - DB_PASSWORD=${DB_PASSWORD}
      - API_KEY=${API_KEY}
```

```bash
# .env file (DO NOT COMMIT)
DB_PASSWORD=secret123
API_KEY=abc456
```

---

## Build Security

### 1. Multi-Stage Builds

```dockerfile
# Stage 1: Build (contains build tools)
FROM golang:1.21 AS builder
COPY . .
RUN go build -o app

# Stage 2: Runtime (minimal, no build tools)
FROM alpine:latest
COPY --from=builder /app/app .
USER nobody
CMD ["./app"]
```

### 2. Minimize Attack Surface

```dockerfile
# ❌ Bloated
FROM ubuntu:latest
RUN apt-get update && apt-get install -y \
    python3 python3-pip curl wget git gcc make

# ✓ Minimal
FROM python:3.9-alpine
RUN apk add --no-cache python3
```

### 3. Remove Setuid/Setgid Binaries

```dockerfile
RUN find / -perm /6000 -type f -exec chmod a-s {} \; || true
```

---

## Access Control

### 1. Least Privilege Principle

```dockerfile
# Set minimal permissions
COPY --chown=appuser:appgroup app.py /app/
RUN chmod 550 /app/app.py
```

### 2. File Permissions

```dockerfile
# Files: 644 (rw-r--r--)
# Directories: 755 (rwxr-xr-x)
# Executables: 755 (rwxr-xr-x)

RUN chmod -R 755 /app && \
    chmod 644 /app/*.py
```

---

## Logging & Monitoring

### 1. Centralized Logging

```yaml
services:
  app:
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
```

### 2. Don't Log Secrets

```python
# ❌ Never log secrets
logger.info(f"Using password: {password}")

# ✓ Log safely
logger.info("Authentication successful")
```

### 3. Health Checks

```dockerfile
HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
  CMD curl -f http://localhost:8080/health || exit 1
```

---