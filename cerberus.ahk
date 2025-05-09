#Requires AutoHotkey v2.0
#SingleInstance Force

; Cerberus - Multi-monitor workspace management system

; ====== Configuration ======
MAX_WORKSPACES := 9  ; Maximum number of workspaces (1-9)
MAX_MONITORS := 9    ; Maximum number of monitors (adjust as needed)

; ====== Global Variables ======
; Monitor workspace assignments (monitor index → workspace ID)
global MonitorWorkspaces := Map()

; Window workspace assignments (window ID → workspace ID)
global WindowWorkspaces := Map()

; Window positions per workspace (workspace ID → Map of window layouts)
global WorkspaceLayouts := Map()

; Workspace overlay GUI handles (monitor index → GUI handle)
global WorkspaceOverlays := Map()

; Overlay display settings
global OVERLAY_SIZE := 60 ; Size of overlay in pixels (increased for better visibility)
global OVERLAY_MARGIN := 20 ; Margin from screen edge
global OVERLAY_TIMEOUT := 0 ; Time in ms before overlay fades (0 for persistent display)
global OVERLAY_OPACITY := 220 ; 0-255 (0 = transparent, 255 = opaque)
global OVERLAY_POSITION := "BottomRight" ; TopLeft, TopRight, BottomLeft, BottomRight

; ====== Initialization ======
; Create a simple message box to indicate script has started
MsgBox("Cerberus Workspace Manager starting..."
      "`nPress OK to continue"
      "`nPress Ctrl+1 through Ctrl+9 to switch workspaces"
      "`nPress Ctrl+0 to toggle overlays", "Cerberus", "T5") ; Shows startup message with key bindings, T5 means timeout after 5 seconds

CoordMode("Mouse", "Screen") ; Sets mouse coordinates to be relative to entire screen instead of active window
SetWinDelay(50) ; Sets a 50ms delay between window operations to improve reliability of window manipulations
DetectHiddenWindows(False) ; Disables detection of hidden windows so they won't be tracked by the script

InitializeWorkspaces() ; Call to initialize workspaces when script starts - sets up monitor-workspace mapping and assigns windows
InitializeOverlays() ; Create workspace overlay displays - adds visual indicators for workspace numbers

