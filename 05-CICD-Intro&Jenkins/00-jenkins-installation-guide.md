# Jenkins Installation & Setup Guide

## Pre-Session Setup Instructions

> **Objective:** Install Jenkins, complete initial setup, harden security, configure Docker agents, and verify everything is production-ready - all in one guided walkthrough.

---

## Prerequisites

Before you begin, ensure you have:

- **Docker** installed and running (Windows / macOS / Linux)
- **Git** installed (for later pipeline labs)
- **A modern browser** (Chrome, Firefox, Edge)
- **Ports 8080 and 50000 available** on your machine

> **Why Docker?** Docker gives us a platform-agnostic, portable installation. Your Jenkins config survives restarts via a named volume, and you can tear it all down cleanly when done.

---

## Phase 1: Choose Your Installation Path

Jenkins requires **Java (JDK 17)**. Choose the method that matches your environment. We recommend **Docker** for the cleanest experience, but all paths lead to the same Jenkins.

### Option A: Docker (Recommended - The "Portable" Way)

*Best for keeping your host machine clean. Works identically on Windows, macOS, and Linux.*

This setup uses **Docker-in-Docker (DinD)** - Jenkins gets its own isolated Docker daemon instead of sharing the host's. This is cleaner and closer to how production CI/CD environments work.

**Step 1: Create a project folder and add these two files:**
```bash
mkdir jenkins-setup && cd jenkins-setup
```

Copy **`Dockerfile-Jenkins`** from the current folder
Copy **`docker-compose-Jenkins.yml`** from the current folder

**Step 2: Build and start**
```bash
docker compose -f docker-compose-Jenkins.yml up -d --build
```

**Step 3: Wait ~60 seconds, then verify:**
```bash
docker compose -f docker-compose-Jenkins.yml logs -f jenkins"
```

> **Why DinD?** Instead of sharing the host's Docker daemon (socket mount), Jenkins gets its own isolated Docker daemon running in a separate container. This means builds can't accidentally affect your host, and it mirrors how production CI environments work. The two containers communicate securely over TLS.

> **Why `--privileged`?** The DinD container needs it to run a Docker daemon inside a container. This is scoped to the DinD container only - Jenkins itself runs unprivileged.

> **Why port 50000?** This is the JNLP port used for agent communication. When Jenkins agents connect back to the controller, they use this port.
```

### Option B: Linux (Ubuntu/Debian - Native)

Run the following commands in your terminal:

```bash
# Install Java 17
sudo apt update
sudo apt install -y fontconfig openjdk-17-jre

# Add Jenkins repository key and source
curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key | sudo tee \
  /usr/share/keyrings/jenkins-keyring.asc > /dev/null

echo deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] \
  https://pkg.jenkins.io/debian-stable binary/ | sudo tee \
  /etc/apt/sources.list.d/jenkins.list > /dev/null

# Install and start Jenkins
sudo apt update
sudo apt install -y jenkins
sudo systemctl start jenkins
sudo systemctl enable jenkins
```

**Verify it's running:**

```bash
sudo systemctl status jenkins
# You should see "active (running)"
```

**Access:** http://localhost:8080
**Logs:** `journalctl -u jenkins -f`

### Option C: macOS (Homebrew)

```bash
brew install jenkins-lts
brew services start jenkins-lts
```

**Access:** http://localhost:8080
**Stop:** `brew services stop jenkins-lts`

> **Note:** Homebrew automatically handles the Java 17 dependency.

### Option D: Windows (Native MSI)

1. **Download** the `.msi` installer from [jenkins.io/download](https://www.jenkins.io/download/)
2. **Install Java 17** first (Adoptium/Temurin recommended)
3. **Run** the MSI installer — it installs Jenkins as a Windows Service
4. During setup, choose **"Run service as LocalSystem"** (for lab purposes)
5. Default port: `8080`

**Access:** http://localhost:8080
**Service management:** Find "Jenkins" in `services.msc`

---

## Phase 2: Initial Setup Wizard

*Regardless of how you installed Jenkins, the browser setup is identical.*

### Step 1: Unlock Jenkins

Open your browser to **http://localhost:8080**. You'll see a screen asking for the **initial admin password**.

Retrieve it based on your installation method:

| Method | Command |
|--------|---------|
| Docker | `docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword` |
| Linux | `sudo cat /var/lib/jenkins/secrets/initialAdminPassword` |
| macOS | Check the file path shown on the unlock screen |
| Windows | Open the file path shown on the unlock screen in Notepad |

Copy and paste this password into the browser.

### Step 2: Install Plugins

Select **"Install Suggested Plugins"** and wait 3-5 minutes. This installs the essential set: Git, Pipeline, Credentials, SSH, and more.

### Step 3: Create Admin User

Fill in:
- **Username:** `admin` (or your preferred username)
- **Password:** Choose something strong
- **Full name:** Your name
- **Email:** Your email address

### Step 4: Configure Instance

- **Jenkins URL:** Keep `http://localhost:8080/`
- If running on a remote server, change to your server's IP or domain
- Click **"Save and Finish"** → **"Start using Jenkins"**

