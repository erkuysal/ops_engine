# OpsEngine: Complete DevOps Infrastructure Detection

## Overview

This document demonstrates how opsengine detects and integrates with **real DevOps infrastructure**: Docker, CI/CD pipelines, build systems, and deployment configurations.

## What Gets Detected

### 1. Docker Infrastructure Detection

#### Dockerfile Analysis
```bash
ops docker detect
```

**Detects:**
- ✅ All Dockerfiles in project (including multi-service setups)
- ✅ Base images used (`FROM node:18`, `FROM python:3.11`, etc.)
- ✅ Multi-stage build detection
- ✅ Build arguments (`ARG` instructions)
- ✅ BuildKit mount features
- ✅ .dockerignore presence

**Analysis:**
```
Dockerfile (backend/):
  Base: python:3.11-slim
  Multi-stage: Yes (2 stages)
  Build args: 3
  BuildKit: Yes (cache mounts)

Dockerfile (frontend/):
  Base: node:18-alpine
  Multi-stage: Yes (3 stages: build → deps → final)
  Build args: 1
  BuildKit: No
```

#### docker-compose Detection
```bash
ops docker detect
```

**Detects:**
- ✅ All docker-compose files (prod, staging, test)
- ✅ Services defined per compose file
- ✅ Volume configurations
- ✅ Network configurations
- ✅ Build contexts
- ✅ Service dependencies (`depends_on`)

**Output:**
```
docker-compose.yml:
  Services: backend, frontend, voice-app, postgres, redis
  Volumes: Yes (postgres-data, redis-data)
  Networks: app-network, db-network
  Build services: backend, frontend, voice-app

docker-compose.staging.yml:
  Services: backend, frontend, nginx
  Volumes: Yes
  Networks: staging-network
```

#### Existing Images Detection
```bash
ops docker detect
```

**Detects:**
- ✅ Images matching project name
- ✅ Image families (backend-v*, frontend-v*, etc.)
- ✅ Version tagging patterns
- ✅ Dangling images count
- ✅ Total disk usage per family

**Output:**
```
Found 12 existing images:
  erkuysal/personal-site:backend-v0.9.8 (2 days ago, 450MB)
  erkuysal/personal-site:backend-v0.9.7 (5 days ago, 448MB)
  erkuysal/personal-site:frontend-v0.9.8 (2 days ago, 85MB)
  ...

Image families: backend, frontend, voice-app
Dangling images: 3 (cleanup recommended)
```

#### Registry Detection
```bash
ops docker detect
```

**Detects:**
- ✅ Docker registry from compose files
- ✅ Registry type (Docker Hub, ghcr.io, GitLab, ECR, GCR)
- ✅ Organization/username

**Output:**
```
Registry: erkuysal (Docker Hub)
Alternative detected: ghcr.io/erkuysal (GitHub Container Registry)
```

### 2. CI/CD Infrastructure Detection

#### GitHub Actions
```bash
ops cicd detect
```

**Detects:**
- ✅ Workflow files in `.github/workflows/`
- ✅ Workflow names and purposes
- ✅ Trigger conditions (push, PR, schedule, manual)
- ✅ Jobs and steps
- ✅ Docker usage in workflows
- ✅ Deployment steps
- ✅ Test automation

**Output:**
```
GitHub Actions detected:
  • ci.yml (on: push, pull_request)
    - Jobs: test, build, deploy
    - Docker: Yes
    - Secrets used: 5
    
  • deploy-staging.yml (on: push to staging)
    - Jobs: deploy
    - Docker: Yes
    - Deploys to: staging.erkuysal.com
    
  • security-scan.yml (on: schedule, weekly)
    - Jobs: dependency-check, container-scan
```

#### GitLab CI
```bash
ops cicd detect
```

**Detects:**
- ✅ .gitlab-ci.yml configuration
- ✅ Pipeline stages
- ✅ Jobs per stage
- ✅ Docker-in-Docker usage
- ✅ Cache configuration
- ✅ Artifacts

