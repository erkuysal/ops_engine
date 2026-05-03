#!/usr/bin/env bash
# .ops override: delegate userengine start to its own scripts/start.sh
# This avoids the cross-shell path issues with `go run` via Windows Go

set -euo pipefail

cd "${OPS_SVC_PATH:?OPS_SVC_PATH not set}"

# Export log dir for the service script
export USERENGINE_LOG_DIR="${OPS_PROJECT_LOG_DIR:-${OPS_PROJECT_ROOT}/.ops.project/logs/userengine}"
mkdir -p "$USERENGINE_LOG_DIR"

# Start services in background and tail logs
if [[ -f scripts/start.sh ]]; then
  # Run userengine start script (starts services via nohup in background)
  ./scripts/start.sh
  
  # Wait for log files to appear
  waited=0
  while [[ ! -f "$USERENGINE_LOG_DIR/gateway.log" ]] && [[ $waited -lt 10 ]]; do
    sleep 0.3
    waited=$((waited + 1))
  done
  
  # Tail the logs so terminal stays live (Ctrl+C detaches but services keep running)
  echo ""
  echo "[INFO] Following UserEngine logs (Ctrl+C to detach, services continue running):"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  # tail -F: follows by name, handles file rotation
  tail -F "$USERENGINE_LOG_DIR"/gateway.log "$USERENGINE_LOG_DIR"/api.log \
           "$USERENGINE_LOG_DIR"/sweeper.log "$USERENGINE_LOG_DIR"/debouncer.log 2>/dev/null || true
else
  echo "[ERROR] UserEngine scripts/start.sh not found at $(pwd)/scripts/start.sh"
  exit 1
fi
