#!/bin/bash
# modules/docker/handler.sh - Docker Infrastructure Management with Detection
# Handles: Dockerfile analysis, compose detection, image cleanup, registry management

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPSENGINE_DIR="$(cd "$MODULE_DIR/../.." && pwd)"

# Load core modules
if [[ -z "${OPSENGINE_CORE_LOADED:-}" ]]; then
    source "$OPSENGINE_DIR/core/utils.sh"
    source "$OPSENGINE_DIR/core/config.sh"
    source "$OPSENGINE_DIR/core/state.sh"
    source "$OPSENGINE_DIR/core/executor.sh"
    source "$OPSENGINE_DIR/core/module_base.sh"
fi

module_register "docker" "Docker Infrastructure Management" "2.0.0"

# =============================================================================
# Docker Detection Storage
# =============================================================================

declare -gA DOCKER_DETECTED

# =============================================================================
# Phase 0: DETECT - Docker Infrastructure
# =============================================================================

module_detect() {
    log_section "Detecting Docker Infrastructure"
    echo ""
    
    local project_root="${1:-.}"
    local found_any=false
    
    # 1. Detect docker-compose files
    log_info "Scanning for docker-compose files..."
    local compose_files=$(find "$project_root" -maxdepth 3 -name "docker-compose*.yml" -o -name "docker-compose*.yaml" 2>/dev/null)
    
    if [[ -n "$compose_files" ]]; then
        while IFS= read -r compose_file; do
            local rel_path=$(realpath --relative-to="$project_root" "$compose_file" 2>/dev/null || echo "$compose_file")
            
            # Parse services from compose file
            local services=$(grep -E "^  [a-zA-Z0-9_-]+:" "$compose_file" | sed 's/:.*//' | tr '\n' ',' | sed 's/,$//')
            local service_count=$(echo "$services" | tr ',' '\n' | wc -l)
            
            # Detect volumes
            local has_volumes=$(grep -q "^volumes:" "$compose_file" && echo "true" || echo "false")
            
            # Detect networks
            local networks=$(grep -A 10 "^networks:" "$compose_file" 2>/dev/null | grep -E "^  [a-zA-Z0-9_-]+:" | sed 's/:.*//' | tr '\n' ',' | sed 's/,$//')
            
            DOCKER_DETECTED["compose_${rel_path}_services"]="$services"
            DOCKER_DETECTED["compose_${rel_path}_count"]="$service_count"
            DOCKER_DETECTED["compose_${rel_path}_volumes"]="$has_volumes"
            DOCKER_DETECTED["compose_${rel_path}_networks"]="$networks"
            
            log_success "Found: $rel_path ($service_count services)"
            found_any=true
        done <<< "$compose_files"
    fi
    
    # 2. Detect Dockerfiles
    log_info "Scanning for Dockerfiles..."
    local dockerfiles=$(find "$project_root" -maxdepth 3 -type f \( -name "Dockerfile" -o -name "Dockerfile.*" \) 2>/dev/null)
    
    if [[ -n "$dockerfiles" ]]; then
        local dockerfile_count=0
        while IFS= read -r dockerfile; do
            local rel_path=$(realpath --relative-to="$project_root" "$dockerfile" 2>/dev/null || echo "$dockerfile")
            local dir=$(dirname "$rel_path")
            
            # Analyze Dockerfile
            local base_image=$(grep -m1 "^FROM" "$dockerfile" | awk '{print $2}')
            local has_multi_stage=$(grep -c "^FROM" "$dockerfile")
            local build_args=$(grep -c "^ARG" "$dockerfile")
            
            DOCKER_DETECTED["dockerfile_${dir}_base"]="$base_image"
            DOCKER_DETECTED["dockerfile_${dir}_multistage"]="$([[ $has_multi_stage -gt 1 ]] && echo "true" || echo "false")"
            DOCKER_DETECTED["dockerfile_${dir}_args"]="$build_args"
            
            log_success "Found: $rel_path (base: $base_image)"
            ((dockerfile_count++))
            found_any=true
        done <<< "$dockerfiles"
        
        DOCKER_DETECTED["dockerfile_total"]="$dockerfile_count"
    fi
    
    # 3. Detect existing Docker images
    if command -v docker &>/dev/null; then
        log_info "Checking for existing Docker images..."
        
        local project_name=$(basename "$project_root" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
        local images=$(docker images --format "{{.Repository}}:{{.Tag}}" 2>/dev/null | grep -i "$project_name" || true)
        
        if [[ -n "$images" ]]; then
            local image_count=$(echo "$images" | wc -l)
            DOCKER_DETECTED["images_found"]="$images"
            DOCKER_DETECTED["images_count"]="$image_count"
            
            # Analyze image tags for versioning pattern
            local has_versioned=$(echo "$images" | grep -c "v[0-9]" || echo 0)
            DOCKER_DETECTED["images_versioned"]="$([[ $has_versioned -gt 0 ]] && echo "true" || echo "false")"
            
            # Detect image families (backend, frontend, etc.)
            local families=$(echo "$images" | sed 's/.*:\(.*\)-v.*/\1/' | sort -u | tr '\n' ',' | sed 's/,$//')
            DOCKER_DETECTED["images_families"]="$families"
            
            log_success "Found $image_count existing images"
            found_any=true
        fi
        
        # Check for dangling images
        local dangling=$(docker images -f "dangling=true" -q 2>/dev/null | wc -l)
        if [[ $dangling -gt 0 ]]; then
            DOCKER_DETECTED["dangling_count"]="$dangling"
            log_warning "Found $dangling dangling images"
        fi
    fi
    
    # 4. Detect Docker registry configuration
    log_info "Detecting registry configuration..."
    
    if [[ -n "$compose_files" ]]; then
        # Check compose files for registry
        local registry=$(grep -h "image:" $compose_files 2>/dev/null | grep -v "#" | head -1 | sed 's/.*image:[[:space:]]*//' | cut -d/ -f1 | tr -d '"' | tr -d "'")
        
        if [[ -n "$registry" ]] && [[ "$registry" != *"$"* ]] && [[ "$registry" != "{"* ]]; then
            DOCKER_DETECTED["registry"]="$registry"
            
            # Determine registry type
            case "$registry" in
                ghcr.io|*github*)
                    DOCKER_DETECTED["registry_type"]="github"
                    ;;
                *gitlab*)
                    DOCKER_DETECTED["registry_type"]="gitlab"
                    ;;
                *amazonaws.com)
                    DOCKER_DETECTED["registry_type"]="ecr"
                    ;;
                gcr.io|*google*)
                    DOCKER_DETECTED["registry_type"]="gcr"
                    ;;
                *)
                    DOCKER_DETECTED["registry_type"]="dockerhub"
                    ;;
            esac
            
            log_success "Registry: $registry (${DOCKER_DETECTED["registry_type"]})"
            found_any=true
        fi
    fi
    
    # 5. Detect .dockerignore
    if [[ -f "$project_root/.dockerignore" ]]; then
        DOCKER_DETECTED["dockerignore"]="true"
        log_success "Found .dockerignore"
        found_any=true
    fi
    
    echo ""
    if [[ "$found_any" == "true" ]]; then
        log_success "Docker infrastructure detected"
        return 0
    else
        log_info "No Docker infrastructure found"
        return 1
    fi
}

