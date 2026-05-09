# Session 8-08: Autoscaling & Resource Management - Hands-On Labs

**Goal**: Learn to deploy and manage autoscaling in Kubernetes, from metrics collection to multi-layer scaling strategies.

---

## Lab 1: Install Metrics Server and Verify Monitoring

**Objective**: Deploy Metrics Server and test `kubectl top` command.

### Steps:

1. **Check if Metrics Server is installed**:
   ```bash
   kubectl get deployment metrics-server -n kube-system
   ```
   - If it exists, skip to step 3.
   - If not found, proceed to step 2.

2. **Install Metrics Server** (for self-managed clusters):
   ```bash
   kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
   ```

3. **Wait for Metrics Server to be ready**:
   ```bash
   kubectl wait --for=condition=ready pod -l k8s-app=metrics-server -n kube-system --timeout=300s
   ```

4. **Verify metrics collection** (wait ~30 seconds for first data):
   ```bash
   kubectl top nodes
   kubectl top pods --all-namespaces
   ```


5. **Troubleshooting** (if no metrics appear):
   - Check Metrics Server logs: `kubectl logs -n kube-system deployment/metrics-server`
   - Common issues:
     - Kubelet API not accessible (firewall/certificate issues)
     - Metrics Server pod not running: `kubectl describe pod -n kube-system -l k8s-app=metrics-server`

---

## Lab 2: Create and Configure HPA

**Objective**: Set up Horizontal Pod Autoscaler targeting CPU utilization.

### Manifest: `app-with-hpa.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hpa-demo
spec:
  replicas: 2
  selector:
    matchLabels:
      app: hpa-demo
  template:
    metadata:
      labels:
        app: hpa-demo
    spec:
      containers:
      - name: nginx
        image: nginx:latest
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: "100m"
            memory: "64Mi"
          limits:
            cpu: "500m"
            memory: "256Mi"

---
apiVersion: v1
kind: Service
metadata:
  name: hpa-demo
spec:
  selector:
    app: hpa-demo
  ports:
  - port: 80
    targetPort: 80
  type: LoadBalancer

---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: hpa-demo
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: hpa-demo
  minReplicas: 2
  maxReplicas: 8
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 50  # Scale when average CPU > 50%
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 0 # No cool down. The HPA reacts immediately to increased load without waiting to see if the spike is sustained.
      policies:
      - type: Percent # type: Percent, value: 100, periodSeconds: 30: Can double (100%) the current pod count every 30 seconds. So 2 pods → 4 → 8 etc.
        value: 100
        periodSeconds: 30
    scaleDown:
      stabilizationWindowSeconds: 300 # Waits 5 minutes of sustained low load before scaling down, preventing flapping from brief dips in traffic.
      policies:
      - type: Percent # Percent, value: 50, periodSeconds: 60: Can only remove half the pods per minute. So 16 → 8 → 4 → 2, stepping down gradually.
        value: 50
        periodSeconds: 60
