#!/bin/bash
# check.sh — quality gates for this plugin.
#
#   bash scripts/check.sh
#
# Everything here runs offline against the checkout: no network, and no
# writes to your real Omarchy configuration. Checks that would need a live
# Hyprland session skip with a notice instead of pretending to pass.

set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
PLUGIN_ID="${PLUGIN_ID:-r4venward.wallpaper-video}"

PASS=0
FAIL=0
SKIP=0

ok() { printf '  \033[32m✓\033[0m %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  \033[31m✗\033[0m %s\n' "$1"; FAIL=$((FAIL + 1)); }
skip() { printf '  \033[33m·\033[0m %s\n' "$1"; SKIP=$((SKIP + 1)); }
section() { printf '\n%s\n' "$1"; }

# ---------------------------------------------------------------- shell
section "Shell syntax"
shell_files=(
  "$ROOT/install.sh"
  "$ROOT/uninstall.sh"
  "$ROOT/bin/wallpaper-video"
  "$ROOT/bin/lib/common.sh"
  "$ROOT/bin/lib/monitors.sh"
  "$ROOT/bin/lib/processes.sh"
  "$ROOT/bin/lib/actions.sh"
  "$ROOT/scripts/wallpaper-video-start"
  "$ROOT/scripts/check.sh"
  "$ROOT/scripts/install-scenarios.sh"
)
for file in "${shell_files[@]}"; do
  rel="${file#"$ROOT"/}"
  if [[ ! -e $file ]]; then bad "$rel is missing"; continue; fi
  if bash -n "$file" 2>/tmp/check-bashn.err; then
    ok "bash -n $rel"
  else
    bad "bash -n $rel: $(tr '\n' ' ' </tmp/check-bashn.err)"
  fi
done

if command -v shellcheck >/dev/null 2>&1; then
  if shellcheck -S error "${shell_files[@]}"; then
    ok "shellcheck (errors only)"
  else
    bad "shellcheck reported errors"
  fi
else
  skip "shellcheck not installed (optional)"
fi

# ------------------------------------------------------------- manifest
section "Manifest"
if jq -e . "$ROOT/manifest.json" >/dev/null 2>&1; then
  ok "manifest.json is valid JSON"
else
  bad "manifest.json is not valid JSON"
fi

manifest_id=$(jq -r '.id // empty' "$ROOT/manifest.json" 2>/dev/null || true)
if [[ -z $manifest_id ]]; then
  bad "manifest id is empty"
elif [[ $manifest_id != "$PLUGIN_ID" ]]; then
  bad "manifest id '$manifest_id' does not match the scripts' id '$PLUGIN_ID'"
else
  ok "manifest id matches install/uninstall/hook ($manifest_id)"
fi

if [[ -n $manifest_id ]] && grep -q "plugins/$manifest_id/" "$ROOT/scripts/wallpaper-video-start"; then
  ok "post-boot hook targets plugins/$manifest_id/"
else
  bad "post-boot hook does not target plugins/$manifest_id/"
fi

if jq -e '.entryPoints.barWidget == "Panel.qml"' "$ROOT/manifest.json" >/dev/null 2>&1; then
  ok "barWidget entry point resolves to Panel.qml"
else
  bad "barWidget entry point is not Panel.qml"
fi

# -------------------------------------------------- omarchy plugin schema
section "Omarchy plugin validation"
if command -v omarchy >/dev/null 2>&1; then
  if omarchy plugin validate "$ROOT" >/tmp/check-validate.out 2>&1; then
    ok "omarchy plugin validate"
  else
    bad "omarchy plugin validate: $(tr '\n' ' ' </tmp/check-validate.out)"
  fi
else
  skip "omarchy CLI not available — run this on an Omarchy machine"
fi

