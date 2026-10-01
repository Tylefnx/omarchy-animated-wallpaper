#!/bin/bash
# install.sh — install or update the animated wallpaper plugin on Omarchy.
#
#   bash install.sh            install from GitHub, or fast-forward an
#                              existing git-managed install
#   bash install.sh --local    install this checkout as-is (development)
#   bash install.sh --dry-run  print the plan and change nothing
#
# Safe to re-run. An already-placed bar widget stays where you put it, your
# settings under ${XDG_CONFIG_HOME:-~/.config}/wallpaper-video are never
# touched, and the post-boot hook is only refreshed in place.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_URL="https://github.com/Tylefnx/omarchy-animated-wallpaper.git"
HOOK_TYPE="post-boot"
HOOK_NAME="wallpaper-video-start"
HOOK_SCRIPT="scripts/$HOOK_NAME"
HOOK_TARGET="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/hooks/$HOOK_TYPE.d/$HOOK_NAME"

OK=$'\e[32m✓\e[0m'
SKIP=$'\e[33m·\e[0m'
ERR=$'\e[31m✗\e[0m'
WARN=$'\e[33m!\e[0m'

LOCAL=0
DRY_RUN=0

usage() {
  sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'
}

while (( $# > 0 )); do
  case "$1" in
    --local) LOCAL=1 ;;
    --dry-run) DRY_RUN=1 ;;
    -h | --help) usage; exit 0 ;;
    *)
      printf '  %s unknown option: %s\n' "$ERR" "$1" >&2
      printf 'Run "bash install.sh --help" for usage.\n' >&2
      exit 1
      ;;
  esac
  shift
done

COMPLETED=()

fail() {
  printf '\n  %s %s\n' "$ERR" "$1" >&2
  shift || true
  local hint
  for hint in "$@"; do printf '    %s\n' "$hint" >&2; done
  if (( ${#COMPLETED[@]} > 0 )); then
    printf '\n  Completed before this error:\n' >&2
    for hint in "${COMPLETED[@]}"; do printf '    · %s\n' "$hint" >&2; done
    printf '\n  Undo everything with: bash uninstall.sh\n' >&2
  fi
  exit 1
}

mark() {
  COMPLETED+=("$1")
  printf '  %s %s\n' "$OK" "$1"
}

echo "→ Installing animated wallpaper..."
echo ""
echo "  Checking dependencies..."

# Every check prints the exact command the user may run themselves; this
# script never installs system packages or asks for sudo.
command -v mpvpaper >/dev/null 2>&1 ||
  fail "mpvpaper is not installed." "Install it with: yay -S mpvpaper"

mpv_help=$(mpvpaper --help 2>&1 || true)
grep -q -- '--auto-pause' <<<"$mpv_help" ||
  fail "mpvpaper does not support --auto-pause." "Update it with: yay -Syu mpvpaper"
grep -q -- '--auto-mode' <<<"$mpv_help" ||
  fail "mpvpaper does not support --auto-mode (needed to pause behind covering windows)." \
    "Update it with: yay -Syu mpvpaper"
echo "  $OK mpvpaper found (auto-pause + auto-mode)"

command -v zenity >/dev/null 2>&1 ||
  fail "zenity is not installed." "Install it with: sudo pacman -S zenity"
echo "  $OK zenity found"

command -v omarchy >/dev/null 2>&1 ||
  fail "the omarchy CLI was not found." \
    "This plugin only runs inside Omarchy: https://omarchy.org/"
echo "  $OK omarchy found"

command -v jq >/dev/null 2>&1 ||
  fail "jq is not installed." "Install it with: sudo pacman -S jq"
echo "  $OK jq found"

command -v python3 >/dev/null 2>&1 ||
  fail "python3 is not installed." "Install it with: sudo pacman -S python"
echo "  $OK python3 found"

command -v hyprctl >/dev/null 2>&1 ||
  fail "hyprctl was not found." "It ships with Hyprland and is how monitors are listed."
echo "  $OK hyprctl found"

echo ""
echo "  Reading manifest..."

[[ -f "$SCRIPT_DIR/manifest.json" ]] ||
  fail "manifest.json is missing from $SCRIPT_DIR." \
    "Run this script from a complete checkout of the plugin."
PLUGIN_ID=$(jq -r '.id // empty' "$SCRIPT_DIR/manifest.json" 2>/dev/null || true)
[[ -n $PLUGIN_ID ]] ||
  fail "manifest.json does not declare a plugin id."
[[ $PLUGIN_ID =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ && $PLUGIN_ID != *..* ]] ||
  fail "manifest.json declares an unusable plugin id: $PLUGIN_ID"
DEFAULT_SECTION=$(jq -r '.barWidget.defaultSection // "center"' "$SCRIPT_DIR/manifest.json")
PLUGIN_DIR="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
echo "  $OK $PLUGIN_ID (bar section: $DEFAULT_SECTION)"

# Decide what this run actually does. A local copy is deliberately not
# "updated" from Git: it is not a checkout, so claiming otherwise would be a
# lie the user only discovers on their next install.
MODE="fresh"
if (( LOCAL )); then
  MODE="local"
elif [[ -e "$PLUGIN_DIR" ]]; then
  if [[ -d "$PLUGIN_DIR/.git" ]]; then
    MODE="update"
  else
    fail "a local copy of $PLUGIN_ID is already installed at $PLUGIN_DIR." \
      "It is not a Git checkout, so there is nothing to update from $REPO_URL." \
      "" \
      "  Sync this checkout over it:   bash install.sh --local" \
      "  Start over from GitHub:       omarchy plugin remove $PLUGIN_ID --yes" \
      "                                bash install.sh"
  fi
fi

echo ""
echo "  Plan:"
case "$MODE" in
  local) echo "    · sync this checkout into $PLUGIN_DIR" ;;
  fresh) echo "    · clone $REPO_URL into $PLUGIN_DIR" ;;
  update) echo "    · fast-forward the install at $PLUGIN_DIR" ;;
