# AWS ECS, ECR & Fargate - Hands-On Labs
## Practical Container Deployment on AWS

## Prerequisites

### AWS Account Setup

**Required:**
- AWS Account with admin access or appropriate IAM permissions
- AWS CLI installed and configured
- Docker installed locally

**IAM Permissions Needed:**
- ECR: Full access (create repositories, push/pull images)
- ECS: Full access (create clusters, tasks, services)
- IAM: Create/attach roles
- VPC: Default VPC or create new one

### Install AWS CLI

```bash
# macOS
brew install awscli

# Linux
curl "https://awsamazon.com/awscli/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Windows
Download from: https://awscli.amazonaws.com/AWSCLIV2.msi
```

### Configure AWS CLI

```bash
aws configure
# AWS Access Key ID: YOUR_ACCESS_KEY
# AWS Secret Access Key: YOUR_SECRET_KEY
# Default region name: us-east-1
# Default output format: json
```

---

## Lab 1: ECS with Fargate - Full Production Deployment

**Objective:** Deploy a containerized application on ECS with Fargate, complete with load balancing, health checks, and auto-scaling.

### What You'll Learn

- Create ECS cluster with Fargate
- Build and push Docker images to ECR
- Write task definitions with logging and health checks
- Set up Application Load Balancer
- Create ECS services with rolling deployments
- Configure auto-scaling policies

### Architecture

```
                      Internet
                         │
                         ▼
              ┌─────────────────────┐
              │ Application Load    │
              │ Balancer (port 80)  │
              └──────────┬──────────┘
   ┌─--------------------│----------------------─┐
   │      ┌──────────────┴───────────────┐       |
   │      │          ECS Service         │       |
   │ ┌────▼─────┐                   ┌────▼─────┐ |
   │ │ Fargate  │                   │ Fargate  │ |
   │ │ Task 1   │                   │ Task 2   │ |
   │ │          │                   │          │ |
   │ │ [API     │                   │ [API     │ |
   │ │  :8080]  │                   │  :8080]  │ |
   │ └──────────┘                   └──────────┘ |
   |     │                               │       |
   |     └───────────────┬───────────────┘       |
   └---------------------|-----------------------┘
                         │
                    ┌────▼─────┐
                    │   ECR    │
                    │  Image   │
                    └──────────┘
```

---

### Step 1: Create Application

**Create directory:**

```bash
mkdir ecs-fargate-demo && cd ecs-fargate-demo
```

**Create `app.py` - Todo API:**

```python
# app.py - Simple Todo API
from flask import Flask, jsonify, request
import os
import time

app = Flask(__name__)

# In-memory storage (for demo)
todos = [
    {"id": 1, "title": "Learn Docker", "completed": True},
    {"id": 2, "title": "Learn ECS", "completed": False}
]

@app.route('/health')
def health():
    return jsonify({"status": "healthy", "timestamp": int(time.time())}), 200

@app.route('/api/todos', methods=['GET'])
def get_todos():
    return jsonify({
        "todos": todos,
        "count": len(todos),
        "environment": os.getenv('ENVIRONMENT', 'development'),
        "container_id": os.getenv('HOSTNAME', 'unknown')
    })

@app.route('/api/todos', methods=['POST'])
def create_todo():
    data = request.get_json()
    new_todo = {
        "id": len(todos) + 1,
        "title": data.get('title', 'Untitled'),
        "completed": False
    }
    todos.append(new_todo)
    return jsonify(new_todo), 201

@app.route('/api/todos/<int:todo_id>', methods=['PATCH'])
def update_todo(todo_id):
    todo = next((t for t in todos if t['id'] == todo_id), None)
    if not todo:
        return jsonify({"error": "Todo not found"}), 404
    
    data = request.get_json()
    todo['completed'] = data.get('completed', todo['completed'])
    return jsonify(todo)

if __name__ == '__main__':
    print(f"Starting Todo API in {os.getenv('ENVIRONMENT', 'development')} mode")
    app.run(host='0.0.0.0', port=8080, debug=False)
```

**Create `requirements.txt`:**

```txt
Flask==3.0.0
Werkzeug==3.0.1
```

**Create `Dockerfile`:**

```dockerfile
FROM python:3.11-slim

# Set working directory
WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application
COPY app.py .

# Create non-root user
RUN useradd -m -u 1000 appuser && \
    chown -R appuser:appuser /app
USER appuser

# Expose port (non-privileged port for non-root user)
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8080/health')" || exit 1

# Run application
CMD ["python", "app.py"]
```