InitializeWorkspaces() {
    OutputDebug("============ INITIALIZING WORKSPACES ============")
    
    ; Initialize monitor workspaces (default: monitor 1 = workspace 1, monitor 2 = workspace 2, etc.)
    monitorCount := MonitorGetCount() ; Gets the total number of physical monitors connected to the system
    OutputDebug("Detected " monitorCount " monitors") ; Logs the number of detected monitors to debug output for troubleshooting
    
    loop MAX_MONITORS {
        monitorIndex := A_Index
        if (monitorIndex <= monitorCount) {
            if (monitorIndex <= MAX_WORKSPACES) {
                MonitorWorkspaces[monitorIndex] := monitorIndex
            } else {
                MonitorWorkspaces[monitorIndex] := 1  ; Default to workspace 1 if we have more monitors than workspaces
            }
            OutputDebug("Assigned monitor " monitorIndex " to workspace " MonitorWorkspaces[monitorIndex])
        }
    }
    
    ; Capture all existing windows and assign them to their monitor's workspace
    DetectHiddenWindows(False) ; Turns off detection of hidden windows so only visible windows are captured
    windows := WinGetList() ; Retrieves an array of all visible window handles (HWND) currently open in the system
    
    OutputDebug("Found " windows.Length " total windows in system")
    windowCount := 0
    assignedCount := 0
    
    ; First pass - identify all valid windows
    validWindows := []
    for hwnd in windows {
        windowCount++
        title := WinGetTitle(hwnd) ; Gets the title text from the window's title bar for identification
        class := WinGetClass(hwnd) ; Gets the window class name which identifies the window type or application
        
        OutputDebug("Checking window - Title: " title ", Class: " class ", hwnd: " hwnd)
        
        if (IsWindowValid(hwnd)) { ; Checks if this window should be tracked (excludes system windows, taskbar, etc.)
            OutputDebug("Window is valid - adding to tracking list")
            validWindows.Push(hwnd)
        }
    }
    
    OutputDebug("Found " validWindows.Length " valid windows to track")
    
    ; Second pass - assign valid windows to workspaces
    for hwnd in validWindows { ; Iterates through the array of window handles that passed validation
        title := WinGetTitle(hwnd)
        class := WinGetClass(hwnd)
        
        ; Check if window is minimized - assign to workspace 0 if it is
        if (WinGetMinMax(hwnd) = -1) { ; Checks window state: -1=minimized, 0=normal, 1=maximized
            WindowWorkspaces[hwnd] := 0 ; Assigns minimized window to workspace 0 (unassigned)
            OutputDebug("Window is minimized, assigned to workspace 0 (unassigned): " title)
            continue ; Skip to next window
        }
        
        ; Assign the window to its monitor's workspace
        monitorIndex := GetWindowMonitor(hwnd) ; Determines which physical monitor contains this window
        workspaceID := MonitorWorkspaces.Has(monitorIndex) ? MonitorWorkspaces[monitorIndex] : 0 ; Gets workspace ID for this monitor, or 0 if monitor isn't tracked

        WindowWorkspaces[hwnd] := workspaceID ; Adds window to the tracking map with its workspace ID
        SaveWindowLayout(hwnd, workspaceID) ; Stores window's position, size, and state (normal/maximized) for later restoration
        
        OutputDebug("Assigned window to workspace " workspaceID " on monitor " monitorIndex ": " title)
        assignedCount++
    }
    
    OutputDebug("Initialization complete: Found " windowCount " windows, " validWindows.Length " valid, assigned " assignedCount " to workspaces")
    OutputDebug("============ INITIALIZATION COMPLETE ============")
    
    ; Display a tray tip with the number of windows assigned
    TrayTip("Cerberus initialized", "Assigned " assignedCount " windows to workspaces") ; Shows notification in system tray
}

; ====== Helper Functions ======
IsWindowValid(hwnd) { ; Checks if window should be tracked by Cerberus
    if !WinExist(hwnd) ; Checks if window exists
        return false
    
    ; Get window information
    title := WinGetTitle(hwnd) ; Gets the window title
    class := WinGetClass(hwnd) ; Gets the window class
    
    ; Debug output for all windows to help diagnose what's happening
    OutputDebug("Checking window - Title: " title ", Class: " class ", hwnd: " hwnd)
    
    ; Skip windows without a title
    if (title = "")
        return false
        
    ; Skip windows without a class
    if (class = "")
        return false
    
    ; Only exclude the most basic system windows and let more through for testing
    static skipClasses := "Progman,Shell_TrayWnd,WorkerW"
    if (InStr(skipClasses, class))
        return false
    
    ; Skip the script's own window
    if (WinActive("A") == hwnd)
        return false
        
    ; Very minimal title filtering for essential system components
    if (InStr(title, "Task View") || InStr(title, "Start Menu"))
        return false
    
    ; Skip child windows
    WS_CHILD := 0x40000000
    style := WinGetStyle(hwnd)
    if (style & WS_CHILD)
        return false
    
    ; Let most windows through for testing
    OutputDebug("VALID WINDOW - Title: " title ", Class: " class ", hwnd: " hwnd)
    return true
}

GetWindowMonitor(hwnd) { ; Determines which monitor contains the window
    monitorCount := MonitorGetCount() ; Gets the total number of physical monitors to determine which monitor contains the window
    
    if (monitorCount = 1)
        return 1
        
    ; Get window position
    WinGetPos(&x, &y, &width, &height, hwnd) ; Retrieves window position and size, storing values in the referenced variables
    
    ; Find which monitor contains the center of the window
    centerX := x + width / 2
    centerY := y + height / 2
    
    loop monitorCount {
        MonitorGetWorkArea(A_Index, &mLeft, &mTop, &mRight, &mBottom) ; Gets coordinates of monitor work area
        if (centerX >= mLeft && centerX <= mRight && centerY >= mTop && centerY <= mBottom)
            return A_Index
    }
    
    ; Default to primary monitor if no match
    return 1
}

