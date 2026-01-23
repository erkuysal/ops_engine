#!/bin/bash
# modules/cicd/handler.sh - CI/CD Workflow Module
# Implements three-phase lifecycle: setup → configure → deploy

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPSENGINE_DIR="$(cd "$MODULE_DIR/../.." && pwd)"

# Load core modules if not already loaded
if [[ -z "${OPSENGINE_CORE_LOADED:-}" ]]; then
    source "$OPSENGINE_DIR/core/utils.sh"
    source "$OPSENGINE_DIR/core/config.sh"
    source "$OPSENGINE_DIR/core/state.sh"
    source "$OPSENGINE_DIR/core/executor.sh"
    source "$OPSENGINE_DIR/core/module_base.sh"
fi

module_register "cicd" "CI/CD Workflow Management" "2.0.0"

# =============================================================================
# CI/CD Detection Storage
# =============================================================================

declare -gA CICD_DETECTED

# =============================================================================
# Phase 0: DETECT - Existing CI/CD Configurations
# =============================================================================

module_detect() {
    log_section "Detecting CI/CD Configurations"
    echo ""
    
    local project_root="${1:-.}"
    local found_any=false
    
    # 1. GitHub Actions
    if [[ -d "$project_root/.github/workflows" ]]; then
        log_info "Scanning GitHub Actions workflows..."
        local workflows=$(find "$project_root/.github/workflows" -name "*.yml" -o -name "*.yaml" 2>/dev/null)
        
        if [[ -n "$workflows" ]]; then
            local workflow_count=$(echo "$workflows" | wc -l)
            CICD_DETECTED["provider"]="github"
            CICD_DETECTED["github_workflow_count"]="$workflow_count"
            
            # Analyze workflows
            while IFS= read -r workflow; do
                local name=$(basename "$workflow")
                local rel_path=$(realpath --relative-to="$project_root" "$workflow")
                
                # Check what it does
                local has_docker=$(grep -c "docker" "$workflow" || echo 0)
                local has_build=$(grep -c "build" "$workflow" || echo 0)
                local has_deploy=$(grep -c "deploy" "$workflow" || echo 0)
                local has_test=$(grep -c "test" "$workflow" || echo 0)
                
                # Detect triggers
                local triggers=$(grep -A 5 "^on:" "$workflow" | grep -E "push|pull_request|schedule|workflow_dispatch" | sed 's/://' | tr '\n' ',' | sed 's/,$//')
                
                CICD_DETECTED["github_${name}_docker"]="$has_docker"
                CICD_DETECTED["github_${name}_triggers"]="$triggers"
                
                log_success "  $name (triggers: $triggers)"
            done <<< "$workflows"
            
            found_any=true
        fi
    fi
    
    # 2. GitLab CI
    if [[ -f "$project_root/.gitlab-ci.yml" ]]; then
        log_info "Found GitLab CI configuration"
        CICD_DETECTED["provider"]="gitlab"
        
        # Analyze stages
        local stages=$(grep -A 10 "^stages:" "$project_root/.gitlab-ci.yml" | grep "^  -" | sed 's/  - //' | tr '\n' ',' | sed 's/,$//')
        CICD_DETECTED["gitlab_stages"]="$stages"
        
        # Check for Docker
        local has_docker=$(grep -c "docker" "$project_root/.gitlab-ci.yml" || echo 0)
        CICD_DETECTED["gitlab_uses_docker"]="$([[ $has_docker -gt 0 ]] && echo "true" || echo "false")"
        
        log_success "GitLab CI (stages: $stages)"
        found_any=true
    fi
    
    # 3. CircleCI
    if [[ -f "$project_root/.circleci/config.yml" ]]; then
        log_info "Found CircleCI configuration"
        CICD_DETECTED["provider"]="circleci"
        
        # Analyze workflows
        local workflows=$(grep -A 5 "workflows:" "$project_root/.circleci/config.yml" | grep "jobs:" -A 10 | grep "^      -" | sed 's/.*- //' | tr '\n' ',' | sed 's/,$//')
        CICD_DETECTED["circleci_workflows"]="$workflows"
        
        log_success "CircleCI (workflows detected)"
        found_any=true
    fi
    
    # 4. Bitbucket Pipelines
    if [[ -f "$project_root/bitbucket-pipelines.yml" ]]; then
        log_info "Found Bitbucket Pipelines"
        CICD_DETECTED["provider"]="bitbucket"
        log_success "Bitbucket Pipelines detected"
        found_any=true
    fi
    
    # 5. Jenkins
    if [[ -f "$project_root/Jenkinsfile" ]]; then
        log_info "Found Jenkinsfile"
        CICD_DETECTED["jenkins"]="true"
        log_success "Jenkins configuration detected"
        found_any=true
    fi
    
    # 6. Detect CI/CD patterns in docker-compose
    if [[ -f "$project_root/docker-compose.yml" ]]; then
        # Check for CI-specific compose files
        local ci_compose=$(find "$project_root" -maxdepth 1 -name "docker-compose.*.yml" | grep -E "ci|test|prod" || true)
        if [[ -n "$ci_compose" ]]; then
            CICD_DETECTED["compose_ci_files"]="$ci_compose"
            log_success "CI-specific compose files detected"
            found_any=true
        fi
    fi
    
    # 7. Detect deployment scripts
    local deploy_scripts=$(find "$project_root" -maxdepth 2 -name "*deploy*" -type f \( -name "*.sh" -o -perm -111 \) 2>/dev/null | head -5)
    if [[ -n "$deploy_scripts" ]]; then
        local script_count=$(echo "$deploy_scripts" | wc -l)
        CICD_DETECTED["deploy_scripts"]="$deploy_scripts"
        CICD_DETECTED["deploy_script_count"]="$script_count"
        log_success "Found $script_count deployment scripts"
        found_any=true
    fi
    
    # 8. Detect secrets/environment setup
    if [[ -f "$project_root/.env.example" ]] || [[ -f "$project_root/.env.template" ]]; then
        CICD_DETECTED["has_env_template"]="true"
        log_success "Environment template found"
        found_any=true
    fi
    
    echo ""
    if [[ "$found_any" == "true" ]]; then
        log_success "CI/CD infrastructure detected"
        return 0
    else
        log_info "No CI/CD configuration found"
        return 1
    fi
}

