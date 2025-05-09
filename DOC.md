# Cerberus - Multi-monitor Workspace Management System

## Introduction

Cerberus is a powerful workspace management tool built with AutoHotkey v2.0 that brings virtual desktop capabilities to Windows with multi-monitor support. It allows you to organize your applications across multiple virtual workspaces and quickly switch between them using simple keyboard shortcuts.

Think of it as having 9 different desktop arrangements that you can instantly switch between, with each workspace remembering the exact position and state of all its windows. This is particularly useful for organizing work by project, context, or task type.

## Getting Started

### System Requirements

- Windows 10 or newer
- AutoHotkey v2.0 or later
- Works with 1-9 monitors

### Installation

1. Ensure AutoHotkey v2.0 or later is installed on your system
2. Download the `cerberus.ahk` script
3. Run the script by double-clicking it or using the command line
4. A notification will display confirming Cerberus is active

### Quick Start Guide

After launching Cerberus, you'll see a semi-transparent workspace number indicator in the corner of each monitor. By default, each monitor is assigned a workspace number matching its index (Monitor 1 = Workspace 1, etc.).

- Press **Ctrl+1** through **Ctrl+9** to switch to different workspaces
- Press **Ctrl+0** to toggle the workspace indicators on/off

## Core Concepts

### Workspaces

A workspace is a virtual desktop that remembers:
- Which windows belong to it
- The exact position and size of each window
- Whether each window is minimized or maximized

You can have up to 9 different workspaces (numbered 1-9), each containing its own arrangement of applications.

### Multi-monitor Support

Cerberus has advanced multi-monitor capabilities:
- Each physical monitor can display a different workspace
- Workspace switching occurs on the monitor containing your active window
- If a requested workspace is already visible on another monitor, the workspaces will swap between monitors

### Window Management

Cerberus tracks:
- All valid application windows (excluding system windows like taskbar)
- Window creation, movement, and resizing
- Window state (normal, minimized, maximized)

When you switch workspaces, Cerberus automatically:
1. Minimizes windows from the previous workspace
2. Restores windows belonging to the new workspace
3. Preserves the exact position and state of each window

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| Ctrl+1   | Switch to Workspace 1 |
| Ctrl+2   | Switch to Workspace 2 |
| Ctrl+3   | Switch to Workspace 3 |
| Ctrl+4   | Switch to Workspace 4 |
| Ctrl+5   | Switch to Workspace 5 |
| Ctrl+6   | Switch to Workspace 6 |
| Ctrl+7   | Switch to Workspace 7 |
| Ctrl+8   | Switch to Workspace 8 |
| Ctrl+9   | Switch to Workspace 9 |
| Ctrl+0   | Toggle workspace indicators on/off |

## Code Flow and Architecture

The codebase follows a modular structure organized around several key functions. Let's explore how these work together.

### Initialization Process

When Cerberus starts, it executes this sequence:

1. **Script Startup**: Sets basic parameters and displays a welcome message
   ```ahk
   MsgBox("Cerberus Workspace Manager starting..."
         "`nPress OK to continue"
         "`nPress Ctrl+1 through Ctrl+9 to switch workspaces"
         "`nPress Ctrl+0 to toggle overlays", "Cerberus", "T5")
   ```

2. **Monitor Detection**: Maps monitors to initial workspace IDs
   ```ahk
   InitializeWorkspaces() {
       monitorCount := MonitorGetCount()
       loop MAX_MONITORS {
           monitorIndex := A_Index
           if (monitorIndex <= monitorCount) {
               if (monitorIndex <= MAX_WORKSPACES) {
                   MonitorWorkspaces[monitorIndex] := monitorIndex
               } else {
                   MonitorWorkspaces[monitorIndex] := 1
               }
           }
       }
       ...
   }
   ```

3. **Window Detection**: Identifies and catalogs existing windows
   ```ahk
   windows := WinGetList()
   for hwnd in windows {
       if (IsWindowValid(hwnd)) {
           validWindows.Push(hwnd)
       }
   }
   ```

4. **Workspace Assignment**: Assigns windows to appropriate workspaces
   ```ahk
   for hwnd in validWindows {
       monitorIndex := GetWindowMonitor(hwnd)
       workspaceID := MonitorWorkspaces.Has(monitorIndex) ? MonitorWorkspaces[monitorIndex] : 0
       WindowWorkspaces[hwnd] := workspaceID
       SaveWindowLayout(hwnd, workspaceID)
   }
   ```

5. **Overlay Creation**: Generates visual indicators showing workspace numbers
   ```ahk
   InitializeOverlays() {
       monitorCount := MonitorGetCount()
       loop monitorCount {
           monitorIndex := A_Index
           CreateOverlay(monitorIndex)
       }
       UpdateAllOverlays()
   }
   ```

### Workspace Switching Logic

The core functionality revolves around the `SwitchToWorkspace()` function:

```ahk
SwitchToWorkspace(requestedID) {
    activeMonitor := GetActiveMonitor()
    currentWorkspaceID := MonitorWorkspaces[activeMonitor]
    
    if (currentWorkspaceID = requestedID)
        return
        
    // Check if workspace exists on another monitor
    // If yes, perform workspace exchange
    // If no, perform standard workspace switch
    
    // Update overlays
    UpdateAllOverlays()
}
```

Two switching mechanisms are implemented:

1. **Standard Switch**: Changes which workspace is displayed on the active monitor
   - Minimizes all windows on the active monitor
   - Updates the monitor's workspace assignment
   - Restores windows belonging to the requested workspace

2. **Cross-Monitor Exchange**: Swaps workspaces between monitors
   - Minimizes windows on both monitors
   - Swaps workspace IDs between monitors
   - Restores windows on both monitors with updated assignments

### Window Tracking System

Cerberus uses event handlers to monitor windows:

1. **Window Creation**: Captured by the WM_CREATE message
   ```ahk
   OnMessage(0x0001, NewWindowHandler)
   
   NewWindowHandler(wParam, lParam, msg, hwnd) {
       SetTimer(() => AssignNewWindow(hwnd), -1000)
   }
   ```

2. **Window Movement/Resizing**: Captured by WM_MOVE and WM_SIZE messages
   ```ahk
   OnMessage(0x0003, WindowMoveResizeHandler)
   OnMessage(0x0005, WindowMoveResizeHandler)
   
   WindowMoveResizeHandler(wParam, lParam, msg, hwnd) {
       if (IsWindowValid(hwnd) && WindowWorkspaces.Has(hwnd)) {
           workspaceID := WindowWorkspaces[hwnd]
           if (workspaceID > 0) 
               SaveWindowLayout(hwnd, workspaceID)
       }
   }
   ```

### Visual Feedback System

The visual indicators are implemented using small GUI windows:

```ahk
CreateOverlay(monitorIndex) {
    // Calculate position based on monitor dimensions
    // Create GUI window
    overlay := Gui("+AlwaysOnTop -Caption +ToolWindow +Owner")
    // Add workspace number text
    // Set transparency
    // Store reference in WorkspaceOverlays map
}
```

## Configuration Options

Cerberus provides several configurable parameters at the top of the script:

```ahk
MAX_WORKSPACES := 9  ; Maximum number of workspaces (1-9)
MAX_MONITORS := 9    ; Maximum number of monitors (adjust as needed)

; Overlay display settings
OVERLAY_SIZE := 60    ; Size in pixels
OVERLAY_MARGIN := 20  ; Margin from screen edge
OVERLAY_TIMEOUT := 0  ; Time before fade (0 = permanent)
OVERLAY_OPACITY := 220 ; 0-255 (transparency)
OVERLAY_POSITION := "BottomRight"  ; Position on screen
```

## Troubleshooting

### Common Issues

1. **Window Not Appearing in Expected Workspace**
   - Ensure the window isn't excluded by the `IsWindowValid()` function
   - Check if the window has special properties that prevent normal window management

2. **Workspaces Not Switching Correctly**
   - Try restarting Cerberus
   - Verify no keyboard conflicts with other applications

3. **Overlays Not Visible**
   - Press Ctrl+0 to toggle overlays
   - Check if transparency settings are compatible with your system

### Debugging

Cerberus includes extensive debug logging via the `OutputDebug()` function. To view debug messages:
1. Run DebugView from Microsoft Sysinternals
2. Filter for AutoHotkey messages
3. Watch the detailed operation logs

## Advanced Usage

### Working with Multiple Monitors

For optimal multi-monitor use:

1. **Independent Workspaces**: Keep different projects on different monitors by assigning distinct workspaces to each
2. **Workspace Swapping**: To move a workspace to another monitor, switch to it while your active window is on that monitor
3. **Monitor-Specific Applications**: Some applications work best when consistently used on the same physical monitor

### Power User Tips

1. **Consistent Application Placement**: Always open specific applications on certain workspaces to build muscle memory
2. **Context-Based Organization**: Group applications by project or workflow on each workspace
3. **Clean Desktop**: Minimize system tray and desktop clutter to let Cerberus handle window organization

## Future Features

Planned enhancements include:
- External configuration file
- Per-workspace wallpapers
- Application rules (auto-assign apps to specific workspaces)
- Workspace naming
- Transition animations

## Contributing

Cerberus is an open project and welcomes contributions. Areas that would benefit from community input include:
- Additional window filtering rules
- Performance optimizations
- Compatibility improvements with specific applications
- New visual indicator designs