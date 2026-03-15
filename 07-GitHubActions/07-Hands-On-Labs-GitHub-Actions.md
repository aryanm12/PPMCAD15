# Session 7: GitHub Actions
## Cloud-Native CI/CD: From First Workflow to Production Deployment

---

## Prerequisites

> **Before this session:** You should have the Flask app in a GitHub repo, AWS credentials configured, and familiarity with the CI/CD pipeline flow (test -> build -> scan -> push -> deploy) from Jenkins.

### Required Setup

| Requirement | Details |
|-------------|---------|
| GitHub repo | `cicd-lab-app` with Flask app, Dockerfile, and tests |
| AWS CLI v2 | Configured with `aws configure` |

---

## ═══════════════════════════════════════════
## Lab 1 - Your First GitHub Actions Workflow
## ═══════════════════════════════════════════

**Objective:** Create your first GitHub Actions workflow, understand the YAML syntax, and set up the same test pipeline you built in Jenkins - now as GHA.

### What You'll Learn
- Workflow YAML structure
- Events, jobs, steps
- `uses:` (actions) vs `run:` (shell commands)
- GitHub-hosted runners
- Matrix testing
- Viewing workflow runs in the GitHub UI

---

### Step 1: Create Your First Workflow

Take the clone of your repo where you have kept your Flask app code:

```bash
mkdir -p .github/workflows
```

**`.github/workflows/ci.yml`:**

```yaml
name: CI - Test and Build

on:
  push:
    branches: [main, 'feature/**']
  pull_request:
    branches: [main]

jobs:
  test:
    name: Run Tests
    runs-on: ubuntu-latest

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.11'
          cache: 'pip'              # Cache pip downloads automatically!

      - name: Install dependencies
        run: pip install -r requirements.txt

      - name: Run pytest
        run: |
          python -m pytest tests/ -v --tb=short --junitxml=test-results.xml

      - name: Upload test results
        uses: actions/upload-artifact@v4
        if: always()              # Upload even if tests fail
        with:
          name: test-results
          path: test-results.xml

  build-image:
    name: Build Docker Image
    runs-on: ubuntu-latest
    needs: test              # Only runs if 'test' job passes

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Get Git metadata
        id: meta
        run: |
          echo "sha_short=$(git rev-parse --short HEAD)" >> $GITHUB_OUTPUT
          echo "run_number=${{ github.run_number }}" >> $GITHUB_OUTPUT

      - name: Build Docker image
        run: |
          docker build \
            --label "git.commit=${{ steps.meta.outputs.sha_short }}" \
            -t cicd-lab-app:${{ steps.meta.outputs.run_number }}-${{ steps.meta.outputs.sha_short }} \
            -t cicd-lab-app:latest \
            .

      - name: Smoke test container
        run: |
          CONTAINER_ID=$(docker run -d -p 9090:8080 cicd-lab-app:latest)
          sleep 5
          HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:9090/health)
          docker stop $CONTAINER_ID
          echo "Health check: HTTP $HTTP_CODE"
          [ "$HTTP_CODE" = "200" ] || exit 1

      - name: Image build summary
        run: |
          echo "## Docker Image Built ✅" >> $GITHUB_STEP_SUMMARY
          echo "**Tag:** \`${{ steps.meta.outputs.run_number }}-${{ steps.meta.outputs.sha_short }}\`" >> $GITHUB_STEP_SUMMARY
          echo "**Commit:** \`${{ github.sha }}\`" >> $GITHUB_STEP_SUMMARY
```

### Step 2: Push and Observe

```bash
git add .github/
git commit -m "ci: add GitHub Actions workflow"
git push origin main
```

Go to your GitHub repo -> **Actions** tab. You should see the workflow running.

Explore:
- Click on the workflow run -> see jobs
- Click on a job -> see individual steps
- Expand a step -> see command output
- Check the **Summary** tab for the Docker image build summary

### Step 3: Add Matrix Testing

Update `ci.yml` to add a matrix testing job:

```yaml
  test-matrix:
    name: Test Python ${{ matrix.python-version }}
    runs-on: ubuntu-latest
    strategy:
      matrix:
        python-version: ['3.10', '3.11', '3.12']
      fail-fast: false      # Run all versions even if one fails

    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: ${{ matrix.python-version }}
          cache: 'pip'
      - run: pip install -r requirements.txt
      - run: python -m pytest tests/ -v
```

