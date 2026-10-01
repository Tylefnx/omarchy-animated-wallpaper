#!/bin/bash
# install.sh — install the animated wallpaper plugin on Omarchy.
#
#   bash install.sh           install from GitHub (the fork's repo)
#   bash install.sh --local   install this checkout as-is (for development)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ID="r4venward.wallpaper-video"
REPO_URL="https://github.com/Tylefnx/omarchy-animated-wallpaper.git"
PLUGIN_DIR="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
HOOK_SCRIPT="scripts/wallpaper-video-start"

OK="\e[32m✓\e[0m"
SKIP="\e[33m·\e[0m"
ERR="\e[31m✗\e[0m"

LOCAL=0
for arg in "$@"; do
  case "$arg" in
    --local) LOCAL=1 ;;
    -h | --help)
      sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo -e "  $ERR unknown option: $arg" >&2
      exit 1
      ;;
  esac
done

echo "→ Installing animated wallpaper..."

# 1. Dependencies
echo ""
echo "  Checking dependencies..."

if ! command -v mpvpaper &>/dev/null; then
  echo -e "  $ERR mpvpaper is not installed. Install it with: yay -S mpvpaper"
  exit 1
fi
if ! mpvpaper --help 2>&1 | grep -q -- '--auto-pause'; then
  echo -e "  $ERR installed mpvpaper does not support --auto-pause; update mpvpaper first"
  exit 1
fi
echo -e "  $OK mpvpaper found"

if ! command -v zenity &>/dev/null; then
  echo -e "  $ERR zenity is not installed. Install it with: sudo pacman -S zenity"
  exit 1
fi
echo -e "  $OK zenity found"

if ! command -v omarchy &>/dev/null; then
  echo -e "  $ERR omarchy CLI not found — this plugin needs Omarchy."
  exit 1
fi
echo -e "  $OK omarchy found"

# 2. Plugin
echo ""
echo "  Installing plugin..."

plugin_discovered() {
  omarchy plugin list --json 2>/dev/null |
    jq -e --arg id "$PLUGIN_ID" 'any(.[]; .id == $id)' >/dev/null 2>&1
}

plugin_enabled() {
  omarchy plugin list --json 2>/dev/null |
    jq -e --arg id "$PLUGIN_ID" 'any(.[]; .id == $id and .enabled == true)' >/dev/null 2>&1
}

if (( LOCAL )); then
  # Dev workflow: re-running install.sh syncs this checkout into the plugin
  # folder; the shell hot-reloads it on save.
  mkdir -p "$PLUGIN_DIR"
  cp -r "$SCRIPT_DIR/." "$PLUGIN_DIR/"
  rm -rf "$PLUGIN_DIR/.git"
  omarchy-shell shell rescanPlugins >/dev/null
  # The registry picks the folder up asynchronously — poll like
  # `omarchy plugin add` does before enabling.
  discovered=0
  for ((attempt = 0; attempt < 40; attempt++)); do
    if plugin_discovered; then
      discovered=1
      break
    fi
    sleep 0.05
  done
  if (( ! discovered )); then
    echo -e "  $ERR plugin was copied but the shell has not discovered it yet"
    echo -e "  $ERR run: omarchy plugin enable $PLUGIN_ID --section right"
    exit 1
  fi
  if plugin_enabled; then
    echo -e "  $SKIP plugin files synced (already enabled)"
  else
    omarchy plugin enable "$PLUGIN_ID" --section right
    echo -e "  $OK plugin installed and added to the bar (right section)"
  fi
elif [[ -d "$PLUGIN_DIR" ]]; then
  echo -e "  $SKIP plugin already installed at $PLUGIN_DIR"
  echo -e "  $SKIP to update it, run: omarchy plugin update $PLUGIN_ID"
else
  omarchy plugin add "$REPO_URL" --enable --yes
  echo -e "  $OK plugin installed and added to the bar (right section)"
fi

# 3. Post-boot hook: start the wallpapers again after login
echo ""
echo "  Installing post-boot hook..."
HOOK_SRC=""
if [[ -f "$PLUGIN_DIR/$HOOK_SCRIPT" ]]; then
  HOOK_SRC="$PLUGIN_DIR/$HOOK_SCRIPT"
elif [[ -f "$SCRIPT_DIR/$HOOK_SCRIPT" ]]; then
  HOOK_SRC="$SCRIPT_DIR/$HOOK_SCRIPT"
fi
if [[ -z "$HOOK_SRC" ]]; then
  echo -e "  $ERR hook script not found"
  exit 1
fi
omarchy hook install post-boot "$HOOK_SRC" >/dev/null
echo -e "  $OK wallpapers will start on login"

echo ""
echo -e "\e[32mInstallation complete!\e[0m"
echo ""
echo "  Left-click the wallpaper icon in the bar to toggle, right-click to open the panel."
echo ""
