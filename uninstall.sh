#!/bin/bash
# uninstall.sh — remove the animated wallpaper plugin from Omarchy.
#
#   bash uninstall.sh             stop the wallpapers, remove this plugin
#                                 and its hook, keep your saved settings
#   bash uninstall.sh --purge     also delete your saved settings
#   bash uninstall.sh --dry-run   print the plan and change nothing
#   bash uninstall.sh --yes       do not ask for confirmation
#
# Only this plugin's own files are removed — never another hook, plugin or
# process. Safe to re-run: a second run reports "nothing to remove".

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
HOOK_TYPE="post-boot"
HOOK_NAME="wallpaper-video-start"
# Same path Omarchy's runner reads and `omarchy hook install` writes — never
# XDG_CONFIG_HOME, which those tools ignore.
HOOK_TARGET="$HOME/.config/omarchy/hooks/$HOOK_TYPE.d/$HOOK_NAME"
# A build older than this one derived HOOK_TARGET from XDG_CONFIG_HOME. On a
# machine where that differs from ~/.config it left a hook the runner never
# executes; it is ours by name, so plan and remove it alongside the real one.
HOOK_TARGET_LEGACY=""
if [[ -n ${XDG_CONFIG_HOME:-} && ${XDG_CONFIG_HOME:-} != "$HOME/.config" ]]; then
  HOOK_TARGET_LEGACY="$XDG_CONFIG_HOME/omarchy/hooks/$HOOK_TYPE.d/$HOOK_NAME"
fi
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/wallpaper-video"
BIN_LINK="$HOME/.local/bin/wallpaper-video"
PLUGINS_DIR="$HOME/.config/omarchy/plugins"
FALLBACK_ID="r4venward.wallpaper-video"

OK=$'\e[32m✓\e[0m'
SKIP=$'\e[33m·\e[0m'
ERR=$'\e[31m✗\e[0m'
WARN=$'\e[33m!\e[0m'

PURGE=0
DRY_RUN=0
ASSUME_YES=0

usage() {
  sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'
}

while (( $# > 0 )); do
  case "$1" in
    --purge) PURGE=1 ;;
    --dry-run) DRY_RUN=1 ;;
    --yes | -y) ASSUME_YES=1 ;;
    -h | --help) usage; exit 0 ;;
    *)
      printf '  %s unknown option: %s\n' "$ERR" "$1" >&2
      printf 'Run "bash uninstall.sh --help" for usage.\n' >&2
      exit 1
      ;;
  esac
  shift
done

ERRORS=0
# Every failure keeps its message and its recovery hints so the run can end
# with one actionable list instead of leaving the user to scroll back.
PENDING=()
ok() { printf '  %s %s\n' "$OK" "$1"; }
skip() { printf '  %s %s\n' "$SKIP" "$1"; }
warn() { _report "$WARN" "$@"; }
err() { _report "$ERR" "$@"; }
_report() {
  local mark="$1" msg="$2" hint entry
  shift 2
  printf '  %s %s\n' "$mark" "$msg" >&2
  entry="· $msg"
  for hint in "$@"; do
    printf '    %s\n' "$hint" >&2
    entry+=$'\n'"      $hint"
  done
  PENDING+=("$entry")
  ERRORS=$((ERRORS + 1))
}

# The id lives in manifest.json. Fall back to the shipped id so uninstall
# still works after the checkout (or the installed copy) has been deleted.
PLUGIN_ID=""
read_id() {
  [[ -f $1 ]] || return 1
  local id
  id=$(jq -r '.id // empty' "$1" 2>/dev/null || true)
  [[ -n $id ]] || return 1
  PLUGIN_ID=$id
  return 0
}
read_id "$SCRIPT_DIR/manifest.json" ||
  read_id "$PLUGINS_DIR/$FALLBACK_ID/manifest.json" ||
  PLUGIN_ID="$FALLBACK_ID"
PLUGIN_DIR="$PLUGINS_DIR/$PLUGIN_ID"

# Prefer the helper that ships next to this script so uninstall works even
# when the installed plugin folder is already gone.
HELPER=""
for candidate in "$SCRIPT_DIR/bin/wallpaper-video" "$PLUGIN_DIR/bin/wallpaper-video"; do
  if [[ -x $candidate ]]; then
    HELPER=$candidate
    break
  fi
done

HOOK_PRESENT=0
[[ -e $HOOK_TARGET || -L $HOOK_TARGET ]] && HOOK_PRESENT=1
HOOK_LEGACY_PRESENT=0
if [[ -n $HOOK_TARGET_LEGACY ]]; then
  [[ -e $HOOK_TARGET_LEGACY || -L $HOOK_TARGET_LEGACY ]] && HOOK_LEGACY_PRESENT=1