esac
echo "    · enable $PLUGIN_ID in the bar, if it is not enabled already"
echo "    · refresh the $HOOK_TYPE hook at $HOOK_TARGET"
echo "    · keep ${XDG_CONFIG_HOME:-$HOME/.config}/wallpaper-video untouched"

if (( DRY_RUN )); then
  echo ""
  echo -e "  $SKIP dry run — nothing was changed."
  exit 0
fi

echo ""
echo "  Installing plugin files..."

case "$MODE" in
  fresh)
    if ! output=$(omarchy plugin add "$REPO_URL" --yes 2>&1); then
      fail "omarchy plugin add failed." "$output" \
        "Retry with: omarchy plugin add $REPO_URL --yes"
    fi
    mark "plugin cloned from $REPO_URL"
    ;;
  update)
    if ! output=$(omarchy plugin update "$PLUGIN_ID" --yes 2>&1); then
      fail "omarchy plugin update failed." "$output" \
        "The plugin folder is a Git checkout, so you can also run:" \
        "  git -C '$PLUGIN_DIR' pull --ff-only"
    fi
    mark "plugin fast-forwarded to the latest commit"
    ;;
  local)
    if [[ "$SCRIPT_DIR" == "$PLUGIN_DIR" ]]; then
      # Running the installer from inside the installed folder: there is
      # nothing to copy, and rsync would refuse source == destination.
      mark "already running from $PLUGIN_DIR (nothing to sync)"
    else
      if ! mkdir -p "$PLUGIN_DIR"; then
        fail "could not create $PLUGIN_DIR." "Check the permissions on ~/.config/omarchy/plugins."
      fi
      # --local means "this checkout is the source of truth": mirror it, then
      # drop .git so the result is a plain copy rather than a Git checkout with
      # uncommitted changes that `omarchy plugin update` could never fast-forward.
      if command -v rsync >/dev/null 2>&1; then
        rsync -a --delete --exclude='.git' "$SCRIPT_DIR/" "$PLUGIN_DIR/" ||
          fail "could not sync $SCRIPT_DIR into $PLUGIN_DIR."
      else
        cp -r "$SCRIPT_DIR/." "$PLUGIN_DIR/" ||
          fail "could not copy $SCRIPT_DIR into $PLUGIN_DIR."
      fi
      rm -rf "$PLUGIN_DIR/.git"
      mark "plugin files synced from this checkout"
    fi
    ;;
esac

if ! output=$(omarchy plugin validate "$PLUGIN_DIR" 2>&1); then
  fail "the installed plugin fails Omarchy's manifest validation." "$output" \
    "Inspect it with: omarchy plugin validate $PLUGIN_DIR"
