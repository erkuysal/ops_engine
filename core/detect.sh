#!/bin/bash
# core/detect.sh - Auto-detect project configuration

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# Detect project type based on files present
detect_project_type() {
    local project_root="${1:-.}"
    
    # Check for docker-compose
    if [ -f "$project_root/docker-compose.yml" ] || [ -f "$project_root/docker-compose.yaml" ]; then
        echo "docker-compose"
        return 0
    fi
    
    # Check for kubernetes
    if [ -d "$project_root/k8s" ] || [ -d "$project_root/kubernetes" ]; then
        echo "kubernetes"
        return 0
    fi
    
    # Check for common frameworks
    if [ -f "$project_root/package.json" ]; then
        echo "node"
        return 0
    fi
    
    if [ -f "$project_root/requirements.txt" ] || [ -f "$project_root/manage.py" ]; then
        echo "python"
        return 0
    fi
    
    if [ -f "$project_root/go.mod" ]; then
        echo "go"
        return 0
    fi
    
    if [ -f "$project_root/pom.xml" ]; then
        echo "java"
        return 0
    fi
    
    # Default
    echo "generic"
}

# Detect services from docker-compose
detect_docker_services() {
    local compose_file="${1:-docker-compose.yml}"
    
    if [ ! -f "$compose_file" ]; then
        echo ""
        return 1
    fi
    
    # Parse services (handles both yml and yaml formats)
    parse_compose_services "$compose_file"
}

# Detect backend framework
detect_backend_type() {
    local project_root="${1:-.}"
    
    # Django
    if [ -f "$project_root/manage.py" ]; then
        echo "django"
        return 0
    fi
    
    # Flask
    if grep -q "flask" "$project_root/requirements.txt" 2>/dev/null; then
        echo "flask"
        return 0
    fi
    
    # FastAPI
    if grep -q "fastapi" "$project_root/requirements.txt" 2>/dev/null; then
        echo "fastapi"
        return 0
    fi
    
    # Express/Node
    if [ -f "$project_root/package.json" ]; then
        if grep -q "express" "$project_root/package.json" 2>/dev/null; then
            echo "express"
            return 0
        fi
    fi
    
    # Go
    if [ -f "$project_root/go.mod" ]; then
        echo "go"
        return 0
    fi
    
    echo "unknown"
}

# Detect frontend framework
detect_frontend_type() {
    local project_root="${1:-.}"
    
    if [ ! -f "$project_root/package.json" ]; then
        echo "unknown"
        return 1
    fi
    
    # React
    if grep -q "\"react\"" "$project_root/package.json"; then
        # Check if it's Next.js
        if grep -q "\"next\"" "$project_root/package.json"; then
            echo "nextjs"
        else
            echo "react"
        fi
        return 0
    fi
    
    # Vue
    if grep -q "\"vue\"" "$project_root/package.json"; then
        # Check if it's Nuxt
        if grep -q "\"nuxt\"" "$project_root/package.json"; then
            echo "nuxt"
        else
            echo "vue"
        fi
        return 0
    fi
    
    # Angular
    if grep -q "\"@angular/core\"" "$project_root/package.json"; then
        echo "angular"
        return 0
    fi
    
    # Svelte
    if grep -q "\"svelte\"" "$project_root/package.json"; then
        echo "svelte"
        return 0
    fi
    
    echo "unknown"
}

