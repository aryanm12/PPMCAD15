# Session 08-15: Jobs and CronJobs - Readout

A one-page primer on Kubernetes batch workloads: Jobs (run-to-completion) and CronJobs (scheduled Jobs). Targets Kubernetes **v1.33+** so that `backoffLimitPerIndex` and `successPolicy` (both GA in v1.33) are available; older features used here have been GA for a while — `ttlSecondsAfterFinished` since v1.23, indexed completion mode since v1.24, CronJob `timeZone` since v1.27, and `podFailurePolicy` since v1.31.

---

## What is a Job?

A **Job** is a built-in Kubernetes controller (`batch/v1`) that creates one or more Pods and tracks them until a specified number of them **terminate successfully**. Unlike a Deployment or ReplicaSet, a Job is **finite**: it has a desired number of completions, after which the Job is `Complete`. Failed Pods are retried until either the Job succeeds, the `backoffLimit` is exhausted, the `activeDeadlineSeconds` expires, or a `podFailurePolicy` rule says otherwise. Use Jobs for batch processing, ETL, migrations, scheduled maintenance, parametric sweeps, and embarrassingly parallel tasks.

---

## What is a CronJob?

A **CronJob** is a higher-level controller that owns a `jobTemplate` and creates a new Job on a cron schedule. CronJob itself reached GA in **v1.21**. Each scheduled invocation produces an independent Job object that runs through the lifecycle described above.

---