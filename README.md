# Cerberus - Multi-Monitor Workspace Manager for Windows

Cerberus is a powerful workspace management tool for Windows that brings Linux-style virtual workspaces to multi-monitor setups. Written in AutoHotkey v2, it allows you to organize windows across multiple workspaces and quickly switch between them.

## Features

- **20 Virtual Workspaces**: Organize your windows across 20 different workspaces
- **Multi-Monitor Support**: Each monitor can display a different workspace
- **Workspace Persistence**: Automatically saves and restores workspace layouts between sessions
- **Visual Indicators**: Customizable overlays show active workspace numbers
- **Window Tiling**: Built-in tiling functionality to arrange windows in a grid
- **Named Workspaces**: Assign custom names to workspaces for better organization
- **Unused Workspace Navigation**: Quickly jump to empty workspaces
- **Z-Order Preservation**: Maintains window stacking order when switching workspaces

## Requirements

- Windows 10 or later
- AutoHotkey v2.0 or later
- Administrator privileges recommended for managing all window types

## Installation

1. Install [AutoHotkey v2.0](https://www.autohotkey.com/download/ahk-v2.exe)
2. Download `cerberus.ahk`
3. Run the script by double-clicking it
4. Optionally, add to Windows startup for automatic launch

## Keyboard Shortcuts

### Workspace Switching (changes workspace on active monitor)
- `Alt+1` to `Alt+9`: Switch to workspaces 1-9
- `Alt+0`: Switch to workspace 10
- `Ctrl+Alt+1` to `Ctrl+Alt+9`: Switch to workspaces 11-19
- `Ctrl+Alt+0`: Switch to workspace 20

### Window Management (moves active window to workspace)
- `Alt+Shift+1` to `Alt+Shift+9`: Send window to workspaces 1-9
- `Alt+Shift+0`: Send window to workspace 10
- `Ctrl+Shift+Alt+1` to `Ctrl+Shift+Alt+9`: Send window to workspaces 11-19
- `Ctrl+Shift+Alt+0`: Send window to workspace 20

### Unused Workspace Navigation
- `Alt+Up`: Switch to next unused workspace
- `Alt+Down`: Switch to previous unused workspace
- `Alt+Shift+Up`: Send window to next unused workspace
- `Alt+Shift+Down`: Send window to previous unused workspace

### Utility Functions
- `Alt+Shift+O`: Toggle workspace overlays and borders
- `Alt+Shift+W`: Show workspace map (displays all workspaces and their windows)
- `Alt+Shift+S`: Save workspace state manually
- `Alt+Shift+T`: Tile windows on active monitor
- `Alt+Shift+N`: Name/rename current workspace
- `Alt+Shift+R`: Refresh monitor configuration
- `Alt+Shift+H`: Show help/instructions

## Configuration

### Settings (in script)
- `DEBUG_MODE`: Enable/disable debug logging (default: true)
- `LOG_TO_FILE`: Log to file instead of debug output (default: true)
- `SHOW_WINDOW_EVENT_TOOLTIPS`: Show tooltips for window events (default: true)
- `SHOW_TRAY_NOTIFICATIONS`: Show system tray notifications (default: true)
- `OVERLAY_SIZE`: Size of workspace number overlay (default: 60)
- `OVERLAY_POSITION`: Position of overlay - "TopLeft", "TopRight", "BottomLeft", "BottomRight" (default: "BottomRight")
- `BORDER_COLOR`: Color of active monitor border (default: "33FFFF")
- `BORDER_THICKNESS`: Thickness of borders in pixels (default: 3)

### File Locations
- Logs: `./logs/cerberus_[timestamp].log`
- Workspace state: `./config/workspace_state.json`

## How It Works

### Active Monitor
The "active monitor" is determined by your mouse cursor position. This is the monitor that will be affected when you switch workspaces.

### Workspace Assignment
- When Cerberus starts, it assigns sequential workspaces to each monitor (Monitor 1 → Workspace 1, Monitor 2 → Workspace 2, etc.)
- Windows on each monitor are automatically assigned to that monitor's workspace
- Unassigned windows default to workspace 0

### Window Memory
- Cerberus remembers window positions and sizes relative to monitor dimensions
- When switching workspaces, windows are minimized/restored automatically
- Window positions are preserved even when moving between monitors of different sizes

### Workspace Naming
- Workspaces can be named for easier identification
- When sending a window to an unused workspace, it's automatically named after the program
- Names appear in the lower-left corner overlay

## Tips

1. **Quick Organization**: Use `Alt+Shift+Up/Down` to quickly send windows to new workspaces
2. **Monitor Focus**: Move your mouse to a monitor before switching its workspace
3. **Persistence**: Workspace layouts are automatically saved and restored between sessions
4. **Tiling**: Use `Alt+Shift+T` to quickly arrange all windows on the current workspace in a grid

## Troubleshooting

- **Windows not switching**: Run as administrator for better window management capabilities
- **Overlays not showing**: Press `Alt+Shift+O` to toggle overlay visibility
- **Lost windows**: Use `Alt+Shift+W` to see all workspaces and their windows
- **Monitor changes**: Press `Alt+Shift+R` after connecting/disconnecting monitors

## License

This project is open source. Feel free to modify and distribute according to your needs.

## Version

Current version: 1.0.0