# Session 2: Hands-on Lab Guide
## Docker Hub and Docker Compose

**Objective**: Master Docker Hub operations and build production-ready multi-container applications

---

## Pre-Lab Checklist

Before starting, ensure:
- ✅ Docker is installed and running
- ✅ Completed Session 1 successfully
- ✅ Docker Hub account created and verified
- ✅ Internet connection active
- ✅ Terminal/Command Prompt open

---

## Lab 1: Docker Hub Operations

### Objective
Learn the complete workflow: build → tag → push → pull from Docker Hub

### Step 1: Login to Docker Hub

```bash
docker login
```

**Prompts:**
```
Username: <your-docker-id>
Password: <your-password>
```

**Expected Output:**
```
Login Succeeded

Logging in with your password grants your terminal complete access to your account.
For better security, log in with a limited-privilege personal access token.
```

✅ **Success:** You're now authenticated!

### Step 2: Create a Simple Application

```bash
mkdir docker-hub-demo && cd docker-hub-demo
```

Create `app.py`:
```python
from datetime import datetime

def main():
    print("=" * 50)
    print("Hello from Docker Hub!")
    print(f"Current time: {datetime.now()}")
    print(f"This image was pulled from Docker Hub")
    print("=" * 50)

if __name__ == "__main__":
    main()
```

Create `Dockerfile`:
```dockerfile
FROM python:3.9-alpine

WORKDIR /app

COPY app.py .

CMD ["python", "app.py"]
```

### Step 3: Build the Image

```bash
docker build -t hub-demo-app .
```

**Expected Output:**
```
[+] Building 5.2s (8/8) FINISHED
 => [1/3] FROM docker.io/library/python:3.9-alpine
 => [2/3] WORKDIR /app
 => [3/3] COPY app.py .
 => exporting to image
Successfully built abc123def456
Successfully tagged hub-demo-app:latest
```

Test locally:
```bash
docker run hub-demo-app
```

### Step 4: Tag for Docker Hub

**Important:** Replace `YOUR-USERNAME` with your actual Docker Hub username!

```bash
# Tag with version
docker tag hub-demo-app:latest YOUR-USERNAME/hub-demo-app:v1.0

# Tag as latest
docker tag hub-demo-app:latest YOUR-USERNAME/hub-demo-app:latest

# Tag with date
docker tag hub-demo-app:latest YOUR-USERNAME/hub-demo-app:$(date +%Y%m%d)
```

Verify tags:
```bash
docker images | grep hub-demo-app
```

**Expected Output:**
```
YOUR-USERNAME/hub-demo-app    v1.0        abc123...   2 min ago   52MB
YOUR-USERNAME/hub-demo-app    latest      abc123...   2 min ago   52MB
YOUR-USERNAME/hub-demo-app    20260206    abc123...   2 min ago   52MB
hub-demo-app                  latest      abc123...   2 min ago   52MB
```

### Step 5: Push to Docker Hub

```bash
docker push YOUR-USERNAME/hub-demo-app:v1.0
docker push YOUR-USERNAME/hub-demo-app:latest
docker push YOUR-USERNAME/hub-demo-app:$(date +%Y%m%d)
```

**Expected Output:**
```
The push refers to repository [docker.io/YOUR-USERNAME/hub-demo-app]
5f70bf18a086: Pushed
v1.0: digest: sha256:abc123... size: 1234
```

### Step 6: Verify on Docker Hub Website

1. Open browser: https://hub.docker.com
2. Login with your credentials
3. Click "Repositories"
4. You should see `hub-demo-app`
5. Click on it to view:
   - All tags (v1.0, latest, date)
   - Image size
   - Last updated time

✅ **Success Criteria:** Your image is public on Docker Hub!

### Step 7: Simulate Pulling from Another Machine

Remove all local copies:
```bash
docker rmi YOUR-USERNAME/hub-demo-app:v1.0
docker rmi YOUR-USERNAME/hub-demo-app:latest
docker rmi YOUR-USERNAME/hub-demo-app:$(date +%Y%m%d)
docker rmi hub-demo-app:latest
```

Verify they're gone:
```bash
docker images | grep hub-demo-app
```

Now pull from Docker Hub:
```bash
docker pull YOUR-USERNAME/hub-demo-app:v1.0
```

**Expected Output:**
```
v1.0: Pulling from YOUR-USERNAME/hub-demo-app
...
Status: Downloaded newer image for YOUR-USERNAME/hub-demo-app:v1.0
docker.io/YOUR-USERNAME/hub-demo-app:v1.0
```

Run the pulled image:
```bash
docker run YOUR-USERNAME/hub-demo-app:v1.0
```

### Step 8: Clean Up

```bash
docker logout
cd ..
rm -rf docker-hub-demo
```

### ✅ Lab 1 Complete!
You've mastered the Docker Hub workflow: build → tag → push → pull!

---