```


### Steps:

1. **Deploy the application**:
   ```bash
   kubectl apply -f app-with-hpa.yaml
   ```

2. **Verify HPA creation**:
   ```bash
   kubectl get hpa
   kubectl describe hpa hpa-demo
   ```

3. **View HPA status repeatedly**:
   ```bash
   kubectl get hpa hpa-demo --watch
   ```

4. **Examine HPA events**:
   ```bash
   kubectl describe hpa hpa-demo
   kubectl get events --sort-by='.lastTimestamp' | grep hpa-demo
   ```

---

## Lab 3: Generate Load and Watch HPA Scale

**Objective**: Create CPU load and observe pods scale up in real-time.

### Steps:

1. **Open three terminals**:

   **Terminal 1 - Watch HPA status**:
   ```bash
   kubectl get hpa hpa-demo --watch
   ```

   **Terminal 2 - Watch pod count**:
   ```bash
   kubectl get pods -l app=hpa-demo --watch
   ```

2. **Generate load** (Terminal 3):
   ```bash
   # Get the service IP or LoadBalancer endpoint
   SERVICE_IP=$(kubectl get svc hpa-demo -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

   # Generate continuous HTTP requests (using kubectl run)
   kubectl run -it --rm load-generator --image=busybox /bin/sh

   # Inside the load-generator pod:
   while true; do wget -q -O- http://hpa-demo; done
   ```

3. **Observe scaling**:
   - Within 1-2 minutes, metrics should show increasing CPU usage
   - HPA should calculate desired replicas and scale up
   - Watch Terminal 2 for new pods appearing
   - Terminal 1 shows replica count increasing

4. **Monitor HPA decision calculation**:
   ```bash
   kubectl describe hpa hpa-demo
   ```
   Look for `Current Metrics` showing actual CPU utilization percentage.

---

## Lab 4: Deploy Cluster Autoscaler on EKS

**Objective**: Install and configure the Kubernetes Cluster Autoscaler on an EKS cluster so that worker nodes scale automatically when pods cannot be scheduled due to insufficient resources.

**Why is this needed?** HPA scales pods, but if the existing nodes don't have enough capacity for those new pods, they remain in `Pending` state. The Cluster Autoscaler watches for unschedulable pods and automatically adds nodes by adjusting the EC2 Auto Scaling Group (ASG) desired capacity. It also removes underutilized nodes to save costs.

### Step 1: Verify Your Node Group's ASG Configuration

Before installing the Cluster Autoscaler, check your node group's Auto Scaling Group settings and increase the maximum capacity to allow scaling:

```bash
# Find the ASG name for your cluster
# Replace <your-cluster-name> with your actual EKS cluster name
export CLUSTER_NAME=<your-cluster-name>

aws autoscaling describe-auto-scaling-groups \
  --query "AutoScalingGroups[? Tags[? (Key=='eks:cluster-name') && Value=='${CLUSTER_NAME}']].[AutoScalingGroupName, MinSize, MaxSize, DesiredCapacity]" \
  --output table
```

Increase the max capacity to allow the autoscaler room to add nodes:

```bash
# Get the ASG name
export ASG_NAME=$(aws autoscaling describe-auto-scaling-groups \
  --query "AutoScalingGroups[? Tags[? (Key=='eks:cluster-name') && Value=='${CLUSTER_NAME}']].AutoScalingGroupName" \
  --output text)

# Update max capacity (e.g., allow up to 5 nodes)
aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name ${ASG_NAME} \
  --min-size 2 \
  --desired-capacity 2 \
  --max-size 5

# Verify the updated values
aws autoscaling describe-auto-scaling-groups \
  --query "AutoScalingGroups[? Tags[? (Key=='eks:cluster-name') && Value=='${CLUSTER_NAME}']].[AutoScalingGroupName, MinSize, MaxSize, DesiredCapacity]" \
  --output table
```

### Step 2: Create an IAM Policy for Cluster Autoscaler

The Cluster Autoscaler needs permissions to describe and modify Auto Scaling Groups.

1. Create the policy JSON file:

```bash
cat > cluster-autoscaler-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:DescribeAutoScalingInstances",
        "autoscaling:DescribeLaunchConfigurations",
        "autoscaling:DescribeTags",
        "autoscaling:SetDesiredCapacity",
        "autoscaling:TerminateInstanceInAutoScalingGroup",
        "ec2:DescribeLaunchTemplateVersions"
      ],
      "Resource": "*",
      "Effect": "Allow"
    }
  ]
}
EOF
```

2. Create the IAM policy:

```bash
aws iam create-policy \
  --policy-name AmazonEKSClusterAutoscalerPolicy \
  --policy-document file://cluster-autoscaler-policy.json
```

Note the **Policy ARN** from the output — you will need it in Step 3.

### Step 3: Create an IAM Role for the Cluster Autoscaler Service Account

- Open the IAM console at https://console.aws.amazon.com/iam/.
- In the left navigation pane, choose **Roles**.
- On the Roles page, choose **Create role**.
- On the Select trusted entity page, do the following:
  - In the Trusted entity type section, choose **Web identity**.
  - For Identity provider, choose the **OpenID Connect provider URL** for your cluster (as shown under Overview in Amazon EKS).
  - For Audience, choose **sts.amazonaws.com**.
  - Choose **Next**.
- On the Add permissions page, do the following:
  - In the Filter policies box, enter **AmazonEKSClusterAutoscalerPolicy**.
  - Select the check box to the left of the **AmazonEKSClusterAutoscalerPolicy** returned in the search.
  - Choose **Next**.
- On the Name, review, and create page, do the following:
  - For Role name, enter **AmazonEKS_Cluster_Autoscaler_Role**.
  - Choose **Create role**.
- After the role is created, choose the role in the console to open it for editing.
- Choose the **Trust relationships** tab, and then choose **Edit trust policy**.
- Find the line that looks similar to the following line:

```
"oidc.eks.region-code.amazonaws.com/id/CF856D2CC9C5E229C4C6D3D43B178C5E:aud": "sts.amazonaws.com"
```

- Add a comma to the end of the previous line, and then add the following line after it. Replace `region-code` with the AWS Region that your cluster is in. Replace `CF856D2CC9C5E229C4C6D3D43B178C5E` with your cluster's OIDC provider ID.

```
"oidc.eks.region-code.amazonaws.com/id/CF856D2CC9C5E229C4C6D3D43B178C5E:sub": "system:serviceaccount:kube-system:cluster-autoscaler"
```

- Choose **Update policy** to finish.
- Note the **Role ARN** — you will need it in Step 4.

### Step 4: Deploy the Cluster Autoscaler

1. Download the Cluster Autoscaler manifest:

```bash
curl -o cluster-autoscaler-autodiscover.yaml \
  https://raw.githubusercontent.com/kubernetes/autoscaler/master/cluster-autoscaler/cloudprovider/aws/examples/cluster-autoscaler-autodiscover.yaml
```

2. Edit the manifest — replace `<YOUR CLUSTER NAME>` with your actual cluster name:

```bash
sed -i "s/<YOUR CLUSTER NAME>/${CLUSTER_NAME}/g" cluster-autoscaler-autodiscover.yaml
```

3. Annotate the Service Account in the manifest with the IAM role ARN. Open `cluster-autoscaler-autodiscover.yaml` and add the annotation under the ServiceAccount section:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: cluster-autoscaler
  namespace: kube-system
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::<ACCOUNT_ID>:role/AmazonEKS_Cluster_Autoscaler_Role
```

