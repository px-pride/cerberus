#Requires AutoHotkey v2.0
#SingleInstance Force

; Cerberus - Multi-monitor workspace management system
; To enable debug mode, change DEBUG_MODE to True below

; Set custom tray icon
TraySetIcon(A_ScriptDir "\cerberus.ico")

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
DelayedWindowCheck(hwnd, *) {
    ; Reference global variables
    global SCRIPT_EXITING, DEBUG_MODE

    ; Skip if script is exiting
    if (SCRIPT_EXITING) {
        if (DEBUG_MODE)
            LogMessage("Script is exiting, ignoring delayed window check")
        return
    }

    ; Only call AssignNewWindow if window is still valid
    try {
        ; More careful check for window existence to avoid errors
        try {
            if (WinExist("ahk_id " hwnd))
                AssignNewWindow(hwnd)
            else if (DEBUG_MODE)
                LogMessage("Skipping delayed assignment for window " hwnd " - no longer exists")
        } catch Error as existErr {
            if (DEBUG_MODE)
                LogMessage("Error checking window existence in DelayedWindowCheck: " existErr.Message)
        }
    } catch Error as err {
        if (DEBUG_MODE)
            LogMessage("Error in delayed window assignment timer: " err.Message)
    }
}
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

        ; Update workspace window overlay if it's visible
        UpdateWorkspaceWindowOverlay()

        if (DEBUG_MODE)
            LogMessage("Window successfully assigned to workspace " targetWorkspaceID)

        if (DEBUG_MODE)
            LogMessage("------------- SEND WINDOW TO WORKSPACE END -------------")
    } catch Error as err {
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

            ; Update overlays immediately after changing workspace IDs
            UpdateAllOverlays()
            
            ; Step 2: Move windows from active monitor to other monitor
            for index, hwnd in activeMonitorWindows {
                try {
                    ; Get window position and state
                    WinGetPos(&x, &y, &width, &height, hwnd)
                    isMaximized := WinGetMinMax(hwnd) = 1
                    
                    if (DEBUG_MODE) {
                        title := WinGetTitle(hwnd)
                        LogMessage("Moving window from active to other monitor: " title)
                    }

                    ; Move window, preserving layout
                    if (isMaximized) {
                        ; First restore to normal, move, then maximize again
                        if (WinGetMinMax(hwnd) = 1)
                            WinRestore("ahk_id " hwnd)

                        ; Move to new position
                        WinMove(x - offsetX, y - offsetY, width, height, "ahk_id " hwnd)

                        ; Verify the window was moved to the correct monitor
                        Sleep(30) ; Allow time for the move operation to complete
                        currMonitor := GetWindowMonitor(hwnd)

                        if (currMonitor != otherMonitor) {
                            ; Recalculate position in other monitor
                            MonitorGetWorkArea(otherMonitor, &mLeft, &mTop, &mRight, &mBottom)
                            centerX := mLeft + (mRight - mLeft - width) / 2
                            centerY := mTop + (mBottom - mTop - height) / 2

                            ; Force window to other monitor
                            WinMove(centerX, centerY, width, height, "ahk_id " hwnd)

                            if (DEBUG_MODE)
                                LogMessage("CORRECTED position to ensure window is on other monitor: " title)
                        }

                        ; Maximize again
                        WinMaximize("ahk_id " hwnd)
                    } else {
                        ; For non-maximized windows, just move them
                        WinMove(x - offsetX, y - offsetY, width, height, "ahk_id " hwnd)

                        ; Verify the window was moved to the correct monitor
                        Sleep(30) ; Allow time for the move operation to complete
                        currMonitor := GetWindowMonitor(hwnd)

                        if (currMonitor != otherMonitor) {
                            ; Recalculate position in other monitor
                            MonitorGetWorkArea(otherMonitor, &mLeft, &mTop, &mRight, &mBottom)
                            centerX := mLeft + (mRight - mLeft - width) / 2
                            centerY := mTop + (mBottom - mTop - height) / 2

                            ; Force window to other monitor
                            WinMove(centerX, centerY, width, height, "ahk_id " hwnd)

                            if (DEBUG_MODE)
                                LogMessage("CORRECTED position to ensure window is on other monitor: " title)
                        }
                    }
                    
                    Sleep(30) ; Short delay to prevent overwhelming the system
                } catch Error as err {
                    if (DEBUG_MODE)
                        LogMessage("ERROR moving window: " err.Message)
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

            ; Update overlays immediately after changing workspace ID
            UpdateAllOverlays()

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

                ; Check if window belongs to the requested workspace
                workspaceID := WindowWorkspaces.Has(hwnd) ? WindowWorkspaces[hwnd] : 0

                if (workspaceID = requestedID) {
                    ; This is a window that belongs to the requested workspace

                    ; Move it to the active monitor if it's not already there
                    if (windowMonitor != activeMonitor) {
                        ; Get monitor dimensions
                        MonitorGetWorkArea(activeMonitor, &mLeft, &mTop, &mRight, &mBottom)

                        ; Get window size
                        WinGetPos(&x, &y, &width, &height, "ahk_id " hwnd)

                        ; Center window on active monitor
                        newX := mLeft + (mRight - mLeft - width) / 2
                        newY := mTop + (mBottom - mTop - height) / 2

                        ; Move window to active monitor
                        WinMove(newX, newY, width, height, "ahk_id " hwnd)

                        if (DEBUG_MODE)
                            LogMessage("MOVING window from monitor " windowMonitor " to active monitor " activeMonitor ": " title)
                    }

                    if (DEBUG_MODE)
                        LogMessage("RESTORING window for workspace " requestedID ": " title)

                    ; Use the proper RestoreWindowLayout function to restore window using saved layout
                    try {
                        ; First restore from minimized state if needed
                        if (winState = -1) {
                            WinRestore("ahk_id " hwnd)
                            Sleep(30) ; Allow time for the restore operation to complete
                        }
                        
                        ; Now use saved layout data to restore the window properly
                        RestoreWindowLayout(hwnd, requestedID)

                        ; Verify window is on the correct monitor even if it was already restored
                        try {
                            ; Get current window position after restore
                            WinGetPos(&currX, &currY, &currWidth, &currHeight, "ahk_id " hwnd)

                            ; Get current window monitor
                            currMonitor := GetWindowMonitor(hwnd)

                            ; Check if window needs to be moved to the active monitor
                            if (currMonitor != activeMonitor) {
                                ; Get active monitor dimensions
                                MonitorGetWorkArea(activeMonitor, &mLeft, &mTop, &mRight, &mBottom)

                                ; Calculate new position to center window on active monitor
                                newX := mLeft + (mRight - mLeft - currWidth) / 2
                                newY := mTop + (mBottom - mTop - currHeight) / 2

                                ; Move window to active monitor
                                WinMove(newX, newY, currWidth, currHeight, "ahk_id " hwnd)

                                if (DEBUG_MODE)
                                    LogMessage("MOVED restored window to active monitor: " title)

                                Sleep(30) ; Allow time for the move operation to complete
                            }
                        } catch Error as moveErr {
                            if (DEBUG_MODE)
                                LogMessage("ERROR moving window to correct monitor: " moveErr.Message)
                        }

                        ; Note: WindowWorkspaces is now updated by event handlers, not directly here
                        SaveWindowLayout(hwnd, requestedID)

                        restoreCount++
                        Sleep(30) ; Delay to allow operations to complete
                    } catch Error as err {
                        if (DEBUG_MODE)
                            LogMessage("ERROR restoring window: " err.Message)
                    }
                }
            }

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
        UpdateAllOverlays()

        ; Also update the workspace window overlay if it's visible
        UpdateWorkspaceWindowOverlay()

        ; Log workspace window contents AFTER the switch
        if (DEBUG_MODE)
            LogWorkspaceWindowContents("AFTER SWITCH:")

        ; Log that the workspace switch is complete
        if (DEBUG_MODE)
            LogMessage("------------- WORKSPACE SWITCH END -------------")

        ; Always clear the switch in progress flag, even if there was an error
        SWITCH_IN_PROGRESS := False
    }
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
        UpdateWorkspaceWindowOverlay() ; Update overlay if visible
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
            LogMessage("Cleaned up " layoutStaleCount " stale layout entries for workspace " workspaceID)
            layoutTotalStaleCount += layoutStaleCount
        }
    }
    
    if ((staleCount > 0 || workspaceStaleCount > 0 || layoutTotalStaleCount > 0) && DEBUG_MODE) {
        LogMessage("Cleaned up " staleCount " window state entries, " workspaceStaleCount " workspace entries, and " layoutTotalStaleCount " layout entries")
    }
}

