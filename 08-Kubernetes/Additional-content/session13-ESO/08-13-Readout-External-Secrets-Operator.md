# Session 08-13 Readout: External Secrets Operator (ESO)

A one-page primer to read before the lab session.

## What is ESO?

The External Secrets Operator is a Kubernetes operator that synchronises secrets from an external secret-management system (AWS Secrets Manager, HashiCorp Vault, Azure Key Vault, GCP Secret Manager, and many more) into native `kind: Secret` objects inside the cluster. Workloads keep consuming Secrets the normal way - via `envFrom`, `valueFrom.secretKeyRef`, or volume mounts - and ESO keeps those Secrets in lock-step with the upstream source of truth.

ESO is a CNCF project. As of May 2026 the current stable line is the **v2.x** stream (Helm chart `external-secrets` v2.4.x; app version v2.x). The older v0.x line ended around v0.17 and the project has since moved through v1.x to the v2.x line.

## Problems it solves

- Stops developers from base64-encoding production secrets into Git.
- Centralises rotation: change the value once in your secrets manager, every cluster picks it up on its next refresh.
- Decouples application code from any specific secrets backend - the workload only sees a `Secret`.
- Provides a uniform Kubernetes-native API across 20+ providers, so multi-cloud and hybrid setups look the same.
- Adds templating so the `Secret` shape (env file, JDBC URL, dockerconfigjson, TLS bundle) can be assembled from raw upstream fields.

## Provider list (current docs)

AWS Secrets Manager, AWS Systems Manager Parameter Store, Google Cloud Secret Manager, Azure Key Vault, HashiCorp Vault (KV v1/v2), and more. Provider availability and stability varies - always check the provider's page on `external-secrets.io/latest/provider/...`.