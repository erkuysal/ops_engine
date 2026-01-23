# OpsEngine: Detection-First Architecture - Quick Reference

## The Big Picture

```
┌─────────────────────────────────────────────────────────────────┐
│                    OPSENGINE ENHANCEMENT                        │
│                                                                 │
│  FROM: Creation-only tool        TO: Integration-smart tool    │
│                                                                 │
│  OLD: ops cert run               NEW: ops cert run             │
│       └─ Always creates new           ├─ Detects existing      │
│                                       ├─ Offers to integrate   │
│                                       └─ Or creates new         │
└─────────────────────────────────────────────────────────────────┘
```

## Core Enhancement: Detection Phase

```
OLD FLOW:
┌──────┐    ┌───────────┐    ┌────────┐
│ SETUP│───▶│ CONFIGURE │───▶│ DEPLOY │
└──────┘    └───────────┘    └────────┘

NEW FLOW:
┌────────┐    ┌───────────┐    ┌──────┐    ┌───────────┐    ┌────────┐
│ DETECT │───▶│ INTEGRATE │───▶│ SETUP│───▶│ CONFIGURE │───▶│ DEPLOY │
└────────┘    └───────────┘    └──────┘    └───────────┘    └────────┘
   ↓                ↓              ↓            ↓              ↓
  Find          Choose:        Check        Get input      Execute
existing     Use or Create   prereqs       if needed      operation
```

## What Gets Detected?

```
┌─────────────────────────────────────────────────────────────────┐
│ 🔒 CERTIFICATES (cert module)                                   │
├─────────────────────────────────────────────────────────────────┤
│ • Let's Encrypt certificates (/etc/letsencrypt/live)           │
│ • Custom certificates (/srv/docker-certs, /etc/nginx/ssl)      │
│ • Expiration dates and health status                           │
│ • Existing monitoring scripts                                  │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│ 📝 VERSION FILES (version module)                               │
├─────────────────────────────────────────────────────────────────┤
│ • VERSION file                                                  │
│ • package.json files (all, not just root)                      │
│ • Vue component version constants                              │
│ • React/JSX version references                                 │
│ • Config file versions                                         │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│ 🐳 DOCKER RESOURCES (docker module)                             │
├─────────────────────────────────────────────────────────────────┤
│ • docker-compose.yml files                                     │
│ • Dockerfiles                                                  │
│ • Existing Docker images (by project name)                    │
│ • Docker registry configuration                               │
│ • Service definitions                                         │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│ 🖥️  DESKTOP APPS (desktop module)                               │
├─────────────────────────────────────────────────────────────────┤
│ • Electron apps (desktop/frontend/desktop)                     │
│ • electron-builder configs                                     │
│ • Auto-updater configuration                                   │
│ • Build output directories                                     │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│ 🔧 UTILITY SCRIPTS (all modules)                                │
├─────────────────────────────────────────────────────────────────┤
│ • .utilities/ directory scripts                                │
│ • scripts/ directory                                           │
│ • Categorized by functionality                                │
│ • Migration suggestions provided                              │
└─────────────────────────────────────────────────────────────────┘
```

## Command Comparison: Old vs New

```
┌─────────────────────────────────────────────────────────────────┐
│ UTILITY SCRIPT                 │  OPSENGINE COMMAND             │
├────────────────────────────────┼────────────────────────────────┤
│ .utilities/check_ssl.sh        │  ops cert diagnose             │
│ .utilities/certificator.sh     │  ops cert run                  │
│ .utilities/fix_cert_loop.sh    │  ops cert repair               │
│ .utilities/setup_monitoring.sh │  ops cert monitor              │
├────────────────────────────────┼────────────────────────────────┤
│ .utilities/bump-version.sh     │  ops version run               │
│ (manual multi-file sync)       │  ops version sync              │
├────────────────────────────────┼────────────────────────────────┤
│ .utilities/image_cleaner.sh    │  ops docker prune              │
│ (docker image prune)           │  ops docker analyze            │
├────────────────────────────────┼────────────────────────────────┤
│ .utilities/publish-updates.sh  │  ops desktop publish           │
│ (manual build + rsync)         │  ops desktop build             │
└─────────────────────────────────────────────────────────────────┘
```

## Usage Examples

### Example 1: Fresh Project
```bash
# Start from scratch
cd new-project/
ops cert run

# Flow:
# 1. Detect → nothing found
# 2. Setup → check certbot
# 3. Configure → enter domain
# 4. Deploy → create certificate
```

### Example 2: Existing Project
```bash
# Project has existing cert
cd existing-project/
ops cert run

# Flow:
# 1. Detect → found erkuysal.com (60 days)
# 2. Prompt: "Use existing? [Y/n]" → yes
# 3. Integrate → import config
# 4. Skip setup/configure (already done)
# 5. Deploy → validate existing
```

