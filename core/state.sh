#!/bin/bash
# core/state.sh - State machine with YAML persistence for OpsEngine
# Manages module states, phase transitions, and guided execution flow

# Determine OpsEngine installation and project directories
OPSENGINE_DATA="${XDG_DATA_HOME:-$HOME/.local/share}/opsengine"
OPSENGINE_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/opsengine"
PROJECT_STATE_DIR=".opsengine"
PROJECT_STATE_FILE="$PROJECT_STATE_DIR/state.yaml"

# Valid phases and statuses
VALID_PHASES=("setup" "configure" "deploy" "complete")
VALID_STATUSES=("pending" "running" "blocked" "complete" "error")

# =============================================================================
# State File Management
# =============================================================================

# Initialize state directory and file for current project
state_init() {
    local project_name="${1:-$(basename "$(pwd)")}"
    
    if [[ ! -d "$PROJECT_STATE_DIR" ]]; then
        mkdir -p "$PROJECT_STATE_DIR/logs"
        
        # Add to gitignore if git repo
        if [[ -d ".git" ]] && ! grep -q "^\.opsengine/$" .gitignore 2>/dev/null; then
            echo ".opsengine/" >> .gitignore
            log_info "Added .opsengine/ to .gitignore"
        fi
    fi
    
    if [[ ! -f "$PROJECT_STATE_FILE" ]]; then
        cat > "$PROJECT_STATE_FILE" <<EOF
# OpsEngine State File
# Auto-generated on $(date -Iseconds)
# DO NOT EDIT MANUALLY unless you know what you're doing

project_name: "$project_name"
initialized: $(date -Iseconds)
last_updated: $(date -Iseconds)
modules: {}
EOF
        log_success "Initialized project state: $PROJECT_STATE_FILE"
    fi
    
    return 0
}

# Check if state is initialized
state_exists() {
    [[ -f "$PROJECT_STATE_FILE" ]]
}

# Backup state before modifications
state_backup() {
    if state_exists; then
        cp "$PROJECT_STATE_FILE" "$PROJECT_STATE_DIR/state.yaml.backup"
    fi
}

# =============================================================================
# YAML Parsing (Pure Bash - no external deps)
# =============================================================================

# Get a value from state file
# Usage: state_get "modules.cert.phase"
state_get() {
    local key="$1"
    local default="${2:-}"
    
    if ! state_exists; then
        echo "$default"
        return 1
    fi
    
    # Split key by dots for nested access
    local result=""
    local in_module=false
    local target_module=""
    local target_key=""
    
    # Simple parsing for our known structure
    case "$key" in
        project_name|initialized|last_updated)
            result=$(grep "^${key}:" "$PROJECT_STATE_FILE" | sed 's/^[^:]*: *//' | tr -d '"')
            ;;
        modules.*.*)
            # Extract module and key: modules.cert.phase -> cert, phase
            target_module=$(echo "$key" | cut -d. -f2)
            target_key=$(echo "$key" | cut -d. -f3-)
            result=$(_state_get_module_value "$target_module" "$target_key")
            ;;
        *)
            result="$default"
            ;;
    esac
    
    if [[ -n "$result" ]]; then
        echo "$result"
    else
        echo "$default"
    fi
}

# Internal: Get value from a module section
_state_get_module_value() {
    local module="$1"
    local key="$2"
    local in_module=false
    local indent=""
    
    while IFS= read -r line; do
        # Check if we're entering the target module
        if [[ "$line" =~ ^[[:space:]]*${module}:[[:space:]]*$ ]]; then
            in_module=true
            continue
        fi
        
        if [[ "$in_module" == true ]]; then
            # Check if we've exited the module (non-indented or different module)
            if [[ "$line" =~ ^[[:space:]]{2}[a-z_]+:[[:space:]]*$ ]] && [[ ! "$line" =~ ^[[:space:]]*${key}: ]]; then
                # Another module started
                break
            elif [[ "$line" =~ ^[a-z_]+: ]]; then
                # Top-level key, exit
                break
            fi
            
            # Look for our key
            if [[ "$line" =~ ^[[:space:]]*${key}:[[:space:]]*(.*)$ ]]; then
                local value="${BASH_REMATCH[1]}"
                # Remove quotes
                value="${value#\"}"
                value="${value%\"}"
                value="${value#\'}"
                value="${value%\'}"
                echo "$value"
                return 0
            fi
        fi
    done < "$PROJECT_STATE_FILE"
    
    return 1
}