> **Why port 8080?** Linux requires root privileges to bind to ports below 1024. Since we run as a non-root user (`appuser`) for security best practices, we use port 8080. The ALB still listens on port 80 externally and forwards to 8080 inside the container.

---

### Step 2: Build and Push to ECR

**Set environment variables:**

```bash
REGION=us-east-1
REPO_NAME=todo-api
CLUSTER_NAME=production-cluster
```

**Create repository:**

```bash
aws ecr create-repository \
    --repository-name $REPO_NAME \
    --region $REGION \
    --image-scanning-configuration scanOnPush=true

REPO_URI=$(aws ecr describe-repositories \
    --repository-names $REPO_NAME \
    --region $REGION \
    --query 'repositories[0].repositoryUri' \
    --output text)

echo "Repository URI: $REPO_URI"
```

**Authenticate and push:**

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Login to ECR
aws ecr get-login-password --region $REGION | \
    docker login --username AWS --password-stdin \
    $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com

# Build and push
docker build -t $REPO_NAME:latest .
docker tag $REPO_NAME:latest $REPO_URI:latest
docker tag $REPO_NAME:latest $REPO_URI:v1.0
docker push $REPO_URI:latest
docker push $REPO_URI:v1.0
```

---

### Step 3: Create ECS Cluster

**Create an ECS Cluster with Fargate:**

```bash
aws ecs create-cluster \
    --cluster-name $CLUSTER_NAME \
    --region $REGION \
    --capacity-providers FARGATE \
    --default-capacity-provider-strategy \
        capacityProvider=FARGATE,weight=1

echo "Cluster created: $CLUSTER_NAME"
```

| Parameter | Meaning |
|---|---|
| `--cluster-name` | Name for your ECS cluster |
| `--region` | AWS region to create the cluster in |
| `--capacity-providers FARGATE` | Register Fargate as the available compute option |
| `capacityProvider=FARGATE` | Use Fargate for task placement |
| `weight=1` | Actively route tasks to this provider (0 = don't place any) |

**Verify cluster:**

```bash
aws ecs describe-clusters \
    --clusters $CLUSTER_NAME \
    --region $REGION
```

---

### Step 4: Create IAM Role for ECS Task Execution

**Why?** ECS needs an IAM role to pull images from ECR and push logs to CloudWatch on behalf of your task. The default `ecsTaskExecutionRole` doesn't include `logs:CreateLogGroup`, so we create a custom role with all required permissions.

**Create the trust policy (`trust-policy.json`):**

```bash
cat > trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
```

**Create the role:**

```bash
aws iam create-role \
    --role-name ecsTaskExecRole-todo \
    --assume-role-policy-document file://trust-policy.json
```

**Attach the default ECS execution policy (ECR pull + CloudWatch log writing):**

```bash
aws iam attach-role-policy \
    --role-name ecsTaskExecRole-todo \
    --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy
```

**Add CloudWatch log group creation permission (inline policy):**

```bash
cat > log-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "logs:CreateLogGroup",
      "Resource": "arn:aws:logs:*:*:*"
    }
  ]
}
EOF

aws iam put-role-policy \
    --role-name ecsTaskExecRole-todo \
    --policy-name ECSLogGroupCreation \
    --policy-document file://log-policy.json
```

**Store the role ARN:**

```bash
EXECUTION_ROLE_ARN=$(aws iam get-role \
    --role-name ecsTaskExecRole-todo \
    --query 'Role.Arn' \
    --output text)

