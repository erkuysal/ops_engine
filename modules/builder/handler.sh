#!/bin/bash
# modules/builder/handler.sh - Docker Build Module
# Implements three-phase lifecycle: setup → configure → deploy

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPSENGINE_DIR="$(cd "$MODULE_DIR/../.." && pwd)"

# Load core modules if not already loaded (skip if OPSENGINE_CORE_LOADED set)
if [[ -z "${OPSENGINE_CORE_LOADED:-}" ]]; then
    source "$OPSENGINE_DIR/core/utils.sh"
    source "$OPSENGINE_DIR/core/config.sh"
    source "$OPSENGINE_DIR/core/state.sh"
    source "$OPSENGINE_DIR/core/executor.sh"
    source "$OPSENGINE_DIR/core/module_base.sh"
fi

module_register "build" "Docker Image Build" "2.0.0"

# =============================================================================
# Build Detection Storage
# =============================================================================

declare -gA BUILD_DETECTED

# =============================================================================
# Phase 0: DETECT - Build Configuration
# =============================================================================

module_detect() {
    log_section "Detecting Build Configuration"
    echo ""
    
    local project_root="${1:-.}"
    local found_any=false
    
    # 1. Detect build tools/frameworks
    log_info "Scanning for build tools..."
    
    # Node.js projects
    if [[ -f "$project_root/package.json" ]]; then
        BUILD_DETECTED["has_nodejs"]="true"
        
        # Check for build scripts
        local build_script=$(grep '"build"' "$project_root/package.json" | sed 's/.*"build":[[:space:]]*"\([^"]*\)".*/\1/')
        if [[ -n "$build_script" ]]; then
            BUILD_DETECTED["nodejs_build"]="$build_script"
            log_success "Node.js build: $build_script"
        fi
        
        # Detect bundler (webpack, vite, etc.)
        if grep -q "webpack" "$project_root/package.json"; then
            BUILD_DETECTED["bundler"]="webpack"
        elif grep -q "vite" "$project_root/package.json"; then
            BUILD_DETECTED["bundler"]="vite"
        elif grep -q "parcel" "$project_root/package.json"; then
            BUILD_DETECTED["bundler"]="parcel"
        fi
        
        found_any=true
    fi
    
    # Python projects
    if [[ -f "$project_root/setup.py" ]] || [[ -f "$project_root/pyproject.toml" ]]; then
        BUILD_DETECTED["has_python"]="true"
        log_success "Python project detected"
        found_any=true
    fi
    
    # Go projects
    if [[ -f "$project_root/go.mod" ]]; then
        BUILD_DETECTED["has_go"]="true"
        log_success "Go project detected"
        found_any=true
    fi
    
    # 2. Detect Docker build configuration
    log_info "Scanning Docker build setup..."
    
    local dockerfiles=$(find "$project_root" -maxdepth 3 -name "Dockerfile*" -type f 2>/dev/null)
    if [[ -n "$dockerfiles" ]]; then
        local dockerfile_count=$(echo "$dockerfiles" | wc -l)
        BUILD_DETECTED["dockerfile_count"]="$dockerfile_count"
        
        # Analyze build strategies
        while IFS= read -r dockerfile; do
            local dir=$(dirname "$dockerfile")
            local name=$(basename "$dockerfile")
            
            # Multi-stage?
            local stage_count=$(grep -c "^FROM" "$dockerfile")
            if [[ $stage_count -gt 1 ]]; then
                BUILD_DETECTED["${name}_multistage"]="true"
                BUILD_DETECTED["${name}_stages"]="$stage_count"
            fi
            
            # Build args?
            local build_args=$(grep "^ARG" "$dockerfile" | wc -l)
            if [[ $build_args -gt 0 ]]; then
                BUILD_DETECTED["${name}_args"]="$build_args"
            fi
            
            # BuildKit features?
            if grep -q "RUN --mount=" "$dockerfile"; then
                BUILD_DETECTED["${name}_buildkit"]="true"
            fi
            
        done <<< "$dockerfiles"
        
        log_success "Found $dockerfile_count Dockerfile(s)"
        found_any=true
    fi
    
    # 3. Detect docker-compose build config
    local compose_files=$(find "$project_root" -maxdepth 2 -name "docker-compose*.yml" -o -name "docker-compose*.yaml" 2>/dev/null)
    if [[ -n "$compose_files" ]]; then
        while IFS= read -r compose_file; do
            local name=$(basename "$compose_file")
            
            # Services with build
            local services=$(grep -A 5 "^  [a-zA-Z0-9_-]+:" "$compose_file" | grep -B 1 "build:" | grep "^  [a-zA-Z]" | sed 's/:.*//' | tr '\n' ',' | sed 's/,$//')
            
            if [[ -n "$services" ]]; then
                BUILD_DETECTED["compose_${name}_services"]="$services"
                
                # Check for build args in compose
                if grep -q "args:" "$compose_file"; then
                    BUILD_DETECTED["compose_${name}_has_args"]="true"
                fi
                
                # Check for target stage
                if grep -q "target:" "$compose_file"; then
                    BUILD_DETECTED["compose_${name}_has_target"]="true"
                fi
                
                log_success "$name builds: $services"
                found_any=true
            fi
        done <<< "$compose_files"
    fi
    
    # 4. Detect build scripts
    local build_scripts=$(find "$project_root" -maxdepth 2 -type f \( -name "*build*" -o -name "compile*" \) \( -name "*.sh" -o -perm -111 \) 2>/dev/null | grep -v node_modules | head -5)
    if [[ -n "$build_scripts" ]]; then
        local script_count=$(echo "$build_scripts" | wc -l)
        BUILD_DETECTED["build_scripts"]="$build_scripts"
        BUILD_DETECTED["build_script_count"]="$script_count"
        log_success "Found $script_count build scripts"
        found_any=true
    fi
    
    # 5. Detect Makefile
    if [[ -f "$project_root/Makefile" ]]; then
        # Check for build targets
        local build_targets=$(grep "^[a-z-]*build" "$project_root/Makefile" | sed 's/:.*//' | tr '\n' ',' | sed 's/,$//')
        if [[ -n "$build_targets" ]]; then
            BUILD_DETECTED["makefile_targets"]="$build_targets"
            log_success "Makefile with build targets: $build_targets"
            found_any=true
        fi
    fi
    
    echo ""
    if [[ "$found_any" == "true" ]]; then
        log_success "Build configuration detected"
        return 0
    else
        log_info "No build configuration found"
        return 1
    fi
}