### Example 3: Full Project Detection
```bash
cd your-project/
ops init --detect

# Output:
# ✓ Certificates: 2 found
# ✓ Docker: 3 services, 12 images
# ✓ Desktop: 1 Electron app
# ✓ Version: 5 files tracked
# ✓ Scripts: 8 utilities found
# 
# Ready to use! Run 'ops <module> run'
```

### Example 4: Troubleshooting
```bash
# SSL issues?
ops cert diagnose

# Checks:
# ✓ HTTPS connection
# ✓ Certificate details
# ✓ File locations
# ✓ Expiration status
# ✓ Symlink validation

# Auto-repair
ops cert repair

# Setup monitoring
ops cert monitor
```

### Example 5: Migration from Scripts
```bash
# See what can be replaced
ops migrate

# Output shows script → command mapping
# Test new commands
ops cert diagnose    # compare with check_ssl.sh

# When ready, deprecate scripts
# (add warning to old scripts)
```

## Key Files Created

```
opsengine/
├── core/
│   ├── integration.sh           ← NEW: Detection framework
│   ├── module_base.sh           ← ENHANCED: Detection support
│   └── detect.sh                ← ENHANCED: Project detection
├── modules/
│   ├── cert/
│   │   ├── handler.sh           ← Current
│   │   └── handler_enhanced.sh  ← NEW: Example with detection
│   ├── version/
│   │   └── handler.sh           ← TODO: Add detection
│   ├── docker/                  ← TODO: Create new module
│   └── desktop/                 ← TODO: Create new module
├── DETECTION_ARCHITECTURE.md    ← NEW: Architecture docs
└── ENHANCEMENT_STRATEGY.md      ← NEW: Implementation plan
```

## Benefits at a Glance

```
┌──────────────────────────────────────────────────────────────┐
│ FOR FRESH PROJECTS                                           │
├──────────────────────────────────────────────────────────────┤
│ ✓ Guided setup with defaults                                │
│ ✓ Best practices built-in                                   │
│ ✓ Consistent structure                                      │
└──────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────┐
│ FOR EXISTING PROJECTS                                        │
├──────────────────────────────────────────────────────────────┤
│ ✓ Auto-detects current setup                                │
│ ✓ No manual config needed                                   │
│ ✓ Seamless integration                                      │
│ ✓ Enhances workflows                                        │
└──────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────┐
│ FOR TEAM ONBOARDING                                          │
├──────────────────────────────────────────────────────────────┤
│ ✓ New member: 'ops init' → done                             │
│ ✓ Config auto-discovered                                    │
│ ✓ Single tool to learn                                      │
│ ✓ Self-documenting                                          │
└──────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────┐
│ FOR MAINTENANCE                                              │
├──────────────────────────────────────────────────────────────┤
│ ✓ Unified interface                                         │
│ ✓ Built-in diagnostics                                      │
│ ✓ Automated monitoring                                      │
│ ✓ Consistent patterns                                       │
└──────────────────────────────────────────────────────────────┘
```

## Implementation Status

```
✅ Phase 1: Core Framework
   ✅ Integration framework
   ✅ Module base enhancement
   ✅ Example implementation
   ✅ Documentation

🔄 Phase 2: Module Creation
   📝 Version module enhancement
   📝 Docker module creation
   📝 Desktop module creation

📋 Phase 3: Integration & Testing
   ⏳ Full integration
   ⏳ Testing suite
   ⏳ Real-world validation

📋 Phase 4: Migration
   ⏳ User documentation
   ⏳ Script deprecation
   ⏳ Cleanup

Legend: ✅ Done | 🔄 In Progress | 📝 Planned | ⏳ Pending
```

## Quick Start for Users

```bash
# 1. Get latest opsengine
cd opsengine && git pull && ./install.sh

# 2. Go to your project
cd ~/projects/your-project

# 3. Let opsengine detect everything
ops init --detect

# 4. Use integrated commands
ops cert run        # Certificates
ops version run     # Version management
ops docker prune    # Docker cleanup
ops desktop publish # Desktop app publishing

# 5. See migration options
ops migrate         # What can replace utility scripts
```

## Support & Documentation

- 📖 Full Architecture: [DETECTION_ARCHITECTURE.md](opsengine/DETECTION_ARCHITECTURE.md)
- 📋 Implementation Plan: [ENHANCEMENT_STRATEGY.md](opsengine/ENHANCEMENT_STRATEGY.md)
- 🔧 Example Module: [modules/cert/handler_enhanced.sh](opsengine/modules/cert/handler_enhanced.sh)
- 🌐 Integration Framework: [core/integration.sh](opsengine/core/integration.sh)

## The Vision

**Transform opsengine from a tool that creates infrastructure into a tool that understands and works with your infrastructure—whether it's new or existing.**

*"Meet users where they are, not where we think they should be."*
