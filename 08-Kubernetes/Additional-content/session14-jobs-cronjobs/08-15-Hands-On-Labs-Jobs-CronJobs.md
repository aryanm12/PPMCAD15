# Session 08-15: Jobs and CronJobs - Hands-On Labs

## Overview
In Session 4 you worked with long-running workloads (Deployments, ReplicaSets). This session is about **finite, run-to-completion** workloads. You will run one-shot Jobs, parallelise them, use the modern failure-handling features (`podFailurePolicy`, `backoffLimitPerIndex`, `successPolicy`) that recently went GA, and schedule recurring work with CronJobs.

**Prerequisites:**
- Working Kubernetes cluster on **v1.33 or newer**.
- `kubectl` configured for the cluster
- A namespace to play in: `kubectl create namespace batch-lab && kubectl config set-context --current --namespace=batch-lab`
- Pods can pull `busybox:1.36`, `perl:5.34.0`

> All commands assume `--namespace batch-lab` (or you've set the context as above). All YAML used in this lab is shown inline. When a step says *"Save the following as `foo.yaml`"*, copy the block into a file with that name in your working directory, then run the `kubectl apply -f foo.yaml` that follows.

---

## Lab 1: Run Your First Job (compute pi)

### Objectives
- Create a single-shot Job and watch it run to completion
- Inspect the Job, its pod, and the captured output
- See how `ttlSecondsAfterFinished` cleans up automatically

### Steps

1. **Save the following as `job-simple.yaml`** and apply it:
   ```yaml
   apiVersion: batch/v1
   kind: Job
   metadata:
     name: pi
   spec:
     backoffLimit: 4
     ttlSecondsAfterFinished: 300
     template:
       spec:
         restartPolicy: Never
         containers:
         - name: pi
           image: perl:5.34.0
           command: ["perl", "-Mbignum=bpi", "-wle", "print bpi(2000)"]
   ```
   ```bash
   kubectl apply -f job-simple.yaml
   ```

2. **Watch the Job and pod come up:**
   ```bash
   kubectl get jobs -w
   ```
   In another terminal:
   ```bash
   kubectl get pods -l batch.kubernetes.io/job-name=pi -w
   ```

3. **Once `COMPLETIONS` reads `1/1`, look at the output:**
   ```bash
   POD=$(kubectl get pods -l batch.kubernetes.io/job-name=pi -o jsonpath='{.items[0].metadata.name}')
   kubectl logs "$POD"
   ```

4. **Describe the Job to see status conditions and timing:**
   ```bash
   kubectl describe job pi
   ```
   Note the `Complete` condition, `startTime`, `completionTime`, and `succeeded: 1`.

5. **Wait ~5 minutes (or change `ttlSecondsAfterFinished` to e.g. `30` and re-apply) and confirm cleanup:**
   ```bash
   kubectl get jobs
   ```

### Verification
- The `pi` Job reached `COMPLETIONS 1/1`
- `kubectl logs` shows ~2000 digits of pi
- After the TTL, the Job and its pod are auto-deleted

---

## Lab 2: Parallelism and Completions

### Objectives
- Run a Job with `completions: 6` and `parallelism: 3`
- Observe that pods are created in waves up to the parallelism cap
- Use `activeDeadlineSeconds` as a hard wall-clock cap

### Steps

1. **Save the following as `job-parallel.yaml`** and apply it:
   ```yaml
   apiVersion: batch/v1
   kind: Job
   metadata:
     name: pi-parallel
   spec:
     # Run 6 successful completions, up to 3 pods at a time.
     completions: 6
     parallelism: 3
     backoffLimit: 6
     activeDeadlineSeconds: 600     # hard wall-clock cap for the whole Job
     ttlSecondsAfterFinished: 300
     template:
       spec:
         restartPolicy: Never
         containers:
         - name: pi
           image: perl:5.34.0
           command: ["perl", "-Mbignum=bpi", "-wle", "print bpi(500)"]
   ```
   ```bash
   kubectl apply -f job-parallel.yaml
   ```

2. **Watch pods cycle in waves of 3 until 6 have succeeded:**
   ```bash
   kubectl get pods -l batch.kubernetes.io/job-name=pi-parallel -w
   ```

3. **Check the progress field on the Job:**
   ```bash
   kubectl get job pi-parallel -o jsonpath='{.status}{"\n"}'
   ```
   Look for `succeeded`, `active`, and `ready`.

4. **(Optional) Trigger the wall-clock deadline.** Edit `job-parallel.yaml` to set `activeDeadlineSeconds: 5`, delete and re-apply:
   ```bash
   kubectl delete job pi-parallel
   kubectl apply -f job-parallel.yaml   # after editing the file
   kubectl describe job pi-parallel
   ```
   The Job is marked `Failed` with reason `DeadlineExceeded`.

### Verification
- Up to 3 pods run simultaneously
- The Job completes once 6 pods have succeeded
- Setting a tight `activeDeadlineSeconds` produces a `Failed`/`DeadlineExceeded` condition

---

## Lab 3: CronJob Basics, TimeZone, and Concurrency

### Objectives
- Schedule a recurring CronJob using a standard cron expression
- Pin the schedule to a specific time zone (`timeZone` GA in v1.27)
- Compare `concurrencyPolicy` values: `Allow`, `Forbid`, `Replace`

### Steps

1. **Save the following as `cronjob-simple.yaml`** and apply it:
   ```yaml
   apiVersion: batch/v1
   kind: CronJob
   metadata:
     name: hello
   spec:
     # Run every minute. Standard 5-field cron schedule syntax.
     schedule: "*/1 * * * *"
     successfulJobsHistoryLimit: 3
     failedJobsHistoryLimit: 1
     jobTemplate:
       spec:
         backoffLimit: 2
         ttlSecondsAfterFinished: 120
         template:
           spec:
             restartPolicy: OnFailure
             containers:
             - name: hello
               image: busybox:1.36
               command:
               - /bin/sh
               - -c
               - date; echo "Hello from the Kubernetes cluster"
   ```
   ```bash
   kubectl apply -f cronjob-simple.yaml
   kubectl get cronjob hello
   ```

2. **After ~2 minutes, list the Job objects the CronJob has spawned:**
   ```bash
   kubectl get jobs --sort-by=.metadata.creationTimestamp
   kubectl get pods -l batch.kubernetes.io/job-name -L batch.kubernetes.io/job-name --sort-by=.metadata.creationTimestamp
   ```
   You should see a new `hello-<timestamp>` Job each minute.

3. **Save the following as `cronjob-timezone.yaml`** and apply it:
   ```yaml
   apiVersion: batch/v1
   kind: CronJob
   metadata:
     name: ist-business-hours-job
   spec:
     # CronJob .spec.timeZone went GA in Kubernetes v1.27.
     # Without timeZone, schedules use kube-controller-manager's local TZ.
     schedule: "30 9 * * 1-5"          # 09:30, Mon-Fri
     timeZone: "Asia/Kolkata"          # IANA name; CRON_TZ / TZ inside schedule are NOT supported
     concurrencyPolicy: Allow
     successfulJobsHistoryLimit: 5
     failedJobsHistoryLimit: 2
     jobTemplate:
       spec:
         backoffLimit: 2
         ttlSecondsAfterFinished: 600
         template:
           spec:
             restartPolicy: OnFailure
             containers:
             - name: greet
               image: busybox:1.36
               command: ["sh", "-c", "date; echo good morning India"]
   ```
   ```bash
   kubectl apply -f cronjob-timezone.yaml
   kubectl get cronjob ist-business-hours-job -o jsonpath='{.spec.schedule}{" @ "}{.spec.timeZone}{"\n"}'
   ```
   Note: `CRON_TZ=...` or `TZ=...` inside the `schedule` string is **rejected** by the API. Use `.spec.timeZone` only.

4. **Save the following as `cronjob-concurrency.yaml`** and apply it. Each Job sleeps 90s, but the schedule is every 60s — so a new run will always overlap the previous one:
   ```yaml
   apiVersion: batch/v1
   kind: CronJob
   metadata:
     name: long-running-cron
   spec:
     # concurrencyPolicy:
     #   Allow   - run them in parallel (default)
     #   Forbid  - skip the new run if the previous is still active
     #   Replace - kill the previous run, start the new one
     schedule: "*/1 * * * *"
     concurrencyPolicy: Forbid
     startingDeadlineSeconds: 30
     successfulJobsHistoryLimit: 3
     failedJobsHistoryLimit: 1
     jobTemplate:
       spec:
         backoffLimit: 0
         template:
           spec:
             restartPolicy: Never
             containers:
             - name: long
               image: busybox:1.36
               command: ["sh", "-c", "echo start $(date); sleep 90; echo done"]
   ```
   ```bash
   kubectl apply -f cronjob-concurrency.yaml
   kubectl get jobs -l batch.kubernetes.io/job-name --watch
   ```
   With `concurrencyPolicy: Forbid`, the second minute's Job is **skipped** while the first is still active. Edit the manifest to `Replace` and re-apply to see the previous run get killed; edit to `Allow` to see them stack up.

5. **Suspend / resume a CronJob:**
   ```bash
   kubectl patch cronjob hello -p '{"spec":{"suspend":true}}'
   kubectl get cronjob hello
   sleep 120
   kubectl get jobs                # no new Jobs created during the pause
   kubectl patch cronjob hello -p '{"spec":{"suspend":false}}'
   ```

6. **Manually trigger a Job from a CronJob (handy for testing):**
   ```bash
   kubectl create job hello-manual --from=cronjob/hello
   kubectl logs -l batch.kubernetes.io/job-name=hello-manual
   ```

### Verification
- `hello` CronJob produces one new Job per minute
- The IST CronJob shows `Asia/Kolkata` in its spec and the next-scheduled time is computed in that zone
- `Forbid` causes overlapping runs to be skipped (visible as gaps in `lastScheduleTime` updates)
- `suspend: true` halts new Jobs without deleting the CronJob
- `--from=cronjob/...` creates an ad-hoc Job using the CronJob's `jobTemplate`

---