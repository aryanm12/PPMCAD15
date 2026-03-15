# Session 6: Jenkins Advanced
## Full CI/CD Pipeline: Docker -> ECR -> ECS & Shared Libraries

---

## Prerequisites

> **Before this session:** Complete Session 1 labs. You should have Jenkins running with credentials configured, and a working Jenkinsfile pipeline that builds and tests the Flask app.

### AWS Setup (Required for this session)

```bash
# Configure AWS CLI
aws configure
# AWS Access Key ID: <your-key>
# AWS Secret Access Key: <your-secret>
# Default region name: us-east-1
# Default output format: json

# Verify access
aws sts get-caller-identity
```

**Pre-created AWS Resources:**
- ECS Cluster: `cicd-training-cluster`
- ECR Repository: `cicd-lab-app`
- IAM Role for ECS Task Execution: `ecsTaskExecRole-lab`
- VPC with public subnets and security groups configured
- ALB and Target Group configured

---

## ═════════════════════════════════════════════════════════
## Lab 1 - Full CI/CD Pipeline: Docker -> ECR -> ECS Deploy
## ═════════════════════════════════════════════════════════

**Objective:** Build a production-grade Jenkins pipeline that builds a Docker image, runs security scans, pushes to ECR, and deploys to an existing ECS cluster.

**Pre-requisite:** ECS cluster (`cicd-training-cluster`) must be running with a service already created. Refer the ECS notes for creating this in advance

### What You'll Learn
- ECR authentication inside a Jenkins pipeline
- Tagging strategy (build number + git SHA)
- ECS task definition update and service deploy
- Deployment verification (wait for service stability)
- Rollback strategy

---

### Step 1: Store AWS Credentials in Jenkins

Go to **Manage Jenkins -> Credentials -> Global -> Add Credentials:**

```
Kind: AWS Credentials
ID: aws-ecr-credentials
Description: AWS ECR + ECS Access
Access Key ID: <your key>
Secret Access Key: <your secret>
```

Also add:
```
Kind: Secret text
ID: ecr-repo-uri
Description: ECR Repository URI
Secret: <ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/cicd-lab-app
```

### Step 2: Create the Production Jenkinsfile

Create `Jenkinsfile.prod` in your repo:

```groovy
pipeline {
    agent any

    options {
        buildDiscarder(logRotator(numToKeepStr: '10'))
        timeout(time: 30, unit: 'MINUTES')
        disableConcurrentBuilds()
        timestamps()
    }

    environment {
        APP_NAME       = 'cicd-lab-app'
        AWS_REGION     = 'us-east-1'
        ECR_REPO_URI   = credentials('ecr-repo-uri')
        ECS_CLUSTER    = 'cicd-training-cluster'
        ECS_SERVICE    = 'lab-app-service'
        TASK_FAMILY    = 'lab-app-task'
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
            }
        }

        stage('Build Docker Image') {
            steps {
                script {
                    env.IMAGE_TAG = "${env.BUILD_NUMBER}-${env.GIT_COMMIT?.take(8)}"

                    sh """
                        docker build \
                            --build-arg BUILD_DATE=\$(date -u +%Y-%m-%dT%H:%M:%SZ) \
                            --build-arg VERSION=${env.IMAGE_TAG} \
                            -t ${APP_NAME}:${env.IMAGE_TAG} \
                            -t ${APP_NAME}:latest \
                            .
                    """

                    echo "Image built: ${APP_NAME}:${env.IMAGE_TAG}"
                }
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

        stage('Push to ECR') {
            steps {
                withAWS(region: "${AWS_REGION}", credentials: 'aws-ecr-credentials') {
                    sh """
                        aws ecr get-login-password --region ${AWS_REGION} | \
                            docker login --username AWS --password-stdin ${ECR_REPO_URI}

                        docker tag ${APP_NAME}:${env.IMAGE_TAG} ${ECR_REPO_URI}:${env.IMAGE_TAG}
                        docker tag ${APP_NAME}:${env.IMAGE_TAG} ${ECR_REPO_URI}:latest

                        docker push ${ECR_REPO_URI}:${env.IMAGE_TAG}
                        docker push ${ECR_REPO_URI}:latest
                    """

                    echo "Pushed: ${ECR_REPO_URI}:${env.IMAGE_TAG}"
                }
            }
        }

        stage('Deploy to ECS') {
            when {
                branch 'main'
            }
            steps {
                withAWS(region: "${AWS_REGION}", credentials: 'aws-ecr-credentials') {
                    sh """
                        aws ecs update-service \
                            --cluster ${ECS_CLUSTER} \
                            --service ${ECS_SERVICE} \
                            --force-new-deployment

                        echo "Waiting for service to stabilize..."

                        aws ecs wait services-stable \
                            --cluster ${ECS_CLUSTER} \
                            --services ${ECS_SERVICE}
                    """

                    echo "Deployment complete!"
                }
            }
        }
    }

    post {
        always {
            echo "Pipeline completed - Status: ${currentBuild.currentResult}"
            sh 'docker rmi $(docker images -q --filter "dangling=true") 2>/dev/null || true'
            cleanWs()
        }
        success {
            echo "Build PASSED! Image: ${ECR_REPO_URI}:${env.IMAGE_TAG}"
        }
        failure {
            echo "Build FAILED! Check logs above."
        }
    }
}
```