WindowMoveResizeHandler(wParam, lParam, msg, hwnd) { ; Handles window move/resize events to update saved layouts
    ; Reference global variables
    global SWITCH_IN_PROGRESS, SCRIPT_EXITING, DEBUG_MODE, MonitorWorkspaces, WindowWorkspaces, WorkspaceLayouts

    ; Skip if script is exiting
    if (SCRIPT_EXITING) {
        if (DEBUG_MODE)
            LogMessage("Script is exiting, ignoring window move/resize event")
        return
    }

    ; Skip if switch is in progress to avoid recursive operations
    if (SWITCH_IN_PROGRESS) {
        if (DEBUG_MODE)
            LogMessage("Workspace switch in progress, ignoring window move/resize event")
        return
    }

    ; Skip invalid windows
    if (!IsWindowValid(hwnd))
        return

    ; Get window info for logging
    title := WinGetTitle(hwnd)
    class := WinGetClass(hwnd)

    ; Log the event type - this helps track all window activity
    if (DEBUG_MODE) {
        eventType := (msg = 0x0003) ? "MOVED" : "RESIZED"
        LogMessage("WINDOW " eventType ": " title " (hwnd: " hwnd ", class: " class ")")
    }

    ; Get window state
    winState := WinGetMinMax(hwnd)

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
                LogMessage("Window minimized and removed from active workspace: " title)
                UpdateWorkspaceWindowOverlay() ; Update overlay if visible
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
                LogMessage("Window un-minimized, reassigned from workspace " prevWorkspaceID " to " newWorkspaceID ": " title)
                UpdateWorkspaceWindowOverlay() ; Update overlay if visible
            }
        }
    }

    ; Update last known state
    lastWindowState[hwnd] := winState

    ; For moved/resized windows, update workspace assignment based on monitor
    if (msg = 0x0003 || msg = 0x0005) { ; WM_MOVE or WM_SIZE
        ; Get current monitor and workspace assignment
        windowMonitor := GetWindowMonitor(hwnd)

        ; Track monitor changes for relative positioning
        static lastWindowMonitor := Map()
        monitorChanged := false
        
        ; Initialize if needed
        if (!lastWindowMonitor.Has(hwnd))
            lastWindowMonitor[hwnd] := windowMonitor
            
        ; Check if monitor has changed
        if (lastWindowMonitor[hwnd] != windowMonitor) {
            monitorChanged := true
            if (DEBUG_MODE)
                LogMessage("Window moved to different monitor: " lastWindowMonitor[hwnd] " -> " windowMonitor)
            
            ; Update stored monitor
            lastWindowMonitor[hwnd] := windowMonitor
        }

        if (MonitorWorkspaces.Has(windowMonitor)) {
            currentMonitorWorkspace := MonitorWorkspaces[windowMonitor]

            ; Only update if window has a workspace assigned
            if (WindowWorkspaces.Has(hwnd)) {
                currentWindowWorkspace := WindowWorkspaces[hwnd]

                ; If window's workspace doesn't match its monitor's workspace, update it
                if (currentWindowWorkspace != currentMonitorWorkspace && currentWindowWorkspace != 0) {
                    WindowWorkspaces[hwnd] := currentMonitorWorkspace
                    LogMessage("Window moved/resized, reassigned from workspace " currentWindowWorkspace " to " currentMonitorWorkspace ": " title)
                    UpdateWorkspaceWindowOverlay() ; Update overlay if visible
                }
            }
        }
    }

    ; Save layout if window has a valid workspace assignment
    if (WindowWorkspaces.Has(hwnd)) {
        workspaceID := WindowWorkspaces[hwnd]
        if (workspaceID > 0) {
            ; Save layout with relative positioning
            SaveWindowLayout(hwnd, workspaceID)
            
            if (DEBUG_MODE && monitorChanged)
                LogMessage("Updated window layout with relative positioning due to monitor change")
        }
    }
}