GetActiveMonitor() { ; Gets the monitor index where the active window is located
    ; Get active window
    activeHwnd := WinExist("A") ; Gets handle of active window
    if !activeHwnd
        return 1  ; Default to primary monitor
        
    return GetWindowMonitor(activeHwnd) ; Gets monitor index for active window
}

SaveWindowLayout(hwnd, workspaceID) { ; Stores window position and state for later restoration
    if !IsWindowValid(hwnd) || workspaceID < 1 || workspaceID > MAX_WORKSPACES
        return
        
    ; Initialize workspace layout map if needed
    if !WorkspaceLayouts.Has(workspaceID) ; Checks if workspace exists in layouts map
        WorkspaceLayouts[workspaceID] := Map() ; Creates new map for this workspace
        
    ; Get window position and state
    WinGetPos(&x, &y, &width, &height, hwnd) ; Captures current window coordinates and dimensions to save in layout
    isMinimized := WinGetMinMax(hwnd) = -1 ; Determines if window is minimized by checking if WinGetMinMax returns -1
    isMaximized := WinGetMinMax(hwnd) = 1 ; Determines if window is maximized by checking if WinGetMinMax returns 1
    
    ; Store window layout
    WorkspaceLayouts[workspaceID][hwnd] := { ; Creates layout object for this window
        x: x,
        y: y,
        width: width,
        height: height,
        isMinimized: isMinimized,
        isMaximized: isMaximized
    }
}

RestoreWindowLayout(hwnd, workspaceID) { ; Restores a window to its saved position and state
    ; Check if window exists and is valid
    if !IsWindowValid(hwnd) {
        OutputDebug("RESTORE FAILED: Window " hwnd " is not valid")
        return
    }
    
    title := WinGetTitle(hwnd)
    OutputDebug("Attempting to restore window: " title " (" hwnd ")")
    
    ; First ensure the window is restored from minimized state
    winState := WinGetMinMax(hwnd) ; Gets window state (-1=minimized, 0=normal, 1=maximized)
    if (winState = -1) { ; If window is currently minimized, restore it first before applying layout
        OutputDebug("Window is minimized, restoring first")
        WinRestore("ahk_id " hwnd) ; Restores window from minimized state so we can apply position/size
        Sleep(100) ; Allow time for the window to restore
    }
    
    ; Check if we have saved layout data
    if (WorkspaceLayouts.Has(workspaceID)) {
        layouts := WorkspaceLayouts[workspaceID]
        
        if (layouts.Has(hwnd)) {
            layout := layouts[hwnd]
            OutputDebug("Found saved layout for window: x=" layout.x ", y=" layout.y ", w=" layout.width ", h=" layout.height)
            
            ; Apply saved layout
            if (layout.isMaximized) { ; If window was previously maximized
                OutputDebug("Maximizing window")
                WinMaximize("ahk_id " hwnd) ; Restore window to maximized state
            } else {
                ; Move window to saved position
                try { ; Try to move window to saved position, might fail if window constraints prevent it
                    OutputDebug("Moving window to saved position")
                    WinMove(layout.x, layout.y, layout.width, layout.height, "ahk_id " hwnd) ; Moves and resizes window to saved position and dimensions
                } catch Error as err {
                    OutputDebug("ERROR moving window: " err.Message)
                }
            }
        } else {
            OutputDebug("No saved layout found for this window, using default position")
            WinActivate("ahk_id " hwnd) ; At least activate the window
        }
    } else {
        OutputDebug("No layouts saved for workspace " workspaceID)
    }
    
    ; Ensure window is visible and brought to front
    WinActivate("ahk_id " hwnd) ; Brings window to foreground and gives it keyboard focus
}

