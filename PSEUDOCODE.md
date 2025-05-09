# Cerberus Workspace Management System - Pseudocode

This document outlines the algorithmic structure of Cerberus in pseudocode format, highlighting the system's key components and processes.

## Global Data Structures

```
GLOBAL MAX_WORKSPACES = 9  // Maximum number of workspaces
GLOBAL MAX_MONITORS = 9     // Maximum number of monitors

// Maps monitor indices to workspace IDs
GLOBAL MonitorWorkspaces = MAP<monitor_index, workspace_id>

// Maps window handles to workspace IDs
GLOBAL WindowWorkspaces = MAP<window_handle, workspace_id>

// Maps workspaces to window layout data
GLOBAL WorkspaceLayouts = MAP<workspace_id, MAP<window_handle, layout_data>>

// Maps monitors to overlay GUI handles
GLOBAL WorkspaceOverlays = MAP<monitor_index, overlay_handle>

// Visual overlay configuration parameters
GLOBAL OVERLAY_SIZE = 60
GLOBAL OVERLAY_MARGIN = 20
GLOBAL OVERLAY_TIMEOUT = 0
GLOBAL OVERLAY_OPACITY = 220
GLOBAL OVERLAY_POSITION = "BottomRight"
```

## Initialization Process

```
PROCEDURE InitializeWorkspaces():
    SHOW welcome message with instructions
    
    // Set up initial environment
    SET mouse coordinates relative to screen
    SET window operation delay
    DISABLE hidden window detection
    
    // Initialize monitor-to-workspace mappings
    monitorCount = GET total monitors
    FOR each monitor up to MAX_MONITORS:
        IF monitor exists:
            IF monitor_index <= MAX_WORKSPACES:
                SET MonitorWorkspaces[monitor_index] = monitor_index
            ELSE:
                SET MonitorWorkspaces[monitor_index] = 1
    
    // Process existing windows
    window_list = GET all visible windows
    valid_windows = EMPTY LIST
    
    // First pass - identify valid windows
    FOR each window in window_list:
        IF IsWindowValid(window):
            ADD window to valid_windows
    
    // Second pass - assign windows to workspaces
    FOR each window in valid_windows:
        IF window is minimized:
            SET WindowWorkspaces[window] = 0  // Unassigned
        ELSE:
            monitor = GET monitor containing window
            workspace = GET workspace for monitor
            SET WindowWorkspaces[window] = workspace
            SAVE window layout data
    
    SHOW initialization complete message
END PROCEDURE

PROCEDURE InitializeOverlays():
    monitorCount = GET total monitors
    
    FOR each monitor up to monitorCount:
        CREATE visual overlay for monitor
    
    UPDATE all overlays to show current workspace numbers
END PROCEDURE
```

## Window Validation

```
FUNCTION IsWindowValid(window_handle):
    IF window doesn't exist:
        RETURN false
    
    title = GET window title
    class = GET window class
    
    IF title is empty OR class is empty:
        RETURN false
    
    IF class is in SKIP_CLASSES list:
        RETURN false
    
    IF window is active script window:
        RETURN false
    
    IF title contains system components:
        RETURN false
    
    IF window has WS_CHILD style:
        RETURN false
    
    RETURN true
END FUNCTION
```

## Monitor Detection

```
FUNCTION GetWindowMonitor(window_handle):
    monitorCount = GET total monitors
    
    IF monitorCount is 1:
        RETURN 1
    
    GET window position (x, y, width, height)
    centerX = x + width / 2
    centerY = y + height / 2
    
    FOR each monitor up to monitorCount:
        GET monitor work area (left, top, right, bottom)
        IF centerX is within horizontal bounds AND centerY is within vertical bounds:
            RETURN monitor index
    
    RETURN 1  // Default to primary monitor
END FUNCTION

FUNCTION GetActiveMonitor():
    active_window = GET active window handle
    
    IF active_window exists:
        RETURN GetWindowMonitor(active_window)
    
    RETURN 1  // Default to primary monitor
END FUNCTION
```

## Window Layout Management

```
PROCEDURE SaveWindowLayout(window_handle, workspace_id):
    IF NOT IsWindowValid(window_handle) OR workspace_id is invalid:
        RETURN
    
    IF WorkspaceLayouts does not have workspace_id:
        CREATE new layout map for workspace_id
    
    GET window position (x, y, width, height)
    isMinimized = CHECK if window is minimized
    isMaximized = CHECK if window is maximized
    
    STORE layout data in WorkspaceLayouts[workspace_id][window_handle]
END PROCEDURE

PROCEDURE RestoreWindowLayout(window_handle, workspace_id):
    IF NOT IsWindowValid(window_handle):
        LOG restoration failed
        RETURN
    
    IF window is minimized:
        RESTORE window
        WAIT for restoration to complete
    
    IF WorkspaceLayouts has workspace_id AND layout data for window:
        layout = GET layout data
        
        IF layout indicates window was maximized:
            MAXIMIZE window
        ELSE:
            MOVE window to saved position and size
    ELSE:
        ACTIVATE window to bring to front
    
    ENSURE window is visible and has focus
END PROCEDURE
```

## Workspace Management