# =============================================================================
# Phase 0.5: INTEGRATE - Use detected CI/CD
# =============================================================================

module_integrate() {
    log_section "CI/CD Integration"
    echo ""
    
    local provider="${CICD_DETECTED["provider"]}"
    
    if [[ -z "$provider" ]]; then
        log_info "No CI/CD provider detected - will create new"
        return 0
    fi
    
    log_info "Detected provider: $provider"
    echo ""
    
    case "$provider" in
        github)
            log_info "GitHub Actions workflows:"
            local count="${CICD_DETECTED["github_workflow_count"]}"
            for key in "${!CICD_DETECTED[@]}"; do
                if [[ "$key" == github_*_triggers ]]; then
                    local workflow="${key#github_}"
                    workflow="${workflow%_triggers}"
                    local triggers="${CICD_DETECTED[$key]}"
                    echo "  • $workflow (on: $triggers)"
                fi
            done
            ;;
        gitlab)
            log_info "GitLab CI stages: ${CICD_DETECTED["gitlab_stages"]}"
            ;;
        circleci)
            log_info "CircleCI workflows: ${CICD_DETECTED["circleci_workflows"]}"
            ;;
    esac
    
    echo ""
    echo "Options:"
    echo "  1) Use existing CI/CD configuration"
    echo "  2) Enhance existing configuration"
    echo "  3) Create new configuration"
    echo ""
    read -p "Choose [1-3, default: 1]: " choice
    choice=${choice:-1}
    
    case "$choice" in
        1)
            config_set "action" "use"
            config_set "ci_provider" "$provider"
            log_success "Will use existing configuration"
            ;;
        2)
            config_set "action" "enhance"
            config_set "ci_provider" "$provider"
            log_info "Will enhance existing configuration"
            ;;
        3)
            config_set "action" "create"
            log_info "Will create new configuration"
            ;;
    esac
    
    return 0
}

# =============================================================================
# Phase 1: SETUP - Check prerequisites
# =============================================================================

module_setup() {
    step_progress 1 3 "Checking git..."
    check_tool "git" "brew install git" "apt install git" "cicd" || return 1
    
    step_progress 2 3 "Checking GitHub CLI (optional)..."
    if command -v gh &>/dev/null; then
        log_success "GitHub CLI available"
    else
        log_info "GitHub CLI not installed (optional for workflow triggers)"
    fi
    
    step_progress 3 3 "Checking repository..."
    if [[ ! -d ".git" ]]; then
        log_error "Not a git repository"
        return 1
    fi
    
    log_success "CI/CD prerequisites satisfied"
    return 0
}

# =============================================================================
# Phase 2: CONFIGURE - Collect CI/CD settings
# =============================================================================

