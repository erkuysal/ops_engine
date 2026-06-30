#!/usr/bin/env bash
# .ops/core/commands/install.sh - Global ops shell installer.

set -euo pipefail

_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_SELF_DIR}/../lib/init.sh"
source "${_SELF_DIR}/../lib/logger.sh"

SUBCMD="${1:-install}"
case "${SUBCMD}" in
  doctor|repair|update|uninstall|install|help|--help|-h) shift || true ;;
  --*) SUBCMD="install" ;;
  *) SUBCMD="install" ;;
esac

DRY_RUN=false
FORCE=false
PREFIX="${OPS_INSTALL_PREFIX:-${HOME}/.local}"
BIN_DIR=""
PACKAGE_DIR=""

while [[ $# -gt 0 ]]; do
  _arg="$1"
  case "${_arg}" in
    --dry-run) DRY_RUN=true ;;
    --force) FORCE=true ;;
    --prefix=*) PREFIX="${_arg#*=}" ;;
    --prefix)
      [[ $# -ge 2 ]] || die "--prefix requires a directory" 2
      PREFIX="$2"
      shift
      ;;
    --bin-dir=*) BIN_DIR="${_arg#*=}" ;;
    --bin-dir)
      [[ $# -ge 2 ]] || die "--bin-dir requires a directory" 2
      BIN_DIR="$2"
      shift
      ;;
    --package-dir=*) PACKAGE_DIR="${_arg#*=}" ;;
    --package-dir)
      [[ $# -ge 2 ]] || die "--package-dir requires a directory" 2
      PACKAGE_DIR="$2"
      shift
      ;;
    --help|-h)
      SUBCMD="help"
      ;;
    *) die "Unknown flag: ${_arg}. Use --help." ;;
  esac
  shift
done

