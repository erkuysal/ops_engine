#!/usr/bin/env bash
# Build deterministic delivery plans from .ops.project/config/shipping.json.

set -euo pipefail
if [[ "${_OPS_CORE_SHIPPING_LOADED:-}" == "1" ]]; then return 0; fi
_OPS_CORE_SHIPPING_LOADED=1

OPS_SHIPPING_CONFIG_FILE="${OPS_SHIPPING_CONFIG_FILE:-${OPS_PROJECT_CONFIG_DIR}/shipping.json}"

shipping_expand_config_path() {
  local path="$1"
  path="${path/#\~/${HOME}}"
  case "${path}" in
    /*) printf '%s' "${path}" ;;
    *) printf '%s/%s' "${OPS_PROJECT_ROOT}" "${path}" ;;
  esac
}

shipping_validate_config() {
  local file="$1" duplicate_ids invalid_dependencies
  [[ -f "${file}" ]] || die "Shipping config not found: ${file}" 2
  jq -e . "${file}" >/dev/null 2>&1 || die "Shipping config is not valid JSON: ${file}" 2

  jq -e '
    .version == 1 and
    (.pipelines | type == "object" and length > 0) and
    ([.pipelines[] | (.jobs | type == "array" and length > 0)] | all) and
    ([.pipelines[].jobs[] |
      (.id | type == "string" and test("^[A-Za-z0-9][A-Za-z0-9._-]*$")) and
      (.uses | IN("docker.compose", "files.sync", "git.checkout", "script")) and
      (if .uses == "docker.compose" then (.compose_files | type == "array" and length > 0)
       elif .uses == "files.sync" then
         (.source | type == "string" and length > 0) and
         (.destination | type == "string" and length > 0)
       elif .uses == "git.checkout" then
         (.repository | type == "string" and length > 0) and
         (.destination | type == "string" and length > 0)
       else (.stages | type == "object" and length > 0)
       end)
    ] | all)
  ' "${file}" >/dev/null || die "Shipping config does not satisfy the required pipeline/job structure: ${file}" 2

  duplicate_ids="$(jq -r '
    .pipelines | to_entries[] |
    .key as $pipeline |
    [.value.jobs[].id] | group_by(.)[] | select(length > 1) |
    "\($pipeline):\(.[0])"
  ' "${file}")"
  [[ -z "${duplicate_ids}" ]] || die "Duplicate shipping job id(s): ${duplicate_ids//$'\n'/, }" 2

  invalid_dependencies="$(jq -r '
    .pipelines | to_entries[] |
    .key as $pipeline |
    [.value.jobs[].id] as $ids |
    .value.jobs[] |
    .id as $job |
    (.depends_on // [])[] |
    . as $dependency |
    select(($ids | index($dependency)) == null) |
    "\($pipeline):\($job)->\($dependency)"
  ' "${file}")"
  [[ -z "${invalid_dependencies}" ]] || die "Unknown shipping job dependency: ${invalid_dependencies//$'\n'/, }" 2

  local default_pipeline
  default_pipeline="$(jq -r '.default_pipeline // empty' "${file}")"
  if [[ -n "${default_pipeline}" ]] && ! jq -e --arg name "${default_pipeline}" '.pipelines[$name] != null' "${file}" >/dev/null; then
    die "default_pipeline does not exist: ${default_pipeline}" 2
  fi
}

shipping_default_pipeline() {
  local file="$1" configured count
  configured="$(jq -r '.default_pipeline // empty' "${file}")"
  if [[ -n "${configured}" ]]; then
    printf '%s' "${configured}"
    return 0
  fi
  count="$(jq '.pipelines | length' "${file}")"
  if [[ "${count}" == "1" ]]; then
    jq -r '.pipelines | keys[0]' "${file}"
    return 0
  fi
  die "Select a shipping pipeline; no default_pipeline is configured." 2
}

shipping_plan_json() {
  local file="$1" pipeline="$2" job_filter="$3" tag="$4" only_stage="$5"
  local build="$6" publish="$7" transfer="$8" deploy="$9" verify="${10}"

  jq -c \
    --arg pipeline "${pipeline}" \
    --arg job_filter "${job_filter}" \
    --arg tag "${tag}" \
    --arg only_stage "${only_stage}" \
    --argjson build "${build}" \
    --argjson publish "${publish}" \
    --argjson transfer "${transfer}" \
    --argjson deploy "${deploy}" \
    --argjson verify "${verify}" '
    def configured($value): $value != null and $value != false;
    def base($job; $pipeline_target): {
      job: $job.id,
      driver: $job.uses,
      target: ($job.target // $pipeline_target // ""),
      depends_on: ($job.depends_on // [])
    };
    def action($job; $pipeline_target; $stage; $operation; $inputs):
      base($job; $pipeline_target) + {
        stage: $stage,
        operation: $operation,
        inputs: $inputs
      };
    def driver_actions($job; $pipeline_target):
      if $job.uses == "docker.compose" then
        (if ($job | has("build")) and $job.build == false then [] else [action($job; $pipeline_target; "build"; "docker.compose.build"; {
            compose_files: $job.compose_files,
            services: ($job.services // []),
            env_files: ($job.env_files // []),
            project_directory: ($job.project_directory // ".")
          })] end)
        + (if ($job | has("publish")) and $job.publish == false then [] else [action($job; $pipeline_target; "publish"; "docker.compose.push"; {
            compose_files: $job.compose_files,
            services: ($job.services // []),
            env_files: ($job.env_files // []),
            project_directory: ($job.project_directory // ".")
          })] end)
        + (if configured($job.transfer) then
             [action($job; $pipeline_target; "transfer"; "docker.compose.transfer"; $job.transfer)]
           else [] end)
        + [action($job; $pipeline_target; "deploy"; "docker.compose.deploy"; {
            compose_files: $job.compose_files,
            services: ($job.services // []),
            remote_path: ($job.remote_path // "")
          })]
        + (if configured($job.verify) then
             [action($job; $pipeline_target; "verify"; "verify"; $job.verify)]
           else [] end)
      elif $job.uses == "files.sync" then
        [action($job; $pipeline_target; "transfer"; "files.sync"; {
          source: $job.source,
          destination: $job.destination,
          method: ($job.method // "rsync")
        })]
        + (if configured($job.deploy) then
             [action($job; $pipeline_target; "deploy"; "files.activate"; $job.deploy)]
           else [] end)
        + (if configured($job.verify) then
             [action($job; $pipeline_target; "verify"; "verify"; $job.verify)]
           else [] end)
      elif $job.uses == "git.checkout" then
        [action($job; $pipeline_target; "transfer"; "git.checkout"; {
          repository: $job.repository,
          ref: (($job.ref // $tag) | gsub("\\{tag\\}"; $tag)),
          destination: $job.destination
        })]
        + (if configured($job.build) then
             [action($job; $pipeline_target; "build"; "git.build"; $job.build)]
           else [] end)
        + (if configured($job.deploy) then
             [action($job; $pipeline_target; "deploy"; "git.deploy"; $job.deploy)]
           else [] end)
        + (if configured($job.verify) then
             [action($job; $pipeline_target; "verify"; "verify"; $job.verify)]
           else [] end)
      else
        ["build", "publish", "transfer", "deploy", "verify"] as $order |
        [$order[] as $stage |
          select($job.stages[$stage] != null) |
          action($job; $pipeline_target; $stage; ("script." + $stage); $job.stages[$stage])]
      end;
    def stage_enabled($stage):
      (if $stage == "build" then $build
       elif $stage == "publish" then $publish
       elif $stage == "transfer" then $transfer
       elif $stage == "deploy" then $deploy
       elif $stage == "verify" then $verify
       else false end)
      and ($only_stage == "" or $only_stage == $stage);

    .pipelines[$pipeline] as $selected |
    if $selected == null then error("unknown shipping pipeline: " + $pipeline) else
      [$selected.jobs[] | select($job_filter == "" or .id == $job_filter)] as $jobs |
      {
        version: 1,
        pipeline: $pipeline,
        description: ($selected.description // ""),
        target: ($selected.target // ""),
        tag: $tag,
        jobs: $jobs,
        actions: [
          $jobs[] as $job |
          driver_actions($job; ($selected.target // ""))[] |
          . + {
            selected: stage_enabled(.stage),
            skip_reason: (if stage_enabled(.stage) then "" elif $only_stage != "" and $only_stage != .stage then "not selected by --only" else "disabled by flag" end)
          }
        ]
      }
    end
  ' "${file}"
}
