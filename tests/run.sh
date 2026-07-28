#!/usr/bin/env bash
# Run all ops package smoke tests.
#
# Usage (from repo root):
#   bash tests/run.sh
#
# Requires: bash 4+, jq, yq

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/harness.sh
source "${SCRIPT_DIR}/lib/harness.sh"

printf 'ops smoke tests\n'
printf 'repo: %s\n\n' "${OPS_REPO_ROOT}"

# shellcheck source=smoke/cli.bash
source "${SCRIPT_DIR}/smoke/cli.bash"
# shellcheck source=smoke/doctor.bash
source "${SCRIPT_DIR}/smoke/doctor.bash"
# shellcheck source=smoke/boundaries.bash
source "${SCRIPT_DIR}/smoke/boundaries.bash"
# shellcheck source=smoke/discovery.bash
source "${SCRIPT_DIR}/smoke/discovery.bash"
# shellcheck source=smoke/setup.bash
source "${SCRIPT_DIR}/smoke/setup.bash"
# shellcheck source=smoke/setup-shipping.bash
source "${SCRIPT_DIR}/smoke/setup-shipping.bash"
# shellcheck source=smoke/validate.bash
source "${SCRIPT_DIR}/smoke/validate.bash"
# shellcheck source=smoke/status.bash
source "${SCRIPT_DIR}/smoke/status.bash"
# shellcheck source=smoke/cleanup.bash
source "${SCRIPT_DIR}/smoke/cleanup.bash"
# shellcheck source=smoke/backup.bash
source "${SCRIPT_DIR}/smoke/backup.bash"
# shellcheck source=smoke/package.bash
source "${SCRIPT_DIR}/smoke/package.bash"
# shellcheck source=smoke/monitor.bash
source "${SCRIPT_DIR}/smoke/monitor.bash"
# shellcheck source=smoke/env-discovery.bash
source "${SCRIPT_DIR}/smoke/env-discovery.bash"
# shellcheck source=smoke/setup-check.bash
source "${SCRIPT_DIR}/smoke/setup-check.bash"
# shellcheck source=smoke/healthcheck.bash
source "${SCRIPT_DIR}/smoke/healthcheck.bash"
# shellcheck source=smoke/docker-compose.bash
source "${SCRIPT_DIR}/smoke/docker-compose.bash"
# shellcheck source=smoke/runner-profiles.bash
source "${SCRIPT_DIR}/smoke/runner-profiles.bash"
# shellcheck source=smoke/container-pipeline.bash
source "${SCRIPT_DIR}/smoke/container-pipeline.bash"
# shellcheck source=smoke/shipping.bash
source "${SCRIPT_DIR}/smoke/shipping.bash"
# shellcheck source=smoke/libs.bash
source "${SCRIPT_DIR}/smoke/libs.bash"

suite_cli
suite_doctor
suite_boundaries
suite_discovery
suite_setup
suite_setup_shipping
suite_validate
suite_status
suite_cleanup
suite_backup
suite_package
suite_monitor
suite_env_discovery
suite_setup_check
suite_healthcheck
suite_docker_compose
suite_runner_profiles
suite_container_pipeline
suite_shipping
suite_libs

harness_summary
