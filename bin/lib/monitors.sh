#!/bin/bash

# Prerequisites that must be checked in the calling shell — inside $( ) a
# die() would only exit the subshell and the failure would be swallowed.
require_monitor_query() {
  command -v hyprctl >/dev/null 2>&1 || die "hyprctl is not installed"
  require_python
}

monitor_names() {
  require_monitor_query || return 1
  hyprctl monitors -j 2>/dev/null | python3 -c '
import json, sys
try: data = json.load(sys.stdin)
except Exception: data = []
for monitor in data:
    name = monitor.get("name", "")
    if isinstance(name, str) and name and "/" not in name and name not in (".", "..") and "\n" not in name:
        print(name)
'
}

monitor_exists() { monitor_names | grep -Fxq -- "$1"; }

# A name counts as known when the monitor is connected or still holds a saved
# assignment or player process, so a typo is reported instead of silently
# doing nothing while a disconnected screen can still be cleared or stopped.
monitor_is_known() {
  valid_monitor_name "$1" || return 1
  monitor_exists "$1" && return 0
  local file
  file=$(monitor_file "$1") || return 1
  [[ -f "$file" && ! -L "$file" ]] && return 0
  file=$(pid_path "$1") || return 1
  [[ -f "$file" && ! -L "$file" ]]
}