NewWindowHandler(wParam, lParam, msg, hwnd) { ; Handles window creation events to assign new windows
    ; Reference global variables
    global SWITCH_IN_PROGRESS, SCRIPT_EXITING, DEBUG_MODE, MonitorWorkspaces, WindowWorkspaces

    ; Skip if script is exiting
    if (SCRIPT_EXITING) {
        if (DEBUG_MODE)
            LogMessage("Script is exiting, ignoring new window event")
        return
    }

    ; Skip if switch is in progress to avoid recursive operations
    if (SWITCH_IN_PROGRESS) {
        if (DEBUG_MODE)
            LogMessage("Workspace switch in progress, ignoring new window event")
        return
    }

    ; Validate hwnd first - make sure it's a valid handle
    try {
        if (!hwnd || hwnd = 0) {
            if (DEBUG_MODE)
                LogMessage("NewWindowHandler: Invalid window handle received (null or zero)")
            return
        }
    } catch Error as err {
        if (DEBUG_MODE)
            LogMessage("NewWindowHandler: Error validating handle parameter: " err.Message)
        return
    }

    ; Get window info for initial logging - even if it's not valid
    try {
        ; First check if the window actually exists
        try {
            if (!WinExist("ahk_id " hwnd)) {
                if (DEBUG_MODE)
                    LogMessage("NewWindowHandler: Window " hwnd " does not exist")
                return
            }
        } catch Error as existErr {
            if (DEBUG_MODE)
                LogMessage("NewWindowHandler: Error checking if window exists: " existErr.Message)
            return
        }

        ; Get basic window info for logging
        try {
            title := WinGetTitle("ahk_id " hwnd)
            class := WinGetClass("ahk_id " hwnd)

            if (DEBUG_MODE)
                LogMessage("NEW WINDOW CREATED: " title " (hwnd: " hwnd ", class: " class ")")
        } catch Error as infoErr {
            if (DEBUG_MODE)
                LogMessage("NEW WINDOW CREATED: Unable to get details (hwnd: " hwnd ") - " infoErr.Message)
        }
    } catch Error as err {
        if (DEBUG_MODE)
            LogMessage("NEW WINDOW CREATED: Unable to get details (hwnd: " hwnd ") - " err.Message)
    }

    ; First do an immediate check to see if the window is valid and what monitor it's on
    if (IsWindowValid(hwnd)) {
        try {
            ; Get window monitor and assign to appropriate workspace immediately
            monitorIndex := GetWindowMonitor(hwnd)

            if (MonitorWorkspaces.Has(monitorIndex)) {
                workspaceID := MonitorWorkspaces[monitorIndex]

                ; Get window title safely
                try {
                    title := WinGetTitle("ahk_id " hwnd)

                    ; Assign to workspace of monitor it appears on
                    WindowWorkspaces[hwnd] := workspaceID
                    UpdateWorkspaceWindowOverlay() ; Update overlay if visible

                    if (DEBUG_MODE)
                        LogMessage("New window immediately assigned to workspace " workspaceID " on monitor " monitorIndex ": " title)

                    ; Save layout and check visibility
                    SaveWindowLayout(hwnd, workspaceID)

                    ; Check if this window should be visible or hidden on this monitor
                    currentWorkspaceID := MonitorWorkspaces[monitorIndex]
                    if (workspaceID != currentWorkspaceID) {
                        ; If window belongs to workspace not current on this monitor, minimize it
                        try {
                            WinMinimize("ahk_id " hwnd)
                            if (DEBUG_MODE)
                                LogMessage("Minimized new window belonging to non-visible workspace")
                        } catch Error as minErr {
                            if (DEBUG_MODE)
                                LogMessage("Error minimizing window: " minErr.Message)
                        }
                    }
                } catch Error as err {
                    if (DEBUG_MODE)
                        LogMessage("Error getting window title in immediate assignment: " err.Message)
                }
            }
        } catch Error as err {
            if (DEBUG_MODE)
                LogMessage("Error in new window handler: " err.Message)
        }
    }

    ; Also queue a delayed assignment to catch any window movement or initialization issues
    ; This helps ensure window properties and position are stable after initial creation

    ; Make sure hwnd is still valid before setting the timer
    try {
        ; Store hwnd in a variable that's accessible to the function
        if (WinExist("ahk_id " hwnd)) {
            local_hwnd := hwnd
            ; Use a traditional function-based approach with SetTimer
            SetTimer(DelayedWindowCheck.Bind(local_hwnd), -1000)
        } else if (DEBUG_MODE) {
            LogMessage("Skipping delayed window check setup - window no longer exists")
        }
    } catch Error as err {
        if (DEBUG_MODE)
            LogMessage("Error setting up delayed window check: " err.Message)
    }
}