> **You're in!** You should now see the Jenkins dashboard.

---

## Phase 3: Install Additional Plugins

The suggested plugins are a good start, but for real-world CI/CD pipelines, we need more. Go to **Manage Jenkins -> Plugins -> Available Plugins** and install:

| Plugin Name | Why You Need It |
|-------------|-----------------|
| Docker Pipeline | Build Docker images directly in pipeline scripts |
| Amazon ECR | Authenticate and push images to AWS ECR |
| GitHub Integration | PR build triggers, commit status updates |
| Blue Ocean | Modern visual pipeline editor and UI |
| Credentials Binding | Safely inject secrets via `withCredentials` block |
| Role-Based Authorization Strategy | Fine-grained user/team access control |
| Generic Webhook Trigger | Custom webhook payloads from any source |

**How to install:**

```
1. Search for each plugin name in the search bar
2. Check the checkbox next to each
3. Click "Install" (without restart)
4. After all are queued, check "Restart Jenkins when installation is complete"
5. Wait for Jenkins to restart and log back in
```

**Verify plugins are installed:**
Go to **Manage Jenkins -> Plugins -> Installed Plugins** and confirm each one appears in the list.

---

## Phase 4: Harden Security

> **CRITICAL:** By default, Jenkins allows anyone who can reach port 8080 to have full admin access. This is the single most common Jenkins security mistake. Fix it now.

### Step 1: Enable Matrix-Based Security

1. Go to **Manage Jenkins → Security**
2. Under **Authorization**, change from "Anyone can do anything" to **"Matrix-based security"**
3. Add your admin user → check **ALL** permissions
4. **Uncheck ALL Anonymous permissions** (or leave only Overall/Read if you want a public dashboard)
5. Click **Save**

### Step 2: Disable Sign-Up

1. Still in **Security** settings
2. Under **Security Realm**, ensure "Allow users to sign up" is **unchecked**
3. Click **Save**

### Step 3: Verify Lockdown

1. Open an incognito/private browser window
2. Go to http://localhost:8080
3. You should see a login page - not the dashboard
4. Verify you cannot see any jobs or configuration

> **If you lock yourself out:** Stop Jenkins, edit `config.xml`, set `<useSecurity>false</useSecurity>`, restart, fix permissions, re-enable security.

---

## Phase 5: Configure Jenkins URL

