#!/bin/bash
# install.sh — installs wallpaper-video on Omarchy (plug and play)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WAYBAR_CONFIG="$HOME/.config/waybar/config.jsonc"
WAYBAR_STYLE="$HOME/.config/waybar/style.css"

# Colors
OK="\e[32m✓\e[0m"
SKIP="\e[33m·\e[0m"
ERR="\e[31m✗\e[0m"

echo "→ Installing wallpaper-video..."

# 1. Dependencies
echo ""
echo "  Checking dependencies..."

if ! command -v mpvpaper &>/dev/null; then
  echo -e "  $ERR mpvpaper is not installed. Install it with: yay -S mpvpaper"
  exit 1
fi
echo -e "  $OK mpvpaper found"

if ! command -v zenity &>/dev/null; then
  echo -e "  $ERR zenity is not installed. Install it with: sudo pacman -S zenity"
  exit 1
fi
echo -e "  $OK zenity found"

# 2. Main script
echo ""
echo "  Installing script..."
install -Dm755 "$SCRIPT_DIR/bin/wallpaper-video" "$HOME/.local/bin/wallpaper-video"
echo -e "  $OK Script installed at ~/.local/bin/wallpaper-video"

# 3. Add ~/.local/bin to systemd user PATH (required for waybar)
mkdir -p "$HOME/.config/environment.d"
if [[ ! -f "$HOME/.config/environment.d/local-bin.conf" ]]; then
  echo 'PATH=$HOME/.local/bin:$PATH' > "$HOME/.config/environment.d/local-bin.conf"
  echo -e "  $OK ~/.local/bin added to systemd PATH"
else
  echo -e "  $SKIP systemd PATH already configured"
fi

# 4. Waybar: add module to config
echo ""
echo "  Configuring waybar..."

if [[ ! -f "$WAYBAR_CONFIG" ]]; then
  echo -e "  $ERR Waybar config not found at $WAYBAR_CONFIG"
  exit 1
fi

# 4a+4b. Add module to modules-right and add definition (Python for reliability)
python3 - "$WAYBAR_CONFIG" << 'PYEOF'
import sys, re

path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

# Add to modules-right array (only if not already present)
if '"custom/wallpaper-video"' not in content:
    content = re.sub(
        r'("custom/gdrive-countdown")',
        r'\1,\n    "custom/wallpaper-video"',
        content,
        count=1
    )
    print("  added to modules-right")
else:
    print("  modules-right already up to date")

# Add module definition (only if not already present)
module_def = '''  "custom/wallpaper-video": {
    "exec": "$HOME/.local/bin/wallpaper-video status",
    "return-type": "json",
    "interval": "once",
    "signal": 11,
    "on-click": "$HOME/.local/bin/wallpaper-video toggle",
    "on-click-right": "$HOME/.local/bin/wallpaper-video pick",
    "tooltip": true
  },\n'''

if '"custom/wallpaper-video":' not in content:
    # Insert before the "custom/gdrive-countdown": { definition
    content = re.sub(
        r'(\s*"custom/gdrive-countdown":\s*\{)',
        '\n' + module_def + r'\1',
        content,
        count=1
    )
    print("  module definition added")
else:
    print("  module definition already exists")

with open(path, 'w') as f:
    f.write(content)
PYEOF
  echo -e "  $OK Waybar config updated"

# 5. Waybar: add CSS
if grep -q 'wallpaper-video' "$WAYBAR_STYLE"; then
  echo -e "  $SKIP CSS already present in style.css"
else
  cat >> "$WAYBAR_STYLE" << 'CSSEOF'

/* wallpaper-video */
#custom-wallpaper-video {
  margin-left: 14px;
  padding-left: 14px;
  border-left: 1px solid;
  opacity: 0.6;
  transition: all 0.2s ease;
}
#custom-wallpaper-video:hover {
  opacity: 1;
}
#custom-wallpaper-video.active {
  color: #a6e3a1;
  opacity: 1;
}
#custom-wallpaper-video.inactive {
  opacity: 0.4;
}
CSSEOF
  echo -e "  $OK CSS added to style.css"
fi

# 6. Restart waybar
echo ""
echo "  Restarting waybar..."
if command -v omarchy-restart-waybar &>/dev/null; then
  omarchy-restart-waybar
  echo -e "  $OK Waybar restarted"
else
  pkill waybar 2>/dev/null || true
  sleep 0.5
  waybar &
  disown
  echo -e "  $OK Waybar restarted"
fi

echo ""
echo -e "\e[32mInstallation complete!\e[0m"
echo ""
echo "  Right-click '󰕧 Wallpaper' in the bar to select a video."
echo ""
