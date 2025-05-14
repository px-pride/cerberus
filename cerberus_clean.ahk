#Requires AutoHotkey v2.0
#SingleInstance Force

; Cerberus - Multi-monitor workspace management system
; To enable debug mode, change DEBUG_MODE to True below

; Set custom tray icon
TraySetIcon(A_ScriptDir "\cerberus.ico")

; Removed external include - functionality integrated directly

; ====== Function Definitions ======

; ----- Core System Functions -----

InitializeWorkspaces() {
    if (DEBUG_MODE)
        LogMessage("============ INITIALIZING WORKSPACES ============")

    ; Initialize monitor workspaces (default: monitor 1 = workspace 1, monitor 2 = workspace 2, etc.)
    monitorCount := MonitorGetCount() ; Gets the total number of physical monitors connected to the system
    if (DEBUG_MODE)
        LogMessage("Detected " monitorCount " monitors") ; Logs the number of detected monitors to debug output for troubleshooting

    loop MAX_MONITORS {
        monitorIndex := A_Index
        if (monitorIndex <= monitorCount) {
            if (monitorIndex <= MAX_WORKSPACES) {
                MonitorWorkspaces[monitorIndex] := monitorIndex
            } else {
                MonitorWorkspaces[monitorIndex] := 1  ; Default to workspace 1 if we have more monitors than workspaces
            }
            if (DEBUG_MODE)
                LogMessage("Assigned monitor " monitorIndex " to workspace " MonitorWorkspaces[monitorIndex])
        }
    }

    ; Capture all existing windows and assign them to their monitor's workspace
    DetectHiddenWindows(False) ; Turns off detection of hidden windows so only visible windows are captured
    windows := WinGetList() ; Retrieves an array of all visible window handles (HWND) currently open in the system

    if (DEBUG_MODE)
        LogMessage("Found " windows.Length " total windows in system")
    windowCount := 0
    assignedCount := 0

    ; First pass - identify all valid windows
    validWindows := []
    for hwnd in windows {
        windowCount++
        title := WinGetTitle(hwnd) ; Gets the title text from the window's title bar for identification
        class := WinGetClass(hwnd) ; Gets the window class name which identifies the window type or application

        if (DEBUG_MODE)
            LogMessage("Checking window - Title: " title ", Class: " class ", hwnd: " hwnd)

        if (IsWindowValid(hwnd)) { ; Checks if this window should be tracked (excludes system windows, taskbar, etc.)
            if (DEBUG_MODE)
                LogMessage("Window is valid - adding to tracking list")
            validWindows.Push(hwnd)
        }
    }

    if (DEBUG_MODE)
        LogMessage("Found " validWindows.Length " valid windows to track")

    ; Second pass - assign valid windows to workspaces
    for hwnd in validWindows { ; Iterates through the array of window handles that passed validation
        title := WinGetTitle(hwnd)
        class := WinGetClass(hwnd)

        ; Check if window is minimized - assign to workspace 0 if it is
        if (WinGetMinMax(hwnd) = -1) { ; Checks window state: -1=minimized, 0=normal, 1=maximized
            WindowWorkspaces[hwnd] := 0 ; Assigns minimized window to workspace 0 (unassigned)
            if (DEBUG_MODE)
                LogMessage("Window is minimized, assigned to workspace 0 (unassigned): " title)
            continue ; Skip to next window
        }

        ; Assign the window to its monitor's workspace
        monitorIndex := GetWindowMonitor(hwnd) ; Determines which physical monitor contains this window
        workspaceID := MonitorWorkspaces.Has(monitorIndex) ? MonitorWorkspaces[monitorIndex] : 0 ; Gets workspace ID for this monitor, or 0 if monitor isn't tracked

        WindowWorkspaces[hwnd] := workspaceID ; Adds window to the tracking map with its workspace ID
        SaveWindowLayout(hwnd, workspaceID) ; Stores window's position, size, and state (normal/maximized) for later restoration

        if (DEBUG_MODE)
            LogMessage("Assigned window to workspace " workspaceID " on monitor " monitorIndex ": " title)
        assignedCount++
    }

    if (DEBUG_MODE) {
        LogMessage("Initialization complete: Found " windowCount " windows, " validWindows.Length " valid, assigned " assignedCount " to workspaces")
        LogMessage("============ INITIALIZATION COMPLETE ============")
    }

    ; Display a tray tip with the number of windows assigned
    TrayTip("Cerberus initialized", "Assigned " assignedCount " windows to workspaces") ; Shows notification in system tray
}

IsWindowValid(hwnd) { ; Checks if window should be tracked by Cerberus
    ; Reference global variables
    global DEBUG_MODE, A_ScriptHwnd

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
            LogMessage("Checking window - Title: " title ", Class: " class ", hwnd: " hwnd)
        }

        ; Fast checks first (skip windows without a title or class)
        if (title = "" || class = "")
            return false

        ; Skip the script's own window reliably using script's own hwnd
        if (hwnd = A_ScriptHwnd)
            return false

        ; More comprehensive class filtering for system windows
        ; removed from skipClasses: ApplicationFrameWindow, which matches windows like Calculator, Media Player, etc... (usually apps from Microsoft Store)
        static skipClasses := "Progman,Shell_TrayWnd,WorkerW,TaskListThumbnailWnd,Windows.UI.Core.CoreWindow,TaskManagerWindow,NotifyIconOverflowWindow"
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
                LogMessage("Error getting window styles: " err.Message)
            return false
        }

        ; For debugging, log valid windows
        if (DEBUG_MODE) {
            LogMessage("VALID WINDOW - Title: " title ", Class: " class ", hwnd: " hwnd)
        }

        ; Window passed all checks, it's valid for tracking
        return true
    } catch Error as err {
        ; If there's any error getting window information, the window isn't valid
        if (DEBUG_MODE)
            LogMessage("Error validating window " hwnd ": " err.Message)
        return false
    }
}

GetWindowMonitor(hwnd) { ; Determines which monitor contains the window
    ; This is now a wrapper for the improved GetWindowMonitorIndex function
    return GetWindowMonitorIndex(hwnd)
}