MinimizeWorkspaceWindows(workspaceID) { ; Minimizes all windows in the specified workspace
    OutputDebug("Minimizing all windows for workspace " workspaceID)
    
    ; Get all open windows
    windows := WinGetList()
    minimizedCount := 0
    
    ; Process each window
    for index, hwnd in windows {
        ; Skip invalid windows
        if (!IsWindowValid(hwnd))
            continue
            
        ; Get window info
        title := WinGetTitle(hwnd)
        winState := WinGetMinMax(hwnd)
        
        ; If window belongs to this workspace and isn't already minimized
        if (WindowWorkspaces.Has(hwnd) && WindowWorkspaces[hwnd] = workspaceID && winState != -1) {
            OutputDebug("Minimizing workspace window: " title)
            try {
                WinMinimize("ahk_id " hwnd) ; Minimizes the window to the taskbar
                minimizedCount++
                Sleep(30) ; Small delay between minimize operations to prevent system overload
            } catch Error as err {
                OutputDebug("ERROR minimizing window: " err.Message)
            }
        }
    }
    
    OutputDebug("Minimized " minimizedCount " windows for workspace " workspaceID)
}

RestoreWorkspaceWindows(workspaceID) { ; Restores all minimized windows for the specified workspace
    OutputDebug("Restoring all windows for workspace " workspaceID)
    
    ; Get all open windows
    windows := WinGetList()
    restoredCount := 0
    
    ; Process each window
    for index, hwnd in windows {
        ; Skip invalid windows
        if (!IsWindowValid(hwnd))
            continue
            
        ; Get window info
        title := WinGetTitle(hwnd)
        winState := WinGetMinMax(hwnd)
        
        ; If window is minimized and belongs to this workspace
        if (winState = -1 && WindowWorkspaces.Has(hwnd) && WindowWorkspaces[hwnd] = workspaceID) {
            OutputDebug("Restoring workspace window: " title)
            try {
                if (WorkspaceLayouts.Has(workspaceID) && WorkspaceLayouts[workspaceID].Has(hwnd)) {
                    RestoreWindowLayout(hwnd, workspaceID) ; Restores window with saved layout
                } else {
                    WinRestore("ahk_id " hwnd) ; Restores window from minimized state when no saved layout exists
                    WinActivate("ahk_id " hwnd) ; Activates the window and brings it to the foreground
                }
                restoredCount++
                Sleep(30) ; Small delay between restore operations
            } catch Error as err {
                OutputDebug("ERROR restoring window: " err.Message)
            }
        }
    }
    
    OutputDebug("Restored " restoredCount " windows for workspace " workspaceID)
}

