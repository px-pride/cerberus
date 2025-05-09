#Requires AutoHotkey v2.0
#SingleInstance Force

; Cerberus - Multi-monitor workspace management system
; To enable debug mode, change DEBUG_MODE to True below

; ====== Function Definitions ======

; ----- Core System Functions -----

InitializeWorkspaces() {
    if (DEBUG_MODE)
        OutputDebug("============ INITIALIZING WORKSPACES ============")

    ; Initialize monitor workspaces (default: monitor 1 = workspace 1, monitor 2 = workspace 2, etc.)
    monitorCount := MonitorGetCount() ; Gets the total number of physical monitors connected to the system
    if (DEBUG_MODE)
        OutputDebug("Detected " monitorCount " monitors") ; Logs the number of detected monitors to debug output for troubleshooting

    loop MAX_MONITORS {
        monitorIndex := A_Index
        if (monitorIndex <= monitorCount) {
            if (monitorIndex <= MAX_WORKSPACES) {
                MonitorWorkspaces[monitorIndex] := monitorIndex
            } else {
                MonitorWorkspaces[monitorIndex] := 1  ; Default to workspace 1 if we have more monitors than workspaces
            }
            if (DEBUG_MODE)
                OutputDebug("Assigned monitor " monitorIndex " to workspace " MonitorWorkspaces[monitorIndex])
        }
    }

    ; Capture all existing windows and assign them to their monitor's workspace
    DetectHiddenWindows(False) ; Turns off detection of hidden windows so only visible windows are captured
    windows := WinGetList() ; Retrieves an array of all visible window handles (HWND) currently open in the system

    if (DEBUG_MODE)
        OutputDebug("Found " windows.Length " total windows in system")
    windowCount := 0
    assignedCount := 0

    ; First pass - identify all valid windows
    validWindows := []
    for hwnd in windows {
        windowCount++
        title := WinGetTitle(hwnd) ; Gets the title text from the window's title bar for identification
        class := WinGetClass(hwnd) ; Gets the window class name which identifies the window type or application

        if (DEBUG_MODE)
            OutputDebug("Checking window - Title: " title ", Class: " class ", hwnd: " hwnd)

        if (IsWindowValid(hwnd)) { ; Checks if this window should be tracked (excludes system windows, taskbar, etc.)
            if (DEBUG_MODE)
                OutputDebug("Window is valid - adding to tracking list")
            validWindows.Push(hwnd)
        }
    }

    if (DEBUG_MODE)
        OutputDebug("Found " validWindows.Length " valid windows to track")

    ; Second pass - assign valid windows to workspaces
    for hwnd in validWindows { ; Iterates through the array of window handles that passed validation
        title := WinGetTitle(hwnd)
        class := WinGetClass(hwnd)

        ; Check if window is minimized - assign to workspace 0 if it is
        if (WinGetMinMax(hwnd) = -1) { ; Checks window state: -1=minimized, 0=normal, 1=maximized
            WindowWorkspaces[hwnd] := 0 ; Assigns minimized window to workspace 0 (unassigned)
            if (DEBUG_MODE)
                OutputDebug("Window is minimized, assigned to workspace 0 (unassigned): " title)
            continue ; Skip to next window
        }

        ; Assign the window to its monitor's workspace
        monitorIndex := GetWindowMonitor(hwnd) ; Determines which physical monitor contains this window
        workspaceID := MonitorWorkspaces.Has(monitorIndex) ? MonitorWorkspaces[monitorIndex] : 0 ; Gets workspace ID for this monitor, or 0 if monitor isn't tracked

        WindowWorkspaces[hwnd] := workspaceID ; Adds window to the tracking map with its workspace ID
        SaveWindowLayout(hwnd, workspaceID) ; Stores window's position, size, and state (normal/maximized) for later restoration

        if (DEBUG_MODE)
            OutputDebug("Assigned window to workspace " workspaceID " on monitor " monitorIndex ": " title)
        assignedCount++
    }

    if (DEBUG_MODE) {
        OutputDebug("Initialization complete: Found " windowCount " windows, " validWindows.Length " valid, assigned " assignedCount " to workspaces")
        OutputDebug("============ INITIALIZATION COMPLETE ============")
    }

    ; Display a tray tip with the number of windows assigned
    TrayTip("Cerberus initialized", "Assigned " assignedCount " windows to workspaces") ; Shows notification in system tray
}