GetWindowMonitorIndex(windowHandle) { ; Improved version with better error handling
    ; Validate the windowHandle parameter
    try {
        if (!windowHandle || windowHandle = 0) {
            if (DEBUG_MODE)
                LogMessage("GetWindowMonitorIndex: Invalid window handle (null or zero)")
            return 1 ; Default to primary monitor
        }
    } catch Error as err {
        if (DEBUG_MODE)
            LogMessage("GetWindowMonitorIndex: Error validating handle parameter: " err.Message)
        return 1 ; Default to primary monitor
    }

    ; Verify window still exists
    try {
        if (!WinExist("ahk_id " windowHandle)) {
            if (DEBUG_MODE)
                LogMessage("GetWindowMonitorIndex: Window " windowHandle " no longer exists")
            return 1 ; Default to primary monitor
        }
    } catch Error as existErr {
        if (DEBUG_MODE)
            LogMessage("GetWindowMonitorIndex: Error checking window existence: " existErr.Message)
        return 1 ; Default to primary monitor
    }

    ; Get monitor count - handle error gracefully
    try {
        monitorCount := MonitorGetCount()
        if (monitorCount <= 0) {
            if (DEBUG_MODE)
                LogMessage("GetWindowMonitorIndex: Invalid monitor count: " monitorCount)
            return 1 ; Default to primary monitor
        }

        if (monitorCount = 1)
            return 1 ; Only one monitor, must be that one
    } catch Error as err {
        if (DEBUG_MODE)
            LogMessage("GetWindowMonitorIndex: Error getting monitor count: " err.Message)
        return 1 ; Default to primary monitor
    }

    ; Safely get window position
    try {
        ; Use a nested try-catch for the WinGetPos call specifically
        try {
            WinGetPos(&winX, &winY, &winWidth, &winHeight, "ahk_id " windowHandle)
        } catch Error as posErr {
            if (DEBUG_MODE)
                LogMessage("GetWindowMonitorIndex: WinGetPos failed: " posErr.Message)
            return 1 ; Default to primary monitor
        }

        ; Validate position values
        if (winX = "" || winY = "" || winWidth = "" || winHeight = "") {
            if (DEBUG_MODE)
                LogMessage("GetWindowMonitorIndex: Invalid position values for window")
            return 1 ; Default to primary monitor
        }

        ; Find window center
        centerX := winX + winWidth / 2
        centerY := winY + winHeight / 2

        ; Check which monitor contains this point
        loop monitorCount {
            try {
                MonitorGetWorkArea(A_Index, &mLeft, &mTop, &mRight, &mBottom)
                if (centerX >= mLeft && centerX <= mRight && centerY >= mTop && centerY <= mBottom)
                    return A_Index
            } catch Error as monErr {
                if (DEBUG_MODE)
                    LogMessage("GetWindowMonitorIndex: Error getting monitor " A_Index " work area: " monErr.Message)
                ; Continue checking other monitors
            }
        }
    } catch Error as err {
        if (DEBUG_MODE)
            LogMessage("GetWindowMonitorIndex: Error processing window position: " err.Message)
        return 1 ; Default to primary monitor
    }

    ; If no monitor contains the window center, default to primary
    if (DEBUG_MODE)
        LogMessage("GetWindowMonitorIndex: Window not found on any monitor - using primary")
    return 1
}

GetActiveMonitor() { ; Gets the monitor index where the mouse cursor is located
    ; Reference global variables
    global DEBUG_MODE

    try {
        ; Get mouse cursor position
        MouseGetPos(&mouseX, &mouseY)

        ;if (DEBUG_MODE)
            ;LogMessage("Getting active monitor for mouse position: " mouseX ", " mouseY)

        ; Find which monitor contains the mouse cursor
        monitorCount := MonitorGetCount()

        loop monitorCount {
            MonitorGetWorkArea(A_Index, &mLeft, &mTop, &mRight, &mBottom)
            if (mouseX >= mLeft && mouseX <= mRight && mouseY >= mTop && mouseY <= mBottom)
                return A_Index
        }

        ; If no monitor was found (should not happen normally), default to primary
        return 1
    } catch Error as err {
        if (DEBUG_MODE)
            LogMessage("Error in GetActiveMonitor: " err.Message)
        return 1  ; Default to primary monitor on any error
    }
}

; Convert absolute window position to relative position (as percentage of monitor)
AbsoluteToRelativePosition(x, y, width, height, monitorIndex) {
    try {
        ; Get monitor dimensions
        MonitorGetWorkArea(monitorIndex, &mLeft, &mTop, &mRight, &mBottom)
        monitorWidth := mRight - mLeft
        monitorHeight := mBottom - mTop
        
        ; Calculate relative positions as percentages
        relX := (x - mLeft) / monitorWidth
        relY := (y - mTop) / monitorHeight
        relWidth := width / monitorWidth
        relHeight := height / monitorHeight
        
        return {
            relX: relX,
            relY: relY,
            relWidth: relWidth,
            relHeight: relHeight,
            monitorIndex: monitorIndex
        }
    } catch Error as err {
        if (DEBUG_MODE)
            LogMessage("Error in AbsoluteToRelativePosition: " err.Message)
        return {
            relX: 0,
            relY: 0,
            relWidth: 0.5,
            relHeight: 0.5,
            monitorIndex: monitorIndex
        }
    }
}

; Convert relative window position to absolute position based on current monitor dimensions
RelativeToAbsolutePosition(relX, relY, relWidth, relHeight, monitorIndex) {
    try {
        ; Get current monitor dimensions
        MonitorGetWorkArea(monitorIndex, &mLeft, &mTop, &mRight, &mBottom)
        monitorWidth := mRight - mLeft
        monitorHeight := mBottom - mTop
        
        ; Calculate absolute positions
        x := mLeft + (relX * monitorWidth)
        y := mTop + (relY * monitorHeight)
        width := relWidth * monitorWidth
        height := relHeight * monitorHeight
        
        return {
            x: Round(x),
            y: Round(y),
            width: Round(width),
            height: Round(height)
        }
    } catch Error as err {
        if (DEBUG_MODE)
            LogMessage("Error in RelativeToAbsolutePosition: " err.Message)
        return {
            x: mLeft,
            y: mTop,
            width: monitorWidth // 2,
            height: monitorHeight // 2
        }
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
            ; Verify the window still exists before trying to get its position
            try {
                if (!WinExist("ahk_id " hwnd)) {
                    if (DEBUG_MODE)
                        LogMessage("SaveWindowLayout: Window " hwnd " no longer exists")
                    return
                }
            } catch Error as existErr {
                if (DEBUG_MODE)
                    LogMessage("SaveWindowLayout: Error checking window existence: " existErr.Message)
                return
            }

            ; Get window position with better error handling
            try {
                WinGetPos(&x, &y, &width, &height, "ahk_id " hwnd) ; Captures current window coordinates and dimensions to save in layout
            } catch Error as posErr {
                if (DEBUG_MODE)
                    LogMessage("SaveWindowLayout: WinGetPos failed: " posErr.Message)
                return
            }

            ; Make sure the values are valid
            if (x = "" || y = "" || width = "" || height = "") {
                if (DEBUG_MODE)
                    LogMessage("SaveWindowLayout: Invalid position values for window " hwnd)
                return ; Skip saving if we get invalid position values
            }
            
            ; Get monitor index for this window
            monitorIndex := GetWindowMonitorIndex(hwnd)
            
            ; Convert to relative position
            relativePos := AbsoluteToRelativePosition(x, y, width, height, monitorIndex)

            ; Get window state with error handling
            try {
                isMinimized := WinGetMinMax("ahk_id " hwnd) = -1 ; Determines if window is minimized by checking if WinGetMinMax returns -1
                isMaximized := WinGetMinMax("ahk_id " hwnd) = 1 ; Determines if window is maximized by checking if WinGetMinMax returns 1
            } catch Error as stateErr {
                if (DEBUG_MODE)
                    LogMessage("SaveWindowLayout: Error getting window state: " stateErr.Message)
                isMinimized := false
                isMaximized := false
            }

            ; Store window layout with both absolute and relative positions
            WorkspaceLayouts[workspaceID][hwnd] := { ; Creates layout object for this window
                x: x,
                y: y,
                width: width,
                height: height,
                relX: relativePos.relX,
                relY: relativePos.relY,
                relWidth: relativePos.relWidth,
                relHeight: relativePos.relHeight,
                monitorIndex: monitorIndex,
                isMinimized: isMinimized,
                isMaximized: isMaximized
            }

            if (DEBUG_MODE)
                LogMessage("SaveWindowLayout: Saved layout for window " hwnd " in workspace " workspaceID)
        } catch Error as err {
            if (DEBUG_MODE)
                LogMessage("Error getting window information in SaveWindowLayout: " err.Message)
        }
    } catch Error as err {
        if (DEBUG_MODE)
            LogMessage("Error in SaveWindowLayout: " err.Message)
    }
}