fi
mark "manifest validated by omarchy plugin validate"

echo ""
echo "  Installing $HOOK_TYPE hook..."

HOOK_SRC=""
if [[ -f "$PLUGIN_DIR/$HOOK_SCRIPT" ]]; then
  HOOK_SRC="$PLUGIN_DIR/$HOOK_SCRIPT"
elif [[ -f "$SCRIPT_DIR/$HOOK_SCRIPT" ]]; then
  HOOK_SRC="$SCRIPT_DIR/$HOOK_SCRIPT"
fi
[[ -n $HOOK_SRC ]] ||
  fail "hook script not found." \
    "Expected $HOOK_SCRIPT next to install.sh or inside $PLUGIN_DIR."
if ! output=$(omarchy hook install "$HOOK_TYPE" "$HOOK_SRC" 2>&1); then
  fail "omarchy hook install failed." "$output" \
    "Install it by hand with:" \
    "  cp '$HOOK_SRC' '$HOOK_TARGET' && chmod 755 '$HOOK_TARGET'"
fi
[[ -x "$HOOK_TARGET" ]] ||
  fail "the hook was not installed at $HOOK_TARGET." \
    "Install it by hand with:" \
    "  cp '$HOOK_SRC' '$HOOK_TARGET' && chmod 755 '$HOOK_TARGET'"
mark "$HOOK_TYPE hook installed (wallpapers restore after login)"

echo ""
echo "  Enabling the bar widget..."

shell_up=0
if command -v omarchy-shell >/dev/null 2>&1 &&
  omarchy-shell shell ping >/dev/null 2>&1; then
  shell_up=1
fi

if (( ! shell_up )); then
  printf '  %s omarchy-shell is not running, so the widget cannot be enabled yet.\n' "$WARN"
else
  # Rescan first: a freshly cloned folder is not in the registry until the
  # shell walks the plugin directory again.
  omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
  discovered=""
  for ((attempt = 0; attempt < 40; attempt++)); do
    if omarchy plugin list --json 2>/dev/null |
      jq -e --arg id "$PLUGIN_ID" 'any(.[]; .id == $id)' >/dev/null 2>&1; then
      discovered=1
      break
    fi
    sleep 0.05
  done
  if [[ -z ${discovered:-} ]]; then
    fail "$PLUGIN_ID was installed but the shell has not discovered it." \
      "Run: omarchy-shell shell rescanPlugins" \
      "Then: omarchy plugin enable $PLUGIN_ID"
  fi

  enabled=$(omarchy plugin list --json 2>/dev/null |
    jq -r --arg id "$PLUGIN_ID" 'any(.[]; .id == $id and .enabled == true)' 2>/dev/null || echo false)
  if [[ $enabled == "true" ]]; then
    echo "  $SKIP $PLUGIN_ID is already enabled — your bar placement was left alone"
  else
    # No placement argument on purpose: enable inserts at the manifest's
    # defaultSection only when the widget is not on the bar, and never moves
    # a widget the user has already arranged.
    if ! output=$(omarchy plugin enable "$PLUGIN_ID" 2>&1); then
      fail "could not enable $PLUGIN_ID in the bar." "$output" \
        "Retry with: omarchy-shell shell rescanPlugins && omarchy plugin enable $PLUGIN_ID"
    fi
    mark "$PLUGIN_ID enabled in the bar's $DEFAULT_SECTION section"
  fi
fi

echo ""
if (( shell_up )); then
  echo -e "\e[32mInstallation complete!\e[0m"
else
  echo -e "\e[33mFiles installed, but the widget is not enabled yet.\e[0m"
fi
echo ""
echo "  Plugin   $PLUGIN_DIR"
echo "  Hook     $HOOK_TARGET"
echo "  Settings ${XDG_CONFIG_HOME:-$HOME/.config}/wallpaper-video (never modified by install)"
echo ""
if (( shell_up )); then
  echo "  Left-click the wallpaper icon in the bar to toggle, right-click to open the panel."
else
  echo "  Start your desktop session, then finish with:"
  echo "      omarchy plugin enable $PLUGIN_ID"
fi
echo ""

if (( ! shell_up )); then
  exit 1
fi
