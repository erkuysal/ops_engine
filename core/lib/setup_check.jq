def norm_files($x):
  ($x // []) | map(tostring) | unique;

def runner_kind_for_role($role):
  if $role == "process_group" then "process_group"
  elif $role == "docker_group" then "compose"
  else "stack"
  end;

def proposed_svc($dir):
  $dir | {
    id,
    stack,
    path,
    role,
    runner_kind: runner_kind_for_role(.role),
    compose_files: norm_files(.compose_files),
    env_files: norm_files(.env_files),
    port: (($proposed_setup[0].services[.id].port // 0) | tonumber),
    command: ($proposed_setup[0].services[.id].command // "")
  };

def current_svc($svc):
  $svc | {
    id,
    stack,
    path,
    role,
    runner_kind: (.runner.kind // "stack"),
    compose_files: norm_files(.compose_files),
    env_files: norm_files(.env_files // .setup.env_files),
    port: ((.setup.port // 0) | tonumber),
    command: (.setup.command // "")
  };

def cache_stale:
  ($cached[0].directories? != null)
  and (
    ([$cached[0].directories[]? | select(.service == true) | .id] | sort)
    != ([$discovery[0].directories[]? | select(.service == true) | .id] | sort)
    or (
      [$discovery[0].directories[]? | select(.service == true)] | any(
        . as $d
        | ($cached[0].directories[]? | select(.id == $d.id)) as $old
        | $old == null
          or $d.stack != $old.stack
          or $d.path != $old.path
          or $d.role != $old.role
          or norm_files($d.compose_files) != norm_files($old.compose_files)
      )
    )
  );

([$discovery[0].directories[]? | select(.service == true) | proposed_svc(.)]) as $discover
| ([$current[0].services[]? | current_svc(.)]) as $current_svcs
| ($discover | map(.id)) as $pids
| ($current_svcs | map(.id)) as $cids
| {
    version: 1,
    generated_at: $generated_at,
    config_source: ($current[0].config_source // "none"),
    summary: {
      added: ([$pids[] | select(. as $id | ($cids | index($id) | not))] | length),
      removed: ([$cids[] | select(. as $id | ($pids | index($id) | not))] | length),
      changed: (
        [$discover[] | . as $p
          | ($current_svcs[] | select(.id == $p.id)) as $c
          | select($c != null)
          | select(
              $p.stack != $c.stack
              or $p.path != $c.path
              or $p.role != $c.role
              or ($p.runner_kind != $c.runner_kind)
              or ($p.compose_files != $c.compose_files)
              or ($p.env_files != $c.env_files)
              or ($p.port != $c.port)
              or (($p.command // "") != ($c.command // ""))
            )
        ] | length
      ),
      global_env_changed: (
        norm_files($discovery[0].global_env_files)
        != norm_files($current[0].global_env_files)
      ),
      cache_stale: cache_stale
    },
    added: [$discover[] | select(.id as $id | ($cids | index($id) | not))],
    removed: [$current_svcs[] | select(.id as $id | ($pids | index($id) | not))],
    changed: [
      $discover[] | . as $p
      | ($current_svcs[] | select(.id == $p.id)) as $c
      | select($c != null)
      | {
          id: $p.id,
          fields: (
            [
              (if $p.stack != $c.stack then {name: "stack", current: $c.stack, proposed: $p.stack} else empty end),
              (if $p.path != $c.path then {name: "path", current: $c.path, proposed: $p.path} else empty end),
              (if $p.role != $c.role then {name: "role", current: $c.role, proposed: $p.role} else empty end),
              (if $p.runner_kind != $c.runner_kind then {name: "runner_kind", current: $c.runner_kind, proposed: $p.runner_kind} else empty end),
              (if $p.compose_files != $c.compose_files then {name: "compose_files", current: $c.compose_files, proposed: $p.compose_files} else empty end),
              (if $p.env_files != $c.env_files then {name: "env_files", current: $p.env_files, proposed: $p.env_files} else empty end),
              (if $p.port != $c.port then {name: "port", current: $c.port, proposed: $p.port} else empty end),
              (if ($p.command // "") != ($c.command // "") then {name: "command", current: $c.command, proposed: $p.command} else empty end)
            ]
          )
        }
      | select(.fields | length > 0)
    ],
    global_env_files: {
      current: norm_files($current[0].global_env_files),
      proposed: norm_files($discovery[0].global_env_files)
    },
    cache: {
      path: ".ops.project/generated/discovery.json",
      stale: cache_stale
    }
  }