# =============================================================================
# Phase 0.5: INTEGRATE - Use detected Docker setup
# =============================================================================

module_integrate() {
    log_section "Docker Infrastructure Integration"
    echo ""
    
    # Show detected compose files
    local compose_count=0
    for key in "${!DOCKER_DETECTED[@]}"; do
        if [[ "$key" == compose_*_services ]]; then
            ((compose_count++))
        fi
    done
    
    if [[ $compose_count -gt 0 ]]; then
        log_info "Detected docker-compose configurations:"
        for key in "${!DOCKER_DETECTED[@]}"; do
            if [[ "$key" == compose_*_services ]]; then
                local file="${key#compose_}"
                file="${file%_services}"
                local services="${DOCKER_DETECTED[$key]}"
                echo "  • $file: $services"
            fi
        done
        echo ""
        
        read -p "Which compose file to use as primary? [Enter path or 'docker-compose.yml']: " primary_compose
        primary_compose=${primary_compose:-docker-compose.yml}
        
        config_set "compose_file" "$primary_compose"
        config_set "services" "${DOCKER_DETECTED["compose_${primary_compose}_services"]}"
    fi
    
    # Import registry config
    if [[ -n "${DOCKER_DETECTED["registry"]}" ]]; then
        config_set "registry" "${DOCKER_DETECTED["registry"]}"
        config_set "registry_type" "${DOCKER_DETECTED["registry_type"]}"
        log_success "Configured registry: ${DOCKER_DETECTED["registry"]}"
    fi
    
    # Ask about image cleanup policy
    if [[ -n "${DOCKER_DETECTED["images_count"]}" ]]; then
        echo ""
        log_info "Found ${DOCKER_DETECTED["images_count"]} existing images"
        read -p "Keep how many versions per service? [default: 3]: " keep_count
        keep_count=${keep_count:-3}
        config_set "keep_images" "$keep_count"
        
        if [[ "${DOCKER_DETECTED["images_families"]}" ]]; then
            config_set "image_families" "${DOCKER_DETECTED["images_families"]}"
        fi
    fi
    
    return 0
}