## Lab 2: Two-Tier Flask + PostgreSQL Application

### Objective
Build a complete web application with database using Docker Compose.

### Step 1: Create Project Structure

```bash
mkdir flask-postgres-app && cd flask-postgres-app
```

### Step 2: Create Flask Application

Create `app.py`:
```python
from flask import Flask, jsonify, render_template_string
import psycopg2
import os
import time

app = Flask(__name__)

# Database configuration
DB_CONFIG = {
    'host': os.getenv('DB_HOST', 'db'),
    'database': os.getenv('DB_NAME', 'testdb'),
    'user': os.getenv('DB_USER', 'postgres'),
    'password': os.getenv('DB_PASSWORD', 'secret123')
}

# HTML template
HTML_TEMPLATE = '''
<!DOCTYPE html>
<html>
<head>
    <title>Flask + PostgreSQL</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            max-width: 800px;
            margin: 50px auto;
            padding: 20px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
        }
        .container {
            background: rgba(255,255,255,0.1);
            padding: 30px;
            border-radius: 10px;
            backdrop-filter: blur(10px);
        }
        button {
            background: #4CAF50;
            color: white;
            padding: 10px 20px;
            border: none;
            border-radius: 5px;
            cursor: pointer;
            font-size: 16px;
            margin: 5px;
        }
        button:hover { background: #45a049; }
        .status { margin: 20px 0; padding: 15px; background: rgba(255,255,255,0.2); border-radius: 5px; }
        .user-list { margin-top: 20px; }
        .user { padding: 10px; margin: 5px 0; background: rgba(255,255,255,0.15); border-radius: 5px; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🐘 Flask + PostgreSQL Demo</h1>
        <p>Multi-container application running with Docker Compose</p>
        
        <div>
            <button onclick="location.href='/health'">Check Health</button>
            <button onclick="location.href='/users'">View Users</button>
            <button onclick="location.href='/init'">Initialize Database</button>
        </div>
    </div>
</body>
</html>
'''

def get_db_connection():
    """Establish database connection with retry logic"""
    max_retries = 5
    retry_delay = 2
    
    for attempt in range(max_retries):
        try:
            conn = psycopg2.connect(**DB_CONFIG)
            return conn
        except psycopg2.OperationalError as e:
            if attempt < max_retries - 1:
                print(f"Database connection attempt {attempt + 1} failed. Retrying in {retry_delay}s...")
                time.sleep(retry_delay)
            else:
                raise

@app.route('/')
def home():
    return render_template_string(HTML_TEMPLATE)

@app.route('/health')
def health():
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute('SELECT version();')
        db_version = cursor.fetchone()[0]
        cursor.close()
        conn.close()
        
        return jsonify({
            'status': 'healthy',
            'database': 'connected',
            'postgres_version': db_version
        })
    except Exception as e:
        return jsonify({
            'status': 'unhealthy',
            'database': 'disconnected',
            'error': str(e)
        }), 500

@app.route('/init')
def init_db():
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # Create table
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS users (
                id SERIAL PRIMARY KEY,
                name VARCHAR(100),
                email VARCHAR(100),
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        ''')
        
        # Check if table is empty
        cursor.execute('SELECT COUNT(*) FROM users')
        count = cursor.fetchone()[0]
        
        if count == 0:
            # Insert sample data
            sample_users = [
                ('Alice Johnson', 'alice@example.com'),
                ('Bob Smith', 'bob@example.com'),
                ('Charlie Brown', 'charlie@example.com'),
                ('Diana Prince', 'diana@example.com'),
                ('Eve Davis', 'eve@example.com')
            ]
            
            cursor.executemany(
                'INSERT INTO users (name, email) VALUES (%s, %s)',
                sample_users
            )
            conn.commit()
            message = f'Database initialized with {len(sample_users)} users'
        else:
            message = f'Database already has {count} users'
        
        cursor.close()
        conn.close()
        
        return jsonify({
            'status': 'success',
            'message': message
        })
    except Exception as e:
        return jsonify({
            'status': 'error',
            'error': str(e)
        }), 500

@app.route('/users')
def users():
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        
        cursor.execute('SELECT id, name, email, created_at FROM users ORDER BY id')
        users_data = cursor.fetchall()
        
        cursor.close()
        conn.close()
        
        return jsonify({
            'count': len(users_data),
            'users': [
                {
                    'id': u[0],
                    'name': u[1],
                    'email': u[2],
                    'created_at': str(u[3])
                }
                for u in users_data
            ]
        })
    except Exception as e:
        return jsonify({
            'status': 'error',
            'error': str(e)
        }), 500

if __name__ == '__main__':
    print("Starting Flask application...")
    print(f"Database host: {DB_CONFIG['host']}")
    app.run(host='0.0.0.0', port=5000, debug=True)
```

### Step 3: Create Requirements File

