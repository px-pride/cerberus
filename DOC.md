# Cerberus Workspace Management System - Documentation

## Introduction

Cerberus is a multi-monitor workspace management system built with AutoHotkey v2.0. It brings virtual workspace functionality to Windows, similar to what many Linux desktop environments offer. With Cerberus, users can organize their applications across multiple virtual workspaces and switch between them with simple keyboard shortcuts, maintaining window positions and states as they switch.

The fundamental problem Cerberus solves is screen clutter and workflow organization. Instead of minimizing windows or alt-tabbing through dozens of applications, users can organize related tasks into distinct workspaces - one for communication, another for coding, a third for research, and so on. This separation helps maintain focus while keeping all necessary tools readily accessible.

## System Overview

At its core, Cerberus implements a virtual workspace system by intelligently controlling window visibility. It doesn't actually create separate desktops - rather, it manages which windows are visible on each monitor at any given time, creating the illusion of separate workspaces.

### Key Concepts

1. **Workspaces**: Virtual environments (up to 9) that can contain different sets of windows. Each workspace has a numeric ID (1-9).

2. **Monitors**: Physical displays connected to the system. Each monitor displays one workspace at a time.

3. **Window Tracking**: The system tracks which windows belong to which workspaces and maintains their layout information.

4. **Workspace Switching**: When the user presses Ctrl+[number], the system changes which workspace is visible on the active monitor.

5. **Visual Feedback**: Small overlays in the corner of each monitor show the current workspace number.

## Architecture and Components

Cerberus is organized around several key data structures and component systems:

### Core Data Structures

- **MonitorWorkspaces**: A map linking monitor indices to workspace IDs, tracking which workspace is currently displayed on each monitor.
  ```ahk
  MonitorWorkspaces[monitorIndex] := workspaceID
  ```

- **WindowWorkspaces**: A map assigning window handles (hwnds) to workspace IDs, recording which workspace each window belongs to.
  ```ahk
  WindowWorkspaces[hwnd] := workspaceID
  ```

- **WorkspaceLayouts**: A nested map storing position and state information for each window in each workspace.
  ```ahk
  WorkspaceLayouts[workspaceID][hwnd] := { x, y, width, height, isMinimized, isMaximized }
  ```

- **WorkspaceOverlays**: A map storing GUI handles for the visual indicators showing workspace numbers.
  ```ahk
  WorkspaceOverlays[monitorIndex] := guiObject
  ```

### Component Systems

1. **Initialization System**: Sets up workspaces and assigns existing windows when the script starts.
2. **Window Tracking System**: Monitors window creation, movement, and destruction.
3. **Workspace Switching System**: Handles the logic of changing which workspace is visible.
4. **Visual Feedback System**: Provides on-screen indicators of workspace status.
5. **Event Handling System**: Responds to window events from the system.

## Initialization Flow

When Cerberus starts, it follows this sequence:

1. **Configuration Loading**: Sets up parameters like maximum workspaces, overlay settings, etc.
2. **Monitor Detection**: Identifies connected monitors and assigns default workspace IDs.
3. **Window Enumeration**: Catalogs all existing windows and determines which ones to track.
4. **Workspace Assignment**: Assigns existing windows to workspaces based on their monitor location.
5. **Overlay Creation**: Creates visual indicators on each monitor.
6. **Event Handlers**: Sets up message hooks to track window activity.

The `InitializeWorkspaces()` function is the entry point for this process:

```ahk
InitializeWorkspaces() {
    ; Detect monitors and set initial workspace assignments
    ; Capture existing windows
    ; Filter valid windows from system components
    ; Assign windows to workspaces based on monitor location
    ; Save initial window layouts
}
```

## Window Tracking System

Cerberus needs to know which windows to track and which to ignore. System windows, the taskbar, and other UI elements should not be managed by the workspace system.

### Window Validation

The `IsWindowValid()` function provides this filtering:

```ahk
IsWindowValid(hwnd) {
    ; Skip invalid handles
    ; Skip windows without titles or classes
    ; Skip the script's own window
    ; Skip system windows based on class or title
    ; Skip child windows and tool windows
    ; Return true if the window passes all filters
}
```

### Window Monitor Detection

To assign windows to workspaces, Cerberus needs to know which monitor contains each window. This is handled by `GetWindowMonitor()`:

```ahk
GetWindowMonitor(hwnd) {
    ; Get window position
    ; Calculate the center point of the window
    ; Determine which monitor contains this point
    ; Return the monitor index
}
```

### Window Layout Management

When windows move or resize, Cerberus saves their new state:

```ahk
SaveWindowLayout(hwnd, workspaceID) {
    ; Get window position and size
    ; Check if window is minimized or maximized
    ; Store this information in WorkspaceLayouts
}
```

Later, when switching workspaces, the system restores these layouts:

