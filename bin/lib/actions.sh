#!/bin/bash

MPVPAPER_AUTO_PAUSE_SUPPORTED=""

ensure_auto_pause_support() {
  [[ -n "$MPVPAPER_AUTO_PAUSE_SUPPORTED" ]] && return 0
  local help
  help=$(mpvpaper --help 2>&1) || true
  if ! grep -q -- '--auto-pause' <<<"$help"; then
    die "installed mpvpaper does not support --auto-pause; update mpvpaper"
  fi
  # -p alone only pauses when the wallpaper surface itself is hidden, which
  # never happens on a background layer — --auto-mode is what makes it react
  # to covering windows.
  if ! grep -q -- '--auto-mode' <<<"$help"; then
    die "installed mpvpaper does not support --auto-mode; update mpvpaper"
  fi
  MPVPAPER_AUTO_PAUSE_SUPPORTED=1
}

# Every failure is a single readable reason on the first stderr line, with an
# optional `hint:` line after it. Callers either show the message as-is (CLI,
# panel) or take the reason and re-attach it to the monitor it belongs to
# (start_all), so no message may depend on being printed bare.
start_monitor() {
  local monitor="$1" assignment video pid started pid_file
  assignment=$(monitor_file "$monitor") || exit 1
  if [[ ! -f "$assignment" || -L "$assignment" ]]; then
    printf 'wallpaper-video: no video is assigned to this monitor\n' >&2
    printf 'hint: open the panel and Pick a video, or Clear this monitor\n' >&2
    return 1
  fi
  video=$(<"$assignment")
  if [[ -z "$video" ]]; then
    printf 'wallpaper-video: the saved assignment for this monitor is empty\n' >&2
    printf 'hint: open the panel and Pick a video for this monitor\n' >&2
    return 1
  fi
  if [[ ! -f "$video" || ! -r "$video" ]]; then
    printf 'wallpaper-video: the assigned video is missing or unreadable: %s\n' "$video" >&2
    printf 'hint: Pick a new video for this monitor, or Clear the assignment\n' >&2
    return 1
  fi
  if ! valid_video "$video"; then
    printf 'wallpaper-video: the assigned file is not a supported video: %s\n' "$video" >&2
    printf 'hint: choose an MP4, WebM, MKV, AVI, MOV, or GIF file\n' >&2
    return 1
  fi
  command -v mpvpaper >/dev/null 2>&1 || die "mpvpaper is not installed"
  ensure_auto_pause_support
  stop_monitor "$monitor"
  mkdir -p -m 700 -- "$PIDS_DIR" || die "cannot create process state directory"
  command -v setsid >/dev/null 2>&1 || die "setsid is not installed"
  setsid mpvpaper --auto-pause -a MAX -o "no-audio loop" "$monitor" "$video" >/dev/null 2>&1 &
  pid=$!
  started=""
  for _ in {1..20}; do
    if pid_is_ours "$pid"; then started=$(process_start_time "$pid") || true; break; fi
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.05
  done
  if [[ -z "$started" ]]; then
    wait "$pid" 2>/dev/null || true
    printf 'wallpaper-video: mpvpaper could not start\n' >&2
    printf 'hint: check the file with: mpvpaper %s %s\n' "$monitor" "$video" >&2
    return 1
  fi
  pid_file=$(pid_path "$monitor") || exit 1
  atomic_write "$pid_file" "$pid $started"
  disown "$pid" 2>/dev/null || true
}

