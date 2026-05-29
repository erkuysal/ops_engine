# Cross-Platform Binary Execution (WSL/Windows)

## Problem Statement

When running `.ops` orchestration in **WSL2 with Windows-installed binaries**, path translation and execution context breaks:

### Symptom
UserEngine service fails to start when Go is installed on **Windows** but code is in **WSL mount**:
```
GetFileAttributesEx main.go: The system cannot find the file specified.
```

### Root Cause
1. **Windows Go** cannot access WSL paths natively (e.g., `/mnt/d/...`)
2. **Generic stack handlers** (e.g., `.ops/core/stacks/go.sh`) run `go run main.go` directly
3. **Working directory** must be converted to Windows path for Windows binary to find files
4. **Current workaround** (userengine override) is project-specific and violates ops abstraction

### Architecture Violation
Current solution in `.ops/commands/userengine/start.sh`:
- ❌ Hardcodes userengine-specific logic
- ❌ Not reusable for other Go services or projects
- ❌ Violates boundary: project logic leaks into `.ops/` package
- ❌ Forces service-level overrides instead of framework-level solution

---

## Solution Approaches

### Option 1: Stack-Level Cross-Shell Wrapper (Recommended)
**Enhance `.ops/core/stacks/go.sh`** to detect and handle Windows Go transparently:

```bash
#!/usr/bin/env bash
# .ops/core/stacks/go.sh
set -euo pipefail

# Detect if running Windows binary in WSL
if is_wsl && [[ "$(command -v go)" == *"/Windows/"* ]]; then
  # Convert working directory to Windows path for Go
  WINCWD="$(wslpath -w "$(pwd)" 2>/dev/null)" || pwd
  
  # Execute Go with Windows path context
  cd "$WINCWD" 2>/dev/null || cd "$(pwd)"
  exec go "$@"
else
  # Native WSL Go or non-WSL environment
  exec go "$@"
fi
```

**Benefits:**
- ✅ Applies to **ALL Go services** automatically (not just userengine)
- ✅ Generic framework-level solution (belongs in `.ops/`)
- ✅ No service-specific overrides needed
- ✅ Reusable across projects
- ✅ Transparent to users

---

### Option 2: Cross-Shell Execution Wrapper Library
**Create reusable helper** in `.ops/core/lib/cross_shell.sh`:

```bash
run_cross_shell_binary() {
  local bin_name="$1"
  shift
  
  if is_wsl; then
    local bin_path
    bin_path="$(command -v "$bin_name")"
    
    # If Windows binary detected
    if [[ "$bin_path" == *"/Windows/"* ]] || [[ "$bin_path" == *"\.exe"* ]]; then
      local wincwd
      wincwd="$(wslpath -w "$(pwd)")" || pwd
      cd "$wincwd" 2>/dev/null || cd "$(pwd)"
    fi
  fi
  
  exec "$bin_name" "$@"
}

# Usage in any stack:
# run_cross_shell_binary go run main.go
# run_cross_shell_binary cargo build --release
```

**Benefits:**
- ✅ Reusable across multiple runtime stacks (Go, Rust, etc.)
- ✅ Declarative path context handling
- ✅ Can be extended for other cross-shell issues

---

### Option 3: Setup Command Post-Processing
**Intercept command in `run.sh`** before execution:

```bash
# In .ops/core/commands/run.sh, before executing setup command:
if is_wsl && [[ "$cmd" =~ ^(go|cargo|gradle) ]]; then
  local wincwd="$(wslpath -w "$(pwd)")"
  cd "$wincwd" 2>/dev/null || true
fi
```

**Benefits:**
- ✅ Single point of interception
- ✅ Works for all stack commands

**Drawbacks:**
- ❌ Requires regex pattern maintenance
- ❌ Less explicit than stack-level handling

---

## Implementation Plan

### Phase 1: Foundation (Immediate)
1. **Extract helper function** from `.ops/core/lib/cross_shell.sh`:
   - `is_wsl()` — Already exists
   - `is_windows_binary(path)` — NEW: Detect Windows executables
   - `run_cross_shell_binary(name, args...)` — NEW: Execute with path conversion

2. **Enhance `.ops/core/stacks/go.sh`**:
   - Source cross_shell.sh
   - Use `run_cross_shell_binary` for execution
   - Test with userengine

### Phase 2: Generalization
1. **Apply to other stacks**: rust, node, python (if applicable)
2. **Test across services**: any service using Windows binaries
3. **Remove userengine override** (no longer needed)

### Phase 3: Documentation
1. Add WSL/Windows section to `.ops/README.md`
2. Document binary detection and shimming behavior
3. Add troubleshooting guide

---

## Dependencies

### Currently Implemented
- ✅ `is_wsl()` — Detect WSL environment
- ✅ `wslpath` — Convert between WSL/Windows paths (WSL built-in)
- ✅ `command -v` — Locate binaries in PATH

### Still Needed

- 🔲 Broader stack coverage (Python/Django activation, Rust)
- 🔲 Tests for Windows binary detection on WSL
- 🔲 Tests for path conversion accuracy

### Implemented in package

- ✅ `is_wsl()`, `is_windows_binary_path()`, `tool_host_os()`, `tool_windows_path()`
- ✅ `run_cross_shell_binary()` — WSL + Windows tool execution
- ✅ `ensure_cross_shell_bin()` / Windows shims in `.ops/bin`
- ✅ Go/Node stacks use cross-shell execution

---

## Success Criteria

- [ ] Works for other runtimes (Rust, Python, etc.)
- [ ] userengine override can be safely deleted
- [ ] All services still work unchanged on native WSL installations
- [x] Any Go service can use Windows Go binary via stack cross-shell path
- [x] Path conversion happens transparently for Go/Node via `run_cross_shell_binary`
- [x] Documentation explains the feature (`docs/core/cross-shell.md`)

---

## Related Files

- `.ops/core/lib/cross_shell.sh` — Binary shimming and detection
- `.ops/core/stacks/go.sh` — Stack handler (needs enhancement)
- `.ops/core/commands/run.sh` — Command execution engine
- `.ops/commands/userengine/start.sh` — Current workaround (to be removed)
- `.ops/core/lib/preflight.sh` — Binary validation

---

## Notes

- **Path translation**: WSL `wslpath` tool converts `/mnt/d/...` ↔ `D:\...`
- **Binary detection**: Check if `command -v` path contains "Windows" or ends with ".exe"
- **Working directory**: Must change to Windows path before invoking Windows Go
- **Fallback**: If path conversion fails, try native execution anyway
