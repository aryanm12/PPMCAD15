# AWS Security Groups — Referencing SGs Instead of CIDRs

## The Setup

A classic three-tier-ish architecture on AWS:

```
Internet  →  ALB  →  EC2 (Java app on port 8080)
```

The ALB is publicly accessible. The EC2 instance behind it runs a Java application listening on port 8080. We want **only the ALB** to be able to reach the EC2 on port 8080 — not other EC2s in the VPC, not bastion hosts, not random workloads on the same subnet.

## Approach 1 — Allow the Whole VPC CIDR (the lazy way)

In the EC2's security group, add an inbound rule:

| Type | Protocol | Port | Source |
|---|---|---|---|
| Custom TCP | TCP | 8080 | `10.0.0.0/16` (VPC CIDR) |

This works - the ALB can now reach port 8080. But so can:

- Every other EC2 in the VPC
- Every Lambda attached to the VPC
- Every other resource sharing the CIDR

You've solved the connectivity problem but opened the door way wider than needed. **Principle of least privilege violated.**

## Approach 2 — Reference the ALB's Security Group (the right way)

Security groups in AWS can reference **other security groups** as a source, not just IPs and CIDRs. This is the cleanest way to express "only this thing can talk to me."

In the EC2's security group, add an inbound rule:

| Type | Protocol | Port | Source |
|---|---|---|---|
| Custom TCP | TCP | 8080 | `sg-0abc123...` (the ALB's SG ID) |

Now port 8080 is **only** reachable from network interfaces that have the ALB's SG attached to them. Every other resource in the VPC is blocked, regardless of its IP.

## Why This Is Better

| Aspect | CIDR-based rule | SG-reference rule |
|---|---|---|
| **Scope** | Anything in the CIDR | Only resources with that specific SG |
| **Survives IP changes** | Have to update if subnets change | Identity-based, IP-agnostic |
| **Auto-scaling friendly** | New ALB nodes get random IPs in the subnet — CIDR has to be wide | New ALB ENIs inherit the SG automatically |
| **Auditability** | "Who is `10.0.5.42`?" — investigate | The rule literally names the resource type |
| **Least privilege** | Loose | Tight |

The auto-scaling point is the killer one in practice. An ALB isn't a single IP — AWS provisions multiple ENIs across AZs, and they can change. Trying to lock down by IP is a losing battle. Locking down by SG is stable.

## The Mental Model

> **Security Groups are identity tags, not just firewall rules.**

When you attach an SG to a resource, you're stamping it with an identity. When another SG references that SG as a source, it's saying *"I trust resources wearing that stamp"* — regardless of where they live or what IP they have today.

## Where SGs Must Be Attached

A security group only does anything when it's attached to a resource that has a network interface (ENI). The common attachment points:

- **EC2 instances** (each instance gets one or more ENIs)
- **ALBs / NLBs** (each LB has ENIs in each AZ)
- **RDS instances** (the database's ENI)
- **Lambda functions** running inside a VPC
- **EKS pods** when using SGs for pods
- **Any other ENI** you create (VPC endpoints, transit gateway attachments, etc.)

If an SG isn't attached to anything, its rules are inert.

## The Pattern Generalized

This SG-referencing pattern applies any time you have a chain of services that should only talk in one direction:

```
ALB (sg-alb)
  ↓  port 8080 — source: sg-alb
EC2 / App tier (sg-app)
  ↓  port 3306 — source: sg-app
RDS (sg-rds)
```

- **ALB SG** allows 80/443 from `0.0.0.0/0` (public)
- **App SG** allows 8080 only from `sg-alb`
- **RDS SG** allows 3306 only from `sg-app`

Each tier exposes its port **only to the tier directly above it**. No CIDRs, no IP guesswork, no overly broad rules. The architecture is enforced by the SG graph itself.

---