Push this change and observe 3 parallel test jobs running simultaneously.

### Step 4: Add Environment Variables and Secrets

1. Go to your GitHub repo -> **Settings -> Secrets and variables -> Actions**
2. Add a **New repository secret**: `SLACK_WEBHOOK_URL` (can be a dummy value for now)

Update `ci.yml` to use it:

```yaml
      - name: Notify on failure
        if: failure()
        run: |
          curl -X POST ${{ secrets.SLACK_WEBHOOK_URL }} \
            -H 'Content-type: application/json' \
            --data '{"text":" CI failed on ${{ github.repository }} branch ${{ github.ref_name }}"}'
```

Notice: secrets are never shown in logs - they appear as `***`.

---

## ═══════════════════════════════════════════════════
## Lab 2 - Reusable Workflows: Write Once, Call Anywhere
## ═══════════════════════════════════════════════════

**Objective:** Create a reusable workflow in one repository and call it from another. Learn how `workflow_call` works, how to pass inputs and secrets, and how to structure shared CI/CD logic across an organization.

### What You'll Learn
- The difference between a **caller** workflow and a **called** (reusable) workflow
- How `workflow_call` works as a trigger
- Defining and passing `inputs` and `secrets`
- Calling a reusable workflow from the same repo and from another repo
- Using `outputs` to pass data back to the caller
- Best practices for organizing shared workflows

---

### Concept: How Reusable Workflows Work

```
┌─────────────────────────┐      uses:      ┌──────────────────────────────┐
│   Caller Workflow       │ ──────────────> │   Reusable Workflow          │
│   (.github/workflows/   │                 │   (.github/workflows/        │
│    deploy.yml)          │   with:         │    shared-build.yml)         │
│                         │   inputs +      │                              │
│   on: push              │   secrets       │   on: workflow_call          │
│   jobs:                 │                 │   inputs: ...                │
│     build:              │                 │   secrets: ...               │
│       uses: org/repo/...│ <────────────── │   outputs: ...               │
│       with:             │   outputs       │                              │
│         env: production │                 │   jobs:                      │
└─────────────────────────┘                 │     build: ...               │
                                            └──────────────────────────────┘
```

**Key rules:**
- The reusable workflow must have `on: workflow_call` (not `push`, `pull_request`, etc.)
- The caller references it with `uses:` at the **job level**, not at the step level
- A reusable workflow can contain multiple jobs
- Maximum nesting depth: **4 levels** (workflow calls workflow calls workflow... up to 4)
- A single workflow can call up to **20 reusable workflows**

---

### Step 1: Create the Reusable Workflow

In your `cicd-lab-app` repo, create a new workflow file:

**`.github/workflows/reusable-build.yml`:**

```yaml
name: Reusable - Build & Test

# This is what makes it reusable!
on:
  workflow_call:
    inputs:
      python-version:
        description: 'Python version to use'
        required: false
        type: string
        default: '3.11'
      run-docker-build:
        description: 'Whether to build Docker image'
        required: false
        type: boolean
        default: true
      image-tag-prefix:
        description: 'Prefix for Docker image tag'
        required: false
        type: string
        default: 'dev'
    secrets:
      SLACK_WEBHOOK_URL:
        required: false
    outputs:
      image-tag:
        description: 'The Docker image tag that was built'
        value: ${{ jobs.build.outputs.image-tag }}
      test-result:
        description: 'Test pass/fail status'
        value: ${{ jobs.test.outputs.result }}

jobs:
  test:
    name: Run Tests (Python ${{ inputs.python-version }})
    runs-on: ubuntu-latest
    outputs:
      result: ${{ steps.tests.outcome }}

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: ${{ inputs.python-version }}
          cache: 'pip'

      - name: Install dependencies
        run: pip install -r requirements.txt

      - name: Run pytest
        id: tests
        run: python -m pytest tests/ -v --tb=short

      - name: Upload test results
        uses: actions/upload-artifact@v4
        if: always()
        with:
          name: test-results-py${{ inputs.python-version }}
          path: test-results.xml

  build:
    name: Build Docker Image
    runs-on: ubuntu-latest
    needs: test
    if: inputs.run-docker-build
    outputs:
      image-tag: ${{ steps.meta.outputs.tag }}

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Generate image tag
        id: meta
        run: |
          TAG="${{ inputs.image-tag-prefix }}-$(git rev-parse --short HEAD)"
          echo "tag=$TAG" >> $GITHUB_OUTPUT
          echo "Generated tag: $TAG"

      - name: Build Docker image
        run: |
          docker build \
            -t cicd-lab-app:${{ steps.meta.outputs.tag }} \
            -t cicd-lab-app:latest \
            .

      - name: Smoke test container
        run: |
          CONTAINER_ID=$(docker run -d -p 9090:8080 cicd-lab-app:latest)
          sleep 5
          HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:9090/health)
          docker stop $CONTAINER_ID
          echo "Health check: HTTP $HTTP_CODE"
          [ "$HTTP_CODE" = "200" ] || exit 1

      - name: Build summary
        run: |
          echo "## Docker Image Built ✅" >> $GITHUB_STEP_SUMMARY
          echo "**Tag:** \`${{ steps.meta.outputs.tag }}\`" >> $GITHUB_STEP_SUMMARY
```

