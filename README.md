# motion-wallpaper-omarchy

Animated video wallpaper for [Omarchy](https://omarchy.org/) using [mpvpaper](https://github.com/GhostNaN/mpvpaper), with a Waybar control module.

![Waybar module: active](https://img.shields.io/badge/waybar-module-blue) ![Wayland](https://img.shields.io/badge/wayland-compatible-green) ![Plug and play](https://img.shields.io/badge/install-plug%20%26%20play-brightgreen)

## Features

- Play any video (MP4, WebM, MKV, GIF...) as your desktop wallpaper
- **Per-monitor support** — assign a different video to each screen
- Toggle on/off with one click from the taskbar
- Right-click to pick a video via file picker (asks which monitor if you have multiple)
- Coexists with Omarchy's static wallpapers — `swaybg` runs underneath, theme commands keep working
- Waybar button shows current state (active/inactive) with a tooltip per monitor
- Videos loop automatically with no audio
- Selected videos persist across reboots

## Requirements

- [Omarchy](https://omarchy.org/) (Arch Linux + Hyprland)
- [mpvpaper](https://github.com/GhostNaN/mpvpaper) — `yay -S mpvpaper`
- `zenity` — usually pre-installed on Omarchy

## Install

The installer is fully automated — it handles everything including the Waybar integration.

```bash
yay -S mpvpaper
bash install.sh
```

That's it. Right-click `󰕧 Wallpaper` in the bar to select a video.

## Uninstall

```bash
bash uninstall.sh
```

Removes the script, saved config, Waybar module, and CSS. Leaves no traces.

## Usage

### Waybar button

| Action | Result |
|--------|--------|
| Left click | Toggle wallpaper on/off |
| Right click | Open monitor + video picker |
| Hover | See per-monitor status |

### Terminal

| Command | Result |
|---------|--------|
| `wallpaper-video start` | Start all configured wallpapers |
| `wallpaper-video stop` | Stop all wallpapers |
| `wallpaper-video toggle` | Toggle on/off |
| `wallpaper-video pick` | Open monitor + video picker |

### Per-monitor setup

When multiple monitors are detected, right-clicking the Waybar button shows a list to choose which screen to configure (or all at once). Each monitor's video is saved independently in `~/.config/wallpaper-video/monitors/<name>`.

## How it works

mpvpaper renders a video directly on the Wayland layer below your windows, on top of the static wallpaper managed by `swaybg`. Stopping the animated wallpaper simply removes that layer, restoring your normal Omarchy wallpaper. Omarchy theme and wallpaper commands (`omarchy-theme-set`, `omarchy-theme-bg-next`) are unaffected.

## License

MIT
