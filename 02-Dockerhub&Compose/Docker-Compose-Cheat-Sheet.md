# Docker Compose Cheat Sheet
## Quick Reference for Multi-Container Applications

---

## Essential Commands

```bash
# Start services (detached)
docker compose up -d

# Start with build
docker compose up --build -d

# Stop services
docker compose stop

# Stop and remove containers
docker compose down

# Stop and remove containers + volumes
docker compose down -v

# Stop and remove containers + images
docker compose down --rmi all
```

---

## Viewing & Monitoring

```bash
# List running services
docker compose ps

# List all (including stopped)
docker compose ps -a

# View logs (all services)
docker compose logs

# Follow logs
docker compose logs -f

# Logs for specific service
docker compose logs -f web

# View last 100 lines
docker compose logs --tail=100
```

---

## Service Management

```bash
# Restart services
docker compose restart

# Restart specific service
docker compose restart web

# Stop specific service
docker compose stop web

# Start specific service
docker compose start web

# Pause services
docker compose pause

# Unpause services
docker compose unpause
```

---

## Execution & Interaction

```bash
# Execute command in running service
docker compose exec web sh

# Execute one-off command
docker compose run web python manage.py migrate

# Scale services
docker compose up -d --scale web=3

# Build services
docker compose build

# Build specific service
docker compose build web

# Build without cache
docker compose build --no-cache
```

---

## docker-compose.yml Reference

### Basic Structure

```yaml
version: '3.8'

services:
  servicename:
    # Service configuration

volumes:
  volumename:
    # Volume configuration

networks:
  networkname:
    # Network configuration
```

### Service Configuration

```yaml
services:
  web:
    # Build from Dockerfile
    build: .
    # Or build with context
    build:
      context: ./dir
      dockerfile: Dockerfile.dev
    
    # Use existing image
    image: nginx:alpine
    
    # Container name
    container_name: my-web
    
    # Ports (host:container)
    ports:
      - "8080:80"
      - "443:443"
    
    # Environment variables
    environment:
      NODE_ENV: production
      API_KEY: abc123
    
    # Environment file
    env_file:
      - .env
      - .env.prod
    
    # Volumes
    volumes:
      - ./code:/app
      - data-volume:/var/lib/data
      - /host/path:/container/path:ro  # read-only
    
    # Networks
    networks:
      - frontend
      - backend
    
    # Dependencies
    depends_on:
      - db
      - cache
    
    # Command override
    command: python app.py --debug
    
    # Entrypoint override
    entrypoint: /app/entrypoint.sh
    
    # Working directory
    working_dir: /app
    
    # Restart policy
    restart: unless-stopped  # no, always, on-failure
    
    # Health check
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost/health"]
      interval: 30s
      timeout: 3s
      retries: 3
      start_period: 40s
    
    # Resource limits
    deploy:
      resources:
        limits:
          cpus: '1.0'
          memory: 512M
        reservations:
          cpus: '0.5'
          memory: 256M
```

### Networks

```yaml
networks:
  frontend:
    driver: bridge
  
  backend:
    driver: bridge
    internal: true  # No external access
  
  custom:
    driver: bridge
    ipam:
      driver: default
      config:
        - subnet: 172.28.0.0/16
```

### Volumes

```yaml
volumes:
  # Named volume
  data:
    driver: local
  
  # External volume
  external-data:
    external: true
  
  # NFS volume
  nfs-data:
    driver: local
    driver_opts:
      type: nfs
      o: addr=10.0.0.1,rw
      device: ":/path/to/dir"
```

---

## Advanced Features

### Using Multiple Compose Files

```bash
# Override with additional file
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d

# Environment-specific
docker compose -f docker-compose.yml -f docker-compose.dev.yml up
```

### Variable Substitution

```yaml
services:
  web:
    image: nginx:${NGINX_VERSION:-latest}
    ports:
      - "${WEB_PORT:-8080}:80"
    environment:
      DB_HOST: ${DB_HOST}
```

### Extension Fields

```yaml
x-common-variables: &common-vars
  NODE_ENV: production
  LOG_LEVEL: info

services:
  web:
    environment:
      <<: *common-vars
      SERVICE: web
  
  api:
    environment:
      <<: *common-vars
      SERVICE: api
```

---

## Common Patterns

### Web App + Database

```yaml
version: '3.8'

services:
  app:
    build: .
    ports:
      - "5000:5000"
    environment:
      DATABASE_URL: postgresql://user:pass@db:5432/dbname
    depends_on:
      - db

  db:
    image: postgres:14-alpine
    environment:
      POSTGRES_DB: dbname
      POSTGRES_USER: user
      POSTGRES_PASSWORD: pass
    volumes:
      - db-data:/var/lib/postgresql/data

volumes:
  db-data:
```

### Development with Live Reload

```yaml
services:
  app:
    build: .
    volumes:
      - ./src:/app/src  # Bind mount for live reload
      - node_modules:/app/node_modules  # Don't override
    environment:
      NODE_ENV: development

volumes:
  node_modules:
```

### Production with Health Checks

```yaml
services:
  app:
    image: myapp:${VERSION}
    restart: always
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost/health"]
      interval: 30s
      timeout: 10s
      retries: 3
    deploy:
      resources:
        limits:
          cpus: '2.0'
          memory: 1G
```

---

## Troubleshooting

```bash
# View config (resolved)
docker compose config

# Validate compose file
docker compose config --quiet

# Check service status
docker compose ps

# Inspect service
docker compose exec web env

# View networks
docker network ls
docker network inspect myapp_default

# View volumes
docker volume ls
docker volume inspect myapp_data

# Remove orphaned containers
docker compose up --remove-orphans

# Force recreate containers
docker compose up -d --force-recreate

# Pull latest images
docker compose pull
```

---

## Best Practices

### ✅ DO

- Use specific image versions
- Implement health checks
- Use named volumes for data
- Set resource limits
- Use restart policies
- Define custom networks
- Use .env for secrets (not in git)
- Document with comments

### ❌ DON'T

- Use `latest` tag in production
- Expose database ports to host
- Store secrets in compose file
- Run as root user
- Skip health checks
- Ignore resource limits
- Commit .env files
- Use deprecated version syntax

---

## Quick Tips

```bash
# Save space - remove unused volumes
docker volume prune

# Remove everything
docker compose down -v --rmi all

# Check what will be created
docker compose config

# Run command without starting services
docker compose run --rm web python manage.py test

# View resource usage
docker stats $(docker compose ps -q)
```

---

**Keep this handy for quick reference! 📋**