[[ -n "${BIN_DIR}" ]] || BIN_DIR="${PREFIX}/bin"
[[ -n "${PACKAGE_DIR}" ]] || PACKAGE_DIR="${PREFIX}/share/ops"
_abs_install_path() {
  local path="$1" parent base
  case "${path}" in
    /*) printf '%s' "${path}" ;;
    *)
      parent="$(dirname "${path}")"
      base="$(basename "${path}")"
      mkdir -p "${parent}" 2>/dev/null || true
      printf '%s/%s' "$(cd "${parent}" && pwd -P)" "${base}"
      ;;
  esac
}

BIN_DIR="$(_abs_install_path "${BIN_DIR}")"
PACKAGE_DIR="$(_abs_install_path "${PACKAGE_DIR}")"
INSTALL_BIN="${BIN_DIR}/ops"
_resolve_source_ops_dir() {
  if [[ -n "${OPS_PACKAGE_ROOT:-}" && -f "${OPS_PACKAGE_ROOT}/core/main.sh" ]]; then
    cd "${OPS_PACKAGE_ROOT}" && pwd -P
    return 0
  fi
  if [[ -n "${OPS_SOURCE_OPS_DIR:-}" && -f "${OPS_SOURCE_OPS_DIR}/core/main.sh" ]]; then
    cd "${OPS_SOURCE_OPS_DIR}" && pwd -P
    return 0
  fi
  if [[ -f "${OPS_PROJECT_ROOT}/.ops/core/main.sh" ]]; then
    cd "${OPS_PROJECT_ROOT}/.ops" && pwd -P
    return 0
  fi
  cd "${_SELF_DIR}/../.." && pwd -P
}

SOURCE_OPS_DIR="$(_resolve_source_ops_dir)"
SOURCE_ROOT="$(dirname "${SOURCE_OPS_DIR}")"
SOURCE_CORE="${SOURCE_OPS_DIR}/core/main.sh"
PACKAGE_CORE="${PACKAGE_DIR}/.ops/core/main.sh"
PACKAGE_MARKER="${PACKAGE_DIR}/.ops-install-source"

_usage_install() {
  cat <<'EOF'
Usage: ops install [--dry-run] [--force] [--prefix DIR] [--bin-dir DIR] [--package-dir DIR]
       ops install doctor [--prefix DIR] [--bin-dir DIR] [--package-dir DIR]
       ops install repair [--dry-run] [--prefix DIR] [--bin-dir DIR] [--package-dir DIR]
       ops install update [--dry-run] [--force] [--prefix DIR] [--bin-dir DIR] [--package-dir DIR]
       ops install uninstall [--dry-run] [--force] [--bin-dir DIR] [--package-dir DIR]

Installs a universal Bash `ops` command.

The installed launcher:
  - walks upward from the current directory for a project-local .ops/core/main.sh
  - otherwise runs the packaged ops core against the current directory
  - keeps setup separate from install

From a standalone .ops package checkout:
  cd .ops
  bash setup
  cd ..
  ./ops.sh install
EOF
}

_path_contains_dir() {
  local dir="$1"
  case ":${PATH}:" in
    *":${dir}:"*) return 0 ;;
    *) return 1 ;;
  esac
}

_shell_rc_hint() {
  local shell_name
  shell_name="$(basename "${SHELL:-sh}")"
  case "${shell_name}" in
    zsh) printf '~/.zshrc' ;;
    bash) printf '~/.bashrc or ~/.bash_profile' ;;
    fish) printf '~/.config/fish/config.fish' ;;
    *) printf 'your shell startup file' ;;
  esac
}

_write_launcher() {
  local dest="$1" package_root="$2" package_core="$3" source_root="$4"
  mkdir -p "$(dirname "${dest}")"
  cat > "${dest}" <<EOF
#!/usr/bin/env bash
# Managed by ops install.
# ops-install-package-root: ${package_root}
# ops-install-source-root: ${source_root}

set -euo pipefail

OPS_INSTALLED_PACKAGE_ROOT='${package_root}'
OPS_INSTALLED_SOURCE_ROOT='${source_root}'
OPS_INSTALLED_CORE_MAIN='${package_core}'

_ops_find_project_root() {
  local dir
  dir="\$(pwd -P)"
  while [[ -n "\${dir}" && "\${dir}" != "/" ]]; do
    if [[ -f "\${dir}/.ops/core/main.sh" ]]; then
      printf '%s' "\${dir}"
      return 0
    fi
    if [[ -f "\${dir}/ops.sh" && -d "\${dir}/.ops/core" ]]; then
      printf '%s' "\${dir}"
      return 0
    fi
    dir="\$(dirname "\${dir}")"
  done
  return 1
}

_ops_project_root=""
_ops_core_main=""

if _ops_project_root="\$(_ops_find_project_root 2>/dev/null)"; then
  _ops_core_main="\${_ops_project_root}/.ops/core/main.sh"
  _ops_core_root="\${_ops_project_root}/.ops/core"
else
  _ops_project_root="\$(pwd -P)"
  _ops_core_main="\${OPS_INSTALLED_CORE_MAIN}"
  _ops_core_root="\${OPS_INSTALLED_PACKAGE_ROOT}/.ops/core"
fi

if [[ ! -f "\${_ops_core_main}" ]]; then
  printf '[ERROR] ops core not found: %s\n' "\${_ops_core_main}" >&2
  printf 'Run from an ops checkout: ./ops.sh install repair\n' >&2
  exit 1
fi

OPS_PROJECT_ROOT="\${_ops_project_root}" OPS_CORE_ROOT="\${_ops_core_root}" exec bash "\${_ops_core_main}" "\$@"
EOF
  chmod +x "${dest}"
}

_is_managed_launcher() {
  local file="$1"
  [[ -f "${file}" ]] || return 1
  head -n 5 "${file}" 2>/dev/null | grep -q 'Managed by ops install'
}

_installed_source_root() {
  local file="$1"
  sed -n 's/^# ops-install-source-root: //p' "${file}" 2>/dev/null | sed -n '1p'
}

_installed_package_root() {
  local file="$1"
  sed -n 's/^# ops-install-package-root: //p' "${file}" 2>/dev/null | sed -n '1p'
}

_source_core_version() {
  sed -n 's/^OPS_CORE_VERSION="\([^"]*\)".*/\1/p' "${SOURCE_CORE}" 2>/dev/null | sed -n '1p'
}