module_configure() {
    log_info "Configure CI/CD Settings"
    echo ""
    
    # CI Provider
    echo "CI Provider:"
    echo "  1) GitHub Actions"
    echo "  2) GitLab CI"
    echo "  3) Bitbucket Pipelines"
    read -p "Choose [1-3, default: 1]: " ci_choice
    
    local ci_provider="github"
    case "${ci_choice:-1}" in
        2) ci_provider="gitlab" ;;
        3) ci_provider="bitbucket" ;;
        *) ci_provider="github" ;;
    esac
    config_set "ci_provider" "$ci_provider"
    
    # Docker Registry
    echo ""
    echo "Docker Registry:"
    echo "  1) Docker Hub"
    echo "  2) GitHub Container Registry (ghcr.io)"
    echo "  3) Custom"
    read -p "Choose [1-3, default: 1]: " reg_choice
    
    local registry="dockerhub"
    case "${reg_choice:-1}" in
        2) registry="ghcr.io" ;;
        3) 
            registry=$(config_prompt "Custom registry URL" "registry" "")
            ;;
        *) registry="dockerhub" ;;
    esac
    config_set "registry" "$registry"
    
    # Docker username/org
    local docker_user=$(config_prompt "Docker username/organization" "docker_user" "")
    
    # Detect services from docker-compose
    echo ""
    log_step "Detecting services..."
    local services=""
    if [[ -f "docker-compose.yml" ]] || [[ -f "docker-compose.yaml" ]]; then
        local compose_file="docker-compose.yml"
        [[ -f "docker-compose.yaml" ]] && compose_file="docker-compose.yaml"
        services=$(docker compose -f "$compose_file" config --services 2>/dev/null | tr '\n' ',' | sed 's/,$//')
        log_success "Detected: $services"
    else
        services=$(config_prompt "Services (comma-separated)" "services" "backend,frontend")
    fi
    config_set "services" "$services"
    
    # Deploy target
    echo ""
    local deploy_host=$(config_prompt "Deploy server (SSH host)" "deploy_host" "")
    local deploy_user=$(config_prompt "Deploy user" "deploy_user" "${USER:-deploy}")
    local deploy_path=$(config_prompt "Deploy path" "deploy_path" "/srv/app")
    
    # Branches
    echo ""
    local main_branch=$(config_prompt "Main branch" "main_branch" "main")
    local staging_branch=$(config_prompt "Staging branch (optional)" "staging_branch" "")
    
    # Summary
    echo ""
    info_box "CI/CD Configuration" \
        "Provider: $ci_provider\nRegistry: $registry\nServices: $services\nDeploy: $deploy_user@$deploy_host:$deploy_path"
    
    confirm "Proceed with these settings?" "y" || return 1
    return 0
}

# =============================================================================
# Phase 3: DEPLOY - Generate workflow files
# =============================================================================

module_deploy() {
    local ci_provider=$(config_get "ci_provider" "github")
    
    case "$ci_provider" in
        github) generate_github_workflow ;;
        gitlab) generate_gitlab_ci ;;
        bitbucket) generate_bitbucket_pipeline ;;
        *)
            log_error "Unknown CI provider: $ci_provider"
            return 1
            ;;
    esac
    
    return 0
}

# =============================================================================
# GitHub Actions Workflow Generator
# =============================================================================

generate_github_workflow() {
    local registry=$(config_get "registry" "dockerhub")
    local docker_user=$(config_get "docker_user" "")
    local services=$(config_get "services" "")
    local deploy_host=$(config_get "deploy_host" "")
    local deploy_user=$(config_get "deploy_user" "deploy")
    local deploy_path=$(config_get "deploy_path" "/srv/app")
    local main_branch=$(config_get "main_branch" "main")
    
    # Create workflow directory
    local workflow_dir=".github/workflows"
    mkdir -p "$workflow_dir"
    
    log_step "Generating GitHub Actions workflow..."
    
    # Build registry prefix
    local image_prefix=""
    case "$registry" in
        dockerhub) image_prefix="${docker_user}/" ;;
        ghcr.io) image_prefix="ghcr.io/\${{ github.repository_owner }}/" ;;
        *) image_prefix="${registry}/${docker_user}/" ;;
    esac
    
    # Parse services
    IFS=',' read -ra svc_array <<< "$services"
    
    cat > "$workflow_dir/ci-cd.yml" << 'WORKFLOW_HEADER'
# CI/CD Pipeline
# Generated by OpsEngine

name: CI/CD