```ahk
RestoreWindowLayout(hwnd, workspaceID) {
    ; Check if layout data exists
    ; If window was maximized, restore that state
    ; Otherwise, move window to saved position
    ; Ensure the window is visible and active
}
```

## Workspace Switching Mechanism

The workspace switching system is the heart of Cerberus, implemented in the `SwitchToWorkspace()` function:

```ahk
SwitchToWorkspace(requestedID) {
    ; Get active monitor
    ; Get current workspace ID for that monitor
    ; Check if requested workspace is already on another monitor
    ; If so, perform workspace exchange between monitors
    ; Otherwise, perform standard workspace switch:
        ; Minimize windows on current workspace
        ; Change workspace ID for monitor
        ; Restore windows belonging to new workspace
    ; Update visual overlays
}
```

Cerberus handles two different switching scenarios:

### Standard Workspace Switch

When switching to a workspace not currently visible on any monitor:
1. Minimize all windows on the active monitor
2. Change the workspace ID assigned to that monitor
3. Restore all windows belonging to the new workspace

### Workspace Exchange

When switching to a workspace that's already visible on another monitor:
1. Identify which monitor currently shows the requested workspace
2. Swap workspace IDs between the two monitors
3. Move windows between monitors, preserving their relative positions

This allows for efficient "swapping" of workspaces between monitors.

## Event Handling System

Cerberus relies on event handlers to track window activity:

### Window Movement and Resizing

The `WindowMoveResizeHandler()` function catches window movement and resizing:

```ahk
WindowMoveResizeHandler(wParam, lParam, msg, hwnd) {
    ; Skip invalid windows
    ; Check if window is minimized
    ; Track window state transitions (especially un-minimizing)
    ; Update workspace assignment when windows move between monitors
    ; Save window layout information
}
```

### New Window Creation

New windows are tracked through the `NewWindowHandler()` function:

```ahk
NewWindowHandler(wParam, lParam, msg, hwnd) {
    ; Check if window is valid
    ; Assign to workspace based on which monitor it appears on
    ; Schedule a delayed follow-up check with DelayedWindowCheck()
}
```

A delayed check is necessary because some windows move or change during initialization:

```ahk
AssignNewWindow(hwnd) {
    ; Recheck window validity
    ; Update workspace assignment if needed
    ; Check if window should be visible or hidden
}
```

### Window Closure

When windows close, they need to be removed from tracking:

```ahk
WindowCloseHandler(wParam, lParam, msg, hwnd) {
    ; Remove window references from tracking maps
    ; Update workspace window overlay if visible
}
```

### Memory Management

To prevent memory leaks, Cerberus periodically cleans up stale window references:

```ahk
CleanupWindowReferences() {
    ; Remove references to windows that no longer exist
    ; Clean up lastWindowState map, WindowWorkspaces map, and WorkspaceLayouts map
}
```

## Visual Feedback System

Cerberus provides visual feedback through two overlay systems:

### Workspace Number Overlays

Small indicators showing the current workspace number on each monitor:

```ahk
CreateOverlay(monitorIndex) {
    ; Calculate overlay position based on configured position
    ; Create GUI element
    ; Add text control showing workspace number
    ; Set transparency and show
}
```

These are updated whenever workspace assignments change:

```ahk
UpdateOverlay(monitorIndex) {
    ; Get current workspace ID for this monitor
    ; Update text in the overlay
}
```

### Workspace Window List Overlay

