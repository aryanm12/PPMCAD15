# Session 08-13: External Secrets Operator (ESO) - Hands-On Labs

## Overview
In these labs you will install the External Secrets Operator, wire it to AWS Secrets Manager using IRSA, sync external secrets into native Kubernetes Secret objects, shape the resulting Secret with templates, share a single store across many namespaces, push a Kubernetes Secret back out to AWS, and watch the controller pick up an upstream value change.

Session 7 already covered how to create and consume native Kubernetes Secrets. We will not re-cover that material here. ESO does not replace `kind: Secret` - it produces them on your behalf from an upstream source of truth.

**Targeted ESO version:** v2.x (Helm chart `external-secrets` v2.4.x as of May 2026 — check `helm search repo external-secrets/external-secrets --versions` for the current release).

**API versions used in labs:**
- `external-secrets.io/v1` for `SecretStore`, `ClusterSecretStore`, `ExternalSecret`, `ClusterExternalSecret` (promoted to GA around v0.16; `v1beta1` was removed in v0.17).
- `external-secrets.io/v1alpha1` for `PushSecret` and `ClusterPushSecret` (still alpha at the time of writing - confirm against the docs for your installed version).

**Prerequisites:**
- Working Kubernetes cluster. EKS is assumed for the AWS labs (Sessions 5 and 6).
- `kubectl` configured against that cluster.
- `helm` v3.x installed locally.
- For the AWS path: AWS CLI v2 configured, an EKS cluster with an IAM OIDC provider already associated (done in Session 6), and permissions to create IAM roles and Secrets Manager secrets.

> All YAML and JSON used in these labs is shown inline. When a step says *"Save the following as `foo.yaml`"*, copy the block into a file with that name in your working directory and then run the `kubectl apply -f foo.yaml` that follows.

---

## Lab 1: Install the External Secrets Operator with Helm

### Objectives
- Add the official Helm repo and install ESO into its own namespace.
- Verify the controller, webhook, and cert-controller pods come up.
- Confirm CRDs are registered.

### Steps

1. **Add the Helm repository:**
   ```bash
   helm repo add external-secrets https://charts.external-secrets.io
   helm repo update
   ```

2. **Install the chart into the `external-secrets` namespace:**
   ```bash
   helm install external-secrets \
     external-secrets/external-secrets \
     -n external-secrets \
     --create-namespace \
     --set installCRDs=true
   ```

3. **Watch the operator pods come up:**
   ```bash
   kubectl get pods -n external-secrets -w
   ```
   You should see three Deployments running: `external-secrets`, `external-secrets-webhook`, and `external-secrets-cert-controller`.

### Verification
- Three operator pods are `Running` in `external-secrets`.
- All ESO CRDs are listed.
- `v1` is one of the served versions for `externalsecrets.external-secrets.io`.

---

## Lab 2: Configure a SecretStore for AWS Secrets Manager (IRSA)

### Objectives
- Create an IAM role that the ESO ServiceAccount can assume via IRSA.
- Create a sample secret in AWS Secrets Manager.
- Define a namespace-scoped `SecretStore` that reads from it.

### Steps

1. **Pick a working namespace and set environment variables:**
   ```bash
   export AWS_REGION=us-east-1
   export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
   export CLUSTER_NAME=<your-eks-cluster-name>
   export NS=eso-demo
   kubectl create namespace $NS
   ```

2. **Create the upstream secret in AWS Secrets Manager:**
   ```bash
   aws secretsmanager create-secret \
     --name dev/myapp/db \
     --region $AWS_REGION \
     --secret-string '{"username":"appuser","password":"S3cretFromAWS!","host":"db.internal","port":"5432"}'
   ```

