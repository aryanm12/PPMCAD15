# Session 1: Hands-on Lab Guide
## Introduction to Containers and Docker
 
**Objective**: Practice essential Docker commands and build your first container

---

## Pre-Lab Checklist

Before starting, ensure:
- ✅ Docker is installed and running
- ✅ You can run: `docker --version`
- ✅ You have internet connection
- ✅ Terminal/Command Prompt is open

---

## Lab 1: Your First Container

### Objective
Learn to pull and run a pre-built container, then interact with it through your browser.

### Step 1: Pull the nginx Image

```bash
docker pull nginx:alpine
```

**Expected Output:**
```
alpine: Pulling from library/nginx
...
Status: Downloaded newer image for nginx:alpine
```

**What's happening?**
- Downloads the nginx web server image from Docker Hub
- `alpine` is a lightweight Linux distribution
- Image is very small! (check the size)

### Step 2: Run the Container

```bash
docker run -d -p 8080:80 --name my-nginx nginx:alpine
```

**Command breakdown:**
- `-d` = detached mode (runs in background)
- `-p 8080:80` = map host port 8080 to container port 80
- `--name my-nginx` = give container a friendly name
- `nginx:alpine` = the image to use

**Expected Output:**
```
a1b2c3d4e5f6... (container ID)
```

### Step 3: Verify Container is Running

```bash
docker ps
```

**Expected Output:**
```
CONTAINER ID   IMAGE          COMMAND                  CREATED         STATUS         PORTS                  NAMES
a1b2c3d4e5f6   nginx:alpine   "/docker-entrypoint.…"   10 seconds ago  Up 9 seconds   0.0.0.0:8080->80/tcp   my-nginx
```

### Step 4: Access via Browser

Open your browser and visit: **http://localhost:8080**

✅ **Success Criteria**: You should see "Welcome to nginx!" page

### Step 5: View Container Logs

```bash
docker logs my-nginx
```

**Expected Output:**
```
/docker-entrypoint.sh: Launching /docker-entrypoint.d/...
...
nginx: [notice] start worker processes
```

### Step 6: Stop the Container

```bash
docker stop my-nginx
```

**Verify it stopped:**
```bash
docker ps
```

Should show no running containers.

### Step 7: View All Containers (Including Stopped)

```bash
docker ps -a
```

You'll see `my-nginx` with STATUS "Exited"

### Step 8: Remove the Container

```bash
docker rm my-nginx
```

**Verify removal:**
```bash
docker ps -a
```

`my-nginx` should be gone.

### ✅ Lab 1 Complete!
You've successfully pulled, run, accessed, stopped, and removed a Docker container.

---

## Lab 2: Exploring Containers

### Objective
Learn to execute commands inside running containers and inspect their details.

### Step 1: Start nginx Again (in Detached Mode)

```bash
docker run -d -p 8080:80 --name web-server nginx:alpine
```

### Step 2: Execute Commands Inside the Container

```bash
docker exec web-server ls /usr/share/nginx/html
```

**Expected Output:**
```
<some>.html
index.html
```

These are nginx's default HTML files.

### Step 3: Get an Interactive Shell

```bash
docker exec -it web-server /bin/sh
```

**You're now inside the container!** Prompt will look like:
```
/ #
```

Try these commands inside the container:
```sh
pwd                    # See current directory
ls                     # List files
cat /etc/os-release    # See OS info
exit                   # Exit the shell
```

### Step 4: View Real-time Logs

```bash
docker logs -f web-server
```

Keep this running and visit `http://localhost:8080` in your browser.

**You'll see:**
```
172.17.0.1 - - [date] "GET / HTTP/1.1" 200 ...
```

Press `Ctrl+C` to stop following logs.

### Step 5: Inspect Container Details

```bash
docker inspect web-server
```

**Expected Output:** Large JSON object with configuration details.

To extract specific info:
```bash
# Get IP address
docker inspect web-server --format='{{.NetworkSettings.IPAddress}}'

# Get container status
docker inspect web-server --format='{{.State.Status}}'
```

### Step 6: View Container Resource Usage

```bash
docker stats web-server
```

**Expected Output:**
```
CONTAINER ID   NAME         CPU %     MEM USAGE / LIMIT   NET I/O       BLOCK I/O
a1b2c3d4e5f6   web-server   0.00%     2.5MiB / 7.7GiB     1.2kB / 648B  0B / 0B
```

Press `Ctrl+C` to stop.

### Step 7: Clean Up

```bash
docker stop web-server
docker rm web-server
```

### ✅ Lab 2 Complete!
You can now interact with running containers like a pro!

---

## Lab 3: Volumes & Data Persistence

### Objective
Understand data persistence with volumes.

### Step 1: Demonstrate Data Loss Without Volumes

