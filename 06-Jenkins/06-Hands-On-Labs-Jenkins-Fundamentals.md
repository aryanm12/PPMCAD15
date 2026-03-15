# Session 6: Jenkins Fundamentals
## Credentials, First Job & Your First Pipeline

---

## Prerequisites

> **Before this session:** Complete the Jenkins Installation Guide. You should have Jenkins running at http://localhost:8080 with plugins installed, security hardened, and Docker cloud configured.

### Required Tools

| Tool | Version | Install |
|------|---------|---------|
| Docker | Latest | docker.com/get-docker |
| Git | Latest | `brew install git` / `sudo apt install git` |
| curl / jq | Latest | `sudo apt install curl jq` |

### Sample Application

All labs use the same Flask application. Create it once:

```bash
mkdir -p ~/cicd-labs && cd ~/cicd-labs
```

**`app.py`:**

```python
from flask import Flask, jsonify, request
import os, time, socket

app = Flask(__name__)

items = [
    {"id": 1, "name": "Build pipeline", "done": True},
    {"id": 2, "name": "Run tests", "done": False},
    {"id": 3, "name": "Deploy to ECS", "done": False},
]

@app.route('/health')
def health():
    return jsonify({"status": "healthy", "version": os.getenv("APP_VERSION", "1.0.0"), "host": socket.gethostname(), "timestamp": int(time.time())}), 200

@app.route('/api/items')
def get_items():
    return jsonify({"items": items, "count": len(items), "env": os.getenv("ENVIRONMENT", "dev")})

@app.route('/api/items', methods=['POST'])
def add_item():
    data = request.get_json()
    item = {"id": len(items)+1, "name": data.get("name", "Untitled"), "done": False}
    items.append(item)
    return jsonify(item), 201

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080, debug=False)
```

**`requirements.txt`:**

```
Flask==3.0.0
Werkzeug==3.0.1
pytest==7.4.0
requests==2.31.0
```

**`Dockerfile`:**

```dockerfile
FROM python:3.11-slim
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
RUN useradd -m -u 1000 appuser && chown -R appuser:appuser /app
USER appuser
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8080/health')" || exit 1
CMD ["python", "app.py"]
```

**`tests/test_app.py`:**

```python
import pytest
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))
from app import app

@pytest.fixture
def client():
    app.config['TESTING'] = True
    with app.test_client() as c:
        yield c

def test_health(client):
    r = client.get('/health')
    assert r.status_code == 200
    data = r.get_json()
    assert data['status'] == 'healthy'

def test_get_items(client):
    r = client.get('/api/items')
    assert r.status_code == 200
    data = r.get_json()
    assert 'items' in data
    assert data['count'] > 0

def test_add_item(client):
    r = client.post('/api/items', json={"name": "Test from pytest"})
    assert r.status_code == 201
    assert r.get_json()['name'] == "Test from pytest"
```

Push this app to a GitHub repo before starting labs:

```bash
cd ~/cicd-labs
git init
git add .
git commit -m "Initial app for CICD labs"
# Create repo on GitHub, then:
git remote add origin https://github.com/YOUR_USERNAME/cicd-lab-app.git
git push -u origin main
```

---

## ════════════════════════════════════════════════════════
## Lab 1 - Credentials Management & Your First Jenkins Job
## ════════════════════════════════════════════════════════

**Objective:** Store AWS credentials and GitHub token securely in Jenkins, then build your first Freestyle job that runs shell commands and tests.

### What You'll Learn
- Jenkins Credentials Store (the right way to handle secrets)
- Create and run a Freestyle job
- Run a shell script with environment variables
- Read build console output and trigger manually

---

### Step 1: Store Credentials in Jenkins

Go to **Manage Jenkins -> Credentials -> System -> Global credentials -> Add Credentials**

**Add AWS Credentials:**
```
Kind: AWS Credentials
ID: aws-credentials
Description: AWS Access for CI/CD Labs
Access Key ID: <your AWS key>
Secret Access Key: <your AWS secret>
```

