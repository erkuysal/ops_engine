#!/usr/bin/env bash

probe_django_stack_id() {
  printf 'django'
}

probe_django_score_dir() {
  local dir="$1"
  local score=0
  [[ -f "${dir}/manage.py" ]] && score=$((score + 3))
  [[ -f "${dir}/requirements.txt" ]] && score=$((score + 2))
  [[ -f "${dir}/Pipfile" ]] && score=$((score + 2))
  [[ -f "${dir}/pyproject.toml" ]] && score=$((score + 1))
  [[ -f "${dir}/setup.py" ]] && score=$((score + 1))
  printf '%d' "${score}"
}