```bash
# Run container and create data
docker run -it --name temp-container alpine sh

# Inside container:
echo "Important data!" > /data.txt
cat /data.txt
exit

# Remove container
docker rm temp-container

# Try to find the data - IT'S GONE!
```

**Problem:** Data is lost when container is deleted!

### Step 2: Create a Named Volume

```bash
# Create volume
docker volume create my-data

# List volumes
docker volume ls

# Inspect volume
docker volume inspect my-data
```

### Step 3: Use Volume for Persistence

```bash
# Run container with volume
docker run -it --name persistent-container \
  -v my-data:/app/data \
  alpine sh

# Inside container:
cd /app/data
echo "This will persist!" > important.txt
echo "Even after container deletion!" >> important.txt
cat important.txt
exit
```

### Step 4: Verify Data Persists

```bash
# Remove the container
docker rm persistent-container

# Create NEW container with SAME volume
docker run -it --name new-container \
  -v my-data:/app/data \
  alpine sh

# Inside NEW container:
cd /app/data
cat important.txt
# DATA IS STILL THERE!
exit
```

### Step 5: Bind Mount Example (Development)

```bash
# Create a directory on host
mkdir ~/docker-demo
cd ~/docker-demo
echo "Hello from host!" > index.html

# Mount host directory into container
docker run -d --name web-server \
  -v $(pwd):/usr/share/nginx/html \
  -p 8080:80 \
  nginx

# Visit http://localhost:8080
# You'll see your HTML file!

# Edit file on host
echo "<h1>Updated from host!</h1>" > index.html

# Refresh browser - changes appear immediately!

# Cleanup
docker stop web-server
docker rm web-server
```

### Step 6: Volume Cleanup

```bash
# List volumes
docker volume ls

# Remove specific volume
docker volume rm my-data

# Remove all unused volumes
docker volume prune
```

✅ **Lab 3 Complete!**  
Volumes persist data across container lifecycles!


---

## Lab 4: Build Your First Image

### Objective
Create a simple Python Flask web application and containerize it.

### Step 1: Create Project Directory

```bash
mkdir my-first-app
cd my-first-app
```

### Step 2: Create Application Code

Create a file named `app.py`:

```python
from flask import Flask

app = Flask(__name__)

@app.route('/')
def hello():
    return '''
    <h1>Hello from Docker!</h1>
    <p>This is my first containerized application.</p>
    <p>Container technology is awesome! 🐳</p>
    '''

@app.route('/about')
def about():
    return '<h2>About: This app is running in a Docker container</h2>'

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)
```

### Step 3: Create Requirements File

Create `requirements.txt`:

```
Flask==2.3.0
```

### Step 4: Write Your Dockerfile

Create a file named `Dockerfile` (no extension):

```dockerfile
# Use official Python runtime as base image
FROM python:3.9-slim

# Set working directory in container
WORKDIR /app

# Copy requirements file
COPY requirements.txt .

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY app.py .

# Expose port 5000
EXPOSE 5000

# Command to run the application
CMD ["python", "app.py"]
```

### Step 5: Build the Docker Image

```bash
docker build -t my-flask-app:v1.0 .
```

**Command breakdown:**
- `build` = build an image
- `-t my-flask-app:v1.0` = tag/name the image
- `.` = build context (current directory)

**Expected Output:**
```
[+] Building 12.3s (10/10) FINISHED
 => [1/5] FROM docker.io/library/python:3.9-slim
 => [2/5] WORKDIR /app
 => [3/5] COPY requirements.txt .
 => [4/5] RUN pip install --no-cache-dir -r requirements.txt
 => [5/5] COPY app.py .
 => exporting to image
Successfully built abc123def456
Successfully tagged my-flask-app:v1.0
```

### Step 6: Verify Image was Created

```bash
docker images
```

**Expected Output:**
```
REPOSITORY      TAG       IMAGE ID       CREATED         SIZE
my-flask-app    v1.0      abc123def456   1 minute ago    125MB
```

### Step 7: Run Your Container

```bash
docker run -d -p 5000:5000 --name flask-container my-flask-app:v1.0
```

### Step 8: Test Your Application

Open browser and visit:
- **http://localhost:5000** - Main page
- **http://localhost:5000/about** - About page

✅ **Success Criteria**: You see your custom HTML pages!

### Step 9: View Application Logs

```bash
docker logs flask-container
```

**Expected Output:**
```
 * Serving Flask app 'app'
 * Debug mode: on
 * Running on all addresses (0.0.0.0)
 * Running on http://127.0.0.1:5000
 * Running on http://172.17.0.2:5000
```

### Step 10: Make Changes (Rebuild Demo)