on:
  push:
    branches: [MAIN_BRANCH]
  pull_request:
    branches: [MAIN_BRANCH]
  workflow_dispatch:
    inputs:
      services:
        description: 'Services to deploy (comma-separated)'
        required: false
        default: 'all'
      run_deploy:
        description: 'Run deployment'
        type: boolean
        default: true

env:
  REGISTRY: REGISTRY_VALUE
  IMAGE_PREFIX: IMAGE_PREFIX_VALUE

jobs:
  # ===========================================
  # Build Jobs
  # ===========================================
WORKFLOW_HEADER

    # Replace placeholders
    sed -i '' "s/MAIN_BRANCH/$main_branch/g" "$workflow_dir/ci-cd.yml"
    sed -i '' "s|REGISTRY_VALUE|$registry|g" "$workflow_dir/ci-cd.yml"
    sed -i '' "s|IMAGE_PREFIX_VALUE|$image_prefix|g" "$workflow_dir/ci-cd.yml"
    
    # Add build jobs for each service
    for svc in "${svc_array[@]}"; do
        svc=$(echo "$svc" | xargs)  # trim whitespace
        cat >> "$workflow_dir/ci-cd.yml" << BUILDJOB

  build-$svc:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3
      
      - name: Login to Registry
        uses: docker/login-action@v3
        with:
          registry: \${{ env.REGISTRY }}
          username: \${{ secrets.DOCKER_USERNAME }}
          password: \${{ secrets.DOCKER_PASSWORD }}
      
      - name: Build and push $svc
        uses: docker/build-push-action@v5
        with:
          context: ./$svc
          push: \${{ github.event_name != 'pull_request' }}
          tags: \${{ env.IMAGE_PREFIX }}$svc:latest,\${{ env.IMAGE_PREFIX }}$svc:\${{ github.sha }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
BUILDJOB
    done
    
    # Add deploy job
    if [[ -n "$deploy_host" ]]; then
        cat >> "$workflow_dir/ci-cd.yml" << DEPLOYJOB

  # ===========================================
  # Deploy Job
  # ===========================================
  deploy:
    runs-on: ubuntu-latest
    needs: [$(echo "${svc_array[@]}" | sed 's/ /, /g' | sed 's/\([^,]*\)/build-\1/g')]
    if: github.ref == 'refs/heads/$main_branch' && (github.event_name == 'push' || github.event.inputs.run_deploy == 'true')
    
    steps:
      - uses: actions/checkout@v4
      
      - name: Deploy to Server
        uses: appleboy/ssh-action@v1.0.0
        with:
          host: \${{ secrets.DEPLOY_HOST }}
          username: \${{ secrets.DEPLOY_USER }}
          key: \${{ secrets.DEPLOY_KEY }}
          script: |
            cd $deploy_path
            docker compose pull
            docker compose up -d --remove-orphans
            docker system prune -f
DEPLOYJOB
    fi
    
    log_success "Created: $workflow_dir/ci-cd.yml"
    
    # Generate secrets documentation
    generate_secrets_doc "$workflow_dir"
    
    success_box "GitHub Actions Workflow Generated!" \
        "File: $workflow_dir/ci-cd.yml\nSecrets: $workflow_dir/SECRETS.md\n\nNext: Add secrets to GitHub repo settings"
    
    return 0
}

generate_secrets_doc() {
    local workflow_dir="$1"
    local registry=$(config_get "registry" "dockerhub")
    
    cat > "$workflow_dir/SECRETS.md" << SECRETS
# Required GitHub Secrets

Add these secrets to your repository settings:
**Settings → Secrets and variables → Actions → New repository secret**

## Docker Registry
SECRETS

    case "$registry" in
        dockerhub)
            cat >> "$workflow_dir/SECRETS.md" << DOCKER_SECRETS