; Handler for window close events
WindowCloseHandler(wParam, lParam, msg, hwnd) {
    ; Reference global variables
    global WindowWorkspaces, SCRIPT_EXITING, DEBUG_MODE

    ; Skip if script is exiting
    if (SCRIPT_EXITING) {
        if (DEBUG_MODE)
            LogMessage("Script is exiting, ignoring window close event")
        return
    }

    ; Skip if the window is not being tracked
    if (!WindowWorkspaces.Has(hwnd))
        return

    ; Get window info for logging before it's gone
    try {
        title := WinGetTitle(hwnd)
        workspaceID := WindowWorkspaces[hwnd]

        if (DEBUG_MODE)
            LogMessage("WINDOW CLOSED: " title " (hwnd: " hwnd "), previously in workspace " workspaceID)
    } catch Error as err {
        ; Window may already be gone by this point, which is fine
        if (DEBUG_MODE)
            LogMessage("Window closing - could not get title - hwnd: " hwnd)
    }

    ; Remove the window from tracking
    WindowWorkspaces.Delete(hwnd)

    ; Update the workspace window overlay if it's visible
    UpdateWorkspaceWindowOverlay()
}

AssignNewWindow(hwnd) { ; Assigns a new window to appropriate workspace (delayed follow-up check)
    ; Reference global variables
    global DEBUG_MODE, MonitorWorkspaces, WindowWorkspaces

    ; Validate the hwnd parameter
    try {
        if (!hwnd || hwnd = 0) {
            if (DEBUG_MODE)
                LogMessage("AssignNewWindow: Invalid window handle (null or zero)")
            return
        }
    } catch Error as err {
        if (DEBUG_MODE)
            LogMessage("AssignNewWindow: Error validating handle parameter: " err.Message)
        return
    }

    ; Verify window still exists
    try {
        if (!WinExist("ahk_id " hwnd)) {
            if (DEBUG_MODE)
                LogMessage("AssignNewWindow: Window " hwnd " no longer exists")
            return
        }
    } catch Error as existErr {
        if (DEBUG_MODE)
            LogMessage("AssignNewWindow: Error checking window existence: " existErr.Message)
        return
    }

    ; Check again if the window exists and is valid - it might have closed already
    if (!IsWindowValid(hwnd)) {
        if (DEBUG_MODE)
            LogMessage("AssignNewWindow: Window " hwnd " is not valid")
        return
    }

    ; Get window info safely
    try {
        title := WinGetTitle("ahk_id " hwnd)
        class := WinGetClass("ahk_id " hwnd)

        if (DEBUG_MODE)
            LogMessage("Follow-up check for window - Title: " title ", Class: " class ", hwnd: " hwnd)
    } catch Error as err {
        if (DEBUG_MODE)
            LogMessage("Error getting window info in delayed check: " err.Message)
        return
    }

    ; Check the window's current monitor (it may have moved since initial creation)
    try {
        monitorIndex := GetWindowMonitor(hwnd) ; Gets which monitor the window is on now
        if (DEBUG_MODE)
            LogMessage("Window is now on monitor: " monitorIndex)
    } catch Error as err {
        if (DEBUG_MODE)
            LogMessage("Error getting window monitor in delayed check: " err.Message)
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
                UpdateWorkspaceWindowOverlay() ; Update overlay if visible
                if (DEBUG_MODE)
                    LogMessage("Window assigned in delayed check to workspace " workspaceID " on monitor " monitorIndex)

                ; Check visibility
                currentWorkspaceID := MonitorWorkspaces[monitorIndex]
                if (workspaceID != currentWorkspaceID) {
                    try {
                        WinMinimize("ahk_id " hwnd)
                        if (DEBUG_MODE)
                            LogMessage("Minimized window belonging to non-visible workspace (delayed check)")
                    } catch Error as minErr {
                        if (DEBUG_MODE)
                            LogMessage("Error minimizing window in delayed check: " minErr.Message)
                    }
                }
            } catch Error as err {
                if (DEBUG_MODE)
                    LogMessage("Error assigning window in delayed check: " err.Message)
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
                    UpdateWorkspaceWindowOverlay() ; Update overlay if visible
                    if (DEBUG_MODE)
                        LogMessage("Updated window workspace from " currentWorkspaceID " to " workspaceID " (delayed check)")

                    ; Check if it needs to be minimized due to workspace mismatch
                    currentMonitorWorkspace := MonitorWorkspaces[monitorIndex]
                    if (workspaceID != currentMonitorWorkspace) {
                        try {
                            if (WinGetMinMax("ahk_id " hwnd) != -1) {
                                WinMinimize("ahk_id " hwnd)
                                if (DEBUG_MODE)
                                    LogMessage("Minimized moved window for workspace consistency (delayed check)")
                            }
                        } catch Error as minErr {
                            if (DEBUG_MODE)
                                LogMessage("Error handling window minimization: " minErr.Message)
                        }
                    }
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
                UpdateWorkspaceWindowOverlay() ; Update overlay if visible
                if (DEBUG_MODE)
                    LogMessage("Assigned window to unassigned workspace (0) - monitor not tracked (delayed check)")
            }
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
        CreateOverlay(monitorIndex) ; Create overlay for this monitor
    }

    ; Create border overlays for all monitors
    InitializeMonitorBorders()

    ; Show all overlays initially
    UpdateAllOverlays() ; Update and show all overlays permanently

    ; Update the active monitor border based on current mouse position
    UpdateActiveMonitorBorder()

    ; No timer needed as we're using persistent overlays
}

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