3. **Create the IAM policy that allows reading that secret.** Save the following as `iam-policy-secretsmanager-read.json`:
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Action": [
           "secretsmanager:GetSecretValue",
           "secretsmanager:DescribeSecret",
           "secretsmanager:ListSecrets"
         ],
         "Resource": "*"
       }
     ]
   }
   ```
   ```bash
   aws iam create-policy \
     --policy-name ESOSecretsManagerRead \
     --policy-document file://iam-policy-secretsmanager-read.json
   ```

4. **Create an IAM role bound via IRSA to a ServiceAccount in `$NS` named `eso-sa`.** We will do this with the AWS CLI + `kubectl` — no `eksctl` required.

   First, look up the cluster's OIDC issuer URL (the IAM OIDC provider was already associated in Session 6):
   ```bash
   OIDC_URL=$(aws eks describe-cluster \
     --name $CLUSTER_NAME --region $AWS_REGION \
     --query "cluster.identity.oidc.issuer" --output text \
     | sed -e 's|^https://||')
   echo "$OIDC_URL"
   ```

   Save the trust policy as `eso-trust-policy.json` (uses shell substitution, so build it with `cat`):
   ```bash
   cat > eso-trust-policy.json <<EOF
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Principal": {
           "Federated": "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/${OIDC_URL}"
         },
         "Action": "sts:AssumeRoleWithWebIdentity",
         "Condition": {
           "StringEquals": {
             "${OIDC_URL}:sub": "system:serviceaccount:${NS}:eso-sa",
             "${OIDC_URL}:aud": "sts.amazonaws.com"
           }
         }
       }
     ]
   }
   EOF
   ```

   Create the IAM role and attach the read policy:
   ```bash
   aws iam create-role \
     --role-name eso-irsa-role \
     --assume-role-policy-document file://eso-trust-policy.json

   aws iam attach-role-policy \
     --role-name eso-irsa-role \
     --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/ESOSecretsManagerRead
   ```

   Create the Kubernetes ServiceAccount and annotate it with the role ARN:
   ```bash
   kubectl create serviceaccount eso-sa -n $NS

   kubectl annotate serviceaccount eso-sa -n $NS \
     eks.amazonaws.com/role-arn=arn:aws:iam::${ACCOUNT_ID}:role/eso-irsa-role
   ```

   Quick reminder of what IRSA does: the IAM role's trust policy permits the EKS OIDC provider to issue STS credentials to any pod running with that ServiceAccount. ESO's AWS provider then uses the projected token automatically through the AWS SDK.

5. **Create the SecretStore.** Save the following as `secretstore-aws.yaml`:
   ```yaml
   apiVersion: external-secrets.io/v1
   kind: SecretStore
   metadata:
     name: aws-secretsmanager
     namespace: eso-demo
   spec:
     provider:
       aws:
         service: SecretsManager
         region: us-east-1
         auth:
           jwt:
             serviceAccountRef:
               name: eso-sa
   ```
   ```bash
   kubectl apply -f secretstore-aws.yaml
   ```

6. **Confirm the store is healthy:**
   ```bash
   kubectl get secretstore -n $NS
   kubectl describe secretstore aws-secretsmanager -n $NS
   ```
   You want `STATUS: Valid` and a `Ready=True` condition.

### Verification
- ServiceAccount `eso-sa` exists in `eso-demo` and carries the `eks.amazonaws.com/role-arn` annotation.
- `SecretStore aws-secretsmanager` reports `Valid`.
- `aws secretsmanager describe-secret --secret-id dev/myapp/db` returns the secret.

---

## Lab 3: Pull a Secret with ExternalSecret (data and dataFrom)

### Objectives
- Create an `ExternalSecret` that produces a Kubernetes Secret named `myapp-db`.
- Demonstrate per-key extraction with `data`.
- Demonstrate JSON expansion with `dataFrom: extract`.

### Steps

1. **Per-key extraction.** Save the following as `externalsecret-basic.yaml`:
   ```yaml
   apiVersion: external-secrets.io/v1
   kind: ExternalSecret
   metadata:
     name: myapp-db
     namespace: eso-demo
   spec:
     refreshInterval: 1m
     secretStoreRef:
       name: aws-secretsmanager
       kind: SecretStore
     target:
       name: myapp-db          # the K8s Secret that will be created
       creationPolicy: Owner
     data:
       - secretKey: DB_USER
         remoteRef:
           key: dev/myapp/db
           property: username
       - secretKey: DB_PASS
         remoteRef:
           key: dev/myapp/db
           property: password
       - secretKey: DB_HOST
         remoteRef:
           key: dev/myapp/db
           property: host
   ```
   ```bash
   kubectl apply -f externalsecret-basic.yaml
   ```

2. **Verify the Kubernetes Secret was generated:**
   ```bash
   kubectl get externalsecret -n eso-demo
   kubectl get secret myapp-db -n eso-demo -o yaml
   kubectl get secret myapp-db -n eso-demo -o jsonpath='{.data.DB_PASS}' | base64 -d ; echo
   ```
   You should see `Status: SecretSynced`.

3. **Pull the entire JSON document at once with `dataFrom`.** Save the following as `externalsecret-datafrom.yaml`:
   ```yaml
   apiVersion: external-secrets.io/v1
   kind: ExternalSecret
   metadata:
     name: myapp-db-all
     namespace: eso-demo
   spec:
     refreshInterval: 1m
     secretStoreRef:
       name: aws-secretsmanager
       kind: SecretStore
     target:
       name: myapp-db-all
       creationPolicy: Owner
     dataFrom:
       - extract:
           key: dev/myapp/db
   ```
   ```bash
   kubectl apply -f externalsecret-datafrom.yaml
   kubectl get secret myapp-db-all -n eso-demo -o json \
     | jq '.data | map_values(@base64d)'
   ```
   Each top-level JSON key in the AWS secret becomes a key in the K8s Secret.

4. **Consume the synced Secret from a Deployment.** Save the following as `demo-deployment.yaml`:
   ```yaml
   apiVersion: apps/v1
   kind: Deployment
   metadata:
     name: demo-app
     namespace: eso-demo
   spec:
     replicas: 1
     selector:
       matchLabels:
         app: demo-app
     template:
       metadata:
         labels:
           app: demo-app
       spec:
         containers:
           - name: app
             image: busybox
             command: ['sh', '-c', 'echo "user=$DB_USER host=$DB_HOST"; sleep 3600']
             envFrom:
               - secretRef:
                   name: myapp-db
   ```
   ```bash
   kubectl apply -f demo-deployment.yaml
   kubectl rollout status deploy/demo-app -n eso-demo
   kubectl logs -n eso-demo deploy/demo-app
   ```

### Verification
- `kubectl get externalsecret -n eso-demo` shows `STATUS: SecretSynced` for both objects.
- Both `myapp-db` and `myapp-db-all` Secrets exist with the expected keys.
- The Deployment's pod prints the username and host from the secret.

---

## Lab 4: Templating - Shape the Output Secret

### Objectives
- Use `target.template` with `engineVersion: v2` to build a custom file payload (a `.env` blob and a JDBC URL) from the upstream values.
- Set Secret `type` and labels.

### Steps

1. **Templated ExternalSecret.** Save the following as `externalsecret-template.yaml`:
   ```yaml
   apiVersion: external-secrets.io/v1
   kind: ExternalSecret
   metadata:
     name: myapp-db-templated
     namespace: eso-demo
   spec:
     refreshInterval: 1m
     secretStoreRef:
       name: aws-secretsmanager
       kind: SecretStore
     target:
       name: myapp-db-templated
       creationPolicy: Owner
       template:
         engineVersion: v2
         type: Opaque
         metadata:
           labels:
             app: myapp
             managed-by: eso
         data:
           JDBC_URL: "jdbc:postgresql://{{ .host }}:{{ .port }}/appdb?user={{ .username }}&password={{ .password }}"
           app.env: |
             DB_USER={{ .username }}
             DB_PASS={{ .password }}
             DB_HOST={{ .host }}
             DB_PORT={{ .port }}
     dataFrom:
       - extract:
           key: dev/myapp/db
   ```
   ```bash
   kubectl apply -f externalsecret-template.yaml
   ```

2. **Inspect the rendered Secret:**
   ```bash
   kubectl get secret myapp-db-templated -n eso-demo \
     -o jsonpath='{.data.JDBC_URL}' | base64 -d ; echo
   kubectl get secret myapp-db-templated -n eso-demo \
     -o jsonpath='{.data.app\.env}' | base64 -d ; echo
   ```

### Verification
- The rendered `JDBC_URL` value contains the username, password, host, and port pulled from AWS.
- The `app.env` key is a multi-line dotenv blob suitable for mounting as a file.
- The Secret carries the `app=myapp` and `managed-by=eso` labels.

---
