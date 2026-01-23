#!/bin/bash
# modules/deployer/handler.sh - Service Deployment Module
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

module_register "deploy" "Service Deployment" "2.0.0"

# =============================================================================
# Phase 1: SETUP
# =============================================================================

module_setup() {
    step_progress 1 2 "Checking Docker..."
    check_tool "docker" "brew install docker" "curl -fsSL https://get.docker.com | sh" "deploy" || return 1
    
    step_progress 2 2 "Checking Docker daemon..."
    check_service "docker" "sudo systemctl start docker" "open -a Docker" "deploy" || return 1
    
    log_success "Deploy prerequisites satisfied"
    return 0
}

# =============================================================================
# Phase 2: CONFIGURE
# =============================================================================

module_configure() {
    log_info "Configure Deployment Settings"
    
    local compose_file="docker-compose.yml"
    [[ -f "docker-compose.yaml" ]] && compose_file="docker-compose.yaml"
    
    if [[ ! -f "$compose_file" ]]; then
        log_error "No docker-compose file found"
        return 1
    fi
    
    config_set "compose_file" "$compose_file"
    
    local services=$(docker compose -f "$compose_file" config --services 2>/dev/null | tr '\n' ' ')
    log_info "Available services: $services"
    
    local selected=$(config_prompt "Services to deploy (comma-sep or 'all')" "services" "all")
    [[ "$selected" == "all" ]] && config_set "services" "$services" || config_set "services" "$selected"
    
    echo ""
    echo "Deploy mode:"
    echo "  1) Hot-swap (replace one at a time, zero downtime)"
    echo "  2) Full restart (stop all, then start)"
    local mode="hot-swap"
    read -p "Choose [1-2, default: 1]: " mode_choice
    [[ "$mode_choice" == "2" ]] && mode="full"
    config_set "mode" "$mode"
    
    config_set "pull" "$(confirm 'Pull latest images first?' 'y' && echo true || echo false)"
    
    confirm "Proceed?" "y" || return 1
    return 0
}

# =============================================================================
# Phase 3: DEPLOY
# =============================================================================

module_deploy() {
    local compose_file=$(config_get "compose_file" "docker-compose.yml")
    local services=$(config_get "services")
    local mode=$(config_get "mode" "hot-swap")
    local pull=$(config_get "pull" "true")
    
    log_info "Deploying services ($mode mode)..."
    
    if [[ "$mode" == "full" ]]; then
        log_step "Stopping all services..."
        docker compose -f "$compose_file" down --remove-orphans || true
    fi
    
    for svc in $services; do
        if [[ "$mode" == "hot-swap" ]]; then
            log_step "Hot-swapping: $svc"
            docker compose -f "$compose_file" stop "$svc" 2>/dev/null || true
            docker compose -f "$compose_file" rm -f "$svc" 2>/dev/null || true
        fi
        
        [[ "$pull" == "true" ]] && docker compose -f "$compose_file" pull "$svc"
        
        log_step "Starting: $svc"
        docker compose -f "$compose_file" up -d "$svc"
        
        # Wait for health
        log_info "Waiting for $svc to be healthy..."
        local attempts=30
        for ((i=1; i<=attempts; i++)); do
            if docker compose -f "$compose_file" ps "$svc" 2>/dev/null | grep -q healthy; then
                log_success "$svc is healthy"
                break
            fi
            sleep 2
        done
    done
    
    success_box "Deployment Complete!" "Services: $services"
    docker compose -f "$compose_file" ps
    return 0
}

module_help() {
    cat <<EOF
Module: deploy (Service Deployment)
====================================
Deploy services with hot-swap or full restart.

Usage:
  ops deploy setup       Check Docker
  ops deploy configure   Select services and mode
  ops deploy deploy      Execute deployment
  ops deploy run         Run all phases

Modes:
  hot-swap    Replace services one at a time
  full        Stop all, then restart
EOF
}

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && module_main "$@"