; Function to gather information about which windows are in each workspace
GetWorkspaceWindowInfo() {
    ; Reference global variables
    global WindowWorkspaces, MAX_WORKSPACES, DEBUG_MODE

    if (DEBUG_MODE)
        LogMessage("Getting fresh window workspace information")

    ; Create a structure to hold window info by workspace
    windowsByWorkspace := Map()

    ; Initialize map for each workspace
    loop MAX_WORKSPACES {
        windowsByWorkspace[A_Index] := []
    }

    ; Add special category for unassigned windows (workspace 0)
    windowsByWorkspace[0] := []

    ; Force a check of the window list (ensure we get the most current windows)
    try {
        ; Collect all valid windows and group them by workspace
        windows := WinGetList() ; Get all window handles

        if (DEBUG_MODE)
            LogMessage("Processing " windows.Length " windows for workspace list")

        windowCount := 0

        for hwnd in windows {
            ; Skip invalid windows
            if (!IsWindowValid(hwnd))
                continue

            ; Get window info
            title := WinGetTitle(hwnd)

            ; Skip windows with no title
            if (title = "")
                continue

            ; Check if window has a workspace assignment
            workspaceID := WindowWorkspaces.Has(hwnd) ? WindowWorkspaces[hwnd] : 0

            ; Add window to appropriate workspace list
            windowsByWorkspace[workspaceID].Push({
                hwnd: hwnd,
                title: title
            })

            windowCount++
        }

        if (DEBUG_MODE)
            LogMessage("Added " windowCount " windows to workspace list")
    } catch Error as err {
        if (DEBUG_MODE)
            LogMessage("Error gathering window information: " err.Message)
    }

    ; Check the window counts for debugging
    if (DEBUG_MODE) {
        totalWindows := 0
        for i in [0, 1, 2, 3, 4, 5, 6, 7, 8, 9] {
            if (windowsByWorkspace.Has(i)) {
                count := windowsByWorkspace[i].Length
                LogMessage("Found " count " windows in workspace " i)
                totalWindows += count
            }
        }
        LogMessage("Total windows counted: " totalWindows)

        ; Log how many windows are in the WindowWorkspaces map
        trackedCount := WindowWorkspaces.Count
        LogMessage("WindowWorkspaces map contains " trackedCount " windows")
    }

    return windowsByWorkspace
}