IsWindowValid(hwnd) { ; Checks if window should be tracked by Cerberus
    ; Skip invalid handles safely
    try {
        if (!WinExist(hwnd)) ; Verifies if the window handle is still valid and references an existing window
            return false
    } catch Error as err {
        ; If there's an error checking the window, it's definitely not valid
        return false
    }

    ; Get window information (only retrieve once) - safely within a try-catch
    try {
        title := WinGetTitle(hwnd) ; Gets the window title
        class := WinGetClass(hwnd) ; Gets the window class

        ; Debug output for all windows only if DEBUG_MODE is on
        if (DEBUG_MODE) {
            OutputDebug("Checking window - Title: " title ", Class: " class ", hwnd: " hwnd)
        }

        ; Fast checks first (skip windows without a title or class)
        if (title = "" || class = "")
            return false

        ; Skip the script's own window reliably using script's own hwnd
        if (hwnd = A_ScriptHwnd)
            return false

        ; More comprehensive class filtering for system windows
        static skipClasses := "Progman,Shell_TrayWnd,WorkerW,TaskListThumbnailWnd,ApplicationFrameWindow,Windows.UI.Core.CoreWindow,TaskManagerWindow,NotifyIconOverflowWindow"
        if (InStr(skipClasses, class))
            return false

        ; More comprehensive title filtering for system components
        static skipTitles := "Task View,Start Menu,Windows Shell Experience Host,Action Center,Search,Cortana,Windows Default Lock Screen,Notifications"
        if (InStr(skipTitles, title))
            return false

        ; Check window styles - safely with additional try-catch
        try {
            WS_CHILD := 0x40000000
            WS_EX_TOOLWINDOW := 0x00000080
            WS_EX_APPWINDOW := 0x00040000

            style := WinGetStyle(hwnd) ; Retrieves window style flags
            exStyle := WinGetExStyle(hwnd) ; Retrieves extended window style flags

            ; Skip child windows
            if (style & WS_CHILD)
                return false

            ; Skip tool windows that don't appear in the taskbar (unless they have the APPWINDOW style)
            if ((exStyle & WS_EX_TOOLWINDOW) && !(exStyle & WS_EX_APPWINDOW))
                return false
        } catch Error as err {
            ; If we can't get window styles, assume it's not valid
            if (DEBUG_MODE)
                OutputDebug("Error getting window styles: " err.Message)
            return false
        }

        ; For debugging, log valid windows
        if (DEBUG_MODE) {
            OutputDebug("VALID WINDOW - Title: " title ", Class: " class ", hwnd: " hwnd)
        }

        ; Window passed all checks, it's valid for tracking
        return true
    } catch Error as err {
        ; If there's any error getting window information, the window isn't valid
        if (DEBUG_MODE)
            OutputDebug("Error validating window " hwnd ": " err.Message)
        return false
    }
}

GetWindowMonitor(hwnd) { ; Determines which monitor contains the window
    try {
        monitorCount := MonitorGetCount() ; Gets the total number of physical monitors to determine which monitor contains the window

        if (monitorCount = 1)
            return 1

        ; Get window position - this can fail if the window is invalid
        try {
            WinGetPos(&x, &y, &width, &height, hwnd) ; Retrieves window position and size, storing values in the referenced variables

            ; Make sure the values are valid
            if (x = "" || y = "" || width = "" || height = "")
                return 1 ; Default to primary monitor if we get invalid position values

            ; Find which monitor contains the center of the window
            centerX := x + width / 2
            centerY := y + height / 2

            loop monitorCount {
                MonitorGetWorkArea(A_Index, &mLeft, &mTop, &mRight, &mBottom) ; Gets coordinates of monitor work area
                if (centerX >= mLeft && centerX <= mRight && centerY >= mTop && centerY <= mBottom)
                    return A_Index
            }
        } catch Error as err {
            if (DEBUG_MODE)
                OutputDebug("Error getting window position: " err.Message)
            return 1 ; Default to primary monitor on error
        }
    } catch Error as err {
        if (DEBUG_MODE)
            OutputDebug("Error in GetWindowMonitor: " err.Message)
        return 1 ; Default to primary monitor on any error
    }

    ; Default to primary monitor if no match
    return 1
}

GetActiveMonitor() { ; Gets the monitor index where the active window is located
    try {
        ; Get active window
        activeHwnd := WinExist("A") ; Gets handle of active window
        if !activeHwnd
            return 1  ; Default to primary monitor

        return GetWindowMonitor(activeHwnd) ; Gets monitor index for active window
    } catch Error as err {
        if (DEBUG_MODE)
            OutputDebug("Error in GetActiveMonitor: " err.Message)
        return 1  ; Default to primary monitor on any error
    }
}

