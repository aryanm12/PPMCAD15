Any app which we develop... it does not get deployed to production env directly...

devs write code -> dev env

qa does testing -> qa env

user acceptance testing -> uat env

staging env -> stg env

pre-prod env -> pre-prod env

certification env 

finally it is -> prod env

------------------

My app is one, and I have written the code and I have created all the Kubernetes manifest files for my code...

deployment.yaml
hpa.yaml
service.yaml
ingress.yaml
cm.yaml
secret.yaml
pvc.yaml

the question is, when I apply these k8s manifest files in dev env and when I apply these k8s manifest in uat env and finally when I apply these in prod env

Do you think the same files with same content can be applied always?

Absolute NO...

why?

the database value will change in each env... deployment replicas will change in each env... resource request and limit may change..we don't even need HPA type of resource in any of the non-prod envs..cert name, cert location


what is the solution?

can't we simply use variable / dynamic values inside k8s manifest files? No


then what is the solution..

1.) why can't I create env specific manifest files.. I created a new configmap with name cm-qa.yaml secret-qa.yaml..

uat env for me .... so this approach.. I ended up created 6 files instead to 2 that too I am still in UAT

Technical Debt of the code base..

2.) Let me use some placeholders inside my manifest files and replace these placeholder at the run time using shell commands...

suppose I have this secret:


secret.yaml:

apiVersion: v1
kind: Secret
metadata:
  name: backend-secret
  namespace: shopnow-demo
type: Opaque
stringData:
  MONGODB_URI: MONGODB_ACTUAL_URI

kubectl apply -f secret.yaml - will put incorrect secret in K8S

so, before applying the above..

I use to run a few shell commands:

like:

cd k8s-manifest
run: `sed` command to replace all these placeholders inside all the k8s manifest files with dev values..


sed 's/MONGODB_ACTUAL_URI/mongodb://shopuser:ShopNowPass123@mongo-0.mongo-headless.shopnow-demo.svc.cluster.local:27017/shopnow?authSource=admin/g' > secrets.yaml  

then apply these file


similarly I would do the same in qa, uat, prod

---

HELM (written in go).. gives you the native capability to templatize  your k8s manifest files