RestoreWindowLayout(hwnd, workspaceID) { ; Restores a window to its saved position and state
    ; Check if window exists and is valid
    if !IsWindowValid(hwnd) {
        if (DEBUG_MODE)
            LogMessage("RESTORE FAILED: Window " hwnd " is not valid")
        return
    }

    title := WinGetTitle(hwnd)
    if (DEBUG_MODE)
        LogMessage("Attempting to restore window: " title " (" hwnd ")")

    try {
        ; First ensure the window is restored from minimized state
        winState := WinGetMinMax(hwnd) ; Gets window state (-1=minimized, 0=normal, 1=maximized)
        if (winState = -1) { ; If window is currently minimized, restore it first before applying layout
            if (DEBUG_MODE)
                LogMessage("Window is minimized, restoring first")

            try {
                WinRestore("ahk_id " hwnd) ; Restores window from minimized state so we can apply position/size
                Sleep(100) ; Allow time for the window to restore

                ; Verify the restore worked
                if (WinGetMinMax(hwnd) = -1) {
                    if (DEBUG_MODE)
                        LogMessage("Window restore failed, retrying...")
                    Sleep(200)
                    WinRestore("ahk_id " hwnd) ; Try again
                    Sleep(100)
                }
            } catch Error as err {
                if (DEBUG_MODE)
                    LogMessage("ERROR restoring window from minimized state: " err.Message)
            }
        }

        ; Check if we have saved layout data
        if (WorkspaceLayouts.Has(workspaceID)) {
            layouts := WorkspaceLayouts[workspaceID]

            if (layouts.Has(hwnd)) {
                layout := layouts[hwnd]
                
                ; Get current monitor index for this window
                currentMonitorIndex := GetWindowMonitorIndex(hwnd)
                
                ; If current monitor is different from saved monitor, we'll use relative positioning
                useRelativePositioning := currentMonitorIndex != layout.monitorIndex
                
                if (DEBUG_MODE) {
                    if (useRelativePositioning)
                        LogMessage("Monitor changed: Original=" layout.monitorIndex ", Current=" currentMonitorIndex ". Using relative positioning.")
                    else
                        LogMessage("Found saved layout for window: x=" layout.x ", y=" layout.y ", w=" layout.width ", h=" layout.height)
                }

                ; Apply saved layout
                if (layout.isMaximized) { ; If window was previously maximized
                    if (DEBUG_MODE)
                        LogMessage("Maximizing window")

                    try {
                        WinMaximize("ahk_id " hwnd) ; Restore window to maximized state

                        ; Verify maximize worked
                        if (WinGetMinMax(hwnd) != 1) {
                            if (DEBUG_MODE)
                                LogMessage("Window maximize failed, retrying...")
                            Sleep(200)
                            WinMaximize("ahk_id " hwnd) ; Try again
                        }
                    } catch Error as err {
                        if (DEBUG_MODE)
                            LogMessage("ERROR maximizing window: " err.Message)
                    }
                } else {
                    ; Move window to saved position
                    try {
                        if (DEBUG_MODE)
                            LogMessage("Moving window to saved position")

                        ; If monitor has changed, calculate new absolute position based on relative values
                        if (useRelativePositioning) {
                            ; Convert relative position to absolute for current monitor
                            absolutePos := RelativeToAbsolutePosition(
                                layout.relX, layout.relY, layout.relWidth, layout.relHeight, currentMonitorIndex)
                            
                            x := absolutePos.x
                            y := absolutePos.y
                            width := absolutePos.width
                            height := absolutePos.height
                            
                            if (DEBUG_MODE)
                                LogMessage("Using relative position: new x=" x ", y=" y ", w=" width ", h=" height)
                        } else {
                            ; Use original absolute position
                            x := layout.x
                            y := layout.y
                            width := layout.width
                            height := layout.height
                        }

                        ; Ensure coordinates are within screen bounds
                        monitorCount := MonitorGetCount()
                        coordsValid := false

                        ; Check if coordinates are within any monitor's bounds
                        loop monitorCount {
                            MonitorGetWorkArea(A_Index, &mLeft, &mTop, &mRight, &mBottom)
                            if (x >= mLeft - width && x <= mRight &&
                                y >= mTop - height && y <= mBottom) {
                                coordsValid := true
                                break
                            }
                        }

                        if (coordsValid) {
                            WinMove(x, y, width, height, "ahk_id " hwnd)
                        } else {
                            if (DEBUG_MODE)
                                LogMessage("Window position out of bounds, using default position")
                            WinActivate("ahk_id " hwnd)
                        }
                    } catch Error as err {
                        if (DEBUG_MODE)
                            LogMessage("ERROR moving window: " err.Message)
                    }
                }
            } else {
                if (DEBUG_MODE)
                    LogMessage("No saved layout found for this window, using default position")
                WinActivate("ahk_id " hwnd) ; At least activate the window
            }
        } else {
            if (DEBUG_MODE)
                LogMessage("No layouts saved for workspace " workspaceID)
        }

        ; Ensure window is visible and brought to front
        try {
            WinActivate("ahk_id " hwnd) ; Brings window to foreground and gives it keyboard focus
        } catch Error as err {
            if (DEBUG_MODE)
                LogMessage("ERROR activating window: " err.Message)
        }
    } catch Error as err {
        if (DEBUG_MODE)
            LogMessage("CRITICAL ERROR in RestoreWindowLayout: " err.Message)
    }
}

; ----- Utility Functions -----

; Function to log messages either to file or debug output
LogMessage(message) {
    global DEBUG_MODE, LOG_TO_FILE, LOG_FILE, SHOW_WINDOW_EVENT_TOOLTIPS, SHOW_TRAY_NOTIFICATIONS

    ; Only log if debugging is enabled
    if (!DEBUG_MODE)
        return

    ; Add timestamp to the message
    timestamp := FormatTime(, "yyyy-MM-dd HH:mm:ss")
    logMessage := timestamp . " - " . message

    ; Either log to file or debug output
    if (LOG_TO_FILE) {
        try {
            FileAppend(logMessage . "`n", LOG_FILE)
        } catch Error as err {
            ; Fall back to debug output if file logging fails
            OutputDebug("ERROR logging to file: " err.Message)
            OutputDebug(logMessage)
        }
    } else {
        ; Send to debug output
        OutputDebug(logMessage)

        ; Check for window events (move, resize, create, close)
        isWindowEvent := (InStr(message, "WINDOW MOVED:") || InStr(message, "WINDOW RESIZED:") ||
                         InStr(message, "WINDOW CLOSED:") || InStr(message, "NEW WINDOW CREATED:"))

        ; Show tooltip for window events if enabled
        if (SHOW_WINDOW_EVENT_TOOLTIPS && isWindowEvent) {
            ; Display a temporary tooltip at cursor position
            MouseGetPos(&xpos, &ypos)
            ToolTip(message, xpos+10, ypos+10)

            ; Auto-hide tooltip after a short delay
            SetTimer(() => ToolTip(), -2000) ; Clear tooltip after 2 seconds
        }

        ; Show tray notifications for window events if enabled
        if (SHOW_TRAY_NOTIFICATIONS && isWindowEvent) {
            ; Extract just the event part for the notification
            eventTitle := ""
            if (InStr(message, "WINDOW MOVED:"))
                eventTitle := "Window Moved"
            else if (InStr(message, "WINDOW RESIZED:"))
                eventTitle := "Window Resized"
            else if (InStr(message, "WINDOW CLOSED:"))
                eventTitle := "Window Closed"
            else if (InStr(message, "NEW WINDOW CREATED:"))
                eventTitle := "New Window"

            ; Show notification
            TrayTip(eventTitle, message)

            ; Auto-hide the tray notification after a short delay
            SetTimer(() => TrayTip(), -3000) ; Clear tray notification after 3 seconds
        }
    }
}

