#!/bin/bash
set -euo pipefail

echo "=== Cerberus KWin Script Uninstaller ==="

# Disable Cerberus
kwriteconfig6 --file kwinrc --group Plugins --key cerberusEnabled false

# Remove the script package
if kpackagetool6 --type=KWin/Script -l 2>/dev/null | grep -q cerberus; then
    echo "Removing Cerberus..."
    kpackagetool6 --type=KWin/Script -r cerberus
fi

# Clean up saved state
kwriteconfig6 --file kwinrc --group Script-cerberus --key state --delete 2>/dev/null || true

# Stop and remove helper services
echo "Removing helper services..."
dbus-send --session --dest=com.cerberus.UI /com/cerberus/UI com.cerberus.UI.Quit 2>/dev/null || true
rm -f "$HOME/.local/bin/cerberus-state-helper"
rm -f "$HOME/.local/bin/cerberus-ui"
rm -f "$HOME/.local/share/dbus-1/services/com.cerberus.StateHelper.service"
rm -f "$HOME/.local/share/dbus-1/services/com.cerberus.UI.service"
rm -f "$HOME/.local/share/cerberus/state.json"
rm -rf "$HOME/.local/share/cerberus/venv"

# Restore previous plugins
echo ""
echo "Would you like to re-enable separate-screen-desktop-switch? (y/N)"
read -r response
if [[ "$response" =~ ^[Yy]$ ]]; then
    kwriteconfig6 --file kwinrc --group Plugins --key separate-screen-desktop-switchEnabled true
    kwriteconfig6 --file kwinrc --group Plugins --key separateoutputsEnabled true
    echo "Re-enabled separate-screen-desktop-switch and separateOutputs."
fi

# Reconfigure KWin
qdbus6 org.kde.KWin /KWin reconfigure

echo ""
echo "=== Cerberus uninstalled ==="
