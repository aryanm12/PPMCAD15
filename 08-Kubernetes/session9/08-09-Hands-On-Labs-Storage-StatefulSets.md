# Session 8-09: Storage - Volumes, PV/PVC & StatefulSets - Hands-On Labs

---

## Pre-requisite: AWS EBS CSI Driver Installation

> **Note:** The EBS CSI driver can also be installed via **AWS EKS Managed Add-Ons** from the AWS Console. The steps below cover the manual installation method using Helm.

### Step 1: Create an IAM Role

- Open the IAM console at https://console.aws.amazon.com/iam/.
- In the left navigation pane, choose **Roles**.
- On the Roles page, choose **Create role**.
- On the Select trusted entity page, do the following:
  - In the Trusted entity type section, choose **Web identity**.
  - For Identity provider, choose the **OpenID Connect provider URL** for your cluster (as shown under Overview in Amazon EKS).
  - For Audience, choose **sts.amazonaws.com**.
  - Choose **Next**.
- On the Add permissions page, do the following:
  - In the Filter policies box, enter **AmazonEBSCSIDriverPolicy**.
  - Select the check box to the left of the **AmazonEBSCSIDriverPolicy** returned in the search.
  - Choose **Next**.
- On the Name, review, and create page, do the following:
  - For Role name, enter a unique name for your role, such as **AmazonEKS_EBS_CSI_DriverRole**.
  - Choose **Create role**.
- After the role is created, choose the role in the console to open it for editing.
- Choose the **Trust relationships** tab, and then choose **Edit trust policy**.
- Find the line that looks similar to the following line:

```
"oidc.eks.region-code.amazonaws.com/id/CF856D2CC9C5E229C4C6D3D43B178C5E:aud": "sts.amazonaws.com"
```

- Add a comma to the end of the previous line, and then add the following line after it. Replace `region-code` with the AWS Region that your cluster is in. Replace `CF856D2CC9C5E229C4C6D3D43B178C5E` with your cluster's OIDC provider ID.

```
"oidc.eks.region-code.amazonaws.com/id/CF856D2CC9C5E229C4C6D3D43B178C5E:sub": "system:serviceaccount:kube-system:ebs-csi-controller-sa"
```

- Choose **Update policy** to finish.

### Step 2: Install the EBS CSI Driver via Helm

```bash
helm repo add aws-ebs-csi-driver https://kubernetes-sigs.github.io/aws-ebs-csi-driver
helm repo update
helm upgrade --install aws-ebs-csi-driver aws-ebs-csi-driver/aws-ebs-csi-driver -n kube-system
```

### Step 3: Verify the Driver Pods are Running

```bash
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-ebs-csi-driver
```

Once the driver pods are in `Running` state, you are ready to proceed with the storage labs below.

---

## Lab 1: StorageClass & Dynamic Provisioning

**Objective:** Use StorageClass to automatically create PersistentVolumes when PVCs are requested.

### Steps:

1. Check available StorageClasses:

```bash
kubectl get storageclass
```

2. Create a StorageClass (for EBS in AWS):

```bash
cat > storage-class.yaml <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ebs-gp3-sc
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  iops: "3000"
  throughput: "125"
reclaimPolicy: Delete
allowVolumeExpansion: true
EOF

kubectl apply -f storage-class.yaml
kubectl get storageclass
```

3. Create a PVC that references the StorageClass:

```bash
cat > pvc-dynamic.yaml <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: dynamic-pvc
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: ebs-gp3-sc
  resources:
    requests:
      storage: 5Gi
EOF

kubectl apply -f pvc-dynamic.yaml
```

**Access Modes:**
   - RWO (ReadWriteOnce): One pod reads & writes (EBS)
   - ROX (ReadOnlyMany): Many pods read only (NFS/EFS)
   - RWX (ReadWriteMany): Many pods read & write (NFS/EFS)


4. Watch the PV be auto-created:

```bash
kubectl get pvc dynamic-pvc -w
# Status changes from Pending → Bound in ~10-30 seconds

kubectl get pv
# A new PV should appear, automatically created!

kubectl describe pvc dynamic-pvc
```

5. Create a pod using the PVC:

```bash
cat > pod-dynamic-pvc.yaml <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: app-with-dynamic-storage
spec:
  containers:
  - name: app
    image: busybox
    volumeMounts:
    - name: data
      mountPath: /data
    command: ["sh", "-c", "echo 'Dynamic storage' > /data/note.txt; sleep 1000"]
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: dynamic-pvc
EOF

kubectl apply -f pod-dynamic-pvc.yaml
kubectl exec -it app-with-dynamic-storage -- cat /data/note.txt
```

**Key Takeaway:** StorageClass enables self-service provisioning without admin intervention.

---

## Lab 5: Deploy a StatefulSet - MySQL with Persistent Storage

