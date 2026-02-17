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
