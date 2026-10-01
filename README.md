# motion-wallpaper-omarchy

Animated video wallpaper for [Omarchy](https://omarchy.org/) using [mpvpaper](https://github.com/GhostNaN/mpvpaper), as a native **Quickshell/Omarchy bar plugin** with a popup control panel.

![Omarchy plugin](https://img.shields.io/badge/omarchy-plugin-blue) ![Quickshell](https://img.shields.io/badge/quickshell-widget-green) ![Plug and play](https://img.shields.io/badge/install-plug%20%26%20play-brightgreen)

## Features

- Play any video (MP4, WebM, MKV, GIF...) as your desktop wallpaper
- **Per-monitor support** — assign a different video to each screen
- Bar icon: left-click toggles everything, right-click opens the panel
- Panel: per-monitor pick/start/stop/clear, global on/off switch, live status
- Videos loop automatically with no audio
- Selected videos persist across reboots (post-boot hook)
- Coexists with Omarchy's static wallpapers — `swaybg` runs underneath, theme commands keep working
- Full theme integration: colors, fonts, and bar styling follow your Omarchy theme

## Requirements

- [Omarchy](https://omarchy.org/) (Arch Linux + Hyprland, Quickshell shell)
- `mpvpaper` — `yay -S mpvpaper`
- `zenity` — usually pre-installed on Omarchy

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
config. Leaves no traces.

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

The plugin only ever kills mpvpaper processes it started itself: each instance
records its PID under `~/.config/wallpaper-video/pids/`, and a PID is only
signalled after `/proc/<pid>/comm` still confirms it is mpvpaper.

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
