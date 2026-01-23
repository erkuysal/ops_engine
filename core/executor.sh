#!/bin/bash
# core/executor.sh - Intelligent command execution with guided fallbacks
# Handles self-execution when possible, provides guidance when not

# =============================================================================
# Dry-Run Mode
# =============================================================================

# Global flag - set via CLI with --dry-run
export OPSENGINE_DRY_RUN="${OPSENGINE_DRY_RUN:-false}"

# Check if in dry-run mode
is_dry_run() {
    [[ "$OPSENGINE_DRY_RUN" == "true" ]]
}

# Show what would be executed in dry-run mode
dry_run_show() {
    local cmd="$1"
    local description="${2:-}"
    
    echo -e "${MAGENTA}[DRY-RUN]${NC} Would execute:"
    echo -e "  ${CYAN}$cmd${NC}"
    if [[ -n "$description" ]]; then
        echo -e "  ${DIM}($description)${NC}"
    fi
    echo ""
    return 0
}

# =============================================================================
# Execution with Fallback Guidance
# =============================================================================

# Execute command or provide guidance if it fails/can't run
# Usage: exec_or_guide "command" "fallback instructions" "resume hint"
exec_or_guide() {
    local cmd="$1"
    local fallback="$2"
    local resume_hint="${3:-}"
    local module="${4:-}"
    
    # Dry-run mode - just show what would happen
    if is_dry_run; then
        dry_run_show "$cmd" "exec_or_guide"
        return 0
    fi
    
    log_step "Attempting: $cmd"
    
    # Try to execute
    if eval "$cmd" 2>/dev/null; then
        log_success "Completed: $cmd"
        return 0
    else
        local exit_code=$?
        log_warning "Could not execute automatically"
        
        # Show guidance
        guidance_box "Manual Step Required" "$fallback" "$resume_hint"
        
        # If module provided, mark as blocked
        if [[ -n "$module" ]]; then
            state_set_status "$module" "blocked"
            state_set "modules.${module}.blocked_on" "$fallback"
        fi
        
        return $exit_code
    fi
}

# Execute with sudo, prompt or guide if needed
# Usage: exec_with_sudo "command" "fallback instructions"
exec_with_sudo() {
    local cmd="$1"
    local fallback="${2:-Run with sudo: $cmd}"
    local module="${3:-}"
    
    # Dry-run mode - just show what would happen
    if is_dry_run; then
        dry_run_show "sudo $cmd" "exec_with_sudo"
        return 0
    fi
    
    log_step "Requires elevated privileges: $cmd"
    
    # Check if we already have sudo
    if sudo -n true 2>/dev/null; then
        if sudo $cmd; then
            log_success "Completed with sudo"
            return 0
        fi
    fi
    
    # Try to get sudo interactively
    echo ""
    log_info "This operation requires sudo privileges."
    
    if sudo $cmd; then
        log_success "Completed with sudo"
        return 0
    else
        local exit_code=$?
        guidance_box "Sudo Required" "$fallback" "${module:+ops $module resume}"
        
        if [[ -n "$module" ]]; then
            state_block "$module" "$fallback"
        fi
        
        return $exit_code
    fi
}

# =============================================================================
# Tool Checking and Installation
# =============================================================================

# Check if a tool exists, offer to install if not
# Usage: check_tool "docker" "brew install docker" "apt install docker.io"
check_tool() {
    local tool="$1"
    local install_mac="${2:-}"
    local install_linux="${3:-$2}"
    local module="${4:-}"
    
    if command -v "$tool" &>/dev/null; then
        log_success "$tool is installed"
        return 0
    fi
    
    log_warning "$tool is not installed"
    
    # Detect OS and suggest installation
    local install_cmd=""
    local os=$(detect_os)
    
    case "$os" in
        macos)
            install_cmd="$install_mac"
            ;;
        linux)
            install_cmd="$install_linux"
            ;;
        *)
            install_cmd="Please install $tool manually"
            ;;
    esac
    
    if [[ -z "$install_cmd" ]]; then
        install_cmd="Please install $tool manually"
    fi
    
    # Ask user if they want to install
    echo ""
    if confirm "Install $tool now?" "y"; then
        exec_or_guide "$install_cmd" "Install manually: $install_cmd" "${module:+ops $module resume}" "$module"
        return $?
    else
        guidance_box "Tool Required" "Install $tool:\n  $install_cmd" "${module:+ops $module resume}"
        
        if [[ -n "$module" ]]; then
            state_block "$module" "Install $tool: $install_cmd"
        fi
        
        return 1
    fi
}