Edit `app.py` - change the main message:
```python
return '<h1>Hello from Docker - Updated!</h1>...'
```

Rebuild:
```bash
docker build -t my-flask-app:v1.1 .
```

**Notice:** Build is faster! Cached layers are reused.

Stop old container and run new version:
```bash
docker stop flask-container
docker rm flask-container
docker run -d -p 5000:5000 --name flask-container my-flask-app:v1.1
```

Refresh browser - see the update!

### ✅ Lab 4 Complete!
You've built and run your own Docker image!

---

## Lab 5: CMD vs ENTRYPOINT Practice

### Objective
Master the difference between CMD and ENTRYPOINT.

### Step 1: CMD Only

```bash
mkdir cmd-demo && cd cmd-demo
```

Create `Dockerfile`:
```dockerfile
FROM alpine
CMD ["echo", "Hello from CMD"]
```

```bash
# Build
docker build -t cmd-demo .

# Run normally - uses CMD
docker run cmd-demo

# Override CMD
docker run cmd-demo echo "Goodbye!"
docker run cmd-demo ls /
docker run cmd-demo whoami
```

**Key Learning:** CMD is easily overridden!

### Step 2: ENTRYPOINT Only

```bash
cd ..
mkdir entry-demo && cd entry-demo
```

Create `Dockerfile`:
```dockerfile
FROM alpine
ENTRYPOINT ["echo", "Fixed prefix:"]
```

```bash
# Build
docker build -t entry-demo .

# Run with different arguments
docker run entry-demo "Hello"
docker run entry-demo "Docker"
docker run entry-demo "World"
```

**Key Learning:** ENTRYPOINT is the fixed command, args are appended!

### Step 3: Both Together (Best Practice)

```bash
cd ..
mkdir ping-demo && cd ping-demo
```

Create `Dockerfile`:
```dockerfile
FROM alpine
RUN apk add --no-cache iputils
ENTRYPOINT ["ping", "-c", "3"]
CMD ["google.com"]
```

```bash
# Build
docker build -t ping-demo .

# Use default CMD (google.com)
docker run ping-demo

# Override CMD with different target
docker run ping-demo 8.8.8.8
docker run ping-demo localhost

# ENTRYPOINT (ping -c 3) stays the same!
```

**Key Learning:** ENTRYPOINT + CMD = Flexible yet predictable!

### Step 4: Real-World Example

```bash
cd ..
mkdir node-app && cd node-app
```

Create `Dockerfile`:
```dockerfile
FROM node:16-alpine
WORKDIR /app
ENTRYPOINT ["node"]
CMD ["--version"]
```

```bash
# Build
docker build -t node-runner .

# Show Node version (default CMD)
docker run node-runner

# Run different commands
docker run node-runner --help
docker run node-runner -e "console.log('Hello')"
```

### Step 5: Cleanup

```bash
cd ..
rm -rf cmd-demo entry-demo ping-demo node-app
```

✅ **Lab 5 Complete!**  
Use ENTRYPOINT for fixed executable, CMD for default arguments!

---

## Lab 6: Docker Networking Basics

### Objective
Understand container networking and communication.

### Step 1: Default Bridge Network

```bash
# Run two containers on default network
docker run -d --name container1 alpine sleep 1000
docker run -d --name container2 alpine sleep 1000

# Try to ping by name (won't work on default bridge)
docker exec container1 ping container2
# Fails! Default bridge doesn't have DNS
```

### Step 2: Create Custom Network

```bash
# Create custom bridge network
docker network create my-network

# List networks
docker network ls

# Inspect network
docker network inspect my-network
```

### Step 3: Run Containers on Custom Network

```bash
# Cleanup previous containers
docker rm -f container1 container2

# Run on custom network
docker run -d --name web --network my-network nginx
docker run -d --name api --network my-network alpine sleep 1000

# Now ping by name works!
docker exec api ping -c 3 web
# Success! DNS resolution works on custom networks
```

### Step 4: Multi-Container Communication Example

```bash
# Create network
docker network create app-network

# Run database
docker run -d \
  --name db \
  --network app-network \
  -e POSTGRES_PASSWORD=secret \
  postgres:14-alpine

# Run application that connects to database
docker run -d \
  --name app \
  --network app-network \
  -e DATABASE_HOST=db \
  -p 8080:80 \
  nginx

# Check they can communicate
docker exec app ping -c 3 db
```

**Key Learning:** Containers on same custom network can communicate by name!

### Step 5: Port Mapping Demonstration

```bash
# Run without port mapping
docker run -d --name web1 nginx
# Can't access from host!

# Run with port mapping
docker run -d --name web2 -p 8080:80 nginx
# Can access at http://localhost:8080

# Check what ports are mapped
docker port web2
```

### Step 6: Network Inspection