SaveWindowLayout(hwnd, workspaceID) { ; Stores window position and state for later restoration
    if !IsWindowValid(hwnd) || workspaceID < 1 || workspaceID > MAX_WORKSPACES
        return

    try {
        ; Initialize workspace layout map if needed
        if !WorkspaceLayouts.Has(workspaceID) ; Checks if workspace exists in layouts map
            WorkspaceLayouts[workspaceID] := Map() ; Creates new map for this workspace

        ; Get window position and state - this can fail if window is invalid or in a transition state
        try {
            WinGetPos(&x, &y, &width, &height, hwnd) ; Captures current window coordinates and dimensions to save in layout

            ; Make sure the values are valid
            if (x = "" || y = "" || width = "" || height = "")
                return ; Skip saving if we get invalid position values

            ; Get window state
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
        } catch Error as err {
            if (DEBUG_MODE)
                OutputDebug("Error getting window position in SaveWindowLayout: " err.Message)
        }
    } catch Error as err {
        if (DEBUG_MODE)
            OutputDebug("Error in SaveWindowLayout: " err.Message)
    }
}

RestoreWindowLayout(hwnd, workspaceID) { ; Restores a window to its saved position and state
    ; Check if window exists and is valid
    if !IsWindowValid(hwnd) {
        if (DEBUG_MODE)
            OutputDebug("RESTORE FAILED: Window " hwnd " is not valid")
        return
    }

    title := WinGetTitle(hwnd)
    if (DEBUG_MODE)
        OutputDebug("Attempting to restore window: " title " (" hwnd ")")

    try {
        ; First ensure the window is restored from minimized state
        winState := WinGetMinMax(hwnd) ; Gets window state (-1=minimized, 0=normal, 1=maximized)
        if (winState = -1) { ; If window is currently minimized, restore it first before applying layout
            if (DEBUG_MODE)
                OutputDebug("Window is minimized, restoring first")

            try {
                WinRestore("ahk_id " hwnd) ; Restores window from minimized state so we can apply position/size
                Sleep(100) ; Allow time for the window to restore

                ; Verify the restore worked
                if (WinGetMinMax(hwnd) = -1) {
                    if (DEBUG_MODE)
                        OutputDebug("Window restore failed, retrying...")
                    Sleep(200)
                    WinRestore("ahk_id " hwnd) ; Try again
                    Sleep(100)
                }
            } catch Error as err {
                if (DEBUG_MODE)
                    OutputDebug("ERROR restoring window from minimized state: " err.Message)
            }
        }

        ; Check if we have saved layout data
        if (WorkspaceLayouts.Has(workspaceID)) {
            layouts := WorkspaceLayouts[workspaceID]

            if (layouts.Has(hwnd)) {
                layout := layouts[hwnd]
                if (DEBUG_MODE)
                    OutputDebug("Found saved layout for window: x=" layout.x ", y=" layout.y ", w=" layout.width ", h=" layout.height)

                ; Apply saved layout
                if (layout.isMaximized) { ; If window was previously maximized
                    if (DEBUG_MODE)
                        OutputDebug("Maximizing window")

                    try {
                        WinMaximize("ahk_id " hwnd) ; Restore window to maximized state

                        ; Verify maximize worked
                        if (WinGetMinMax(hwnd) != 1) {
                            if (DEBUG_MODE)
                                OutputDebug("Window maximize failed, retrying...")
                            Sleep(200)
                            WinMaximize("ahk_id " hwnd) ; Try again
                        }
                    } catch Error as err {
                        if (DEBUG_MODE)
                            OutputDebug("ERROR maximizing window: " err.Message)
                    }
                } else {
                    ; Move window to saved position
                    try {
                        if (DEBUG_MODE)
                            OutputDebug("Moving window to saved position")

                        ; Ensure coordinates are within screen bounds
                        monitorCount := MonitorGetCount()
                        coordsValid := false

                        ; Check if coordinates are within any monitor's bounds
                        loop monitorCount {
                            MonitorGetWorkArea(A_Index, &mLeft, &mTop, &mRight, &mBottom)
                            if (layout.x >= mLeft - layout.width && layout.x <= mRight &&
                                layout.y >= mTop - layout.height && layout.y <= mBottom) {
                                coordsValid := true
                                break
                            }
                        }

                        if (coordsValid) {
                            WinMove(layout.x, layout.y, layout.width, layout.height, "ahk_id " hwnd)
                        } else {
                            if (DEBUG_MODE)
                                OutputDebug("Window position out of bounds, using default position")
                            WinActivate("ahk_id " hwnd)
                        }
                    } catch Error as err {
                        if (DEBUG_MODE)
                            OutputDebug("ERROR moving window: " err.Message)
                    }
                }
            } else {
                if (DEBUG_MODE)
                    OutputDebug("No saved layout found for this window, using default position")
                WinActivate("ahk_id " hwnd) ; At least activate the window
            }
        } else {
            if (DEBUG_MODE)
                OutputDebug("No layouts saved for workspace " workspaceID)
        }

        ; Ensure window is visible and brought to front
        try {
            WinActivate("ahk_id " hwnd) ; Brings window to foreground and gives it keyboard focus
        } catch Error as err {
            if (DEBUG_MODE)
                OutputDebug("ERROR activating window: " err.Message)
        }
    } catch Error as err {
        if (DEBUG_MODE)
            OutputDebug("CRITICAL ERROR in RestoreWindowLayout: " err.Message)
    }
}