**Objective:** Deploy a MySQL StatefulSet with unique PVCs per replica and a headless service for clustering.

### Steps:

1. Create the headless service:

```bash
cat > mysql-headless-service.yaml <<EOF
apiVersion: v1
kind: Service
metadata:
  name: mysql-headless
spec:
  clusterIP: None
  selector:
    app: mysql
  ports:
  - port: 3306
    name: mysql
EOF

kubectl apply -f mysql-headless-service.yaml
kubectl get svc mysql-headless
```

2. Create a ConfigMap for MySQL initialization:

```bash
cat > mysql-configmap.yaml <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: mysql-config
data:
  init.sql: |
    CREATE DATABASE IF NOT EXISTS testdb;
    CREATE TABLE IF NOT EXISTS testdb.users (
      id INT AUTO_INCREMENT PRIMARY KEY,
      name VARCHAR(100)
    );
    INSERT INTO testdb.users (name) VALUES ('Alice'), ('Bob');
EOF

kubectl apply -f mysql-configmap.yaml
```

3. Create the StorageClass (using the EBS CSI driver):

```bash
cat > mysql-storageclass.yaml <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: mysql-storage
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
reclaimPolicy: Delete
EOF

kubectl apply -f mysql-storageclass.yaml
```

4. Create the StatefulSet:

```bash
cat > mysql-statefulset.yaml <<EOF
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: mysql
spec:
  serviceName: mysql-headless
  replicas: 3
  selector:
    matchLabels:
      app: mysql
  template:
    metadata:
      labels:
        app: mysql
    spec:
      containers:
      - name: mysql
        image: mysql:5.7
        ports:
        - containerPort: 3306
          name: mysql
        env:
        - name: MYSQL_ROOT_PASSWORD
          value: "rootpassword"
        - name: MYSQL_DATABASE
          value: testdb
        volumeMounts:
        - name: mysql-data
          mountPath: /var/lib/mysql
        - name: config
          mountPath: /docker-entrypoint-initdb.d
      volumes:
      - name: config
        configMap:
          name: mysql-config
  volumeClaimTemplates:
  - metadata:
      name: mysql-data
    spec:
      accessModes: [ "ReadWriteOnce" ]
      storageClassName: mysql-storage
      resources:
        requests:
          storage: 5Gi
EOF

kubectl apply -f mysql-statefulset.yaml
```

5. Watch the StatefulSet scale up (ordered):

```bash
kubectl get statefulset mysql -w
# Watch: 0/3 → 1/3 → 2/3 → 3/3

kubectl get pods -l app=mysql
# Should see: mysql-0, mysql-1, mysql-2 (in order)

kubectl get pvc
# Should see: mysql-data-mysql-0, mysql-data-mysql-1, mysql-data-mysql-2
```

6. Test MySQL connectivity:

```bash
kubectl run -it --rm mysql-client --image=mysql:5.7 --restart=Never -- \
  mysql -h mysql-0.mysql-headless.default.svc.cluster.local \
  -uroot -prootpassword -e "SELECT * FROM testdb.users;"
```

**Key Takeaway:** StatefulSet ensures each pod gets its own storage and stable identity.

---

## Lab 6: Test StatefulSet Behavior

**Objective:** Verify pod identity persistence, ordering, and DNS resolution.

### Steps:

1. **Test 1: Pod Identity Persistence**

```bash
# Get the current pod
kubectl get pod mysql-0 -o wide

# Note the node it's running on

# Delete mysql-0
kubectl delete pod mysql-0

# Watch it recreate with the same name
kubectl get pods -l app=mysql -w

# mysql-0 should reappear on the same (or different) node
# But it will bind to the SAME PVC (mysql-data-mysql-0)
```

2. **Test 2: Ordered Scaling**

```bash
# Scale down
kubectl scale statefulset mysql --replicas=2
kubectl get pods -l app=mysql
# mysql-0, mysql-1 remain; mysql-2 is deleted

# Scale up
kubectl scale statefulset mysql --replicas=3
# mysql-2 is recreated (in order)

kubectl get pods -l app=mysql
```

3. **Test 3: Headless Service DNS**

```bash
# Launch a test pod
kubectl run -it --rm dns-test --image=busybox --restart=Never -- sh

# Inside the container:
nslookup mysql-0.mysql-headless.default.svc.cluster.local
nslookup mysql-1.mysql-headless.default.svc.cluster.local
nslookup mysql-2.mysql-headless.default.svc.cluster.local

# Compare with regular service DNS (notice no pod name):
nslookup mysql-headless.default.svc.cluster.local
# This returns multiple A records (one per pod)
```

4. **Test 4: Data Persistence Across Pod Restarts**

