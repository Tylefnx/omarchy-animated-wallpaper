#!/bin/bash
# install-scenarios.sh — install and uninstall paths, exercised for real.
#
# Sourced by scripts/check.sh so every scenario counts against the same
# PASS/FAIL/SKIP totals. Each scenario runs against a throwaway HOME with a
# fake `omarchy` / `omarchy-shell` on PATH: the real Omarchy configuration,
# plugin registry, hooks and running shell are never written to. The fakes
# refuse to run at all if they are ever pointed at a HOME outside the
# scenario root, so a leaked variable cannot reach the desktop.

SCEN_TMP="$TMP_ROOT/scen"
SCEN_BIN="$SCEN_TMP/bin"
SCEN_HOME="$SCEN_TMP/home"
SCEN_STATE="$SCEN_TMP/state"
SCEN_LOG="$SCEN_TMP/omarchy.log"
SCEN_REMOTE="$SCEN_TMP/remote"
SCEN_PIDS=()

scen_teardown() {
  local pid
  for pid in "${SCEN_PIDS[@]:-}"; do
    [[ -n $pid ]] && kill "$pid" 2>/dev/null || true
  done
  SCEN_PIDS=()
}

scen_setup() {
  rm -rf -- "$SCEN_TMP"
  mkdir -p "$SCEN_BIN" "$SCEN_HOME" "$SCEN_STATE"
  : >"$SCEN_LOG"

  cat >"$SCEN_BIN/omarchy" <<'FAKE'
#!/bin/bash
set -uo pipefail
# Refuse to touch anything unless HOME is the scenario root.
case "${HOME:-}" in
  "${SCEN_HOME:?}" | "${SCEN_HOME:?}/"*) ;;
  *)
    printf 'leak:%s\n' "${HOME:-}" >>"${SCEN_LEAK:?}"
    echo "fake omarchy: refusing to run with HOME=$HOME" >&2
    exit 1
    ;;
esac
printf '%s\n' "$*" >>"$SCEN_LOG"
case "${1:-} ${2:-}" in
  "plugin add")
    [[ -n ${SCEN_ADD_FAIL:-} ]] && { echo "plugin add failed on purpose"; exit 1; }
    dest="$HOME/.config/omarchy/plugins/$SCEN_ID"
    rm -rf -- "$dest"
    git clone -q -- "$SCEN_REMOTE" "$dest" || { echo "clone failed"; exit 1; }
    printf 'Added %s\n' "$SCEN_ID"
    ;;
  "plugin update")
    [[ -n ${SCEN_UPDATE_FAIL:-} ]] && { echo "update failed on purpose"; exit 1; }
    git -C "$HOME/.config/omarchy/plugins/$SCEN_ID" pull -q --ff-only ||
      { echo "pull --ff-only failed"; exit 1; }
    printf 'Updated %s\n' "$SCEN_ID"
    ;;
  "plugin validate")
    if ! jq -e 'type == "object" and (.id | type == "string") and (.id | length > 0)' \
      "${3:-/nonexistent}/manifest.json" >/dev/null 2>&1; then
      echo "invalid manifest at ${3:-}"; exit 1
    fi
    printf 'valid\n'
    ;;
  "plugin enable")
    [[ -n ${SCEN_ENABLE_FAIL:-} ]] && { echo "enable failed on purpose"; exit 1; }
    printf 'true\n' >"$SCEN_STATE/enabled"
    printf 'Enabled %s\n' "$SCEN_ID"
    ;;
  "plugin list")
    polls=$(( $(cat "$SCEN_STATE/polls" 2>/dev/null || printf 0) + 1 ))
    printf '%s\n' "$polls" >"$SCEN_STATE/polls"
    if [[ -f $SCEN_STATE/scanned ]] && (( polls > ${SCEN_DISCOVER_AFTER:-0} )); then
      printf '[{"id":"%s","enabled":%s}]\n' "$SCEN_ID" \
        "$(cat "$SCEN_STATE/enabled" 2>/dev/null || printf false)"
    else
      printf '[]\n'
    fi
    ;;
  "plugin remove")
    [[ -n ${SCEN_REMOVE_FAIL:-} ]] && { echo "remove failed on purpose"; exit 1; }
    rm -rf -- "$HOME/.config/omarchy/plugins/$3"
    printf 'Removed %s\n' "$3"
    ;;
  "hook install")
    [[ -n ${SCEN_HOOK_FAIL:-} ]] && { echo "hook install failed on purpose"; exit 1; }
    mkdir -p "$HOME/.config/omarchy/hooks/$3.d"
    cp -- "$4" "$HOME/.config/omarchy/hooks/$3.d/$(basename -- "$4")"
    chmod 755 "$HOME/.config/omarchy/hooks/$3.d/$(basename -- "$4")"
    printf 'Hook installed\n'
    ;;
  *) printf '{}\n' ;;