SwitchToWorkspace(requestedID) { ; Changes active workspace on current monitor
    if (requestedID < 1 || requestedID > MAX_WORKSPACES)
        return

    ; Debug output to help diagnose issues
    if (DEBUG_MODE) {
        OutputDebug("------------- WORKSPACE SWITCH START -------------")
        OutputDebug("Switching to workspace: " requestedID)
    }

    ; Get active monitor
    activeMonitor := GetActiveMonitor() ; Gets the monitor index that contains the currently active (focused) window
    if (DEBUG_MODE)
        OutputDebug("Active monitor: " activeMonitor)

    ; Get current workspace ID for active monitor
    currentWorkspaceID := MonitorWorkspaces.Has(activeMonitor) ? MonitorWorkspaces[activeMonitor] : 1 ; Gets current workspace ID for active monitor, defaults to 1 if not found
    if (DEBUG_MODE)
        OutputDebug("Current workspace on active monitor: " currentWorkspaceID)

    ; If already on requested workspace, do nothing
    if (currentWorkspaceID = requestedID) {
        if (DEBUG_MODE)
            OutputDebug("Already on requested workspace. No action needed.")
        return
    }

    ; Check if the requested workspace is already on another monitor - direct swap approach
    otherMonitor := 0
    for monIndex, workspaceID in MonitorWorkspaces {
        if (monIndex != activeMonitor && workspaceID = requestedID) {
            otherMonitor := monIndex
            if (DEBUG_MODE)
                OutputDebug("Found requested workspace on monitor: " otherMonitor)
            break
        }
    }

    if (otherMonitor > 0) {
        ; === PERFORMING WORKSPACE EXCHANGE BETWEEN MONITORS ===
        if (DEBUG_MODE)
            OutputDebug("Performing workspace exchange between monitors " activeMonitor " and " otherMonitor)

        ; Get monitor dimensions
        MonitorGetWorkArea(activeMonitor, &aLeft, &aTop, &aRight, &aBottom)
        MonitorGetWorkArea(otherMonitor, &oLeft, &oTop, &oRight, &oBottom)

        ; Calculate offset between monitors (to maintain relative positions)
        offsetX := aLeft - oLeft
        offsetY := aTop - oTop

        ; Get all open windows
        windows := WinGetList()
        if (DEBUG_MODE)
            OutputDebug("Found " windows.Length " total windows")

        ; Collect windows on each monitor
        activeMonitorWindows := []
        otherMonitorWindows := []

        for index, hwnd in windows {
            ; Skip invalid windows
            if (!IsWindowValid(hwnd))
                continue

            ; Get window monitor
            windowMonitor := GetWindowMonitor(hwnd)

            ; Collect windows by monitor
            if (windowMonitor = activeMonitor)
                activeMonitorWindows.Push(hwnd)
            else if (windowMonitor = otherMonitor)
                otherMonitorWindows.Push(hwnd)
        }

        if (DEBUG_MODE) {
            OutputDebug("Found " activeMonitorWindows.Length " windows on active monitor and "
                otherMonitorWindows.Length " windows on other monitor")
        }

        ; Step 1: Swap workspace IDs between monitors
        if (DEBUG_MODE)
            OutputDebug("Swapping workspace IDs: " currentWorkspaceID " and " requestedID)
        MonitorWorkspaces[otherMonitor] := currentWorkspaceID
        MonitorWorkspaces[activeMonitor] := requestedID

        ; Step 2: Move windows from active monitor to other monitor
        for index, hwnd in activeMonitorWindows {
            try {
                ; Get window position and state
                WinGetPos(&x, &y, &width, &height, hwnd)
                isMaximized := WinGetMinMax(hwnd) = 1

                if (DEBUG_MODE) {
                    title := WinGetTitle(hwnd)
                    OutputDebug("Moving window from active to other monitor: " title)
                }

                ; Move window, preserving layout
                if (isMaximized) {
                    ; First restore to normal, move, then maximize again
                    if (WinGetMinMax(hwnd) = 1)
                        WinRestore("ahk_id " hwnd)

                    ; Move to new position
                    WinMove(x - offsetX, y - offsetY, width, height, "ahk_id " hwnd)

                    ; Maximize again
                    WinMaximize("ahk_id " hwnd)
                } else {
                    ; For non-maximized windows, just move them
                    WinMove(x - offsetX, y - offsetY, width, height, "ahk_id " hwnd)
                }

                Sleep(30) ; Short delay to prevent overwhelming the system
            } catch Error as err {
                if (DEBUG_MODE)
                    OutputDebug("ERROR moving window: " err.Message)
            }
        }

        ; Step 3: Move windows from other monitor to active monitor
        for index, hwnd in otherMonitorWindows {
            try {
                ; Get window position and state
                WinGetPos(&x, &y, &width, &height, hwnd)
                isMaximized := WinGetMinMax(hwnd) = 1

                if (DEBUG_MODE) {
                    title := WinGetTitle(hwnd)
                    OutputDebug("Moving window from other to active monitor: " title)
                }

                ; Move window, preserving layout
                if (isMaximized) {
                    ; First restore to normal, move, then maximize again
                    if (WinGetMinMax(hwnd) = 1)
                        WinRestore("ahk_id " hwnd)

                    ; Move to new position
                    WinMove(x + offsetX, y + offsetY, width, height, "ahk_id " hwnd)

                    ; Maximize again
                    WinMaximize("ahk_id " hwnd)
                } else {
                    ; For non-maximized windows, just move them
                    WinMove(x + offsetX, y + offsetY, width, height, "ahk_id " hwnd)
                }

                Sleep(30) ; Short delay to prevent overwhelming the system
            } catch Error as err {
                if (DEBUG_MODE)
                    OutputDebug("ERROR moving window: " err.Message)
            }
        }

        if (DEBUG_MODE)
            OutputDebug("Moved windows between monitors while preserving layout")
    }
    else {
        ; === STANDARD WORKSPACE SWITCH (NO EXCHANGE) ===
        if (DEBUG_MODE)
            OutputDebug("Standard workspace switch - no exchange needed")

        ; ====== STEP 1: Identify and minimize all windows on the active monitor ======
        ; Get all open windows
        windows := WinGetList() ; Gets a list of all open windows
        if (DEBUG_MODE)
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
                if (DEBUG_MODE)
                    OutputDebug("MINIMIZING window on active monitor: " title)

                ; Force the window to minimize
                try {
                    WinMinimize("ahk_id " hwnd)
                    Sleep(50) ; Delay to allow minimize operation to complete
                } catch Error as err {
                    if (DEBUG_MODE)
                        OutputDebug("ERROR minimizing window: " err.Message)
                }
            }
        }

        ; ====== STEP 2: Change workspace ID for active monitor ======
        ; Update the workspace ID for the active monitor
        MonitorWorkspaces[activeMonitor] := requestedID
        if (DEBUG_MODE)
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

            ; Check if window is on active monitor
            if (windowMonitor = activeMonitor) {
                ; This is a window that should be restored for the new workspace
                if (DEBUG_MODE)
                    OutputDebug("RESTORING window for new workspace: " title)

                ; Force window restore - the WindowMoveResizeHandler will handle workspace assignment
                try {
                    ; Restore from minimized state if needed
                    if (winState = -1) {
                        WinRestore("ahk_id " hwnd)
                    }

                    ; Note: WindowWorkspaces is now updated by event handlers, not directly here
                    SaveWindowLayout(hwnd, requestedID)

                    restoreCount++
                    Sleep(30) ; Delay to allow restore operation to complete
                } catch Error as err {
                    if (DEBUG_MODE)
                        OutputDebug("ERROR restoring window: " err.Message)
                }
            }
        }

        if (DEBUG_MODE)
            OutputDebug("Restored " restoreCount " windows for workspace " requestedID)
    }

    if (DEBUG_MODE)
        OutputDebug("------------- WORKSPACE SWITCH END -------------")

    ; Update workspace overlays to reflect the new assignments
    UpdateAllOverlays()
}

