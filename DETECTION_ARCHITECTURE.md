# OpsEngine Detection & Integration Architecture

## Overview

OpsEngine now features a **detection-first architecture** that automatically discovers and integrates existing infrastructure instead of requiring fresh setup every time. This makes it ideal for both greenfield projects and brownfield migrations.

## Core Concepts

### 1. Detection Phase (Phase 0)
Before any setup or configuration, modules can detect:
- Existing certificates
- Current version management setup
- Docker configurations and images
- Desktop app configurations
- Utility scripts that could be replaced

### 2. Integration Phase (Phase 0.5)
After detection, modules offer:
- Interactive choice: use existing vs create new
- Automatic import of existing configurations
- Seamless migration from utility scripts

### 3. Enhanced Workflow

```
Old: setup → configure → deploy
New: detect → integrate → setup → configure → deploy
```

## Architecture Components

### Core Modules

#### 1. `core/integration.sh`
Central integration framework providing:
- `detect_existing_certs()` - Find SSL certificates
- `detect_existing_versions()` - Find version files
- `detect_existing_docker()` - Find Docker configs
- `detect_existing_desktop()` - Find Electron/desktop apps
- `detect_existing_utilities()` - Find utility scripts
- `integration_prompt()` - Interactive use vs create choice
- `import_detected_config()` - Import settings to opsengine.conf
- `show_detection_summary()` - Summary of all detected resources
- `generate_migration_guide()` - Map utility scripts to ops commands

#### 2. `core/module_base.sh` (Enhanced)
Base module template now includes:
- `module_detect()` - Optional detection function
- `module_integrate()` - Optional integration function
- Auto-detection in `module_run()`
- New commands: `detect`, `integrate`

### Module-Specific Detection

Each module implements its own detection logic:

```bash
# modules/cert/handler.sh
module_detect() {
    # Find existing certificates
    # Check Let's Encrypt, custom paths
    # Store in CERT_DETECTED array
    # Return 0 if found, 1 if none
}

module_integrate() {
    # Show detected certificates
    # Let user choose which to use
    # Import config via config_set()
    # Determine action: use, renew, or create new
}
```

## Usage Patterns

### Pattern 1: Fresh Setup (No Existing Resources)

```bash
ops cert run
```

**Flow:**
1. Detect runs → finds nothing
2. Proceeds to standard setup → configure → deploy
3. Creates new certificate

### Pattern 2: Existing Resources (Auto-Detect)

```bash
ops cert run
```

**Flow:**
1. Detect runs → finds existing cert (erkuysal.com, 60 days left)
2. Prompts: "Use detected resources? [Y/n]"
3. User says yes → integrate runs
4. Shows options:
   - 1) erkuysal.com (60 days left)
   - 0) Create new
5. User selects → config imported
6. Skips setup/configure (already done)
7. Proceeds to deploy (or skip if not needed)

### Pattern 3: Manual Detection & Integration

```bash
# Step 1: Detect only
ops cert detect

# Output:
# ✓ Found: erkuysal.com (expires in 60 days)
# ✓ Found: api.erkuysal.com (expires in 60 days)
# ✓ Certificate monitoring is installed

# Step 2: Integrate specific one
ops cert integrate

# Step 3: Continue workflow
ops cert configure
ops cert deploy
```

### Pattern 4: Full Project Detection

```bash
ops init --detect
```

**Runs detection for all modules:**
- Certificates: 2 found
- Version files: 5 found
- Docker: 3 compose files, 12 images
- Desktop: 1 Electron app
- Utility scripts: 8 found

**Generates migration guide:**
```
Replace utility scripts with opsengine:
  .utilities/bump-version.sh → ops version run
  .utilities/check_ssl.sh → ops cert diagnose
  .utilities/image_cleaner.sh → ops docker prune
  ...
```

## Command Reference

### Global Commands

```bash
ops init                  # Initialize project (with detection)
ops init --detect         # Initialize with full detection report
ops init --no-detect      # Initialize without detection
ops detect                # Run detection for all modules
ops migrate               # Show migration guide for utility scripts
```

### Module Commands

Every module now supports:

```bash
ops <module> detect       # Detect existing resources
ops <module> integrate    # Integrate detected resources
ops <module> setup        # Check prerequisites
ops <module> configure    # Configure settings
ops <module> deploy       # Execute operation
ops <module> run          # Full workflow (auto-detects)
ops <module> run --no-detect   # Skip detection
```

### Special Commands (Module-Specific)

#### Certificate Module
```bash
ops cert diagnose         # Comprehensive SSL diagnostics
ops cert repair           # Auto-repair common issues
ops cert monitor          # Setup expiration monitoring
ops cert verify           # Quick health check
```

#### Version Module
```bash
ops version sync          # Sync versions across all files
ops version check         # Check version consistency
ops version audit         # Show all files with versions
```

#### Docker Module
```bash
ops docker prune          # Clean old images with retention policy
ops docker analyze        # Show disk usage by repository
ops docker orphans        # Find dangling images/volumes
```

#### Desktop Module
```bash
ops desktop build         # Build desktop app
ops desktop publish       # Publish to update server
ops desktop test          # Test update mechanism
```

## Configuration Import

When integrating existing resources, configurations are automatically imported to `opsengine.conf`:

```bash
# Before integration
# (empty or minimal config)

# After: ops cert integrate
CERT_erkuysal.com_path="/etc/letsencrypt/live/erkuysal.com"
CERT_erkuysal.com_expiry="Apr 15 2026"
CERT_erkuysal.com_days_left="60"
CERT_monitoring_installed="true"

# After: ops version integrate
VERSION_version_file="./VERSION"
VERSION_current_version="0.9.8"
VERSION_file_count="5"
VERSION_files="VERSION frontend/desktop/package.json ..."

# After: ops docker integrate
DOCKER_compose_docker-compose.yml="found"
DOCKER_services="backend,frontend,voice-app"
DOCKER_registry="erkuysal"
DOCKER_existing_images="erkuysal/personal-site:backend-v0.9.8 ..."
```

## Detection Storage Structure

Modules use associative arrays to store detection results:

```bash
# Cert module
declare -gA CERT_DETECTED
CERT_DETECTED["domain_found"]="true"
CERT_DETECTED["domain_path"]="/etc/letsencrypt/live/domain"
CERT_DETECTED["domain_expiry"]="Apr 15 2026"
CERT_DETECTED["domain_days_left"]="60"

# Version module
declare -gA VERSION_DETECTED
VERSION_DETECTED["version_file"]="./VERSION"
VERSION_DETECTED["current_version"]="0.9.8"
VERSION_DETECTED["file_count"]="5"

# Docker module
declare -gA DOCKER_DETECTED
DOCKER_DETECTED["compose_docker-compose.yml"]="found"
DOCKER_DETECTED["services"]="backend,frontend"
DOCKER_DETECTED["image_count"]="12"
```

## Migration from Utility Scripts

### Automatic Detection

Utility scripts are detected and categorized:

```bash
detect_existing_utilities
# Finds:
# - .utilities/bump-version.sh → version
# - .utilities/check_ssl.sh → cert (diagnose)
# - .utilities/certificator.sh → cert
# - .utilities/image_cleaner.sh → docker
# - .utilities/publish-updates.sh → desktop
```

### Migration Guide Generation

```bash
ops migrate

# Output:
# ╔══════════════════════════════════════════════════════════
# ║ Migration Guide: Utility Scripts → OpsEngine
# ╚══════════════════════════════════════════════════════════
# 
# Certificate Management:
#   .utilities/check_ssl.sh
#   → ops cert diagnose
#
#   .utilities/certification/certificator.sh
#   → ops cert run
#
#   .utilities/certification/fix_cert_loop.sh
#   → ops cert repair
#
# Version Management:
#   .utilities/bump-version.sh
#   → ops version run
#
# Docker Management:
#   .utilities/image_cleaner.sh
#   → ops docker prune
#
# Desktop Publishing:
#   .utilities/publish-updates.sh
#   → ops desktop publish
```

### Compatibility Period

During migration, both systems can coexist:

1. **Phase 1**: Run detection, keep utility scripts
2. **Phase 2**: Test opsengine equivalents
3. **Phase 3**: Add deprecation notices to scripts:
   ```bash
   echo "⚠️  This script is deprecated. Use: ops cert run"
   ```