fi
PLUGIN_PRESENT=0
[[ -e $PLUGIN_DIR || -L $PLUGIN_DIR ]] && PLUGIN_PRESENT=1
CONFIG_PRESENT=0
[[ -d $CONFIG_DIR && ! -L $CONFIG_DIR ]] && CONFIG_PRESENT=1
# A settings directory that is a symlink still holds the user's data, but
# `rm -rf` on a symlink must never be allowed to reach its target. It is
# reported for what it is and, at most, the link itself is removed.
CONFIG_LINK=0
[[ -L $CONFIG_DIR ]] && CONFIG_LINK=1
LINK_TARGET=""
LINK_OURS=0
if [[ -L $BIN_LINK ]]; then
  LINK_TARGET=$(readlink -- "$BIN_LINK" 2>/dev/null || true)
  case "$LINK_TARGET" in
    "$PLUGIN_DIR" | "$PLUGIN_DIR"/*) LINK_OURS=1 ;;
  esac
fi

echo "→ Uninstalling animated wallpaper..."
echo ""
# Every mode states plainly what will happen, before anything is touched:
# a dry run applies nothing, --yes applies without asking, a real terminal is
# asked first, and a non-terminal is refused outright.
if (( DRY_RUN )); then
  echo "  Plan — a dry run; nothing below will happen"
elif (( ASSUME_YES )); then
  echo "  Plan — applied immediately (--yes)"
elif [[ -t 0 && -t 1 ]]; then
  echo "  Plan — applied after you confirm below"
else
  echo "  Plan — will not be applied; confirmation is required"
fi
echo ""
echo "  Will remove:"
if (( HOOK_PRESENT )); then
  echo "    · post-boot hook   $HOOK_TARGET"
else
  echo "    · post-boot hook   (not present)"
fi
if (( HOOK_LEGACY_PRESENT )); then
  echo "    · stale hook from an older install   $HOOK_TARGET_LEGACY"
fi
if (( PLUGIN_PRESENT )); then
  echo "    · plugin + bar entry   $PLUGIN_DIR"
else
  echo "    · plugin + bar entry   (not installed)"
fi
if (( LINK_OURS )); then
  echo "    · PATH symlink     $BIN_LINK"
fi
echo "    · any wallpaper-video player this plugin started"
echo ""
echo "  Will keep:"
if (( CONFIG_PRESENT )); then
  if (( PURGE )); then
    echo "    · nothing — --purge deletes your saved settings in $CONFIG_DIR"
  else
    echo "    · your saved settings in $CONFIG_DIR   (--purge deletes them)"
  fi
elif (( CONFIG_LINK )); then
  if (( PURGE )); then
    echo "    · the link $CONFIG_DIR (the folder it points to is never followed)"
  else
    echo "    · the link $CONFIG_DIR   (--purge removes the link only)"
  fi
else
  echo "    · no settings directory found"
fi

echo ""
if (( DRY_RUN )); then
  echo "  Confirmation: a dry run stops here, nothing is prompted"
  if (( ! ASSUME_YES )) && [[ ! -t 0 || ! -t 1 ]]; then
    echo "    a real run on this input would refuse and exit 1 without --yes"
  fi
elif (( ASSUME_YES )); then
  echo "  Confirmation: skipped (--yes)"
elif [[ -t 0 && -t 1 ]]; then
  echo "  Confirmation: will be asked next, before anything is touched"
else
  echo "  Confirmation: will refuse and exit 1 — this is not a terminal, pass --yes"
fi

if (( DRY_RUN )); then
  echo ""
  echo -e "  $SKIP dry run — nothing was changed; run without --dry-run to apply the plan above."
  exit 0
fi

if (( ! HOOK_PRESENT && ! HOOK_LEGACY_PRESENT && ! PLUGIN_PRESENT && ! CONFIG_PRESENT && ! CONFIG_LINK && ! LINK_OURS )); then
  # Nothing of ours exists; still try to stop anything left over from an
  # earlier install so a stray player cannot outlive the plugin.
  if [[ -n $HELPER ]]; then
    "$HELPER" stop >/dev/null 2>&1 || true
  fi
  echo ""
  echo -e "  $SKIP nothing to remove."
  exit 0
fi

if (( ! ASSUME_YES )); then
  if [[ -t 0 && -t 1 ]]; then
    scope="the plugin, its hook, its bar entry and its wallpapers"
    (( PURGE )) && scope="$scope and your saved settings"
    printf '  Remove %s? [y/N] ' "$scope"
    read -r reply
    case "$reply" in
      y | Y | yes | YES) ;;
      *) echo "  Aborted. Nothing was changed."; exit 1 ;;
    esac
  else
    printf '  %s refusing to uninstall without confirmation; pass --yes\n' "$ERR" >&2
    exit 1
  fi
fi

echo ""
echo "  Stopping wallpapers..."
if [[ -n $HELPER ]]; then
  if output=$("$HELPER" stop 2>&1); then
    ok "wallpapers stopped"
  else
    err "could not stop every wallpaper: $(printf '%s' "$output" | tr '\n' ' ')" \
      "Check with: pgrep -a mpvpaper"
  fi
else
  warn "the helper was not found — no player was stopped" \
    "Run 'bash uninstall.sh' from the plugin checkout to stop players."
fi

echo ""
echo "  Removing the post-boot hook..."
if (( HOOK_PRESENT )); then
  if rm -f -- "$HOOK_TARGET"; then
    ok "removed $HOOK_TARGET"
  else
    err "could not remove $HOOK_TARGET"
  fi
else
  skip "not present"
fi
if (( HOOK_LEGACY_PRESENT )); then
  # Written by an older install.sh that derived the path from
  # XDG_CONFIG_HOME. Omarchy's runner never reads it, but it is ours.
  if rm -f -- "$HOOK_TARGET_LEGACY"; then
    ok "removed the stale hook $HOOK_TARGET_LEGACY"
  else
    err "could not remove $HOOK_TARGET_LEGACY" "Remove it by hand: rm -f '$HOOK_TARGET_LEGACY'"
  fi
fi

if (( LINK_OURS )); then
  if rm -f -- "$BIN_LINK"; then
    ok "removed the PATH symlink $BIN_LINK"
  else
    err "could not remove $BIN_LINK"
  fi
elif [[ -e $BIN_LINK ]]; then
  skip "$BIN_LINK is not this plugin's symlink — left alone"
fi

echo ""
echo "  Removing the plugin..."
if (( PLUGIN_PRESENT )); then
  if ! command -v omarchy >/dev/null 2>&1; then
    err "the omarchy CLI is not available, so the plugin was left in place" \
      "Remove it once Omarchy is available: omarchy plugin remove $PLUGIN_ID --yes" \
      "Or by hand: rm -rf '$PLUGIN_DIR'"
  elif output=$(omarchy plugin remove "$PLUGIN_ID" --yes 2>&1); then
    ok "removed plugin $PLUGIN_ID"
    # `omarchy plugin remove` backs up a folder that is not a Git checkout;
    # tell the user where their copy went instead of hiding it.
    while IFS= read -r line; do
      [[ -n $line ]] && echo "      $line"
    done < <(printf '%s\n' "$output" | grep -E 'Backup at:|Unlinked|Removed|enabled and was unloaded|Restored' || true)
  else
    err "omarchy plugin remove failed: $(printf '%s' "$output" | tr '\n' ' ')" \
      "Retry with: omarchy plugin remove $PLUGIN_ID --yes"
  fi
else
  skip "not installed"
fi

echo ""
echo "  Your settings..."
if (( CONFIG_PRESENT )); then
  if (( PURGE )); then
    # Refuse anything that is not exactly this plugin's own config directory,
    # so a stray XDG_CONFIG_HOME can never widen the blast radius.
    if [[ $CONFIG_DIR == */wallpaper-video && $CONFIG_DIR != "/" && $CONFIG_DIR != "$HOME" ]]; then
      if rm -rf -- "$CONFIG_DIR"; then
        ok "deleted $CONFIG_DIR"
      else
        err "could not delete $CONFIG_DIR"
      fi
    else
      err "refusing to delete an unexpected path: $CONFIG_DIR"
    fi
  else
    skip "kept $CONFIG_DIR (run with --purge to delete it)"
  fi