; ----- Event Handlers -----

; Clean up stale window references to prevent memory leaks
CleanupWindowReferences() {
    ; Clean up lastWindowState map if it exists in the WindowMoveResizeHandler function
    staleCount := 0
    
    ; Only try to clean up lastWindowState if the property exists on the function
    try {
        ; Check if the static map has been initialized in WindowMoveResizeHandler
        if (ObjHasOwnProp(WindowMoveResizeHandler, "lastWindowState")) {
            lastStateMap := WindowMoveResizeHandler.lastWindowState
            
            for hwnd, state in lastStateMap {
                try {
                    if !WinExist(hwnd) {
                        lastStateMap.Delete(hwnd)
                        staleCount++
                    }
                } catch Error as err {
                    ; If there's an error, remove this reference anyway
                    lastStateMap.Delete(hwnd)
                    staleCount++
                }
            }
        }
    } catch Error as err {
        if (DEBUG_MODE)
            OutputDebug("Info: Skipping lastWindowState cleanup - not initialized yet")
    }
    
    ; Clean up WindowWorkspaces map
    workspaceStaleCount := 0
    for hwnd, workspaceID in WindowWorkspaces {
        try {
            if !WinExist(hwnd) {
                WindowWorkspaces.Delete(hwnd)
                workspaceStaleCount++
            }
        } catch Error as err {
            ; If there's an error, remove this reference anyway
            WindowWorkspaces.Delete(hwnd)
            workspaceStaleCount++
        }
    }
    
    ; Clean up WorkspaceLayouts map
    layoutTotalStaleCount := 0
    for workspaceID, layoutMap in WorkspaceLayouts {
        layoutStaleCount := 0
        for hwnd, layout in layoutMap {
            try {
                if !WinExist(hwnd) {
                    layoutMap.Delete(hwnd)
                    layoutStaleCount++
                }
            } catch Error as err {
                ; If there's an error, remove this reference anyway
                layoutMap.Delete(hwnd)
                layoutStaleCount++
            }
        }
        if (layoutStaleCount > 0 && DEBUG_MODE) {
            OutputDebug("Cleaned up " layoutStaleCount " stale layout entries for workspace " workspaceID)
            layoutTotalStaleCount += layoutStaleCount
        }
    }
    
    if ((staleCount > 0 || workspaceStaleCount > 0 || layoutTotalStaleCount > 0) && DEBUG_MODE) {
        OutputDebug("Cleaned up " staleCount " window state entries, " workspaceStaleCount " workspace entries, and " layoutTotalStaleCount " layout entries")
    }
}

