#!/bin/bash

pid_is_ours() {
  local pid="$1" comm
  [[ "$pid" =~ ^[0-9]+$ ]] || return 1
  kill -0 "$pid" 2>/dev/null || return 1
  comm=$(<"/proc/$pid/comm") || return 1
  [[ "$comm" == "mpvpaper" ]]
}

process_start_time() {
  local stat rest
  [[ "$1" =~ ^[0-9]+$ ]] || return 1
  IFS= read -r stat 2>/dev/null <"/proc/$1/stat" || return 1
  rest="${stat##*) }"
  # After the final ')' field 22 (starttime) is field 20.
  set -- $rest
  [[ $# -ge 20 ]] || return 1
  printf '%s' "${20}"
}

owned_pid_is_running() {
  local pid="$1" expected="$2" actual
  pid_is_ours "$pid" || return 1
  actual=$(process_start_time "$pid") || return 1
  [[ -n "$expected" && "$actual" == "$expected" ]]
}

terminate_owned_group() {
  local pid="$1" pgid sid i
  local expected="${2:-}"
  owned_pid_is_running "$pid" "$expected" || return 0
  pgid=$(ps -o pgid= -p "$pid" 2>/dev/null | tr -d ' ')
  sid=$(ps -o sid= -p "$pid" 2>/dev/null | tr -d ' ')
  if [[ "$pgid" =~ ^[0-9]+$ && "$sid" =~ ^[0-9]+$ && "$pgid" == "$pid" && "$sid" == "$pid" ]]; then
    kill -TERM -- "-$pgid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true
  else
    kill -TERM "$pid" 2>/dev/null || true
  fi
  for i in {1..20}; do
    owned_pid_is_running "$pid" "$expected" || break
    sleep 0.1
  done
  if owned_pid_is_running "$pid" "$expected"; then
    if [[ "$pgid" == "$pid" && "$sid" == "$pid" ]]; then
      kill -KILL -- "-$pgid" 2>/dev/null || kill -KILL "$pid" 2>/dev/null || true
    else
      kill -KILL "$pid" 2>/dev/null || true
    fi
  fi
}

read_pid() {
  local file
  file=$(pid_path "$1") || return 1
  [[ -f "$file" && ! -L "$file" ]] || return 1
  cat -- "$file" 2>/dev/null
}

any_running() {
  local f
  [[ -d "$PIDS_DIR" ]] || return 1
  for f in "$PIDS_DIR"/*.pid; do
    [[ -e "$f" ]] || continue
    local pid started
    IFS=' ' read -r pid started <"$f" || continue
    owned_pid_is_running "$pid" "$started" && return 0
  done
  return 1
}

stop_monitor() {
  local file pid started
  file=$(pid_path "$1") || exit 1
  [[ -f "$file" && ! -L "$file" ]] || return 0
  IFS=' ' read -r pid started <"$file" || true
  terminate_owned_group "$pid" "$started"
  rm -f -- "$file"
}

stop_all() {
  local f
  [[ ! -L "$PIDS_DIR" ]] || die "unsafe process state directory"
  [[ -d "$PIDS_DIR" ]] || return 0
  for f in "$PIDS_DIR"/*.pid; do
    [[ -e "$f" ]] || continue
    stop_monitor "$(basename -- "$f" .pid)"
  done
}
