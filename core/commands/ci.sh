#!/usr/bin/env bash
# .ops/core/commands/ci.sh - Basic CI configuration and credential readiness.

set -euo pipefail

_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_SELF_DIR}/../lib/init.sh"
source "${_SELF_DIR}/../lib/logger.sh"
source "${_SELF_DIR}/../lib/setup.sh"

SUBCMD="${1:-show}"
case "${SUBCMD}" in
  setup|show|doctor|env|connect|secrets|ssh-key|help|--help|-h) shift || true ;;
  *) SUBCMD="show" ;;
esac

APPLY=false
INTERACTIVE=false
PROFILE=""
KEY_PATH=""
KEY_COMMENT="github-actions-deploy"
REMOTE_COMMAND=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply) APPLY=true ;;
    --interactive) INTERACTIVE=true ;;
    --profile=*) PROFILE="${1#*=}" ;;
    --profile)
      [[ $# -ge 2 ]] || die "--profile requires a value" 2
      PROFILE="$2"
      shift
      ;;
    --path=*) KEY_PATH="${1#*=}" ;;
    --path)
      [[ $# -ge 2 ]] || die "--path requires a value" 2
      KEY_PATH="$2"
      shift
      ;;
    --comment=*) KEY_COMMENT="${1#*=}" ;;
    --comment)
      [[ $# -ge 2 ]] || die "--comment requires a value" 2
      KEY_COMMENT="$2"
      shift
      ;;
    --command=*) REMOTE_COMMAND="${1#*=}" ;;
    --command)
      [[ $# -ge 2 ]] || die "--command requires a value" 2
      REMOTE_COMMAND="$2"
      shift
      ;;
    --help|-h)
      SUBCMD="help"
      ;;
    *) die "Unknown flag: $1. Use --help." 2 ;;
  esac
  shift
done

[[ -n "${PROFILE}" ]] || PROFILE="$(setup_default_profile)"

OPS_CI_CONFIG_FILE="${OPS_PROJECT_CONFIG_DIR}/ci.json"

_usage_ci() {
  cat <<'EOF'
Usage: ops ci setup [--interactive] [--apply] [--profile NAME]
       ops ci show
       ops ci doctor
       ops ci env [--apply]
       ops ci connect [--apply] [--command CMD]
       ops ci secrets
       ops ci ssh-key [--path PATH] [--comment TEXT] [--apply]

Stores non-secret CI/server metadata in:
  .ops.project/config/ci.json

Local secrets can live in:
  .ops.project/secrets/ci.env

GitHub Actions remains optional. ops can print GitHub secret setup guidance, but
the primary flow can use your own env file and SSH connection.
EOF
}

_prompt_ci_value() {
  local label="$1" default="${2:-}" value
  if [[ -n "${default}" ]]; then
    printf '%s [%s]: ' "${label}" "${default}" >&2
  else
    printf '%s: ' "${label}" >&2
  fi
  read -r value
  printf '%s' "${value:-${default}}"
}

_git_remote_url() {
  if command -v git >/dev/null 2>&1; then
    git -C "${OPS_PROJECT_ROOT}" remote get-url origin 2>/dev/null || true
  fi
}

_project_name() {
  local name
  name="$(basename "${OPS_PROJECT_ROOT}")"
  if [[ -f "${OPS_PROJECT_CONFIG_DIR}/project.json" ]]; then
    name="$(jq -r '.name // empty' "${OPS_PROJECT_CONFIG_DIR}/project.json" 2>/dev/null || true)"
  fi
  [[ -n "${name}" ]] && printf '%s' "${name}" || basename "${OPS_PROJECT_ROOT}"
}

_existing_ci_get() {
  local expr="$1" default="${2:-}"
  local value
  if [[ -f "${OPS_CI_CONFIG_FILE}" ]]; then
    value="$(jq -r "${expr} // \"\"" "${OPS_CI_CONFIG_FILE}" 2>/dev/null | sed -n '1p')"
    [[ -n "${value}" && "${value}" != "null" ]] && printf '%s' "${value}" || printf '%s' "${default}"
  else
    printf '%s' "${default}"
  fi
}