**Output:**
```
GitLab CI detected:
  Stages: build, test, deploy
  
  Jobs:
    build: Uses docker:latest
    test: Runs unit tests
    deploy: SSH to production
    
  Docker: Yes (dind service)
  Cache: node_modules, pip cache
```

#### CircleCI
```bash
ops cicd detect
```

**Detects:**
- ✅ `.circleci/config.yml`
- ✅ Workflows and jobs
- ✅ Docker executors
- ✅ Orbs in use

**Output:**
```
CircleCI detected:
  Workflows: build-test-deploy
  Jobs: checkout, test, build, deploy
  Orbs: node, docker, aws-ecr
```

#### Jenkins
```bash
ops cicd detect
```

**Detects:**
- ✅ Jenkinsfile presence
- ✅ Pipeline type (declarative/scripted)
- ✅ Stages defined
- ✅ Docker agent usage

**Output:**
```
Jenkins detected:
  Type: Declarative Pipeline
  Stages: Build, Test, Deploy
  Docker: Yes (docker agent)
```

#### Deployment Scripts
```bash
ops cicd detect
```

**Detects:**
- ✅ Shell scripts for deployment
- ✅ Python/Node deployment scripts
- ✅ Ansible playbooks
- ✅ Terraform configurations

**Output:**
```
Deployment automation:
  Scripts:
    • deploy.sh (Docker compose deployment)
    • deploy-staging.sh (Staging environment)
    • ci-deploy.sh (CI-triggered deployment)
  
  Infrastructure as Code:
    • terraform/ (AWS infrastructure)
    • ansible/ (Server provisioning)
```

### 3. Build System Detection

#### Language/Framework Detection
```bash
ops build detect
```

**Detects:**
- ✅ Node.js projects (package.json)
- ✅ Python projects (setup.py, pyproject.toml)
- ✅ Go projects (go.mod)
- ✅ Java/Maven (pom.xml)
- ✅ .NET projects (*.csproj)
- ✅ Elixir projects (mix.exs)

**Output:**
```
Project types detected:

backend/:
  Type: Python (Django)
  Build: pip install + manage.py collectstatic
  Dependencies: requirements.txt

frontend/web/:
  Type: Node.js (Vue 3 + Vite)
  Build: npm run build
  Output: dist/
  Bundler: Vite

frontend/desktop/:
  Type: Node.js (Electron)
  Build: npm run dist:prod
  Bundler: Webpack + electron-builder

voice_app/:
  Type: Elixir (Phoenix)
  Build: mix compile + mix release
  Dependencies: mix.exs
```

#### Build Tool Detection
```bash
ops build detect
```

**Detects:**
- ✅ npm/yarn/pnpm scripts
- ✅ Makefile targets
- ✅ Build scripts (build.sh, compile.sh)
- ✅ Webpack/Vite/Rollup configs
- ✅ Docker build contexts

**Output:**
```
Build tools:
  package.json scripts:
    • build: vite build
    • build:prod: vite build --mode production
    • build:desktop: electron-builder
  
  Makefile:
    • make build (builds all services)
    • make build-backend
    • make build-frontend
  
  Shell scripts:
    • build.sh (orchestrates multi-service build)
    • backend/build.sh (Python-specific build)
```

#### Multi-Stage Build Detection
```bash
ops build detect
```

**Detects:**
- ✅ Multi-stage Dockerfiles
- ✅ Stage names and purposes
- ✅ Build optimizations
- ✅ BuildKit features (cache mounts, secrets)

**Output:**
```
Multi-stage builds:

backend/Dockerfile:
  Stage 1: builder (dependencies + compile)
  Stage 2: runtime (slim final image)
  Optimization: pip cache mount
  Size reduction: 850MB → 450MB

frontend/Dockerfile:
  Stage 1: deps (node_modules)
  Stage 2: builder (npm run build)
  Stage 3: runtime (nginx serve)
  Optimization: Multi-layer cache
  Size reduction: 1.2GB → 85MB
```