# =============================================================================
# Phase 0.5: INTEGRATE - Use detected build config
# =============================================================================

module_integrate() {
    log_section "Build Integration"
    echo ""
    
    # Show detected build strategies
    if [[ -n "${BUILD_DETECTED["compose_docker-compose.yml_services"]}" ]]; then
        local services="${BUILD_DETECTED["compose_docker-compose.yml_services"]}"
        log_info "Detected services to build: $services"
        
        if confirm "Use these services?" "y"; then
            config_set "use_existing" "true"
            config_set "services" "$services"
            config_set "compose_file" "docker-compose.yml"
        fi
    fi
    
    # Detect build optimizations
    echo ""
    log_info "Detected build optimizations:"
    
    local has_multistage=false
    for key in "${!BUILD_DETECTED[@]}"; do
        if [[ "$key" == *"_multistage" ]] && [[ "${BUILD_DETECTED[$key]}" == "true" ]]; then
            has_multistage=true
            local dockerfile="${key%_multistage}"
            local stages="${BUILD_DETECTED["${dockerfile}_stages"]}"
            echo "  ✓ $dockerfile: $stages-stage build"
        fi
    done
    
    if [[ "$has_multistage" == "true" ]]; then
        log_success "Multi-stage builds detected (optimized)"
    fi
    
    # BuildKit features
    for key in "${!BUILD_DETECTED[@]}"; do
        if [[ "$key" == *"_buildkit" ]]; then
            log_success "BuildKit features in use (build caching)"
            break
        fi
    done
    
    return 0
}

# =============================================================================
# Phase 1: SETUP
# =============================================================================

module_setup() {
    step_progress 1 3 "Checking Docker..."
    
    if ! check_tool "docker" "brew install docker" "curl -fsSL https://get.docker.com | sh" "build"; then
        return 1
    fi
    
    step_progress 2 3 "Checking Docker daemon..."
    
    if ! check_service "docker" "sudo systemctl start docker" "open -a Docker" "build"; then
        return 1
    fi
    
    step_progress 3 3 "Checking docker-compose..."
    
    if ! docker compose version &>/dev/null && ! command -v docker-compose &>/dev/null; then
        state_block "build" "Docker Compose not found"
        return 1
    fi
    
    log_success "Build prerequisites satisfied"
    return 0
}

# =============================================================================
# Phase 2: CONFIGURE
# =============================================================================

module_configure() {
    log_info "Configure Build Settings"
    
    # Detect compose file
    local compose_file="docker-compose.yml"
    [[ -f "docker-compose.yaml" ]] && compose_file="docker-compose.yaml"
    
    if [[ ! -f "$compose_file" ]]; then
        log_error "No docker-compose file found"
        return 1
    fi
    
    config_set "compose_file" "$compose_file"
    
    # Parse services
    local services=$(docker compose -f "$compose_file" config --services 2>/dev/null | tr '\n' ' ')
    log_info "Available services: $services"
    
    local selected=$(config_prompt "Services to build (comma-sep or 'all')" "services" "all")
    [[ "$selected" == "all" ]] && config_set "services" "$services" || config_set "services" "$selected"
    
    config_set "no_cache" "$(confirm 'Build without cache?' 'n' && echo true || echo false)"
    config_set "push" "$(confirm 'Push after build?' 'n' && echo true || echo false)"
    
    confirm "Proceed?" "y" || return 1
    return 0
}

# =============================================================================
# Phase 3: DEPLOY
# =============================================================================

module_deploy() {
    local compose_file=$(config_get "compose_file" "docker-compose.yml")
    local services=$(config_get "services")
    local no_cache=$(config_get "no_cache" "false")
    local push=$(config_get "push" "false")
    
    local build_args=()
    [[ "$no_cache" == "true" ]] && build_args+=(--no-cache)
    
    for svc in $services; do
        log_step "Building: $svc"
        DOCKER_BUILDKIT=1 docker compose -f "$compose_file" build "${build_args[@]}" "$svc" || return 1
        log_success "Built: $svc"
    done
    
    if [[ "$push" == "true" ]]; then
        for svc in $services; do
            log_step "Pushing: $svc"
            docker compose -f "$compose_file" push "$svc" || log_warning "Push failed: $svc"
        done
    fi
    
    success_box "Build Complete!" "Services: $services"
    return 0
}

module_help() {
    cat <<EOF
Module: build (Docker Image Build)
===================================
Build Docker images using docker-compose.

Usage:
  ops build setup       Check Docker and compose
  ops build configure   Select services and options  
  ops build deploy      Build the images
  ops build run         Run all phases
EOF
}

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && module_main "$@"