; Function to log detailed workspace window information
LogWorkspaceWindowContents(prefix := "") {
    ; Reference global variables
    global DEBUG_MODE, MAX_WORKSPACES, WindowWorkspaces

    if (!DEBUG_MODE)
        return

    ; Get window information
    windowsByWorkspace := GetWorkspaceWindowInfo()

    ; Start log message
    LogMessage(prefix " ===== WORKSPACE WINDOW CONTENTS =====")

    ; Log each workspace's windows
    totalWindows := 0
    for workspaceID in [0, 1, 2, 3, 4, 5, 6, 7, 8, 9] {
        if (workspaceID > MAX_WORKSPACES && workspaceID != 0)
            continue

        if (windowsByWorkspace.Has(workspaceID)) {
            windows := windowsByWorkspace[workspaceID]

            ; Log workspace header
            if (workspaceID = 0)
                LogMessage(prefix " UNASSIGNED WORKSPACE: " windows.Length " windows")
            else
                LogMessage(prefix " WORKSPACE " workspaceID ": " windows.Length " windows")

            ; Log each window in this workspace
            for index, window in windows {
                title := window.title
                hwnd := window.hwnd

                ; Get window state information for more detail
                try {
                    isMinimized := WinGetMinMax("ahk_id " hwnd) = -1
                    isMaximized := WinGetMinMax("ahk_id " hwnd) = 1

                    ; Get monitor info if possible
                    monitorIndex := GetWindowMonitor(hwnd)

                    ; Create state string
                    stateStr := isMinimized ? "MINIMIZED" : (isMaximized ? "MAXIMIZED" : "NORMAL")

                    ; Log window details
                    LogMessage(prefix "   [" index "] hwnd: " hwnd ", title: '" title "', state: " stateStr ", monitor: " monitorIndex)
                } catch Error as err {
                    ; Simpler log if error occurs getting details
                    LogMessage(prefix "   [" index "] hwnd: " hwnd ", title: '" title "', ERROR: " err.Message)
                }
            }

            totalWindows += windows.Length
        } else if (workspaceID != 0) {
            ; Log empty workspace
            LogMessage(prefix " WORKSPACE " workspaceID ": 0 windows")
        }
    }

    ; Log summary
    LogMessage(prefix " Total windows: " totalWindows)
    LogMessage(prefix " ===== END WORKSPACE WINDOW CONTENTS =====")
}

CreateOverlay(monitorIndex) { ; Creates workspace indicator overlay for specified monitor
    ; Reference global variables
    global MonitorWorkspaces, WorkspaceOverlays, OVERLAY_SIZE, OVERLAY_MARGIN, OVERLAY_POSITION, OVERLAY_OPACITY

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
    ; Reference global variables
    global WorkspaceOverlays

    ; Update and show all overlays
    for monitorIndex, overlay in WorkspaceOverlays {
        UpdateOverlay(monitorIndex)
    }

    ; No timer needed as we're using persistent overlays
}