```bash
# See all containers on a network
docker network inspect app-network

# See networks a container is connected to
docker inspect app

# Disconnect from network
docker network disconnect app-network app

# Reconnect
docker network connect app-network app
```

### Step 7: Cleanup

```bash
docker rm -f web api db web1 web2
docker network rm my-network app-network
```

✅ **Lab 6 Complete!**  
Custom networks provide DNS and isolation!


---

## Lab 7: Container Management

### Objective
Practice managing multiple containers and cleaning up Docker resources.

### Step 1: List All Containers

```bash
# Running containers only
docker ps

# All containers (including stopped)
docker ps -a
```

### Step 2: Start a Stopped Container

If you still have the flask container:
```bash
docker stop flask-container
docker start flask-container
```

Check status:
```bash
docker ps
```

### Step 3: Restart a Container

```bash
docker restart flask-container
```

**Use case:** When application needs a fresh start without rebuilding.

### Step 4: View All Images

```bash
docker images
```

**Expected Output:**
```
REPOSITORY      TAG       IMAGE ID       CREATED          SIZE
my-flask-app    v1.1      xyz789abc123   2 minutes ago    125MB
my-flask-app    v1.0      abc123def456   15 minutes ago   125MB
nginx           alpine    def456ghi789   2 weeks ago      23MB
python          3.9-slim  ghi789jkl012   3 weeks ago      122MB
```

### Step 5: Remove Specific Image

```bash
docker rmi my-flask-app:v1.0
```

If you get an error (image in use), stop and remove the container first:
```bash
docker stop flask-container
docker rm flask-container
docker rmi my-flask-app:v1.0
```

### Step 6: Clean Up Unused Resources

```bash
# Remove all stopped containers
docker container prune

# Confirm with 'y' when prompted
```

```bash
# Remove unused images
docker image prune
```

```bash
# See disk usage
docker system df
```

### Step 7: Remove Everything

⚠️ **Careful:** This removes ALL unused Docker resources!

```bash
docker system prune -a
```

Type `y` to confirm.

### ✅ Lab 7 Complete!
You know how to manage Docker resources efficiently!

---

## Lab 8: Debugging Exercise

### Objective
Learn to identify and fix common Dockerfile errors.

### Step 1: Create Broken Dockerfile

Create a new directory:
```bash
mkdir debug-exercise
cd debug-exercise
```

Create `app.py`:
```python
print("Hello from Python!")
```

Create this **intentionally broken** `Dockerfile`:

```dockerfile
FROM python:3.9-slim

WORKDIR /application

COPY app.py /app/

CMD ["python", "app.py"]
```

### Step 2: Build and Identify the Problem

```bash
docker build -t debug-app .
```

Build succeeds. Now run it:
```bash
docker run debug-app
```

**Error:**
```
python: can't open file '/app/app.py': [Errno 2] No such file or directory
```

### Step 3: Debug the Issue

**Question:** Why can't it find the file?

**Hints:**
- Check the WORKDIR
- Check where COPY puts the file
- Check what CMD is trying to run

**Problem:** 
- WORKDIR is `/application`
- COPY puts file in `/app/`
- CMD tries to run from WORKDIR (`/application/app.py`)

### Step 4: Fix the Dockerfile

**Solution 1:** Match the paths
```dockerfile
FROM python:3.9-slim

WORKDIR /app

COPY app.py .

CMD ["python", "app.py"]
```

**Solution 2:** Use absolute path
```dockerfile
FROM python:3.9-slim

WORKDIR /application

COPY app.py /app/

CMD ["python", "/app/app.py"]
```

### Step 5: Rebuild and Test

```bash
docker build -t debug-app-fixed .
docker run debug-app-fixed
```

**Expected Output:**
```
Hello from Python!
```

✅ **Success!**

### Step 6: Another Common Error

Create this Dockerfile:
```dockerfile
FROM python:3.9-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY app.py .
CMD ["python", "app.py"]
```

Try to build:
```bash
docker build -t test-app .
```

**Error:**
```
COPY failed: file not found in build context
```

**Problem:** `requirements.txt` doesn't exist!

**Fix:** Either create the file or remove those lines if not needed.

### ✅ Lab 8 Complete!
You can now debug Docker build errors!

---

### Key Commands to Remember

```bash
# Images
docker pull <image>       # Download image
docker build -t <name> .  # Build image
docker images             # List images

# Containers
docker run <image>        # Create and start
docker ps                 # List running
docker ps -a              # List all
docker stop <id>          # Stop container
docker rm <id>            # Remove container

# Interaction
docker logs <id>          # View logs
docker exec -it <id> sh   # Get shell
docker inspect <id>       # Detailed info

# Cleanup
docker system prune       # Remove unused resources
```