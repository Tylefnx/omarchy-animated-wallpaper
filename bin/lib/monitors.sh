#!/bin/bash

monitor_names() {
  command -v hyprctl >/dev/null 2>&1 || return 1
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
