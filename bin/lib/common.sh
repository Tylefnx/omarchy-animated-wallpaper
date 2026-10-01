#!/bin/bash
# Shared paths and safe primitives for wallpaper-video commands.

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/wallpaper-video"
MONITORS_DIR="$CONFIG_DIR/monitors"
PIDS_DIR="$CONFIG_DIR/pids"
MODE_FILE="$CONFIG_DIR/mode"
BACKGROUND_FILE="$CONFIG_DIR/background"

die() { printf 'wallpaper-video: %s\n' "$*" >&2; exit 1; }

valid_monitor_name() {
  [[ -n "$1" && "$1" != */* && "$1" != "." && "$1" != ".." && "$1" != *$'\n'* ]]
}

monitor_file() {
  valid_monitor_name "$1" || die "invalid monitor name"
  [[ ! -L "$MONITORS_DIR" && ( ! -e "$MONITORS_DIR" || -d "$MONITORS_DIR" ) ]] || die "unsafe monitor configuration directory"
  printf '%s/%s' "$MONITORS_DIR" "$1"
}

pid_path() {
  valid_monitor_name "$1" || die "invalid monitor name"
  [[ ! -L "$PIDS_DIR" && ( ! -e "$PIDS_DIR" || -d "$PIDS_DIR" ) ]] || die "unsafe process state directory"
  printf '%s/%s.pid' "$PIDS_DIR" "$1"
}

atomic_write() {
  local target="$1" value="$2" temporary
  mkdir -p -- "$(dirname -- "$target")" || die "cannot create configuration directory"
  [[ ! -L "$target" ]] || die "refusing to replace a symlink: $target"
  chmod 700 -- "$(dirname -- "$target")" 2>/dev/null || true
  temporary=$(mktemp "$(dirname -- "$target")/.wallpaper-video.XXXXXX") || die "cannot create temporary configuration file"
  chmod 600 -- "$temporary" || { rm -f -- "$temporary"; die "cannot secure temporary file"; }
  if ! printf '%s\n' "$value" >"$temporary" || ! mv -f -- "$temporary" "$target"; then
    rm -f -- "$temporary"
    die "cannot save configuration"
  fi
}

wallpaper_mode() {
  local value
  [[ -f "$MODE_FILE" && ! -L "$MODE_FILE" ]] || { printf 'video'; return; }
  IFS= read -r value <"$MODE_FILE" || value="video"
  case "$value" in video|image|off) printf '%s' "$value" ;; *) printf 'video' ;; esac
}

current_background() {
  local link="$HOME/.local/state/omarchy/current/background"
  [[ -e "$link" ]] || return 1
  readlink -f -- "$link" 2>/dev/null
}

capture_background() {
  local path
  path=$(current_background) || return 0
  atomic_write "$BACKGROUND_FILE" "$path"
}
