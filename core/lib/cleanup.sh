#!/usr/bin/env bash
# .ops/core/lib/cleanup.sh — Runtime state cleanup helpers.

set -euo pipefail
if [[ "${_OPS_CORE_CLEANUP_LOADED:-}" == "1" ]]; then return 0; fi
_OPS_CORE_CLEANUP_LOADED=1

cleanup_pid_is_alive() {
  local pid="${1:-}"
  [[ -n "${pid}" && "${pid}" =~ ^[0-9]+$ ]] || return 1
  kill -0 "${pid}" 2>/dev/null
}

cleanup_read_pid() {
  local file="${1:?cleanup_read_pid: file required}"
  tr -d '[:space:]' < "${file}" 2>/dev/null || true
}

cleanup_stale_pid_files() {
  local apply="${1:-false}"
  local count=0 file pid rel

  [[ -d "${OPS_PROJECT_RUN_DIR}" ]] || {
    printf 'none\n'
    return 0
  }

  while IFS= read -r file; do
    [[ -n "${file}" && -f "${file}" ]] || continue
    pid="$(cleanup_read_pid "${file}")"
    cleanup_pid_is_alive "${pid}" && continue
    rel="${file#${OPS_PROJECT_ROOT}/}"
    if [[ "${apply}" == "true" ]]; then
      rm -f "${file}"
      printf 'removed stale pid: %s\n' "${rel}"
    else
      printf 'stale pid: %s%s\n' "${rel}" "$([[ -n "${pid}" ]] && printf ' (%s)' "${pid}")"
    fi
    count=$((count + 1))
  done < <(find "${OPS_PROJECT_RUN_DIR}" -type f -name '*.pid' 2>/dev/null | sort)

  [[ "${count}" -gt 0 ]] || printf 'none\n'
  return 0
}

cleanup_old_log_files() {
  local apply="${1:-false}" days="${2:-}"
  local count=0 file rel

  [[ -n "${days}" ]] || return 0
  [[ "${days}" =~ ^[0-9]+$ ]] || die "--logs-older-than requires a day count" 2
  [[ -d "${OPS_PROJECT_LOG_DIR}" ]] || {
    printf 'none\n'
    return 0
  }

  while IFS= read -r file; do
    [[ -n "${file}" && -f "${file}" ]] || continue
    rel="${file#${OPS_PROJECT_ROOT}/}"
    if [[ "${apply}" == "true" ]]; then
      rm -f "${file}"
      printf 'removed old log: %s\n' "${rel}"
    else
      printf 'old log: %s\n' "${rel}"
    fi
    count=$((count + 1))
  done < <(find "${OPS_PROJECT_LOG_DIR}" -type f -name '*.log' -mtime +"${days}" 2>/dev/null | sort)

  [[ "${count}" -gt 0 ]] || printf 'none\n'
  return 0
}

