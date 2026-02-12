# Session 3: Hands-on Lab Guide
## Advanced Docker with GenAI

**Objective**: Master production patterns and deploy AI applications

---

## Pre-Lab Checklist

Before starting, ensure:
- ✅ Docker is running (4GB+ RAM allocated)
- ✅ Completed Sessions 1 & 2
- ✅ 10GB+ free disk space
- ✅ Internet connection for downloading models
- ✅ Terminal/Command Prompt open

---

## Lab 1: Multi-Stage Build Optimization

### Objective
Transform a bloated single-stage image into an optimized multi-stage build.

### Step 1: Create a Go Application

```bash
mkdir go-multistage && cd go-multistage
```

Create `main.go`:
```go
package main

import (
    "fmt"
    "log"
    "net/http"
    "time"
)

func handler(w http.ResponseWriter, r *http.Request) {
    html := `
    <!DOCTYPE html>
    <html>
    <head>
        <title>Optimized Go App</title>
        <style>
            body {
                font-family: Arial, sans-serif;
                max-width: 600px;
                margin: 100px auto;
                padding: 20px;
                text-align: center;
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                color: white;
            }
            .container {
                background: rgba(255,255,255,0.1);
                padding: 40px;
                border-radius: 15px;
                backdrop-filter: blur(10px);
            }
        </style>
    </head>
    <body>
        <div class="container">
            <h1>🚀 Multi-Stage Build Success!</h1>
            <p>This is a highly optimized Docker image</p>
            <p>Build time: %s</p>
        </div>
    </body>
    </html>
    `
    fmt.Fprintf(w, html, time.Now().Format("2006-01-02 15:04:05"))
}

func main() {
    http.HandleFunc("/", handler)
    fmt.Println("Server starting on :8080...")
    log.Fatal(http.ListenAndServe(":8080", nil))
}
```

### Step 2: Single-Stage Dockerfile (Bad Example)

Create `Dockerfile.single`:
```dockerfile
FROM golang:1.21

WORKDIR /app

COPY main.go .

RUN go build -o server main.go

EXPOSE 8080

CMD ["./server"]
```

Build and check size:
```bash
docker build -f Dockerfile.single -t go-app:single .
docker images | grep go-app
```

**Expected Size:** ~800MB+ (includes entire Go toolchain!) ❌

### Step 3: Multi-Stage Dockerfile (Best Practice)

Create `Dockerfile`:
```dockerfile
# Build stage
FROM golang:1.21-alpine AS builder

WORKDIR /app

COPY main.go .

# Build with optimizations
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-w -s" -o server main.go

# Runtime stage
FROM alpine:latest

WORKDIR /app

# Copy only the binary
COPY --from=builder /app/server .

EXPOSE 8080

CMD ["./server"]
```

Build and compare:
```bash
docker build -t go-app:multi .
docker images | grep go-app
```

**Expected Size:** ~15-20MB (97% reduction!) ✅

### Step 4: Test Both Images

```bash
# Run single-stage
docker run -d -p 8080:8080 --name single go-app:single

# Check it works
curl http://localhost:8080

# Stop and remove
docker stop single && docker rm single

# Run multi-stage
docker run -d -p 8080:8080 --name multi go-app:multi

# Check it works (same functionality!)
curl http://localhost:8080
# Or visit: http://localhost:8080 in browser

# Clean up
docker stop multi && docker rm multi
```

### Step 5: Analyze the Difference

```bash
# Compare image details
docker history go-app:single
docker history go-app:multi

# See layers count
docker inspect go-app:single | grep -A 20 "Layers"
docker inspect go-app:multi | grep -A 20 "Layers"
```

### ✅ Lab 1 Complete!
**Key Learning:** Multi-stage builds dramatically reduce image size while maintaining functionality!

---

## Lab 2: Ollama GenAI Container

### Objective
Deploy and interact with a local LLM using Ollama in Docker.

### Step 1: Pull Ollama Image

```bash
docker pull ollama/ollama:latest
```

**Note:** This is ~700MB download - patience required!

### Step 2: Run Ollama Container

```bash
docker run -d \
  --name ollama \
  -p 11434:11434 \
  -v ollama-data:/root/.ollama \
  ollama/ollama
```

Verify it's running:
```bash
docker ps | grep ollama
docker logs ollama
```

### Step 3: Download a Small Model

**Important:** We'll use a small model (1-2GB) for class:

```bash
# Pull llama3.2:1b (smallest, ~1GB)
docker exec ollama ollama pull llama3.2:1b
```

**Wait for download to complete** (progress shown):
```
pulling manifest
pulling 43f7a214e5e0... 100% ▕████████████▏ 1.3 GB
pulling 8c17c2ebb0ea... 100% ▕████████████▏  7.0 KB
pulling 590d74a5569b... 100% ▕████████████▏  4.8 KB
pulling 0ba8f0e314b4... 100% ▕████████████▏   78 B
pulling 56bb8bd477a5... 100% ▕████████████▏  100 B
verifying sha256 digest
writing manifest
success
```

### Step 4: List Available Models

```bash
docker exec ollama ollama list
```

**Expected Output:**
```
NAME               ID              SIZE      MODIFIED
llama3.2:1b        baf6a787fdbf    1.3 GB    2 minutes ago
```

### Step 5: Test Ollama API

Simple test:
```bash
curl http://localhost:11434/api/generate -d '{
  "model": "llama3.2:1b",
  "prompt": "What is Docker in one sentence?",
  "stream": false
}'
```

**Expected:** JSON response with AI-generated answer!

### Step 6: Create Python Client Application

```bash
mkdir ollama-client && cd ollama-client
```

Create `requirements.txt`:
```
requests==2.31.0
```

Create `client.py`:
```python
import requests
import json
import sys

OLLAMA_URL = "http://localhost:11434"

def chat(prompt, model="llama3.2:1b"):
    """Send prompt to Ollama and get response"""
    try:
        response = requests.post(
            f"{OLLAMA_URL}/api/generate",
            json={
                "model": model,
                "prompt": prompt,
                "stream": False
            },
            timeout=60
        )
        response.raise_for_status()
        data = response.json()
        return data.get('response', 'No response')
    except requests.exceptions.RequestException as e:
        return f"Error: {e}"

def main():
    print("=" * 60)
    print("OLLAMA DOCKER CLIENT")
    print("=" * 60)
    
    if len(sys.argv) > 1:
        # Command line prompt
        prompt = ' '.join(sys.argv[1:])
        print(f"\nPrompt: {prompt}")
        print("\nResponse:")
        print(chat(prompt))
    else:
        # Interactive mode
        print("\nEnter prompts (or 'quit' to exit):\n")
        while True:
            try:
                prompt = input("You: ")
                if prompt.lower() in ['quit', 'exit', 'q']:
                    break
                if prompt.strip():
                    print("\nOllama:", chat(prompt))
                    print()
            except KeyboardInterrupt:
                break
    
    print("\n" + "=" * 60)

if __name__ == "__main__":
    main()
```

### Step 7: Test the Client

```bash
# Install dependencies
pip install -r requirements.txt --break-system-packages

# Single prompt test
python client.py "Explain containers in simple terms"

# Interactive mode
python client.py
# You: What are the benefits of Docker?
# You: How does multi-stage build work?
# You: quit
```

### Step 8: Create Flask Web Interface

