# Local Persistent Volumes in Kubernetes

## Scenario

A customer runs Kubernetes in their own on-prem datacenter. Each worker node has a local SSD physically attached to it (e.g., `/mnt/disks/vol1`). They want a stateful workload (a PostgreSQL database) to use this fast local storage instead of network-attached storage.

This is the classic use case for **local persistent volumes**: high-performance storage that lives on a specific node.

---

## Key Principles

1. **Local PVs are node-pinned.** A pod using a local PV will only run on the node where the disk physically exists. Plan for this — if the node dies, the workload doesn't reschedule elsewhere.
2. **No dynamic provisioning.** You manually create one PV per disk/directory. There's no auto-provisioner like with cloud volumes.
3. **Always use a StorageClass with `WaitForFirstConsumer`.** This makes the scheduler bind the PVC only after a pod is created, so PV-to-pod placement decisions stay coordinated.
4. **The directory must pre-exist on the node.** Local PVs do not create the path for you.
5. **Use `local`, not `hostPath`.** The `local` volume type is node-aware via `nodeAffinity`; `hostPath` is not and is unsafe in multi-node clusters.
6. **Reclaim policy `Retain` is the safe default.** Data on local disks is precious — don't let it auto-delete.

---

## Full Cycle Example

**Scenario:** Deploy a PostgreSQL pod that stores its data on a local SSD mounted at `/mnt/disks/pgdata` on `worker-node-1`.

### Step 0: Prepare the node (one-time, on the node itself)

```bash
# SSH into worker-node-1
ssh worker-node-1
sudo mkdir -p /mnt/disks/pgdata
sudo chmod 700 /mnt/disks/pgdata
# (Optionally mount the dedicated SSD at this path via /etc/fstab)
```

### Step 1: Create the StorageClass

```yaml
# storageclass.yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-storage
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Retain
```

Apply once for the whole cluster:

```bash
kubectl apply -f storageclass.yaml
```

### Step 2: Create the PersistentVolume

```yaml
# pv.yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pg-local-pv-node1
spec:
  capacity:
    storage: 50Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: local-storage
  local:
    path: /mnt/disks/pgdata
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - worker-node-1
```

```bash
kubectl apply -f pv.yaml
kubectl get pv pg-local-pv-node1
# STATUS: Available
```

### Step 3: Create the PersistentVolumeClaim

```yaml
# pvc.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pg-data-pvc
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: local-storage
  resources:
    requests:
      storage: 50Gi
```

```bash
kubectl apply -f pvc.yaml
kubectl get pvc pg-data-pvc
# STATUS: Pending  ← expected! WaitForFirstConsumer holds binding until a pod appears.
```

### Step 4: Create the Deployment

```yaml
# deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgres
  namespace: default
spec:
  replicas: 1   # IMPORTANT: only 1 — local PV is RWO and pinned to a node.
  strategy:
    type: Recreate   # Avoid two pods trying to mount the same PV during rollout.
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
      - name: postgres
        image: postgres:16
        ports:
        - containerPort: 5432
        env:
        - name: POSTGRES_PASSWORD
          value: "changeme"
        - name: PGDATA
          value: /var/lib/postgresql/data/pgdata
        volumeMounts:
        - name: pg-storage
          mountPath: /var/lib/postgresql/data
      volumes:
      - name: pg-storage
        persistentVolumeClaim:
          claimName: pg-data-pvc
```

```bash
kubectl apply -f deployment.yaml
```

### Step 5: Verify the full chain

```bash
kubectl get pvc pg-data-pvc
# STATUS: Bound  ← now bound, because the pod was created.

kubectl get pv pg-local-pv-node1
# STATUS: Bound, CLAIM: default/pg-data-pvc

kubectl get pods -o wide
# postgres-xxx  Running  ...  worker-node-1   ← scheduled on the right node automatically.
```

---