cleanup_validate_semver() {
  [[ "${1:-}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

cleanup_version_lt() {
  local candidate="${1:-}" minimum="${2:-}" rule="${3:-semver}"
  local candidate_major candidate_minor candidate_patch
  local minimum_major minimum_minor minimum_patch

  cleanup_validate_semver "${candidate}" || return 2
  cleanup_validate_semver "${minimum}" || return 2

  IFS=. read -r candidate_major candidate_minor candidate_patch <<< "${candidate}"
  IFS=. read -r minimum_major minimum_minor minimum_patch <<< "${minimum}"

  case "${rule}" in
    semver) ;;
    patch-first-digit)
      candidate_patch="${candidate_patch:0:1}"
      minimum_patch="${minimum_patch:0:1}"
      ;;
    *) return 2 ;;
  esac

  ((10#${candidate_major} < 10#${minimum_major})) && return 0
  ((10#${candidate_major} > 10#${minimum_major})) && return 1
  ((10#${candidate_minor} < 10#${minimum_minor})) && return 0
  ((10#${candidate_minor} > 10#${minimum_minor})) && return 1
  ((10#${candidate_patch} < 10#${minimum_patch}))
}

cleanup_local_images() {
  local apply="${1:-false}" repository="${2:-}" minimum="${3:-}" rule="${4:-semver}"
  local output repo tag image_id version ref entry
  local -a candidates=() kept=() skipped=()

  [[ -n "${repository}" ]] || die "Image cleanup requires --repository=NAME" 2
  [[ "${repository}" =~ ^[A-Za-z0-9._/-]+$ ]] || \
    die "--repository contains unsupported characters" 2
  cleanup_validate_semver "${minimum}" || die "--min-version must be X.Y.Z" 2
  case "${rule}" in
    semver|patch-first-digit) ;;
    *) die "--version-rule must be semver or patch-first-digit" 2 ;;
  esac
  require_bins docker

  if ! output="$(docker images --format '{{.Repository}} {{.Tag}} {{.ID}}')"; then
    die "Could not list local Docker images. Is the Docker daemon available?"
  fi

  while read -r repo tag image_id; do
    [[ -n "${repo:-}" && "${repo}" == "${repository}" ]] || continue
    ref="${repo}:${tag}"
    if [[ "${tag}" == "<none>" ]]; then
      skipped+=("${ref} (untagged)")
      continue
    fi
    if [[ "${tag}" =~ [vV]?([0-9]+\.[0-9]+\.[0-9]+) ]]; then
      version="${BASH_REMATCH[1]}"
      if cleanup_version_lt "${version}" "${minimum}" "${rule}"; then
        candidates+=("${ref} ${image_id} v${version}")
      else
        kept+=("${ref} ${image_id} v${version}")
      fi
    else
      skipped+=("${ref} (no version found)")
    fi
  done <<< "${output}"

  printf 'Repository: %s\n' "${repository}"
  printf 'Minimum version: %s\n' "${minimum}"
  printf 'Version rule: %s\n' "${rule}"
  printf 'Keep: %d, remove: %d, skipped: %d\n' \
    "${#kept[@]}" "${#candidates[@]}" "${#skipped[@]}"

  if [[ "${#candidates[@]}" -eq 0 ]]; then
    printf 'none\n'
    return 0
  fi

  for entry in "${candidates[@]}"; do
    read -r ref image_id version <<< "${entry}"
    if [[ "${apply}" == "true" ]]; then
      docker image rm "${ref}"
      printf 'removed image tag: %s (%s, %s)\n' "${ref}" "${image_id}" "${version}"
    else
      printf 'image candidate: %s (%s, %s)\n' "${ref}" "${image_id}" "${version}"
    fi
  done
}

cleanup_generated_files() {
  local apply="${1:-false}" generated_dir="${OPS_PROJECT_GENERATED_DIR}"
  local count=0 file rel dir

  case "${OPS_PROJECT_STATE_DIR}/" in
    "${OPS_PROJECT_ROOT}/"*) ;;
    *) die "Cleanup state directory is outside the project root: ${OPS_PROJECT_STATE_DIR}" ;;
  esac
  [[ "${generated_dir}" == "${OPS_PROJECT_STATE_DIR}/generated" ]] || \
    die "Refusing unexpected generated-state path: ${generated_dir}"
  [[ ! -L "${OPS_PROJECT_STATE_DIR}" && ! -L "${generated_dir}" ]] || \
    die "Refusing to clean generated state through a symlink"
  [[ -d "${generated_dir}" ]] || {
    printf 'none\n'
    return 0
  }

  while IFS= read -r file; do
    [[ -n "${file}" ]] || continue
    rel="${file#${OPS_PROJECT_ROOT}/}"
    if [[ "${apply}" == "true" ]]; then
      rm -f -- "${file}"
      printf 'removed generated file: %s\n' "${rel}"
    else
      printf 'generated file: %s\n' "${rel}"
    fi
    count=$((count + 1))
  done < <(find "${generated_dir}" \( -type f -o -type l \) -print 2>/dev/null | sort)

  if [[ "${apply}" == "true" ]]; then
    while IFS= read -r dir; do
      [[ -n "${dir}" ]] && rmdir -- "${dir}" 2>/dev/null || true
    done < <(find "${generated_dir}" -mindepth 1 -type d -depth -print 2>/dev/null)
  fi

  [[ "${count}" -gt 0 ]] || printf 'none\n'
  return 0
}

return 0
