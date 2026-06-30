#!/usr/bin/env bash
# Package command smoke tests.

suite_package() {
  local root json install_prefix install_output embedded_root embedded_output
  root="$(fixture_copy config-only)"

  assert_ok "package status exits 0" \
    ops_run "${root}" package status

  json="$(OPS_PROJECT_ROOT="${root}" OPS_CORE_ROOT="${OPS_CORE_ROOT}" OPS_PLAIN=true CI=true OPS_NON_INTERACTIVE=true \
    bash "${OPS_CORE_ROOT}/main.sh" package status --json)"
  assert_eq "package status json has package root" "true" "$(jq -r '(.package_root | length) > 0' <<< "${json}")"

  install_prefix="$(mktemp -d "${TMPDIR:-/tmp}/ops-install-prefix-XXXXXX")"
  HARNESS_FIXTURES+=("${install_prefix}")
  install_output="$(OPS_PROJECT_ROOT="${OPS_REPO_ROOT}" OPS_CORE_ROOT="${OPS_CORE_ROOT}" OPS_PLAIN=true CI=true OPS_NON_INTERACTIVE=true \
    bash "${OPS_CORE_ROOT}/main.sh" install --dry-run --prefix "${install_prefix}")"
  assert_eq "package-local install dry-run uses package source" "true" \
    "$(grep -F "Install source: ${OPS_REPO_ROOT}" <<< "${install_output}" >/dev/null && printf true || printf false)"

  assert_eq "package shell files use LF line endings" "" \
    "$(grep -RIl $'\r' "${OPS_REPO_ROOT}/core" "${OPS_REPO_ROOT}/tests" "${OPS_REPO_ROOT}/setup" 2>/dev/null || true)"

  embedded_root="$(mktemp -d "${TMPDIR:-/tmp}/ops-embedded-project-XXXXXX")"
  HARNESS_FIXTURES+=("${embedded_root}")
  mkdir -p "${embedded_root}/.ops" "${embedded_root}/app"
  ln -s "${OPS_REPO_ROOT}/core" "${embedded_root}/.ops/core"
  cp "${OPS_REPO_ROOT}/setup" "${embedded_root}/.ops/setup"
  printf 'print("hello")\n' > "${embedded_root}/app/manage.py"
  assert_ok "embedded package setup creates project launcher" \
    bash "${embedded_root}/.ops/setup"
  assert_file_exists "embedded package setup writes project ops.sh" \
    "${embedded_root}/ops.sh"
  embedded_output="$(cd "${embedded_root}" && OPS_PLAIN=true CI=true OPS_NON_INTERACTIVE=true \
    bash ./ops.sh setup --dry-run)"
  assert_eq "generated project launcher scans parent project root" "true" \
    "$(grep -F "id: app" <<< "${embedded_output}" >/dev/null && printf true || printf false)"
}
