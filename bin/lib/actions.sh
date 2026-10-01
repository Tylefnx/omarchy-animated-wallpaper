#!/bin/bash

MPVPAPER_AUTO_PAUSE_SUPPORTED=""

ensure_auto_pause_support() {
  [[ -n "$MPVPAPER_AUTO_PAUSE_SUPPORTED" ]] && return 0
  if mpvpaper --help 2>&1 | grep -q -- '--auto-pause'; then
    MPVPAPER_AUTO_PAUSE_SUPPORTED=1
  else
    die "installed mpvpaper does not support --auto-pause; update mpvpaper"
  fi
}

start_monitor() {
  local monitor="$1" assignment video pid started
  assignment=$(monitor_file "$monitor")
  [[ -f "$assignment" && ! -L "$assignment" ]] || return 1
  video=$(<"$assignment")
  [[ -n "$video" && -f "$video" && -r "$video" ]] || return 1
  command -v mpvpaper >/dev/null 2>&1 || die "mpvpaper is not installed"
  ensure_auto_pause_support
  stop_monitor "$monitor"
  mkdir -p -m 700 -- "$PIDS_DIR" || die "cannot create process state directory"
  command -v setsid >/dev/null 2>&1 || die "setsid is not installed"
  setsid mpvpaper --auto-pause -o "no-audio loop" "$monitor" "$video" >/dev/null 2>&1 &
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
    local -a names=()
    mapfile -t names < <(monitor_names)
    (( ${#names[@]} > 0 )) || die "no monitors detected"
    for m in "${names[@]}"; do atomic_write "$(monitor_file "$m")" "$video"; done
  else
    target=$(monitor_file "$monitor")
    atomic_write "$target" "$video"
  fi
  atomic_write "$MODE_FILE" video
  capture_background
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
    atomic_write "$MODE_FILE" off
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

valid_image() {
  [[ -f "$1" && -r "$1" && "$1" != *$'\n'* ]] || return 1
  case "${1,,}" in *.png|*.jpg|*.jpeg|*.webp|*.avif|*.bmp) return 0 ;; *) return 1 ;; esac
}

apply_image() {
  local image="$1"
  valid_image "$image" || die "choose a readable PNG, JPEG, WebP, AVIF, or BMP image"
  image=$(realpath -e -- "$image") || die "cannot resolve image path"
  command -v omarchy-theme-bg-set >/dev/null 2>&1 || die "omarchy-theme-bg-set is not available"
  omarchy-theme-bg-set "$image" || die "Omarchy could not apply the selected image"
  stop_all
  atomic_write "$MODE_FILE" image
  capture_background
}

pick_image() {
  local image
  command -v zenity >/dev/null 2>&1 || die "zenity is not installed"
  image=$(zenity --file-selection --title="Choose a static wallpaper" \
    --file-filter="Images | *.png *.jpg *.jpeg *.webp *.avif *.bmp *.PNG *.JPG *.JPEG *.WEBP *.AVIF *.BMP" 2>/dev/null) || true
  [[ -n "$image" ]] || return 0
  apply_image "$image"
}

reconcile_background() {
  local current recorded mode
  current=$(current_background) || return 0
  mode=$(wallpaper_mode)
  [[ "$mode" == video ]] || return 0
  if [[ ! -f "$BACKGROUND_FILE" || -L "$BACKGROUND_FILE" ]]; then
    atomic_write "$BACKGROUND_FILE" "$current"
    return 0
  fi
  IFS= read -r recorded <"$BACKGROUND_FILE" || recorded=""
  [[ -n "$recorded" && "$recorded" != "$current" ]] || return 0
  stop_all
  atomic_write "$MODE_FILE" image
}