# Start every assigned monitor. Success stays quiet; a partial failure reports
# each monitor with its own reason, plus what the other monitors are doing, so
# one broken file never hides which screens are still fine.
start_all() {
  local monitor assignment detail line rest joined=""
  local -a monitors=() failures=() running=() idle=() details=()
  require_monitor_query
  mapfile -t monitors < <(monitor_names)
  for monitor in "${monitors[@]}"; do
    # A monitor without an assignment is not a failure — it is simply idle.
    assignment=$(monitor_file "$monitor") || exit 1
    if [[ ! -f "$assignment" || -L "$assignment" ]]; then
      idle+=("$monitor")
      continue
    fi
    if detail=$(start_monitor "$monitor" 2>&1); then
      running+=("$monitor")
    else
      failures+=("$monitor")
      details+=("$detail")
    fi
  done
  if (( ${#failures[@]} == 0 )); then
    # No assignments at all is a valid idle state, not an error.
    return 0
  fi
  for monitor in "${failures[@]}"; do joined+="${joined:+, }$monitor"; done
  printf 'wallpaper-video: could not start the wallpaper on %s\n' "$joined" >&2
  local i rest_lines
  for i in "${!failures[@]}"; do
    detail=${details[$i]}
    line=${detail%%$'\n'*}
    printf '  %s: %s\n' "${failures[$i]}" "${line#wallpaper-video: }" >&2
    rest=${detail#*$'\n'}
    if [[ $rest != "$detail" ]]; then
      while IFS= read -r rest_lines; do
        [[ -n $rest_lines ]] && printf '      %s\n' "$rest_lines" >&2
      done <<<"$rest"
    fi
  done
  (( ${#running[@]} == 0 )) || printf '  running: %s\n' "${running[*]}" >&2
  (( ${#idle[@]} == 0 )) || printf '  idle (no video): %s\n' "${idle[*]}" >&2
  return 1
}

valid_video() {
  [[ -f "$1" && -r "$1" && "$1" != *$'\n'* ]] || return 1
  case "${1,,}" in
    *.mp4|*.webm|*.mkv|*.avi|*.mov|*.gif) return 0 ;;
    *) return 1 ;;
  esac
}

set_video() {
  local monitor="$1" video="$2" was_running=false m target was_target_running=false
  [[ -n "$monitor" && -n "$video" ]] || usage
  [[ -f "$video" && -r "$video" ]] || die "video file does not exist or is not readable: $video"
  [[ "$video" != *$'\n'* ]] || die "video path contains an unsupported newline"
  valid_video "$video" || die "choose an MP4, WebM, MKV, AVI, MOV, or GIF file: $video"
  video=$(realpath -e -- "$video") || die "cannot resolve video path"
  if [[ "$monitor" != all ]]; then
    monitor_exists "$monitor" || die "unknown monitor '$monitor'"
  fi
  mkdir -p -m 700 -- "$MONITORS_DIR" "$PIDS_DIR" || die "cannot create configuration directory"
  if [[ "$monitor" == all ]]; then any_running && was_running=true; fi
  if [[ "$monitor" != all ]]; then
    local pid="" started=""
    target=$(pid_path "$monitor") || exit 1
    if [[ -f "$target" && ! -L "$target" ]]; then
      IFS=' ' read -r pid started <"$target" || true
    fi
    owned_pid_is_running "$pid" "$started" && was_target_running=true
  fi
  if [[ "$monitor" == all ]]; then
    local -a names=()
    require_monitor_query
    mapfile -t names < <(monitor_names)
    (( ${#names[@]} > 0 )) || die "no monitors detected"
    for m in "${names[@]}"; do
      target=$(monitor_file "$m") || exit 1
      atomic_write "$target" "$video"
    done
  else
    target=$(monitor_file "$monitor") || exit 1
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
    monitor_is_known "$monitor" || die "unknown monitor '$monitor'"
    target=$(monitor_file "$monitor") || exit 1
    stop_monitor "$monitor"
    [[ -L "$target" ]] || rm -f -- "$target"
  fi
}

pick_video() {
  local monitor="${1:-all}" video
  command -v zenity >/dev/null 2>&1 || die "zenity is not installed"
  if [[ "$monitor" != all ]]; then monitor_exists "$monitor" || die "unknown monitor '$monitor'"; fi
  video=$(zenity --file-selection --title="Select video${monitor:+ for $monitor}" \
    --file-filter="Videos | *.mp4 *.webm *.mkv *.avi *.mov *.gif *.MP4 *.WEBM *.MKV *.AVI *.MOV *.GIF" 2>/dev/null) || true
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
