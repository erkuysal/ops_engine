#!/bin/bash
# core/module_base.sh - Base template and helpers for OpsEngine modules
# All modules must implement the functions defined here

# =============================================================================
# Module Registration
# =============================================================================

# Module metadata (set by each module)
MODULE_NAME=""
MODULE_VERSION="1.0.0"
MODULE_DESCRIPTION=""
MODULE_AUTHOR=""

# Register a module with its metadata
module_register() {
    MODULE_NAME="$1"
    MODULE_DESCRIPTION="${2:-No description}"
    MODULE_VERSION="${3:-1.0.0}"
}

# =============================================================================
# Required Module Functions (must be implemented)
# =============================================================================

# Phase 0: Detect - Detect existing resources (optional)
# Should detect existing configurations, certificates, services, etc.
# Returns: 0 = detection complete, 1 = nothing found
module_detect() {
    # Default: no detection
    return 1
}

# Phase 1: Setup - Check prerequisites, install dependencies
# Should check for required tools, services, permissions
# Returns: 0 = ready to proceed, 1 = blocked (manual action needed), 2 = error
module_setup() {
    log_error "module_setup() not implemented for $MODULE_NAME"
    return 2
}

# Phase 2: Configure - Collect user inputs, validate settings
# Should prompt for required configuration, save to state
# Returns: 0 = fully configured, 1 = incomplete/cancelled
module_configure() {
    log_error "module_configure() not implemented for $MODULE_NAME"
    return 1
}

# Phase 3: Deploy - Execute the actual operation
# Should perform the main action using collected configuration
# Returns: 0 = success, 1 = failed
module_deploy() {
    log_error "module_deploy() not implemented for $MODULE_NAME"
    return 1
}

# =============================================================================
# Optional Module Functions (can be overridden)
# =============================================================================

# Show current state and configuration of the module
module_status() {
    local phase=$(state_get_phase "$MODULE_NAME")
    local status=$(state_get_status "$MODULE_NAME")
    local last_run=$(state_get "modules.${MODULE_NAME}.last_run" "never")
    
    echo ""
    echo "Module: $MODULE_NAME"
    echo "==============================="
    echo "Phase:    $phase"
    echo "Status:   $status"
    echo "Last Run: $last_run"
    
    if state_is_blocked "$MODULE_NAME"; then
        echo ""
        echo "⚠️  BLOCKED:"
        echo "   $(state_get_blocked_on "$MODULE_NAME")"
    fi
    echo ""
}

# Reset module to initial state
module_reset() {
    if confirm "Reset $MODULE_NAME to initial state?" "n"; then
        state_reset_module "$MODULE_NAME"
        log_success "$MODULE_NAME reset"
    fi
}

# Integrate existing resources (optional)
# Prompts user to use detected resources vs create new
module_integrate() {
    log_info "No integration available for $MODULE_NAME"
    return 0
}

# Show help for this module
module_help() {
    cat <<EOF
Module: $MODULE_NAME
=====================
$MODULE_DESCRIPTION

Usage:
  ops $MODULE_NAME detect     Detect existing resources
  ops $MODULE_NAME integrate  Integrate existing setup
  ops $MODULE_NAME setup      Check prerequisites
  ops $MODULE_NAME configure  Configure settings
  ops $MODULE_NAME deploy     Execute operation
  ops $MODULE_NAME run        Run all phases (with auto-detect)
  ops $MODULE_NAME resume     Resume blocked operation
  ops $MODULE_NAME status     Show current state
  ops $MODULE_NAME reset      Reset to initial state

EOF
}

# =============================================================================
# Module Execution Engine
# =============================================================================