_source_revision() {
  if command -v git >/dev/null 2>&1 && [[ -d "${SOURCE_OPS_DIR}/.git" || -d "${SOURCE_ROOT}/.git" ]]; then
    git -C "${SOURCE_OPS_DIR}" rev-parse --short HEAD 2>/dev/null || git -C "${SOURCE_ROOT}" rev-parse --short HEAD 2>/dev/null || true
  fi
}

_marker_get() {
  local key="$1"
  [[ -f "${PACKAGE_MARKER}" ]] || return 0
  sed -n "s/^${key}=//p" "${PACKAGE_MARKER}" 2>/dev/null | sed -n '1p'
}

_package_core_version() {
  _marker_get "ops-core-version"
}

_package_updated_at() {
  _marker_get "updated-at"
}

_package_source_revision() {
  _marker_get "source-revision"
}

_is_managed_package() {
  [[ -f "${PACKAGE_MARKER}" ]] || return 1
  grep -q '^managed-by=ops-install$' "${PACKAGE_MARKER}" 2>/dev/null
}

_sync_package() {
  local package_dir="$1" tmp_dir old_dir
  local source_version source_revision now
  tmp_dir="${package_dir}.tmp.$$"
  old_dir="${package_dir}.old.$$"
  source_version="$(_source_core_version)"
  source_revision="$(_source_revision)"
  now="$(ops_timestamp)"

  rm -rf "${tmp_dir}" "${old_dir}"
  mkdir -p "${tmp_dir}"
  cp -R "${SOURCE_OPS_DIR}" "${tmp_dir}/.ops"
  cp "${SOURCE_ROOT}/ops.sh" "${tmp_dir}/ops.sh" 2>/dev/null || true
  {
    printf 'managed-by=ops-install\n'
    printf 'package-format=1\n'
    printf 'ops-core-version=%s\n' "${source_version:-unknown}"
    printf 'source-root=%s\n' "${SOURCE_ROOT}"
    printf 'source-ops-dir=%s\n' "${SOURCE_OPS_DIR}"
    printf 'source-revision=%s\n' "${source_revision:-unknown}"
    if [[ -f "${PACKAGE_MARKER}" ]]; then
      local installed_at
      installed_at="$(_marker_get "installed-at")"
      printf 'installed-at=%s\n' "${installed_at:-${now}}"
    else
      printf 'installed-at=%s\n' "${now}"
    fi
    printf 'updated-at=%s\n' "${now}"
  } > "${tmp_dir}/.ops-install-source"

  if [[ -e "${package_dir}" ]]; then
    mv "${package_dir}" "${old_dir}"
  fi
  mv "${tmp_dir}" "${package_dir}"
  rm -rf "${old_dir}"
}