| Secret | Description |
|--------|-------------|
| \`DOCKER_USERNAME\` | Docker Hub username |
| \`DOCKER_PASSWORD\` | Docker Hub access token (not password) |

Get your token at: https://hub.docker.com/settings/security
DOCKER_SECRETS
            ;;
        ghcr.io)
            cat >> "$workflow_dir/SECRETS.md" << GHCR_SECRETS

| Secret | Description |
|--------|-------------|
| \`DOCKER_USERNAME\` | GitHub username |
| \`DOCKER_PASSWORD\` | GitHub Personal Access Token (PAT) with \`write:packages\` scope |

Create PAT at: https://github.com/settings/tokens
GHCR_SECRETS
            ;;
    esac
    
    local deploy_host=$(config_get "deploy_host" "")
    if [[ -n "$deploy_host" ]]; then
        cat >> "$workflow_dir/SECRETS.md" << DEPLOY_SECRETS

## Deployment

| Secret | Description |
|--------|-------------|
| \`DEPLOY_HOST\` | Server IP or hostname (e.g., \`your-server.com\`) |
| \`DEPLOY_USER\` | SSH username for deployment |
| \`DEPLOY_KEY\` | SSH private key (entire contents, including BEGIN/END lines) |

### Generate Deploy Key
\`\`\`bash
ssh-keygen -t ed25519 -C "github-deploy" -f deploy_key
# Add deploy_key.pub to server's ~/.ssh/authorized_keys
# Copy deploy_key contents to DEPLOY_KEY secret
\`\`\`
DEPLOY_SECRETS
    fi
    
    log_success "Created: $workflow_dir/SECRETS.md"
}

generate_gitlab_ci() {
    log_step "Generating GitLab CI configuration..."
    
    local services=$(config_get "services" "")
    local deploy_host=$(config_get "deploy_host" "")
    local deploy_path=$(config_get "deploy_path" "/srv/app")
    
    cat > ".gitlab-ci.yml" << GITLAB
# GitLab CI/CD Pipeline
# Generated by OpsEngine

stages:
  - build
  - deploy

variables:
  DOCKER_TLS_CERTDIR: "/certs"

GITLAB

    IFS=',' read -ra svc_array <<< "$services"
    
    for svc in "${svc_array[@]}"; do
        svc=$(echo "$svc" | xargs)
        cat >> ".gitlab-ci.yml" << GITLAB_BUILD

build-$svc:
  stage: build
  image: docker:24.0.5
  services:
    - docker:24.0.5-dind
  script:
    - docker build -t \$CI_REGISTRY_IMAGE/$svc:\$CI_COMMIT_SHA ./$svc
    - docker push \$CI_REGISTRY_IMAGE/$svc:\$CI_COMMIT_SHA
  only:
    - main
GITLAB_BUILD
    done
    
    if [[ -n "$deploy_host" ]]; then
        cat >> ".gitlab-ci.yml" << GITLAB_DEPLOY

deploy:
  stage: deploy
  image: alpine:latest
  before_script:
    - apk add --no-cache openssh-client
    - eval \$(ssh-agent -s)
    - echo "\$SSH_PRIVATE_KEY" | ssh-add -
  script:
    - ssh -o StrictHostKeyChecking=no \$DEPLOY_USER@\$DEPLOY_HOST "cd $deploy_path && docker compose pull && docker compose up -d"
  only:
    - main
GITLAB_DEPLOY
    fi
    
    log_success "Created: .gitlab-ci.yml"
    success_box "GitLab CI Generated!" "File: .gitlab-ci.yml"
    return 0
}

generate_bitbucket_pipeline() {
    log_step "Generating Bitbucket Pipelines configuration..."
    
    local services=$(config_get "services" "")
    
    cat > "bitbucket-pipelines.yml" << BITBUCKET
# Bitbucket Pipelines
# Generated by OpsEngine

image: docker:24.0.5

definitions:
  services:
    docker:
      memory: 2048

pipelines:
  default:
    - step:
        name: Build
        services:
          - docker
        script:
          - docker compose build
  
  branches:
    main:
      - step:
          name: Build and Push
          services:
            - docker
          script:
            - docker compose build
            - docker compose push
BITBUCKET
    
    log_success "Created: bitbucket-pipelines.yml"
    success_box "Bitbucket Pipeline Generated!" "File: bitbucket-pipelines.yml"
    return 0
}

# =============================================================================
# Module Help
# =============================================================================

module_help() {
    cat <<EOF
Module: cicd (CI/CD Workflow Management)
=========================================

Generate and manage CI/CD workflow configurations.

Usage:
  ops cicd setup       Check git and prerequisites
  ops cicd configure   Configure CI/CD settings
  ops cicd deploy      Generate workflow files
  ops cicd run         Run all phases
  ops cicd status      Show current configuration

Supported Providers:
  ✓ GitHub Actions
  ✓ GitLab CI
  ✓ Bitbucket Pipelines

Generated Files:
  GitHub:    .github/workflows/ci-cd.yml
  GitLab:    .gitlab-ci.yml
  Bitbucket: bitbucket-pipelines.yml

Examples:
  ops cicd run                    # Full setup wizard
  ops cicd configure              # Just configure
  ops cicd deploy                 # Generate files

EOF
}

# =============================================================================
# Entry Point
# =============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    module_main "$@"
fi