SwitchToWorkspace(requestedID) { ; Changes active workspace on current monitor
    if (requestedID < 1 || requestedID > MAX_WORKSPACES)
        return
        
    ; Debug output to help diagnose issues
    OutputDebug("------------- WORKSPACE SWITCH START -------------")
    OutputDebug("Switching to workspace: " requestedID)
    
    ; Get active monitor
    activeMonitor := GetActiveMonitor() ; Gets the monitor index that contains the currently active (focused) window
    OutputDebug("Active monitor: " activeMonitor)
    
    ; Get current workspace ID for active monitor
    currentWorkspaceID := MonitorWorkspaces.Has(activeMonitor) ? MonitorWorkspaces[activeMonitor] : 1 ; Gets current workspace ID for active monitor, defaults to 1 if not found
    OutputDebug("Current workspace on active monitor: " currentWorkspaceID)
    
    ; If already on requested workspace, do nothing
    if (currentWorkspaceID = requestedID) {
        OutputDebug("Already on requested workspace. No action needed.")
        return
    }
    
    ; Check if the requested workspace is already on another monitor - direct swap approach
    otherMonitor := 0
    for monIndex, workspaceID in MonitorWorkspaces {
        if (monIndex != activeMonitor && workspaceID = requestedID) {
            otherMonitor := monIndex
            OutputDebug("Found requested workspace on monitor: " otherMonitor)
            break
        }
    }
    
    if (otherMonitor > 0) {
        ; === PERFORMING WORKSPACE EXCHANGE BETWEEN MONITORS ===
        OutputDebug("Performing workspace exchange between monitors " activeMonitor " and " otherMonitor)
        
        ; Step 1: Minimize all windows on both monitors
        ; Get all open windows
        windows := WinGetList()
        OutputDebug("Found " windows.Length " total windows")
        
        ; Identify and minimize windows on both monitors
        for index, hwnd in windows {
            ; Skip invalid windows
            if (!IsWindowValid(hwnd))
                continue
            
            ; Get window info
            title := WinGetTitle(hwnd)
            windowMonitor := GetWindowMonitor(hwnd)
            
            ; Check if window is on either the active or other monitor
            if (windowMonitor = activeMonitor || windowMonitor = otherMonitor) {
                OutputDebug("MINIMIZING window on monitor " windowMonitor ": " title)
                
                ; Force the window to minimize
                try {
                    WinMinimize("ahk_id " hwnd)
                    Sleep(50) ; Delay to allow minimize operation to complete
                } catch Error as err {
                    OutputDebug("ERROR minimizing window: " err.Message)
                }
            }
        }
        
        ; Step 2: Swap workspace IDs between monitors
        OutputDebug("Swapping workspace IDs: " currentWorkspaceID " and " requestedID)
        MonitorWorkspaces[otherMonitor] := currentWorkspaceID
        MonitorWorkspaces[activeMonitor] := requestedID
        
        ; Force a delay to ensure minimizations complete
        Sleep(300)
        
        ; Step 3: Restore windows for both workspaces on their new monitors
        windows := WinGetList() ; Get fresh window list
        restoredActive := 0
        restoredOther := 0
        
        for index, hwnd in windows {
            ; Skip invalid windows
            if (!IsWindowValid(hwnd))
                continue
                
            ; Update window workspace assignment based on monitor it's on
            windowMonitor := GetWindowMonitor(hwnd)
            
            if (windowMonitor = activeMonitor) {
                ; Set window to requested workspace since it's on active monitor
                WindowWorkspaces[hwnd] := requestedID
                OutputDebug("Assigned window to active monitor workspace: " requestedID)
                
                ; Restore window if it's minimized
                if (WinGetMinMax(hwnd) = -1) {
                    WinRestore("ahk_id " hwnd)
                    restoredActive++
                    Sleep(30)
                }
            } 
            else if (windowMonitor = otherMonitor) {
                ; Set window to current workspace ID since it's on other monitor
                WindowWorkspaces[hwnd] := currentWorkspaceID
                OutputDebug("Assigned window to other monitor workspace: " currentWorkspaceID)
                
                ; Restore window if it's minimized
                if (WinGetMinMax(hwnd) = -1) {
                    WinRestore("ahk_id " hwnd)
                    restoredOther++
                    Sleep(30)
                }
            }
        }
        
        OutputDebug("Restored " restoredActive " windows on active monitor, " restoredOther " on other monitor")
    }
    else {
        ; === STANDARD WORKSPACE SWITCH (NO EXCHANGE) ===
        OutputDebug("Standard workspace switch - no exchange needed")
        
        ; ====== STEP 1: Identify and minimize all windows on the active monitor ======
        ; Get all open windows
        windows := WinGetList() ; Gets a list of all open windows    
        OutputDebug("Found " windows.Length " total windows")
        
        ; Process each window
        for index, hwnd in windows {
            ; Skip invalid windows
            if (!IsWindowValid(hwnd))
                continue
            
            ; Check if window is on active monitor
            windowMonitor := GetWindowMonitor(hwnd)
            if (windowMonitor = activeMonitor) {
                ; Directly minimize the window on active monitor
                title := WinGetTitle(hwnd)
                OutputDebug("MINIMIZING window on active monitor: " title)
                
                ; Force the window to minimize
                try {
                    WinMinimize("ahk_id " hwnd)
                    Sleep(50) ; Delay to allow minimize operation to complete
                } catch Error as err {
                    OutputDebug("ERROR minimizing window: " err.Message)
                }
            }
        }
        
        ; ====== STEP 2: Change workspace ID for active monitor ======
        ; Update the workspace ID for the active monitor
        MonitorWorkspaces[activeMonitor] := requestedID
        OutputDebug("Changed active monitor workspace to: " requestedID)
        
        ; Force a delay to allow minimizations to complete
        Sleep(300)
        
        ; ====== STEP 3: Restore windows belonging to requested workspace ======
        restoreCount := 0
        
        ; Get all windows again (in case things changed)
        windows := WinGetList()
        
        ; Process each window
        for index, hwnd in windows {
            ; Skip invalid windows
            if (!IsWindowValid(hwnd))
                continue
                
            ; Get window info
            title := WinGetTitle(hwnd)
            windowMonitor := GetWindowMonitor(hwnd)
            winState := WinGetMinMax(hwnd)
            
            ; Check if window is minimized and on active monitor
            if (windowMonitor = activeMonitor) {
                ; This is a window that should be restored for the new workspace
                OutputDebug("RESTORING window for new workspace: " title)
                
                ; Force window restore
                try {
                    ; Restore from minimized state if needed
                    if (winState = -1) {
                        WinRestore("ahk_id " hwnd)
                    }
                    
                    ; Update workspace assignment
                    WindowWorkspaces[hwnd] := requestedID
                    SaveWindowLayout(hwnd, requestedID)
                    
                    restoreCount++
                    Sleep(30) ; Delay to allow restore operation to complete
                } catch Error as err {
                    OutputDebug("ERROR restoring window: " err.Message)
                }
            }
        }
        
        OutputDebug("Restored " restoreCount " windows for workspace " requestedID)
    }
    
    OutputDebug("------------- WORKSPACE SWITCH END -------------")
    
    ; Update workspace overlays to reflect the new assignments
    UpdateAllOverlays()
}