4. Apply the manifest:

```bash
kubectl apply -f cluster-autoscaler-autodiscover.yaml
```

5. Add the safe-to-evict annotation to prevent the Cluster Autoscaler from evicting itself:

```bash
kubectl -n kube-system annotate deployment.apps/cluster-autoscaler \
  cluster-autoscaler.kubernetes.io/safe-to-evict="false"
```

6. Set the Cluster Autoscaler image to match your Kubernetes version. Check the [Cluster Autoscaler releases page](https://github.com/kubernetes/autoscaler/releases) for the version that matches your cluster:

```bash
# Check your cluster's Kubernetes version
kubectl version --short

# Update the image (replace v1.XX.X with the matching version)
kubectl set image deployment cluster-autoscaler \
  -n kube-system \
  cluster-autoscaler=registry.k8s.io/autoscaling/cluster-autoscaler:v1.XX.X
```

### Step 5: Verify the Cluster Autoscaler is Running

```bash
# Check the pod is running
kubectl get pods -n kube-system -l app=cluster-autoscaler

# Check the logs
kubectl logs -n kube-system deployment/cluster-autoscaler | tail -20
```

You should see log entries indicating the autoscaler is scanning for unschedulable pods and monitoring node utilization.

---

## Lab 5: Test Cluster Autoscaler - Scale Nodes Up and Down

**Objective**: Create a workload that exceeds current node capacity and observe the Cluster Autoscaler add new nodes automatically.

### Steps:

1. **Check the current node count**:

```bash
kubectl get nodes
```

Note the current number of nodes (e.g., 2).

2. **Open monitoring terminals**:

   **Terminal 1 - Watch nodes**:
   ```bash
   kubectl get nodes --watch
   ```

   **Terminal 2 - Watch pods**:
   ```bash
   kubectl get pods -l app=ca-test --watch
   ```

   **Terminal 3 - Watch Cluster Autoscaler logs**:
   ```bash
   kubectl logs -f -n kube-system deployment/cluster-autoscaler
   ```

3. **Deploy a workload that requests more resources than available**:

```bash
cat > ca-test-deployment.yaml <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ca-test
spec:
  replicas: 15
  selector:
    matchLabels:
      app: ca-test
  template:
    metadata:
      labels:
        app: ca-test
    spec:
      containers:
      - name: nginx
        image: nginx:latest
        resources:
          requests:
            cpu: "200m"
            memory: "128Mi"
EOF

kubectl apply -f ca-test-deployment.yaml
```

4. **Observe the scaling behavior**:

```bash
# Check for pending pods (these trigger the autoscaler)
kubectl get pods -l app=ca-test | grep Pending

# Check Cluster Autoscaler activity
kubectl logs -n kube-system deployment/cluster-autoscaler | grep -i "scale up"
```

- Some pods will go into `Pending` state because existing nodes don't have enough capacity.
- The Cluster Autoscaler detects these pending pods within ~10 seconds.
- It calculates that a new node is needed and increases the ASG desired capacity.
- A new EC2 instance launches (takes ~2-3 minutes to join the cluster).
- Once the new node is `Ready`, pending pods get scheduled on it.

5. **Verify a new node was added**:

```bash
kubectl get nodes
# You should see more nodes than before
```

6. **Test scale-down — reduce the workload**:

```bash
kubectl scale deployment ca-test --replicas=2
```

- Wait ~10 minutes (the default scale-down delay).
- The Cluster Autoscaler identifies underutilized nodes (below 50% utilization by default).
- It drains the node and terminates the EC2 instance.

```bash
# Watch the nodes reduce over time
kubectl get nodes --watch

# Check autoscaler logs for scale-down activity
kubectl logs -n kube-system deployment/cluster-autoscaler | grep -i "scale down"
```

7. **Cleanup**:

```bash
kubectl delete deployment ca-test
```

**Key Takeaway:** The Cluster Autoscaler complements HPA by ensuring there is always enough node capacity for the pods that HPA creates. HPA scales pods, Cluster Autoscaler scales nodes.

---

## Cleanup

```bash
# Remove all lab resources
kubectl delete -f app-with-hpa.yaml
kubectl delete deployment ca-test --ignore-not-found
kubectl delete -f cluster-autoscaler-autodiscover.yaml

# Reset the ASG max capacity if needed
aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name ${ASG_NAME} \
  --max-size 2
```

---

## Further Reading

- [Cluster Autoscaler on AWS](https://github.com/kubernetes/autoscaler/blob/master/cluster-autoscaler/cloudprovider/aws/README.md)
- [EKS Best Practices - Cluster Autoscaling](https://docs.aws.amazon.com/eks/latest/best-practices/cas.html)
- [VPA Documentation](https://github.com/kubernetes/autoscaler/tree/master/vertical-pod-autoscaler)
- [Karpenter - Next-gen Node Autoscaling](https://karpenter.sh/)