# ------------------------------------------------------------------- qml
section "QML"
# Only a Qt 6 qmllint understands this codebase. Qt 5's qmllint 1.0 rejects
# valid Qt 6 syntax and fails with no output at all, so it must never be
# mistaken for a real result.
QMLLINT=""
for candidate in /usr/lib/qt6/bin/qmllint /usr/lib/qt6/libexec/qmllint qmllint; do
  if [[ $candidate == */* ]]; then [[ -x $candidate ]] || continue
  else candidate=$(command -v "$candidate") || continue; fi
  version=$("$candidate" --version 2>&1) || continue
  [[ $version =~ qmllint\ (6|[2-9][0-9]*) ]] || continue
  QMLLINT="$candidate"
  break
done

if [[ -n $QMLLINT ]]; then
  ok "qmllint is Qt 6 ($("$QMLLINT" --version 2>&1 | head -1))"
  for file in "$ROOT/Panel.qml" "$ROOT/Service.qml"; do
    rel="${file#"$ROOT"/}"
    if "$QMLLINT" "$file" >/tmp/check-qmllint.out 2>&1; then
      ok "qmllint $rel parses (warnings about qs.* imports are expected outside Quickshell)"
    else
      bad "qmllint $rel: $(tr '\n' ' ' </tmp/check-qmllint.out)"
    fi
  done
elif command -v qmllint >/dev/null 2>&1; then
  skip "qmllint is Qt 5 ($(qmllint --version 2>&1 | head -1)) — cannot lint Qt 6 QML"
else
  skip "qmllint not installed"
fi

# -------------------------------------------------------------- engine
section "Engine (isolated config, real Omarchy state untouched)"
TMP_ROOT=$(mktemp -d) || { bad "could not create a temporary directory"; TMP_ROOT=""; }
cleanup() {
  if declare -F scen_teardown >/dev/null 2>&1; then scen_teardown; fi
  [[ -n ${TMP_ROOT:-} && -d $TMP_ROOT ]] && rm -rf -- "$TMP_ROOT"
}
trap cleanup EXIT

ENGINE="$ROOT/bin/wallpaper-video"
saved_xdg="${XDG_CONFIG_HOME-}"
export XDG_CONFIG_HOME="$TMP_ROOT/config"

expect_ok() {
  local label="$1"
  shift
  local out
  if out=$("$@" 2>&1); then
    ok "$label"
  else
    bad "$label → $(printf '%s' "$out" | tr '\n' ' ')"
  fi
}

expect_fail() {
  local label="$1"
  shift
  local out
  if out=$("$@" 2>&1); then
    bad "$label → expected failure but it succeeded"
  else
    ok "$label"
  fi
}

if [[ -n $TMP_ROOT ]]; then
  expect_ok "status --json runs" "$ENGINE" status --json
  if "$ENGINE" status --json | jq -e '
      (.monitors | type) == "array"
      and (.active | type) == "number"
      and (.total | type) == "number"
      and (.mode | type) == "string"' >/dev/null 2>&1; then
    ok "status --json has monitors/active/total/mode"
  else
    bad "status --json is missing required keys"
  fi

  expect_ok "status (text) runs" "$ENGINE" status
  expect_fail "unknown command is rejected" "$ENGINE" frobnicate
  expect_fail "unknown monitor is rejected" "$ENGINE" clear no-such-monitor
  expect_fail "path traversal in a monitor name is rejected" "$ENGINE" clear "../../etc"
  expect_fail "missing video file is rejected" "$ENGINE" set all "$TMP_ROOT/nope.mp4"
  expect_fail "unsupported file type is rejected" "$ENGINE" set all "$TMP_ROOT/notes.txt"

  # Nothing is assigned yet, so start/toggle must succeed without spawning a
  # single mpvpaper. Run these BEFORE any `set` below: once an assignment
  # exists, `start` would really launch a player.
  if command -v hyprctl >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
    expect_ok "start with no assignments is a valid idle state" "$ENGINE" start
    expect_ok "toggle with no assignments is a valid idle state" "$ENGINE" toggle
    expect_ok "stop is safe with nothing running" "$ENGINE" stop
  else
    skip "hyprctl/python3 unavailable — skipping idle start/toggle checks"
  fi
  if [[ -z $(ls -A "$XDG_CONFIG_HOME/wallpaper-video/pids" 2>/dev/null) ]]; then
    ok "no players were spawned for an empty configuration"
  else
    bad "an empty configuration spawned a player"
  fi

  if command -v hyprctl >/dev/null 2>&1 && command -v mpvpaper >/dev/null 2>&1; then
    monitor=$("$ENGINE" status --json | jq -r '.monitors[0].name // empty')
    if [[ -z $monitor ]]; then
      skip "no monitor reported by hyprctl — skipping assignment round-trip"
    else
      printf 'sample' >"$TMP_ROOT/sample.mp4"
      expect_ok "assign a video to $monitor" "$ENGINE" set "$monitor" "$TMP_ROOT/sample.mp4"
      if "$ENGINE" status --json | jq -e --arg m "$monitor" \
        '.monitors[] | select(.name == $m) | .video and .available' >/dev/null 2>&1; then
        ok "assignment is reported back with available=true"
      else
        bad "assignment is not reported back"
      fi
      expect_ok "clear the assignment" "$ENGINE" clear "$monitor"
      if "$ENGINE" status --json | jq -e --arg m "$monitor" \
        '.monitors[] | select(.name == $m) | (.video == "")' >/dev/null 2>&1; then
        ok "assignment is gone after clear"
      else
        bad "assignment survived clear"
      fi
      expect_ok "clear all is idempotent" "$ENGINE" clear all
      expect_ok "clear all is idempotent (second run)" "$ENGINE" clear all
    fi
  else
    skip "hyprctl/mpvpaper unavailable — skipping assignment round-trip"
  fi

  if [[ -z $(ls -A "$XDG_CONFIG_HOME/wallpaper-video/pids" 2>/dev/null) ]]; then
    ok "no player pid files were ever written outside the temp config"
  else
    bad "pid files leaked during the smoke test"
  fi
fi

if [[ -n ${saved_xdg+x} ]]; then export XDG_CONFIG_HOME="$saved_xdg"; else unset XDG_CONFIG_HOME; fi

# ------------------------------------------------------- post-boot hook
section "Post-boot hook (temp HOME)"
HOOK="$ROOT/scripts/wallpaper-video-start"
HOOK_HOME="$TMP_ROOT/hookhome"
HOOK_HELPER="$HOOK_HOME/.config/omarchy/plugins/$PLUGIN_ID/bin/wallpaper-video"
run_hook() { HOME="$HOOK_HOME" bash "$HOOK"; }

if [[ -n $TMP_ROOT ]]; then
  if out=$(run_hook 2>&1); then
    ok "hook exits 0 when the plugin is not installed"
  else
    bad "hook exits non-zero when the plugin is not installed → $(printf '%s' "$out" | tr '\n' ' ')"
  fi

  mkdir -p "$(dirname -- "$HOOK_HELPER")"
  printf '#!/bin/bash\nprintf "assigned video for DP-1 is missing\\n" >&2\nexit 1\n' >"$HOOK_HELPER"
  chmod +x "$HOOK_HELPER"
  status=0
  out=$(run_hook 2>&1) || status=$?
  if ((status == 0)) && [[ $out == *"assigned video for DP-1 is missing"* ]]; then
    ok "hook surfaces a failed start but never fails the boot"
  else
    bad "hook failed: exit=$status output=$(printf '%s' "$out" | tr '\n' ' ')"
  fi

  printf '#!/bin/bash\nexit 0\n' >"$HOOK_HELPER"
  if out=$(run_hook 2>&1); then
    ok "hook exits 0 on a successful start"
  else
    bad "hook exits non-zero on a successful start → $(printf '%s' "$out" | tr '\n' ' ')"
  fi
  rm -rf -- "$HOOK_HOME"
fi

# ------------------------------------------------------- install/uninstall
section "Installer scripts (temp HOME, dry run only)"
FAKE_HOME="$TMP_ROOT/home"
if [[ -n $TMP_ROOT ]]; then
  if HOME="$FAKE_HOME" XDG_CONFIG_HOME="$FAKE_HOME/.config" bash "$ROOT/install.sh" --dry-run \
    >/tmp/check-install-dry.out 2>&1; then
    ok "install.sh --dry-run exits 0"
  else
    bad "install.sh --dry-run: $(tr '\n' ' ' </tmp/check-install-dry.out)"
  fi
  if [[ ! -e "$FAKE_HOME/.config/omarchy" ]]; then
    ok "install.sh --dry-run changes nothing"
  else
    bad "install.sh --dry-run created $FAKE_HOME/.config/omarchy"
  fi

  if HOME="$FAKE_HOME" XDG_CONFIG_HOME="$FAKE_HOME/.config" bash "$ROOT/uninstall.sh" --dry-run \
    >/tmp/check-uninstall-dry.out 2>&1; then
    ok "uninstall.sh --dry-run exits 0 when nothing is installed"
  else
    bad "uninstall.sh --dry-run: $(tr '\n' ' ' </tmp/check-uninstall-dry.out)"
  fi

  # A dry run against a populated fake install must leave every artifact in
  # place — that is the whole point of the flag.
  mkdir -p "$FAKE_HOME/.config/omarchy/plugins/$PLUGIN_ID" \
    "$FAKE_HOME/.config/omarchy/hooks/post-boot.d" \
    "$FAKE_HOME/.config/wallpaper-video/monitors"
  printf '{}\n' >"$FAKE_HOME/.config/omarchy/plugins/$PLUGIN_ID/manifest.json"
  printf '#!/bin/bash\n' >"$FAKE_HOME/.config/omarchy/hooks/post-boot.d/wallpaper-video-start"
  printf '/tmp/sample.mp4\n' >"$FAKE_HOME/.config/wallpaper-video/monitors/DP-1"
  if HOME="$FAKE_HOME" XDG_CONFIG_HOME="$FAKE_HOME/.config" bash "$ROOT/uninstall.sh" --dry-run \
    >/tmp/check-uninstall-dry2.out 2>&1; then
    ok "uninstall.sh --dry-run exits 0 for a populated install"
  else
    bad "uninstall.sh --dry-run (populated): $(tr '\n' ' ' </tmp/check-uninstall-dry2.out)"
  fi
  if [[ -f "$FAKE_HOME/.config/wallpaper-video/monitors/DP-1" &&
        -f "$FAKE_HOME/.config/omarchy/hooks/post-boot.d/wallpaper-video-start" &&
        -d "$FAKE_HOME/.config/omarchy/plugins/$PLUGIN_ID" ]]; then
    ok "uninstall.sh --dry-run removes nothing"
  else
    bad "uninstall.sh --dry-run deleted something"
  fi
fi

# --------------------------------------------- install/uninstall failure paths
section "Install/uninstall scenarios (throwaway HOME, fake omarchy CLI)"
if [[ -z $TMP_ROOT ]]; then
  skip "no temporary directory — scenario suite not run"
elif ! command -v git >/dev/null 2>&1; then
  skip "git not installed — the install/uninstall scenario suite needs it"
else
  # shellcheck source=install-scenarios.sh
  source "$ROOT/scripts/install-scenarios.sh"
  scenario_suite
fi

# ----------------------------------------------------------------- summary
printf '\n%s\n' "────────────────────────────────────────"
printf '  %d passed · %d failed · %d skipped\n' "$PASS" "$FAIL" "$SKIP"
if ((FAIL > 0)); then
  printf '  \033[31mchecks failed\033[0m\n'
  exit 1
fi
printf '  \033[32mall checks passed\033[0m\n'
exit 0