_generate_ci_config_json() {
  require_bins jq

  local project_name repo_url docker_namespace docker_registry image_prefix
  local deploy_host deploy_user deploy_path deploy_key_path
  local local_env_file
  local workflow_server workflow_desktop default_branch
  local github_secrets docker_secrets deploy_secrets

  project_name="$(_existing_ci_get '.project.name' "$(_project_name)")"
  repo_url="$(_existing_ci_get '.github.repository' "$(_git_remote_url)")"
  docker_namespace="$(_existing_ci_get '.docker.namespace' '')"
  docker_registry="$(_existing_ci_get '.docker.registry' 'docker.io')"
  image_prefix="$(_existing_ci_get '.docker.image_prefix' "${project_name}")"
  deploy_host="$(_existing_ci_get '.deploy.host' '')"
  deploy_user="$(_existing_ci_get '.deploy.user' '')"
  deploy_path="$(_existing_ci_get '.deploy.path' '')"
  deploy_key_path="$(_existing_ci_get '.deploy.ssh_key_path' "${HOME}/.ssh/github_actions_deploy")"
  local_env_file="$(_existing_ci_get '.secrets.local_env_file' '.ops.project/secrets/ci.env')"
  workflow_server="$(_existing_ci_get '.github.workflows.server' 'ci-cd.yml')"
  workflow_desktop="$(_existing_ci_get '.github.workflows.desktop' 'desktop-release.yml')"
  default_branch="$(_existing_ci_get '.github.default_branch' 'root')"

  if [[ "${INTERACTIVE}" == "true" ]]; then
    project_name="$(_prompt_ci_value "Project name" "${project_name}")"
    repo_url="$(_prompt_ci_value "GitHub repository URL" "${repo_url}")"
    default_branch="$(_prompt_ci_value "Default branch" "${default_branch}")"
    docker_registry="$(_prompt_ci_value "Docker registry" "${docker_registry}")"
    docker_namespace="$(_prompt_ci_value "Docker namespace/user" "${docker_namespace}")"
    image_prefix="$(_prompt_ci_value "Docker image prefix/repository" "${image_prefix}")"
    deploy_host="$(_prompt_ci_value "Deploy host" "${deploy_host}")"
    deploy_user="$(_prompt_ci_value "Deploy user" "${deploy_user}")"
    deploy_path="$(_prompt_ci_value "Deploy path on server" "${deploy_path}")"
    deploy_key_path="$(_prompt_ci_value "Local deploy SSH private key path" "${deploy_key_path}")"
    local_env_file="$(_prompt_ci_value "Local CI/deploy env file" "${local_env_file}")"
    workflow_server="$(_prompt_ci_value "Server workflow file" "${workflow_server}")"
    workflow_desktop="$(_prompt_ci_value "Desktop workflow file" "${workflow_desktop}")"
  fi

  github_secrets="$(jq -n '{
    docker_username: "DOCKER_USERNAME",
    docker_password: "DOCKER_PASSWORD",
    deploy_host: "DEPLOY_HOST",
    deploy_user: "DEPLOY_USER",
    deploy_ssh_key: "DEPLOY_SSH_KEY",
    deploy_path: "DEPLOY_PATH"
  }')"
  docker_secrets="$(jq -n '{username_env: "DOCKER_USERNAME", password_env: "DOCKER_PASSWORD"}')"
  deploy_secrets="$(jq -n '{ssh_private_key_secret: "DEPLOY_SSH_KEY"}')"

  jq -n \
    --arg generated_at "$(ops_timestamp)" \
    --arg project_name "${project_name}" \
    --arg repo_url "${repo_url}" \
    --arg default_branch "${default_branch}" \
    --arg workflow_server "${workflow_server}" \
    --arg workflow_desktop "${workflow_desktop}" \
    --arg docker_registry "${docker_registry}" \
    --arg docker_namespace "${docker_namespace}" \
    --arg image_prefix "${image_prefix}" \
    --arg deploy_host "${deploy_host}" \
    --arg deploy_user "${deploy_user}" \
    --arg deploy_path "${deploy_path}" \
    --arg deploy_key_path "${deploy_key_path}" \
    --arg local_env_file "${local_env_file}" \
    --argjson github_secrets "${github_secrets}" \
    --argjson docker_secrets "${docker_secrets}" \
    --argjson deploy_secrets "${deploy_secrets}" \
    '{
      version: "1",
      generated_at: $generated_at,
      source: "ops_ci_setup",
      project: {name: $project_name},
      github: {
        repository: $repo_url,
        default_branch: $default_branch,
        workflows: {server: $workflow_server, desktop: $workflow_desktop},
        secrets: $github_secrets
      },
      docker: {
        registry: $docker_registry,
        namespace: $docker_namespace,
        image_prefix: $image_prefix,
        credentials: $docker_secrets
      },
      deploy: {
        host: $deploy_host,
        user: $deploy_user,
        path: $deploy_path,
        ssh_key_path: $deploy_key_path,
        credentials: $deploy_secrets
      },
      secrets: {
        local_env_file: $local_env_file,
        required_env: ["DEPLOY_HOST", "DEPLOY_USER", "DEPLOY_PATH"],
        optional_env: ["DEPLOY_SSH_KEY_PATH", "DOCKER_USERNAME", "DOCKER_PASSWORD"]
      }
    }'
}

