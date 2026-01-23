#!/bin/bash
# modules/network/handler.sh - Docker Network Module
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

module_register "network" "Docker Network Management" "2.0.0"

# =============================================================================
# Phase 1: SETUP
# =============================================================================

module_setup() {
    step_progress 1 1 "Checking Docker..."
    check_tool "docker" "brew install docker" "curl -fsSL https://get.docker.com | sh" "network" || return 1
    
    log_success "Network prerequisites satisfied"
    return 0
}

# =============================================================================
# Phase 2: CONFIGURE
# =============================================================================

module_configure() {
    log_info "Configure Network Settings"
    
    echo ""
    echo "Current Docker networks:"
    docker network ls --format "table {{.Name}}\t{{.Driver}}\t{{.Scope}}"
    echo ""
    
    echo "Action:"
    echo "  1) Create new network"
    echo "  2) Remove network"
    echo "  3) Inspect network"
    echo "  4) Connect container to network"
    
    read -p "Choose [1-4]: " action
    config_set "action" "$action"
    
    case "$action" in
        1)
            local name=$(config_prompt "Network name" "network_name" "")
            local driver=$(config_prompt "Driver (bridge/overlay/host)" "driver" "bridge")
            config_set "network_name" "$name"
            config_set "driver" "$driver"
            ;;
        2|3)
            local name=$(config_prompt "Network name" "network_name" "")
            config_set "network_name" "$name"
            ;;
        4)
            local name=$(config_prompt "Network name" "network_name" "")
            local container=$(config_prompt "Container name/ID" "container" "")
            config_set "network_name" "$name"
            config_set "container" "$container"
            ;;
    esac
    
    return 0
}

# =============================================================================
# Phase 3: DEPLOY
# =============================================================================

module_deploy() {
    local action=$(config_get "action" "1")
    local network_name=$(config_get "network_name")
    
    case "$action" in
        1)
            local driver=$(config_get "driver" "bridge")
            log_step "Creating network: $network_name ($driver)"
            docker network create --driver "$driver" "$network_name" && \
                success_box "Network Created!" "Name: $network_name\nDriver: $driver"
            ;;
        2)
            log_step "Removing network: $network_name"
            docker network rm "$network_name" && \
                log_success "Network removed: $network_name"
            ;;
        3)
            docker network inspect "$network_name"
            ;;
        4)
            local container=$(config_get "container")
            log_step "Connecting $container to $network_name"
            docker network connect "$network_name" "$container" && \
                log_success "Connected $container to $network_name"
            ;;
    esac
    
    return 0
}

module_help() {
    cat <<EOF
Module: network (Docker Network Management)
============================================
Create, remove, and manage Docker networks.

Usage:
  ops network setup       Check Docker
  ops network configure   Choose action
  ops network deploy      Execute action
  ops network run         Run all phases
EOF
}

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && module_main "$@"