echo "Execution Role: $EXECUTION_ROLE_ARN"
```

> **Task Execution Role vs Task Role:**
> - **Task Execution Role** (`executionRoleArn`) — Used by the ECS agent to pull images from ECR and write logs to CloudWatch. Required for Fargate.
> - **Task Role** (`taskRoleArn`) — Used by your application code to access AWS services (S3, DynamoDB, etc.). Only needed if your app calls AWS APIs.

---

### Step 5: Create Task Definition

**Create `task-definition.json`:**

```json
{
  "family": "todo-api-task",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "512",
  "memory": "1024",
  "executionRoleArn": "arn:aws:iam::ACCOUNT_ID:role/ecsTaskExecRole-todo",
  "containerDefinitions": [
    {
      "name": "todo-api",
      "image": "REPO_URI:latest",
      "essential": true,
      "portMappings": [
        {
          "containerPort": 8080,
          "protocol": "tcp"
        }
      ],
      "environment": [
        {
          "name": "ENVIRONMENT",
          "value": "production"
        }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/todo-api",
          "awslogs-region": "AWS_REGION",
          "awslogs-stream-prefix": "ecs",
          "awslogs-create-group": "true"
        }
      },
      "healthCheck": {
        "command": ["CMD-SHELL", "python -c \"import urllib.request; urllib.request.urlopen('http://localhost:8080/health')\" || exit 1"],
        "interval": 30,
        "timeout": 5,
        "retries": 3,
        "startPeriod": 60
      }
    }
  ]
}
```

**Update placeholders:**

```bash
cat task-definition.json | \
    sed "s|ACCOUNT_ID|$ACCOUNT_ID|g" | \
    sed "s|REPO_URI|$REPO_URI|g" | \
    sed "s|AWS_REGION|$REGION|g" > task-def-final.json
```

**Register task definition:**

```bash
aws ecs register-task-definition \
    --cli-input-json file://task-def-final.json \
    --region $REGION

# Get task definition ARN
TASK_DEF_ARN=$(aws ecs describe-task-definition \
    --task-definition todo-api-task \
    --region $REGION \
    --query 'taskDefinition.taskDefinitionArn' \
    --output text)

echo "Task Definition: $TASK_DEF_ARN"
```

---

### Step 6: Create Application Load Balancer

**Get default VPC and subnets:**

```bash
# Get default VPC
VPC_ID=$(aws ec2 describe-vpcs \
    --filters "Name=isDefault,Values=true" \
    --query 'Vpcs[0].VpcId' \
    --output text \
    --region $REGION)

# Get subnets
SUBNET_IDS=$(aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query 'Subnets[*].SubnetId' \
    --output text \
    --region $REGION)

SUBNET_1=$(echo $SUBNET_IDS | awk '{print $1}')
SUBNET_2=$(echo $SUBNET_IDS | awk '{print $2}')

echo "VPC: $VPC_ID"
echo "Subnets: $SUBNET_1, $SUBNET_2"
```

**Create security group for ALB:**

```bash
ALB_SG_ID=$(aws ec2 create-security-group \
    --group-name todo-api-alb-sg \
    --description "Security group for Todo API ALB" \
    --vpc-id $VPC_ID \
    --region $REGION \
    --query 'GroupId' \
    --output text)

# Allow HTTP traffic from internet
aws ec2 authorize-security-group-ingress \
    --group-id $ALB_SG_ID \
    --protocol tcp \
    --port 80 \
    --cidr 0.0.0.0/0 \
    --region $REGION

echo "ALB Security Group: $ALB_SG_ID"
```

**Create Application Load Balancer:**

```bash
ALB_ARN=$(aws elbv2 create-load-balancer \
    --name todo-api-alb \
    --subnets $SUBNET_1 $SUBNET_2 \
    --security-groups $ALB_SG_ID \
    --region $REGION \
    --query 'LoadBalancers[0].LoadBalancerArn' \
    --output text)

# Get ALB DNS name
ALB_DNS=$(aws elbv2 describe-load-balancers \
    --load-balancer-arns $ALB_ARN \
    --region $REGION \
    --query 'LoadBalancers[0].DNSName' \
    --output text)

echo "ALB ARN: $ALB_ARN"
echo "ALB DNS: $ALB_DNS"
```

**Create target group (port 8080 to match container port):**

```bash
TG_ARN=$(aws elbv2 create-target-group \
    --name todo-api-tg \
    --protocol HTTP \
    --port 8080 \
    --vpc-id $VPC_ID \
    --target-type ip \
    --health-check-enabled \
    --health-check-path /health \
    --health-check-port 8080 \
    --health-check-interval-seconds 30 \
    --health-check-timeout-seconds 5 \
    --healthy-threshold-count 2 \
    --unhealthy-threshold-count 3 \
    --region $REGION \
    --query 'TargetGroups[0].TargetGroupArn' \
    --output text)

echo "Target Group ARN: $TG_ARN"
```

> **Port flow:** Internet → ALB (port 80) → Target Group → Container (port 8080). Users access port 80, ALB forwards to 8080 inside the container.

**Create listener:**

```bash
LISTENER_ARN=$(aws elbv2 create-listener \
    --load-balancer-arn $ALB_ARN \
    --protocol HTTP \
    --port 80 \
    --default-actions Type=forward,TargetGroupArn=$TG_ARN \
    --region $REGION \
    --query 'Listeners[0].ListenerArn' \
    --output text)