WindowMoveResizeHandler(wParam, lParam, msg, hwnd) { ; Handles window move/resize events to update saved layouts
    ; Skip invalid windows
    if (!IsWindowValid(hwnd))
        return

    ; Get window state
    winState := WinGetMinMax(hwnd)
    title := WinGetTitle(hwnd)

    ; Check if window is minimized
    if (winState = -1) { ; Window is minimized
        ; Check if window is assigned to a workspace
        if (WindowWorkspaces.Has(hwnd)) {
            workspaceID := WindowWorkspaces[hwnd]

            ; Get the active monitor and its workspace
            activeMonitor := GetActiveMonitor()
            activeWorkspaceID := MonitorWorkspaces.Has(activeMonitor) ? MonitorWorkspaces[activeMonitor] : 1

            ; If window belongs to the currently active workspace, set it to workspace 0 (unassigned)
            if (workspaceID = activeWorkspaceID) {
                WindowWorkspaces[hwnd] := 0
                OutputDebug("Window minimized and removed from active workspace: " title)
            }
        }
        return
    }

    ; Handle window un-minimization (going from minimized to normal state)
    ; Use a static class variable to persist the map between function calls
    static lastWindowState := Map() ; Static map to track previous window states

    ; Store the map in the function object to make it accessible from other functions
    WindowMoveResizeHandler.lastWindowState := lastWindowState

    ; Check if we're tracking this window already
    if (!lastWindowState.Has(hwnd))
        lastWindowState[hwnd] := -999 ; Initialize with invalid state value

    ; Detect un-minimization (from minimized to normal/maximized)
    if (lastWindowState[hwnd] = -1 && winState != -1) {
        ; Window was just un-minimized, assign to monitor's workspace
        windowMonitor := GetWindowMonitor(hwnd)

        if (MonitorWorkspaces.Has(windowMonitor)) {
            newWorkspaceID := MonitorWorkspaces[windowMonitor]

            ; Update workspace assignment
            prevWorkspaceID := WindowWorkspaces.Has(hwnd) ? WindowWorkspaces[hwnd] : 0

            if (prevWorkspaceID != newWorkspaceID) {
                WindowWorkspaces[hwnd] := newWorkspaceID
                OutputDebug("Window un-minimized, reassigned from workspace " prevWorkspaceID " to " newWorkspaceID ": " title)
            }
        }
    }

    ; Update last known state
    lastWindowState[hwnd] := winState

    ; For moved/resized windows, update workspace assignment based on monitor
    if (msg = 0x0003 || msg = 0x0005) { ; WM_MOVE or WM_SIZE
        ; Get current monitor and workspace assignment
        windowMonitor := GetWindowMonitor(hwnd)

        if (MonitorWorkspaces.Has(windowMonitor)) {
            currentMonitorWorkspace := MonitorWorkspaces[windowMonitor]

            ; Only update if window has a workspace assigned
            if (WindowWorkspaces.Has(hwnd)) {
                currentWindowWorkspace := WindowWorkspaces[hwnd]

                ; If window's workspace doesn't match its monitor's workspace, update it
                if (currentWindowWorkspace != currentMonitorWorkspace && currentWindowWorkspace != 0) {
                    WindowWorkspaces[hwnd] := currentMonitorWorkspace
                    OutputDebug("Window moved/resized, reassigned from workspace " currentWindowWorkspace " to " currentMonitorWorkspace ": " title)
                }
            }
        }
    }

    ; Save layout if window has a valid workspace assignment
    if (WindowWorkspaces.Has(hwnd)) {
        workspaceID := WindowWorkspaces[hwnd]
        if (workspaceID > 0)
            SaveWindowLayout(hwnd, workspaceID)
    }
}