# Check multiple tools at once
# Usage: check_tools "docker,docker-compose,git"
check_tools() {
    local tools="$1"
    local missing=()
    
    IFS=',' read -ra TOOL_LIST <<< "$tools"
    
    for tool in "${TOOL_LIST[@]}"; do
        tool=$(echo "$tool" | xargs)  # trim whitespace
        if ! command -v "$tool" &>/dev/null; then
            missing+=("$tool")
        fi
    done
    
    if [[ ${#missing[@]} -eq 0 ]]; then
        return 0
    else
        log_warning "Missing tools: ${missing[*]}"
        return 1
    fi
}

# =============================================================================
# Service and Daemon Checks
# =============================================================================

# Check if a service is running
# Usage: check_service "docker" "systemctl start docker" "open -a Docker"
check_service() {
    local service="$1"
    local start_linux="${2:-}"
    local start_mac="${3:-$2}"
    local module="${4:-}"
    
    local os=$(detect_os)
    local running=false
    
    case "$service" in
        docker)
            if docker info &>/dev/null; then
                running=true
            fi
            ;;
        nginx)
            if pgrep -x nginx &>/dev/null; then
                running=true
            fi
            ;;
        *)
            # Generic check
            if pgrep -x "$service" &>/dev/null; then
                running=true
            fi
            ;;
    esac
    
    if [[ "$running" == true ]]; then
        log_success "$service is running"
        return 0
    fi
    
    log_warning "$service is not running"
    
    local start_cmd=""
    case "$os" in
        macos) start_cmd="$start_mac" ;;
        linux) start_cmd="$start_linux" ;;
    esac
    
    if [[ -n "$start_cmd" ]] && confirm "Start $service now?" "y"; then
        exec_or_guide "$start_cmd" "Start $service manually: $start_cmd" "${module:+ops $module resume}" "$module"
        
        # Wait and recheck
        sleep 2
        if check_service "$service" "" "" ""; then
            return 0
        fi
    fi
    
    guidance_box "Service Required" "Start $service:\n  $start_cmd" "${module:+ops $module resume}"
    
    if [[ -n "$module" ]]; then
        state_block "$module" "Start $service: $start_cmd"
    fi
    
    return 1
}

# =============================================================================
# External Service Checks
# =============================================================================

# Check if an external service/URL is reachable
# Usage: check_external "https://api.example.com" "Ensure API is accessible"
check_external() {
    local url="$1"
    local description="${2:-$url}"
    local timeout="${3:-5}"
    
    log_step "Checking: $description"
    
    if curl -sf --max-time "$timeout" "$url" &>/dev/null; then
        log_success "$description is reachable"
        return 0
    else
        log_warning "$description is not reachable"
        return 1
    fi
}

# Check DNS resolution
# Usage: check_dns "example.com"
check_dns() {
    local domain="$1"
    
    log_step "Checking DNS for: $domain"
    
    if host "$domain" &>/dev/null || nslookup "$domain" &>/dev/null; then
        log_success "DNS resolves for $domain"
        return 0
    else
        log_warning "DNS does not resolve for $domain"
        return 1
    fi
}

# =============================================================================
# File and Directory Operations
# =============================================================================

# Ensure directory exists, create if needed
# Usage: ensure_dir "/path/to/dir" "Description"
ensure_dir_exec() {
    local dir="$1"
    local description="${2:-$dir}"
    
    if [[ -d "$dir" ]]; then
        log_success "$description exists"
        return 0
    fi
    
    log_step "Creating: $description"
    
    if mkdir -p "$dir" 2>/dev/null; then
        log_success "Created: $description"
        return 0
    else
        exec_with_sudo "mkdir -p $dir" "Create directory manually: sudo mkdir -p $dir"
        return $?
    fi
}

# Ensure file exists with content
# Usage: ensure_file "/path/to/file" "content" "Description"
ensure_file_exec() {
    local file="$1"
    local content="$2"
    local description="${3:-$file}"
    
    if [[ -f "$file" ]]; then
        log_success "$description exists"
        return 0
    fi
    
    log_step "Creating: $description"
    
    # Ensure parent directory exists
    ensure_dir_exec "$(dirname "$file")" "$(dirname "$file")"
    
    if echo "$content" > "$file" 2>/dev/null; then
        log_success "Created: $description"
        return 0
    else
        guidance_box "Cannot Create File" "Create manually:\n  File: $file\n  Content: (see below)" ""
        echo "$content"
        return 1
    fi
}

# =============================================================================
# Progress and Retry Helpers
# =============================================================================

# Wait for a condition with timeout
# Usage: wait_for "docker info" 30 "Docker to start"
wait_for() {
    local cmd="$1"
    local timeout="${2:-30}"
    local description="${3:-condition}"
    
    log_step "Waiting for $description (timeout: ${timeout}s)..."
    
    local elapsed=0
    while [[ $elapsed -lt $timeout ]]; do
        if eval "$cmd" &>/dev/null; then
            log_success "$description ready"
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
        printf "."
    done
    
    echo ""
    log_error "Timeout waiting for $description"
    return 1
}

# Retry a command with exponential backoff
# Usage: retry_exec "curl http://example.com" 3 "API call"
retry_exec() {
    local cmd="$1"
    local max_attempts="${2:-3}"
    local description="${3:-command}"
    
    local attempt=1
    local delay=1
    
    while [[ $attempt -le $max_attempts ]]; do
        log_step "Attempt $attempt/$max_attempts: $description"
        
        if eval "$cmd"; then
            log_success "$description succeeded"
            return 0
        fi
        
        if [[ $attempt -lt $max_attempts ]]; then
            log_warning "Failed, retrying in ${delay}s..."
            sleep $delay
            delay=$((delay * 2))
        fi
        
        attempt=$((attempt + 1))
    done
    
    log_error "$description failed after $max_attempts attempts"
    return 1
}

# =============================================================================
# Export functions
# =============================================================================

export -f is_dry_run dry_run_show
export -f exec_or_guide exec_with_sudo
export -f check_tool check_tools check_service
export -f check_external check_dns
export -f ensure_dir_exec ensure_file_exec
export -f wait_for retry_exec