esac
FAKE

  cat >"$SCEN_BIN/omarchy-shell" <<'FAKE'
#!/bin/bash
set -uo pipefail
case "${HOME:-}" in
  "${SCEN_HOME:?}" | "${SCEN_HOME:?}/"*) ;;
  *)
    printf 'leak:%s\n' "${HOME:-}" >>"${SCEN_LEAK:?}"
    echo "fake omarchy-shell: refusing to run with HOME=$HOME" >&2
    exit 1
    ;;
esac
printf '%s\n' "$*" >>"$SCEN_LOG"
case "${1:-} ${2:-}" in
  "shell ping")
    [[ -n ${SCEN_SHELL_DOWN:-} ]] && exit 1
    exit 0
    ;;
  "shell rescanPlugins")
    [[ -n ${SCEN_RESCAN_FAIL:-} ]] && exit 1
    if [[ -d $HOME/.config/omarchy/plugins/${SCEN_ID:?} ]]; then
      printf 'scanned\n' >"$SCEN_STATE/scanned"
    fi
    exit 0
    ;;
esac
exit 0
FAKE

  chmod +x "$SCEN_BIN/omarchy" "$SCEN_BIN/omarchy-shell"

  # A local git remote built from this checkout: `omarchy plugin add` clones
  # from it instead of the network, so the update path is a real fast-forward.
  mkdir -p "$SCEN_REMOTE"
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --exclude='.git' "$ROOT/" "$SCEN_REMOTE/"
  else
    (cd "$ROOT" && tar --exclude=.git -cf - .) | tar -xf - -C "$SCEN_REMOTE"
  fi
  git -C "$SCEN_REMOTE" init -q
  git -C "$SCEN_REMOTE" add -A
  git -C "$SCEN_REMOTE" -c user.email=check@example.invalid -c user.name=check \
    commit -qm "fixture" >/dev/null 2>&1 || true
}

# scen_run <script> [args…] — sets SCEN_RC and SCEN_OUT.
scen_run() {
  local out rc=0
  out=$(HOME="$SCEN_HOME" \
    XDG_CONFIG_HOME="$SCEN_HOME/.config" \
    PATH="$SCEN_BIN:$PATH" \
    SCEN_HOME="$SCEN_HOME" SCEN_STATE="$SCEN_STATE" SCEN_LOG="$SCEN_LOG" \
    SCEN_LEAK="$SCEN_TMP/leak" \
    SCEN_REMOTE="$SCEN_REMOTE" SCEN_ID="$PLUGIN_ID" \
    bash "$@" </dev/null 2>&1) || rc=$?
  SCEN_RC=$rc
  SCEN_OUT=$out
}

scen_reset() {
  rm -rf -- "$SCEN_HOME"
  mkdir -p "$SCEN_HOME"
  : >"$SCEN_LOG"
  rm -rf -- "$SCEN_STATE"
  mkdir -p "$SCEN_STATE"
}

scen_has() { grep -q -- "$1" <<<"$2"; }
scen_log_has() { grep -q -- "$1" "$SCEN_LOG"; }
scen_log_count() { grep -c -- "$1" "$SCEN_LOG"; }

scen_out() { printf '%s' "$SCEN_OUT" | tr '\n' ' '; }

scen_plugin() { printf '%s/.config/omarchy/plugins/%s' "$SCEN_HOME" "$PLUGIN_ID"; }
scen_hook() { printf '%s/.config/omarchy/hooks/post-boot.d/wallpaper-video-start' "$SCEN_HOME"; }
scen_settings() { printf '%s/.config/wallpaper-video' "$SCEN_HOME"; }

# Fresh state plus a first successful install.
scen_installed() {
  scen_reset
  scen_run "$ROOT/install.sh"
  return "$SCEN_RC"
}