; Helper function to find which monitor a workspace should be on
monitorForWorkspace(workspaceID) { ; Finds which monitor is displaying the specified workspace
    for monIndex, wsID in MonitorWorkspaces {
        if (wsID = workspaceID)
            return monIndex
    }
    return 1 ; Default to primary monitor if not found
}

; ====== Keyboard Shortcuts ======
; Ctrl+1 through Ctrl+9 for switching workspaces
^1::SwitchToWorkspace(1) ; Ctrl+1 hotkey to switch to workspace 1
^2::SwitchToWorkspace(2) ; Ctrl+2 hotkey to switch to workspace 2
^3::SwitchToWorkspace(3) ; Ctrl+3 hotkey to switch to workspace 3
^4::SwitchToWorkspace(4) ; Ctrl+4 hotkey to switch to workspace 4
^5::SwitchToWorkspace(5) ; Ctrl+5 hotkey to switch to workspace 5
^6::SwitchToWorkspace(6) ; Ctrl+6 hotkey to switch to workspace 6
^7::SwitchToWorkspace(7) ; Ctrl+7 hotkey to switch to workspace 7
^8::SwitchToWorkspace(8) ; Ctrl+8 hotkey to switch to workspace 8
^9::SwitchToWorkspace(9) ; Ctrl+9 hotkey to switch to workspace 9

; Ctrl+0 to toggle workspace overlays
^0::ToggleOverlays() ; Ctrl+0 hotkey to show/hide workspace overlays

; ====== Window Event Handlers ======
; Track window move/resize events to update layouts
OnMessage(0x0003, WindowMoveResizeHandler)  ; WM_MOVE - Registers a handler for window move events
OnMessage(0x0005, WindowMoveResizeHandler)  ; WM_SIZE - Registers a handler for window resize events

WindowMoveResizeHandler(wParam, lParam, msg, hwnd) { ; Handles window move/resize events to update saved layouts
    ; Don't track minimized windows
    if (WinGetMinMax(hwnd) = -1) ; Checks if window is minimized
        return
        
    if (IsWindowValid(hwnd) && WindowWorkspaces.Has(hwnd)) { ; Checks if window is valid and has workspace assignment
        workspaceID := WindowWorkspaces[hwnd] ; Gets workspace ID for this window
        if (workspaceID > 0) 
            SaveWindowLayout(hwnd, workspaceID) ; Saves updated window layout
    }
}

