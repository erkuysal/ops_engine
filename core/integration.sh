#!/bin/bash
# core/integration.sh - Integration Framework for Existing Configurations
# Provides utilities for detecting and integrating existing infrastructure

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh" 2>/dev/null || true

# =============================================================================
# Detection Result Structure
# =============================================================================

# Stores detection results in associative arrays
declare -gA DETECTED_CERTS
declare -gA DETECTED_VERSIONS
declare -gA DETECTED_DOCKER
declare -gA DETECTED_DESKTOP
declare -gA DETECTED_SCRIPTS

# =============================================================================
# Core Detection Functions
# =============================================================================

# Detect existing SSL certificates
detect_existing_certs() {
    local domain="${1:-}"
    
    log_info "Detecting existing SSL certificates..."
    
    # Check Let's Encrypt directory
    local letsencrypt_live="/etc/letsencrypt/live"
    if [[ -d "$letsencrypt_live" ]]; then
        local found_certs=$(sudo find "$letsencrypt_live" -maxdepth 1 -type d 2>/dev/null | tail -n +2)
        if [[ -n "$found_certs" ]]; then
            while IFS= read -r cert_dir; do
                local cert_domain=$(basename "$cert_dir")
                local fullchain="$cert_dir/fullchain.pem"
                local privkey="$cert_dir/privkey.pem"
                
                if [[ -f "$fullchain" ]] && [[ -f "$privkey" ]]; then
                    # Get expiration date
                    local expiry=$(sudo openssl x509 -in "$fullchain" -noout -enddate 2>/dev/null | cut -d= -f2)
                    local days_left=$(( ($(date -d "$expiry" +%s 2>/dev/null || echo 0) - $(date +%s)) / 86400 ))
                    
                    DETECTED_CERTS["${cert_domain}_path"]="$cert_dir"
                    DETECTED_CERTS["${cert_domain}_expiry"]="$expiry"
                    DETECTED_CERTS["${cert_domain}_days_left"]="$days_left"
                    
                    log_success "Found: $cert_domain (expires in $days_left days)"
                fi
            done <<< "$found_certs"
            return 0
        fi
    fi
    
    # Check custom certificate locations
    local custom_paths=(
        "/srv/docker-certs"
        "/etc/nginx/ssl"
        "/etc/ssl/certs"
        "$HOME/certs"
    )
    
    for cert_path in "${custom_paths[@]}"; do
        if [[ -d "$cert_path" ]]; then
            local found=$(find "$cert_path" -name "fullchain.pem" -o -name "*.crt" 2>/dev/null)
            if [[ -n "$found" ]]; then
                while IFS= read -r cert_file; do
                    local cert_dir=$(dirname "$cert_file")
                    local cert_name=$(basename "$cert_dir")
                    
                    DETECTED_CERTS["custom_${cert_name}_path"]="$cert_dir"
                    log_success "Found custom cert: $cert_name in $cert_dir"
                done <<< "$found"
            fi
        fi
    done
    
    return 0
}

# Detect existing version management files
detect_existing_versions() {
    local project_root="${1:-.}"
    
    log_info "Detecting version management setup..."
    
    local version_files=()
    
    # Check VERSION file
    if [[ -f "$project_root/VERSION" ]]; then
        local version=$(cat "$project_root/VERSION" | tr -d 'v\n\r')
        DETECTED_VERSIONS["version_file"]="$project_root/VERSION"
        DETECTED_VERSIONS["current_version"]="$version"
        version_files+=("VERSION")
        log_success "Found VERSION file: $version"
    fi
    
    # Check package.json files
    local package_files=$(find "$project_root" -name "package.json" -not -path "*/node_modules/*" 2>/dev/null)
    if [[ -n "$package_files" ]]; then
        while IFS= read -r pkg_file; do
            local rel_path=$(realpath --relative-to="$project_root" "$pkg_file")
            local version=$(grep '"version"' "$pkg_file" | head -1 | sed 's/.*"version".*"\([^"]*\)".*/\1/')
            
            if [[ -n "$version" ]]; then
                DETECTED_VERSIONS["package_$rel_path"]="$version"
                version_files+=("$rel_path")
                log_success "Found $rel_path: $version"
            fi
        done <<< "$package_files"
    fi
    
    # Check for version in Vue/React components
    local version_patterns=(
        "FALLBACK_INSTALLER.*[0-9]+\.[0-9]+\.[0-9]+"
        "const version.*[0-9]+\.[0-9]+\.[0-9]+"
        "APP_VERSION.*[0-9]+\.[0-9]+\.[0-9]+"
    )
    
    for pattern in "${version_patterns[@]}"; do
        local found=$(grep -r "$pattern" "$project_root" --include="*.vue" --include="*.jsx" --include="*.tsx" 2>/dev/null | head -5)
        if [[ -n "$found" ]]; then
            while IFS= read -r match; do
                local file=$(echo "$match" | cut -d: -f1)
                local rel_path=$(realpath --relative-to="$project_root" "$file")
                version_files+=("$rel_path")
                log_success "Found version reference in $rel_path"
            done <<< "$found"
        fi
    done
    
    DETECTED_VERSIONS["file_count"]="${#version_files[@]}"
    DETECTED_VERSIONS["files"]="${version_files[*]}"
    
    return 0
}