UpdateOverlay(monitorIndex) { ; Updates the workspace indicator for specified monitor
    ; Reference global variables
    global MonitorWorkspaces, WorkspaceOverlays, OVERLAY_SIZE

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
        UpdateAllOverlays()

        ; Reset hide timer if using timeout
        if (OVERLAY_TIMEOUT > 0) {
            SetTimer(HideAllOverlays, -OVERLAY_TIMEOUT) ; Sets timer to hide overlays after specified delay
        }
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

; Function to show/hide an overlay with a list of windows in each workspace
ShowWorkspaceWindowList() {
    ; Reference global variables
    global WindowListVisible, WindowListOverlay

    ; Toggle the overlay visibility
    if (WindowListVisible && WindowListOverlay && WinExist("ahk_id " WindowListOverlay.Hwnd)) {
        HideWorkspaceWindowList()
    } else {
        ShowWorkspaceWindowOverlay()
    }
}

; Function to hide the workspace window overlay
HideWorkspaceWindowList() {
    ; Reference global variables
    global WindowListVisible, WindowListOverlay, DEBUG_MODE

    if (WindowListVisible && WindowListOverlay && WinExist("ahk_id " WindowListOverlay.Hwnd)) {
        ; Stop the update timer
        SetTimer(PeriodicOverlayUpdate, 0) ; Disable the timer

        ; Destroy the overlay
        WindowListOverlay.Destroy()
        WindowListOverlay := ""
        WindowListVisible := false

        if (DEBUG_MODE)
            LogMessage("Workspace window overlay hidden")
    }
}

; Function for periodic updates of the workspace window overlay
PeriodicOverlayUpdate(*) {
    ; Reference global variables
    global WindowListVisible, WindowListOverlay, SCRIPT_EXITING, DEBUG_MODE

    ; Skip if script is exiting
    if (SCRIPT_EXITING) {
        if (DEBUG_MODE)
            LogMessage("Script is exiting, ignoring overlay update")
        return
    }

    if (DEBUG_MODE)
        LogMessage("Periodic update check for workspace window overlay")

    ; Only proceed if the overlay is visible
    if (WindowListVisible && WindowListOverlay && WinExist("ahk_id " WindowListOverlay.Hwnd)) {
        ; Get fresh window information and rebuild the overlay completely
        if (DEBUG_MODE)
            LogMessage("Refreshing workspace window overlay with current window state")

        ; Get current window information
        windowsByWorkspace := GetWorkspaceWindowInfo()

        ; Update the text in the overlay directly without recreating it
        windowList := BuildWorkspaceWindowText(windowsByWorkspace)

        ; Find the text control and update it
        try {
            for ctrl in WindowListOverlay {
                ctrl.Value := windowList
                break ; Only update the first control (which is our text control)
            }
        } catch Error as err {
            if (DEBUG_MODE)
                LogMessage("Error updating overlay text: " err.Message)
        }
    }
}

; Function to update the workspace window overlay if it's visible
UpdateWorkspaceWindowOverlay() {
    ; Reference global variables
    global WindowListVisible, WindowListOverlay, DEBUG_MODE

    ; If the workspace window overlay is visible, update it
    if (WindowListVisible && WindowListOverlay && WinExist("ahk_id " WindowListOverlay.Hwnd)) {
        if (DEBUG_MODE)
            LogMessage("Updating workspace window overlay due to window changes")

        ; Call our improved periodic update function that directly updates the content
        PeriodicOverlayUpdate()
    }
}

; Function to show or update the workspace window overlay
ShowWorkspaceWindowOverlay() {
    ; Reference global variables
    global WindowListVisible, WindowListOverlay, MAX_WORKSPACES

    ; First destroy any existing overlay
    if (WindowListOverlay && WinExist("ahk_id " WindowListOverlay.Hwnd)) {
        WindowListOverlay.Destroy()
    }

    ; Get current window information for all workspaces
    windowsByWorkspace := GetWorkspaceWindowInfo()

    ; Create a new GUI for the workspace window list overlay
    listGui := Gui("+AlwaysOnTop -Caption +ToolWindow +Owner")
    listGui.BackColor := "000000" ; Black background for overlay

    ; Set overlay size - make it cover most of the screen but not all
    screenWidth := A_ScreenWidth
    screenHeight := A_ScreenHeight
    guiWidth := screenWidth * 0.8
    guiHeight := screenHeight * 0.8

    ; Calculate position to center on screen
    xPos := (screenWidth - guiWidth) / 2
    yPos := (screenHeight - guiHeight) / 2

    ; Add a text control to display the window list
    listGui.SetFont("s12", "Consolas")
    windowList := BuildWorkspaceWindowText(windowsByWorkspace)
    textCtrl := listGui.Add("Text", "x10 y10 w" guiWidth-20 " h" guiHeight-20 " c33FFFF", windowList)

    ; Store GUI reference in global variable
    WindowListOverlay := listGui
    WindowListVisible := true

    ; Show the GUI as an overlay
    listGui.Show("x" xPos " y" yPos " w" guiWidth " h" guiHeight " NoActivate")

    ; Make it semi-transparent (higher value = less transparent)
    WinSetTransparent(225, "ahk_id " listGui.Hwnd)

    ; Set up a timer for periodic updates (every 2 seconds)
    SetTimer(PeriodicOverlayUpdate, 2000)

    if (DEBUG_MODE)
        LogMessage("Workspace window overlay created/updated")

    return listGui
}

; Helper function to build the text display for workspace windows
BuildWorkspaceWindowText(windowsByWorkspace) {
    ; Reference global variables
    global MAX_WORKSPACES

    text := "==========================================`n"
    text .= "           WORKSPACE WINDOWS`n"
    text .= "==========================================`n`n"

    totalWindows := 0

    ; Add windows from each workspace
    loop MAX_WORKSPACES {
        workspaceID := A_Index
        windows := windowsByWorkspace[workspaceID]

        ; If this workspace has windows, add them to the text
        if (windows.Length > 0) {
            text .= "WORKSPACE " workspaceID " (" windows.Length " windows):`n"
            text .= "------------------------------------------`n"

            ; Add each window in this workspace
            for index, window in windows {
                truncatedTitle := SubStr(window.title, 1, 60) ; Truncate long titles
                if (StrLen(window.title) > 60)
                    truncatedTitle .= "..."

                text .= "  • " truncatedTitle "`n"
                totalWindows++
            }

            text .= "`n"
        }
    }

    ; Add unassigned windows (workspace 0) at the end if there are any
    unassignedWindows := windowsByWorkspace[0]
    if (unassignedWindows.Length > 0) {
        text .= "UNASSIGNED (" unassignedWindows.Length " windows):`n"
        text .= "------------------------------------------`n"

        for index, window in unassignedWindows {
            truncatedTitle := SubStr(window.title, 1, 60) ; Truncate long titles
            if (StrLen(window.title) > 60)
                truncatedTitle .= "..."

            text .= "  • " truncatedTitle "`n"
            totalWindows++
        }

        text .= "`n"
    }

    text .= "==========================================`n"
    text .= "Total: " totalWindows " windows across " MAX_WORKSPACES " workspaces`n"
    text .= "Press Ctrl+` again to close this overlay`n"
    text .= "==========================================`n"

    return text
}

; ====== Configuration ======
MAX_WORKSPACES := 9  ; Maximum number of workspaces (1-9)
MAX_MONITORS := 9    ; Maximum number of monitors (adjust as needed)

; ====== Global Variables ======
; ===== DEBUG SETTINGS =====
; Set this to True to enable detailed logging for troubleshooting
global DEBUG_MODE := True  ; Change to True to enable debugging
global LOG_TO_FILE := False  ; Set to True to log to file instead of Debug output
global LOG_FILE := A_ScriptDir "\cerberus.log"  ; Path to log file
global SHOW_WINDOW_EVENT_TOOLTIPS := True  ; Set to True to show tooltips for window events
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
global WindowListOverlay := ""
global WindowListVisible := false
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
    global DEBUG_MODE, SCRIPT_EXITING, WorkspaceOverlays, WindowListOverlay, WindowListVisible

    ; Set flag to prevent handlers from running during exit
    SCRIPT_EXITING := True

    if (DEBUG_MODE)
        LogMessage("===== SCRIPT EXITING (" ExitReason ") =====")

    ; Stop all timers
    SetTimer(CleanupWindowReferences, 0)
    SetTimer(CheckMouseMovement, 0)
    SetTimer(PeriodicOverlayUpdate, 0)
    
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
        if (WindowListOverlay && WindowListOverlay.HasProp("Hwnd") && WinExist("ahk_id " WindowListOverlay.Hwnd)) {
            WindowListOverlay.Destroy()
            WindowListOverlay := ""
            WindowListVisible := false
        }
    } catch Error as err {
        if (DEBUG_MODE)
            LogMessage("Error cleaning up window list overlay: " err.Message)
    }
    
    ; Remove message hooks
    OnMessage(0x0003, WindowMoveResizeHandler, 0)  ; WM_MOVE
    OnMessage(0x0005, WindowMoveResizeHandler, 0)  ; WM_SIZE
    OnMessage(0x0001, NewWindowHandler, 0)         ; WM_CREATE
    OnMessage(0x0002, WindowCloseHandler, 0)       ; WM_DESTROY
    
    ; Clean up any open tool tips
    ToolTip()
    
    ; Clean up static maps in handlers to prevent memory leaks
    try {
        ; Clean global maps to release references to window handles
        WindowWorkspaces := Map()
        WorkspaceLayouts := Map()
        
        ; Clear any remaining handler static variables if possible
        if (ObjHasOwnProp(WindowMoveResizeHandler, "lastWindowState")) {
            WindowMoveResizeHandler.lastWindowState := Map()
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
        if (WindowListOverlay && WinExist("ahk_id " WindowListOverlay.Hwnd)) {
            try WindowListOverlay.Destroy()
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
dlg.Add("Text", "w382 y+0", "Press Ctrl+` to toggle window assignments overlay.")
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
; Ctrl+` to toggle window workspace information overlay
^`::ShowWorkspaceWindowList() ; Ctrl+` hotkey to toggle overlay showing windows in each workspace

; Function to toggle both workspace overlays and monitor borders with Ctrl+0
ToggleBordersAndOverlays() {
    ; Toggle workspace number overlays
    ToggleOverlays()

    ; Toggle monitor borders separately
    ToggleMonitorBorders()
}

; ====== Register Event Handlers ======
; Track window move/resize events to update layouts
OnMessage(0x0003, WindowMoveResizeHandler)  ; WM_MOVE - Registers a handler for window move events
OnMessage(0x0005, WindowMoveResizeHandler)  ; WM_SIZE - Registers a handler for window resize events
; Track new window events to assign to current workspace
; This event provides an hwnd when a window is created
OnMessage(0x0001, NewWindowHandler)  ; WM_CREATE - Registers a handler for window creation events
; Track window close events to remove windows from tracking
OnMessage(0x0002, WindowCloseHandler)  ; WM_DESTROY - Registers a handler for window destruction events