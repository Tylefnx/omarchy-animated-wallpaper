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
- Selected videos persist across reboots (post-boot hook)
- Coexists with Omarchy's static wallpapers — `swaybg` runs underneath, theme commands keep working
- Full theme integration: colors, fonts, and bar styling follow your Omarchy theme

## Requirements

- [Omarchy](https://omarchy.org/) (Arch Linux + Hyprland, Quickshell shell)
- `mpvpaper` — `yay -S mpvpaper`
- `mpvpaper` must include the `--auto-pause` option
- `zenity` — usually pre-installed on Omarchy

The installer checks for these tools but does not install system packages. If
`zenity` is missing, it prints a `sudo pacman -S zenity` suggestion for you to
run yourself. Static images use Omarchy's `omarchy-theme-bg-set` command.

## Install

```bash
yay -S mpvpaper
bash install.sh
```

That's it. Left-click `󰕧` in the bar to toggle, right-click it to open the panel.

The installer adds the plugin with `omarchy plugin add`, places it in the bar's
right section, and installs a post-boot hook so your wallpapers come back after
login. Prefer doing it by hand?

```bash
omarchy plugin add https://github.com/Tylefnx/omarchy-animated-wallpaper.git --enable
omarchy hook install post-boot ~/.config/omarchy/plugins/r4venward.wallpaper-video/scripts/wallpaper-video-start
```

Developing? `bash install.sh --local` installs your working copy instead of
cloning from GitHub.

## Uninstall

```bash
bash uninstall.sh
```

Stops the wallpapers, removes the hook, the plugin, the bar entry, and the saved
per-monitor assignments and process records.

## Permissions and scope

The plugin runs as your desktop user. It does not request elevated permissions
or run `sudo`; the only privileged command shown is the optional package install
suggestion above, which you run yourself if needed.

| Area | What it does | Scope |
|------|--------------|-------|
| Install | Checks for `mpvpaper`, `zenity`, and Omarchy. `install.sh --local` copies this checkout; regular installation asks Omarchy to add the declared Git repository. | `~/.config/omarchy/plugins/r4venward.wallpaper-video/` |
| Bar and startup | Uses Omarchy commands to enable/place the plugin and register the selected post-boot hook. | Omarchy-managed plugin/bar entry and `~/.config/omarchy/hooks/post-boot.d/wallpaper-video-start` |
| Wallpaper state | Saves each monitor's selected video path, PID/start-time records, the selected image/video mode, and the base image used when videos start. | `${XDG_CONFIG_HOME:-~/.config}/wallpaper-video/` |
| Runtime commands | Reads monitor names from `hyprctl`; launches `mpvpaper`; opens `zenity` only when you choose a file; applies a chosen image with `omarchy-theme-bg-set`; may send a desktop notification if no wallpapers can start. | Current user session, selected local media, and `~/.local/state/omarchy/current/background` |
| Stop and cleanup | Stops only a recorded PID that still identifies as `mpvpaper` with the same process start time. Uninstall removes this plugin, its Omarchy hook, and this plugin's wallpaper state. | The plugin's own processes and paths listed above |

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
- **Choose static image** applies an image with Omarchy and stops active videos without clearing their assignments
- Each monitor row shows its assigned video (or `No video`) and lets you
  **Pick** a new video, **Start/Stop** that screen alone, or **Clear** the
  assignment

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
mpvpaper's native `--auto-pause` option pauses playback when the compositor
hides the wallpaper. Choosing a static image calls Omarchy's background setter,
stops active video layers, and remembers not to restore them at the next login;
choosing or starting a video switches back to video mode. If another Omarchy
background command changes the active image while videos are running, the plugin
stops those layers and leaves the new static image visible.

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
manifest.json          Omarchy plugin manifest (bar-widget)
Panel.qml              Bar icon + popup panel (Quickshell/QML)
Service.qml            Runs the engine script, mirrors its status
bin/wallpaper-video    The engine: mpvpaper lifecycle + assignments
scripts/wallpaper-video-start   post-boot hook
install.sh             plugin add + bar placement + hook
uninstall.sh           full removal
```

## License

MIT