NewWindowHandler(wParam, lParam, msg, hwnd) { ; Handles window creation events to assign new windows
    ; First do an immediate check to see if the window is valid and what monitor it's on
    if (IsWindowValid(hwnd)) {
        try {
            ; Get window monitor and assign to appropriate workspace immediately
            monitorIndex := GetWindowMonitor(hwnd)

            if (MonitorWorkspaces.Has(monitorIndex)) {
                workspaceID := MonitorWorkspaces[monitorIndex]

                ; Get window title safely
                try {
                    title := WinGetTitle(hwnd)

                    ; Assign to workspace of monitor it appears on
                    WindowWorkspaces[hwnd] := workspaceID

                    if (DEBUG_MODE)
                        OutputDebug("New window immediately assigned to workspace " workspaceID " on monitor " monitorIndex ": " title)

                    ; Save layout and check visibility
                    SaveWindowLayout(hwnd, workspaceID)

                    ; Check if this window should be visible or hidden on this monitor
                    currentWorkspaceID := MonitorWorkspaces[monitorIndex]
                    if (workspaceID != currentWorkspaceID) {
                        ; If window belongs to workspace not current on this monitor, minimize it
                        WinMinimize("ahk_id " hwnd)
                        if (DEBUG_MODE)
                            OutputDebug("Minimized new window belonging to non-visible workspace")
                    }
                } catch Error as err {
                    if (DEBUG_MODE)
                        OutputDebug("Error getting window title in immediate assignment: " err.Message)
                }
            }
        } catch Error as err {
            if (DEBUG_MODE)
                OutputDebug("Error in new window handler: " err.Message)
        }
    }

    ; Also queue a delayed assignment to catch any window movement or initialization issues
    ; This helps ensure window properties and position are stable after initial creation
    SetTimer(() => AssignNewWindow(hwnd), -1000) ; Run a follow-up check after 1 second
}

