#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SHORTCUTS="$HOME/.config/kglobalshortcutsrc"

echo "=== Cerberus KWin Script Installer ==="

# Step 1: Disable conflicting plugins
echo "Disabling conflicting plugins..."
kwriteconfig6 --file kwinrc --group Plugins --key separate-screen-desktop-switchEnabled false
kwriteconfig6 --file kwinrc --group Plugins --key separateoutputsEnabled false

# Step 2: Disable Cerberus if previously installed (needed for clean shortcut purge)
kwriteconfig6 --file kwinrc --group Plugins --key cerberusEnabled false
qdbus6 org.kde.KWin /KWin reconfigure 2>/dev/null || true
sleep 1

# Step 3: Purge stale Cerberus shortcut actions from kglobalaccel
echo "Purging stale shortcut registrations..."
dbus-send --session --dest=org.kde.kglobalaccel /component/kwin \
    org.kde.kglobalaccel.Component.cleanUp 2>/dev/null || true
sed -i '/^Cerberus:/d' "$SHORTCUTS" 2>/dev/null || true

# Step 3b: Explicitly unregister all cached Cerberus shortcuts
# (cleanUp alone doesn't clear kglobalaccel's persistent binding cache)
echo "Unregistering cached Cerberus shortcuts..."
for i in $(seq 1 20); do
    dbus-send --session --dest=org.kde.kglobalaccel /kglobalaccel \
        org.kde.KGlobalAccel.unregister \
        string:"kwin" string:"Cerberus: Switch to Workspace $i" 2>/dev/null || true
    dbus-send --session --dest=org.kde.kglobalaccel /kglobalaccel \
        org.kde.KGlobalAccel.unregister \
        string:"kwin" string:"Cerberus: Send to Workspace $i" 2>/dev/null || true
done
for name in "Next Empty Workspace" "Previous Empty Workspace" \
            "Send to Next Empty Workspace" "Send to Previous Empty Workspace" \
            "Tile Windows" "Refresh Monitors" \
            "Toggle Overlays" "Name Workspace" "Show Workspace Map" "Show Help"; do
    dbus-send --session --dest=org.kde.kglobalaccel /kglobalaccel \
        org.kde.KGlobalAccel.unregister \
        string:"kwin" string:"Cerberus: $name" 2>/dev/null || true
done

# Step 4: Clear conflicting KDE shortcuts
echo "Clearing conflicting KDE shortcuts..."
if [ -f "$SHORTCUTS" ]; then
    sed -i 's/^Switch to Desktop \([0-9]*\)=[^,]*/Switch to Desktop \1=none/' "$SHORTCUTS"
    sed -i 's/^Window to Desktop \([0-9]*\)=[^,]*/Window to Desktop \1=none/' "$SHORTCUTS"
    sed -i 's/^Toggle Tiles Editor=[^,]*/Toggle Tiles Editor=Meta+T/' "$SHORTCUTS"
fi
# Also clear via DBus (config file alone is insufficient for Window to Desktop)
for i in $(seq 1 20); do
    dbus-send --session --dest=org.kde.kglobalaccel /kglobalaccel \
        org.kde.KGlobalAccel.setForeignShortcut \
        "array:string:kwin,Window to Desktop $i,KWin,Window to Desktop $i" \
        array:int32:0 2>/dev/null || true
    sleep 0.1
done
dbus-send --session --dest=org.kde.kglobalaccel /kglobalaccel \
    org.kde.KGlobalAccel.setForeignShortcut \
    "array:string:kwin,Toggle Tiles Editor,KWin,Toggle Tiles Editor" \
    array:int32:0 2>/dev/null || true

# Step 5: Install D-Bus helper services
echo "Installing helper services..."
HELPER_DIR="$HOME/.local/bin"
DBUS_SERVICES="$HOME/.local/share/dbus-1/services"
mkdir -p "$HELPER_DIR" "$DBUS_SERVICES"

# State helper (persistence)
cp "$SCRIPT_DIR/cerberus-state-helper" "$HELPER_DIR/cerberus-state-helper"
chmod +x "$HELPER_DIR/cerberus-state-helper"
cat > "$DBUS_SERVICES/com.cerberus.StateHelper.service" <<DBUSEOF
[D-BUS Service]
Name=com.cerberus.StateHelper
Exec=$HELPER_DIR/cerberus-state-helper
DBUSEOF

# UI helper (overlays and dialogs) — needs PyQt6 venv + system Qt6 libs
VENV_DIR="$HOME/.local/share/cerberus/venv"
if [ ! -d "$VENV_DIR" ] || ! "$VENV_DIR/bin/python3" -c "import PyQt6" 2>/dev/null; then
    echo "Creating Python venv with PyQt6..."
    python3 -m venv --system-site-packages "$VENV_DIR"
    "$VENV_DIR/bin/pip" install --quiet PyQt6
    # Remove bundled Qt6 libs — use system Qt6 + layer-shell-qt instead
    "$VENV_DIR/bin/pip" uninstall -y PyQt6-Qt6 2>/dev/null || true