_doctor_install() {
  local fail=0 warn=0
  local source_version package_version package_revision package_updated_at

  ops_section "ops install doctor"

  if [[ -f "${SOURCE_CORE}" ]]; then
    ops_ok "install source core: ${SOURCE_CORE}"
    source_version="$(_source_core_version)"
    ops_ok "source version: ${source_version:-unknown}"
  else
    ops_error "install source core missing: ${SOURCE_CORE}"
    fail=$((fail + 1))
  fi

  if [[ -f "${PACKAGE_CORE}" ]]; then
    if _is_managed_package; then
      ops_ok "package core: ${PACKAGE_CORE}"
      package_version="$(_package_core_version)"
      package_revision="$(_package_source_revision)"
      package_updated_at="$(_package_updated_at)"
      ops_ok "package version: ${package_version:-unknown}"
      ops_info "package revision: ${package_revision:-unknown}"
      ops_info "package updated: ${package_updated_at:-unknown}"
      if [[ -n "${source_version:-}" && -n "${package_version:-}" && "${source_version}" != "${package_version}" ]]; then
        ops_warn "installed package version differs from current source (${package_version} != ${source_version})"
        ops_info "Refresh with: ops install update"
        warn=$((warn + 1))
      fi
    else
      ops_error "package exists but is not managed by ops: ${PACKAGE_DIR}"
      fail=$((fail + 1))
    fi
  else
    ops_warn "package not installed: ${PACKAGE_DIR}"
    warn=$((warn + 1))
  fi

  if [[ -f "${INSTALL_BIN}" ]]; then
    if _is_managed_launcher "${INSTALL_BIN}"; then
      ops_ok "launcher: ${INSTALL_BIN}"
      local installed_source
      local installed_package
      installed_source="$(_installed_source_root "${INSTALL_BIN}")"
      installed_package="$(_installed_package_root "${INSTALL_BIN}")"
      if [[ "${installed_source}" == "${SOURCE_ROOT}" ]]; then
        ops_ok "launcher source matches current checkout"
      else
        ops_warn "launcher source differs: ${installed_source:-unknown}"
        warn=$((warn + 1))
      fi
      if [[ "${installed_package}" == "${PACKAGE_DIR}" ]]; then
        ops_ok "launcher package matches install target"
      else
        ops_warn "launcher package differs: ${installed_package:-unknown}"
        warn=$((warn + 1))
      fi
    else
      ops_error "launcher exists but is not managed by ops: ${INSTALL_BIN}"
      fail=$((fail + 1))
    fi
  else
    ops_warn "launcher not installed: ${INSTALL_BIN}"
    warn=$((warn + 1))
  fi

  if _path_contains_dir "${BIN_DIR}"; then
    ops_ok "PATH contains ${BIN_DIR}"
  else
    ops_warn "PATH does not contain ${BIN_DIR}"
    ops_info "Add this to $(_shell_rc_hint): export PATH=\"${BIN_DIR}:\$PATH\""
    warn=$((warn + 1))
  fi

  local resolved=""
  resolved="$(command -v ops 2>/dev/null || true)"
  if [[ -n "${resolved}" ]]; then
    ops_ok "shell resolves ops: ${resolved}"
  else
    ops_warn "current shell does not resolve ops yet"
    warn=$((warn + 1))
  fi

  if command -v bash >/dev/null 2>&1; then
    ops_ok "bash: $(command -v bash)"
  else
    ops_error "bash not found"
    fail=$((fail + 1))
  fi

  printf '\n'
  printf 'Install doctor: %d failed, %d warnings\n' "${fail}" "${warn}"
  return "${fail}"
}

_install_global() {
  ops_section "ops install"

  if [[ ! -f "${SOURCE_CORE}" ]]; then
    die "Cannot install: ops core missing at ${SOURCE_CORE}" 2
  fi

  if [[ -e "${INSTALL_BIN}" && "${FORCE}" != "true" ]] && ! _is_managed_launcher "${INSTALL_BIN}"; then
    die "Refusing to overwrite unmanaged file: ${INSTALL_BIN}. Use --force only if you own it." 2
  fi
  if [[ -e "${PACKAGE_DIR}" && "${FORCE}" != "true" ]] && ! _is_managed_package; then
    die "Refusing to overwrite unmanaged package directory: ${PACKAGE_DIR}. Use --force only if you own it." 2
  fi

  ops_info "Install target: ${INSTALL_BIN}"
  ops_info "Package target: ${PACKAGE_DIR}"
  ops_info "Install source: ${SOURCE_OPS_DIR}"

  if [[ "${DRY_RUN}" == "true" ]]; then
    ops_info "Dry-run only. No files written."
  else
    _sync_package "${PACKAGE_DIR}"
    _write_launcher "${INSTALL_BIN}" "${PACKAGE_DIR}" "${PACKAGE_CORE}" "${SOURCE_ROOT}"
    ops_ok "Installed ops package: ${PACKAGE_DIR}"
    ops_ok "Installed universal ops command: ${INSTALL_BIN}"
  fi

  if ! _path_contains_dir "${BIN_DIR}"; then
    ops_warn "${BIN_DIR} is not currently on PATH"
    ops_info "Add this to $(_shell_rc_hint): export PATH=\"${BIN_DIR}:\$PATH\""
  fi

  ops_info "Install only installs the global command. Run 'ops setup --apply' inside a project to initialize project state."
}

