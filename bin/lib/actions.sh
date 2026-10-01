#!/bin/bash

start_monitor() {
  local monitor="$1" assignment video pid started
  assignment=$(monitor_file "$monitor")
  [[ -f "$assignment" && ! -L "$assignment" ]] || return 1
  video=$(<"$assignment")
  [[ -n "$video" && -f "$video" && -r "$video" ]] || return 1
  command -v mpvpaper >/dev/null 2>&1 || die "mpvpaper is not installed"
  stop_monitor "$monitor"
  mkdir -p -m 700 -- "$PIDS_DIR" || die "cannot create process state directory"
  command -v setsid >/dev/null 2>&1 || die "setsid is not installed"
  setsid mpvpaper -o "no-audio loop" "$monitor" "$video" >/dev/null 2>&1 &
  pid=$!
  started=""
  for _ in {1..20}; do
    if pid_is_ours "$pid"; then started=$(process_start_time "$pid") || true; break; fi
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.05
  done
  if [[ -z "$started" ]]; then
    wait "$pid" 2>/dev/null || true
    die "mpvpaper failed to start on $monitor"
  fi
  atomic_write "$(pid_path "$monitor")" "$pid $started"
  disown "$pid" 2>/dev/null || true
}

start_all() {
  local started=0 monitor
  local -a failures=()
  while IFS= read -r monitor; do
    if start_monitor "$monitor"; then started=$((started + 1)); else failures+=("$monitor"); fi
  done < <(monitor_names)
  if (( started == 0 )); then
    if (( ${#failures[@]} )); then die "could not start wallpaper on: ${failures[*]}"; fi
    command -v notify-send >/dev/null 2>&1 && notify-send "Animated wallpaper" "No readable videos configured." --urgency=normal 2>/dev/null || true
    return 1
  fi
  (( ${#failures[@]} == 0 )) || { printf 'wallpaper-video: failed on: %s\n' "${failures[*]}" >&2; return 1; }
}

set_video() {
  local monitor="$1" video="$2" was_running=false m target was_target_running=false
  [[ -n "$monitor" && -n "$video" ]] || usage
  [[ -f "$video" && -r "$video" ]] || die "video file does not exist or is not readable: $video"
  [[ "$video" != *$'\n'* ]] || die "video path contains an unsupported newline"
  video=$(realpath -e -- "$video") || die "cannot resolve video path"
  if [[ "$monitor" != all ]]; then
    monitor_exists "$monitor" || die "unknown monitor '$monitor'"
  fi
  mkdir -p -m 700 -- "$MONITORS_DIR" "$PIDS_DIR" || die "cannot create configuration directory"
  if [[ "$monitor" == all ]]; then any_running && was_running=true; fi
  if [[ "$monitor" != all ]]; then
    local pid="" started=""
    target=$(pid_path "$monitor")
    if [[ -f "$target" && ! -L "$target" ]]; then
      IFS=' ' read -r pid started <"$target" || true
    fi
    owned_pid_is_running "$pid" "$started" && was_target_running=true
  fi
  if [[ "$monitor" == all ]]; then
    local assigned=0
    while IFS= read -r m; do atomic_write "$(monitor_file "$m")" "$video"; done < <(monitor_names)
    while IFS= read -r m; do (( assigned += 1 )); done < <(monitor_names)
    (( assigned > 0 )) || die "no monitors detected"
  else
    target=$(monitor_file "$monitor")
    atomic_write "$target" "$video"
  fi
  if [[ "$monitor" == all && "$was_running" == true ]]; then stop_all; start_all
  elif [[ "$monitor" != all && "$was_target_running" == true ]]; then stop_monitor "$monitor"; start_monitor "$monitor"; fi
}

clear_video() {
  local monitor="$1" m target
  [[ -n "$monitor" ]] || usage
  if [[ "$monitor" == all ]]; then
    stop_all
    [[ ! -L "$MONITORS_DIR" ]] || die "unsafe monitor configuration directory"
    [[ -d "$MONITORS_DIR" ]] || return 0
    shopt -s nullglob
    local assignment
    for assignment in "$MONITORS_DIR"/*; do [[ -L "$assignment" ]] || rm -f -- "$assignment"; done
    shopt -u nullglob
  else
    stop_monitor "$monitor"
    target=$(monitor_file "$monitor")
    [[ -L "$target" ]] || rm -f -- "$target"
  fi
}

pick_video() {
  local monitor="${1:-all}" video
  command -v zenity >/dev/null 2>&1 || die "zenity is not installed"
  if [[ "$monitor" != all ]]; then monitor_exists "$monitor" || die "unknown monitor '$monitor'"; fi
  video=$(zenity --file-selection --title="Select video${monitor:+ for $monitor}" \
    --file-filter="Videos | *.mp4 *.webm *.mkv *.avi *.mov *.gif *.MP4 *.WEBM *.MKV" 2>/dev/null) || true
  [[ -n "$video" ]] || return 0
  set_video "$monitor" "$video"
}