; ----- Event Handlers -----

; Helper function for delayed window checking
SendWindowToWorkspace(targetWorkspaceID) { ; Sends active window to specified workspace
    ; Reference global variables
    global SWITCH_IN_PROGRESS, DEBUG_MODE, MAX_WORKSPACES, MonitorWorkspaces, WindowWorkspaces, WorkspaceLayouts

    ; Early exit conditions
    if (targetWorkspaceID < 1 || targetWorkspaceID > MAX_WORKSPACES)
        return

    ; Check if another switch operation is already in progress
    if (SWITCH_IN_PROGRESS) {
        if (DEBUG_MODE)
            LogMessage("Another workspace operation in progress, ignoring send window request")
        return
    }

    ; Set the flag to indicate operation is in progress
    SWITCH_IN_PROGRESS := True

    try {
        ; Log the start of window movement
        if (DEBUG_MODE)
            LogMessage("------------- SEND WINDOW TO WORKSPACE START -------------")

        ; Get active window
        activeHwnd := WinExist("A")
        if (!activeHwnd || !IsWindowValid(activeHwnd)) {
            if (DEBUG_MODE)
                LogMessage("No valid active window to move")
            SWITCH_IN_PROGRESS := False
            return
        }

        ; Get window title for logging
        title := WinGetTitle(activeHwnd)
        if (DEBUG_MODE)
            LogMessage("Sending window '" title "' to workspace " targetWorkspaceID)

        ; Update window workspace assignment
        prevWorkspaceID := WindowWorkspaces.Has(activeHwnd) ? WindowWorkspaces[activeHwnd] : 0
        WindowWorkspaces[activeHwnd] := targetWorkspaceID

        ; Check if target workspace is visible on any monitor
        targetMonitor := 0
        for monIndex, workspaceID in MonitorWorkspaces {
            if (workspaceID = targetWorkspaceID) {
                targetMonitor := monIndex
                break
            }
        }

        if (targetMonitor > 0) {
            ; Target workspace is visible - move window to that monitor
            if (DEBUG_MODE)
                LogMessage("Target workspace " targetWorkspaceID " is visible on monitor " targetMonitor)

            ; Get target monitor dimensions
            MonitorGetWorkArea(targetMonitor, &mLeft, &mTop, &mRight, &mBottom)
            if (DEBUG_MODE)
                LogMessage(mTop " " mLeft " " mBottom " " mRight)

            ; Get current window position and size
            try {
                WinGetPos(&x, &y, &width, &height, "ahk_id " activeHwnd)

                ; Check for valid dimensions
                if (x = "" || y = "" || width = "" || height = "") {
                    if (DEBUG_MODE)
                        LogMessage("SendWindowToWorkspace: Invalid position values for window")

                    ; Use default sizes if we couldn't get valid values
                    width := width ? width : 800
                    height := height ? height : 600
                    x := x ? x : 0
                    y := y ? y : 0
                }
            } catch Error as err {
                if (DEBUG_MODE)
                    LogMessage("SendWindowToWorkspace: Error getting window position: " err.Message)

                ; Use default values on error
                width := 800
                height := 600
                x := 0
                y := 0
            }

            ; Get the source monitor for the window
            sourceMonitorIndex := GetWindowMonitorIndex(activeHwnd)
            
            ; Calculate position based on whether we've seen this window before
            if (WindowWorkspaces.Has(activeHwnd) && WorkspaceLayouts.Has(WindowWorkspaces[activeHwnd]) && 
                WorkspaceLayouts[WindowWorkspaces[activeHwnd]].Has(activeHwnd)) {
                
                ; Get existing layout data with relative positioning
                existingWorkspaceID := WindowWorkspaces[activeHwnd]
                existingLayout := WorkspaceLayouts[existingWorkspaceID][activeHwnd]
                
                if (DEBUG_MODE)
                    LogMessage("Found existing layout data for window, using relative positioning")
                
                ; Use relative positioning to calculate new position on target monitor
                absolutePos := RelativeToAbsolutePosition(
                    existingLayout.relX, existingLayout.relY, existingLayout.relWidth, existingLayout.relHeight, targetMonitor)
                
                newX := absolutePos.x
                newY := absolutePos.y
                newWidth := absolutePos.width
                newHeight := absolutePos.height
                if (DEBUG_MODE)
                    LogMessage(absolutePos.x " " absolutePos.y " " absolutePos.width " " absolutePos.height)
                if (DEBUG_MODE)
                    LogMessage("Using relative position: new x=" newX ", y=" newY ", w=" newWidth ", h=" newHeight)
            } else {
                ; No previous layout data - center window on monitor
                if (DEBUG_MODE)
                    LogMessage("No existing layout data, centering window on monitor")
                
                newX := mLeft + (mRight - mLeft - width) / 2
                newY := mTop + (mBottom - mTop - height) / 2
                newWidth := width
                newHeight := height
            }

            ; Move the window to target monitor
            try {
                WinMove(newX, newY, newWidth, newHeight, "ahk_id " activeHwnd)
            } catch Error as err {
                if (DEBUG_MODE)
                    LogMessage("SendWindowToWorkspace: Error moving window: " err.Message)
            }

            ; Save the new layout
            SaveWindowLayout(activeHwnd, targetWorkspaceID)

            ; Activate the window to bring it to front
            WinActivate("ahk_id " activeHwnd)

            if (DEBUG_MODE)
                LogMessage("Moved window to monitor " targetMonitor " with workspace " targetWorkspaceID)
        } else {
            ; Target workspace not visible on any monitor - minimize the window
            if (DEBUG_MODE)
                LogMessage("Target workspace " targetWorkspaceID " is not visible - minimizing window")

            ; Minimize the window
            WinMinimize("ahk_id " activeHwnd)

            ; Save window layout for future restoration
            SaveWindowLayout(activeHwnd, targetWorkspaceID)
        }

                if (DEBUG_MODE)
            LogMessage("ERROR in SendWindowToWorkspace: " err.Message)
    } finally {
        ; Always clear the switch in progress flag
        SWITCH_IN_PROGRESS := False
    }
}

