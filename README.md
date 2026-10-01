# motion-wallpaper-omarchy

Animated video wallpaper for [Omarchy](https://omarchy.org/) using [mpvpaper](https://github.com/GhostNaN/mpvpaper), as a native **Quickshell/Omarchy bar plugin** with a popup control panel.

![Omarchy plugin](https://img.shields.io/badge/omarchy-plugin-blue) ![Quickshell](https://img.shields.io/badge/quickshell-widget-green) ![Plug and play](https://img.shields.io/badge/install-plug%20%26%20play-brightgreen)

## Features

- Play any video (MP4, WebM, MKV, GIF...) as your desktop wallpaper
- **Per-monitor support** — assign a different video to each screen
- Bar icon: left-click toggles everything, right-click opens the panel
- Panel: per-monitor pick/start/stop/clear, global on/off switch, live status
- Videos loop automatically with no audio
- Videos automatically pause while the compositor hides the wallpaper, reducing idle CPU use
- Apply a static image through Omarchy without deleting saved per-monitor video assignments
- Missing or unreadable video assignments are shown in the panel
- Failures are reported where you are: in the panel with a Dismiss action, in
  the bar icon via the urgent tint, and from the post-boot hook as a
  notification
- Fully keyboard navigable panel (arrows to move, Enter to run, Esc to close)
- Selected videos persist across reboots (post-boot hook)
- Coexists with Omarchy's static wallpapers — `swaybg` runs underneath, theme commands keep working
- Full theme integration: colors, fonts, and bar styling follow your Omarchy theme

## Requirements

- [Omarchy](https://omarchy.org/) (Arch Linux + Hyprland, Quickshell shell)
- `mpvpaper` — `yay -S mpvpaper`
- `mpvpaper` must include the `--auto-pause` and `--auto-mode` options
- `zenity` — usually pre-installed on Omarchy

The installer checks for these tools but does not install system packages: each
missing dependency is reported with what to do about it — usually the exact
command to run yourself (for example `sudo pacman -S zenity`,
`sudo pacman -S jq`, `sudo pacman -S python`). It also verifies that `omarchy`
and `hyprctl` are present and that mpvpaper supports both options. Static
images use Omarchy's `omarchy-theme-bg-set` command.

## Install

```bash
yay -S mpvpaper
bash install.sh
```

That's it. Left-click `󰕧` in the bar to toggle, right-click it to open the panel.

The installer verifies every dependency with an actionable hint, runs
`omarchy plugin validate`, registers the post-boot hook, and places the widget
in the bar's right section **only if it is not placed yet** — re-running it
never moves a widget you have relocated. A running shell is detected and
refreshed, so the icon appears without a logout; if the shell is not running
it tells you exactly what to run instead of failing silently.

| Flag | Effect |
|------|--------|
| `--dry-run` | Print every step — including any backup or overwrite — without touching your system |
| `--local` | Mirror this checkout over the installed copy instead of cloning from GitHub |
| `--help` | Show usage |

Re-running `bash install.sh` updates an existing install in place: a
git-managed folder is fast-forwarded by Omarchy, and your configuration is
never touched. If that folder is **no longer a git checkout** the installer
moves it aside as `<plugin>.backup-<timestamp>` and clones fresh — the old
copy stays on disk, it is never deleted, so anything you had edited in it is
still there when the run finishes.

`--local` is the development path: it mirrors *this* checkout over the
installed copy with `rsync --delete`, so files found only in the installed
copy are removed. Before doing that it verifies the target really is this
plugin's own folder and refuses anything else — a folder without
`manifest.json`, a folder belonging to a different plugin id, or a symlink.

Prefer doing it by hand?

```bash
omarchy plugin add https://github.com/Tylefnx/omarchy-animated-wallpaper.git --enable
omarchy hook install post-boot ~/.config/omarchy/plugins/r4venward.wallpaper-video/scripts/wallpaper-video-start
```

## Uninstall

```bash
bash uninstall.sh
```

Stops the wallpapers, removes the hook, the plugin and its bar entry — and
**keeps your videos, assignments and settings** by default, so reinstalling
picks up where you left off.

| Flag | Effect |
|------|--------|
| `--dry-run` | List what would be removed and change nothing |
| `--purge` | Also delete `${XDG_CONFIG_HOME:-~/.config}/wallpaper-video` |
| `--yes` | Skip the confirmation prompt (required when not on a terminal) |

```bash
bash uninstall.sh --purge --yes   # remove everything, no prompts
```

## Permissions and scope

The plugin runs as your desktop user. It does not request elevated permissions
or run `sudo`; the only privileged command shown is the optional package install
suggestion above, which you run yourself if needed.

| Area | What it does | Scope |
|------|--------------|-------|
| Install | Checks for `mpvpaper`, `zenity`, and Omarchy. `install.sh --local` mirrors this checkout over the plugin folder after confirming the folder is this plugin's own; regular installation asks Omarchy to add the declared Git repository, moving a non-Git copy aside as a backup first. | `~/.config/omarchy/plugins/r4venward.wallpaper-video/` |
| Bar and startup | Uses Omarchy commands to enable/place the plugin and register the selected post-boot hook. | Omarchy-managed plugin/bar entry and `~/.config/omarchy/hooks/post-boot.d/wallpaper-video-start` |
| Wallpaper state | Saves each monitor's selected video path, PID/start-time records, the selected image/video mode, and the base image used when videos start. | `${XDG_CONFIG_HOME:-~/.config}/wallpaper-video/` |
| Runtime commands | Reads monitor names from `hyprctl`; launches `mpvpaper`; opens `zenity` only when you choose a file; applies a chosen image with `omarchy-theme-bg-set`; the post-boot hook notifies if a saved wallpaper cannot start. | Current user session, selected local media, and `~/.local/state/omarchy/current/background` |
| Stop and cleanup | Stops only a recorded PID that still identifies as `mpvpaper` with the same process start time. Uninstall removes this plugin and its Omarchy hook; your wallpaper state is kept unless you pass `--purge`. | The plugin's own processes and paths listed above |

The helper does not kill arbitrary `mpvpaper` processes, edit theme files, or
change unrelated user configuration. Applying an image uses Omarchy's supported
background command and never writes into theme directories. Runtime playback
uses local files; network access occurs only when Omarchy installs or updates
the plugin.

## Usage

### Bar

| Action | Result |
|--------|--------|
| Left click | Toggle all wallpapers on/off |
| Right click | Open the control panel |
| Middle click | Refresh status |
| Hover | Per-monitor status tooltip |

### Panel

- **Toggle switch** in the header turns everything on/off
- **Choose static image** applies an image with Omarchy and stops active videos
  without clearing their assignments; **Refresh** re-reads state at any time,
  even while a command runs
- Each monitor row shows its assigned video (or `No video`) and lets you
  **Pick** a new video, **Start/Stop** that screen alone, or **Clear** the
  assignment
- With nothing assigned yet, **Choose video for a monitor…** picks one file and
  assigns it to every monitor
- A failed command stays visible with a **Dismiss** action instead of
  disappearing on the next status poll

#### Keyboard

| Key | Result |
|-----|--------|
| Arrow keys (or `hjkl`) | Move the highlight — down/up changes rows, left/right changes actions |
| Enter / Space | Run the highlighted control |
| Esc | Close the panel |
| Tab | Switch to the next plugin panel |
| `t` | Toggle all wallpapers |
| `r` | Refresh status |

Mouse hover moves the same highlight, so there is only ever one highlighted
control on screen.

### Settings

Right-click the bar widget → settings (or `omarchy bar set`):

| Key | Values | Effect |
|-----|--------|--------|
| `barLabel` | `Nothing` / `Active monitors` | Show `1/2` style active/total next to the icon |

### Terminal

The engine script is also usable on its own:

| Command | Result |
|---------|--------|
| `wallpaper-video status [--json]` | Show status as text or JSON |
| `wallpaper-video start [monitor]` | Start wallpapers (all or one monitor) |
| `wallpaper-video stop [monitor]` | Stop wallpapers (only ones it started) |
| `wallpaper-video toggle` | Toggle everything |
| `wallpaper-video set <monitor\|all> <file>` | Assign a video |
| `wallpaper-video clear <monitor\|all>` | Remove an assignment |
| `wallpaper-video pick [monitor]` | File picker (zenity) |
| `wallpaper-video image [file]` | Choose or apply a static image through Omarchy |
| `wallpaper-video reconcile` | Stop videos when Omarchy's base image changes |

The script lives inside the plugin folder:
`~/.config/omarchy/plugins/r4venward.wallpaper-video/bin/wallpaper-video` —
symlink it to `~/.local/bin` if you want it on your PATH.

### IPC

```bash
omarchy-shell r4venward.wallpaper-video toggle    # open/close the panel
omarchy-shell r4venward.wallpaper-video start
omarchy-shell r4venward.wallpaper-video stop
omarchy-shell r4venward.wallpaper-video pick DP-1
```

## How it works

mpvpaper renders a video directly on the Wayland layer below your windows, on
top of the static wallpaper managed by `swaybg`. Stopping the animated wallpaper
removes that layer, restoring your normal Omarchy wallpaper. Omarchy theme and
wallpaper commands (`omarchy theme set`, `omarchy theme bg next`) are unaffected.
mpvpaper runs with `--auto-pause -a MAX`, so playback pauses while a
fullscreen or maximized window covers the screen and resumes as soon as the
desktop is visible again — no process is killed in the process. Choosing a
static image calls Omarchy's background setter, stops active video layers, and
remembers not to restore them at the next login; choosing or starting a video
switches back to video mode. If another Omarchy background command changes the
active image while videos are running, the plugin stops those layers and leaves
the new static image visible.

The helper only signals mpvpaper processes whose PID it recorded under
`~/.config/wallpaper-video/pids/`, and verifies `/proc/<pid>/comm` immediately
before signalling. Each player gets a dedicated session so its process group
can be stopped cleanly. Monitor names are validated before they become file
paths; assignments and PID records are written atomically with user-only
permissions. Status polling runs while the panel is open and after actions.
The engine is split into focused modules under `bin/lib/` for shared paths,
monitor discovery, process ownership, and actions.

`status --json` includes an `available` boolean for each monitor assignment,
indicating whether the configured video exists and can be read, plus a `mode`
field (`video`, `image`, or `off`).

## Layout

```
manifest.json                     Omarchy plugin manifest (bar-widget)
Panel.qml                         Bar icon + popup panel (Quickshell/QML)
Service.qml                       Runs the engine script, mirrors its status
bin/wallpaper-video               The engine: mpvpaper lifecycle + assignments
bin/lib/                          Shared paths, monitor discovery, process
                                  ownership, and actions
scripts/wallpaper-video-start     Post-boot hook
scripts/check.sh                  Offline quality gates
install.sh                        Dependency checks + plugin add + bar + hook
uninstall.sh                      Full removal (keeps your data by default)
```

## Development

```bash
bash scripts/check.sh
```

Runs the quality gates offline: shell syntax, manifest and
`omarchy plugin validate`, Qt 6 `qmllint`, an isolated engine smoke test in a
throwaway config, post-boot hook behaviour, and installer dry runs. Nothing
writes to your real Omarchy configuration, and tools that are not installed
(for example `shellcheck`) are reported as skipped rather than passing
silently.

## License

MIT