# =============================================================================
# Additional Commands
# =============================================================================

# Analyze Docker setup
docker_analyze() {
    log_section "Docker Infrastructure Analysis"
    echo ""
    
    # Disk usage
    if command -v docker &>/dev/null; then
        log_info "Docker Disk Usage:"
        docker system df
        echo ""
    fi
    
    # Image analysis by repository
    log_info "Images by Repository:"
    docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedSince}}" | head -20
    echo ""
    
    # Service dependencies from compose
    local compose_file=$(config_get "compose_file" "docker-compose.yml")
    if [[ -f "$compose_file" ]]; then
        log_info "Service Dependencies ($compose_file):"
        grep -E "^  [a-zA-Z0-9_-]+:" "$compose_file" | sed 's/://g' | while read service; do
            local depends=$(grep -A 5 "^  $service:" "$compose_file" | grep "depends_on:" -A 10 | grep "^      -" | sed 's/.*- //' || echo "none")
            echo "  $service → $depends"
        done
    fi
}

# Prune old images with retention policy
docker_prune() {
    log_section "Docker Image Cleanup"
    echo ""
    
    local keep_count=$(config_get "keep_images" "3")
    local families=$(config_get "image_families" "")
    local repository=$(config_get "registry" "")
    
    read -p "Repository to clean (e.g., erkuysal/personal-site): " repo_input
    repository=${repo_input:-$repository}
    
    if [[ -z "$repository" ]]; then
        log_error "Repository name required"
        return 1
    fi
    
    log_info "Retention policy: Keep $keep_count images per family"
    echo ""
    
    # Get all images for repository
    local all_images=$(docker images --format "{{.Repository}}:{{.Tag}}" | grep "^$repository:" | grep -v "<none>")
    
    if [[ -z "$all_images" ]]; then
        log_info "No images found for $repository"
        return 0
    fi
    
    # Group by family (e.g., backend-v0.0.1 -> backend)
    declare -A family_images
    
    while IFS= read -r image; do
        local tag="${image#*:}"
        
        # Extract family name (everything before -v or first v)
        local family
        if [[ "$tag" =~ ^([a-z-]+)-v[0-9] ]]; then
            family="${BASH_REMATCH[1]}"
        elif [[ "$tag" =~ ^v[0-9] ]]; then
            family="root"
        else
            family="misc"
        fi
        
        family_images["$family"]+="$image "
    done <<< "$all_images"
    
    # Process each family
    for family in "${!family_images[@]}"; do
        log_info "Family: $family"
        
        local images=(${family_images[$family]})
        local image_count=${#images[@]}
        
        echo "  Found: $image_count images"
        
        if [[ $image_count -le $keep_count ]]; then
            log_success "  Keeping all (within limit)"
            continue
        fi
        
        # Sort by tag (assumes semver) and keep newest
        local sorted=$(printf '%s\n' "${images[@]}" | sort -V -r)
        local to_delete=$(echo "$sorted" | tail -n +$((keep_count + 1)))
        
        echo "  To delete: $(echo "$to_delete" | wc -l) images"
        echo "$to_delete" | while read img; do
            echo "    - $img"
        done
        
        if confirm "Delete these images?" "n"; then
            echo "$to_delete" | while read img; do
                docker rmi "$img" 2>/dev/null && log_success "    Deleted: $img" || log_warning "    Failed: $img"
            done
        fi
    done
    
    # Clean dangling images
    local dangling=$(docker images -f "dangling=true" -q | wc -l)
    if [[ $dangling -gt 0 ]]; then
        echo ""
        log_warning "Found $dangling dangling images"
        if confirm "Remove dangling images?" "y"; then
            docker image prune -f
            log_success "Dangling images removed"
        fi
    fi
}

# Find orphaned resources
docker_orphans() {
    log_section "Docker Orphaned Resources"
    echo ""
    
    # Dangling images
    log_info "Dangling Images:"
    docker images -f "dangling=true" --format "table {{.ID}}\t{{.CreatedSince}}\t{{.Size}}"
    echo ""
    
    # Unused volumes
    log_info "Unused Volumes:"
    docker volume ls -f "dangling=true" --format "table {{.Name}}\t{{.Driver}}"
    echo ""
    
    # Stopped containers
    log_info "Stopped Containers:"
    docker ps -a --filter "status=exited" --format "table {{.Names}}\t{{.Status}}\t{{.Image}}"
    echo ""
    
    if confirm "Clean all orphaned resources?" "n"; then
        docker system prune -a --volumes -f
        log_success "Cleanup complete"
    fi
}

# Validate Dockerfiles
docker_validate() {
    log_section "Dockerfile Validation"
    echo ""
    
    local dockerfiles=$(find . -maxdepth 3 -name "Dockerfile*" -type f)
    
    while IFS= read -r dockerfile; do
        log_info "Checking: $dockerfile"
        
        # Check for common issues
        local issues=0
        
        # 1. Check for COPY before RUN
        if grep -q "^RUN" "$dockerfile" && ! grep -q "^COPY\|^ADD" "$dockerfile"; then
            log_warning "  No COPY/ADD before RUN - might cause cache issues"
            ((issues++))
        fi
        
        # 2. Check for apt-get update without install
        if grep -q "apt-get update" "$dockerfile" && ! grep -q "apt-get install" "$dockerfile"; then
            log_warning "  apt-get update without install - cache issue"
            ((issues++))
        fi
        
        # 3. Check for missing .dockerignore
        local dir=$(dirname "$dockerfile")
        if [[ ! -f "$dir/.dockerignore" ]] && [[ "$dir" == "." ]]; then
            log_warning "  Missing .dockerignore file"
            ((issues++))
        fi
        
        # 4. Check for hardcoded secrets
        if grep -iE "password|secret|token|key.*=" "$dockerfile" | grep -v "ARG" >/dev/null; then
            log_error "  Potential hardcoded secret found!"
            ((issues++))
        fi
        
        if [[ $issues -eq 0 ]]; then
            log_success "  No issues found"
        fi
        
        echo ""
    done <<< "$dockerfiles"
}

# =============================================================================
# Module Phases
# =============================================================================

module_setup() {
    step_progress 1 2 "Checking Docker..."
    if ! command -v docker &>/dev/null; then
        log_error "Docker not installed"
        state_block "docker" "Install Docker: https://docs.docker.com/get-docker/"
        return 1
    fi
    
    # Check Docker is running
    if ! docker info >/dev/null 2>&1; then
        log_error "Docker daemon not running"
        state_block "docker" "Start Docker daemon"
        return 1
    fi
    
    step_progress 2 2 "Checking docker-compose..."
    if ! command -v docker-compose &>/dev/null && ! docker compose version &>/dev/null 2>&1; then
        log_warning "docker-compose not found (will use 'docker compose')"
    fi
    
    log_success "Docker prerequisites satisfied"
    return 0
}

module_configure() {
    # If integrated, skip
    if [[ "$(config_get use_existing)" == "true" ]]; then
        log_info "Using detected configuration"
        return 0
    fi
    
    # Manual configuration
    local compose_file=$(config_prompt "Docker Compose file" "compose_file" "docker-compose.yml")
    
    if [[ ! -f "$compose_file" ]]; then
        log_error "Compose file not found: $compose_file"
        return 1
    fi
    
    local registry=$(config_prompt "Docker registry" "registry" "dockerhub")
    config_set "registry" "$registry"
    
    return 0
}

module_deploy() {
    log_info "Docker management configured"
    log_success "Use 'ops docker analyze' to view infrastructure"
    return 0
}

# =============================================================================
# Custom Main Handler
# =============================================================================

docker_main() {
    local action="${1:-run}"
    shift 2>/dev/null || true
    
    case "$action" in
        analyze|stats|info)
            docker_analyze
            ;;
        prune|clean|cleanup)
            docker_prune
            ;;
        orphans|dangling)
            docker_orphans
            ;;
        validate|lint)
            docker_validate
            ;;
        *)
            module_main "$action" "$@"
            ;;
    esac
}

module_help() {
    cat <<EOF
Module: docker
==============
Docker Infrastructure Management & Analysis

Detection & Integration:
  ops docker detect      Detect existing Docker setup
  ops docker integrate   Configure from detected resources
  ops docker run         Full workflow with auto-detection

Analysis & Maintenance:
  ops docker analyze     Show infrastructure analysis
  ops docker prune       Clean old images (retention policy)
  ops docker orphans     Find and remove orphaned resources
  ops docker validate    Validate Dockerfiles

Examples:
  # Detect existing setup
  ops docker detect
  
  # Clean old images (keep 3 per family)
  ops docker prune
  
  # Find orphaned resources
  ops docker orphans
  
  # Analyze current infrastructure
  ops docker analyze

Configuration:
  DOCKER_KEEP_IMAGES     Number of images to keep per family
  DOCKER_REGISTRY        Docker registry
  DOCKER_COMPOSE_FILE    Compose file to use

EOF
}

export -f module_detect module_integrate
export -f docker_analyze docker_prune docker_orphans docker_validate docker_main

docker_main "$@"
