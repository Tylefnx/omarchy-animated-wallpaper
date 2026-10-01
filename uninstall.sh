#!/bin/bash
# uninstall.sh — remove the animated wallpaper plugin from Omarchy.

set -euo pipefail

PLUGIN_ID="r4venward.wallpaper-video"
PLUGIN_DIR="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/wallpaper-video"
HOOK_PATH="$HOME/.config/omarchy/hooks/post-boot.d/wallpaper-video-start"

OK="\e[32m✓\e[0m"
SKIP="\e[33m·\e[0m"

echo "→ Uninstalling animated wallpaper..."

# 1. Stop any wallpaper this plugin started
echo ""
echo "  Stopping wallpapers..."
if [[ -x "$PLUGIN_DIR/bin/wallpaper-video" ]]; then
  "$PLUGIN_DIR/bin/wallpaper-video" stop 2>/dev/null || true
  echo -e "  $OK wallpapers stopped"
else
  echo -e "  $SKIP plugin helper not found"
fi

# 2. Remove the post-boot hook
echo ""
echo "  Removing hooks..."
if [[ -f "$HOOK_PATH" ]]; then
  rm -f "$HOOK_PATH"
  echo -e "  $OK post-boot hook removed"
else
  echo -e "  $SKIP post-boot hook not found"
fi

# 3. Remove the plugin (deletes the bar entry and the plugin folder)
echo ""
echo "  Removing plugin..."
if [[ -d "$PLUGIN_DIR" ]]; then
  omarchy plugin remove "$PLUGIN_ID" --yes
  echo -e "  $OK plugin removed"
else
  echo -e "  $SKIP plugin not installed"
fi

# 4. Remove saved monitor assignments
echo ""
echo "  Removing config..."
if [[ -d "$CONFIG_DIR" ]]; then
  rm -rf "$CONFIG_DIR"
  echo -e "  $OK removed $CONFIG_DIR"
else
  echo -e "  $SKIP config not found"
fi

echo ""
echo -e "\e[32mUninstall complete.\e[0m"
echo ""