scen_start_player() {
  local monitor="$1" bin pid started file
  file="$(scen_settings)/pids/$monitor.pid"
  mkdir -p "$(dirname -- "$file")" "$(dirname -- "$SCEN_TMP/player/mpvpaper")"
  bin="$SCEN_TMP/player/mpvpaper"
  cp -- "$(command -v sleep)" "$bin" 2>/dev/null || cp -- /bin/sleep "$bin"
  "$bin" 900 >/dev/null 2>&1 &
  pid=$!
  SCEN_PIDS+=("$pid")
  started=$(scen_starttime "$pid") || return 1
  printf '%s %s\n' "$pid" "$started" >"$file"
  SCEN_PLAYER_PID=$pid
}

scen_starttime() {
  local stat rest
  IFS= read -r stat <"/proc/$1/stat" || return 1
  rest="${stat##*) }"
  # shellcheck disable=SC2086
  set -- $rest
  [[ $# -ge 20 ]] || return 1
  printf '%s' "${20}"
}

scen_player_alive() {
  kill -0 "${SCEN_PLAYER_PID:-0}" 2>/dev/null
}

# ------------------------------------------------------------- install paths
install_scenarios() {
  local plug hook backup head remote_head

  plug=$(scen_plugin)
  hook=$(scen_hook)

  scen_reset
  scen_run "$ROOT/install.sh"
  if ((SCEN_RC == 0)) && [[ -f $plug/manifest.json && -x $hook ]] &&
    scen_has "Installation complete" "$SCEN_OUT" &&
    scen_log_has "^plugin add "; then
    ok "fresh install clones the repo, installs the hook and enables the widget"
  else
    bad "fresh install → rc=$SCEN_RC $(scen_out)"
  fi
  if [[ -n $(ls -d "$plug".backup-* 2>/dev/null) ]]; then
    bad "a first install left a backup folder behind"
  else
    ok "a first install creates no backup folder"
  fi

  # --- re-run: fast-forward, idempotent, no second clone -------------------
  scen_run "$ROOT/install.sh"
  if ((SCEN_RC == 0)) && scen_has "fast-forward" "$SCEN_OUT" &&
    scen_has "already enabled" "$SCEN_OUT" &&
    [[ $(scen_log_count '^plugin add ') -eq 1 ]]; then
    ok "re-running fast-forwards without cloning again or moving the bar entry"
  else
    bad "re-run → rc=$SCEN_RC $(scen_out)"
  fi
  if [[ -n $(ls -d "$plug".backup-* 2>/dev/null) ]]; then
    bad "re-running a git install left a backup folder behind"
  else
    ok "re-running a git install leaves no backup folder behind"
  fi

  # --- update follows the remote ------------------------------------------
  printf 'fixture update\n' >>"$SCEN_REMOTE/README.md"
  git -C "$SCEN_REMOTE" add -A
  git -C "$SCEN_REMOTE" -c user.email=check@example.invalid -c user.name=check \
    commit -qm "advance" >/dev/null 2>&1
  scen_run "$ROOT/install.sh"
  head=$(git -C "$plug" rev-parse HEAD 2>/dev/null || printf missing)
  remote_head=$(git -C "$SCEN_REMOTE" rev-parse HEAD)
  if ((SCEN_RC == 0)) && [[ $head == "$remote_head" ]]; then
    ok "update fast-forwards the checkout to the new remote commit"
  else
    bad "update → rc=$SCEN_RC head=$head remote=$remote_head"
  fi

  # --- --local mirrors this checkout --------------------------------------
  printf 'stale\n' >"$plug/stale-file.txt"
  scen_run "$ROOT/install.sh" --local
  if ((SCEN_RC == 0)) && scen_has "every file found only in" "$SCEN_OUT" &&
    [[ ! -e $plug/stale-file.txt && -f $plug/Panel.qml && ! -e $plug/.git ]]; then
    ok "--local mirrors this checkout, removes stray files and drops .git"
  else
    bad "--local → rc=$SCEN_RC $(scen_out)"
  fi

  # --- --local refuses a folder it does not own ---------------------------
  scen_reset
  mkdir -p "$plug"
  printf '{"id":"someone.else"}\n' >"$plug/manifest.json"
  scen_run "$ROOT/install.sh" --local
  if ((SCEN_RC == 1)) && scen_has "belongs to someone.else" "$SCEN_OUT" &&
    [[ $(cat "$plug/manifest.json") == '{"id":"someone.else"}' ]]; then
    ok "--local refuses a folder owned by another plugin and writes nothing"
  else
    bad "--local over a foreign folder → rc=$SCEN_RC $(scen_out)"
  fi

  scen_reset
  mkdir -p "$SCEN_TMP/elsewhere" "$(dirname -- "$plug")"
  ln -s "$SCEN_TMP/elsewhere" "$plug"
  scen_run "$ROOT/install.sh" --local
  if ((SCEN_RC == 1)) && scen_has "is a symlink" "$SCEN_OUT" && [[ -L $plug ]]; then
    ok "--local refuses a symlinked folder and leaves the link in place"
  else
    bad "--local over a symlink → rc=$SCEN_RC $(scen_out)"
  fi

  # --- a non-Git copy is moved aside, never deleted ------------------------
  scen_installed
  rm -rf -- "$plug/.git"
  printf 'user edits\n' >"$plug/mine.txt"
  scen_run "$ROOT/install.sh"
  backup=$(ls -d "$plug".backup-* 2>/dev/null | head -1)
  if ((SCEN_RC == 0)) && [[ -n $backup && -f $backup/mine.txt && -d $plug/.git ]] &&
    scen_has "move the existing copy aside" "$SCEN_OUT" &&
    scen_has "Backup   $backup" "$SCEN_OUT"; then
    ok "a non-Git copy is kept as a backup while a fresh clone replaces it"
  else
    bad "replace → rc=$SCEN_RC backup=${backup:-none} $(scen_out)"
  fi

  # --- a failed clone puts the previous copy back --------------------------
  scen_installed
  rm -rf -- "$plug/.git"
  printf 'user edits\n' >"$plug/mine.txt"
  SCEN_ADD_FAIL=1 scen_run "$ROOT/install.sh"
  if ((SCEN_RC == 1)) && [[ -f $plug/mine.txt && ! -d $plug/.git ]] &&
    [[ -z $(ls -d "$plug".backup-* 2>/dev/null) ]] &&
    scen_has "the previous copy was put back" "$SCEN_OUT"; then
    ok "a failed clone restores the previous copy instead of leaving a hole"
  else
    bad "failed clone → rc=$SCEN_RC $(scen_out)"
  fi

  # --- discovery retries ---------------------------------------------------
  scen_reset
  SCEN_DISCOVER_AFTER=3 scen_run "$ROOT/install.sh"
  if ((SCEN_RC == 0)) && scen_has "enabled in the bar" "$SCEN_OUT"; then
    ok "widget enable waits for the shell to discover a freshly cloned plugin"
  else
    bad "delayed discovery → rc=$SCEN_RC $(scen_out)"
  fi

  scen_reset
  SCEN_DISCOVER_AFTER=9999 scen_run "$ROOT/install.sh"
  if ((SCEN_RC == 1)) && scen_has "has not discovered it" "$SCEN_OUT" &&
    scen_has "omarchy plugin enable" "$SCEN_OUT"; then
    ok "an undiscovered plugin fails with the exact commands to run next"
  else
    bad "undiscovered plugin → rc=$SCEN_RC $(scen_out)"
  fi

  # --- hook install failure ------------------------------------------------
  scen_reset
  SCEN_HOOK_FAIL=1 scen_run "$ROOT/install.sh"
  if ((SCEN_RC == 1)) && scen_has "omarchy hook install failed" "$SCEN_OUT" &&
    scen_has "chmod 755" "$SCEN_OUT" && [[ ! -e $hook ]]; then
    ok "a failed hook install is reported with the manual copy command"
  else
    bad "hook failure → rc=$SCEN_RC $(scen_out)"
  fi

  # --- enable failure ------------------------------------------------------
  scen_reset
  SCEN_ENABLE_FAIL=1 scen_run "$ROOT/install.sh"
  if ((SCEN_RC == 1)) && scen_has "could not enable" "$SCEN_OUT" &&
    scen_has "omarchy plugin enable" "$SCEN_OUT"; then
    ok "a failed widget enable is reported with the retry command"
  else
    bad "enable failure → rc=$SCEN_RC $(scen_out)"
  fi

  # --- shell not running ---------------------------------------------------
  scen_reset
  SCEN_SHELL_DOWN=1 scen_run "$ROOT/install.sh"
  if ((SCEN_RC == 1)) && scen_has "not enabled yet" "$SCEN_OUT" &&
    [[ -f $plug/manifest.json && -x $hook ]]; then
    ok "a stopped shell still installs the files and says what to run later"
  else
    bad "shell down → rc=$SCEN_RC $(scen_out)"
  fi

  # --- rescan failure on an update is tolerated ----------------------------
  scen_installed
  SCEN_RESCAN_FAIL=1 scen_run "$ROOT/install.sh"
  if ((SCEN_RC == 0)) && scen_has "fast-forward" "$SCEN_OUT"; then
    ok "a failing rescan during an update does not abort the install"
  else
    bad "rescan failure → rc=$SCEN_RC $(scen_out)"
  fi

  # --- dry run over a real install changes nothing -------------------------
  scen_installed
  local before after
  before=$(find "$SCEN_HOME" -printf '%P\n' 2>/dev/null | sort)
  scen_run "$ROOT/install.sh" --dry-run
  after=$(find "$SCEN_HOME" -printf '%P\n' 2>/dev/null | sort)
  if ((SCEN_RC == 0)) && [[ $before == "$after" ]] &&
    scen_has "nothing was changed" "$SCEN_OUT" &&
    scen_has "fast-forward" "$SCEN_OUT"; then
    ok "--dry-run reports the real plan and writes nothing"
  else
    bad "--dry-run → rc=$SCEN_RC $(scen_out)"
  fi
}

# ---------------------------------------------------------- uninstall paths
# A populated install: plugin folder, hook, settings and a PATH symlink.
scen_seed_uninstall() {
  local plug hook settings
  plug=$(scen_plugin)
  hook=$(scen_hook)
  settings=$(scen_settings)
  scen_reset
  mkdir -p "$(dirname -- "$hook")" "$plug" "$settings" "$SCEN_HOME/.local/bin"
  printf '{"id":"%s"}\n' "$PLUGIN_ID" >"$plug/manifest.json"
  printf 'sample\n' >"$settings/DP-1"
  cp -- "$ROOT/scripts/wallpaper-video-start" "$hook"
  chmod 755 "$hook"
  ln -sfn "$plug/bin/wallpaper-video" "$SCEN_HOME/.local/bin/wallpaper-video"
}

uninstall_scenarios() {
  local plug hook settings

  plug=$(scen_plugin)
  hook=$(scen_hook)
  settings=$(scen_settings)

  # --- a non-terminal without --yes changes nothing ------------------------
  scen_seed_uninstall
  scen_run "$ROOT/uninstall.sh"
  if ((SCEN_RC == 1)) && scen_has "refusing to uninstall without confirmation" "$SCEN_OUT" &&
    scen_has "will not be applied; confirmation is required" "$SCEN_OUT" &&
    [[ -x $hook && -f $plug/manifest.json && -f $settings/DP-1 ]]; then
    ok "uninstall refuses without --yes on a non-terminal and removes nothing"
  else
    bad "uninstall without --yes → rc=$SCEN_RC $(scen_out)"
  fi

  # --- dry run reports the refusal, keeps a running player -----------------
  scen_seed_uninstall
  scen_start_player DP-1
  scen_run "$ROOT/uninstall.sh" --dry-run
  if ((SCEN_RC == 0)) && scen_has "would refuse and exit 1 without --yes" "$SCEN_OUT" &&
    scen_has "Plan — a dry run" "$SCEN_OUT" &&
    [[ -x $hook && -f $plug/manifest.json && -f $settings/DP-1 ]] &&
    scen_player_alive; then
    ok "--dry-run states the future refusal, removes nothing and stops no player"
  else
    bad "uninstall --dry-run → rc=$SCEN_RC $(scen_out)"
  fi
  scen_teardown

  # --- --yes removes exactly what the plan listed --------------------------
  scen_seed_uninstall
  scen_start_player DP-1
  scen_run "$ROOT/uninstall.sh" --yes
  if ((SCEN_RC == 0)) &&
    scen_has "Plan — applied immediately (--yes)" "$SCEN_OUT" &&
    scen_has "Confirmation: skipped (--yes)" "$SCEN_OUT" &&
    scen_has "post-boot hook   $hook" "$SCEN_OUT" &&
    scen_has "plugin + bar entry   $plug" "$SCEN_OUT" &&
    scen_has "$settings" "$SCEN_OUT" &&
    [[ ! -e $hook && ! -e $plug &&
       ! -L $SCEN_HOME/.local/bin/wallpaper-video &&
       -f $settings/DP-1 ]] &&
    ! scen_player_alive; then
    ok "--yes removes the planned paths, keeps settings and stops the player"
  else
    bad "uninstall --yes → rc=$SCEN_RC alive=$(scen_player_alive && echo yes || echo no) $(scen_out)"
  fi
  scen_teardown

  # --- --purge removes exactly the settings directory ----------------------
  scen_seed_uninstall
  scen_run "$ROOT/uninstall.sh" --purge --yes
  if ((SCEN_RC == 0)) && [[ ! -e $settings && ! -e $hook && ! -e $plug ]] &&
    scen_has "deleted $settings" "$SCEN_OUT"; then
    ok "--purge deletes the settings directory and nothing else"
  else
    bad "--purge → rc=$SCEN_RC $(scen_out)"
  fi

  # --- a failing plugin removal is collected, not swallowed ----------------
  scen_seed_uninstall
  SCEN_REMOVE_FAIL=1 scen_run "$ROOT/uninstall.sh" --yes
  if ((SCEN_RC == 1)) && scen_has "Left to do by hand" "$SCEN_OUT" &&
    scen_has "Retry with: omarchy plugin remove" "$SCEN_OUT" &&
    scen_has "Unfinished: 1 step" "$SCEN_OUT" &&
    [[ -f $plug/manifest.json && ! -e $hook ]]; then
    ok "a failed removal exits 1 with an actionable list of what is left"
  else
    bad "plugin remove failure → rc=$SCEN_RC $(scen_out)"
  fi

  # --- a symlinked settings directory is never followed --------------------
  scen_seed_uninstall
  rm -rf -- "$settings"
  mkdir -p "$SCEN_TMP/real-settings"
  printf 'sample\n' >"$SCEN_TMP/real-settings/DP-1"
  ln -s "$SCEN_TMP/real-settings" "$settings"
  scen_run "$ROOT/uninstall.sh" --dry-run --yes
  local reported=0
  scen_has "the link $settings" "$SCEN_OUT" && reported=1
  scen_run "$ROOT/uninstall.sh" --purge --yes
  if ((SCEN_RC == 0 && reported)) &&
    [[ ! -L $settings && -f $SCEN_TMP/real-settings/DP-1 ]] &&
    scen_has "removed the link $settings" "$SCEN_OUT"; then
    ok "--purge removes only the symlink and never follows it"
  else
    bad "symlinked settings → rc=$SCEN_RC reported=$reported $(scen_out)"
  fi
}

# ------------------------------------------------------------- driver
REAL_HOME="${REAL_HOME:-$HOME}"

scen_real_snapshot() {
  local h="$REAL_HOME"
  {
    printf 'plugins:%s\n' "$(ls -1 "$h/.config/omarchy/plugins" 2>/dev/null | sort | tr '\n' ',')"
    printf 'plugins-dir:%s\n' "$(stat -c '%Y:%s' "$h/.config/omarchy/plugins" 2>/dev/null || printf none)"
    printf 'shell-json:%s\n' "$(stat -c '%Y:%s' "$h/.config/omarchy/shell.json" 2>/dev/null || printf none)"
    printf 'hook:%s\n' "$(stat -c '%Y:%s' "$h/.config/omarchy/hooks/post-boot.d/wallpaper-video-start" 2>/dev/null || printf none)"
    printf 'settings:%s\n' "$(stat -c '%Y:%s' "$h/.config/wallpaper-video" 2>/dev/null || printf none)"
  }
}

scenario_suite() {
  local before after
  before=$(scen_real_snapshot)
  scen_setup
  install_scenarios
  uninstall_scenarios
  scen_teardown
  after=$(scen_real_snapshot)

  if [[ -e $SCEN_TMP/leak ]]; then
    bad "a fake was invoked with a HOME outside its scenario root: $(tr '\n' ' ' <"$SCEN_TMP/leak")"
  else
    ok "no scenario ever ran with a HOME outside its throwaway root"
  fi
  if [[ $before == "$after" ]]; then
    ok "the real Omarchy configuration was not touched by any scenario"
  else
    bad "the real system changed during the scenario run"
  fi
}