_ci_config_json() {
  if [[ -f "${OPS_CI_CONFIG_FILE}" ]]; then
    cat "${OPS_CI_CONFIG_FILE}"
  else
    _generate_ci_config_json
  fi
}

_write_ci_config() {
  local config_json="$1" tmp
  ensure_dir "${OPS_PROJECT_CONFIG_DIR}"
  tmp="$(mktemp)"
  printf '%s\n' "${config_json}" > "${tmp}"
  mv "${tmp}" "${OPS_CI_CONFIG_FILE}"
  ops_ok "Wrote ${OPS_CI_CONFIG_FILE#${OPS_PROJECT_ROOT}/}"
}

_expand_path() {
  local path="$1"
  path="${path/#\~/${HOME}}"
  case "${path}" in
    /*) printf '%s' "${path}" ;;
    *) printf '%s/%s' "${OPS_PROJECT_ROOT}" "${path}" ;;
  esac
}

_ci_local_env_file() {
  local config_json
  config_json="$(_ci_config_json)"
  jq -r '.secrets.local_env_file // ".ops.project/secrets/ci.env"' <<< "${config_json}"
}

_load_ci_env() {
  local env_file expanded
  env_file="$(_ci_local_env_file)"
  expanded="$(_expand_path "${env_file}")"
  [[ -f "${expanded}" ]] || return 1
  set -a
  # shellcheck disable=SC1090
  source <(sed 's/\r$//' "${expanded}")
  set +a
  return 0
}

_ci_value() {
  local json_expr="$1" env_name="$2" default="${3:-}" value=""
  value="${!env_name:-}"
  if [[ -n "${value}" ]]; then
    printf '%s' "${value}"
    return 0
  fi
  value="$(jq -r "${json_expr} // \"\"" <<< "$(_ci_config_json)" 2>/dev/null || true)"
  [[ -n "${value}" && "${value}" != "null" ]] && printf '%s' "${value}" || printf '%s' "${default}"
}

_print_ci_summary() {
  local config_json="$1"
  jq -r '
    "Project: " + (.project.name // "") ,
    "Repository: " + (.github.repository // "<unset>"),
    "Default branch: " + (.github.default_branch // "<unset>"),
    "Server workflow: " + (.github.workflows.server // "<unset>"),
    "Desktop workflow: " + (.github.workflows.desktop // "<unset>"),
    "Docker registry: " + (.docker.registry // "<unset>"),
    "Docker namespace: " + (.docker.namespace // "<unset>"),
    "Docker image prefix: " + (.docker.image_prefix // "<unset>"),
    "Deploy host: " + (.deploy.host // "<unset>"),
    "Deploy user: " + (.deploy.user // "<unset>"),
    "Deploy path: " + (.deploy.path // "<unset>"),
    "Deploy key path: " + (.deploy.ssh_key_path // "<unset>"),
    "Local env file: " + (.secrets.local_env_file // ".ops.project/secrets/ci.env"),
    "Expected GitHub secrets: " + ((.github.secrets | to_entries | map(.value) | unique | join(", ")) // "")
  ' <<< "${config_json}"
}

_is_unset() {
  local value="${1:-}"
  [[ -z "${value}" || "${value}" == "null" || "${value}" == "<unset>" ]]
}

_doctor_ci() {
  require_bins jq
  local config_json fail=0 warn=0
  config_json="$(_ci_config_json)"

  ops_section "ops ci doctor"
  if _load_ci_env; then
    ops_ok "loaded local CI env: $(_ci_local_env_file)"
  else
    ops_warn "local CI env not found: $(_ci_local_env_file)"
    warn=$((warn + 1))
  fi

  local field value label
  while IFS=$'\t' read -r label value; do
    if _is_unset "${value}"; then
      ops_warn "missing CI config/env: ${label}"
      warn=$((warn + 1))
    else
      ops_ok "${label}: ${value}"
    fi
  done < <(
    printf '.github.repository\t%s\n' "$(_ci_value '.github.repository' GITHUB_REPOSITORY)"
    printf '.docker.namespace\t%s\n' "$(_ci_value '.docker.namespace' DOCKER_NAMESPACE)"
    printf '.docker.image_prefix\t%s\n' "$(_ci_value '.docker.image_prefix' DOCKER_IMAGE_PREFIX)"
    printf '.deploy.host\t%s\n' "$(_ci_value '.deploy.host' DEPLOY_HOST)"
    printf '.deploy.user\t%s\n' "$(_ci_value '.deploy.user' DEPLOY_USER)"
    printf '.deploy.path\t%s\n' "$(_ci_value '.deploy.path' DEPLOY_PATH)"
    printf '.deploy.ssh_key_path\t%s\n' "${DEPLOY_SSH_KEY_PATH:-$(jq -r '.deploy.ssh_key_path // ""' <<< "${config_json}")}"
  )

  local key_path
  key_path="${DEPLOY_SSH_KEY_PATH:-$(jq -r '.deploy.ssh_key_path // ""' <<< "${config_json}")}"
  if [[ -n "${key_path}" && -f "$(_expand_path "${key_path}")" ]]; then
    ops_ok "local deploy SSH key exists"
  else
    ops_warn "local deploy SSH key not found: ${key_path:-<unset>}"
    warn=$((warn + 1))
  fi

  if command -v git >/dev/null 2>&1; then ops_ok "git: $(command -v git)"; else ops_warn "git not found"; warn=$((warn + 1)); fi
  if command -v ssh >/dev/null 2>&1; then ops_ok "ssh: $(command -v ssh)"; else ops_warn "ssh not found"; warn=$((warn + 1)); fi
  if command -v docker >/dev/null 2>&1; then ops_ok "docker: $(command -v docker)"; else ops_warn "docker not found"; warn=$((warn + 1)); fi
  if command -v gh >/dev/null 2>&1; then ops_ok "gh: $(command -v gh)"; else ops_warn "GitHub CLI (gh) not found; workflow trigger checks will be manual"; warn=$((warn + 1)); fi

  local server_workflow desktop_workflow
  server_workflow="$(jq -r '.github.workflows.server // ""' <<< "${config_json}")"
  desktop_workflow="$(jq -r '.github.workflows.desktop // ""' <<< "${config_json}")"
  if [[ -n "${server_workflow}" && -f "${OPS_PROJECT_ROOT}/.github/workflows/${server_workflow}" ]]; then
    ops_ok "server workflow exists: .github/workflows/${server_workflow}"
  else
    ops_warn "server workflow missing: .github/workflows/${server_workflow:-<unset>}"
    warn=$((warn + 1))
  fi
  if [[ -n "${desktop_workflow}" && -f "${OPS_PROJECT_ROOT}/.github/workflows/${desktop_workflow}" ]]; then
    ops_ok "desktop workflow exists: .github/workflows/${desktop_workflow}"
  else
    ops_warn "desktop workflow missing: .github/workflows/${desktop_workflow:-<unset>}"
    warn=$((warn + 1))
  fi

  printf '\nExpected GitHub Actions secrets\n'
  jq -r '.github.secrets | to_entries[] | "  " + .value' <<< "${config_json}" | sort -u

  printf '\nCI doctor: %d failed, %d warnings\n' "${fail}" "${warn}"
  return "${fail}"
}

_write_ci_gitignore() {
  local file="${OPS_PROJECT_STATE_DIR}/.gitignore"
  mkdir -p "${OPS_PROJECT_STATE_DIR}"
  if [[ ! -f "${file}" ]]; then
    {
      printf '# Generated by ops. .ops.project is local project state.\n'
      printf 'secrets/\n'
      printf 'logs/\n'
      printf 'run/\n'
    } > "${file}"
    ops_ok "Wrote ${file#${OPS_PROJECT_ROOT}/}"
  elif ! grep -qx 'secrets/' "${file}" 2>/dev/null; then
    printf 'secrets/\n' >> "${file}"
    ops_ok "Updated ${file#${OPS_PROJECT_ROOT}/}"
  fi
}

_ci_env_template() {
  cat <<'EOF'
# Local ops CI/deploy secrets and server configuration.
# This file is local-only. Do not commit it.

DEPLOY_HOST=
DEPLOY_USER=
DEPLOY_PATH=
DEPLOY_SSH_KEY_PATH=

DOCKER_USERNAME=
DOCKER_PASSWORD=
DOCKER_REGISTRY=docker.io
DOCKER_NAMESPACE=

# Optional GitHub mirror. GitHub Actions is not required for ops local CI.
GITHUB_REPOSITORY=
GITHUB_DEFAULT_BRANCH=
EOF
}

_ci_env_init() {
  local env_file expanded
  env_file="$(_ci_local_env_file)"
  expanded="$(_expand_path "${env_file}")"

  ops_section "ops ci env"
  ops_info "Local env file: ${expanded}"

  if [[ -f "${expanded}" ]]; then
    ops_ok "env file already exists"
  elif [[ "${APPLY}" == "true" ]]; then
    mkdir -p "$(dirname "${expanded}")"
    _ci_env_template > "${expanded}"
    chmod 600 "${expanded}" 2>/dev/null || true
    _write_ci_gitignore
    ops_ok "Created ${env_file}"
  else
    ops_info "Preview only. Use --apply to create the local env template."
  fi

  if [[ -f "${expanded}" ]]; then
    printf '\nConfigured variables:\n'
    grep -E '^[A-Za-z_][A-Za-z0-9_]*=' "${expanded}" | sed 's/=.*$/=<set or empty>/' | sed 's/^/  /'
  fi
}

_ci_connect() {
  require_bins jq
  local host user path key_path command ssh_args=()
  _load_ci_env || true
  host="$(_ci_value '.deploy.host' DEPLOY_HOST)"
  user="$(_ci_value '.deploy.user' DEPLOY_USER)"
  path="$(_ci_value '.deploy.path' DEPLOY_PATH)"
  key_path="${DEPLOY_SSH_KEY_PATH:-$(_ci_value '.deploy.ssh_key_path' DEPLOY_SSH_KEY_PATH)}"
  command="${REMOTE_COMMAND:-cd $(_shell_escape "${path}") && pwd && docker --version && docker compose version}"

  ops_section "ops ci connect"
  if _is_unset "${host}" || _is_unset "${user}" || _is_unset "${path}"; then
    die "Missing DEPLOY_HOST, DEPLOY_USER, or DEPLOY_PATH. Run: ops ci env --apply" 2
  fi

  if [[ -n "${key_path}" && "${key_path}" != "null" ]]; then
    key_path="$(_expand_path "${key_path}")"
    ssh_args+=("-i" "${key_path}")
  fi
  ssh_args+=("${user}@${host}" "${command}")

  printf 'SSH target: %s@%s\n' "${user}" "${host}"
  printf 'Deploy path: %s\n' "${path}"
  printf 'Command: %s\n' "${command}"
  if [[ "${APPLY}" != "true" ]]; then
    printf '\nPreview command:\n  ssh'
    local arg
    for arg in "${ssh_args[@]}"; do printf ' %s' "$(_shell_escape "${arg}")"; done
    printf '\n'
    ops_info "Preview only. Use --apply to run the SSH check."
    return 0
  fi

  ssh "${ssh_args[@]}"
}

_print_secret_setup() {
  require_bins jq
  local config_json deploy_host deploy_user deploy_path key_path
  config_json="$(_ci_config_json)"
  deploy_host="$(jq -r '.deploy.host // ""' <<< "${config_json}")"
  deploy_user="$(jq -r '.deploy.user // ""' <<< "${config_json}")"
  deploy_path="$(jq -r '.deploy.path // ""' <<< "${config_json}")"
  key_path="$(jq -r '.deploy.ssh_key_path // ""' <<< "${config_json}")"

  ops_section "ops ci secrets"
  printf 'Expected GitHub Actions secrets:\n'
  jq -r '.github.secrets | to_entries[] | "  - " + .value' <<< "${config_json}" | sort -u

  printf '\nGitHub CLI setup commands\n'
  printf '  gh secret set DOCKER_USERNAME\n'
  printf '  gh secret set DOCKER_PASSWORD\n'
  if [[ -n "${deploy_host}" ]]; then printf '  printf %%s %s | gh secret set DEPLOY_HOST\n' "$(_shell_escape "${deploy_host}")"; else printf '  gh secret set DEPLOY_HOST\n'; fi
  if [[ -n "${deploy_user}" ]]; then printf '  printf %%s %s | gh secret set DEPLOY_USER\n' "$(_shell_escape "${deploy_user}")"; else printf '  gh secret set DEPLOY_USER\n'; fi
  if [[ -n "${deploy_path}" ]]; then printf '  printf %%s %s | gh secret set DEPLOY_PATH\n' "$(_shell_escape "${deploy_path}")"; else printf '  gh secret set DEPLOY_PATH\n'; fi
  if [[ -n "${key_path}" ]]; then printf '  gh secret set DEPLOY_SSH_KEY < %s\n' "$(_shell_escape "$(_expand_path "${key_path}")")"; else printf '  gh secret set DEPLOY_SSH_KEY < ~/.ssh/github_actions_deploy\n'; fi

  printf '\nServer public key install\n'
  if [[ -n "${deploy_user}" && -n "${deploy_host}" && -n "${key_path}" ]]; then
    printf '  ssh-copy-id -i %s.pub %s@%s\n' "$(_shell_escape "$(_expand_path "${key_path}")")" "${deploy_user}" "${deploy_host}"
  else
    printf '  ssh-copy-id -i ~/.ssh/github_actions_deploy.pub <deploy-user>@<deploy-host>\n'
  fi

  printf '\nNotes\n'
  printf '  ops does not store secret values. Use GitHub Secrets for tokens/private keys.\n'
}

_shell_escape() {
  printf '%q' "$1"
}

_ssh_key_path_from_config() {
  local config_json
  config_json="$(_ci_config_json)"
  jq -r '.deploy.ssh_key_path // ""' <<< "${config_json}"
}

_ssh_key_setup() {
  local key_path expanded public_path
  key_path="${KEY_PATH:-$(_ssh_key_path_from_config)}"
  [[ -n "${key_path}" ]] || key_path="${HOME}/.ssh/github_actions_deploy"
  expanded="$(_expand_path "${key_path}")"
  public_path="${expanded}.pub"

  ops_section "ops ci ssh-key"
  ops_info "Private key path: ${expanded}"
  ops_info "Public key path: ${public_path}"
  ops_info "Comment: ${KEY_COMMENT}"

  if [[ -f "${expanded}" ]]; then
    ops_ok "Private key already exists"
  elif [[ "${APPLY}" == "true" ]]; then
    if ! command -v ssh-keygen >/dev/null 2>&1; then
      die "ssh-keygen not found" 2
    fi
    mkdir -p "$(dirname "${expanded}")"
    chmod 700 "$(dirname "${expanded}")" 2>/dev/null || true
    ssh-keygen -t ed25519 -C "${KEY_COMMENT}" -f "${expanded}" -N ""
    chmod 600 "${expanded}" 2>/dev/null || true
    ops_ok "Generated deploy SSH key"
  else
    ops_info "Preview only. Use --apply to generate the key."
  fi

  if [[ -f "${public_path}" ]]; then
    printf '\nPublic key to install on server:\n'
    sed 's/^/  /' "${public_path}"
  else
    printf '\nPublic key not available yet.\n'
  fi

  printf '\nNext:\n'
  printf '  ops ci secrets\n'
}

case "${SUBCMD}" in
  help|--help|-h)
    _usage_ci
    ;;
  setup)
    require_bins jq
    ops_section "ops ci setup"
    config_json="$(_generate_ci_config_json)"
    _print_ci_summary "${config_json}"
    printf '\n'
    if [[ "${APPLY}" == "true" ]]; then
      _write_ci_config "${config_json}"
    else
      ops_info "Preview only. Use --apply to write .ops.project/config/ci.json."
    fi
    ;;
  show)
    require_bins jq
    ops_section "ops ci show"
    config_json="$(_ci_config_json)"
    _print_ci_summary "${config_json}"
    if [[ ! -f "${OPS_CI_CONFIG_FILE}" ]]; then
      printf '\n'
      ops_info "No .ops.project/config/ci.json yet. Run: ops ci setup --interactive --apply"
    fi
    ;;
  doctor)
    _doctor_ci
    ;;
  env)
    _ci_env_init
    ;;
  connect)
    _ci_connect
    ;;
  secrets)
    _print_secret_setup
    ;;
  ssh-key)
    _ssh_key_setup
    ;;
  *)
    die "Unknown ci subcommand: ${SUBCMD}" 2
    ;;
esac
