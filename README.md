# OpsEngine

**Universal DevOps CLI Tool** - Runs like native shell commands (`ls`, `mkdir`).

## Quick Start

```bash
# Install
./install.sh --local    # To ~/.local/bin/ops
./install.sh            # To /usr/local/bin/ops (requires sudo)

# Use anywhere
ops init                # Initialize project
ops cert run            # Full SSL certificate flow
ops build deploy        # Build then deploy
ops status              # Show all module states
```

## Modules

| Module | Description |
|--------|-------------|
| `cert` | SSL/TLS certificate management (Let's Encrypt) |
| `build` | Docker image building |
| `deploy` | Service deployment with hot-swap |
| `network` | Docker network management |
| `service` | Service lifecycle (start/stop/scale) |
| `version` | Version bumping and releases |

## Three-Phase Architecture

Each module follows a consistent lifecycle:

```
┌─────────┐     ┌───────────┐     ┌────────┐
│  SETUP  │ ──▶ │ CONFIGURE │ ──▶ │ DEPLOY │
└─────────┘     └───────────┘     └────────┘
 Check deps      Collect input     Execute
```

```bash
ops MODULE setup      # Check prerequisites
ops MODULE configure  # Enter settings
ops MODULE deploy     # Execute operation
ops MODULE run        # All phases in sequence
ops MODULE resume     # Resume if blocked
ops MODULE status     # Show current state
```

## State Persistence

OpsEngine saves state per-project in `.opsengine/`:
- Resume interrupted operations
- Guided fallbacks for manual steps
- Config stored in `opsengine.conf`

## Directory Structure

```
opsengine/
├── core/               # Core utilities
│   ├── state.sh        # YAML state machine
│   ├── executor.sh     # Guided execution
│   └── module_base.sh  # Three-phase template
├── modules/            # Feature modules
│   ├── cert/
│   ├── build/
│   ├── deploy/
│   ├── network/
│   ├── service/
│   └── version/
├── opsengine           # Main CLI
└── install.sh          # Installer
```

## License

MIT