; Track new window events to assign to current workspace
; This event provides an hwnd when a window is created
OnMessage(0x0001, NewWindowHandler)  ; WM_CREATE - Registers a handler for window creation events

NewWindowHandler(wParam, lParam, msg, hwnd) { ; Handles window creation events to assign new windows
    ; Give the window a moment to initialize fully before assigning
    ; This helps ensure window properties and position are stable
    SetTimer(() => AssignNewWindow(hwnd), -1000) ; Increased timer to 1 second for better stability
}

AssignNewWindow(hwnd) { ; Assigns a new window to appropriate workspace
    ; Check again if the window exists and is valid - it might have closed already
    if (!WinExist(hwnd) || !IsWindowValid(hwnd))
        return
    
    title := WinGetTitle(hwnd)
    class := WinGetClass(hwnd)
    OutputDebug("Assigning new window - Title: " title ", Class: " class ", hwnd: " hwnd)
    
    ; Assign the window to its monitor's workspace
    monitorIndex := GetWindowMonitor(hwnd) ; Gets which monitor the window is on
    OutputDebug("Window is on monitor: " monitorIndex)
    
    if (MonitorWorkspaces.Has(monitorIndex)) { ; Checks if monitor has assigned workspace
        workspaceID := MonitorWorkspaces[monitorIndex] ; Gets workspace ID for this monitor
        
        ; Check if this window should be tracked
        if (!WindowWorkspaces.Has(hwnd)) {
            ; New window - assign to the current workspace of its monitor
            WindowWorkspaces[hwnd] := workspaceID ; Assigns window to workspace
            SaveWindowLayout(hwnd, workspaceID) ; Saves window layout
            OutputDebug("Assigned new window to workspace " workspaceID " on monitor " monitorIndex)
            
            ; Determine if the window should be visible or hidden
            currentWorkspaceID := MonitorWorkspaces[monitorIndex]
            if (workspaceID != currentWorkspaceID) {
                ; If the window belongs to a workspace not currently shown on this monitor, minimize it
                WinMinimize("ahk_id " hwnd)
                OutputDebug("Minimized window belonging to non-visible workspace")
            }
        } else {
            ; Update existing window's workspace assignment if needed
            if (WindowWorkspaces[hwnd] != workspaceID) {
                WindowWorkspaces[hwnd] := workspaceID
                SaveWindowLayout(hwnd, workspaceID)
                OutputDebug("Updated existing window's workspace to " workspaceID)
            }
        }
    } else {
        ; Default to unassigned if monitor has no workspace
        WindowWorkspaces[hwnd] := 0
        OutputDebug("Assigned new window to unassigned workspace (0) - monitor not tracked")
    }
}

; ====== Workspace Overlay Functions ======
InitializeOverlays() { ; Creates and displays workspace number indicators on all monitors
    ; Create an overlay for each monitor
    monitorCount := MonitorGetCount() ; Gets the total number of physical monitors to determine which monitor contains the window
    
    loop monitorCount {
        monitorIndex := A_Index
        CreateOverlay(monitorIndex) ; Create overlay for this monitor
    }
    
    ; Show all overlays initially
    UpdateAllOverlays() ; Update and show all overlays permanently
    
    ; No timer needed as we're using persistent overlays
}

