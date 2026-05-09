Upgrade the node -> Vertical Scaling

Vertical scaling: I have an ec2 server with following specs:

2 Core vcpu and 4 GB RAM

My application running on this server, requires 2 vcpu and 6 GB RAM

-> I will upgrade my existing EC2 server configuration from 2 Core vcpu and 4 GB RAM to 4 vcpu and 16 GB RAM


---

Horizontal Scaling: 

1 server: 2 Core vcpu and 4 GB RAM

and I will add another server with the same configuration: 2 Core vcpu and 4 GB RAM

---

Horizontal scaling is what majorly constitutes Auto-scaling terminology 


---

I have an app running on EKS

my app has 3 replicas... 3 pods are running..

there is a sudden high load observed on my app...

1st -> Auto-scale the pods, add more replicas of the pod, 3->30 via HPA
2nd -> Auto-scale the worker nodes -> Cluster Auto-scalar

---


Why Auto-scaling:

- scale up our servers to avoid downtime..
- scale down to avoid excess cost..


On-Prem:
- Many of the resources are over-provisioned (if my app need 4 vcpu and 16 gb ram, 8 vcpu and 32 gb ram)

- auto-scaling will upgrade or downgrade...