Create `web_client.py`:
```python
from flask import Flask, render_template_string, request, jsonify
import requests

app = Flask(__name__)
OLLAMA_URL = "http://localhost:11434"

HTML_TEMPLATE = '''
<!DOCTYPE html>
<html>
<head>
    <title>Ollama Chat</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            max-width: 800px;
            margin: 50px auto;
            padding: 20px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
        }
        .container {
            background: white;
            padding: 30px;
            border-radius: 15px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.3);
        }
        .chat-box {
            height: 400px;
            overflow-y: auto;
            border: 1px solid #ddd;
            padding: 15px;
            margin: 20px 0;
            background: #f9f9f9;
            border-radius: 8px;
        }
        .message {
            margin: 10px 0;
            padding: 10px;
            border-radius: 8px;
        }
        .user { background: #e3f2fd; text-align: right; }
        .ai { background: #f1f8e9; }
        input[type="text"] {
            width: calc(100% - 100px);
            padding: 12px;
            border: 1px solid #ddd;
            border-radius: 5px;
            font-size: 16px;
        }
        button {
            padding: 12px 25px;
            background: #4CAF50;
            color: white;
            border: none;
            border-radius: 5px;
            cursor: pointer;
            font-size: 16px;
        }
        button:hover { background: #45a049; }
        .loading { color: #666; font-style: italic; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🤖 Ollama Chat Interface</h1>
        <p>Powered by Docker + Ollama + Llama 3.2</p>
        
        <div class="chat-box" id="chatBox"></div>
        
        <input type="text" id="prompt" placeholder="Ask me anything..." onkeypress="if(event.key==='Enter') sendMessage()">
        <button onclick="sendMessage()">Send</button>
    </div>
    
    <script>
        function addMessage(text, isUser) {
            const chatBox = document.getElementById('chatBox');
            const msg = document.createElement('div');
            msg.className = 'message ' + (isUser ? 'user' : 'ai');
            msg.textContent = (isUser ? 'You: ' : 'AI: ') + text;
            chatBox.appendChild(msg);
            chatBox.scrollTop = chatBox.scrollHeight;
        }
        
        async function sendMessage() {
            const input = document.getElementById('prompt');
            const prompt = input.value.trim();
            if (!prompt) return;
            
            addMessage(prompt, true);
            input.value = '';
            
            const chatBox = document.getElementById('chatBox');
            const loading = document.createElement('div');
            loading.className = 'message loading';
            loading.textContent = 'AI is thinking...';
            loading.id = 'loading';
            chatBox.appendChild(loading);
            chatBox.scrollTop = chatBox.scrollHeight;
            
            try {
                const response = await fetch('/api/chat', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ prompt: prompt })
                });
                const data = await response.json();
                
                document.getElementById('loading').remove();
                addMessage(data.response, false);
            } catch (error) {
                document.getElementById('loading').remove();
                addMessage('Error: ' + error.message, false);
            }
        }
    </script>
</body>
</html>
'''

@app.route('/')
def home():
    return render_template_string(HTML_TEMPLATE)

@app.route('/api/chat', methods=['POST'])
def chat():
    data = request.json
    prompt = data.get('prompt', '')
    
    try:
        response = requests.post(
            f"{OLLAMA_URL}/api/generate",
            json={
                "model": "llama3.2:1b",
                "prompt": prompt,
                "stream": False
            },
            timeout=60
        )
        response.raise_for_status()
        result = response.json()
        return jsonify({'response': result.get('response', 'No response')})
    except Exception as e:
        return jsonify({'response': f'Error: {str(e)}'}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)
```

Update `requirements.txt`:
```
requests==2.31.0
Flask==3.0.0
```

Install and run:
```bash
pip install Flask --break-system-packages
python web_client.py
```

Visit **http://localhost:5000** and chat with the AI! 🤖

### Step 9: Resource Monitoring

While the AI is running, monitor resources:
```bash
# In another terminal
docker stats ollama
```

Watch CPU and memory usage spike during generation!

### ✅ Lab 2 Complete!
You've deployed a local AI model in Docker! 🎉

---

## Lab 3: Security & Resource Management (5 minutes)

### Objective
Implement production security and resource controls.

### Step 1: Secure Dockerfile Example

Create `Dockerfile.secure`:
```dockerfile
FROM python:3.9-alpine

# Create non-root user
RUN addgroup -g 1000 appgroup && \
    adduser -D -u 1000 -G appgroup appuser

WORKDIR /app

# Install dependencies as root
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy app
COPY app.py .

# Switch to non-root user
USER appuser

EXPOSE 5000

CMD ["python", "app.py"]
```

### Step 2: Resource-Limited Compose

Create `docker-compose.secure.yml`:
```yaml
version: '3.8'

services:
  app:
    build:
      context: .
      dockerfile: Dockerfile.secure
    read_only: true
    security_opt:
      - no-new-privileges:true
    deploy:
      resources:
        limits:
          cpus: '1.0'
          memory: 512M
        reservations:
          cpus: '0.5'
          memory: 256M
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "python", "-c", "import requests; requests.get('http://localhost:5000/health')"]
      interval: 30s
      timeout: 3s
      retries: 3
```

### Step 3: Test Resource Limits

```bash
# Run with limits
docker run -d \
  --name limited-app \
  --memory="256m" \
  --cpus="0.5" \
  python:3.9-alpine sleep 3600

# Check stats
docker stats limited-app

# Try to exceed memory (will be killed)
docker exec limited-app sh -c 'python -c "s = \"a\" * 10**9"'

# Clean up
docker stop limited-app && docker rm limited-app
```

### ✅ Lab 3 Complete!
Security and resource controls mastered!

---