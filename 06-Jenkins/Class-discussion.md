# Class Discussion - Session 7
## Jenkins CI Triggers & Shared Libraries

---

### How Jenkins Picks Up Your Code

As soon as you commit and push code to your Git repo, Jenkins needs to know about it. There are **4 ways** this can happen:

---

#### 1. Manual Trigger

The simplest approach — you go to the Jenkins console and click **Build Now** yourself. No automation, fully on-demand.

**When to use:** Ad-hoc testing, debugging a specific build, first-time pipeline setup.

---

#### 2. SCM Polling

You tell Jenkins: *"Keep checking the Git repo every X minutes. If you find a new commit, run the build."*

How it works behind the scenes:
- Jenkins stores the **last commit ID** of the branch it built against
- Every polling interval (say 2 or 5 minutes), it compares that stored commit ID with the latest state of the repo
- If they differ → new commit detected → build is triggered

```groovy
triggers {
    pollSCM('H/5 * * * *')   // check every 5 minutes
}
```

**Downside:** Wastes resources polling when nothing has changed. Introduces a delay (up to the polling interval) before builds start.

---

#### 3. Scheduled Trigger

Run the build on a fixed schedule, regardless of whether new commits exist. Uses **cron syntax**.

**Example use case:** You have an integration test suite that takes 4 hours to complete. You don't want it running on every commit. Instead, you create a **nightly job** that runs at 2 AM every day.

```groovy
triggers {
    cron('0 2 * * *')   // run at 2 AM every day
}
```

**When to use:** Long-running test suites, nightly builds, periodic deployments, scheduled reports.

---

#### 4. Webhook Trigger (Recommended)

The Git repo is integrated with Jenkins. Instead of Jenkins checking the repo, the **repo tells Jenkins** when something changes.

*"Hey Jenkins, I just received a new commit — go ahead and run the CI pipeline."*

```groovy
triggers {
    githubPush()
}
```

**Why this is the best approach:**
- **Instant** — no polling delay, builds start within seconds of a push
- **Efficient** — no wasted resources checking for changes that don't exist
- **Scalable** — works the same whether you have 1 repo or 100

**Requirement:** Jenkins must be reachable from GitHub (public URL, or ngrok for local setups).

---

### Quick Comparison

| Trigger | Speed | Resource Usage | Setup Effort |
|---------|-------|----------------|--------------|
| Manual | On-demand | None | None |
| SCM Polling | Delayed (up to polling interval) | High (constant checking) | Low |
| Scheduled | Fixed time | None between runs | Low |
| Webhook | Instant | Minimal | Medium (needs network access) |

---

---

### Shared Libraries - DRY Your Pipelines

**DRY = Don't Repeat Yourself**

#### The Problem

Without shared libraries, every team writes their own full Jenkinsfile. Across 10 teams, you end up with 10 bulky Jenkinsfiles that all do roughly the same thing — build, test, push to ECR, deploy to ECS. Same logic duplicated everywhere. When something needs to change (say, a new security scan step), you're updating 10 files.

#### The Solution

Create a **Shared Library** — a central repo that holds reusable pipeline steps. For example, a Node.js CI/CD shared library that knows how to build, test, and deploy Node apps.

Now every team just references the shared library in their Jenkinsfile:

```groovy
@Library('nodejs-cicd-lib@main') _

pipeline {
    agent any
    stages {
        stage('Build')  { steps { nodeBuild()  } }
        stage('Test')   { steps { nodeTest()   } }
        stage('Deploy') { steps { nodeDeploy() } }
    }
}
```

#### What This Gives You

- **Write once, use everywhere** — pipeline logic lives in one place
- **Consistency** — all teams follow the same build process
- **Easy updates** — change the library once, every pipeline picks it up automatically
- **Clean Jenkinsfiles** — teams go from 100+ lines to ~20 lines

Perform the hands-on labs **06-Hands-On-Labs-Jenkins-Advanced.md**
---