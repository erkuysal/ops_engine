#!/usr/bin/env bash
# .ops-core/lib/cross_shell.sh — Helpers to detect Windows binaries from WSL and create shims

set -euo pipefail
if [[ "${_OPS_CORE_CROSS_SHELL_LOADED:-}" == "1" ]]; then return 0; fi
_OPS_CORE_CROSS_SHELL_LOADED=1

# Are we running under WSL? (works for WSL1/WSL2)
is_wsl() {
  if grep -qi microsoft /proc/version 2>/dev/null; then
    return 0
  fi
  return 1
}

# Try to locate a Windows executable by name using multiple probes.
# Returns the Windows path on stdout (e.g. C:\\Go\\bin\\go.exe) or empty.
find_windows_executable() {
  local name="${1:?name required}"
  local out

  # Prefer PowerShell Get-Command if available
  if command -v powershell.exe >/dev/null 2>&1; then
    out="$(powershell.exe -NoProfile -Command "try { (Get-Command '${name}.exe' -ErrorAction SilentlyContinue).Source } catch { '' }" 2>/dev/null | tr -d '\r')"
    if [[ -n "${out// /}" ]]; then
      printf '%s' "${out}"
      return 0
    fi
  fi

  # Fall back to cmd.exe where
  if command -v cmd.exe >/dev/null 2>&1; then
    out="$(cmd.exe /c where "${name}.exe" 2>/dev/null | sed -n '1p' | tr -d '\r')"
    if [[ -n "${out// /}" ]]; then
      printf '%s' "${out}"
      return 0
    fi
  fi

  # Nothing found
  return 1
}

# Convert a Windows path (C:\\foo\\bar.exe) to a WSL path if `wslpath` exists,
# otherwise return a normalized path where backslashes are left as-is.
winpath_to_wsl() {
  local winpath="${1:?winpath required}"
  if command -v wslpath >/dev/null 2>&1; then
    # Trim CRLF
    winpath="$(printf '%s' "${winpath}" | tr -d '\r')"
    wslpath -u "${winpath}"
    return 0
  fi
  printf '%s' "${winpath}"
}

shell_host_os() {
  if is_wsl; then
    printf 'wsl'
    return 0
  fi
  case "$(uname -s 2>/dev/null || printf unknown)" in
    Darwin) printf 'macos' ;;
    Linux)  printf 'linux' ;;
    *)      printf 'unknown' ;;
  esac
}

shim_windows_path() {
  local shim="${1:?shim path required}"
  [[ -f "${shim}" ]] || return 1
  sed -n "s/^WINPATH='\(.*\)'$/\1/p" "${shim}" 2>/dev/null | sed -n '1p'
}

is_windows_binary_path() {
  local path="${1:-}"
  [[ -n "${path}" ]] || return 1
  case "${path}" in
    *.exe|*.EXE) return 0 ;;
  esac
  if [[ -n "$(shim_windows_path "${path}" 2>/dev/null || true)" ]]; then
    return 0
  fi
  return 1
}

tool_host_os() {
  local name="${1:?tool name required}"
  local path
  path="$(command -v "${name}" 2>/dev/null || true)"
  if [[ -n "${path}" ]] && is_windows_binary_path "${path}"; then
    printf 'windows'
    return 0
  fi
  shell_host_os
}

tool_windows_path() {
  local name="${1:?tool name required}"
  local path winpath
  path="$(command -v "${name}" 2>/dev/null || true)"
  if [[ -n "${path}" ]]; then
    winpath="$(shim_windows_path "${path}" 2>/dev/null || true)"
    if [[ -n "${winpath}" ]]; then
      printf '%s' "${winpath}"
      return 0
    fi
    case "${path}" in
      *.exe|*.EXE)
        printf '%s' "${path}"
        return 0
        ;;
    esac
  fi
  find_windows_executable "${name}"
}

ps_single_quote() {
  local value="${1:-}"
  value="${value//\'/\'\'}"
  printf "'%s'" "${value}"
}

windows_go_build_linux() {
  local output="${1:?output path required}"
  local package="${2:?package path required}"
  local goarch="${3:-amd64}"
  local goexe wincwd winout

  command -v powershell.exe >/dev/null 2>&1 || return 1
  command -v wslpath >/dev/null 2>&1 || return 1

  goexe="$(tool_windows_path go 2>/dev/null || true)"
  [[ -n "${goexe}" ]] || return 1
  wincwd="$(wslpath -w "$(pwd)")" || return 1
  winout="$(wslpath -w "${output}")" || return 1

  powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command \
    "Set-Location -LiteralPath $(ps_single_quote "${wincwd}"); \$env:GOOS='linux'; \$env:GOARCH=$(ps_single_quote "${goarch}"); & $(ps_single_quote "${goexe}") build -o $(ps_single_quote "${winout}") $(ps_single_quote "${package}")" \
    < /dev/null
}

# Create a small shim in .ops/bin that proxies calls to the Windows exe via cmd.exe.
# Shim path: ${OPS_LOCAL_DIR}/bin/<name>
create_windows_shim() {
  local name="${1:?name required}"
  local winpath="${2:?winpath required}"
  local shim_dir="${OPS_LOCAL_DIR}/bin"
  local shim_file="${shim_dir}/${name}"

  mkdir -p "${shim_dir}"

  # Generate shim directly with embedded Windows path
  # Use a function to write content, avoiding quoting issues
  cat <<'EOF' > "${shim_file}"
#!/usr/bin/env bash
# Auto-generated shim to invoke Windows executable

EOF

  # Append the Windows path as a variable assignment (single-quoted to avoid expansion)
  printf "WINPATH='%s'\n" "${winpath}" >> "${shim_file}"

  cat <<'EOF' >> "${shim_file}"

# Try PowerShell first (handles quoting better than cmd.exe)
if command -v powershell.exe >/dev/null 2>&1; then
  # PowerShell's & call operator handles paths with spaces correctly
  exec powershell.exe -NoProfile -Command "& '$WINPATH' @args" -- "$@"
fi

# Fall back to cmd.exe
if command -v cmd.exe >/dev/null 2>&1; then
  exec cmd.exe /C "$WINPATH" "$@"
fi

# Last resort: direct execution (won't work in WSL but harmless)
exec "$WINPATH" "$@"
EOF

  chmod +x "${shim_file}"
  return 0
}

# Ensure a binary is available: if not present in PATH and we're under WSL,
# probe Windows and create a shim inside ${OPS_LOCAL_DIR}/bin.
# Returns 0 if binary is available after this call, non-zero otherwise.
ensure_cross_shell_bin() {
  local name="${1:?name required}"
  if command -v "${name}" >/dev/null 2>&1; then
    return 0
  fi
  if ! is_wsl; then
    return 1
  fi
  local winpath
  winpath="$(find_windows_executable "${name}" || true)"
  if [[ -z "${winpath}" ]]; then
    return 1
  fi
  create_windows_shim "${name}" "${winpath}"
  # Prepend bin dir to PATH if not already present
  if [[ ":${PATH}:" != *":${OPS_LOCAL_DIR}/bin:"* ]]; then
    PATH="${OPS_LOCAL_DIR}/bin:${PATH}"
    export PATH
  fi
  return 0
}

return 0
