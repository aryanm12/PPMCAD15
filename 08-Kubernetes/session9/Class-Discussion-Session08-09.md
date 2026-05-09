# Class Discussion - Session 8-09
# Storage in Kubernetes — CSI, PV/PVC, StorageClass & Headless Services

---

## How Kubernetes Stays Pluggable — CNI vs CSI

Kubernetes doesn't ship with built-in networking or storage. Instead, it defines **interfaces** and lets vendors plug in their own implementations.

| Interface | What it plugs in | Examples |
|---|---|---|
| **CNI** (Container Network Interface) | Pod networking | VPC CNI (AWS), Calico, Cilium, Flannel |
| **CSI** (Container Storage Interface) | Pod storage | EBS CSI Driver, EFS CSI Driver, ceph-csi, Azure Disk CSI |

Same idea both times — Kubernetes says "here's the contract," and the cloud provider or storage vendor writes a driver that fulfills it. Want to use AWS EBS volumes in your pods? Install the EBS CSI Driver. Want Ceph? Install ceph-csi. Kubernetes itself doesn't care what's underneath.

---

## The Problem PV and PVC Solve

### The Laptop Analogy

Imagine you have **10 laptops**. Each one has its own internal SSD - that's local, isolated storage. Fine for personal files.

Now you want all 10 laptops to **share a common folder**. What do you do?

1. Buy an external storage device (NAS / NFS server)
2. Configure it on your network
3. Mount the NFS share on each laptop

Now all 10 laptops see the same folder. Write a file from laptop 3, read it from laptop 7.

### Same Problem in Kubernetes

You have **10 replicas of an app** running as pods. Pods are ephemeral - they come and go. If a pod writes data to its own filesystem, that data dies with the pod.

You need:
- Storage that **outlives the pod**
- Storage that can be **shared or attached** as the pod is rescheduled
- Storage that the cluster can manage as a first-class resource

That's what PV and PVC give you.

```
External NFS / EBS / Ceph   →   PersistentVolume (PV)   →   PersistentVolumeClaim (PVC)   →   Pod
   (the actual storage)         (cluster resource)              (the request)              (the consumer)
```

---

## PV vs PVC — Who Does What

| | PersistentVolume (PV) | PersistentVolumeClaim (PVC) |
|---|---|---|
| **What it is** | The actual storage resource in the cluster | A request for storage by a user/pod |
| **Who creates it** | Cluster admin (or dynamically by a CSI driver) | Application developer |
| **Analogy** | The available apartment | The rental application |
| **Scope** | Cluster-wide | Namespaced |
| **Describes** | Capacity, access modes, where the storage actually lives | How much storage is needed, what access mode, which StorageClass |

The PVC binds to a PV that satisfies its request. The pod then references the PVC - it never references the PV directly.

---

## StorageClass — The Two Jobs

A StorageClass has two distinct responsibilities. Most people only know about the first one.

### Job 1: Dynamic Provisioning

When a developer creates a PVC, the StorageClass tells Kubernetes **how to automatically create a PV** for it. No admin needed.

```
Developer creates PVC  →  StorageClass triggers CSI driver  →  Driver provisions actual disk  →  PV created  →  PVC bound
```

Example: PVC with `storageClassName: gp3` → EBS CSI driver creates a real EBS volume in AWS → PV gets created automatically → bound to the PVC.

### Job 2: Controlling Binding Behavior

Even when **no dynamic provisioning** is happening (like with local storage), the StorageClass controls *when* a PVC binds to a PV via `volumeBindingMode`:

- **`Immediate`** (default) — PVC binds to a PV as soon as it's created
- **`WaitForFirstConsumer`** — PVC stays Pending until a pod is created, then binds based on where the pod will run

For local storage, Job 2 is the whole reason you'd create a StorageClass at all (with `provisioner: kubernetes.io/no-provisioner`).

---

## Service Types — A Refresher

### Normal ClusterIP Service

Use case: **stateless apps** where any replica can serve any request.

```
Nginx Deployment with 5 replicas

         nginx-service (ClusterIP: 10.96.x.x)
         DNS: nginx-service.default.svc.cluster.local
                          │
       ┌──────┬───────────┼───────────┬──────┐
       ▼      ▼           ▼           ▼      ▼
     pod-1  pod-2       pod-3       pod-4  pod-5
```

The service has **one VIP and one DNS name**. Traffic is load-balanced across all 5 pods. The client doesn't know or care which pod answers.

### Headless Service

Use case: **stateful apps** where each replica has an identity (a primary, replicas, shards, etc.).

Created by setting `clusterIP: None` on the service. There's **no VIP** - instead, DNS resolves directly to individual pod IPs.

```
MySQL StatefulSet with 3 replicas + Headless Service "mysql-headless"

mysql-0.mysql-headless  →  pod-0's IP
mysql-1.mysql-headless  →  pod-1's IP
mysql-2.mysql-headless  →  pod-2's IP
```

Each pod is **individually addressable by name**. This is essential for things like:
- Replication setup ("replica, follow `mysql-0`")
- Cluster membership ("join the cluster at `mysql-0.mysql-headless`")
- Quorum protocols (Zookeeper, etcd, Cassandra, Kafka)

---

## Open Question from Class

> **Can we use a headless service to send writes only to the master (db-0) and reads to the replicas?**

**Short answer: not by itself.**

A headless service just gives you DNS records for each pod. It doesn't *route* anything - there's no proxy or load balancer in the path. So the headless service alone can't decide "this is a write, send it to db-0."

**How it's actually done in practice:**

The split happens at the **application layer**, not the service layer. Common patterns:

1. **Two services** — create a regular ClusterIP `mysql-write` selecting only the primary pod (via a label like `role: primary`), and `mysql-read` selecting the replicas. The app sends writes to one, reads to the other.

2. **App-aware client / connection string** — many database drivers accept separate read and write endpoints. The app uses `mysql-0.mysql-headless` for writes and round-robins reads across `mysql-1` / `mysql-2`.

3. **Proxy in front** — tools like ProxySQL, PgBouncer, or Vitess sit between the app and the DB and inspect the SQL itself. Writes (INSERT/UPDATE/DELETE) → primary. Reads (SELECT) → replicas. This is the cleanest solution for production.

The headless service is the **foundation** that makes individual pods addressable - but the read/write split logic lives above it.

---

## Key Takeaways

> **CSI is to storage what CNI is to networking - a pluggable interface, not an implementation.**

> **PVC is the request, PV is the resource. Pods talk to PVCs, not PVs.**

> **StorageClass does two things: dynamic provisioning *and* binding policy. Don't forget the second one.**

> **ClusterIP = one VIP load-balancing across replicas. Headless = no VIP, each pod individually addressable by DNS.**

> **Read/write splitting isn't a service feature - it's an application or proxy feature built on top of headless services.**

---