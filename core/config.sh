#!/bin/bash
# core/config.sh - Configuration management for OpsEngine

# Find the OpsEngine root directory
OPSENGINE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Default config file locations (in order of precedence)
PROJECT_CONFIG="${OPSENGINE_PROJECT_CONFIG:-}"
if [ -z "$PROJECT_CONFIG" ]; then
    # Look in current directory first, then parent, then OpsEngine utility dir
    if [ -f "./opsengine.conf" ]; then
        PROJECT_CONFIG="./opsengine.conf"
    elif [ -f "../opsengine.conf" ]; then
        PROJECT_CONFIG="../opsengine.conf"
    elif [ -f "$OPSENGINE_ROOT/opsengine.conf" ]; then
        PROJECT_CONFIG="$OPSENGINE_ROOT/opsengine.conf"
    else
        PROJECT_CONFIG="./opsengine.conf"  # Default for creation
    fi
fi

# Load configuration from file
load_config() {
    if [ ! -f "$PROJECT_CONFIG" ]; then
        return 1
    fi
    
    # Source the config file
    source "$PROJECT_CONFIG"
    return 0
}

# Get a config value with optional default
get_config() {
    local key="$1"
    local default="${2:-}"
    
    # Try to load config if not already loaded
    if [ -z "${OPSENGINE_LOADED:-}" ]; then
        load_config || true
    fi
    
    # Get value from environment variable (PROJECT_NAME format)
    local value="${!key}"
    
    # Return value or default
    if [ -n "$value" ]; then
        echo "$value"
    else
        echo "$default"
    fi
}

# Set a config value (updates file)
set_config() {
    local key="$1"
    local value="$2"
    
    if [ -z "$key" ]; then
        return 1
    fi
    
    # Ensure config file exists
    touch "$PROJECT_CONFIG"
    
    # Escape special characters for sed
    local escaped_value=$(echo "$value" | sed 's/[\/&]/\\&/g')
    
    if grep -q "^${key}=" "$PROJECT_CONFIG" 2>/dev/null; then
        # Update existing value
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' "s|^${key}=.*|${key}=\"${escaped_value}\"|" "$PROJECT_CONFIG"
        else
            sed -i "s|^${key}=.*|${key}=\"${escaped_value}\"|" "$PROJECT_CONFIG"
        fi
    else
        # Append new value
        echo "${key}=\"${value}\"" >> "$PROJECT_CONFIG"
    fi
}

# Get project root (where opsengine.conf is located)
get_project_root() {
    if [ -f "$PROJECT_CONFIG" ]; then
        dirname "$(realpath "$PROJECT_CONFIG")"
    else
        pwd
    fi
}

# Get configured services as an array
get_services() {
    local services_str=$(get_config "PROJECT_SERVICES" "")
    if [ -n "$services_str" ]; then
        echo "$services_str" | tr ',' ' '
    fi
}

# Check if a service is configured
has_service() {
    local service="$1"
    local services=$(get_services)
    
    for svc in $services; do
        if [ "$svc" = "$service" ]; then
            return 0
        fi
    done
    return 1
}

# Get service-specific config
get_service_config() {
    local service="$1"
    local key="$2"
    local default="${3:-}"
    
    # SERVICE_BACKEND_TYPE, SERVICE_FRONTEND_PORT, etc.
    local config_key="SERVICE_${service^^}_${key^^}"
    get_config "$config_key" "$default"
}

# Validate configuration
validate_config() {
    local errors=0
    
    # Check required fields
    if [ -z "$(get_config 'PROJECT_NAME')" ]; then
        echo "Error: PROJECT_NAME is not configured" >&2
        errors=$((errors + 1))
    fi
    
    if [ -z "$(get_config 'PROJECT_TYPE')" ]; then
        echo "Error: PROJECT_TYPE is not configured" >&2
        errors=$((errors + 1))
    fi
    
    return $errors
}

# Display current configuration
show_config() {
    if [ ! -f "$PROJECT_CONFIG" ]; then
        echo "No configuration file found at: $PROJECT_CONFIG"
        return 1
    fi
    
    echo "Configuration file: $PROJECT_CONFIG"
    echo "================================"
    cat "$PROJECT_CONFIG"
    echo "================================"
}

# Initialize configuration with defaults
init_config() {
    local project_name="${1:-myproject}"
    local project_type="${2:-generic}"
    
    # Create config file
    cat > "$PROJECT_CONFIG" <<EOF
# OpsEngine Configuration
# Generated on $(date)

# Project Info
PROJECT_NAME="$project_name"
PROJECT_TYPE="$project_type"
PROJECT_VERSION="0.1.0"

# Paths (relative to project root)
PROJECT_ROOT="."
PROJECT_FRONTEND_PATH="frontend"
PROJECT_BACKEND_PATH="backend"

# Services (comma-separated)
PROJECT_SERVICES=""

# Docker Configuration
DOCKER_REGISTRY=""
DOCKER_COMPOSE_FILE="docker-compose.yml"

# Deployment
DEPLOY_DOMAIN=""
DEPLOY_IP=""
DEPLOY_USER=""
DEPLOY_HOST=""

# Build Settings
BUILD_NO_CACHE="false"
BUILD_PUSH="true"

# Marks config as loaded
OPSENGINE_LOADED="true"
EOF
    
    echo "Created configuration file: $PROJECT_CONFIG"
}

# Export functions for use in other scripts
export -f load_config get_config set_config get_project_root get_services has_service get_service_config validate_config show_config init_config