### Step 2: Create a Caller Workflow (Same Repo)

Now create a workflow that **calls** the reusable one:

**`.github/workflows/ci-caller.yml`:**

```yaml
name: CI Pipeline (uses reusable workflow)

on:
  push:
    branches: [main, 'feature/**']
  pull_request:
    branches: [main]

jobs:
  # Call the reusable workflow for development builds
  build-dev:
    uses: ./.github/workflows/reusable-build.yml    # Same repo = relative path
    with:
      python-version: '3.11'
      run-docker-build: true
      image-tag-prefix: 'dev'
    secrets:
      SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK_URL }}

  # Use the output from the reusable workflow
  report:
    needs: build-dev
    runs-on: ubuntu-latest
    steps:
      - name: Show build results
        run: |
          echo "Image tag: ${{ needs.build-dev.outputs.image-tag }}"
          echo "Test result: ${{ needs.build-dev.outputs.test-result }}"

      - name: Post summary
        run: |
          echo "## CI Pipeline Complete 🚀" >> $GITHUB_STEP_SUMMARY
          echo "- **Image:** \`${{ needs.build-dev.outputs.image-tag }}\`" >> $GITHUB_STEP_SUMMARY
          echo "- **Tests:** ${{ needs.build-dev.outputs.test-result }}" >> $GITHUB_STEP_SUMMARY
```

### Step 3: Push and Observe

```bash
git add .github/workflows/reusable-build.yml .github/workflows/ci-caller.yml
git commit -m "ci: add reusable workflow and caller"
git push origin main
```

Go to **Actions** tab and observe:
- The **caller** workflow (`CI Pipeline`) is what you see running
- Click into it — you'll see the reusable workflow's jobs (`Run Tests`, `Build Docker Image`) executing as part of it
- The `report` job waits for the reusable workflow to finish, then reads its outputs

### Step 4: Call the Reusable Workflow from Another Repo

Now let's simulate what an org-wide shared workflow looks like.

1. **Create a second repo** (or use any other repo you have):
   ```bash
   # In another repo
   mkdir -p .github/workflows
   ```

2. **Create a caller workflow in the second repo:**

   **`.github/workflows/ci.yml`** (in the second repo):

   ```yaml
   name: CI - Using Shared Workflow

   on:
     push:
       branches: [main]

   jobs:
     build:
       # Cross-repo call: org/repo/.github/workflows/file.yml@ref
       uses: YOUR-USERNAME/cicd-lab-app/.github/workflows/reusable-build.yml@main
       with:
         python-version: '3.12'
         run-docker-build: false     # Skip Docker for this repo
         image-tag-prefix: 'other'
       secrets:
         SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK_URL }}

     report:
       needs: build
       runs-on: ubuntu-latest
       steps:
         - run: echo "Tests passed using shared workflow!"
   ```

   > **Replace `YOUR-USERNAME`** with your actual GitHub username.

3. **Push and observe** the second repo calling the first repo's reusable workflow.

> **Important:** For cross-repo calls, the reusable workflow's repo must be **public**, or both repos must be in the **same org** with Actions sharing enabled (Settings → Actions → General → Access).

---