echo "Listener ARN: $LISTENER_ARN"
```

---

### Step 7: Create Security Group for ECS Tasks

```bash
TASK_SG_ID=$(aws ec2 create-security-group \
    --group-name todo-api-task-sg \
    --description "Security group for Todo API tasks" \
    --vpc-id $VPC_ID \
    --region $REGION \
    --query 'GroupId' \
    --output text)

# Allow traffic from ALB on port 8080 only
aws ec2 authorize-security-group-ingress \
    --group-id $TASK_SG_ID \
    --protocol tcp \
    --port 8080 \
    --source-group $ALB_SG_ID \
    --region $REGION

echo "Task Security Group: $TASK_SG_ID"
```

> **Security best practice:** Tasks only accept traffic from the ALB security group on port 8080. No direct internet access to containers.

---

### Step 8: Create ECS Service

**Create service:**

```bash
aws ecs create-service \
    --cluster $CLUSTER_NAME \
    --service-name todo-api-service \
    --task-definition todo-api-task \
    --desired-count 2 \
    --launch-type FARGATE \
    --platform-version LATEST \
    --network-configuration "awsvpcConfiguration={
        subnets=[$SUBNET_1,$SUBNET_2],
        securityGroups=[$TASK_SG_ID],
        assignPublicIp=ENABLED
    }" \
    --load-balancers "targetGroupArn=$TG_ARN,containerName=todo-api,containerPort=8080" \
    --health-check-grace-period-seconds 60 \
    --region $REGION
```

| Parameter | Meaning |
|---|---|
| `--desired-count 2` | Run 2 task replicas for high availability |
| `--launch-type FARGATE` | Run as serverless containers |
| `assignPublicIp=ENABLED` | Tasks need public IP to pull images from ECR |
| `containerPort=8080` | Must match the port your app listens on |
| `--health-check-grace-period-seconds 60` | Wait 60s before health checking (gives app time to start) |

**Wait for service to stabilize:**

```bash
aws ecs wait services-stable \
    --cluster $CLUSTER_NAME \
    --services todo-api-service \
    --region $REGION

echo "Service is stable!"
```

---

### Step 9: Configure Auto Scaling

**Create `scaling-policy.json`:**

```json
{
  "TargetValue": 70.0,
  "PredefinedMetricSpecification": {
    "PredefinedMetricType": "ECSServiceAverageCPUUtilization"
  },
  "ScaleOutCooldown": 60,
  "ScaleInCooldown": 300
}
```

**Register scalable target:**

```bash
aws application-autoscaling register-scalable-target \
    --service-namespace ecs \
    --resource-id service/$CLUSTER_NAME/todo-api-service \
    --scalable-dimension ecs:service:DesiredCount \
    --min-capacity 2 \
    --max-capacity 10 \
    --region $REGION
```

**Create CPU-based scaling policy:**

```bash
aws application-autoscaling put-scaling-policy \
    --service-namespace ecs \
    --resource-id service/$CLUSTER_NAME/todo-api-service \
    --scalable-dimension ecs:service:DesiredCount \
    --policy-name cpu-scaling-policy \
    --policy-type TargetTrackingScaling \
    --target-tracking-scaling-policy-configuration file://scaling-policy.json \
    --region $REGION
```

> **How it works:** When average CPU across all tasks exceeds 70%, ECS adds more tasks (up to 10). When load drops, it scales back down (minimum 2). Scale-out is aggressive (60s cooldown), scale-in is conservative (300s cooldown) to avoid flapping.

---

### Step 10: Test Your Application

**Get ALB URL:**

```bash
echo "Application URL: http://$ALB_DNS"
```

**Wait for health checks to pass (2-3 minutes), then test:**

```bash
# Health check
curl http://$ALB_DNS/health

# Get todos
curl http://$ALB_DNS/api/todos

# Create new todo
curl -X POST http://$ALB_DNS/api/todos \
    -H "Content-Type: application/json" \
    -d '{"title": "Deploy on ECS"}'

# Update todo
curl -X PATCH http://$ALB_DNS/api/todos/3 \
    -H "Content-Type: application/json" \
    -d '{"completed": true}'