# Detect Docker setup
detect_existing_docker() {
    local project_root="${1:-.}"
    
    log_info "Detecting Docker configuration..."
    
    # Check docker-compose files
    local compose_files=$(find "$project_root" -maxdepth 2 -name "docker-compose*.yml" -o -name "docker-compose*.yaml" 2>/dev/null)
    if [[ -n "$compose_files" ]]; then
        while IFS= read -r compose_file; do
            local rel_path=$(realpath --relative-to="$project_root" "$compose_file")
            DETECTED_DOCKER["compose_$rel_path"]="found"
            log_success "Found Docker Compose: $rel_path"
            
            # Extract services
            local services=$(grep "^  [a-z]" "$compose_file" | sed 's/:.*//' | tr '\n' ',' | sed 's/,$//')
            DETECTED_DOCKER["services_$rel_path"]="$services"
        done <<< "$compose_files"
    fi
    
    # Check Dockerfiles
    local dockerfiles=$(find "$project_root" -maxdepth 3 -name "Dockerfile" -o -name "Dockerfile.*" 2>/dev/null)
    if [[ -n "$dockerfiles" ]]; then
        local count=$(echo "$dockerfiles" | wc -l)
        DETECTED_DOCKER["dockerfile_count"]="$count"
        log_success "Found $count Dockerfile(s)"
    fi
    
    # Check for existing images
    if command -v docker &>/dev/null; then
        local project_name=$(basename "$project_root")
        local images=$(docker images --format "{{.Repository}}:{{.Tag}}" | grep -i "$project_name" 2>/dev/null || true)
        if [[ -n "$images" ]]; then
            DETECTED_DOCKER["existing_images"]="$images"
            local count=$(echo "$images" | wc -l)
            log_success "Found $count existing Docker image(s)"
        fi
    fi
    
    # Check Docker registry in compose files
    if [[ -n "$compose_files" ]]; then
        local registry=$(grep "image:" "$compose_files" 2>/dev/null | head -1 | sed 's/.*image:[[:space:]]*//' | cut -d/ -f1)
        if [[ -n "$registry" ]] && [[ "$registry" != *"{"* ]]; then
            DETECTED_DOCKER["registry"]="$registry"
            log_success "Found Docker registry: $registry"
        fi
    fi
    
    return 0
}

# Detect desktop/Electron setup
detect_existing_desktop() {
    local project_root="${1:-.}"
    
    log_info "Detecting desktop app configuration..."
    
    local desktop_paths=(
        "$project_root/desktop"
        "$project_root/frontend/desktop"
        "$project_root/electron"
    )
    
    for desktop_path in "${desktop_paths[@]}"; do
        if [[ -d "$desktop_path" ]]; then
            DETECTED_DESKTOP["path"]="$desktop_path"
            log_success "Found desktop app: $desktop_path"
            
            # Check for electron-builder config
            if [[ -f "$desktop_path/package.json" ]]; then
                local has_electron=$(grep -c "electron" "$desktop_path/package.json" 2>/dev/null || echo 0)
                if [[ $has_electron -gt 0 ]]; then
                    DETECTED_DESKTOP["type"]="electron"
                    
                    # Check for build configs
                    local build_configs=$(find "$desktop_path" -name "electron-builder*.json" 2>/dev/null)
                    if [[ -n "$build_configs" ]]; then
                        DETECTED_DESKTOP["build_configs"]="$build_configs"
                        log_success "Found electron-builder config(s)"
                    fi
                    
                    # Check for update configuration
                    if grep -q "electron-updater" "$desktop_path/package.json" 2>/dev/null; then
                        DETECTED_DESKTOP["has_updater"]="true"
                        log_success "Auto-updater configured"
                    fi
                fi
            fi
            
            return 0
        fi
    done
    
    return 1
}