```bash
# Write data to mysql-1
kubectl exec -it mysql-1 -- mysql -uroot -prootpassword -e \
  "INSERT INTO testdb.users (name) VALUES ('Charlie');"

# Delete mysql-1
kubectl delete pod mysql-1

# Wait for it to recreate (watch mysql-1 come back)
kubectl get pods -w

# Query again - data is still there
kubectl exec -it mysql-1 -- mysql -uroot -prootpassword -e \
  "SELECT * FROM testdb.users;"
```

---

## Cleanup

```bash
kubectl delete statefulset mysql
kubectl delete svc mysql-headless
kubectl delete configmap mysql-config
kubectl delete storageclass mysql-storage
kubectl delete pvc --all
kubectl delete pod --all

# Optional: Clean up manually created resources
kubectl delete pv,pvc --all
```

---

## Key Concepts to Remember

1. **emptyDir:** Ephemeral, shared within a pod, deleted on pod termination
2. **PersistentVolume (PV):** Cluster-level storage resource
3. **PersistentVolumeClaim (PVC):** Pod's request for storage (1-to-1 binding with PV)
4. **StorageClass:** Automates PV creation via CSI drivers
5. **Access Modes:**
   - RWO (ReadWriteOnce): One pod reads & writes (EBS)
   - ROX (ReadOnlyMany): Many pods read only (NFS)
   - RWX (ReadWriteMany): Many pods read & write (NFS)
6. **StatefulSet:** Provides stable pod identity, ordered scaling, unique PVC per pod
7. **Headless Service:** Direct DNS to individual pods (clusterIP: None)
8. **volumeClaimTemplates:** Automatically create unique PVCs for each StatefulSet replica

---

## Additional Labs to cover:

## Lab 5: emptyDir Volume - Container-to-Container Sharing

**Objective:** Understand how emptyDir allows containers in the same pod to share ephemeral data.

### Steps:

1. Create a pod with emptyDir and two containers:

```bash
cat > pod-emptydir-lab.yaml <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: emptydir-demo
spec:
  containers:
  - name: writer
    image: busybox
    volumeMounts:
    - name: shared-data
      mountPath: /data
    command: ["sh", "-c", "for i in {1..5}; do echo 'Line '$i >> /data/shared.txt; sleep 2; done; sleep 100"]
  - name: reader
    image: busybox
    volumeMounts:
    - name: shared-data
      mountPath: /reader
    command: ["sh", "-c", "sleep 5; while true; do echo '--- Reader output ---'; cat /reader/shared.txt 2>/dev/null || echo 'File not yet written'; sleep 10; done"]
  volumes:
  - name: shared-data
    emptyDir: {}
EOF

kubectl apply -f pod-emptydir-lab.yaml
```

2. Watch both containers:

```bash
# Terminal 1: Watch writer
kubectl logs -f emptydir-demo -c writer

# Terminal 2: Watch reader
kubectl logs -f emptydir-demo -c reader
```

3. Verify they're sharing data (reader sees writer's output):

```bash
kubectl exec -it emptydir-demo -c reader -- cat /reader/shared.txt
```

4. Delete the pod and observe data is lost:

```bash
kubectl delete pod emptydir-demo
# Data is gone forever - emptyDir is ephemeral
```

**Key Takeaway:** emptyDir is perfect for inter-container communication within a pod but is destroyed when the pod terminates.

---

## Lab 6: ConfigMap as Volume - Mount Configuration Files

**Objective:** Mount a ConfigMap as a volume to serve static files from nginx.

### Steps:

1. Create a ConfigMap with HTML content:

```bash
cat > html-content.html <<EOF
<!DOCTYPE html>
<html>
<head><title>Storage Demo</title></head>
<body>
<h1>Hello from ConfigMap Volume!</h1>
<p>This HTML is stored in a ConfigMap and mounted as a volume.</p>
<p>Time: $(date)</p>
</body>
</html>
EOF

kubectl create configmap html-content --from-file=html-content.html
kubectl describe configmap html-content
```

2. Create a pod that mounts the ConfigMap:

```bash
cat > pod-configmap-vol-lab.yaml <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: nginx-configmap-demo
spec:
  containers:
  - name: nginx
    image: nginx:latest
    ports:
    - containerPort: 80
    volumeMounts:
    - name: html-vol
      mountPath: /usr/share/nginx/html
  volumes:
  - name: html-vol
    configMap:
      name: html-content
EOF

kubectl apply -f pod-configmap-vol-lab.yaml
```

3. Port-forward and test:

```bash
kubectl port-forward pod/nginx-configmap-demo 8080:80 &
curl http://localhost:8080/html-content.html
kill %1
```

4. Update the ConfigMap and verify the pod sees the change (within 1 minute):

```bash
kubectl edit configmap html-content
# Change the <p> text to something else

# Wait ~1 minute and refresh
kubectl port-forward pod/nginx-configmap-demo 8080:80 &
curl http://localhost:8080/html-content.html
```

**Key Takeaway:** ConfigMap volumes are read-only and updates propagate with a delay. Good for config files but not for data that pods write to.

---