_repair_install() {
  ops_section "ops install repair"
  FORCE=true
  _install_global
}

_update_install() {
  ops_section "ops install update"

  if [[ ! -f "${SOURCE_CORE}" ]]; then
    die "Cannot update: ops source core missing at ${SOURCE_CORE}" 2
  fi

  if [[ -e "${INSTALL_BIN}" && "${FORCE}" != "true" ]] && ! _is_managed_launcher "${INSTALL_BIN}"; then
    die "Refusing to update unmanaged launcher: ${INSTALL_BIN}. Use --force only if you own it." 2
  fi
  if [[ -e "${PACKAGE_DIR}" && "${FORCE}" != "true" ]] && ! _is_managed_package; then
    die "Refusing to update unmanaged package directory: ${PACKAGE_DIR}. Use --force only if you own it." 2
  fi

  local old_version old_revision new_version new_revision
  old_version="$(_package_core_version)"
  old_revision="$(_package_source_revision)"
  new_version="$(_source_core_version)"
  new_revision="$(_source_revision)"

  ops_info "Package target: ${PACKAGE_DIR}"
  ops_info "Launcher target: ${INSTALL_BIN}"
  ops_info "Version: ${old_version:-not installed} -> ${new_version:-unknown}"
  ops_info "Revision: ${old_revision:-not installed} -> ${new_revision:-unknown}"

  if [[ "${DRY_RUN}" == "true" ]]; then
    ops_info "Dry-run only. No files written."
    return 0
  fi

  _sync_package "${PACKAGE_DIR}"
  _write_launcher "${INSTALL_BIN}" "${PACKAGE_DIR}" "${PACKAGE_CORE}" "${SOURCE_ROOT}"
  ops_ok "Updated ops package: ${PACKAGE_DIR}"
  ops_ok "Updated universal ops command: ${INSTALL_BIN}"
}

_uninstall_global() {
  ops_section "ops install uninstall"

  if [[ ! -e "${INSTALL_BIN}" && ! -e "${PACKAGE_DIR}" ]]; then
    ops_ok "not installed: ${INSTALL_BIN}"
    return 0
  fi

  if [[ -e "${INSTALL_BIN}" ]] && ! _is_managed_launcher "${INSTALL_BIN}" && [[ "${FORCE}" != "true" ]]; then
    die "Refusing to remove unmanaged file: ${INSTALL_BIN}. Use --force only if you own it." 2
  fi
  if [[ -e "${PACKAGE_DIR}" ]] && ! _is_managed_package && [[ "${FORCE}" != "true" ]]; then
    die "Refusing to remove unmanaged package directory: ${PACKAGE_DIR}. Use --force only if you own it." 2
  fi

  if [[ "${DRY_RUN}" == "true" ]]; then
    [[ -e "${INSTALL_BIN}" ]] && ops_info "Would remove launcher: ${INSTALL_BIN}"
    [[ -e "${PACKAGE_DIR}" ]] && ops_info "Would remove package: ${PACKAGE_DIR}"
  else
    if [[ -e "${INSTALL_BIN}" ]]; then
      rm -f "${INSTALL_BIN}"
      ops_ok "Removed launcher: ${INSTALL_BIN}"
    fi
    if [[ -e "${PACKAGE_DIR}" ]]; then
      rm -rf "${PACKAGE_DIR}"
      ops_ok "Removed package: ${PACKAGE_DIR}"
    fi
  fi
}

case "${SUBCMD}" in
  help|--help|-h)
    _usage_install
    ;;
  install)
    _install_global
    ;;
  doctor)
    _doctor_install
    ;;
  repair)
    _repair_install
    ;;
  update)
    _update_install
    ;;
  uninstall)
    _uninstall_global
    ;;
  *)
    die "Unknown install subcommand: ${SUBCMD}" 2
    ;;
esac
