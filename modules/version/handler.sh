#!/bin/bash
# modules/version/handler.sh - Version Management Module
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

module_register "version" "Version Management" "2.0.0"

# =============================================================================
# Helpers
# =============================================================================

get_current_version() {
    if [[ -f "VERSION" ]]; then
        cat VERSION | tr -d 'v\n\r'
    elif [[ -f "package.json" ]]; then
        grep '"version"' package.json | head -1 | sed 's/.*"version".*"\([^"]*\)".*/\1/'
    else
        echo "0.0.0"
    fi
}

bump_version() {
    local current="$1"
    local type="$2"
    
    IFS='.' read -r major minor patch <<< "$current"
    
    case "$type" in
        major) echo "$((major + 1)).0.0" ;;
        minor) echo "${major}.$((minor + 1)).0" ;;
        patch) echo "${major}.${minor}.$((patch + 1))" ;;
        *) echo "$current" ;;
    esac
}

# =============================================================================
# Phase 1: SETUP
# =============================================================================

module_setup() {
    step_progress 1 2 "Checking git..."
    check_tool "git" "brew install git" "apt install git" "version" || return 1
    
    step_progress 2 2 "Checking repository..."
    if [[ ! -d ".git" ]]; then
        log_warning "Not a git repository"
        if ! confirm "Continue anyway?" "n"; then
            return 1
        fi
    fi
    
    log_success "Version prerequisites satisfied"
    return 0
}

# =============================================================================
# Phase 2: CONFIGURE
# =============================================================================

module_configure() {
    local current=$(get_current_version)
    
    log_info "Current version: $current"
    echo ""
    
    echo "Bump type:"
    echo "  1) patch  → $(bump_version "$current" "patch")"
    echo "  2) minor  → $(bump_version "$current" "minor")"
    echo "  3) major  → $(bump_version "$current" "major")"
    echo "  4) custom version"
    
    read -p "Choose [1-4]: " choice
    
    local new_version=""
    case "$choice" in
        1) new_version=$(bump_version "$current" "patch"); config_set "bump_type" "patch" ;;
        2) new_version=$(bump_version "$current" "minor"); config_set "bump_type" "minor" ;;
        3) new_version=$(bump_version "$current" "major"); config_set "bump_type" "major" ;;
        4) 
            read -p "Enter version (X.Y.Z): " new_version
            config_set "bump_type" "custom"
            ;;
    esac
    
    config_set "current_version" "$current"
    config_set "new_version" "$new_version"
    
    # Options
    local create_tag="false"
    confirm "Create git tag?" "y" && create_tag="true"
    config_set "create_tag" "$create_tag"
    
    local push="false"
    confirm "Push to remote?" "y" && push="true"
    config_set "push" "$push"
    
    info_box "Version Change" \
        "$current → $new_version\nTag: $create_tag\nPush: $push"
    
    confirm "Proceed?" "y" || return 1
    return 0
}

# =============================================================================
# Phase 3: DEPLOY
# =============================================================================

module_deploy() {
    local current=$(config_get "current_version")
    local new_version=$(config_get "new_version")
    local create_tag=$(config_get "create_tag" "false")
    local push=$(config_get "push" "false")
    
    log_info "Bumping version: $current → $new_version"
    
    # Update VERSION file
    if [[ -f "VERSION" ]]; then
        log_step "Updating VERSION file..."
        echo "v$new_version" > VERSION
        log_success "Updated VERSION"
    fi
    
    # Update package.json if exists
    if [[ -f "package.json" ]]; then
        log_step "Updating package.json..."
        if command -v node &>/dev/null; then
            node -e "
                const fs = require('fs');
                const pkg = JSON.parse(fs.readFileSync('package.json', 'utf8'));
                pkg.version = '$new_version';
                fs.writeFileSync('package.json', JSON.stringify(pkg, null, 2) + '\n');
            "
            log_success "Updated package.json"
        else
            log_warning "Node not found, skipping package.json"
        fi
    fi
    
    # Git commit
    if [[ -d ".git" ]]; then
        log_step "Committing version bump..."
        git add -A
        git commit -m "Bump version to $new_version" || true
        log_success "Committed"
        
        # Create tag
        if [[ "$create_tag" == "true" ]]; then
            log_step "Creating tag v$new_version..."
            git tag -a "v$new_version" -m "Release v$new_version"
            log_success "Created tag"
        fi
        
        # Push
        if [[ "$push" == "true" ]]; then
            log_step "Pushing to remote..."
            if [[ "$create_tag" == "true" ]]; then
                git push --follow-tags
            else
                git push
            fi
            log_success "Pushed"
        fi
    fi
    
    success_box "Version Bumped!" "New version: v$new_version"
    return 0
}

module_help() {
    cat <<EOF
Module: version (Version Management)
=====================================
Bump project version and manage releases.

Usage:
  ops version setup       Check git
  ops version configure   Choose bump type
  ops version deploy      Bump and commit
  ops version run         Run all phases

Bump Types:
  patch    0.0.X → 0.0.X+1
  minor    0.X.0 → 0.X+1.0
  major    X.0.0 → X+1.0.0
  custom   Set specific version

Updates:
  - VERSION file
  - package.json (if exists)
  - Git commit and tag
EOF
}

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && module_main "$@"