# Detect existing utility scripts
detect_existing_utilities() {
    local project_root="${1:-.}"
    
    log_info "Detecting existing utility scripts..."
    
    local utility_dirs=(
        "$project_root/.utilities"
        "$project_root/scripts"
        "$project_root/bin"
        "$project_root/tools"
    )
    
    for util_dir in "${utility_dirs[@]}"; do
        if [[ -d "$util_dir" ]]; then
            # Find all scripts
            local scripts=$(find "$util_dir" -type f \( -name "*.sh" -o -perm -111 \) 2>/dev/null)
            if [[ -n "$scripts" ]]; then
                while IFS= read -r script; do
                    local script_name=$(basename "$script")
                    local rel_path=$(realpath --relative-to="$project_root" "$script")
                    
                    # Categorize by name pattern
                    case "$script_name" in
                        *cert*|*ssl*)
                            DETECTED_SCRIPTS["cert_$script_name"]="$rel_path"
                            ;;
                        *version*|*bump*)
                            DETECTED_SCRIPTS["version_$script_name"]="$rel_path"
                            ;;
                        *docker*|*image*|*clean*)
                            DETECTED_SCRIPTS["docker_$script_name"]="$rel_path"
                            ;;
                        *deploy*|*publish*|*update*)
                            DETECTED_SCRIPTS["deploy_$script_name"]="$rel_path"
                            ;;
                        *build*)
                            DETECTED_SCRIPTS["build_$script_name"]="$rel_path"
                            ;;
                    esac
                done <<< "$scripts"
                
                local count=$(echo "$scripts" | wc -l)
                log_success "Found $count utility script(s) in $util_dir"
            fi
        fi
    done
    
    return 0
}

# =============================================================================
# Integration Helpers
# =============================================================================

# Interactive: Choose between detected and new
integration_prompt() {
    local module="$1"
    local resource_name="$2"
    local detected_value="$3"
    local default_action="${4:-use}"  # use|create|skip
    
    echo ""
    log_info "Found existing $resource_name:"
    echo "  $detected_value"
    echo ""
    echo "Options:"
    echo "  1) Use existing"
    echo "  2) Create new"
    echo "  3) Skip"
    echo ""
    
    local choice
    read -p "Choose [1-3] (default: 1): " choice
    choice=${choice:-1}
    
    case "$choice" in
        1) echo "use" ;;
        2) echo "create" ;;
        3) echo "skip" ;;
        *) echo "use" ;;
    esac
}

# Import existing config into opsengine.conf
import_detected_config() {
    local key="$1"
    local value="$2"
    
    if [[ -n "$value" ]]; then
        config_set "$key" "$value"
        log_success "Imported: $key=$value"
    fi
}

# Batch import all detected configurations
import_all_detected() {
    log_step "Importing detected configurations..."
    
    # Import certs
    for key in "${!DETECTED_CERTS[@]}"; do
        import_detected_config "CERT_$key" "${DETECTED_CERTS[$key]}"
    done
    
    # Import versions
    for key in "${!DETECTED_VERSIONS[@]}"; do
        import_detected_config "VERSION_$key" "${DETECTED_VERSIONS[$key]}"
    done
    
    # Import docker
    for key in "${!DETECTED_DOCKER[@]}"; do
        import_detected_config "DOCKER_$key" "${DETECTED_DOCKER[$key]}"
    done
    
    # Import desktop
    for key in "${!DETECTED_DESKTOP[@]}"; do
        import_detected_config "DESKTOP_$key" "${DETECTED_DESKTOP[$key]}"
    done
    
    log_success "Configuration import complete"
}