1. Go to **Manage Jenkins -> System**
2. Find **Jenkins Location -> Jenkins URL**
3. Set it to `http://localhost:8080/` (or your server's actual URL)
4. Set the **System Admin e-mail address**
5. Click **Save**

> **Why this matters:** Jenkins uses this URL in email notifications, webhook callbacks, and Blue Ocean links. An incorrect URL means broken links everywhere.

---

## Phase 6: Understanding Agents (The "Workers")

Jenkins follows a **Controller + Agent** architecture:
- **Controller** (Master): The brain - hosts the UI, stores configs, schedules builds
- **Agents** (Workers): The muscle - actually run your build commands

> **Best Practice:** The controller should only orchestrate. Never run build workloads on the controller node. This is a security and performance anti-pattern.

### Option 1: Docker Agent (Recommended - The Modern Way)

*This allows Jenkins to "spin up" a container, run a build, and delete it immediately. Ephemeral, clean, and cloud-native.*

**Configure Docker Cloud:**

1. Go to **Manage Jenkins -> Nodes and Clouds -> Clouds -> Add a new cloud -> Docker**
2. **Docker Host URI:**
   - Linux/macOS/Docker Desktop: `unix:///var/run/docker.sock`
   - Windows (native): `npipe://./pipe/docker_engine`
3. Click **Test Connection** - you should see "Version: ..." confirming Jenkins can talk to Docker
4. Click **Save**

**Add a Docker Agent Template:**

1. Under the Docker cloud you just created, click **Docker Agent Templates -> Add**
2. Configure:
   - **Labels:** `docker-agent`
   - **Docker Image:** `jenkins/agent:latest-jdk17`
   - **Remote File System Root:** `/home/jenkins/agent`
   - **Usage:** "Only build jobs with label expressions matching this node"
   - **Pull Strategy:** "Pull once and update latest"
3. Click **Save**

> **How it works:** When a job requests the `docker-agent` label, Jenkins automatically pulls the image, starts a container, runs the build inside it, and destroys the container when done. Zero cleanup, zero state leakage between builds.


### Where Do Docker Agents Actually Run?

When we configure Docker agents using `unix:///var/run/docker.sock`, the agent containers run **on the same machine** as the Jenkins controller. Here's why:

By mounting the Docker socket, we give Jenkins access to the **host machine's Docker daemon**. When a build is triggered, Jenkins tells that Docker daemon to spin up a new container - and since it's the local daemon, the container runs locally.

**Our Lab Setup (Single Host):**
```
┌────────────────────────────────────────────────┐
│           Your Machine (Host)                  │
│                                                │
│   ┌───────────────────┐                        │
│   │ Jenkins Controller│──── docker.sock ──┐    │
│   │   (container)     │                   │    │
│   └───────────────────┘                   │    │
│                                           ▼    │
│                               Docker Daemon    │
│                                      │         │
│                              ┌───────┴───┐     │
│                              ▼           ▼     │
│                     ┌──────────┐ ┌──────────┐  │
│                     │  Agent 1 │ │  Agent 2 │  │
│                     │(ephemeral│ │(ephemeral│  │
│                     │container)│ │container)│  │
│                     └──────────┘ └──────────┘  │
└────────────────────────────────────────────────┘
```

This is perfectly fine for **learning, labs, and small teams**.

**Production Setup (Separate Hosts):**

In production, you'd separate controller and agents to avoid resource contention:

Remote Docker Host: Change URI to `tcp://build-server:2376` - agents run on a dedicated build server

So tcp://build-server:2376 means "connect to the Docker daemon running on build-server over a secure TLS connection on port 2376." Jenkins then sends Docker commands over the network to that remote machine, and the agent containers spin up there instead of locally.

> **Key takeaway:** In our lab, everything runs on one machine. In production, you'd point Jenkins to a remote Docker daemon or Kubernetes cluster so the controller stays lean and build workloads run on dedicated worker nodes.


### Option 2: Permanent SSH Agent (The Traditional Way)

*Use this if you have a dedicated build server (VM, EC2 instance, etc.).*

1. **On the Agent Machine:**
   - Install Java 17
   - Create a `jenkins` user: `sudo useradd -m jenkins`
   - Ensure SSH is running

2. **On Jenkins UI:**
   - Go to **Manage Jenkins → Nodes → New Node**
   - **Node name:** `linux-build-agent`
   - **Type:** Permanent Agent
   - **Remote root directory:** `/home/jenkins/agent`
   - **Labels:** `linux`
   - **Launch method:** "Launch agent via SSH"
   - **Host:** IP address of your agent machine
   - **Credentials:** Add SSH key or username/password
   - **Host Key Verification Strategy:** "Non verifying" (for lab) or "Known hosts" (for production)

3. Click **Save** and check the agent log — it should show "Agent successfully connected"

---

## Phase 7: Verification — Prove Everything Works

Create a test job to verify your entire setup is functioning correctly.

### Test: Freestyle Job on Docker Agent

1. From the Jenkins dashboard, click **"New Item"**
2. Enter name: `test-docker-agent`
3. Select **"Freestyle project"** -> Click **OK**
4. Under **General -> Restrict where this project can be run:**
   - Label Expression: `docker-agent`
5. Under **Build Steps -> Add build step -> Execute shell:**

```bash
echo "========================================="
echo "Hello from inside a Docker container!"
echo "========================================="
echo "Hostname: $(hostname)"
echo "User: $(whoami)"
echo "Java: $(java -version 2>&1 | head -1)"
echo "Working dir: $(pwd)"
echo "Date: $(date)"
echo "========================================="
```

6. Click **Save** -> Click **"Build Now"**
7. Click on build #1 -> **Console Output**

**Expected result:** You should see output from inside a temporary container - a different hostname each time, proving Jenkins is spinning up ephemeral agents.

---

## Final Checklist

Before moving on, verify every item:

| Check | Status |
|-------|--------|
| Jenkins accessible at http://localhost:8080 | ☐ |
| Login with admin credentials works | ☐ |
| All additional plugins installed and active | ☐ |
| Anonymous access disabled (Matrix security) | ☐ |
| User sign-up disabled | ☐ |
| Jenkins URL configured correctly | ☐ |
| Docker cloud connection test passes | ☐ |
| Docker agent template configured | ☐ |
| Freestyle test job runs on Docker agent | ☐ |
| Pipeline test job runs successfully | ☐ |

---

## Troubleshooting

### Jenkins won't start

```bash
# Check if port 8080 is already in use
lsof -i :8080          # macOS/Linux
netstat -ano | find "8080"  # Windows

# Check Docker container logs
docker logs jenkins --tail 50
```

### "Permission denied" on Docker socket

```bash
# The Jenkins container needs access to the Docker socket
# On Linux, you may need:
sudo chmod 666 /var/run/docker.sock

# Or add the jenkins user to the docker group:
sudo usermod -aG docker jenkins
```

### Docker agent fails to connect

- Verify Docker cloud Test Connection passes
- Check that the Docker image `jenkins/agent:latest-jdk17` can be pulled: `docker pull jenkins/agent:latest-jdk17`
- Ensure port 50000 is exposed (it's the JNLP agent port)

### Locked out after security changes

```bash
# For Docker installation:
docker exec -it jenkins bash
# Edit config.xml and set <useSecurity>false</useSecurity>
# Then restart:
docker restart jenkins
# Fix permissions in the UI, then re-enable security
```

### Plugins fail to install

- Check your internet connection
- Go to **Manage Jenkins -> Plugins -> Advanced** and verify the update site URL
- Try: **Manage Jenkins -> Plugins -> Check now** to refresh the plugin list

---