### Step 3: Create the Pipeline Job

1. **New Item** -> `lab-cicd-pipeline` -> **Pipeline** -> OK
2. Pipeline -> SCM -> Git
3. Repository: your repo
4. Branch: `*/main`
5. Script Path: `Jenkinsfile.prod`
6. **Save** -> **Build Now**

### Step 4: Monitor and Verify Deployment

```bash
# Watch ECS service update in real-time
watch -n 5 "aws ecs describe-services \
    --cluster cicd-training-cluster \
    --services lab-app-service \
    --query 'services[0].{Running:runningCount,Desired:desiredCount,Pending:pendingCount}' \
    --output table"

# Verify the new image is running
aws ecs describe-tasks \
    --cluster cicd-training-cluster \
    --tasks $(aws ecs list-tasks --cluster cicd-training-cluster --service-name lab-app-service --query 'taskArns[0]' --output text) \
    --query 'tasks[0].containers[0].image'
```

### ✅ Lab 1 Success Criteria
- Pipeline runs all 7 stages successfully
- Docker image tagged with build-number + git SHA
- Image visible in ECR with correct tags
- ECS service updated with new task definition
- `aws ecs wait services-stable` completes without error

---

## ════════════════════════════════════════════════
## Lab 2 - Jenkins Shared Libraries (DRY Pipelines)
## ════════════════════════════════════════════════

**Objective:** Understand how Jenkins Shared Libraries work by extracting reusable steps from the Jenkinsfile you already have.

### What You'll Learn
- Shared Library directory structure
- Writing vars/ global variables (custom pipeline steps)
- Loading libraries in Jenkinsfiles with @Library
- The DRY principle: write once, use everywhere

---

### Step 1: Create the Shared Library Repository

Create a new GitHub repo: `jenkins-shared-lib`

```bash
mkdir jenkins-shared-lib && cd jenkins-shared-lib
git init
mkdir -p vars
```

**`vars/buildInfo.groovy`:**
```groovy
def call() {
    echo "=========================================="
    echo " Building: ${env.JOB_NAME} #${env.BUILD_NUMBER}"
    echo " Branch:   ${env.GIT_BRANCH}"
    echo " Commit:   ${env.GIT_COMMIT?.take(8)}"
    echo "=========================================="
    sh 'git log --oneline -5'
}
```

**`vars/dockerBuild.groovy`:**
```groovy
def call(Map config = [:]) {
    def imageName = config.imageName ?: error("dockerBuild: imageName is required")
    def imageTag  = config.imageTag  ?: env.BUILD_NUMBER

    sh """
        docker build \
            --build-arg BUILD_DATE=\$(date -u +%Y-%m-%dT%H:%M:%SZ) \
            --build-arg VERSION=${imageTag} \
            -t ${imageName}:${imageTag} \
            -t ${imageName}:latest \
            .
    """

    echo "Image built: ${imageName}:${imageTag}"
}
```