```
PROCEDURE SwitchToWorkspace(requested_id):
    IF requested_id is invalid:
        RETURN

    active_monitor = GetActiveMonitor()
    current_workspace = MonitorWorkspaces[active_monitor]

    IF current_workspace equals requested_id:
        RETURN  // Already on requested workspace

    // Check if requested workspace is on another monitor
    other_monitor = FIND monitor displaying requested_id

    IF other_monitor exists:
        // Exchange workspaces between monitors

        // Step 1: Minimize all windows on both monitors
        windows = GET all open windows
        FOR each window:
            IF IsWindowValid(window) AND (monitor is active_monitor OR monitor is other_monitor):
                MINIMIZE window
                DELAY to allow minimize operation to complete

        // Step 2: Swap workspace IDs between monitors
        MonitorWorkspaces[other_monitor] = current_workspace
        MonitorWorkspaces[active_monitor] = requested_id

        // Step 3: Restore windows for both workspaces on their new monitors
        windows = GET all open windows
        FOR each window:
            IF IsWindowValid(window):
                windowMonitor = GetWindowMonitor(window)

                IF windowMonitor equals active_monitor:
                    SET WindowWorkspaces[window] = requested_id
                    IF window is minimized:
                        RESTORE window

                ELSE IF windowMonitor equals other_monitor:
                    SET WindowWorkspaces[window] = current_workspace
                    IF window is minimized:
                        RESTORE window
    ELSE:
        // Standard workspace switch (no exchange)

        // Step 1: Minimize all windows on active monitor
        windows = GET all open windows
        FOR each window:
            IF IsWindowValid(window) AND monitor is active_monitor:
                MINIMIZE window
                DELAY to allow minimize operation to complete

        // Step 2: Update workspace ID for active monitor
        SET MonitorWorkspaces[active_monitor] = requested_id

        // Step 3: Restore windows belonging to requested workspace
        windows = GET all open windows
        FOR each window:
            IF IsWindowValid(window) AND monitor is active_monitor:
                RESTORE window if needed
                SET WindowWorkspaces[window] = requested_id
                SAVE window layout

    UPDATE workspace overlays
END PROCEDURE
```

## Event Handlers

```
PROCEDURE WindowMoveResizeHandler(window_handle):
    IF window is not minimized AND IsWindowValid(window) AND WindowWorkspaces has window:
        workspace_id = WindowWorkspaces[window]
        IF workspace_id is valid:
            SAVE updated window layout
END PROCEDURE

PROCEDURE NewWindowHandler(window_handle):
    SCHEDULE AssignNewWindow with delay of 1000ms
END PROCEDURE

PROCEDURE AssignNewWindow(window_handle):
    IF window still exists AND IsWindowValid(window):
        monitor = GetWindowMonitor(window)
        
        IF MonitorWorkspaces has monitor:
            workspace_id = MonitorWorkspaces[monitor]
            
            IF WindowWorkspaces does not have window:
                SET WindowWorkspaces[window] = workspace_id
                SAVE window layout
                
                current_workspace = MonitorWorkspaces[monitor]
                IF workspace_id not equal to current_workspace:
                    MINIMIZE window
            ELSE:
                IF WindowWorkspaces[window] not equal to workspace_id:
                    UPDATE workspace assignment
                    SAVE window layout
        ELSE:
            SET WindowWorkspaces[window] = 0  // Unassigned
END PROCEDURE
```

## Visual Feedback System

```
PROCEDURE CreateOverlay(monitor_index):
    GET monitor work area dimensions
    CALCULATE overlay position based on OVERLAY_POSITION setting
    
    CREATE GUI window with always-on-top, no caption, tool window properties
    SET background color to dark gray
    
    GET current workspace number for monitor
    ADD text control with workspace number
    DISPLAY overlay at calculated position
    SET transparency level
    
    STORE overlay in WorkspaceOverlays map
END PROCEDURE

PROCEDURE UpdateAllOverlays():
    FOR each monitor in WorkspaceOverlays:
        UPDATE overlay for monitor
END PROCEDURE

PROCEDURE UpdateOverlay(monitor_index):
    IF WorkspaceOverlays has monitor_index:
        overlay = WorkspaceOverlays[monitor_index]
        workspace_id = MonitorWorkspaces[monitor_index]
        
        UPDATE text control to show workspace_id
        ENSURE proper positioning and centering
        SHOW overlay without activating it
END PROCEDURE

PROCEDURE ToggleOverlays():
    STATIC isVisible = true
    
    IF isVisible:
        HIDE all overlays
    ELSE:
        UPDATE and SHOW all overlays
        IF OVERLAY_TIMEOUT > 0:
            SCHEDULE hiding overlays after timeout
    
    TOGGLE isVisible flag
END PROCEDURE
```

## Keyboard Shortcuts

```
HOTKEY Ctrl+1: CALL SwitchToWorkspace(1)
HOTKEY Ctrl+2: CALL SwitchToWorkspace(2)
HOTKEY Ctrl+3: CALL SwitchToWorkspace(3)
HOTKEY Ctrl+4: CALL SwitchToWorkspace(4)
HOTKEY Ctrl+5: CALL SwitchToWorkspace(5)
HOTKEY Ctrl+6: CALL SwitchToWorkspace(6)
HOTKEY Ctrl+7: CALL SwitchToWorkspace(7)
HOTKEY Ctrl+8: CALL SwitchToWorkspace(8)
HOTKEY Ctrl+9: CALL SwitchToWorkspace(9)
HOTKEY Ctrl+0: CALL ToggleOverlays()
```

## Main Program Flow

```
MAIN:
    SHOW welcome message
    SET UP global environment
    CALL InitializeWorkspaces()
    CALL InitializeOverlays()
    REGISTER window event handlers
    REGISTER keyboard shortcuts
    ENTER event loop
END MAIN
```