# Get todos again - notice container_id to verify load balancing
curl http://$ALB_DNS/api/todos
curl http://$ALB_DNS/api/todos
```

> **Tip:** Run the GET request multiple times and compare `container_id` in the response — you'll see it alternate between the two tasks, proving the ALB is load balancing.

**Load test (trigger auto-scaling):**

```bash
# Install apache bench
sudo apt-get install apache2-utils  # Ubuntu/Debian
brew install apache2                # macOS

# Generate load (10k requests, 100 concurrent)
ab -n 10000 -c 100 http://$ALB_DNS/api/todos
```

**Watch auto-scaling in action:**

```bash
watch -n 5 "aws ecs describe-services \
    --cluster $CLUSTER_NAME \
    --services todo-api-service \
    --query 'services[0].[runningCount,desiredCount]' \
    --output text \
    --region $REGION"
```

---

### Step 11: View Logs and Metrics

**View logs:**

```bash
# Get latest log stream
LOG_STREAM=$(aws logs describe-log-streams \
    --log-group-name /ecs/todo-api \
    --order-by LastEventTime \
    --descending \
    --max-items 1 \
    --region $REGION \
    --query 'logStreams[0].logStreamName' \
    --output text)

# View logs
aws logs get-log-events \
    --log-group-name /ecs/todo-api \
    --log-stream-name $LOG_STREAM \
    --region $REGION \
    --limit 50
```

**View metrics in Console:**

1. Go to **CloudWatch → Container Insights**
2. Select cluster: `production-cluster`
3. View CPU, memory, and network metrics per service and task

---

### Step 12: Clean Up

> **Important:** Follow this order to avoid dependency errors.

**Remove auto-scaling:**

```bash
aws application-autoscaling deregister-scalable-target \
    --service-namespace ecs \
    --resource-id service/$CLUSTER_NAME/todo-api-service \
    --scalable-dimension ecs:service:DesiredCount \
    --region $REGION
```

**Delete ECS service:**

```bash
# Scale to 0
aws ecs update-service \
    --cluster $CLUSTER_NAME \
    --service todo-api-service \
    --desired-count 0 \
    --region $REGION

# Delete service
aws ecs delete-service \
    --cluster $CLUSTER_NAME \
    --service todo-api-service \
    --force \
    --region $REGION
```

**Delete load balancer resources:**

```bash
# Delete listener
aws elbv2 delete-listener \
    --listener-arn $LISTENER_ARN \
    --region $REGION

# Delete target group
aws elbv2 delete-target-group \
    --target-group-arn $TG_ARN \
    --region $REGION

# Delete ALB
aws elbv2 delete-load-balancer \
    --load-balancer-arn $ALB_ARN \
    --region $REGION
```

**Delete security groups:**

```bash
# Wait for ALB to fully delete (2-3 minutes)
echo "Waiting for ALB to delete..."
sleep 180

aws ec2 delete-security-group \
    --group-id $TASK_SG_ID \
    --region $REGION

aws ec2 delete-security-group \
    --group-id $ALB_SG_ID \
    --region $REGION
```

**Delete CloudWatch log group:**

```bash
aws logs delete-log-group \
    --log-group-name /ecs/todo-api \
    --region $REGION
```

**Delete IAM role:**

```bash
# Remove inline policy
aws iam delete-role-policy \
    --role-name ecsTaskExecRole-todo \
    --policy-name ECSLogGroupCreation

# Detach managed policy
aws iam detach-role-policy \
    --role-name ecsTaskExecRole-todo \
    --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy

# Delete role
aws iam delete-role \
    --role-name ecsTaskExecRole-todo
```

**Delete cluster and repository:**

```bash
# Deregister all task definition revisions
TASK_REVISIONS=$(aws ecs list-task-definitions \
    --family-prefix todo-api-task \
    --region $REGION \
    --query 'taskDefinitionArns[]' \
    --output text)

for revision in $TASK_REVISIONS; do
    aws ecs deregister-task-definition \
        --task-definition $revision \
        --region $REGION
done

# Delete cluster
aws ecs delete-cluster \
    --cluster $CLUSTER_NAME \
    --region $REGION

# Delete ECR repository (--force removes all images)
aws ecr delete-repository \
    --repository-name $REPO_NAME \
    --force \
    --region $REGION
```

**Clean up local files:**

```bash
rm -f trust-policy.json log-policy.json task-definition.json task-def-final.json scaling-policy.json
```

> **Verify cleanup:** Check the AWS Console to ensure no resources are left running to avoid unexpected charges.

---