A more detailed overlay (toggled with Ctrl+`) showing which windows are in each workspace:

```ahk
ShowWorkspaceWindowOverlay() {
    ; Get current window information for all workspaces
    ; Create GUI overlay
    ; Build text representation of windows by workspace
    ; Display as semi-transparent overlay
    ; Set up periodic updates
}
```

## Data Flow: A Day in the Life of a Window

To understand how all these components work together, let's follow the lifecycle of a window:

1. **Window Creation**: 
   - User opens a new application
   - System generates WM_CREATE message
   - `NewWindowHandler()` intercepts this and assigns the window to the workspace currently visible on its monitor
   - Window information is saved in WindowWorkspaces and WorkspaceLayouts

2. **Window Movement**:
   - User moves window to different position
   - System generates WM_MOVE message
   - `WindowMoveResizeHandler()` updates position in WorkspaceLayouts
   - If window moved to different monitor, updates workspace assignment

3. **Workspace Switch**:
   - User presses Ctrl+5 to switch monitor to workspace 5
   - `SwitchToWorkspace(5)` is called
   - Current windows are minimized
   - Monitor's workspace is updated in MonitorWorkspaces
   - Windows belonging to workspace 5 are restored using saved layouts
   - Workspace overlay updates to show "5"

4. **Window Close**:
   - User closes the application
   - System generates WM_DESTROY message
   - `WindowCloseHandler()` removes window references from tracking
   - Regular cleanup process eventually removes stale references

## Configuration Options

Cerberus provides several configuration options:

### Workspace Configuration
- `MAX_WORKSPACES`: Maximum number of workspaces (default: 9)
- `MAX_MONITORS`: Maximum supported monitors (default: 9)

### Overlay Display Settings
- `OVERLAY_SIZE`: Size of workspace indicators
- `OVERLAY_MARGIN`: Margin from screen edge
- `OVERLAY_TIMEOUT`: Time before indicators fade (0 for permanent)
- `OVERLAY_OPACITY`: Transparency level (0-255)
- `OVERLAY_POSITION`: Position on screen ("TopLeft", "TopRight", "BottomLeft", "BottomRight")

### Debug Settings
- `DEBUG_MODE`: Enables detailed logging
- `LOG_TO_FILE`: Outputs logs to file instead of debug output
- `LOG_FILE`: Path to log file
- `SHOW_WINDOW_EVENT_TOOLTIPS`: Shows tooltips for window events
- `SHOW_TRAY_NOTIFICATIONS`: Shows tray notifications for window events

## Keyboard Shortcuts

- **Ctrl+1** through **Ctrl+9**: Switch to workspace 1-9
- **Ctrl+0**: Toggle workspace number overlays
- **Ctrl+`**: Toggle detailed workspace window list

## Technical Implementation Details

### Workspace Switching Algorithm

The workspace switching logic handles window transitions smoothly:

1. **Single Monitor Switching**:
   - Identify windows on active monitor
   - Minimize all these windows
   - Update monitor's workspace ID
   - Find windows belonging to new workspace
   - Restore these windows using saved layouts

2. **Monitor Exchange Switching**:
   - Calculate offset between monitors' positions
   - Move windows from monitor A to monitor B, adjusting by offset
   - Move windows from monitor B to monitor A, adjusting by offset
   - Swap workspace IDs between monitors

### Window Layout Preservation

Window states are stored in a structured format:

```ahk
{
    x: windowX,
    y: windowY,
    width: windowWidth,
    height: windowHeight,
    isMinimized: (minimized state),
    isMaximized: (maximized state)
}
```

When restoring layouts, Cerberus:
1. Checks if the saved position is still valid (within screen bounds)
2. Restores minimized/maximized state
3. For normal windows, moves them to the saved position and size
4. For maximized windows, ensures they remain maximized

### Workspace Exchange Positioning

When exchanging workspaces between monitors, window positions are adjusted based on the relative positions of the monitors:

1. Calculate position offset between monitors
2. Adjust window positions by this offset when moving between monitors
3. Preserve window state (normal/maximized)

This ensures windows maintain their relative positions when moved between monitors of different sizes or positions.

## Limitations and Edge Cases

### Known Limitations

1. **Non-Standard Windows**: Applications that use custom window management techniques may not behave as expected within Cerberus.

2. **Parent-Child Relationships**: Windows with parent-child relationships may not transition correctly if they belong to different workspaces.

3. **System Integration**: Cerberus may conflict with other window management tools or Windows' built-in features like Task View.

4. **Application Behavior**: Some applications may not respond well to being minimized and restored repeatedly.

### Edge Cases

1. **Monitor Disconnection**: If a monitor is disconnected, windows assigned to it may need manual reassignment.

2. **Window Initialization**: Some applications create their windows with multiple steps or delayed positioning, which can sometimes cause initial workspace assignment issues.

3. **System Modal Dialogs**: Dialog boxes that are system-modal may appear on all workspaces.

## Debugging and Troubleshooting

Cerberus includes comprehensive logging to aid in troubleshooting:

```ahk
LogMessage(message) {
    ; Add timestamp
    ; Format log message
    ; Output to debug view or log file
    ; Optionally show as tooltip or tray notification
}
```

When debugging issues:

1. Enable `DEBUG_MODE` to see detailed logs
2. Use `SHOW_WINDOW_EVENT_TOOLTIPS` to visualize window events
3. Check logs for warnings about window handling problems
4. Look for issues in workspace transitions or window tracking

## Future Enhancements

The design allows for several potential enhancements:

1. **Named Workspaces**: Allow custom names for workspaces instead of just numbers
2. **Per-Workspace Wallpapers**: Different desktop backgrounds for each workspace
3. **Application Rules**: Automatically assign specific applications to designated workspaces
4. **Transition Effects**: Visual animations during workspace switching
5. **Additional Visual Indicators**: More detailed overlay information

## Conclusion

Cerberus provides a powerful workspace management system for Windows, allowing users to organize their workflow across multiple virtual spaces. By understanding the architecture and component systems described in this document, engineers can effectively work with, troubleshoot, and extend the functionality of Cerberus.

At its heart, Cerberus is about managing window visibility intelligently to create the illusion of separate workspaces, while preserving window layouts and providing intuitive visual feedback to the user. The modular design makes it adaptable to different user needs and configurable for various workflows.