# Run a single phase with proper state management
_run_phase() {
    local phase="$1"
    local phase_func="module_${phase}"
    
    # Check if function exists
    if ! declare -f "$phase_func" &>/dev/null; then
        log_error "Phase function not found: $phase_func"
        return 2
    fi
    
    # Show phase header
    phase_header "$phase" "$MODULE_NAME"
    
    # Update state
    state_set_phase "$MODULE_NAME" "$phase"
    state_set_status "$MODULE_NAME" "running"
    
    # Run the phase
    local result=0
    "$phase_func" || result=$?
    
    # Update status based on result
    case $result in
        0)
            state_set_status "$MODULE_NAME" "complete"
            log_success "Phase '$phase' completed"
            ;;
        1)
            # Blocked state is set by the phase itself via state_block()
            if ! state_is_blocked "$MODULE_NAME"; then
                state_set_status "$MODULE_NAME" "blocked"
            fi
            log_warning "Phase '$phase' requires manual action"
            ;;
        *)
            state_set_status "$MODULE_NAME" "error"
            log_error "Phase '$phase' failed with error $result"
            ;;
    esac
    
    return $result
}detect → setup → configure → deploy)
module_run() {
    local start_phase="${1:-}"
    local skip_detect="${2:-false}"
    local phases=("setup" "configure" "deploy")
    local started=false
    
    # Run detection first (if not skipped and function exists)
    if [[ "$skip_detect" != "true" ]] && declare -f module_detect &>/dev/null; then
        if module_detect; then
            # Detection succeeded, offer integration
            if declare -f module_integrate &>/dev/null; then
                echo ""
                if confirm "Use detected resources?" "y"; then
                    module_integrate
                fi
            fi
        fi
        echo ""
    fi${1:-}"
    local phases=("setup" "configure" "deploy")
    local started=false
    
    # If start_phase specified, skip phases before it
    if [[ -z "$start_phase" ]]; then
        started=true
    fi
    
    for phase in "${phases[@]}"; do
        if [[ "$started" == false ]]; then
            if [[ "$phase" == "$start_phase" ]]; then
                started=true
            else
                continue
            fi
        fi
        
        _run_phase "$phase"
        local result=$?
        
        if [[ $result -ne 0 ]]; then
            if state_is_blocked "$MODULE_NAME"; then
                log_info "Module blocked. After completing the manual step, run:"
                echo "  ops $MODULE_NAME resume"
            fi
            return $result
        fi
    done
    
    # Mark module as complete
    state_set_phase "$MODULE_NAME" "complete"
    state_set_status "$MODULE_NAME" "complete"
    
    echo ""
    log_success "🎉 $MODULE_NAME completed successfully!"
}

# Resume from blocked state
module_resume() {
    if ! state_is_blocked "$MODULE_NAME"; then
        log_info "$MODULE_NAME is not blocked"
        module_status
        return 0
    fi
    
    local current_phase=$(state_get_phase "$MODULE_NAME")
    log_info "Resuming $MODULE_NAME from phase: $current_phase"
    
    # Clear blocked state
    state_resume "$MODULE_NAME"
    
    # Re-run current phase
    _run_phase "$current_phase"
    local result=$?
    
    if [[ $result -eq 0 ]]; then
        # Continue to next phases
        case "$current_phase" in
            setup)
                module_run "configure"
                ;;
            configure)
                module_run "deploy"
                ;;
            deploy)
                state_set_phase "$MODULE_NAME" "complete"
                log_success "🎉 $MODULE_NAME completed!"
                ;;
        esac
    fi
}detect)
            if declare -f module_detect &>/dev/null; then
                module_detect
            else
                log_warning "Detection not implemented for $MODULE_NAME"
            fi
            ;;
        integrate)
            if declare -f module_integrate &>/dev/null; then
                module_integrate
            else
                log_warning "Integration not implemented for $MODULE_NAME"
            fi
            ;;
        

# =============================================================================
# Module Entry Point
# =============================================================================

# Main handler for module commands
module_main() {
    local action="${1:-run}"
    shift 2>/dev/null || true
    
    # Ensure state is initialized
    if ! state_exists; then
        state_init
    fi
    
    case "$action" in
        setup)
            _run_phase "setup"
            ;;
        configure)
            _run_phase "configure"
            ;;
        deploy)
            _run_phase "deploy"
            ;;
        run)
            module_run "$@"
            ;;
        resume)
            module_resume
            ;;
        status)
            module_status
            ;;
        reset)
            module_reset
            ;;
        help|--help|-h)
            module_help
            ;;
        *)
            log_error "Unknown action: $action"
            module_help
            return 1
            ;;
    esac
}

# =============================================================================
# Configuration Helpers for modules
# =============================================================================

# Prompt for configuration value and save to state
# Usage: config_prompt "Enter domain" "domain" "example.com"
config_prompt() {
    local prompt="$1"
    local key="$2"
    local defaultdetect module_integrate
export -f module_="${3:-}"
    
    local current=$(state_get "modules.${MODULE_NAME}.config.${key}" "$default")
    
    read_with_default "$prompt" "$current" value
    
    state_set "modules.${MODULE_NAME}.config.${key}" "$value"
    echo "$value"
}

# Get configuration value
config_get() {
    local key="$1"
    local default="${2:-}"
    state_get "modules.${MODULE_NAME}.config.${key}" "$default"
}

# Set configuration value
config_set() {
    local key="$1"
    local value="$2"
    state_set "modules.${MODULE_NAME}.config.${key}" "$value"
}

# =============================================================================
# Export functions
# =============================================================================

export -f module_register
export -f module_setup module_configure module_deploy
export -f module_status module_reset module_help
export -f module_run module_resume module_main
export -f config_prompt config_get config_set