### 4. Deployment Infrastructure Detection

#### Server/Host Detection
```bash
ops deploy detect
```

**Detects:**
- ✅ Environment files (.env, .env.production)
- ✅ Server hostnames/IPs
- ✅ SSH configurations
- ✅ Deployment targets
- ✅ SSL/TLS certificate locations

**Output:**
```
Deployment targets:

Production:
  Host: erkuysal.com (1.2.3.4)
  User: ubuntu
  Method: Docker Compose (SSH)
  Certs: /etc/letsencrypt/live/erkuysal.com

Staging:
  Host: staging.erkuysal.com (5.6.7.8)
  User: deploy
  Method: Docker Compose (SSH)
  Certs: /srv/docker-certs/staging
```

#### Infrastructure as Code
```bash
ops deploy detect
```

**Detects:**
- ✅ Terraform configurations
- ✅ Ansible playbooks
- ✅ Kubernetes manifests
- ✅ Docker Swarm configs
- ✅ Helm charts

**Output:**
```
Infrastructure as Code:

Terraform:
  Provider: AWS
  Resources:
    • EC2 instances (3)
    • RDS database (PostgreSQL)
    • S3 buckets (2)
    • CloudFront distribution

Ansible:
  Playbooks:
    • setup.yml (initial server setup)
    • deploy.yml (application deployment)
    • update-certs.yml (SSL renewal)
```

## Integration Workflows

### Scenario 1: Existing Docker Project

```bash
cd existing-project/
ops docker detect

# Output:
# ✓ docker-compose.yml (3 services)
# ✓ 3 Dockerfiles detected
# ✓ 12 existing images found
# ✓ Registry: erkuysal/personal-site

ops docker integrate

# Prompts:
# Which compose file? [docker-compose.yml]
# Keep how many versions? [3]

# Result:
# Configuration imported automatically
# Ready to use: ops docker prune
```

### Scenario 2: Existing CI/CD Pipeline

```bash
ops cicd detect

# Output:
# ✓ GitHub Actions (.github/workflows/ci.yml)
# ✓ Workflows: ci, deploy-staging, security-scan
# ✓ Docker builds: Yes
# ✓ Deployment: Automated

ops cicd integrate

# Options:
# 1) Use existing (monitoring only)
# 2) Enhance existing (add features)
# 3) Create new

# Choose: 2

# Enhancements offered:
# - Add caching for faster builds
# - Add security scanning
# - Add deployment approval gates
# - Add notification webhooks
```

### Scenario 3: Multi-Service Build

```bash
ops build detect

# Output:
# ✓ Backend: Python/Django
# ✓ Frontend: Node.js/Vue/Vite
# ✓ Voice App: Elixir/Phoenix
# ✓ Desktop: Electron
#
# Build strategies detected:
# ✓ Multi-stage Dockerfiles (3 of 3)
# ✓ BuildKit caching enabled
# ✓ Parallel build possible

ops build integrate

# Configuration:
# Services: backend, frontend, voice-app
# Build order: Parallel (no dependencies)
# Cache: Enabled
# Estimated time: 3-5 minutes
```

## Command Quick Reference

### Docker Module
```bash
ops docker detect       # Detect Docker infrastructure
ops docker integrate    # Configure from detected setup
ops docker analyze      # Show infrastructure analysis
ops docker prune        # Clean old images (retention policy)
ops docker validate     # Lint Dockerfiles
ops docker orphans      # Find unused resources
```

### CI/CD Module
```bash
ops cicd detect         # Detect existing CI/CD
ops cicd integrate      # Use/enhance existing pipelines
ops cicd generate       # Generate new workflows
ops cicd validate       # Validate pipeline configs
ops cicd compare        # Compare environments
```