Create `requirements.txt`:
```
Flask==3.0.0
psycopg2-binary==2.9.9
```

### Step 4: Create Dockerfile

Create `Dockerfile`:
```dockerfile
FROM python:3.9-slim

WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application
COPY app.py .

EXPOSE 5000

CMD ["python", "app.py"]
```

### Step 5: Create docker-compose.yml

Create `docker-compose.yml`:
```yaml
version: '3.8'

services:
  web:
    build: .
    container_name: flask-app
    ports:
      - "5000:5000"
    environment:
      DB_HOST: db
      DB_NAME: testdb
      DB_USER: postgres
      DB_PASSWORD: secret123
    depends_on:
      - db
    networks:
      - app-network
    restart: unless-stopped

  db:
    image: postgres:14-alpine
    container_name: postgres-db
    environment:
      POSTGRES_DB: testdb
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: secret123
    volumes:
      - postgres-data:/var/lib/postgresql/data
    networks:
      - app-network
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 10s
      timeout: 5s
      retries: 5

volumes:
  postgres-data:
    driver: local

networks:
  app-network:
    driver: bridge
```

### Step 6: Start the Application

```bash
docker compose up -d
```

**Expected Output:**
```
[+] Running 4/4
 ✔ Network flask-postgres-app_app-network       Created
 ✔ Volume "flask-postgres-app_postgres-data"    Created
 ✔ Container postgres-db                        Started
 ✔ Container flask-app                          Started
```

### Step 7: Verify Services are Running

```bash
docker compose ps
```

**Expected Output:**
```
NAME           IMAGE                      STATUS         PORTS
flask-app      flask-postgres-app-web     Up 10 seconds  0.0.0.0:5000->5000/tcp
postgres-db    postgres:14-alpine         Up 11 seconds  5432/tcp
```

### Step 8: Test the Application

Open browser and visit:
- **http://localhost:5000** - Home page
- Click "Initialize Database" button
- Click "View Users" to see JSON data
- **http://localhost:5000/health** - Database health check

Or use curl:
```bash
curl http://localhost:5000/health
curl http://localhost:5000/init
curl http://localhost:5000/users
```

✅ **Success Criteria:**
- Home page loads with styled interface
- Health endpoint shows database connection
- Users endpoint returns 5 sample users

### Step 9: View Logs

```bash
# All services
docker compose logs

# Specific service
docker compose logs web
docker compose logs db

# Follow logs in real-time
docker compose logs -f web
```

Press `Ctrl+C` to stop following logs.

### Step 10: Execute Commands in Containers

**Connect to PostgreSQL:**
```bash
docker compose exec db psql -U postgres -d testdb
```

Inside PostgreSQL, try:
```sql
\dt                          -- List tables
SELECT * FROM users;         -- View all users
SELECT COUNT(*) FROM users;  -- Count users
\q                           -- Quit
```

**Get shell in web container:**
```bash
docker compose exec web /bin/bash
```

Inside container:
```bash
ls -la
env | grep DB_
exit
```

### Step 11: Test Data Persistence

Stop containers:
```bash
docker compose stop
```

Start again:
```bash
docker compose start
```

Visit http://localhost:5000/users - data is still there! ✅

### Step 12: Complete Cleanup

```bash
# Stop and remove containers (keeps volumes)
docker compose down

# Stop and remove everything including volumes
docker compose down -v
```

### ✅ Lab 2 Complete!
You've built a production-ready two-tier application!

---

## Lab 3: Environment-Specific Configurations

### Objective
Learn to use different configurations for development vs production.

### Step 1: Create Environment Files

In `flask-postgres-app` directory:

Create `.env.dev`:
```env
DB_HOST=db
DB_NAME=devdb
DB_USER=postgres
DB_PASSWORD=devpassword123
FLASK_ENV=development
LOG_LEVEL=DEBUG
```

Create `.env.prod`:
```env
DB_HOST=db
DB_NAME=proddb
DB_USER=postgres
DB_PASSWORD=prod_secure_password_456
FLASK_ENV=production
LOG_LEVEL=WARNING
```

### Step 2: Update docker-compose.yml

Modify the `web` service to use env files:

```yaml
services:
  web:
    build: .
    env_file:
      - .env.dev  # or .env.prod
    ports:
      - "5000:5000"
    depends_on:
      - db
    networks:
      - app-network
```

### Step 3: Test Development Configuration

```bash
# Using development env
docker compose --env-file .env.dev up -d

# Check environment variables
docker compose exec web env | grep DB_
docker compose exec web env | grep FLASK_

docker compose down
```

### Step 4: Test Production Configuration

```bash
# Using production env
docker compose --env-file .env.prod up -d

# Check environment variables
docker compose exec web env | grep DB_
docker compose exec web env | grep FLASK_

docker compose down
```

**Benefit:** Same compose file, different configurations! ✅

### ✅ Lab 3 Complete!
Environment-specific configs mastered!

---