# Set a value in state file
# Usage: state_set "modules.cert.phase" "configure"
state_set() {
    local key="$1"
    local value="$2"
    
    if ! state_exists; then
        log_error "State not initialized. Run: ops init"
        return 1
    fi
    
    state_backup
    
    # Update last_updated timestamp
    _state_update_timestamp
    
    case "$key" in
        project_name|initialized|last_updated)
            _state_set_top_level "$key" "$value"
            ;;
        modules.*.*)
            local module=$(echo "$key" | cut -d. -f2)
            local subkey=$(echo "$key" | cut -d. -f3-)
            _state_set_module_value "$module" "$subkey" "$value"
            ;;
        *)
            log_error "Unknown state key: $key"
            return 1
            ;;
    esac
}

# Internal: Update timestamp
_state_update_timestamp() {
    local timestamp=$(date -Iseconds)
    if [[ "$(uname)" == "Darwin" ]]; then
        sed -i '' "s/^last_updated:.*/last_updated: $timestamp/" "$PROJECT_STATE_FILE"
    else
        sed -i "s/^last_updated:.*/last_updated: $timestamp/" "$PROJECT_STATE_FILE"
    fi
}

# Internal: Set top-level value
_state_set_top_level() {
    local key="$1"
    local value="$2"
    
    if grep -q "^${key}:" "$PROJECT_STATE_FILE"; then
        if [[ "$(uname)" == "Darwin" ]]; then
            sed -i '' "s|^${key}:.*|${key}: \"${value}\"|" "$PROJECT_STATE_FILE"
        else
            sed -i "s|^${key}:.*|${key}: \"${value}\"|" "$PROJECT_STATE_FILE"
        fi
    else
        echo "${key}: \"${value}\"" >> "$PROJECT_STATE_FILE"
    fi
}

# Internal: Set module value (creates module section if needed)
_state_set_module_value() {
    local module="$1"
    local key="$2"
    local value="$3"
    
    # Check if module section exists
    if ! grep -q "^  ${module}:" "$PROJECT_STATE_FILE"; then
        # Create module section
        echo "  ${module}:" >> "$PROJECT_STATE_FILE"
        echo "    phase: \"setup\"" >> "$PROJECT_STATE_FILE"
        echo "    status: \"pending\"" >> "$PROJECT_STATE_FILE"
        echo "    last_run: \"\"" >> "$PROJECT_STATE_FILE"
        echo "    blocked_on: \"\"" >> "$PROJECT_STATE_FILE"
    fi
    
    # Update the specific key
    # This is a simplified approach - for complex YAML, consider yq
    local temp_file=$(mktemp)
    local in_module=false
    local key_found=false
    
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]{2}${module}:[[:space:]]*$ ]]; then
            in_module=true
            echo "$line" >> "$temp_file"
            continue
        fi
        
        if [[ "$in_module" == true ]]; then
            if [[ "$line" =~ ^[[:space:]]{2}[a-z_]+:[[:space:]]*$ ]] || [[ "$line" =~ ^[a-z_]+: ]]; then
                # Exiting module, add key if not found
                if [[ "$key_found" == false ]]; then
                    echo "    ${key}: \"${value}\"" >> "$temp_file"
                fi
                in_module=false
            elif [[ "$line" =~ ^[[:space:]]*${key}: ]]; then
                echo "    ${key}: \"${value}\"" >> "$temp_file"
                key_found=true
                continue
            fi
        fi
        
        echo "$line" >> "$temp_file"
    done < "$PROJECT_STATE_FILE"
    
    # If we ended while still in module and key not found, add it
    if [[ "$in_module" == true ]] && [[ "$key_found" == false ]]; then
        echo "    ${key}: \"${value}\"" >> "$temp_file"
    fi
    
    mv "$temp_file" "$PROJECT_STATE_FILE"
}

# =============================================================================
# Phase Management
# =============================================================================