### Build Module
```bash
ops build detect        # Detect build configuration
ops build integrate     # Use detected build setup
ops build run           # Execute builds
ops build analyze       # Analyze build efficiency
ops build optimize      # Suggest optimizations
```

### Deploy Module
```bash
ops deploy detect       # Detect deployment targets
ops deploy integrate    # Configure from detected setup
ops deploy run          # Execute deployment
ops deploy rollback     # Rollback last deployment
ops deploy health       # Check deployment health
```

## Detection Output Examples

### Full Project Scan
```bash
ops init --detect

╔══════════════════════════════════════════════════════════
║ OpsEngine: Complete Infrastructure Detection
╚══════════════════════════════════════════════════════════

📦 Project: personal-site
🏷️  Version: 0.9.8
🔧 Type: Multi-service Docker application

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🐳 DOCKER INFRASTRUCTURE
├─ Compose files: 3
│  ├─ docker-compose.yml (production)
│  ├─ docker-compose.staging.yml (staging)
│  └─ docker-compose.test.yml (testing)
├─ Services: backend, frontend, voice-app, postgres, redis
├─ Dockerfiles: 3 (all multi-stage)
├─ Images: 12 (erkuysal/personal-site)
├─ Registry: Docker Hub (erkuysal)
└─ Dangling: 3 images (cleanup recommended)

🔨 BUILD CONFIGURATION
├─ Backend: Python/Django
│  └─ Build: Multi-stage (850MB → 450MB)
├─ Frontend: Node.js/Vue/Vite
│  └─ Build: Multi-stage (1.2GB → 85MB)
├─ Voice App: Elixir/Phoenix
│  └─ Build: Multi-stage (1.5GB → 120MB)
├─ Desktop: Electron
│  └─ Build: electron-builder (Windows)
└─ Optimizations: BuildKit caching, layer optimization

🚀 CI/CD PIPELINES
├─ Provider: GitHub Actions
├─ Workflows: 3
│  ├─ ci.yml (test + build on push)
│  ├─ deploy-staging.yml (auto-deploy staging)
│  └─ security-scan.yml (weekly scans)
├─ Docker: Integrated
└─ Secrets: 8 configured

📡 DEPLOYMENT
├─ Production: erkuysal.com
│  ├─ Method: Docker Compose (SSH)
│  └─ SSL: Let's Encrypt (60 days remaining)
├─ Staging: staging.erkuysal.com
│  └─ Method: Docker Compose (SSH)
└─ Scripts: 3 deployment scripts detected

🔒 CERTIFICATES
├─ erkuysal.com (60 days)
├─ api.erkuysal.com (60 days)
├─ voice.erkuysal.com (60 days)
└─ Monitoring: Installed ✓

📝 VERSION MANAGEMENT
├─ Current: 0.9.8
├─ Files tracked: 5
│  ├─ VERSION
│  ├─ frontend/desktop/package.json
│  ├─ frontend/web/src/.../SoundilerryLanding.vue
│  └─ ... (2 more)
└─ Strategy: Semantic versioning

🔧 UTILITY SCRIPTS
└─ 8 scripts → migration available (run 'ops migrate')

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

✅ Infrastructure fully detected and mapped
⚡ Ready to use: ops <module> run
📚 Docs: ops help <module>
```

## Benefits

### Smart Detection
- No manual Docker/CI/CD inventory needed
- Automatically understands your setup
- Detects optimization opportunities

### Seamless Integration  
- Works with existing pipelines
- Enhances rather than replaces
- Preserves your workflow

### DevOps Intelligence
- Analyzes build efficiency
- Suggests optimizations
- Identifies security issues
- Tracks resource usage

### Unified Interface
```bash
# Instead of:
docker images | grep personal-site
docker-compose build backend
./deploy.sh production
./.utilities/image_cleaner.sh

# Use:
ops docker analyze
ops build run backend
ops deploy run production
ops docker prune
```

This is true DevOps infrastructure detection—understanding real Docker setups, CI/CD pipelines, multi-stage builds, and deployment configurations!
