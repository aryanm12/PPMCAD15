# Lab: Setting Up an Ubuntu Self-Hosted Runner for GitHub Actions

## Objective

Register an Ubuntu machine (EC2 instance or local VM) as a **self-hosted runner** for your GitHub repository so your workflows can execute on your own infrastructure instead of GitHub-hosted VMs.

## What You'll Learn

- What a self-hosted runner is and why you'd use one
- How to provision and configure an Ubuntu runner
- How to register it with your GitHub repo
- How to target it in your workflow YAML
- Security considerations and cleanup

---

## Background: GitHub-Hosted vs Self-Hosted

| Aspect | GitHub-Hosted | Self-Hosted |
|--------|--------------|-------------|
| Setup | Zero - just use `runs-on: ubuntu-latest` | You provision and maintain the machine |
| Environment | Fresh VM every job, destroyed after | Persistent - tools, caches, data survive |
| Network | GitHub's network only | Access your VPC, private subnets, on-prem |
| Cost | Uses your plan's free minutes (2,000–50,000/mo) | Your infra cost + $0.002/min platform fee on private repos (as of March 2026) |
| Use case | Most teams, getting started | GPU workloads, private network access, compliance, custom hardware |

---

## Prerequisites

- A GitHub repository where you have **admin** access (needed to register runners)
- An Ubuntu machine (one of the following):
  - **AWS EC2**: Ubuntu 22.04+ (t2.medium or larger recommended)
  - **Local VM**: Ubuntu 22.04+ via VirtualBox, Multipass, or WSL2
  - **Any Ubuntu server** with internet access
- SSH access to the machine
- `curl`, `tar`, and `shasum` available (pre-installed on Ubuntu)

---

## Step 1: Prepare the Ubuntu Machine

SSH into your machine and install the tools your workflows will need:

```bash
# Update packages
sudo apt-get update && sudo apt-get upgrade -y

# Install common CI/CD tools
sudo apt-get install -y \
  build-essential \
  curl \
  git \
  docker.io \
  python3 \
  python3-pip \
  python3-venv \
  jq

# Enable and start Docker
sudo systemctl enable docker
sudo systemctl start docker

# Create a dedicated runner user (don't run as root)
sudo useradd -m -s /bin/bash github-runner
sudo usermod -aG docker github-runner
```

> **Why a dedicated user?** The runner executes arbitrary code from your workflows. Using a dedicated non-root user limits the blast radius if something goes wrong.

---

## Step 2: Get the Runner Token from GitHub

1. Go to your GitHub repository → **Settings** → **Actions** → **Runners**
2. Click **"New self-hosted runner"**
3. Select **Linux** and **x64** (or ARM64 if applicable)
4. GitHub will display a page with download commands and a **registration token**

> The token is valid for **1 hour**. If it expires, come back to this page to generate a new one.

Keep this page open - you'll copy commands from it in the next step.

---

## Step 3: Download and Install the Runner

Switch to your runner user and follow the commands GitHub shows you:

```bash
# Switch to runner user
sudo su - github-runner

# Create a directory for the runner
mkdir actions-runner && cd actions-runner

# Download the latest runner package (GitHub shows the exact URL)
curl -o actions-runner-linux-x64-2.321.0.tar.gz -L \
  https://github.com/actions/runner/releases/download/v2.321.0/actions-runner-linux-x64-2.321.0.tar.gz

# Extract
tar xzf ./actions-runner-linux-x64-2.321.0.tar.gz
```

> **Note:** Replace the version number with the values shown on your GitHub page. They update frequently.

---

## Step 4: Register the Runner

```bash
# Configure the runner (GitHub shows the exact command with your token)
./config.sh \
  --url https://github.com/YOUR-ORG/YOUR-REPO \
  --token YOUR_REGISTRATION_TOKEN
```

The script will ask you a few questions:

| Prompt | What to enter |
|--------|--------------|
| Runner group | Press Enter for `Default` |
| Runner name | Give it a descriptive name, e.g. `ubuntu-ec2-runner-01` |
| Labels | Add custom labels like `self-hosted,linux,x64,docker` |
| Work folder | Press Enter for `_work` (default) |

