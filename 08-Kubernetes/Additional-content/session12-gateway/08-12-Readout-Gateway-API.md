# Session 08-12: Kubernetes Gateway API - Readout

## What is Gateway API?

The Kubernetes Gateway API is an official, vendor-neutral, role-oriented set of resources for configuring L4 and L7 traffic routing into and within a Kubernetes cluster. It is maintained by the Kubernetes SIG-Network community as a successor to the legacy `Ingress` resource. The core resources (`GatewayClass`, `Gateway`, `HTTPRoute`) reached **GA in v1.0 (October 2023)**. The current standard channel is **v1.5 (released February 2026)**, which graduated several previously experimental features to Stable. `GRPCRoute` graduated to GA in v1.1. 

Unlike `Ingress`, the Gateway API is not a single overloaded object decorated with controller-specific annotations. It is a layered, multi-resource model designed for production multi-tenant clusters.

## Why It Exists (Problems with Ingress)

The legacy `networking.k8s.io/v1 Ingress` resource has few limitations that drove the creation of Gateway API:

- **Annotation sprawl.** Every advanced feature (TLS policies, redirects, header rewrites, weighted routing, timeouts) is implemented through controller-specific annotations like `alb.ingress.kubernetes.io/...` or `nginx.ingress.kubernetes.io/...`. This makes manifests non-portable.
- **No protocol coverage beyond HTTP.** Ingress is HTTP-only. TCP, UDP, gRPC, and TLS passthrough must be hacked in via CRDs or annotations.
- **No clear separation of concerns.** A single `Ingress` mixes infrastructure concerns (which load balancer, certs, policies) with application concerns (which paths route to which Service). Cluster operators and app developers end up colliding on the same object.
- **Cross-namespace references are unsafe.** There's no native way to authorize an Ingress in one namespace to reference a Service in another - Gateway API solves this with `ReferenceGrant`.

## Resource Model

Gateway API splits responsibilities across four primary resources:

| Resource           | API Group / Version                    | Purpose                                                                 |
|--------------------|----------------------------------------|-------------------------------------------------------------------------|
| `GatewayClass`     | `gateway.networking.k8s.io/v1`         | Cluster-scoped. Identifies the controller (e.g. AWS LBC, NGINX, Envoy, Istio) implementing Gateways. |
| `Gateway`          | `gateway.networking.k8s.io/v1`         | Namespaced. Declares one or more listeners (port + protocol + TLS) - i.e., the actual data plane. |
| `HTTPRoute`        | `gateway.networking.k8s.io/v1`         | Namespaced. Defines L7 HTTP routing rules attached to a `Gateway`.       |
| `GRPCRoute`        | `gateway.networking.k8s.io/v1`         | Namespaced. gRPC-specific routing (GA in v1.1).                          |
| `TLSRoute`         | `gateway.networking.k8s.io/v1`         | Namespaced. TLS passthrough routing. Promoted to **Standard / GA in v1.5** (Feb 2026). |
| `TCPRoute`/`UDPRoute` | `gateway.networking.k8s.io/v1alpha2` | Experimental L4 routes for raw TCP/UDP.                             |
| `ReferenceGrant`   | `gateway.networking.k8s.io/v1`         | Namespaced. Authorizes cross-namespace references (e.g. an HTTPRoute in `ns-a` referencing a Service in `ns-b`). Promoted to **Standard / GA in v1.5**; `v1beta1` is still served for backwards compatibility. |

The model maps cleanly to **three distinct roles**, each owning their own resources.

## Roles

| Role                  | Owns                                  | Typical persona                          |
|-----------------------|---------------------------------------|------------------------------------------|
| Infrastructure Provider | `GatewayClass`                       | Cloud provider, platform team, or controller vendor - defines what implementations are available. |
| Cluster Operator      | `Gateway` (listeners, TLS, addresses) | Platform / SRE team - owns the load balancers, certificates, and which routes can attach. |
| Application Developer | `HTTPRoute`, `GRPCRoute`, etc.        | Service owner - owns route rules, backends, weights, headers. Cannot tamper with the listener config. |

This separation is the single biggest practical improvement over Ingress: app teams ship route changes without touching shared infrastructure, and platform teams enforce TLS / hostname / namespace policies without blocking app teams.

## Implementations

Gateway API has many conformant implementations. Pick one based on your platform:

| Implementation                  | Notes                                                                           |
|---------------------------------|---------------------------------------------------------------------------------|
| **AWS Load Balancer Controller (Gateway API)** | Same controller you used in Session 6 for Ingress. Since v2.13 it also reconciles Gateway API: L7 routes (`HTTPRoute`, `GRPCRoute`) provision an **ALB** via `GatewayClass` controllerName `gateway.k8s.aws/alb`; L4 routes (`TCPRoute`, `UDPRoute`, `TLSRoute`) provision an **NLB** via `gateway.k8s.aws/nlb`. The default AWS-on-EKS choice. Used in Lab 2. |
| **NGINX Gateway Fabric**        | Official NGINX implementation. Works on any cluster (minikube, kind, EKS). Used in Lab 1.        |
| **Envoy Gateway**               | CNCF project, Envoy-based, lightweight standalone control plane.                |
| **Istio**                       | Service mesh; Gateway API replaces the legacy `Gateway`/`VirtualService` for ingress. Also implements GAMMA. |
| **Cilium**                      | eBPF-based, integrates with Cilium's existing networking stack.                 |
| **Contour**                     | Envoy-based, by VMware/Tanzu.                                                   |
| **Kong Gateway / Kong Ingress** | Kong's Gateway API implementation; rich plugin ecosystem.                       |
| **HAProxy / Traefik**           | Both ship Gateway API support in addition to legacy Ingress.                    |
| **Google Kubernetes Engine (GKE)** | First-party Gateway controller using Google Cloud Load Balancers.            |

## When to Use What

- **New cluster, new app, no Ingress legacy?** Start with Gateway API. There is no reason to pick Ingress for greenfield work in 2026.
- **Existing Ingress + AWS LBC working fine, no advanced routing needs?** Keep it. Ingress is still GA and supported. Plan a migration when you need header routing, weighted splitting, or stricter role boundaries.
- **Multi-tenant cluster with platform team + many app teams?** Gateway API. The role separation is a good feature.
- **On EKS and want Gateway API in front of pods (ALB/NLB)?** Use the AWS Load Balancer Controller's Gateway API support — it's the same controller you already have from Session 6, no extra controller to install.
- **Need TLS passthrough, raw TCP, UDP, or gRPC routing?** Gateway API; Ingress simply cannot express these.