AssignNewWindow(hwnd) { ; Assigns a new window to appropriate workspace (delayed follow-up check)
    ; Check again if the window exists and is valid - it might have closed already
    if (!IsWindowValid(hwnd))
        return

    ; Get window info safely
    try {
        title := WinGetTitle(hwnd)
        class := WinGetClass(hwnd)

        if (DEBUG_MODE)
            OutputDebug("Follow-up check for window - Title: " title ", Class: " class ", hwnd: " hwnd)
    } catch Error as err {
        if (DEBUG_MODE)
            OutputDebug("Error getting window info in delayed check: " err.Message)
        return
    }

    ; Check the window's current monitor (it may have moved since initial creation)
    try {
        monitorIndex := GetWindowMonitor(hwnd) ; Gets which monitor the window is on now
        if (DEBUG_MODE)
            OutputDebug("Window is now on monitor: " monitorIndex)
    } catch Error as err {
        if (DEBUG_MODE)
            OutputDebug("Error getting window monitor in delayed check: " err.Message)
        return
    }

    if (MonitorWorkspaces.Has(monitorIndex)) { ; Checks if monitor has assigned workspace
        workspaceID := MonitorWorkspaces[monitorIndex] ; Gets workspace ID for this monitor

        ; Check if this window already has a workspace assignment
        if (!WindowWorkspaces.Has(hwnd)) {
            try {
                ; Window was not assigned in initial handler - assign it now
                WindowWorkspaces[hwnd] := workspaceID ; Assigns window to workspace
                SaveWindowLayout(hwnd, workspaceID) ; Saves window layout
                if (DEBUG_MODE)
                    OutputDebug("Window assigned in delayed check to workspace " workspaceID " on monitor " monitorIndex)

                ; Check visibility
                currentWorkspaceID := MonitorWorkspaces[monitorIndex]
                if (workspaceID != currentWorkspaceID) {
                    WinMinimize("ahk_id " hwnd)
                    if (DEBUG_MODE)
                        OutputDebug("Minimized window belonging to non-visible workspace (delayed check)")
                }
            } catch Error as err {
                if (DEBUG_MODE)
                    OutputDebug("Error assigning window in delayed check: " err.Message)
            }
        } else {
            try {
                ; Window already has workspace assignment, but may need updating if it moved monitors
                currentWorkspaceID := WindowWorkspaces[hwnd]

                ; If window's current workspace doesn't match its monitor's workspace, update it
                if (currentWorkspaceID != workspaceID) {
                    WindowWorkspaces[hwnd] := workspaceID
                    SaveWindowLayout(hwnd, workspaceID)
                    if (DEBUG_MODE)
                        OutputDebug("Updated window workspace from " currentWorkspaceID " to " workspaceID " (delayed check)")

                    ; Check if it needs to be minimized due to workspace mismatch
                    currentMonitorWorkspace := MonitorWorkspaces[monitorIndex]
                    if (workspaceID != currentMonitorWorkspace && WinGetMinMax(hwnd) != -1) {
                        WinMinimize("ahk_id " hwnd)
                        if (DEBUG_MODE)
                            OutputDebug("Minimized moved window for workspace consistency (delayed check)")
                    }
                }
            } catch Error as err {
                if (DEBUG_MODE)
                    OutputDebug("Error updating window workspace in delayed check: " err.Message)
            }
        }
    } else {
        ; Default to unassigned if monitor has no workspace
        try {
            WindowWorkspaces[hwnd] := 0
            if (DEBUG_MODE)
                OutputDebug("Assigned window to unassigned workspace (0) - monitor not tracked (delayed check)")
        } catch Error as err {
            if (DEBUG_MODE)
                OutputDebug("Error assigning window to unassigned workspace: " err.Message)
        }
    }
}

; ----- Overlay Functions -----

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

; ====== Configuration ======
MAX_WORKSPACES := 9  ; Maximum number of workspaces (1-9)
MAX_MONITORS := 9    ; Maximum number of monitors (adjust as needed)

; ====== Global Variables ======
; ===== DEBUG SETTINGS =====
; Set this to True to enable detailed logging for troubleshooting
global DEBUG_MODE := False  ; Change to True to enable debugging

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

; ====== Start Cerberus ======
InitializeWorkspaces() ; Call to initialize workspaces when script starts - sets up monitor-workspace mapping and assigns windows
InitializeOverlays() ; Create workspace overlay displays - adds visual indicators for workspace numbers

; Set up periodic cleanup of window references (every 2 minutes)
SetTimer(CleanupWindowReferences, 120000)

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

; ====== Register Event Handlers ======
; Track window move/resize events to update layouts
OnMessage(0x0003, WindowMoveResizeHandler)  ; WM_MOVE - Registers a handler for window move events
OnMessage(0x0005, WindowMoveResizeHandler)  ; WM_SIZE - Registers a handler for window resize events
; Track new window events to assign to current workspace
; This event provides an hwnd when a window is created
OnMessage(0x0001, NewWindowHandler)  ; WM_CREATE - Registers a handler for window creation events