**Labels are important** - they're how your workflows target this specific runner.

---

## Step 5: Start the Runner

### Option A: Interactive (for testing)

```bash
./run.sh
```

You'll see output like:

```
√ Connected to GitHub
Current runner version: '2.321.0'
Listening for Jobs
```

Press `Ctrl+C` to stop.

### Option B: As a systemd Service (for production)

```bash
# Exit back to your admin user
exit

# Install the service (run as root/sudo)
cd /home/github-runner/actions-runner
sudo ./svc.sh install github-runner

# Start the service
sudo ./svc.sh start

# Check status
sudo ./svc.sh status
```

The runner will now start automatically on boot and restart if it crashes.

---

## Step 6: Verify in GitHub

Go back to **Settings → Actions → Runners** in your repository.

You should see your runner listed with a **green "Idle"** status. This means it's online and waiting for jobs.

---

## Step 7: Use It in a Workflow

Update your workflow YAML to target your self-hosted runner:

```yaml
name: CI on Self-Hosted Runner

on:
  push:
    branches: [main]

jobs:
  test:
    runs-on: [self-hosted, linux, x64]   # Matches your runner's labels

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Run tests
        run: |
          python3 -m pytest tests/ -v

      - name: Build Docker image
        run: |
          docker build -t myapp:${{ github.sha }} .

      - name: Smoke test
        run: |
          docker run -d -p 9090:8080 myapp:${{ github.sha }}
          sleep 5
          curl -f http://localhost:9090/health
```

Push this and watch the job get picked up by your self-hosted runner in the Actions tab.

---

## Step 8: Add Multiple Labels for Routing

You can have multiple runners with different labels and route specific jobs to specific machines:

```yaml
jobs:
  unit-tests:
    runs-on: [self-hosted, linux, x64]        # Any Linux runner

  gpu-training:
    runs-on: [self-hosted, linux, gpu]         # Only GPU runners

  integration-tests:
    runs-on: [self-hosted, linux, docker]      # Runners with Docker
```

To add labels after registration:

```bash
cd /home/github-runner/actions-runner
./config.sh --url https://github.com/ORG/REPO --token NEW_TOKEN --labels gpu,cuda
```

Or add them in the GitHub UI: **Settings → Actions → Runners → click runner → edit labels**.

---

## Security Best Practices

1. **Never use self-hosted runners on public repos** - anyone who forks your repo and opens a PR can execute arbitrary code on your machine.

2. **Use a dedicated, non-root user** - never run the runner as `root`.

3. **Isolate the runner** - use a separate VM or container, not your development machine.

4. **Keep the runner updated** - the runner application auto-updates by default, but keep the OS patched too:
   ```bash
   sudo apt-get update && sudo apt-get upgrade -y
   ```

5. **Clean up between jobs** - self-hosted runners don't reset between jobs like GitHub-hosted ones do. Consider adding cleanup steps:
   ```yaml
   - name: Cleanup
     if: always()
     run: |
       docker system prune -af
       rm -rf ${{ github.workspace }}/*
   ```

6. **Restrict runner access** - at the org level, you can limit which repos can use a runner group.

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Runner shows "Offline" | Check if the service is running: `sudo ./svc.sh status` |
| Jobs stuck in "Queued" | Verify labels match between workflow and runner |
| Permission denied (Docker) | Add runner user to docker group: `sudo usermod -aG docker github-runner` then restart |
| Token expired during setup | Go back to Settings → Runners → New runner to get a fresh token |
| Runner won't start after reboot | Install as systemd service (Step 5, Option B) |

---

## Cleanup / Removing a Runner

If you want to decommission the runner:

```bash
# On the runner machine
cd /home/github-runner/actions-runner

# Stop the service
sudo ./svc.sh stop
sudo ./svc.sh uninstall

# Remove the runner registration
./config.sh remove --token YOUR_REMOVE_TOKEN
```

Get the remove token from **Settings → Actions → Runners → your runner → Remove**.

---