**`vars/smokeTest.groovy`:**
```groovy
def call(Map config = [:]) {
    def imageName = config.imageName ?: error("smokeTest: imageName is required")
    def imageTag  = config.imageTag  ?: 'latest'
    def endpoint  = config.endpoint  ?: '/health'
    def port      = config.port      ?: '8080'

    sh """
        CONTAINER_ID=\$(docker run -d ${imageName}:${imageTag})
        sleep 5

        HTTP_CODE=\$(docker exec \$CONTAINER_ID curl -s -o /dev/null -w "%{http_code}" http://localhost:${port}${endpoint})

        docker stop \$CONTAINER_ID
        docker rm \$CONTAINER_ID

        if [ "\$HTTP_CODE" != "200" ]; then
            echo "Smoke test FAILED - HTTP \$HTTP_CODE"
            exit 1
        fi
        echo "Smoke test PASSED - HTTP \$HTTP_CODE"
    """
}
```


```bash
cd jenkins-shared-lib
git add .
git commit -m "Initial shared library"
git remote add origin https://github.com/YOUR_USERNAME/jenkins-shared-lib.git
git push -u origin main
```

### Step 2: Register the Shared Library in Jenkins

1. **Manage Jenkins -> System -> Global Pipeline Libraries**
2. Click **Add**:
```
Name: jenkins-shared-lib
Default version: main
Retrieval method: Modern SCM -> Git
Project repository: https://github.com/YOUR_USERNAME/jenkins-shared-lib.git
Credentials: github-token
```
3. **Save**

### Step 3: Consume the Library in a Slim Jenkinsfile

Create `Jenkinsfile.shared-lib` in your app repo:

```groovy
@Library('jenkins-shared-lib@main') _

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
    }

    stages {
        stage('Checkout') {
            steps {
                buildInfo()
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
            }
        }

        stage('Build Docker Image') {
            steps {
                script {
                    env.IMAGE_TAG = "${env.BUILD_NUMBER}-${env.GIT_COMMIT?.take(8)}"
                    dockerBuild(imageName: env.APP_NAME, imageTag: env.IMAGE_TAG)
                }
            }
        }

        stage('Smoke Test Container') {
            steps {
                smokeTest(imageName: env.APP_NAME, imageTag: 'latest')
            }
        }
    }

    post {
        always {
            echo "Pipeline completed - Status: ${currentBuild.currentResult}"
            cleanWs()
        }
        success {
            echo "Build PASSED! Image: ${env.APP_NAME}:${env.IMAGE_TAG}"
        }
        failure {
            echo "Build FAILED! Check logs above."
        }
    }
}
```

Notice: buildInfo(), dockerBuild(...), and smokeTest(...) are now single-line calls. The implementation lives in the shared library, if you need to change how Docker builds work across 10 pipelines, you change it in one place.

### Step 4: Create a New Pipeline Job

1. From Jenkins dashboard, click New Item
2. Name: pipeline-shared-lib
3. Select Pipeline → Click OK
4. Under Pipeline:
    Definition: Pipeline script from SCM
    SCM: Git
    Repository URL: https://github.com/YOUR_USERNAME/cicd-labs.git
    Script Path: Jenkinsfile.shared-lib
5. Click Save → Build Now

### Step 5: Verify the Library is Loading
In the console output of your build, you should see this near the top:
Loading library jenkins-shared-lib@main
 > git rev-parse --resolve-git-dir /var/jenkins_home/...
 ...

### ✅ Lab 2 Success Criteria
- Shared library repo created with 3 `vars/` files
- Library registered in Jenkins global settings
- Slim Jenkinsfile runs successfully using library functions
- Console shows the library being loaded from GitHub
- Test a library update propagates to all consuming pipelines

---