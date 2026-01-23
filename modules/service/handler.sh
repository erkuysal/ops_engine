#!/bin/bash
# modules/service/handler.sh - Service Lifecycle Module
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

module_register "service" "Service Lifecycle Management" "2.0.0"

# =============================================================================
# Phase 1: SETUP
# =============================================================================

module_setup() {
    step_progress 1 2 "Checking Docker..."
    check_tool "docker" "brew install docker" "curl -fsSL https://get.docker.com | sh" "service" || return 1
    
    step_progress 2 2 "Checking Docker daemon..."
    check_service "docker" "sudo systemctl start docker" "open -a Docker" "service" || return 1
    
    log_success "Service prerequisites satisfied"
    return 0
}

# =============================================================================
# Phase 2: CONFIGURE
# =============================================================================

module_configure() {
    log_info "Configure Service Action"
    
    local compose_file="docker-compose.yml"
    [[ -f "docker-compose.yaml" ]] && compose_file="docker-compose.yaml"
    
    if [[ ! -f "$compose_file" ]]; then
        log_error "No docker-compose file found"
        return 1
    fi
    config_set "compose_file" "$compose_file"
    
    echo ""
    echo "Current services:"
    docker compose -f "$compose_file" ps 2>/dev/null || echo "  (none running)"
    echo ""
    
    echo "Action:"
    echo "  1) Start services"
    echo "  2) Stop services"
    echo "  3) Restart services"
    echo "  4) View logs"
    echo "  5) Scale service"
    echo "  6) Execute command in container"
    
    read -p "Choose [1-6]: " action
    config_set "action" "$action"
    
    local services=$(docker compose -f "$compose_file" config --services 2>/dev/null | tr '\n' ' ')
    
    case "$action" in
        1|2|3)
            local selected=$(config_prompt "Services (comma-sep or 'all')" "services" "all")
            [[ "$selected" == "all" ]] && config_set "services" "$services" || config_set "services" "$selected"
            ;;
        4)
            local svc=$(config_prompt "Service to view logs" "log_service" "")
            config_set "log_service" "$svc"
            local follow="false"
            confirm "Follow logs?" "y" && follow="true"
            config_set "follow" "$follow"
            ;;
        5)
            local svc=$(config_prompt "Service to scale" "scale_service" "")
            local count=$(config_prompt "Number of replicas" "replicas" "2")
            config_set "scale_service" "$svc"
            config_set "replicas" "$count"
            ;;
        6)
            local svc=$(config_prompt "Service" "exec_service" "")
            local cmd=$(config_prompt "Command" "exec_cmd" "/bin/sh")
            config_set "exec_service" "$svc"
            config_set "exec_cmd" "$cmd"
            ;;
    esac
    
    return 0
}

# =============================================================================
# Phase 3: DEPLOY
# =============================================================================

module_deploy() {
    local compose_file=$(config_get "compose_file" "docker-compose.yml")
    local action=$(config_get "action" "1")
    
    case "$action" in
        1) # Start
            local services=$(config_get "services")
            log_step "Starting services: $services"
            for svc in $services; do
                docker compose -f "$compose_file" up -d "$svc"
                log_success "Started: $svc"
            done
            ;;
        2) # Stop
            local services=$(config_get "services")
            log_step "Stopping services: $services"
            for svc in $services; do
                docker compose -f "$compose_file" stop "$svc"
                log_success "Stopped: $svc"
            done
            ;;
        3) # Restart
            local services=$(config_get "services")
            log_step "Restarting services: $services"
            for svc in $services; do
                docker compose -f "$compose_file" restart "$svc"
                log_success "Restarted: $svc"
            done
            ;;
        4) # Logs
            local svc=$(config_get "log_service")
            local follow=$(config_get "follow" "false")
            local args=""
            [[ "$follow" == "true" ]] && args="-f"
            docker compose -f "$compose_file" logs $args "$svc"
            ;;
        5) # Scale
            local svc=$(config_get "scale_service")
            local count=$(config_get "replicas" "2")
            log_step "Scaling $svc to $count replicas"
            docker compose -f "$compose_file" up -d --scale "$svc=$count" "$svc"
            log_success "Scaled $svc to $count"
            ;;
        6) # Exec
            local svc=$(config_get "exec_service")
            local cmd=$(config_get "exec_cmd" "/bin/sh")
            log_info "Executing in $svc: $cmd"
            docker compose -f "$compose_file" exec "$svc" $cmd
            ;;
    esac
    
    echo ""
    docker compose -f "$compose_file" ps
    return 0
}

module_help() {
    cat <<EOF
Module: service (Service Lifecycle)
====================================
Manage Docker Compose service lifecycle.

Usage:
  ops service setup       Check Docker
  ops service configure   Choose action
  ops service deploy      Execute action
  ops service run         Run all phases

Actions:
  start     Start services
  stop      Stop services
  restart   Restart services
  logs      View service logs
  scale     Scale service replicas
  exec      Run command in container
EOF
}

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && module_main "$@"