CreateOverlay(monitorIndex) { ; Creates workspace indicator overlay for specified monitor
    ; Get monitor dimensions
    MonitorGetWorkArea(monitorIndex, &mLeft, &mTop, &mRight, &mBottom) ; Gets coordinates of monitor
    
    ; Calculate overlay position based on preference
    if (OVERLAY_POSITION = "TopLeft") {
        x := mLeft + OVERLAY_MARGIN
        y := mTop + OVERLAY_MARGIN
    } else if (OVERLAY_POSITION = "TopRight") {
        x := mRight - OVERLAY_SIZE - OVERLAY_MARGIN
        y := mTop + OVERLAY_MARGIN
    } else if (OVERLAY_POSITION = "BottomLeft") {
        x := mLeft + OVERLAY_MARGIN
        y := mBottom - OVERLAY_SIZE - OVERLAY_MARGIN
    } else { ; Default to BottomRight
        x := mRight - OVERLAY_SIZE - OVERLAY_MARGIN
        y := mBottom - OVERLAY_SIZE - OVERLAY_MARGIN
    }
    
    ; Create GUI for overlay
    overlay := Gui("+AlwaysOnTop -Caption +ToolWindow +Owner") ; Creates a borderless, always-on-top window
    overlay.BackColor := "222222" ; Dark gray background
    
    ; Add workspace label
    workspaceID := MonitorWorkspaces.Has(monitorIndex) ? MonitorWorkspaces[monitorIndex] : 0
    overlay.SetFont("s30 bold", "Arial") ; Increased font size for better visibility
    ; Calculate better vertical centering - move text down to center it
    verticalOffset := 8 ; Moderate y-offset for precise vertical centering
    ; Add text with proper centering (both horizontal and vertical)
    overlay.Add("Text", "x0 y" verticalOffset " c33FFFF Center vWorkspaceText w" OVERLAY_SIZE " h" OVERLAY_SIZE, workspaceID) ; Adds text label with workspace ID
    
    ; Show the overlay first so we can set transparency
    overlay.Show("x" x " y" y " w" OVERLAY_SIZE " h" OVERLAY_SIZE " NoActivate") ; Shows the overlay
    
    ; Set transparency after the window is shown
    try {
        WinSetTransparent(OVERLAY_OPACITY, "ahk_id " overlay.Hwnd) ; Sets window transparency
    } catch Error as err {
        ; If transparency setting fails, continue without it
    }
    
    ; Store overlay reference
    WorkspaceOverlays[monitorIndex] := overlay
    ; Overlay is already shown above
}

UpdateAllOverlays() { ; Updates all workspace number indicators
    ; Update and show all overlays
    for monitorIndex, overlay in WorkspaceOverlays {
        UpdateOverlay(monitorIndex)
    }
    
    ; No timer needed as we're using persistent overlays
}

UpdateOverlay(monitorIndex) { ; Updates the workspace indicator for specified monitor
    ; Update overlay content to show current workspace ID
    if (!WorkspaceOverlays.Has(monitorIndex))
        return
        
    overlay := WorkspaceOverlays[monitorIndex]
    workspaceID := MonitorWorkspaces.Has(monitorIndex) ? MonitorWorkspaces[monitorIndex] : 0
    
    ; Update the text control by name
    try {
        ; Get the text control
        ctrl := overlay["WorkspaceText"]
        
        ; Update the text value
        ctrl.Value := workspaceID ; Updates the text to current workspace ID
        
        ; Ensure proper position - redoing options to maintain vertical centering
        verticalOffset := 8 ; Match the offset used in CreateOverlay
        ctrl.Opt("x0 y" verticalOffset " Center w" OVERLAY_SIZE " h" OVERLAY_SIZE)
    } catch Error as err {
        ; If control can't be found by name, fall back to first control
        for ctrl in overlay {
            ctrl.Value := workspaceID ; Updates the text to current workspace ID
            verticalOffset := 8 ; Match the offset used in CreateOverlay
            ctrl.Opt("x0 y" verticalOffset " Center w" OVERLAY_SIZE " h" OVERLAY_SIZE)
            break ; Only update the first control
        }
    }
    
    ; Show the overlay
    overlay.Show("NoActivate") ; Shows the overlay without activating it
}

HideAllOverlays() { ; Hides all workspace indicators
    ; Hide all overlays
    for monitorIndex, overlay in WorkspaceOverlays {
        overlay.Hide() ; Hides the overlay
    }
}

ToggleOverlays() { ; Toggles visibility of workspace indicators
    ; Toggle overlay visibility
    static isVisible := true
    
    if (isVisible) {
        HideAllOverlays()
    } else {
        UpdateAllOverlays()
        
        ; Reset hide timer if using timeout
        if (OVERLAY_TIMEOUT > 0) {
            SetTimer(HideAllOverlays, -OVERLAY_TIMEOUT) ; Sets timer to hide overlays after specified delay
        }
    }
    
    isVisible := !isVisible
}