# Show detection summary
show_detection_summary() {
    echo ""
    log_section "Detection Summary"
    echo ""
    
    # Certificates
    local cert_count=$(echo "${!DETECTED_CERTS[@]}" | grep "_path$" | wc -w)
    if [[ $cert_count -gt 0 ]]; then
        log_info "SSL Certificates: ${cert_count} found"
    fi
    
    # Version files
    local version_count="${DETECTED_VERSIONS[file_count]:-0}"
    if [[ $version_count -gt 0 ]]; then
        log_info "Version Files: ${version_count} found"
    fi
    
    # Docker
    local docker_compose_count=$(echo "${!DETECTED_DOCKER[@]}" | grep "^compose_" | wc -w)
    if [[ $docker_compose_count -gt 0 ]]; then
        log_info "Docker Compose: ${docker_compose_count} file(s)"
    fi
    
    # Desktop
    if [[ -n "${DETECTED_DESKTOP[path]}" ]]; then
        log_info "Desktop App: ${DETECTED_DESKTOP[path]}"
    fi
    
    # Utility scripts
    local script_count=$(echo "${!DETECTED_SCRIPTS[@]}" | wc -w)
    if [[ $script_count -gt 0 ]]; then
        log_info "Utility Scripts: ${script_count} found"
    fi
    
    echo ""
}

# Run full detection and write to config
run_full_detection() {
    local project_root="${1:-.}"
    local write_config="${2:-true}"
    
    log_section "Detecting Existing Infrastructure"
    echo ""
    
    detect_existing_certs
    detect_existing_versions "$project_root"
    detect_existing_docker "$project_root"
    detect_existing_desktop "$project_root"
    detect_existing_utilities "$project_root"
    
    show_detection_summary
    
    # Write to config if requested
    if [[ "$write_config" == "true" ]]; then
        write_detection_to_config "$project_root"
    fi
}

