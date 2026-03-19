#!/bin/bash
# uninstall.sh — removes wallpaper-video from Omarchy

set -euo pipefail

WAYBAR_CONFIG="$HOME/.config/waybar/config.jsonc"
WAYBAR_STYLE="$HOME/.config/waybar/style.css"

OK="\e[32m✓\e[0m"
SKIP="\e[33m·\e[0m"

echo "→ Uninstalling wallpaper-video..."

# 1. Stop any running instance
echo ""
echo "  Stopping wallpaper..."
if pgrep -x mpvpaper > /dev/null; then
  pkill -x mpvpaper 2>/dev/null || true
  echo -e "  $OK mpvpaper stopped"
else
  echo -e "  $SKIP mpvpaper was not running"
fi

# 2. Remove script
echo ""
echo "  Removing files..."
if [[ -f "$HOME/.local/bin/wallpaper-video" ]]; then
  rm "$HOME/.local/bin/wallpaper-video"
  echo -e "  $OK Removed ~/.local/bin/wallpaper-video"
else
  echo -e "  $SKIP ~/.local/bin/wallpaper-video not found"
fi

if [[ -d "$HOME/.config/wallpaper-video" ]]; then
  rm -rf "$HOME/.config/wallpaper-video"
  echo -e "  $OK Removed ~/.config/wallpaper-video"
else
  echo -e "  $SKIP ~/.config/wallpaper-video not found"
fi

# 3. Remove from waybar config
echo ""
echo "  Cleaning up waybar config..."

if [[ -f "$WAYBAR_CONFIG" ]]; then
  python3 - "$WAYBAR_CONFIG" << 'PYEOF'
import sys

path = sys.argv[1]
with open(path, 'r') as f:
    lines = f.readlines()

out = []
skip = False
depth = 0

for line in lines:
    # Remove from modules-right array
    stripped = line.strip().rstrip(',')
    if stripped == '"custom/wallpaper-video"':
        # Also remove trailing comma from previous line if needed
        if out and out[-1].rstrip().endswith(','):
            out[-1] = out[-1].rstrip()[:-1] + '\n'
        continue

    # Detect start of wallpaper-video definition block
    if '"custom/wallpaper-video":' in line and '{' in line:
        skip = True
        depth = line.count('{') - line.count('}')
        continue

    if skip:
        depth += line.count('{') - line.count('}')
        if depth <= 0:
            skip = False
        continue

    out.append(line)

with open(path, 'w') as f:
    f.writelines(out)
PYEOF
  echo -e "  $OK Module removed from waybar config"
else
  echo -e "  $SKIP Waybar config not found"
fi

# 4. Remove CSS from style.css
if [[ -f "$WAYBAR_STYLE" ]]; then
  python3 - "$WAYBAR_STYLE" << 'PYEOF'
import sys

path = sys.argv[1]
with open(path, 'r') as f:
    lines = f.readlines()

out = []
skip = False

i = 0
while i < len(lines):
    if '/* wallpaper-video */' in lines[i]:
        skip = True
    if skip and lines[i].strip() == '' and i > 0 and '}' in lines[i-1]:
        skip = False
        i += 1
        continue
    if not skip:
        out.append(lines[i])
    i += 1

with open(path, 'w') as f:
    f.writelines(out)
PYEOF
  echo -e "  $OK CSS removed from style.css"
else
  echo -e "  $SKIP style.css not found"
fi

# 5. Restart waybar
echo ""
echo "  Restarting waybar..."
if command -v omarchy-restart-waybar &>/dev/null; then
  omarchy-restart-waybar
else
  pkill waybar 2>/dev/null || true
  sleep 0.5
  waybar & disown
fi
echo -e "  $OK Waybar restarted"

echo ""
echo -e "\e[32mUninstall complete.\e[0m"
echo ""
