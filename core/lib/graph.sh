#!/usr/bin/env bash
# .ops-core/lib/graph.sh — Dependency graph resolver and cycle detection.
#
# Requires: manifest.sh, logger.sh

set -euo pipefail
if [[ "${_OPS_CORE_GRAPH_LOADED:-}" == "1" ]]; then return 0; fi
_OPS_CORE_GRAPH_LOADED=1

# Run a DFS to detect cycles in the depends_on graph.
# Exits with code 4 if a cycle is found.
graph_cycle_check() {
  local all_ids=()
  mapfile -t all_ids < <(manifest_list_services | sort 2>/dev/null || true)
  
  # state: 0=unvisited, 1=visiting, 2=visited
  local -A state=()
  for id in "${all_ids[@]+"${all_ids[@]}"}"; do state["$id"]=0; done
  
  local cycle_path=()
  
  _dfs_check() {
    local node="$1"
    state["$node"]=1
    cycle_path+=("$node")
    
    local deps=()
    mapfile -t deps < <(manifest_get_service_list_field "$node" depends_on 2>/dev/null || true)
    
    local dep
    for dep in "${deps[@]+"${deps[@]}"}"; do
      if [[ -z "$dep" || "$dep" == "null" ]]; then continue; fi
      
      if [[ "${state[$dep]:-0}" == 1 ]]; then
        # Cycle detected!
        cycle_path+=("$dep")
        ops_error "Cycle detected in depends_on graph!"
        local path_str="${cycle_path[*]}"
        ops_error "Path: ${path_str// / -> }"
        return 1
      elif [[ "${state[$dep]:-0}" == 0 ]]; then
        if ! _dfs_check "$dep"; then return 1; fi
      fi
    done
    
    state["$node"]=2
    local last_idx=$((${#cycle_path[@]} - 1))
    unset "cycle_path[$last_idx]"
    return 0
  }
  
  local id
  for id in "${all_ids[@]+"${all_ids[@]}"}"; do
    if [[ "${state[$id]}" == 0 ]]; then
      if ! _dfs_check "$id"; then exit 4; fi
    fi
  done
  
  return 0
}

# Returns a space-separated list of services in topological order.
# Order: Dependencies first, then the service itself.
# Usage: graph_topo_sort <service_id | --all>
graph_topo_sort() {
  local target="${1:?graph_topo_sort: target required}"
  local -A visited=()
  local sorted=()

  local nodes_to_visit=()
  if [[ "$target" == "--all" ]]; then
    mapfile -t nodes_to_visit < <(manifest_list_services | sort 2>/dev/null || true)
  else
    nodes_to_visit=("$target")
  fi
  
  _visit_topo() {
    local node="$1"
    if [[ -n "${visited[$node]:-}" ]]; then return; fi
    visited["$node"]=1
    
    local deps=()
    # Sort alphabetically to guarantee deterministic resolution
    mapfile -t deps < <(manifest_get_service_list_field "$node" depends_on 2>/dev/null | sort || true)
    
    local dep
    for dep in "${deps[@]+"${deps[@]}"}"; do
      [[ -z "$dep" || "$dep" == "null" ]] && continue
      _visit_topo "$dep"
    done
    
    sorted+=("$node")
  }
  
  local n
  for n in "${nodes_to_visit[@]+"${nodes_to_visit[@]}"}"; do
    _visit_topo "$n"
  done
  
  echo "${sorted[@]}"
}

# Returns a space-separated list of services in reverse topological order.
# Order: Service itself, then its dependencies (used for teardown).
# Usage: graph_reverse_topo_sort <service_id | --all>
graph_reverse_topo_sort() {
  local target="$1"
  local fwd=()
  read -ra fwd <<< "$(graph_topo_sort "$target")"
  
  local rev=()
  local i
  for (( i=${#fwd[@]}-1; i>=0; i-- )); do
    rev+=("${fwd[$i]}")
  done
  echo "${rev[@]}"
}