# Write all detected paths to config in KEY=VALUE format
write_detection_to_config() {
    local project_root="${1:-.}"
    local config_file="${OPSENGINE_CONFIG:-$project_root/opsengine.conf}"
    
    log_section "Writing Configuration"
    echo ""
    
    # Create backup if config exists
    if [[ -f "$config_file" ]]; then
        cp "$config_file" "${config_file}.backup"
        log_info "Backed up existing config to ${config_file}.backup"
    fi
    
    # Write header
    cat > "$config_file" <<EOF
# OpsEngine Configuration
# Auto-generated by detection on $(date)
# Project root: $project_root

# ============================================
# Project Information
# ============================================
PROJECT_ROOT="$project_root"
PROJECT_NAME="$(basename "$project_root" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')"
DETECTION_DATE="$(date -Iseconds)"

EOF
    
    # Write Docker paths
    if [[ ${#DETECTED_DOCKER[@]} -gt 0 ]]; then
        echo "# ============================================" >> "$config_file"
        echo "# Docker Infrastructure" >> "$config_file"
        echo "# ============================================" >> "$config_file"
        
        for key in "${!DETECTED_DOCKER[@]}"; do
            local value="${DETECTED_DOCKER[$key]}"
            echo "DOCKER_${key^^}=\"$value\"" >> "$config_file"
        done
        echo "" >> "$config_file"
        
        log_success "Docker paths written"
    fi
    
    # Write certificate paths
    if [[ ${#DETECTED_CERTS[@]} -gt 0 ]]; then
        echo "# ============================================" >> "$config_file"
        echo "# SSL Certificates" >> "$config_file"
        echo "# ============================================" >> "$config_file"
        
        for key in "${!DETECTED_CERTS[@]}"; do
            local value="${DETECTED_CERTS[$key]}"
            echo "CERT_${key^^}=\"$value\"" >> "$config_file"
        done
        echo "" >> "$config_file"
        
        log_success "Certificate paths written"
    fi
    
    # Write version paths
    if [[ ${#DETECTED_VERSIONS[@]} -gt 0 ]]; then
        echo "# ============================================" >> "$config_file"
        echo "# Version Management" >> "$config_file"
        echo "# ============================================" >> "$config_file"
        
        for key in "${!DETECTED_VERSIONS[@]}"; do
            local value="${DETECTED_VERSIONS[$key]}"
            echo "VERSION_${key^^}=\"$value\"" >> "$config_file"
        done
        echo "" >> "$config_file"
        
        log_success "Version paths written"
    fi
    
    # Write desktop paths
    if [[ ${#DETECTED_DESKTOP[@]} -gt 0 ]]; then
        echo "# ============================================" >> "$config_file"
        echo "# Desktop Application" >> "$config_file"
        echo "# ============================================" >> "$config_file"
        
        for key in "${!DETECTED_DESKTOP[@]}"; do
            local value="${DETECTED_DESKTOP[$key]}"
            echo "DESKTOP_${key^^}=\"$value\"" >> "$config_file"
        done
        echo "" >> "$config_file"
        
        log_success "Desktop paths written"
    fi
    
    # Write utility script paths
    if [[ ${#DETECTED_SCRIPTS[@]} -gt 0 ]]; then
        echo "# ============================================" >> "$config_file"
        echo "# Utility Scripts" >> "$config_file"
        echo "# ============================================" >> "$config_file"
        
        for key in "${!DETECTED_SCRIPTS[@]}"; do
            local value="${DETECTED_SCRIPTS[$key]}"
            echo "SCRIPT_${key^^}=\"$value\"" >> "$config_file"
        done
        echo "" >> "$config_file"
        
        log_success "Utility script paths written"
    fi
    
    echo ""
    log_success "Configuration written to: $config_file"
    echo ""
    echo "To use this configuration:"
    echo "  source $config_file"
    echo "  ops <module> integrate"
}

# =============================================================================
# Migration Helpers
# =============================================================================

# Suggest opsengine equivalent for utility scripts
suggest_opsengine_command() {
    local script_path="$1"
    local script_name=$(basename "$script_path")
    
    case "$script_name" in
        *bump*version*|*version*bump*)
            echo "ops version run"
            ;;
        check*ssl*|check*cert*)
            echo "ops cert diagnose"
            ;;
        *cert*fix*|fix*cert*)
            echo "ops cert repair"
            ;;
        *cert*monitor*|setup*cert*monitor*)
            echo "ops cert monitor"
            ;;
        *cert*|certificator*)
            echo "ops cert run"
            ;;
        *image*clean*|*prune*image*)
            echo "ops docker prune"
            ;;
        publish*update*|*publish*)
            echo "ops desktop publish"
            ;;
        deploy*)
            echo "ops deploy run"
            ;;
        build*)
            echo "ops build run"
            ;;
        *)
            echo "ops <module> run"
            ;;
    esac
}

# Create migration guide
generate_migration_guide() {
    local project_root="${1:-.}"
    
    if [[ ${#DETECTED_SCRIPTS[@]} -eq 0 ]]; then
        return 0
    fi
    
    log_section "Migration Guide"
    echo ""
    log_info "Replace utility scripts with opsengine commands:"
    echo ""
    
    for key in "${!DETECTED_SCRIPTS[@]}"; do
        local script_path="${DETECTED_SCRIPTS[$key]}"
        local script_name=$(basename "$script_path")
        local ops_command=$(suggest_opsengine_command "$script_path")
        
        echo "  $script_path"
        echo "  → $ops_command"
        echo ""
    done
}

# =============================================================================
# Recursive Deep Scan
# =============================================================================

# Deep recursive detection of all infrastructure
deep_detect_all() {
    local project_root="${1:-.}"
    local max_depth="${2:-5}"
    
    log_section "Deep Infrastructure Scan"
    log_info "Scanning from: $project_root (max depth: $max_depth)"
    echo ""
    
    # Store results
    declare -gA DEEP_DETECTED
    
    # 1. Find all Dockerfiles recursively
    log_step "Scanning for Dockerfiles..."
    local dockerfiles=$(find "$project_root" -maxdepth "$max_depth" -type f -name "Dockerfile*" 2>/dev/null | grep -v node_modules | grep -v ".git")
    
    if [[ -n "$dockerfiles" ]]; then
        local count=0
        while IFS= read -r dockerfile; do
            local rel_path=$(realpath --relative-to="$project_root" "$dockerfile" 2>/dev/null || echo "$dockerfile")
            
            # Create conventional key based on directory
            local dir=$(dirname "$rel_path")
            local service=$(basename "$dir")
            [[ "$service" == "." ]] && service="root"
            
            local key="${service^^}"  # Uppercase service name
            DEEP_DETECTED["DOCKERFILE_${key}"]="$rel_path"
            
            # Analyze Dockerfile
            local base=$(grep -m1 "^FROM" "$dockerfile" | awk '{print $2}')
            DEEP_DETECTED["BASE_IMAGE_${key}"]="$base"
            
            local stages=$(grep -c "^FROM" "$dockerfile")
            DEEP_DETECTED["BUILD_STAGES_${key}"]="$stages"
            
            log_success "  $rel_path (base: $base, stages: $stages)"
            ((count++))
        done <<< "$dockerfiles"
        DEEP_DETECTED["TOTAL_DOCKERFILES"]="$count"
    fi
    
    # 2. Find all docker-compose files
    log_step "Scanning for docker-compose files..."
    local compose_files=$(find "$project_root" -maxdepth "$max_depth" -type f \( -name "docker-compose*.yml" -o -name "docker-compose*.yaml" \) 2>/dev/null | grep -v node_modules)
    
    if [[ -n "$compose_files" ]]; then
        local count=0
        while IFS= read -r compose; do
            local rel_path=$(realpath --relative-to="$project_root" "$compose" 2>/dev/null || echo "$compose")
            local filename=$(basename "$compose" .yml)
            filename=$(basename "$filename" .yaml)
            
            # Create conventional key
            if [[ "$filename" == "docker-compose" ]]; then
                DEEP_DETECTED["COMPOSE_FILE"]="$rel_path"
            else
                # Extract environment (staging, test, prod, etc.)
                local env=$(echo "$filename" | sed 's/docker-compose[.-]*//' | tr '[:lower:]' '[:upper:]' | tr '-' '_')
                DEEP_DETECTED["COMPOSE_${env}_FILE"]="$rel_path"
            fi
            
            # Extract services
            local services=$(grep -E "^  [a-zA-Z0-9_-]+:" "$compose" | sed 's/:.*//' | tr '\n' ',' | sed 's/,$//')
            if [[ "$filename" == "docker-compose" ]]; then
                DEEP_DETECTED["COMPOSE_SERVICES"]="$services"
            else
                local env=$(echo "$filename" | sed 's/docker-compose[.-]*//' | tr '[:lower:]' '[:upper:]' | tr '-' '_')
                DEEP_DETECTED["COMPOSE_${env}_SERVICES"]="$services"
            fi
            
            log_success "  $rel_path (services: $services)"
            ((count++))
        done <<< "$compose_files"
        DEEP_DETECTED["TOTAL_COMPOSE_FILES"]="$count"
    fi
    
    # 3. Find CI/CD configurations
    log_step "Scanning for CI/CD configurations..."
    
    # GitHub Actions
    local gh_workflows=$(find "$project_root/.github/workflows" -name "*.yml" -o -name "*.yaml" 2>/dev/null)
    if [[ -n "$gh_workflows" ]]; then
        local count=0
        while IFS= read -r workflow; do
            local rel_path=$(realpath --relative-to="$project_root" "$workflow" 2>/dev/null || echo "$workflow")
            local name=$(basename "$workflow" .yml | tr '[:lower:]' '[:upper:]' | tr '-' '_')
            DEEP_DETECTED["GITHUB_WORKFLOW_${name}"]="$rel_path"
            log_success "  GitHub: $rel_path"
            ((count++))
        done <<< "$gh_workflows"
        DEEP_DETECTED["TOTAL_GITHUB_WORKFLOWS"]="$count"
    fi
    
    # GitLab CI
    if [[ -f "$project_root/.gitlab-ci.yml" ]]; then
        DEEP_DETECTED["GITLAB_CI_FILE"]=".gitlab-ci.yml"
        log_success "  GitLab: .gitlab-ci.yml"
    fi
    
    # CircleCI
    if [[ -f "$project_root/.circleci/config.yml" ]]; then
        DEEP_DETECTED["CIRCLECI_CONFIG"]=".circleci/config.yml"
        log_success "  CircleCI: .circleci/config.yml"
    fi
    
    # Jenkins
    local jenkinsfiles=$(find "$project_root" -maxdepth 3 -name "Jenkinsfile*" 2>/dev/null)
    if [[ -n "$jenkinsfiles" ]]; then
        while IFS= read -r jenkinsfile; do
            local rel_path=$(realpath --relative-to="$project_root" "$jenkinsfile" 2>/dev/null || echo "$jenkinsfile")
            DEEP_DETECTED["JENKINSFILE"]="$rel_path"
            log_success "  Jenkins: $rel_path"
        done <<< "$jenkinsfiles"
    fi
    
    # 4. Find build files
    log_step "Scanning for build configurations..."
    
    # package.json files
    local packages=$(find "$project_root" -maxdepth "$max_depth" -name "package.json" 2>/dev/null | grep -v node_modules)
    if [[ -n "$packages" ]]; then
        local count=0
        while IFS= read -r pkg; do
            local rel_path=$(realpath --relative-to="$project_root" "$pkg" 2>/dev/null || echo "$pkg")
            local dir=$(dirname "$rel_path")
            
            # Create conventional key based on directory
            if [[ "$dir" == "." ]]; then
                DEEP_DETECTED["PACKAGE_JSON"]="$rel_path"
            else
                local name=$(echo "$dir" | tr '/' '_' | tr '[:lower:]' '[:upper:]' | tr '-' '_')
                DEEP_DETECTED["PACKAGE_JSON_${name}"]="$rel_path"
            fi
            log_success "  $rel_path"
            ((count++))
        done <<< "$packages"
        DEEP_DETECTED["TOTAL_PACKAGE_JSON"]="$count"
    fi
    
    # Makefile
    local makefiles=$(find "$project_root" -maxdepth 3 -name "Makefile" 2>/dev/null)
    if [[ -n "$makefiles" ]]; then
        while IFS= read -r makefile; do
            local rel_path=$(realpath --relative-to="$project_root" "$makefile" 2>/dev/null || echo "$makefile")
            DEEP_DETECTED["MAKEFILE"]="$rel_path"
            log_success "  $rel_path"
        done <<< "$makefiles"
    fi
    
    # 5. Find deployment/utility scripts
    log_step "Scanning for scripts..." .sh)
            local key=$(echo "$basename" | tr '[:lower:]' '[:upper:]' | tr '-' '_')
            DEEP_DETECTED["SCRIPT_${key}"]="$rel_path"
            ((count++))
        done <<< "$scripts"
        DEEP_DETECTED["TOTAL_SCRIPTSdo
            local rel_path=$(realpath --relative-to="$project_root" "$script" 2>/dev/null || echo "$script")
            local basename=$(basename "$script")
            local key="script_$(echo "$basename" | tr '/' '_' | tr '.' '_' | tr '-' '_')"
            DEEP_DETECTED["${key}_path"]="$rel_path"
            ((count++))
        done <<< "$scripts"
        DEEP_DETECTED["script_count"]="$count"
        log_success "  Found $count scripts"
    fi
    
    # 6. Find envifilename=$(basename "$rel_path")
            
            # Create conventional key
            if [[ "$filename" == ".env" ]]; then
                DEEP_DETECTED["ENV_FILE"]="$rel_path"
            else
                # Extract suffix (.env.production -> PRODUCTION)
                local suffix=$(echo "$filename" | sed 's/^\.env[.-]*//' | tr '[:lower:]' '[:upper:]' | tr '.' '_')
                DEEP_DETECTED["ENV_${suffix}"]="$rel_path"
            fi
            log_success "  $rel_path"
            ((count++))
        done <<< "$env_files"
        DEEP_DETECTED["TOTAL_ENV_FILES
            local rel_path=$(realpath --relative-to="$project_root" "$env" 2>/dev/null || echo "$env")
            local key="env_$(echo "$rel_path" | tr '/' '_' | tr '.' '_')"
            DEEP_DETECTED["${key}_path"]="$rel_path"
            log_success "  $rel_path"
            ((count++))
        done <<< "$env_files"
        DEEP_DETECTED["env_file_count"]="$count"
    fi
    
    echo ""
    log_success "Deep scan complete"
    
    # Write everything to config
    write_deep_detection_to_config "$project_root"
}

# Write deep detection results to config
write_deep_detection_to_config() {
    local project_root="${1:-.}"
    local config_file="${OPSENGINE_CONFIG:-$project_root/opsengine.conf}"
    
    log_section "Writing Deep Scan Results"
    echo ""
    
    # Create backup
    if [[ -f "$config_file" ]]; then
        cp "$config_file" "${config_file}.backup.$(date +%Y%m%d_%H%M%S)"
    fi
    
    # Write comprehensive config
    cat > "$config_file" <<EOF
# OpsEngine Configuration
# Auto-generated by deep detection on $(date)
# Project root: $project_root

# ============================================
# Project Information
# ===================== (keys are already uppercase)
    local categories=("DOCKERFILE" "BASE_IMAGE" "BUILD_STAGES" "COMPOSE" "GITHUB" "GITLAB" "CIRCLECI" "JENKINSFILE" "PACKAGE_JSON" "MAKEFILE" "SCRIPT" "ENV")
    
    for category in "${categories[@]}"; do
        local has_items=false
        
        # Check if category has items
        for key in "${!DEEP_DETECTED[@]}"; do
            if [[ "$key" == ${category}* ]]; then
                has_items=true
                break
            fi
        done
        
        if [[ "$has_items" == "true" ]]; then
            # Determine section title
            local section_title="$category"
            case "$category" in
                DOCKERFILE|BASE_IMAGE|BUILD_STAGES)
                    [[ "$category" == "DOCKERFILE" ]] && section_title="Docker Files" || continue
                    ;;
                COMPOSE)
                    section_title="Docker Compose"
                    ;;
                GITHUB|GITLAB|CIRCLECI|JENKINSFILE)
                    section_title="CI/CD Pipelines"
                    ;;
                PACKAGE_JSON|MAKEFILE)
                    section_title="Build Configuration"
                    ;;
                SCRIPT)
                    section_title="Scripts"
                    ;;
                ENV)
                    section_title="Environment Files"
                    ;;
            esac
            
            # Check if header already writtenTOTAL_DOCKERFILES]:-0}\"" >> "$config_file"
    echo "TOTAL_COMPOSE_FILES=\"${DEEP_DETECTED[TOTAL_COMPOSE_FILES]:-0}\"" >> "$config_file"
    echo "TOTAL_PACKAGE_JSON=\"${DEEP_DETECTED[TOTAL_PACKAGE_JSON]:-0}\"" >> "$config_file"
    echo "TOTAL_SCRIPTS=\"${DEEP_DETECTED[TOTAL_SCRIPTS]:-0}\"" >> "$config_file"
    echo "TOTAL_ENV_FILES=\"${DEEP_DETECTED[TOTAL_ENV_FILES]:-0}\"" >> "$config_file"
    echo "" >> "$config_file"
    
    log_success "Configuration written to: $config_file"
    echo ""
    echo "Total items detected:"
    echo "  Dockerfiles: ${DEEP_DETECTED[TOTAL_DOCKERFILES]:-0}"
    echo "  Compose files: ${DEEP_DETECTED[TOTAL_COMPOSE_FILES]:-0}"
    echo "  Package.json: ${DEEP_DETECTED[TOTAL_PACKAGE_JSON]:-0}"
    echo "  Scripts: ${DEEP_DETECTED[TOTAL_SCRIPTS]:-0}"
    echo "  Environment files: ${DEEP_DETECTED[TOTAL_ENV_FILES]:-0}"
    echo ""
    echo "To use:"
    echo "  source $config_file"
    echo "  echo \$DOCKERFILE_BACKEND
                    ;;
            esac
            
            log_success "${category}TECTED[$key]}"
                    # Convert key to uppercase
                    local upper_key=$(echo "$key" | tr '[:lower:]' '[:upper:]')
                    echo "${upper_key}=\"$value\"" >> "$config_file"
                fi
            done
            echo "" >> "$config_file"
            
            log_success "${category} paths written"
        fi
    done
    
    # Add summary
    echo "# ============================================" >> "$config_file"
    echo "# Detection Summary" >> "$config_file"
    echo "# ============================================" >> "$config_file"
    echo "TOTAL_DOCKERFILES=\"${DEEP_DETECTED[dockerfile_total_count]:-0}\"" >> "$config_file"
    echo "TOTAL_COMPOSE_FILES=\"${DEEP_DETECTED[compose_total_count]:-0}\"" >> "$config_file"
    echo "TOTAL_PACKAGE_JSON=\"${DEEP_DETECTED[package_json_count]:-0}\"" >> "$config_file"
    echo "TOTAL_SCRIPTS=\"${DEEP_DETECTED[script_count]:-0}\"" >> "$config_file"
    echo "TOTAL_ENV_FILES=\"${DEEP_DETECTED[env_file_count]:-0}\"" >> "$config_file"
    echo "" >> "$config_file"
    
    log_success "Configuration written to: $config_file"
    echo ""
    echo "Total items detected:"
    echo "  Dockerfiles: ${DEEP_DETECTED[dockerfile_total_count]:-0}"
    echo "  Compose files: ${DEEP_DETECTED[compose_total_count]:-0}"
    echo "  Package.json: ${DEEP_DETECTED[package_json_count]:-0}"
    echo "  Scripts: ${DEEP_DETECTED[script_count]:-0}"
    echo "  Environment files: ${DEEP_DETECTED[env_file_count]:-0}"
    echo ""
    echo "To use:"
    echo "  source $config_file"
    echo "  echo \$DOCKERFILE_BACKEND_DOCKERFILE_PATH"
}

# =============================================================================
# Export Functions
# =============================================================================

export -f detect_existing_certs detect_existing_versions detect_existing_docker
export -f detect_existing_desktop detect_existing_utilities
export -f integration_prompt import_detected_config import_all_detected
export -f show_detection_summary run_full_detection write_detection_to_config
export -f deep_detect_all write_deep_detection_to_config
export -f suggest_opsengine_command generate_migration_guide