elif (( CONFIG_LINK )); then
  link_target=$(readlink -- "$CONFIG_DIR" 2>/dev/null || true)
  if (( PURGE )); then
    # `rm` on a symlink removes the link itself; nothing behind it is
    # followed or deleted.
    if rm -- "$CONFIG_DIR"; then
      ok "removed the link $CONFIG_DIR${link_target:+ → $link_target (left in place)}"
    else
      err "could not remove the link $CONFIG_DIR" \
        "Remove it by hand: rm -- '$CONFIG_DIR'"
    fi
  else
    skip "kept the link $CONFIG_DIR (run with --purge to remove the link only)"
  fi
else
  skip "no settings directory"
fi

echo ""
if (( ERRORS > 0 )); then
  echo -e "\e[33mUnfinished: $ERRORS step(s) need attention.\e[0m"
  echo ""
  echo "  Left to do by hand:"
  for entry in "${PENDING[@]}"; do
    printf '  %s\n' "$entry"
  done
  echo ""
else
  echo -e "\e[32mUninstall complete.\e[0m"
  echo ""
fi
if (( CONFIG_PRESENT && ! PURGE )); then
  echo "  Your saved monitor assignments are still in:"
  echo "      $CONFIG_DIR"
  echo "  Delete them with:"
  echo "      bash uninstall.sh --purge --yes"
  echo ""
elif (( CONFIG_LINK && ! PURGE )); then
  echo "  Your saved assignments sit behind this link and are untouched:"
  echo "      $CONFIG_DIR -> $(readlink -- "$CONFIG_DIR" 2>/dev/null || echo '?')"
  echo "  Remove the link (never its target) with:"
  echo "      bash uninstall.sh --purge --yes"
  echo ""
fi
exit "$(( ERRORS > 0 ? 1 : 0 ))"