fi

cp "$SCRIPT_DIR/cerberus-ui" "$HELPER_DIR/cerberus-ui"
chmod +x "$HELPER_DIR/cerberus-ui"
# Rewrite shebang to use venv python (has PyQt6)
sed -i "1s|.*|#!$VENV_DIR/bin/python3|" "$HELPER_DIR/cerberus-ui"
cat > "$DBUS_SERVICES/com.cerberus.UI.service" <<DBUSEOF
[D-BUS Service]
Name=com.cerberus.UI
Exec=$HELPER_DIR/cerberus-ui
DBUSEOF

# Step 6: Uninstall previous version if present
if kpackagetool6 --type=KWin/Script -l 2>/dev/null | grep -q cerberus; then
    echo "Removing previous Cerberus installation..."
    kpackagetool6 --type=KWin/Script -r cerberus || true
fi

# Step 6: Install the script package
echo "Installing Cerberus..."
kpackagetool6 --type=KWin/Script -i "$SCRIPT_DIR"

# Step 7: Enable the script
kwriteconfig6 --file kwinrc --group Plugins --key cerberusEnabled true

# Step 8: Ensure we have at least 2 virtual desktops (1 stage + 1 parking)
current_count=$(kreadconfig6 --file kwinrc --group Desktops --key Number)
if [ "$current_count" -lt 2 ] 2>/dev/null; then
    echo "Creating virtual desktops (need 2, have ${current_count:-0})..."
    kwriteconfig6 --file kwinrc --group Desktops --key Number 2
fi

# Step 9: Reconfigure KWin — loads Cerberus, registerShortcut creates actions
echo "Loading Cerberus..."
qdbus6 org.kde.KWin /KWin reconfigure
sleep 2

# Step 10: Fix Send-to-Workspace shortcut bindings for Wayland
# Qt normalizes "Alt+!" → Alt+Shift+Key_1, but Wayland sends Alt+Key_Exclam.
# Override with actual keysyms WHILE the script is loaded (script must be active).
echo "Applying Wayland shortcut fixes..."

# Alt + shifted digit keycodes: ) ! @ # $ % ^ & * (
#   index:                        0 1 2 3 4 5 6 7 8 9
SEND_CODES=(134217769 134217761 134217792 134217763 134217764 134217765 134217822 134217766 134217770 134217768)
# Ctrl+Alt + shifted digit keycodes
CTRL_SEND_CODES=(201326633 201326625 201326656 201326627 201326628 201326629 201326686 201326630 201326634 201326632)

for i in $(seq 1 9); do
    dbus-send --session --dest=org.kde.kglobalaccel /kglobalaccel \
        org.kde.KGlobalAccel.setForeignShortcut \
        "array:string:kwin,Cerberus: Send to Workspace $i,KWin,Cerberus: Send to Workspace $i" \
        "array:int32:${SEND_CODES[$i]}" 2>/dev/null || true
    sleep 0.5
done
dbus-send --session --dest=org.kde.kglobalaccel /kglobalaccel \
    org.kde.KGlobalAccel.setForeignShortcut \
    "array:string:kwin,Cerberus: Send to Workspace 10,KWin,Cerberus: Send to Workspace 10" \
    "array:int32:${SEND_CODES[0]}" 2>/dev/null || true
sleep 0.5

for i in $(seq 1 9); do
    ws=$((i + 10))
    dbus-send --session --dest=org.kde.kglobalaccel /kglobalaccel \
        org.kde.KGlobalAccel.setForeignShortcut \
        "array:string:kwin,Cerberus: Send to Workspace $ws,KWin,Cerberus: Send to Workspace $ws" \
        "array:int32:${CTRL_SEND_CODES[$i]}" 2>/dev/null || true
    sleep 0.5
done
dbus-send --session --dest=org.kde.kglobalaccel /kglobalaccel \
    org.kde.KGlobalAccel.setForeignShortcut \
    "array:string:kwin,Cerberus: Send to Workspace 20,KWin,Cerberus: Send to Workspace 20" \
    "array:int32:${CTRL_SEND_CODES[0]}" 2>/dev/null || true

echo ""
echo "=== Cerberus installed successfully ==="
echo ""
echo "Keybindings:"
echo "  Alt+1-0         Switch to workspace 1-10"
echo "  Ctrl+Alt+1-0    Switch to workspace 11-20"
echo "  Alt+Shift+1-0   Send window to workspace 1-10"
echo "  Alt+Shift+T     Tile windows"
echo "  Alt+Up/Down     Next/prev empty workspace"
echo "  Alt+Shift+O     Toggle overlays"
echo "  Alt+Shift+N     Name workspace"
echo "  Alt+Shift+W     Workspace map"
echo "  Alt+Shift+H     Show help"
echo ""
echo "Debug: journalctl --user -f | grep Cerberus"