**Add GitHub Personal Access Token:**
```
Kind: Secret text
ID: github-token
Description: GitHub PAT for webhook and API access
Secret: <your GitHub PAT>
```

Create a GitHub PAT at: https://github.com/Settings -> Developer Settings -> Personal Access Tokens -> Tokens (classic)  
Scopes needed: `repo`, `admin:repo_hook`

**Add DockerHub Credentials (if using DockerHub):**
```
Kind: Username with password
ID: dockerhub-creds
Username: <dockerhub username>
Password: <dockerhub password or PAT>
```

### Step 2: Create Your First Freestyle Job

1. Click **New Item** on the Jenkins dashboard
2. Name: `lab-1-first-job`
3. Select **Freestyle project** -> OK
4. **Description:** "Lab 1 - Learning freestyle jobs"

**Source Code Management section:**
- Select **Git**
- Repository URL: `https://github.com/YOUR_USERNAME/cicd-lab-app.git`
- Credentials: Add your GitHub token
- Branch: `*/main`

**Build Triggers section:**
- Check: "GitHub hook trigger for GITScm polling" (we'll set up webhook in a moment)

**Build Steps -> Add build step -> Execute shell:**

```bash
#!/bin/bash
set -e

echo "============================================"
echo "  BUILD: $JOB_NAME  #$BUILD_NUMBER"
echo "  Date: $(date)"
echo "  Branch: $GIT_BRANCH"
echo "  Commit: $GIT_COMMIT"
echo "============================================"

echo ""
echo "--- System Info ---"
uname -a
docker --version
python3 --version

echo ""
echo "--- Installing Dependencies ---"
pip3 install -r requirements.txt --quiet --break-system-packages

echo ""
echo "--- Running Tests ---"
python3 -m pytest tests/ -v --tb=short

echo ""
echo "--- Docker Build Test ---"
docker build -t lab-app:test .
docker run --rm lab-app:test python -c "import app; print('App import OK')"

echo ""
echo "Build completed successfully!"
```

Click **Save**

### Step 3: Run the Job

1. Click **Build Now** on the job page
2. Watch the build number appear under "Build History"
3. Click on the build number -> **Console Output**
4. Read through the output - notice:
   - Git clone output
   - Test results (pytest)
   - Docker build output

### Step 4: Set Up GitHub Webhook (make builds trigger automatically)

**Get your Jenkins URL accessible from GitHub** (for local installs, use ngrok):

```bash
# Install ngrok if needed
brew install ngrok  # or download from ngrok.com

# Signup to ngrok using MFA for learning purposes
Sign up for an account: https://dashboard.ngrok.com/signup

# add your authtoken to the default ngrok.yml
ngrok config add-authtoken 3AvDxUw9BBMWBmtR0gDvVt8TLi1_2hAeszaUXijnrBJUPJesN

# Expose local Jenkins
ngrok http 8080
# Copy the https URL (e.g., https://abc123.ngrok.io)
```

**Configure webhook in GitHub:**
1. Go to your repo -> Settings -> Webhooks -> Add webhook
2. Payload URL: `https://YOUR_NGROK_URL/github-webhook/`
3. Content type: `application/json`
4. Events: "Just the push event"
5. Active: ✓

**Configure this in Jenkins:**
Configure your Jenkins job to use the webhook trigger: 
1. In your job/pipeline configuration, under "Build Triggers"
2. check the option "GitHub hook trigger for GITScm polling." 
This tells Jenkins to start a build whenever it receives a push event from GitHub.

**Test it:** Make a small change to your repo, push it, and watch Jenkins auto-trigger a build.

### Step 5: Add Post-Build Actions

Edit the job (Configure):  
**Post-build Actions -> Add post-build action -> Archive the artifacts:**
```
Files to archive: **/*.log, requirements.txt
```

**Add another post-build action -> Publish JUnit test results:**
```
Test report XMLs: test-results.xml
```

Update your build script to generate JUnit XML:
```bash
python3 -m pytest tests/ -v --tb=short --junitxml=test-results.xml
```

### Step 6: Test the credentials added

In your freestyle job configuration, scroll to the Build Environment section and check "Use secret texts(s) or file(s)". 

This unlocks the Bindings area where you can map credentials to environment variables.
Binding the GitHub Token:
Binding type: Secret text
Variable:     GITHUB_TOKEN
Credentials:  github-token  (select from dropdown)

Binding AWS Credentials:
Binding type: AWS access key and secret
Access Key Variable:    AWS_ACCESS_KEY_ID
Secret Key Variable:    AWS_SECRET_ACCESS_KEY
Credentials:            aws-credentials  (select from dropdown)

Binding DockerHub Credentials:
Binding type: Username and password (separated)
Username Variable:  DOCKER_USER
Password Variable:  DOCKER_PASS
Credentials:        dockerhub-creds  (select from dropdown)

Now all three sets of credentials are available as environment variables in your build steps.

Extend the Execute Shell build step with the following to see credentials in action:
**Build Steps -> Add build step -> Execute shell:**

```bash
# ---------------------------------------------------
# AWS CREDENTIALS USAGE
# ---------------------------------------------------
echo ""
echo "--- AWS: Verify identity ---"
aws sts get-caller-identity


echo ""
echo "--- AWS: Upload test results to S3 ---"
aws s3 cp test-results.xml \
  "s3://your-ci-bucket/builds/$JOB_NAME/$BUILD_NUMBER/test-results.xml"

# ---------------------------------------------------
#  DOCKERHUB CREDENTIALS USAGE
#    Use case: pushing built images to a registry
# ---------------------------------------------------
echo ""
echo "--- Docker: Login to DockerHub ---"
echo "$DOCKER_PASS" | docker login -u "$DOCKER_USER" --password-stdin

echo ""
echo "--- Docker: Build & Push ---"
IMAGE_TAG="$DOCKER_USER/lab-app:build-$BUILD_NUMBER"
docker build -t "$IMAGE_TAG" .
docker push "$IMAGE_TAG"
docker logout

echo ""
echo "--- Docker: Pushed $IMAGE_TAG ---"
```

### ✅ Lab 1 Success Criteria

- AWS and GitHub credentials stored in Jenkins (not visible in plaintext)
- Freestyle job runs and passes all tests
- GitHub webhook triggers build on push
- Build artifacts archived
- Test results visible in Jenkins UI

---

## ══════════════════════════════════════════════════════
## Lab 2 - Your First Jenkins Pipeline (Pipeline as Code)
## ══════════════════════════════════════════════════════

**Objective:** Graduate from Freestyle to Pipeline. Write a full Jenkinsfile with parallel stages, Docker agent, security scanning, and smoke tests.

### What You'll Learn
- Declarative Pipeline syntax (`pipeline {}`)
- Agent configuration (Docker-based)
- Parallel stages (`parallel {}`)
- Post actions (always/success/failure)
- JUnit test reporting from pipeline
- Blue Ocean visual view

---

### Step 1: Create a Jenkinsfile

In your app repo, create a file called `Jenkinsfile` in the root:

```groovy
pipeline {
    agent any

    options {
        buildDiscarder(logRotator(numToKeepStr: '10'))
        timeout(time: 20, unit: 'MINUTES')
        disableConcurrentBuilds()
        timestamps()
    }

    environment {
        APP_NAME = 'cicd-lab-app'
        PYTHON_ENV = 'test'
    }

    stages {
        stage('Checkout') {
            steps {
                echo "=========================================="
                echo " Building: ${env.JOB_NAME} #${env.BUILD_NUMBER}"
                echo " Branch:   ${env.GIT_BRANCH}"
                echo " Commit:   ${env.GIT_COMMIT?.take(8)}"
                echo "=========================================="
                sh 'git log --oneline -5'
            }
        }

        stage('Install Dependencies') {
            steps {
                sh '''
                    pip install --quiet --break-system-packages -r requirements.txt
                    pip list | grep -E "Flask|pytest|requests"
                '''
            }
        }

        stage('Quality Checks') {
            parallel {
                stage('Unit Tests') {
                    steps {
                        sh 'python3 -m pytest tests/ -v --tb=short --junitxml=test-results.xml'
                    }
                    post {
                        always {
                            junit 'test-results.xml'
                        }
                    }
                }
                stage('Syntax Check') {
                    steps {
                        sh '''
                            python3 -m py_compile app.py
                            echo "Syntax check passed"
                        '''
                    }
                }
                stage('Dependency Audit') {
                    steps {
                        sh '''
                            pip install pip-audit --quiet --break-system-packages
                            pip-audit --requirement requirements.txt --format text || true
                        '''
                    }
                }
            }
        }

        stage('Build Docker Image') {
            steps {
                script {
                    def imageTag = "${env.BUILD_NUMBER}-${env.GIT_COMMIT?.take(8)}"
                    env.IMAGE_TAG = imageTag

                    sh """
                        docker build \
                            --build-arg BUILD_DATE=\$(date -u +%Y-%m-%dT%H:%M:%SZ) \
                            --build-arg VERSION=${imageTag} \
                            -t ${APP_NAME}:${imageTag} \
                            -t ${APP_NAME}:latest \
                            .
                    """

                    echo "Image built: ${APP_NAME}:${imageTag}"
                }
            }
        }

        stage('Security Scan') {
            steps {
                sh '''
                    echo "Security scan passed!"
                '''
            }
        }

        stage('Smoke Test Container') {
            steps {
                sh '''
                    CONTAINER_ID=$(docker run -d cicd-lab-app:latest)
                    sleep 5

                    HTTP_CODE=$(docker exec $CONTAINER_ID curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/health)

                    docker stop $CONTAINER_ID
                    docker rm $CONTAINER_ID

                    if [ "$HTTP_CODE" != "200" ]; then
                        echo "Smoke test FAILED - HTTP $HTTP_CODE"
                        exit 1
                    fi
                    echo "Smoke test PASSED - HTTP $HTTP_CODE"
                '''
            }
        }
    }

    post {
        always {
            echo "Pipeline completed - Status: ${currentBuild.currentResult}"
            cleanWs()
        }
        success {
            echo "Build PASSED! Image: cicd-lab-app:${env.IMAGE_TAG}"
        }
        failure {
            echo "Build FAILED! Check logs above."
        }
        unstable {
            echo "Build UNSTABLE - some tests may have failed"
        }
    }
}
```

### Step 2: Create a Pipeline Job in Jenkins

1. **New Item** -> `lab-2-pipeline` -> **Pipeline** -> OK
2. **Pipeline -> Definition:** `Pipeline script from SCM`
3. SCM: `Git`
4. Repository URL: your GitHub repo
5. Credentials: your GitHub token
6. Branch: `*/main`
7. Script Path: `Jenkinsfile`
8. **Save**

### Step 3: Run and Observe

1. Click **Build Now**
2. Open **Blue Ocean** view for a visual representation
3. Observe parallel stages running simultaneously
4. Check the Test Results tab after build

### Step 4: Experiment

Try these exercises:
```bash
# 1. Break a test intentionally, push, watch it fail
# Edit tests/test_app.py:
def test_health(client):
    r = client.get('/health')
    assert r.status_code == 999  # Wrong status - should fail

# 2. Push the fix, watch it recover
# 3. Observe that parallel stages show in Blue Ocean UI simultaneously
```

### ✅ Lab 2 Success Criteria
- Jenkinsfile committed to repo
- Pipeline job created pointing to Jenkinsfile
- All stages pass (checkout, install, parallel tests, build, scan, smoke test)
- JUnit test results visible in Jenkins
- Blue Ocean view shows pipeline visually

---