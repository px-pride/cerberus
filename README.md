# Cerberus Workspace Manager

Cerberus is a powerful workspace management system for Windows built with AutoHotkey v2. It allows you to create and manage virtual workspaces across multiple monitors, making it easier to organize your windows and improve productivity.

## Features

- **Multi-Monitor Support**: Cerberus works seamlessly across multiple monitors, allowing you to assign different workspaces to each monitor.
- **Virtual Workspaces**: Create up to 9 virtual workspaces to organize your windows.
- **Persistent Window Management**: Windows retain their position, size, and state when switching between workspaces.
- **Visual Indicators**: Display workspace numbers and active monitor borders for easy navigation.
- **Keyboard Shortcuts**: Use convenient hotkeys to switch workspaces and move windows between workspaces.
- **Window Assignment Overlay**: Quickly see which windows are assigned to each workspace.

## Requirements

- Windows 10 or later
- [AutoHotkey v2.0](https://www.autohotkey.com/) or higher

## Installation

1. Install AutoHotkey v2.0 or higher from [the official website](https://www.autohotkey.com/).
2. Clone this repository or download the files.
3. Double-click on `cerberus.ahk` to run the script.

## Keyboard Shortcuts

Cerberus uses the following keyboard shortcuts:

- **Ctrl + 1-9**: Switch to workspace 1-9 on the active monitor
- **Ctrl + Alt + 0-9**: Switch to workspace 10-19 on the active monitor
- **Ctrl + Shift + 1-9**: Send the active window to workspace 1-9
- **Ctrl + Shift + Alt + 0-9**: Send the active window to workspace 10-19
- **Ctrl + 0**: Toggle workspace number overlays and monitor border
- **Ctrl + Alt + H**: Show help dialog with all keyboard shortcuts
- **Ctrl + `**: Show window workspace map dialog
- **Alt + Shift + R**: Refresh monitor configuration and overlays

## How It Works

### Workspaces

Cerberus creates virtual workspaces that can be assigned to physical monitors. Each monitor can display one workspace at a time, and windows are assigned to workspaces rather than monitors. When you switch workspaces on a monitor, windows belonging to the new workspace are shown, and windows belonging to the previous workspace are hidden.

### Window Tracking

Cerberus tracks window position, size, and state (normal, maximized, minimized) per workspace. When a window is moved or resized, its layout is saved for the current workspace. When switching workspaces, windows are restored to their saved positions and states.

### Active Monitor

The active monitor is determined by the mouse cursor position and is highlighted with a thin border. This makes it easy to see which monitor is currently active when working across multiple displays.

## Configuration

You can configure Cerberus by editing the following variables at the top of the script:

```ahk
; Workspace settings
MAX_WORKSPACES := 9     ; Maximum number of workspaces (1-9)
MAX_MONITORS := 9       ; Maximum number of monitors

; Debug settings
DEBUG_MODE := True      ; Enable/disable debug mode
LOG_TO_FILE := False    ; Log to file instead of debug output
LOG_FILE := A_ScriptDir "\cerberus.log"  ; Path to log file

; Visual settings
OVERLAY_SIZE := 60      ; Size of workspace number overlay in pixels
OVERLAY_MARGIN := 20    ; Margin from screen edge
OVERLAY_TIMEOUT := 0    ; Time before overlay fades (0 for persistent display)
OVERLAY_OPACITY := 220  ; Opacity of overlays (0-255)
OVERLAY_POSITION := "BottomRight"  ; Position of workspace overlay (TopLeft, TopRight, BottomLeft, BottomRight)
BORDER_COLOR := "33FFFF"  ; Color of active monitor border
BORDER_THICKNESS := 3   ; Thickness of monitor border in pixels
```

## Bugs

- disconnecting/connecting monitors

## Feature Requests

- save/load window workspace map
- ctrl+backtick overlay displaying window workspace map
- better system tray icon
- visual settings config menu

## Troubleshooting

If you encounter issues with Cerberus:

1. **Enable Debug Mode**: Set `DEBUG_MODE := True` to see detailed logging.
2. **Check Logs**: If `LOG_TO_FILE := True`, check the log file for error messages.
3. **Window Issues**: Some system windows or windows with special properties may not be tracked correctly.
4. **Performance**: If you experience performance issues, try reducing the number of windows being tracked or increase the delay between window operations by modifying `SetWinDelay`.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is open source and available under the [MIT License](LICENSE).

## Acknowledgements

Cerberus was inspired by various virtual desktop and window management tools, with the goal of creating a lightweight, customizable solution specifically for multi-monitor setups.