SwitchToWorkspace(requestedID) { ; Changes active workspace on current monitor
    ; Reference global variables
    global SWITCH_IN_PROGRESS, DEBUG_MODE, MAX_WORKSPACES, MonitorWorkspaces, WindowWorkspaces, WorkspaceLayouts

    ; Early exit conditions
    if (requestedID < 1 || requestedID > MAX_WORKSPACES)
        return

    ; Check if another switch operation is already in progress
    if (SWITCH_IN_PROGRESS) {
        if (DEBUG_MODE)
            LogMessage("Another workspace switch already in progress, ignoring request")
        return
    }

    ; Set the flag to indicate switch is in progress
    SWITCH_IN_PROGRESS := True

    try {
        ; Log the start of workspace switching
        LogMessage("------------- WORKSPACE SWITCH START -------------")
        LogMessage("Switching to workspace: " requestedID)

        ; Log workspace window contents BEFORE the switch
        if (DEBUG_MODE)
            LogWorkspaceWindowContents("BEFORE SWITCH:")

        ; Get active monitor
        activeMonitor := GetActiveMonitor() ; Gets the monitor index that contains the currently active (focused) window
        LogMessage("Active monitor: " activeMonitor)

        ; Get current workspace ID for active monitor
        currentWorkspaceID := MonitorWorkspaces.Has(activeMonitor) ? MonitorWorkspaces[activeMonitor] : 1 ; Gets current workspace ID for active monitor, defaults to 1 if not found
        if (DEBUG_MODE)
            LogMessage("Current workspace on active monitor: " currentWorkspaceID)

        ; If already on requested workspace, do nothing
        if (currentWorkspaceID = requestedID) {
            if (DEBUG_MODE)
                LogMessage("Already on requested workspace. No action needed.")
            SWITCH_IN_PROGRESS := False ; Clear flag before early return
            return
        }

        ; Check if the requested workspace is already on another monitor - direct swap approach
        otherMonitor := 0
        for monIndex, workspaceID in MonitorWorkspaces {
            if (monIndex != activeMonitor && workspaceID = requestedID) {
                otherMonitor := monIndex
                if (DEBUG_MODE)
                    LogMessage("Found requested workspace on monitor: " otherMonitor)
                break
            }
        }

        if (otherMonitor > 0) {
            ; === PERFORMING WORKSPACE EXCHANGE BETWEEN MONITORS ===
            if (DEBUG_MODE)
                LogMessage("Performing workspace exchange between monitors " activeMonitor " and " otherMonitor)

            ; Get monitor dimensions
            MonitorGetWorkArea(activeMonitor, &aLeft, &aTop, &aRight, &aBottom)
            MonitorGetWorkArea(otherMonitor, &oLeft, &oTop, &oRight, &oBottom)
            
            ; Calculate offset between monitors (to maintain relative positions)
            offsetX := aLeft - oLeft
            offsetY := aTop - oTop
            
            ; Get all open windows
            windows := WinGetList()
            if (DEBUG_MODE)
                LogMessage("Found " windows.Length " total windows")

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
                LogMessage("Found " activeMonitorWindows.Length " windows on active monitor and " 
                    otherMonitorWindows.Length " windows on other monitor")
            }
            
            ; Step 1: Swap workspace IDs between monitors
            if (DEBUG_MODE)
                LogMessage("Swapping workspace IDs: " currentWorkspaceID " and " requestedID)
            MonitorWorkspaces[otherMonitor] := currentWorkspaceID
            MonitorWorkspaces[activeMonitor] := requestedID

            ; Step 3: Move windows from other monitor to active monitor
            for index, hwnd in otherMonitorWindows {
                try {
                    ; Get window position and state
                    WinGetPos(&x, &y, &width, &height, hwnd)
                    isMaximized := WinGetMinMax(hwnd) = 1
                    
                    if (DEBUG_MODE) {
                        title := WinGetTitle(hwnd)
                        LogMessage("Moving window from other to active monitor: " title)
                    }

                    ; Move window, preserving layout
                    if (isMaximized) {
                        ; First restore to normal, move, then maximize again
                        if (WinGetMinMax(hwnd) = 1)
                            WinRestore("ahk_id " hwnd)

                        ; Move to new position
                        WinMove(x + offsetX, y + offsetY, width, height, "ahk_id " hwnd)

                        ; Verify the window was moved to the correct monitor
                        Sleep(30) ; Allow time for the move operation to complete
                        currMonitor := GetWindowMonitor(hwnd)

                        if (currMonitor != activeMonitor) {
                            ; Recalculate position in active monitor
                            MonitorGetWorkArea(activeMonitor, &mLeft, &mTop, &mRight, &mBottom)
                            centerX := mLeft + (mRight - mLeft - width) / 2
                            centerY := mTop + (mBottom - mTop - height) / 2

                            ; Force window to active monitor
                            WinMove(centerX, centerY, width, height, "ahk_id " hwnd)

                            if (DEBUG_MODE)
                                LogMessage("CORRECTED position to ensure window is on active monitor: " title)
                        }

                        ; Maximize again
                        WinMaximize("ahk_id " hwnd)
                    } else {
                        ; For non-maximized windows, just move them
                        WinMove(x + offsetX, y + offsetY, width, height, "ahk_id " hwnd)

                        ; Verify the window was moved to the correct monitor
                        Sleep(30) ; Allow time for the move operation to complete
                        currMonitor := GetWindowMonitor(hwnd)

                        if (currMonitor != activeMonitor) {
                            ; Recalculate position in active monitor
                            MonitorGetWorkArea(activeMonitor, &mLeft, &mTop, &mRight, &mBottom)
                            centerX := mLeft + (mRight - mLeft - width) / 2
                            centerY := mTop + (mBottom - mTop - height) / 2

                            ; Force window to active monitor
                            WinMove(centerX, centerY, width, height, "ahk_id " hwnd)

                            if (DEBUG_MODE)
                                LogMessage("CORRECTED position to ensure window is on active monitor: " title)
                        }
                    }
                    
                    Sleep(30) ; Short delay to prevent overwhelming the system
                } catch Error as err {
                    if (DEBUG_MODE)
                        LogMessage("ERROR moving window: " err.Message)
                }
            }
            
            if (DEBUG_MODE)
                LogMessage("Moved windows between monitors while preserving layout")
        }
        else {
            ; === STANDARD WORKSPACE SWITCH (NO EXCHANGE) ===
            if (DEBUG_MODE)
                LogMessage("Standard workspace switch - no exchange needed")

            ; ====== STEP 1: Identify and minimize windows that don't belong to requested workspace ======
            ; Get all open windows
            windows := WinGetList() ; Gets a list of all open windows
            if (DEBUG_MODE)
                LogMessage("Found " windows.Length " total windows")

            ; Process each window
            for index, hwnd in windows {
                ; Skip invalid windows
                if (!IsWindowValid(hwnd))
                    continue

                ; Get window info for checking workspace assignment
                title := WinGetTitle(hwnd)
                workspaceID := WindowWorkspaces.Has(hwnd) ? WindowWorkspaces[hwnd] : 0
                windowMonitor := GetWindowMonitor(hwnd)

                ; Only minimize windows on the active monitor that don't belong to requested workspace
                if (windowMonitor = activeMonitor && workspaceID != requestedID) {
                    ; This window is on the active monitor but belongs to a different workspace
                    if (DEBUG_MODE)
                        LogMessage("MINIMIZING window (workspace " workspaceID ") on active monitor: " title)

                    ; Force the window to minimize
                    try {
                        WinMinimize("ahk_id " hwnd)
                        Sleep(50) ; Delay to allow minimize operation to complete
                    } catch Error as err {
                        if (DEBUG_MODE)
                            LogMessage("ERROR minimizing window: " err.Message)
                    }
                }
            }

            ; ====== STEP 2: Change workspace ID for active monitor ======
            ; Update the workspace ID for the active monitor
            MonitorWorkspaces[activeMonitor] := requestedID
            if (DEBUG_MODE)
                LogMessage("Changed active monitor workspace to: " requestedID)

            if (DEBUG_MODE)
                LogMessage("Restored " restoreCount " windows for workspace " requestedID)
        }
    }
    catch Error as err {
        ; Log the error
        if (DEBUG_MODE)
            LogMessage("ERROR during workspace switch: " err.Message)
    }
    finally {
        ; Always update overlays to ensure they reflect the current workspace state,
        ; even if there was an error or early return in the switch logic
}
; Clean up stale window references to prevent memory leaks
CleanupWindowReferences() {
    ; Reference global variables
    global DEBUG_MODE, SCRIPT_EXITING, WindowWorkspaces, WorkspaceLayouts

    ; Skip if script is exiting
    if (SCRIPT_EXITING) {
        if (DEBUG_MODE)
            LogMessage("Script is exiting, ignoring cleanup timer")
        return
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
    for workspaceID, layouts in WorkspaceLayouts {
        layoutStaleCount := 0
        for hwnd, layout in layouts {
            try {
                if !WinExist(hwnd) {
                    layouts.Delete(hwnd)
                    layoutStaleCount++
                }
            } catch Error as err {
                ; If there's an error, remove this reference anyway
                layouts.Delete(hwnd)
                layoutStaleCount++
            }
        }
        layoutTotalStaleCount += layoutStaleCount
    }

    if ((workspaceStaleCount > 0 || layoutTotalStaleCount > 0) && DEBUG_MODE) {
        LogMessage("Cleaned up " workspaceStaleCount " workspace entries and " layoutTotalStaleCount " layout entries")
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
            LogMessage("Info: Skipping lastWindowState cleanup - not initialized yet")
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

    ; If any windows were removed and the count is significant, update the overlay
    if (workspaceStaleCount > 0) {
    
    if ((staleCount > 0 || workspaceStaleCount > 0 || layoutTotalStaleCount > 0) && DEBUG_MODE) {
        LogMessage("Cleaned up " staleCount " window state entries, " workspaceStaleCount " workspace entries, and " layoutTotalStaleCount " layout entries")
    }
}

        } else {
            try {
                ; Verify the window still exists again before updating
                try {
                    if (!WinExist("ahk_id " hwnd)) {
                        if (DEBUG_MODE)
                            LogMessage("AssignNewWindow: Window disappeared during processing")
                        return
                    }
                } catch Error as existErr {
                    if (DEBUG_MODE)
                        LogMessage("AssignNewWindow: Error rechecking window: " existErr.Message)
                    return
                }

                ; Window already has workspace assignment, but may need updating if it moved monitors
                currentWorkspaceID := WindowWorkspaces[hwnd]
                
                ; IMPORTANT: Always save the layout, even for existing windows
                ; This ensures we always have layout data for relative positioning
                SaveWindowLayout(hwnd, currentWorkspaceID)
                if (DEBUG_MODE)
                    LogMessage("Updated layout for existing window in workspace " currentWorkspaceID)

                ; If window's current workspace doesn't match its monitor's workspace, update it
                if (currentWorkspaceID != workspaceID) {
                    WindowWorkspaces[hwnd] := workspaceID
                    SaveWindowLayout(hwnd, workspaceID)
                }
            } catch Error as err {
                if (DEBUG_MODE)
                    LogMessage("Error updating window workspace in delayed check: " err.Message)
            }
        }
    } else {
        ; Default to unassigned if monitor has no workspace
        try {
            ; Verify window still exists
            if (WinExist("ahk_id " hwnd)) {
                WindowWorkspaces[hwnd] := 0
        } catch Error as err {
            if (DEBUG_MODE)
                LogMessage("Error assigning window to unassigned workspace: " err.Message)
        }
    }
}

; ----- Overlay Functions -----

InitializeOverlays() { ; Creates and displays workspace number indicators and monitor border on all monitors
    ; Reference global variables
    global MonitorWorkspaces, WorkspaceOverlays, BORDER_VISIBLE

    ; Create an overlay for each monitor
    monitorCount := MonitorGetCount() ; Gets the total number of physical monitors to determine which monitor contains the window

    loop monitorCount {
        monitorIndex := A_Index

InitializeMonitorBorders() { ; Creates border overlays for all monitors
    ; Reference global variables
    global BorderOverlay, DEBUG_MODE, BORDER_COLOR, BORDER_THICKNESS

    ; Clear any existing border overlays
    for _, overlay in BorderOverlay {
        try {
            overlay.Destroy()
        } catch Error as err {
            if (DEBUG_MODE)
                LogMessage("Error destroying border overlay: " err.Message)
        }
    }
    BorderOverlay := Map()

    ; Create new border overlays for each monitor
    monitorCount := MonitorGetCount()

    loop monitorCount {
        monitorIndex := A_Index

        ; Get monitor dimensions
        MonitorGetWorkArea(monitorIndex, &mLeft, &mTop, &mRight, &mBottom)

        ; Create the border components (4 thin gui elements for each edge)
        CreateMonitorBorder(monitorIndex, mLeft, mTop, mRight, mBottom)

        if (DEBUG_MODE)
            LogMessage("Created border overlay for monitor " monitorIndex)
    }
}

CreateMonitorBorder(monitorIndex, mLeft, mTop, mRight, mBottom) { ; Creates border for a specific monitor
    ; Reference global variables
    global BorderOverlay, BORDER_COLOR, BORDER_THICKNESS, BORDER_VISIBLE

    ; Create a map to store the 4 edges of this monitor's border
    BorderOverlay[monitorIndex] := Map()

    ; Calculate dimensions
    width := mRight - mLeft
    height := mBottom - mTop

    ; Create top edge
    topEdge := Gui("+AlwaysOnTop -Caption +ToolWindow +Owner")
    topEdge.BackColor := BORDER_COLOR
    topEdge.Show("x" mLeft " y" mTop " w" width " h" BORDER_THICKNESS " NoActivate")
    WinSetTransparent(200, "ahk_id " topEdge.Hwnd)

    ; Create bottom edge
    bottomEdge := Gui("+AlwaysOnTop -Caption +ToolWindow +Owner")
    bottomEdge.BackColor := BORDER_COLOR
    bottomEdge.Show("x" mLeft " y" (mBottom - BORDER_THICKNESS) " w" width " h" BORDER_THICKNESS " NoActivate")
    WinSetTransparent(200, "ahk_id " bottomEdge.Hwnd)

    ; Create left edge
    leftEdge := Gui("+AlwaysOnTop -Caption +ToolWindow +Owner")
    leftEdge.BackColor := BORDER_COLOR
    leftEdge.Show("x" mLeft " y" mTop " w" BORDER_THICKNESS " h" height " NoActivate")
    WinSetTransparent(200, "ahk_id " leftEdge.Hwnd)

    ; Create right edge
    rightEdge := Gui("+AlwaysOnTop -Caption +ToolWindow +Owner")
    rightEdge.BackColor := BORDER_COLOR
    rightEdge.Show("x" (mRight - BORDER_THICKNESS) " y" mTop " w" BORDER_THICKNESS " h" height " NoActivate")
    WinSetTransparent(200, "ahk_id " rightEdge.Hwnd)

    ; Store the edges
    BorderOverlay[monitorIndex]["top"] := topEdge
    BorderOverlay[monitorIndex]["bottom"] := bottomEdge
    BorderOverlay[monitorIndex]["left"] := leftEdge
    BorderOverlay[monitorIndex]["right"] := rightEdge

    ; Hide all borders initially (we'll show only the active monitor border)
    if (BORDER_VISIBLE) {
        HideMonitorBorder(monitorIndex)
    }
}

HideAllOverlays() { ; Hides all workspace indicators
    ; Reference global variables
    global WorkspaceOverlays

    ; Hide all overlays
    for monitorIndex, overlay in WorkspaceOverlays {
        overlay.Hide() ; Hides the overlay
    }
}

ToggleOverlays() { ; Toggles visibility of workspace indicators
    ; Reference global variables
    global OVERLAY_TIMEOUT

    ; Toggle overlay visibility
    static isVisible := true

    if (isVisible) {
        HideAllOverlays()
    } else {
    }

    isVisible := !isVisible
}

ShowMonitorBorder(monitorIndex) { ; Shows the border for a specific monitor
    ; Reference global variables
    global BorderOverlay, DEBUG_MODE

    try {
        if (BorderOverlay.Has(monitorIndex)) {
            edges := BorderOverlay[monitorIndex]

            for edge, gui in edges {
                gui.Show("NoActivate")
            }

            ;if (DEBUG_MODE)
                ;LogMessage("Showed border for monitor " monitorIndex)
        }
    } catch Error as err {
        if (DEBUG_MODE)
            LogMessage("Error showing monitor border: " err.Message)
    }
}

HideMonitorBorder(monitorIndex) { ; Hides the border for a specific monitor
    ; Reference global variables
    global BorderOverlay, DEBUG_MODE

    try {
        if (BorderOverlay.Has(monitorIndex)) {
            edges := BorderOverlay[monitorIndex]

            for edge, gui in edges {
                gui.Hide()
            }

            if (DEBUG_MODE)
                LogMessage("Hid border for monitor " monitorIndex)
        }
    } catch Error as err {
        if (DEBUG_MODE)
            LogMessage("Error hiding monitor border: " err.Message)
    }
}

UpdateActiveMonitorBorder() { ; Updates the active monitor border based on current mouse position
    ; Reference global variables
    global LAST_ACTIVE_MONITOR, DEBUG_MODE, BORDER_VISIBLE

    ; If borders are toggled off, do nothing
    if (!BORDER_VISIBLE)
        return

    ; Get current active monitor based on mouse position
    currentMonitor := GetActiveMonitor()

    ; Check if we need to update the border
    if (currentMonitor != LAST_ACTIVE_MONITOR || LAST_ACTIVE_MONITOR == 0) {
        if (DEBUG_MODE)
            LogMessage("Active monitor changed from " LAST_ACTIVE_MONITOR " to " currentMonitor)

        ; Hide border on previous monitor
        if (LAST_ACTIVE_MONITOR > 0)
            HideMonitorBorder(LAST_ACTIVE_MONITOR)

        ; Show border on new active monitor
        ShowMonitorBorder(currentMonitor)

        ; Update last active monitor
        LAST_ACTIVE_MONITOR := currentMonitor
    } else {
        ; Even if the monitor hasn't changed, ensure the border is visible
        ShowMonitorBorder(currentMonitor)
    }
}

ToggleMonitorBorders() { ; Toggles visibility of all monitor borders
    ; Reference global variables
    global BorderOverlay, BORDER_VISIBLE, DEBUG_MODE, LAST_ACTIVE_MONITOR

    ; Toggle the visibility state
    BORDER_VISIBLE := !BORDER_VISIBLE

    if (DEBUG_MODE)
        LogMessage("Monitor borders toggled: " (BORDER_VISIBLE ? "ON" : "OFF"))

    if (BORDER_VISIBLE) {
        ; Get the current active monitor
        currentMonitor := GetActiveMonitor()

        ; Force show active monitor border regardless of whether it has changed
        ShowMonitorBorder(currentMonitor)

        ; Update last active monitor
        LAST_ACTIVE_MONITOR := currentMonitor

        if (DEBUG_MODE)
            LogMessage("Showing border for monitor " currentMonitor)
    } else {
        ; Hide all borders
        for monitorIndex in BorderOverlay {
            HideMonitorBorder(monitorIndex)
        }
    }
}

; ====== Configuration ======
MAX_WORKSPACES := 9  ; Maximum number of workspaces (1-9)
MAX_MONITORS := 9    ; Maximum number of monitors (adjust as needed)

; ====== Additional Window Handling Functions ======
; Functions from window_monitor_fix.ahk integrated directly

HandleNewWindow(hwnd) {
    ; Validate the hwnd parameter
    try {
        if (!hwnd || hwnd = 0) {
            if (DEBUG_MODE)
                LogMessage("HandleNewWindow: Invalid window handle (null or zero)")
            return
        }
    } catch Error as err {
        if (DEBUG_MODE)
            LogMessage("HandleNewWindow: Error validating handle parameter: " err.Message)
        return
    }
    
    ; Verify window still exists
    try {
        if (!WinExist("ahk_id " hwnd)) {
            if (DEBUG_MODE)
                LogMessage("HandleNewWindow: Window " hwnd " no longer exists")
            return
        }
    } catch Error as existErr {
        if (DEBUG_MODE)
            LogMessage("HandleNewWindow: Error checking window existence: " existErr.Message)
        return
    }
    
    ; Get monitor index safely
    try {
        monitorIndex := GetWindowMonitorIndex(hwnd)
        if (DEBUG_MODE)
            LogMessage("HandleNewWindow: Window is on monitor " monitorIndex)
    } catch Error as err {
        if (DEBUG_MODE)
            LogMessage("HandleNewWindow: Error getting monitor index: " err.Message)
        monitorIndex := 1 ; Default to primary
    }
    
    ; Rest of handling logic...
}

WindowCreationCheck(hwnd) {
    ; Validate the hwnd parameter
    try {
        if (!hwnd || hwnd = 0) {
            if (DEBUG_MODE)
                LogMessage("WindowCreationCheck: Invalid window handle (null or zero)")
            return
        }
    } catch Error as err {
        if (DEBUG_MODE)
            LogMessage("WindowCreationCheck: Error validating handle parameter: " err.Message)
        return
    }
    
    ; Verify window still exists
    try {
        if (!WinExist("ahk_id " hwnd)) {
            if (DEBUG_MODE)
                LogMessage("WindowCreationCheck: Window " hwnd " no longer exists")
            return
        }
    } catch Error as existErr {
        if (DEBUG_MODE)
            LogMessage("WindowCreationCheck: Error checking window existence: " existErr.Message)
        return
    }
    
    ; Call HandleNewWindow safely
    try {
        HandleNewWindow(hwnd)
    } catch Error as err {
        if (DEBUG_MODE)
            LogMessage("WindowCreationCheck: Error in HandleNewWindow: " err.Message)
    }
}

; ====== Global Variables ======
; ===== DEBUG SETTINGS =====
; Set this to True to enable detailed logging for troubleshooting
global DEBUG_MODE := True  ; Change to True to enable debugging
global LOG_TO_FILE := False  ; Set to True to log to file instead of Debug output
global LOG_FILE := A_ScriptDir "\cerberus.log"  ; Path to log file
global SHOW_WINDOW_EVENT_TOOLTIPS := False  ; Set to False to hide tooltips for window events
global SHOW_TRAY_NOTIFICATIONS := False  ; Set to True to show tray notifications for window events

; ===== STATE FLAGS =====
; Flag to prevent recursive workspace switching and handler execution
global SWITCH_IN_PROGRESS := False
; Flag to indicate script is exiting - handlers should check this and return immediately
; Global variable to prevent event handlers from running during script termination
global SCRIPT_EXITING := False

; Monitor workspace assignments (monitor index → workspace ID)
global MonitorWorkspaces := Map()
; Window workspace assignments (window ID → workspace ID)
global WindowWorkspaces := Map()
; Window positions per workspace (workspace ID → Map of window layouts)
global WorkspaceLayouts := Map()
; Workspace overlay GUI handles (monitor index → GUI handle)
global WorkspaceOverlays := Map()
; Workspace window list overlay
; Active monitor border overlay
global BorderOverlay := Map()
global BORDER_VISIBLE := true
; Overlay display settings
global OVERLAY_SIZE := 60 ; Size of overlay in pixels (increased for better visibility)
global OVERLAY_MARGIN := 20 ; Margin from screen edge
global OVERLAY_TIMEOUT := 0 ; Time in ms before overlay fades (0 for persistent display)
global OVERLAY_OPACITY := 220 ; 0-255 (0 = transparent, 255 = opaque)
global OVERLAY_POSITION := "BottomRight" ; TopLeft, TopRight, BottomLeft, BottomRight
global BORDER_COLOR := "33FFFF" ; Cyan color for active monitor border
global BORDER_THICKNESS := 3 ; Thickness of the monitor border in pixels
global LAST_ACTIVE_MONITOR := 0 ; Tracks the last known active monitor

; ====== Exit Handler ======
; Register exit handler to clean up resources on script termination
OnExit(ExitHandler)

ExitHandler(ExitReason, ExitCode) {

    ; Set flag to prevent handlers from running during exit
    SCRIPT_EXITING := True

    if (DEBUG_MODE)
        LogMessage("===== SCRIPT EXITING (" ExitReason ") =====")

    ; Stop all timers
    SetTimer(CleanupWindowReferences, 0)
    SetTimer(CheckMouseMovement, 0)
        
    ; Clean up workspace overlays
    try {
        for monitorIndex, overlay in WorkspaceOverlays {
            if (overlay && overlay.HasProp("Hwnd") && WinExist("ahk_id " overlay.Hwnd)) {
                overlay.Destroy()
            }
        }
        WorkspaceOverlays := Map()
    } catch Error as err {
        if (DEBUG_MODE)
            LogMessage("Error cleaning up workspace overlays: " err.Message)
    }
    
    ; Clean up window list overlay
    try {
        }
    } catch Error as err {
        if (DEBUG_MODE)
            LogMessage("Error cleaning up window list overlay: " err.Message)
    }
    
    ; Remove message hooks
    
    ; Clean up any open tool tips
    ToolTip()
    
    ; Clean up static maps in handlers to prevent memory leaks
    try {
        ; Clean global maps to release references to window handles
        WindowWorkspaces := Map()
        WorkspaceLayouts := Map()
        
        ; Clear any remaining handler static variables if possible
        }
    } catch Error as err {
        if (DEBUG_MODE)
            LogMessage("Error cleaning up handler static variables: " err.Message)
    }
    
    ; Log successful exit
    if (DEBUG_MODE)
        LogMessage("Successfully cleaned up resources, script terminating cleanly")
    try {
        ; Hide all workspace overlays
        for monitorIndex, overlay in WorkspaceOverlays {
            try overlay.Destroy()
            catch Error as err {
                if (DEBUG_MODE)
                    LogMessage("Error destroying workspace overlay: " err.Message)
            }
        }

        ; Hide workspace window list if visible
            catch Error as err {
                if (DEBUG_MODE)
                    LogMessage("Error destroying window list overlay: " err.Message)
            }
        }

        ; Clean up monitor borders
        for monitorIndex, edges in BorderOverlay {
            for edge, gui in edges {
                try gui.Destroy()
                catch Error as err {
                    if (DEBUG_MODE)
                        LogMessage("Error destroying border: " err.Message)
                }
            }
        }
    } catch Error as err {
        if (DEBUG_MODE)
            LogMessage("Error in cleanup: " err.Message)
    }

    if (DEBUG_MODE)
        LogMessage("===== CLEANUP COMPLETE =====")
}

; ====== Core Initialization ======
; Set up initial script environment
CoordMode("Mouse", "Screen") ; Sets mouse coordinates to be relative to entire screen instead of active window
SetWinDelay(50) ; Sets a 50ms delay between window operations to improve reliability of window manipulations
DetectHiddenWindows(False) ; Disables detection of hidden windows so they won't be tracked by the script

; Initialize core workspace functionality first (before showing any UI)
InitializeWorkspaces() ; Call to initialize workspaces when script starts - sets up monitor-workspace mapping and assigns windows

; ====== Show Instructions Dialog ======
; Start by ensuring our tray icon is correct
TraySetIcon(A_ScriptDir "\cerberus.ico")

; Create a simple dialog that looks identical to MsgBox but with our icon in the taskbar
dlg := Gui("+AlwaysOnTop +OwnDialogs")
dlg.Opt("+SysMenu")  ; Adds an icon to the title bar
dlg.Title := "Cerberus"

; Add the information text with exact same formatting as the MsgBox
dlg.SetFont("s9", "Segoe UI")
dlg.Add("Text", "w382", "Cerberus Instructions:")
dlg.Add("Text", "w382 y+0", "Press Ctrl+1 through Ctrl+9 to switch workspaces.")
dlg.Add("Text", "w382 y+0", "Press Ctrl+Shift+[Number] to send active window to specific workspace.")
dlg.Add("Text", "w382 y+0", "Press Ctrl+0 to toggle workspace number overlays and monitor border.")

dlg.Add("Text", "w382 y+0", "Active monitor (based on mouse position) is highlighted with a border.")
dlg.Add("Text", "w382 y+0", "Press OK to continue.")

; Use a simpler way to center the button with a container
buttonContainer := dlg.Add("Text", "w382 h1 Center y+15") ; Invisible container for centering
dlg.Add("Button", "Default w80 Section xp+151 yp+0", "OK").OnEvent("Click", (*) => dlg.Destroy())

; Display the dialog
dlg.Show()
WinWaitClose(dlg)

; ====== Visual Elements Initialization ======
; Initialize visual elements only after the dialog is dismissed
InitializeOverlays() ; Create workspace overlay displays - adds visual indicators for workspace numbers

; ====== Start Timers ======
; Set up periodic cleanup of window references (every 2 minutes)
SetTimer(CleanupWindowReferences, 120000)

; Set up periodic check for mouse movement to update active monitor border
SetTimer(CheckMouseMovement, 100) ; Check every 100ms

; Function to periodically check mouse position and update active monitor border
CheckMouseMovement(*) {
    ; Reference global variables
    global SCRIPT_EXITING, BORDER_VISIBLE, DEBUG_MODE

    ; Skip if script is exiting
    if (SCRIPT_EXITING) {
        if (DEBUG_MODE)
            LogMessage("Script is exiting, ignoring mouse movement check")
        return
    }

    ; Only check for active monitor updates when border is visible
    if (BORDER_VISIBLE) {
        try {
            UpdateActiveMonitorBorder()
        } catch Error as err {
            if (DEBUG_MODE)
                LogMessage("Error updating active monitor border: " err.Message)
        }
    }
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

; Ctrl+Shift+1 through Ctrl+Shift+9 for sending active window to workspaces
^+1::SendWindowToWorkspace(1) ; Ctrl+Shift+1 hotkey to send active window to workspace 1
^+2::SendWindowToWorkspace(2) ; Ctrl+Shift+2 hotkey to send active window to workspace 2
^+3::SendWindowToWorkspace(3) ; Ctrl+Shift+3 hotkey to send active window to workspace 3
^+4::SendWindowToWorkspace(4) ; Ctrl+Shift+4 hotkey to send active window to workspace 4
^+5::SendWindowToWorkspace(5) ; Ctrl+Shift+5 hotkey to send active window to workspace 5
^+6::SendWindowToWorkspace(6) ; Ctrl+Shift+6 hotkey to send active window to workspace 6
^+7::SendWindowToWorkspace(7) ; Ctrl+Shift+7 hotkey to send active window to workspace 7
^+8::SendWindowToWorkspace(8) ; Ctrl+Shift+8 hotkey to send active window to workspace 8
^+9::SendWindowToWorkspace(9) ; Ctrl+Shift+9 hotkey to send active window to workspace 9

; Ctrl+0 to toggle workspace overlays and monitor border
^0::ToggleBordersAndOverlays() ; Ctrl+0 hotkey to show/hide workspace overlays and monitor border

; Function to toggle both workspace overlays and monitor borders with Ctrl+0
ToggleBordersAndOverlays() {
    ; Toggle workspace number overlays
    ToggleOverlays()

    ; Toggle monitor borders separately
    ToggleMonitorBorders()
}

; ====== Register Event Handlers ======
; Track window move/resize events to update layouts
; Track new window events to assign to current workspace
; This event provides an hwnd when a window is created
; Track window close events to remove windows from tracking
