# Docker Installation Guide
## Pre-Session Setup Instructions

---

## Table of Contents
1. [Windows Installation](#windows-installation)
2. [macOS Installation](#macos-installation)
3. [Linux Installation](#linux-installation)
4. [Docker Hub Account Setup](#docker-hub-account-setup)
5. [Pre-flight Check](#pre-flight-check)

---

## Windows Installation

### Prerequisites
- Windows 10 64-bit: Pro, Enterprise, or Education (Build 19041 or higher)
- OR Windows 11 64-bit

### Step 1: Enable WSL2 (Windows Subsystem for Linux)

Open PowerShell as **Administrator** and run:

```powershell
wsl --install
```

This command will:
- Enable WSL
- Install Ubuntu as default Linux distribution
- Enable Virtual Machine Platform

**Restart your computer** after this step.

### Step 2: Download Docker Desktop

1. Visit: **https://docs.docker.com/desktop/install/windows-install/**
2. Click "Download Docker Desktop for Windows"
3. Run the installer (Docker Desktop Installer.exe)
4. Follow the installation wizard
5. Ensure "Use WSL 2 instead of Hyper-V" is selected
6. Complete installation and restart if prompted

### Step 3: Start Docker Desktop

1. Launch Docker Desktop from Start Menu
2. Accept the Docker Subscription Service Agreement
3. Wait for Docker Engine to start (whale icon in system tray should be stable)

### Step 4: Verify Installation

Open **Command Prompt** or **PowerShell** and run:

```cmd
docker --version
docker-compose --version
docker run hello-world
```

**Expected Output**:
```
Docker version 24.x.x, build xxxxxxx
Docker Compose version v2.x.x
...
Hello from Docker!
This message shows that your installation appears to be working correctly.
```

---

## macOS Installation

### For Intel Macs

### Step 1: Download Docker Desktop

1. Visit: **https://docs.docker.com/desktop/install/mac-install/**
2. Download "Docker Desktop for Mac with Intel chip"
3. Open the downloaded .dmg file
4. Drag Docker icon to Applications folder

### Step 2: Launch Docker Desktop

1. Open Docker from Applications
2. Grant permissions when prompted
3. Wait for Docker to start (whale icon in menu bar)

### For Apple Silicon (M1/M2/M3) Macs

### Step 1: Install Rosetta 2 (if not already installed)

Open Terminal and run:

```bash
softwareupdate --install-rosetta
```

### Step 2: Download Docker Desktop

1. Visit: **https://docs.docker.com/desktop/install/mac-install/**
2. Download "Docker Desktop for Mac with Apple silicon"
3. Open the downloaded .dmg file
4. Drag Docker icon to Applications folder

### Step 3: Launch Docker Desktop

1. Open Docker from Applications
2. Grant permissions when prompted
3. Wait for Docker to start

### Step 4: Verify Installation (All Macs)

Open **Terminal** and run:

```bash
docker --version
docker-compose --version
docker run hello-world
```

**Expected Output**:
```
Docker version 24.x.x, build xxxxxxx
Docker Compose version v2.x.x
...
Hello from Docker!
This message shows that your installation appears to be working correctly.
```

---

## Linux Installation

### Ubuntu / Debian

### Step 1: Update Package Index

```bash
sudo apt-get update
```

### Step 2: Install Prerequisites

```bash
sudo apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release
```

### Step 3: Add Docker's Official GPG Key

```bash
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
```

### Step 4: Set Up Repository

```bash
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
```

### Step 5: Install Docker Engine

```bash
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

### Step 6: Add Your User to Docker Group

```bash
sudo usermod -aG docker $USER
```

**Important**: Log out and log back in for this to take effect, or run:

```bash
newgrp docker
```

### Step 7: Verify Installation

```bash
docker --version
docker compose version
docker run hello-world
```

---

## Docker Hub Account Setup

### Step 1: Create Account

1. Visit: **https://hub.docker.com/**
2. Click "Sign Up"
3. Fill in:
   - Docker ID (username)
   - Email address
   - Password
4. Complete the registration

### Step 2: Verify Email

1. Check your email inbox
2. Click the verification link
3. Confirm your account

### Step 3: Login from CLI (Optional)

```bash
docker login
```

Enter your Docker ID and password when prompted.

---

## Pre-flight Check

Run these commands to ensure everything is working:

### 1. Check Docker Version
```bash
docker --version
```

### 2. Check Docker Compose
```bash
docker compose version
```

### 3. Test Docker Run
```bash
docker run hello-world
```

### 4. Check Docker Info
```bash
docker info
```

### 5. Pull a Test Image
```bash
docker pull nginx:alpine
docker images
```

### 6. Run and Test Nginx
```bash
docker run -d -p 8080:80 --name test-nginx nginx:alpine
```

Open browser and visit: `http://localhost:8080`


Clean up:
```bash
docker stop test-nginx
docker rm test-nginx
```

---