4. **Phase 4**: Remove utility scripts

## Best Practices

### 1. Always Run Detection First
```bash
# Good
ops cert detect
ops cert integrate
ops cert configure

# Also good (auto-detects)
ops cert run
```

### 2. Use Integration for Existing Projects
```bash
# Don't start from scratch if resources exist
ops cert run   # Auto-detects and offers integration
```

### 3. Review Detection Results
```bash
# See what was found
ops detect
ops cert detect
```

### 4. Import Before Manual Config
```bash
# Let integration import settings first
ops cert integrate

# Then make manual adjustments
ops cert configure
```

### 5. Test Before Replacing Utility Scripts
```bash
# Test opsengine equivalent
ops cert diagnose

# Compare with old script
.utilities/check_ssl.sh

# When confident, replace
```

## Example Workflows

### Scenario 1: New Team Member Onboarding

```bash
# 1. Clone repository
git clone <repo>
cd <repo>

# 2. Initialize opsengine (auto-detects everything)
ops init

# Output shows:
# ✓ Detected: 2 SSL certificates
# ✓ Detected: Docker setup with 3 services
# ✓ Detected: Desktop app (Electron)
# ✓ Detected: Version management (5 files)

# 3. Everything is configured automatically
ops status

# Output:
# cert: ready (using erkuysal.com)
# build: ready (3 services detected)
# deploy: ready
# desktop: ready (Electron app found)
```

### Scenario 2: Certificate Renewal

```bash
# Check certificate status
ops cert detect

# Output:
# ⚠️  Found: erkuysal.com (expires in 15 days)

# Integrate and renew
ops cert integrate
# User selects erkuysal.com
# System detects it needs renewal
# Offers to renew

ops cert deploy
# Renews certificate automatically
```

### Scenario 3: Migrating from Utility Scripts

```bash
# 1. See what can be replaced
ops migrate

# 2. Test equivalent commands
ops cert diagnose    # vs .utilities/check_ssl.sh
ops version run      # vs .utilities/bump-version.sh
ops docker prune     # vs .utilities/image_cleaner.sh

# 3. Add deprecation notices
# Edit utility scripts to warn users

# 4. Update documentation
# Update README with new commands

# 5. Remove utility scripts (after transition period)
rm -rf .utilities
```

## Technical Implementation

### Module Template with Detection

```bash
#!/bin/bash
# modules/example/handler.sh

module_register "example" "Example Module with Detection" "1.0.0"

# Phase 0: Detect
module_detect() {
    log_info "Detecting existing resources..."
    
    # Detection logic
    if [[ -f "/some/resource" ]]; then
        EXAMPLE_DETECTED["resource_found"]="true"
        return 0
    fi
    
    return 1
}

# Phase 0.5: Integrate
module_integrate() {
    if [[ "${EXAMPLE_DETECTED[resource_found]}" == "true" ]]; then
        if confirm "Use existing resource?" "y"; then
            config_set "use_existing" "true"
            return 0
        fi
    fi
    
    config_set "use_existing" "false"
    return 0
}

# Phase 1: Setup
module_setup() {
    if [[ "$(config_get use_existing)" == "true" ]]; then
        log_info "Using existing resource, skipping setup"
        return 0
    fi
    
    # Normal setup logic
}

# Phase 2: Configure
module_configure() {
    if [[ "$(config_get use_existing)" == "true" ]]; then
        log_info "Using existing config"
        return 0
    fi
    
    # Normal configure logic
}

# Phase 3: Deploy
module_deploy() {
    local use_existing=$(config_get use_existing)
    
    if [[ "$use_existing" == "true" ]]; then
        log_info "Validating existing resource..."
        # Validation logic
    else
        log_info "Creating new resource..."
        # Creation logic
    fi
}

# Run module
module_main "$@"
```

## Summary

The detection-first architecture transforms opsengine from a **creation tool** into an **integration tool** that:

✅ **Discovers** existing infrastructure automatically  
✅ **Integrates** seamlessly with what you have  
✅ **Migrates** from utility scripts gracefully  
✅ **Maintains** existing resources intelligently  
✅ **Supports** both fresh and existing projects

This makes opsengine the **unified general-purpose tool** for both new projects and existing infrastructure.
