## ════════════════════════════════════════════════
## Adding a Permanent Linux Agent to Jenkins
## ════════════════════════════════════════════════

**Objective:** Connect a Linux machine (EC2 instance, VM, or any Linux server) as a permanent build agent to your Jenkins controller.

### Why Use a Permanent Agent?

In the earlier labs, we ran builds directly on the Jenkins controller. That works for learning, but in real environments:

- The **controller** should only orchestrate — schedule builds, host the UI, store configs
- **Agents** should do the heavy lifting — run builds, tests, Docker commands
- Separating them means a runaway build can't crash your Jenkins UI

A permanent agent stays connected 24/7 and is ready to pick up jobs anytime. Think of it as a dedicated build server.

---

### Architecture

```
┌───────────────────────┐         SSH           ┌──────────────────────┐
│   Jenkins Controller  │ ────────────────────► │   Linux Agent (VM)   │
│   (your Docker setup) │     Port 22           │                      │
│                       │                       │  - Java 17           │
│   Schedules builds    │                       │  - Git, Docker, etc. │
│   Hosts UI            │                       │  - Runs your builds  │
└───────────────────────┘                       └──────────────────────┘
```

---

### Prerequisites

- Jenkins controller up and running (from your Docker/DinD setup)
- A Linux machine you can SSH into (EC2 instance, Vagrant VM, WSL2, etc.)
- The Linux machine should be reachable from Jenkins over the network

---

### Step 1: Prepare the Agent Machine

SSH into your Linux machine and run:

```bash
# Install Java  (required - Jenkins agent is a Java process)
sudo apt update
sudo apt install -y openjdk-21-jre-headless

# Verify
java -version
```

Create a dedicated Jenkins user:

```bash
# Create user with home directory
sudo useradd -m -s /bin/bash jenkins

# Set a password (you'll need this later)
sudo passwd jenkins

# Create the agent working directory
sudo mkdir -p /home/jenkins/agent
sudo chown jenkins:jenkins /home/jenkins/agent
```

Install any tools your builds need:

```bash
# Git (almost always needed)
sudo apt install -y git

# Docker (if your pipelines build images)
sudo apt install -y docker.io
sudo usermod -aG docker jenkins

# Python (if your pipelines run Python)
sudo apt install -y python3 python3-pip
```

Verify SSH is running:

```bash
sudo systemctl status ssh

# If not installed:
sudo apt install -y openssh-server
sudo systemctl start ssh
sudo systemctl enable ssh

# Allow 
sudo sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
sudo sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config.d/*.conf
sudo systemctl restart sshd
sudo systemctl restart ssh
```

> **Note the Public IP address**

---

### Step 2: Add SSH Credentials in Jenkins

Before adding the agent node, Jenkins needs credentials to SSH into the machine.

1. Go to **Manage Jenkins → Credentials → System → Global credentials**
2. Click **Add Credentials**
3. Fill in:
   - **Kind:** Username with password *(or SSH Username with private key if you prefer key-based auth)*
   - **Username:** `jenkins`
   - **Password:** the password you set in Step 1
   - **ID:** `linux-agent-ssh`
   - **Description:** `Linux Agent SSH Credentials`
4. Click **Create**

> **For production**, always use SSH key-based authentication instead of passwords. Generate a key pair with `ssh-keygen`, add the public key to the agent's `~/.ssh/authorized_keys`, and use "SSH Username with private key" in Jenkins.

---

### Step 3: Add the Agent Node in Jenkins

1. Go to **Manage Jenkins → Nodes → New Node**
2. Fill in:
   - **Node name:** `linux-agent-1`
   - **Type:** Permanent Agent
3. Click **Create**, then configure:

| Setting | Value | Why |
|---------|-------|-----|
| **Description** | `Linux build agent` | Just a label for the UI |
| **Number of executors** | `2` | How many builds can run in parallel on this agent |
| **Remote root directory** | `/home/jenkins/agent` | Where Jenkins stores build workspaces on the agent |
| **Labels** | `linux docker` | Used in pipelines to target this agent |
| **Usage** | `Only build jobs with label expressions matching this node` | Prevents random jobs from landing here |
| **Launch method** | `Launch agents via SSH` | Jenkins SSHs into the machine to start the agent |
| **Host** | `<your-agent-IP>` | The IP from Step 1 |
| **Credentials** | `linux-agent-ssh` | The credentials from Step 2 |
| **Host Key Verification Strategy** | `Non verifying Verification Strategy` | Fine for labs — use "Known hosts" in production |

4. Click **Save**

---

### Step 4: Verify the Agent is Connected

After saving, Jenkins will attempt to connect. Check the status:

1. Go to **Manage Jenkins → Nodes**
2. Click on **linux-agent-1**
3. Click **Log** in the left sidebar

You should see output ending with:

```
Agent successfully connected and online
```

The node list should show your agent with a green dot indicating it's online.

> **If it fails to connect**, check:
> - Can Jenkins reach the agent IP? (network/firewall)
> - Is SSH running on the agent? (`sudo systemctl status ssh`)
> - Are the credentials correct? (try SSHing manually first)
> - Is Java installed on the agent? (`java -version`)

---

### Step 5: Run a Test Job on the Agent

Create a quick freestyle job to verify everything works:

1. **New Item** → Name: `test-linux-agent` → **Freestyle project**
2. Under **General** → check **Restrict where this project can be run**
   - **Label Expression:** `linux`
3. Under **Build Steps** → **Execute shell:**

```bash
echo "========================================="
echo " Running on a permanent Linux agent!"
echo "========================================="
echo "Hostname: $(hostname)"
echo "User:     $(whoami)"
echo "Java:     $(java -version 2>&1 | head -1)"
echo "Git:      $(git --version)"
echo "Docker:   $(docker --version 2>/dev/null || echo 'not installed')"
echo "Python:   $(python3 --version 2>/dev/null || echo 'not installed')"
echo "Work dir: $(pwd)"
echo "========================================="
```

4. Click **Save** → **Build Now**
5. Check **Console Output** — it should show the agent machine's hostname, not the Jenkins controller's

---

### Step 6: Use the Agent in a Pipeline

Update your Jenkinsfile to target the agent using its label:

```groovy
pipeline {
    agent { label 'linux' }

    stages {
        stage('Hello from Agent') {
            steps {
                echo "Running on: ${env.NODE_NAME}"
                sh 'hostname'
            }
        }
    }
}
```

Or if you want different stages on different agents:

```groovy
pipeline {
    agent none

    stages {
        stage('Test') {
            agent { label 'linux' }
            steps {
                sh 'python3 -m pytest tests/ -v'
            }
        }

        stage('Build Docker Image') {
            agent { label 'docker' }
            steps {
                sh 'docker build -t myapp .'
            }
        }
    }
}
```

> **`agent any`** - runs on whatever is available (controller or any agent)
> **`agent { label 'linux' }`** - runs only on nodes with the `linux` label
> **`agent none`** - no default agent; each stage picks its own

---