# Get current phase for a module
state_get_phase() {
    local module="$1"
    state_get "modules.${module}.phase" "setup"
}

# Set phase for a module
state_set_phase() {
    local module="$1"
    local phase="$2"
    
    # Validate phase
    local valid=false
    for p in "${VALID_PHASES[@]}"; do
        [[ "$p" == "$phase" ]] && valid=true && break
    done
    
    if [[ "$valid" == false ]]; then
        log_error "Invalid phase: $phase. Valid: ${VALID_PHASES[*]}"
        return 1
    fi
    
    state_set "modules.${module}.phase" "$phase"
    state_set "modules.${module}.last_run" "$(date -Iseconds)"
}

# Get current status for a module
state_get_status() {
    local module="$1"
    state_get "modules.${module}.status" "pending"
}

# Set status for a module
state_set_status() {
    local module="$1"
    local status="$2"
    
    # Validate status
    local valid=false
    for s in "${VALID_STATUSES[@]}"; do
        [[ "$s" == "$status" ]] && valid=true && break
    done
    
    if [[ "$valid" == false ]]; then
        log_error "Invalid status: $status. Valid: ${VALID_STATUSES[*]}"
        return 1
    fi
    
    state_set "modules.${module}.status" "$status"
}

# =============================================================================
# Blocked State Management
# =============================================================================

# Mark a module as blocked with guidance message
state_block() {
    local module="$1"
    local message="$2"
    local resume_hint="${3:-ops ${module} resume}"
    
    state_set_status "$module" "blocked"
    state_set "modules.${module}.blocked_on" "$message"
    state_set "modules.${module}.resume_hint" "$resume_hint"
    
    log_warning "Module '$module' is blocked"
    echo ""
    guidance_box "Manual Action Required" "$message" "$resume_hint"
}

# Check if module is blocked
state_is_blocked() {
    local module="$1"
    [[ "$(state_get_status "$module")" == "blocked" ]]
}

# Get blocked message
state_get_blocked_on() {
    local module="$1"
    state_get "modules.${module}.blocked_on" ""
}

# Resume a blocked module
state_resume() {
    local module="$1"
    
    if ! state_is_blocked "$module"; then
        log_info "Module '$module' is not blocked"
        return 0
    fi
    
    state_set_status "$module" "pending"
    state_set "modules.${module}.blocked_on" ""
    log_success "Module '$module' resumed"
}

# =============================================================================
# Module State Utilities
# =============================================================================

# Get all modules with their current state
state_list_modules() {
    if ! state_exists; then
        log_error "No state file found. Run: ops init"
        return 1
    fi
    
    echo "Module States:"
    echo "=============="
    
    # Parse modules section
    local in_modules=false
    local current_module=""
    
    while IFS= read -r line; do
        if [[ "$line" == "modules:" ]]; then
            in_modules=true
            continue
        fi
        
        if [[ "$in_modules" == true ]]; then
            if [[ "$line" =~ ^[[:space:]]{2}([a-z_]+):[[:space:]]*$ ]]; then
                current_module="${BASH_REMATCH[1]}"
                local phase=$(state_get_phase "$current_module")
                local status=$(state_get_status "$current_module")
                printf "  %-12s phase: %-10s status: %s\n" "$current_module" "$phase" "$status"
            fi
        fi
    done < "$PROJECT_STATE_FILE"
}

# Reset a module to initial state
state_reset_module() {
    local module="$1"
    
    state_set_phase "$module" "setup"
    state_set_status "$module" "pending"
    state_set "modules.${module}.blocked_on" ""
    state_set "modules.${module}.last_run" ""
    
    log_success "Module '$module' reset to initial state"
}

# Reset all modules
state_reset_all() {
    if state_exists; then
        rm -f "$PROJECT_STATE_FILE"
        state_init
        log_success "All state reset"
    fi
}

# =============================================================================
# Export functions
# =============================================================================

export -f state_init state_exists state_backup
export -f state_get state_set
export -f state_get_phase state_set_phase
export -f state_get_status state_set_status
export -f state_block state_is_blocked state_get_blocked_on state_resume
export -f state_list_modules state_reset_module state_reset_all