# Detect project name from various sources
detect_project_name() {
    local project_root="${1:-.}"
    
    # Try package.json
    if [ -f "$project_root/package.json" ]; then
        local name=$(grep -o '"name"[[:space:]]*:[[:space:]]*"[^"]*"' "$project_root/package.json" | head -1 | sed 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
        if [ -n "$name" ] && [ "$name" != "null" ]; then
            echo "$name"
            return 0
        fi
    fi
    
    # Try docker-compose.yml project name
    if [ -f "$project_root/docker-compose.yml" ]; then
        local name=$(grep "^name:" "$project_root/docker-compose.yml" 2>/dev/null | head -1 | sed 's/name:[[:space:]]*\(.*\)/\1/' | tr -d '"' | tr -d "'")
        if [ -n "$name" ]; then
            echo "$name"
            return 0
        fi
    fi
    
    # Use directory name as fallback
    basename "$(realpath "$project_root")" | tr '[:upper:]' '[:lower:]' | tr ' ' '-'
}

# Detect version from various sources
detect_version() {
    local project_root="${1:-.}"
    
    # Try VERSION file
    if [ -f "$project_root/VERSION" ]; then
        cat "$project_root/VERSION" | tr -d '\n' | tr -d '\r'
        return 0
    fi
    
    # Try package.json
    if [ -f "$project_root/package.json" ]; then
        local version=$(grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "$project_root/package.json" | head -1 | sed 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
        if [ -n "$version" ] && [ "$version" != "null" ]; then
            echo "$version"
            return 0
        fi
    fi
    
    # Default
    echo "0.1.0"
}

# Detect paths
detect_paths() {
    local project_root="${1:-.}"
    
    # Common frontend paths
    if [ -d "$project_root/frontend" ]; then
        echo "FRONTEND:frontend"
    elif [ -d "$project_root/client" ]; then
        echo "FRONTEND:client"
    elif [ -d "$project_root/web" ]; then
        echo "FRONTEND:web"
    elif [ -d "$project_root/ui" ]; then
        echo "FRONTEND:ui"
    fi
    
    # Common backend paths
    if [ -d "$project_root/backend" ]; then
        echo "BACKEND:backend"
    elif [ -d "$project_root/server" ]; then
        echo "BACKEND:server"
    elif [ -d "$project_root/api" ]; then
        echo "BACKEND:api"
    fi
    
    # Desktop app
    if [ -d "$project_root/desktop" ]; then
        echo "DESKTOP:desktop"
    elif [ -d "$project_root/frontend/desktop" ]; then
        echo "DESKTOP:frontend/desktop"
    fi
}

# Detect domain/IP from existing configs
detect_deployment_info() {
    local project_root="${1:-.}"
    
    # Check .env files
    for env_file in "$project_root/.env" "$project_root/backend/.env" "$project_root/.env.production"; do
        if [ -f "$env_file" ]; then
            # Domain
            local domain=$(grep "^DOMAIN=" "$env_file" 2>/dev/null | cut -d'=' -f2-)
            if [ -n "$domain" ]; then
                echo "DOMAIN:$domain"
            fi
            
            # Host
            local host=$(grep "^HOST=" "$env_file" 2>/dev/null | cut -d'=' -f2-)
            if [ -n "$host" ]; then
                echo "HOST:$host"
            fi
        fi
    done
}

# Detect Docker registry
detect_docker_registry() {
    local project_root="${1:-.}"
    
    # Check docker-compose.yml for image references
    if [ -f "$project_root/docker-compose.yml" ]; then
        if grep -q "ghcr.io" "$project_root/docker-compose.yml"; then
            echo "ghcr.io"
            return 0
        fi
        
        if grep -q "registry.gitlab.com" "$project_root/docker-compose.yml"; then
            echo "gitlab"
            return 0
        fi
    fi
    
    # Default to Docker Hub
    echo "dockerhub"
}

# Generate full configuration based on detection
generate_detected_config() {
    local project_root="${1:-.}"
    
    log_step "Detecting project configuration..."
    
    local project_name=$(detect_project_name "$project_root")
    local project_type=$(detect_project_type "$project_root")
    local project_version=$(detect_version "$project_root")
    local services=$(detect_docker_services "$project_root/docker-compose.yml")
    local registry=$(detect_docker_registry "$project_root")
    
    log_info "Project Name: $project_name"
    log_info "Project Type: $project_type"
    log_info "Version: $project_version"
    
    if [ -n "$services" ]; then
        log_info "Services: $services"
    fi
    
    # Detect paths
    local frontend_path="frontend"
    local backend_path="backend"
    local desktop_path="frontend/desktop"
    
    while IFS=: read -r type path; do
        case "$type" in
            FRONTEND) frontend_path="$path" ;;
            BACKEND) backend_path="$path" ;;
            DESKTOP) desktop_path="$path" ;;
        esac
    done < <(detect_paths "$project_root")
    
    # Generate config content
    cat <<EOF
# OpsEngine Configuration
# Auto-generated on $(date)

# Project Information
PROJECT_NAME="$project_name"
PROJECT_TYPE="$project_type"
PROJECT_VERSION="$project_version"

# Project Paths
PROJECT_ROOT="."
PROJECT_FRONTEND_PATH="$frontend_path"
PROJECT_BACKEND_PATH="$backend_path"
PROJECT_DESKTOP_PATH="$desktop_path"

# Services
PROJECT_SERVICES="$services"

# Docker Configuration
DOCKER_REGISTRY="$registry"
DOCKER_COMPOSE_FILE="docker-compose.yml"

# Deployment
DEPLOY_DOMAIN=""
DEPLOY_IP=""
DEPLOY_USER=""
DEPLOY_HOST=""

# Build Settings
BUILD_NO_CACHE="false"
BUILD_PUSH="true"

# Updates
UPDATES_APP_NAME="$project_name"
UPDATES_CHANNEL="stable"
UPDATES_HOST=""

# Mark as loaded
OPSENGINE_LOADED="true"
EOF
}

# Interactive detection with user confirmation
interactive_detect() {
    local project_root="${1:-.}"
    
    show_opsengine_banner
    echo "Detecting project configuration..."
    echo ""
    
    # Detect and confirm each setting
    local project_name=$(detect_project_name "$project_root")
    read_with_default "Project Name" "$project_name" project_name
    
    local project_type=$(detect_project_type "$project_root")
    read_with_default "Project Type" "$project_type" project_type
    
    local project_version=$(detect_version "$project_root")
    read_with_default "Version" "$project_version" project_version
    
    local services=$(detect_docker_services "$project_root/docker-compose.yml")
    if [ -n "$services" ]; then
        read_with_default "Services (comma-separated)" "$services" services
    else
        read_with_default "Services (comma-separated)" "backend,frontend" services
    fi
    
    # Generate and return values
    echo "PROJECT_NAME=$project_name"
    echo "PROJECT_TYPE=$project_type"
    echo "PROJECT_VERSION=$project_version"
    echo "PROJECT_SERVICES=$services"
}

# Export functions
export -f detect_project_type detect_docker_services detect_backend_type detect_frontend_type
export -f detect_project_name detect_version detect_paths detect_deployment_info detect_docker_registry
export -f generate_detected_config interactive_detect
