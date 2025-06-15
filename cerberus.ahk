#Requires AutoHotkey v2.0
#SingleInstance Force

; Cerberus - Multi-monitor workspace management system
; Version 1.0.0
; To enable debug mode, change DEBUG_MODE to True below

; Application version
global APP_VERSION := "1.0.0"

; Set custom tray icon
TraySetIcon(A_ScriptDir "\cerberus.ico")

; Removed external include - functionality integrated directly

; ====== Function Definitions ======

; ----- Core System Functions -----

InitializeWorkspaces() {
    LogMessage("============ INITIALIZING WORKSPACES ============")

    ; Initialize monitor workspaces (default: monitor 1 = workspace 1, monitor 2 = workspace 2, etc.)
    monitorCount := MonitorGetCount() ; Gets the total number of physical monitors connected to the system
    LogMessage("Detected " monitorCount " monitors") ; Logs the number of detected monitors to debug output for troubleshooting

    loop MAX_MONITORS {
        monitorIndex := A_Index
        if (monitorIndex <= monitorCount) {
            if (monitorIndex <= MAX_WORKSPACES) {
                MonitorWorkspaces[monitorIndex] := monitorIndex
            } else {
                MonitorWorkspaces[monitorIndex] := 1  ; Default to workspace 1 if we have more monitors than workspaces
            }
            LogMessage("Assigned monitor " monitorIndex " to workspace " MonitorWorkspaces[monitorIndex])
        }
    }

    ; Capture all existing windows and assign them to their monitor's workspace
    DetectHiddenWindows(False) ; Turns off detection of hidden windows so only visible windows are captured
    windows := WinGetList() ; Retrieves an array of all visible window handles (HWND) currently open in the system

    LogMessage("Found " windows.Length " total windows in system")
    windowCount := 0
    assignedCount := 0

    ; First pass - identify all valid windows
    validWindows := []
    for hwnd in windows {
        windowCount++
        title := WinGetTitle(hwnd) ; Gets the title text from the window's title bar for identification
        class := WinGetClass(hwnd) ; Gets the window class name which identifies the window type or application

        LogMessage("Checking window - Title: " title ", Class: " class ", hwnd: " hwnd)

        if (IsWindowValid(hwnd)) { ; Checks if this window should be tracked (excludes system windows, taskbar, etc.)
            LogMessage("Window is valid - adding to tracking list")
            validWindows.Push(hwnd)
        }
    }

    LogMessage("Found " validWindows.Length " valid windows to track")
    
    ; Try to load saved workspace state
    stateLoaded := LoadWorkspaceState()
    if (stateLoaded) {
        LogMessage("Loaded saved workspace state")
    }

    ; Second pass - assign valid windows to workspaces
    for hwnd in validWindows { ; Iterates through the array of window handles that passed validation
        title := WinGetTitle(hwnd)
        class := WinGetClass(hwnd)
        
        ; Check if this window already has a workspace assignment from loaded state
        if (WindowWorkspaces.Has(hwnd)) {
            workspaceID := WindowWorkspaces[hwnd]
            SaveWindowLayout(hwnd, workspaceID)  ; Still save the layout
            LogMessage("Window already assigned to workspace " workspaceID " from saved state: " title)
            assignedCount++
            continue
        }

        ; Check if window is minimized - assign to workspace 0 if it is
        if (WinGetMinMax(hwnd) = -1) { ; Checks window state: -1=minimized, 0=normal, 1=maximized
            WindowWorkspaces[hwnd] := 0 ; Assigns minimized window to workspace 0 (unassigned)
            LogMessage("Window is minimized, assigned to workspace 0 (unassigned): " title)
            continue ; Skip to next window
        }

        ; Assign the window to its monitor's workspace
        monitorIndex := GetWindowMonitor(hwnd) ; Determines which physical monitor contains this window
        workspaceID := MonitorWorkspaces.Has(monitorIndex) ? MonitorWorkspaces[monitorIndex] : 0 ; Gets workspace ID for this monitor, or 0 if monitor isn't tracked

        WindowWorkspaces[hwnd] := workspaceID ; Adds window to the tracking map with its workspace ID
        SaveWindowLayout(hwnd, workspaceID) ; Stores window's position, size, and state (normal/maximized) for later restoration

        LogMessage("Assigned window to workspace " workspaceID " on monitor " monitorIndex ": " title)
        assignedCount++
    }

    LogMessage("Initialization complete: Found " windowCount " windows, " validWindows.Length " valid, assigned " assignedCount " to workspaces")
    LogMessage("============ INITIALIZATION COMPLETE ============")
    
    ; Arrange windows according to their workspace assignments
    if (stateLoaded) {
        ArrangeWindowsToWorkspaces()
    }
    
    ; Save the initial workspace state
    SaveWorkspaceState()

    ; Display a tray tip with the number of windows assigned
    TrayTip("Cerberus initialized", "Assigned " assignedCount " windows to workspaces") ; Shows notification in system tray
}

; ----- Persistence Functions -----

SaveWorkspaceState() {
    ; Create config directory if it doesn't exist
    if (!DirExist(CONFIG_DIR)) {
        try {
            DirCreate(CONFIG_DIR)
            LogMessage("Created config directory: " CONFIG_DIR)
        } catch Error as err {
            LogMessage("Error creating config directory: " err.Message)
            return false
        }
    }
    
    ; Build a data structure to save
    stateData := Map()
    stateData["version"] := "1.0"
    stateData["timestamp"] := A_Now
    
    ; Convert WindowWorkspaces map to saveable format
    ; We need to save: hwnd, workspace ID, window title, window class, and exe name for validation
    windowData := []
    for hwnd, workspaceID in WindowWorkspaces {
        try {
            ; Skip if window no longer exists
            if (!WinExist("ahk_id " hwnd))
                continue
                
            ; Get window information for validation on load
            title := WinGetTitle(hwnd)
            class := WinGetClass(hwnd)
            processName := WinGetProcessName(hwnd)
            
            ; Create window entry
            windowEntry := Map()
            windowEntry["hwnd"] := String(hwnd)  ; Convert to string for JSON
            windowEntry["workspaceID"] := workspaceID
            windowEntry["title"] := title
            windowEntry["class"] := class
            windowEntry["process"] := processName
            
            windowData.Push(windowEntry)
        } catch Error as err {
            LogMessage("Error getting window info for save: " err.Message)
        }
    }
    
    stateData["windows"] := windowData
    
    ; Convert to JSON format
    jsonText := "{"
    jsonText .= '"version":"' . stateData["version"] . '",'
    jsonText .= '"timestamp":"' . stateData["timestamp"] . '",'
    jsonText .= '"windows":['
    
    ; Add window entries
    for index, window in windowData {
        if (index > 1)
            jsonText .= ","
        jsonText .= '{'
        jsonText .= '"hwnd":"' . window["hwnd"] . '",'
        jsonText .= '"workspaceID":' . window["workspaceID"] . ','
        jsonText .= '"title":"' . StrReplace(StrReplace(window["title"], '\', '\\'), '"', '\"') . '",'
        jsonText .= '"class":"' . window["class"] . '",'
        jsonText .= '"process":"' . window["process"] . '"'
        jsonText .= '}'
    }
    
    jsonText .= ']}'
    
    ; Write to file
    try {
        FileDelete(WORKSPACE_STATE_FILE)  ; Delete old file if exists
    } catch {
        ; File doesn't exist, that's okay
    }
    
    try {
        FileAppend(jsonText, WORKSPACE_STATE_FILE, "UTF-8")
        LogMessage("Saved workspace state to: " WORKSPACE_STATE_FILE)
        return true
    } catch Error as err {
        LogMessage("Error saving workspace state: " err.Message)
        return false
    }
}

LoadWorkspaceState() {
    ; Check if state file exists
    if (!FileExist(WORKSPACE_STATE_FILE)) {
        LogMessage("No workspace state file found")
        return false
    }
    
    try {
        ; Read the file
        jsonText := FileRead(WORKSPACE_STATE_FILE, "UTF-8")
        LogMessage("Loaded workspace state file")
        
        ; Parse JSON manually (AutoHotkey doesn't have built-in JSON parsing)
        ; Extract windows array
        windowsStart := InStr(jsonText, '"windows":[') + 11
        windowsEnd := InStr(jsonText, ']}', , windowsStart)
        windowsText := SubStr(jsonText, windowsStart, windowsEnd - windowsStart)
        
        ; Parse each window entry
        restoredCount := 0
        pos := 1
        while (pos < StrLen(windowsText)) {
            ; Find next window entry
            entryStart := InStr(windowsText, '{', , pos)
            if (!entryStart)
                break
                
            entryEnd := InStr(windowsText, '}', , entryStart)
            if (!entryEnd)
                break
                
            entry := SubStr(windowsText, entryStart + 1, entryEnd - entryStart - 1)
            
            ; Extract fields
            hwndMatch := RegExMatch(entry, '"hwnd":"(\d+)"', &hwndResult)
            workspaceMatch := RegExMatch(entry, '"workspaceID":(\d+)', &workspaceResult)
            titleMatch := RegExMatch(entry, '"title":"([^"]*)"', &titleResult)
            classMatch := RegExMatch(entry, '"class":"([^"]*)"', &classResult)
            processMatch := RegExMatch(entry, '"process":"([^"]*)"', &processResult)
            
            if (hwndMatch && workspaceMatch) {
                savedHwnd := hwndResult[1]
                workspaceID := Integer(workspaceResult[1])
                savedTitle := titleMatch ? titleResult[1] : ""
                savedClass := classMatch ? classResult[1] : ""
                savedProcess := processMatch ? processResult[1] : ""
                
                ; Try to find matching window
                matchedHwnd := FindMatchingWindow(savedHwnd, savedTitle, savedClass, savedProcess)
                
                if (matchedHwnd) {
                    ; Restore the workspace assignment
                    WindowWorkspaces[matchedHwnd] := workspaceID
                    LogMessage("Restored window to workspace " workspaceID ": " savedTitle)
                    restoredCount++
                } else {
                    LogMessage("Could not find matching window for: " savedTitle " (class: " savedClass ")")
                }
            }
            
            pos := entryEnd + 1
        }
        
        LogMessage("Restored " restoredCount " window assignments from saved state")
        return true
        
    } catch Error as err {
        LogMessage("Error loading workspace state: " err.Message)
        return false
    }
}

FindMatchingWindow(savedHwnd, savedTitle, savedClass, savedProcess) {
    ; First try the saved hwnd directly
    try {
        if (WinExist("ahk_id " savedHwnd)) {
            ; Verify it's still the same window
            currentClass := WinGetClass(savedHwnd)
            currentProcess := WinGetProcessName(savedHwnd)
            
            if (currentClass = savedClass && currentProcess = savedProcess) {
                return savedHwnd
            }
        }
    } catch {
        ; Window doesn't exist with that hwnd
    }
    
    ; If direct hwnd match fails, try to find by class and process
    if (savedClass != "" && savedProcess != "") {
        windows := WinGetList()
        for hwnd in windows {
            try {
                if (WinGetClass(hwnd) = savedClass && WinGetProcessName(hwnd) = savedProcess) {
                    currentTitle := WinGetTitle(hwnd)
                    
                    ; For some applications, title might change but class/process stay same
                    ; This is a reasonable match
                    LogMessage("Found window by class/process match: " currentTitle)
                    return hwnd
                }
            } catch {
                ; Skip this window
            }
        }
    }
    
    return 0  ; No match found
}

ArrangeWindowsToWorkspaces() {
    ; This function arranges windows to their assigned workspaces after loading state
    LogMessage("Arranging windows to their assigned workspaces...")
    
    arrangedCount := 0
    minimizedCount := 0
    
    ; Go through all windows in WindowWorkspaces
    for hwnd, workspaceID in WindowWorkspaces {
        try {
            ; Skip if window no longer exists
            if (!WinExist("ahk_id " hwnd))
                continue
                
            ; Skip unassigned windows
            if (workspaceID = 0)
                continue
                
            title := WinGetTitle(hwnd)
            
            ; Check if this workspace is currently visible on any monitor
            visibleOnMonitor := 0
            for monitorIndex, monitorWorkspace in MonitorWorkspaces {
                if (monitorWorkspace = workspaceID) {
                    visibleOnMonitor := monitorIndex
                    break
                }
            }
            
            if (visibleOnMonitor > 0) {
                ; Workspace is visible, ensure window is on the correct monitor
                currentMonitor := GetWindowMonitor(hwnd)
                
                if (currentMonitor != visibleOnMonitor) {
                    ; Window is on wrong monitor, move it
                    ; Check if we have saved layout data
                    if (WorkspaceLayouts.Has(workspaceID) && WorkspaceLayouts[workspaceID].Has(hwnd)) {
                        layoutData := WorkspaceLayouts[workspaceID][hwnd]
                        
                        if (layoutData.Has("relX") && layoutData.Has("relY") && 
                            layoutData.Has("relWidth") && layoutData.Has("relHeight")) {
                            ; Use relative positioning to move window
                            absolutePos := RelativeToAbsolutePosition(
                                layoutData["relX"], layoutData["relY"], 
                                layoutData["relWidth"], layoutData["relHeight"], 
                                visibleOnMonitor)
                            
                            WinMove(absolutePos.x, absolutePos.y, absolutePos.width, absolutePos.height, "ahk_id " hwnd)
                            LogMessage("Moved window to correct monitor " visibleOnMonitor ": " title)
                            arrangedCount++
                        }
                    }
                }
                
                ; Ensure window is not minimized if it should be visible
                if (WinGetMinMax(hwnd) = -1) {
                    WinRestore(hwnd)
                    LogMessage("Restored minimized window on visible workspace: " title)
                }
            } else {
                ; Workspace is not visible, minimize the window
                if (WinGetMinMax(hwnd) != -1) {
                    WinMinimize(hwnd)
                    LogMessage("Minimized window on non-visible workspace " workspaceID ": " title)
                    minimizedCount++
                }
            }
            
        } catch Error as err {
            LogMessage("Error arranging window: " err.Message)
        }
    }
    
    LogMessage("Window arrangement complete: " arrangedCount " moved, " minimizedCount " minimized")
}

IsWindowValid(hwnd) { ; Checks if window should be tracked by Cerberus
    ; Reference global variables
    global A_ScriptHwnd

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

        LogMessage("Checking window - Title: " title ", Class: " class ", hwnd: " hwnd)

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
            LogMessage("Error getting window styles: " err.Message)
            return false
        }

        ; For debugging, log valid windows
        LogMessage("VALID WINDOW - Title: " title ", Class: " class ", hwnd: " hwnd)

        ; Window passed all checks, it's valid for tracking
        return true
    } catch Error as err {
        ; If there's any error getting window information, the window isn't valid
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
            LogMessage("GetWindowMonitorIndex: Invalid window handle (null or zero)")
            return 1 ; Default to primary monitor
        }
    } catch Error as err {
        LogMessage("GetWindowMonitorIndex: Error validating handle parameter: " err.Message)
        return 1 ; Default to primary monitor
    }

    ; Verify window still exists
    try {
        if (!WinExist("ahk_id " windowHandle)) {
            LogMessage("GetWindowMonitorIndex: Window " windowHandle " no longer exists")
            return 1 ; Default to primary monitor
        }
    } catch Error as existErr {
        LogMessage("GetWindowMonitorIndex: Error checking window existence: " existErr.Message)
        return 1 ; Default to primary monitor
    }

    ; Get monitor count - handle error gracefully
    try {
        monitorCount := MonitorGetCount()
        if (monitorCount <= 0) {
            LogMessage("GetWindowMonitorIndex: Invalid monitor count: " monitorCount)
            return 1 ; Default to primary monitor
        }

        if (monitorCount = 1)
            return 1 ; Only one monitor, must be that one
    } catch Error as err {
        LogMessage("GetWindowMonitorIndex: Error getting monitor count: " err.Message)
        return 1 ; Default to primary monitor
    }

    ; Safely get window position
    try {
        ; Use a nested try-catch for the WinGetPos call specifically
        try {
            WinGetPos(&winX, &winY, &winWidth, &winHeight, "ahk_id " windowHandle)
        } catch Error as posErr {
            LogMessage("GetWindowMonitorIndex: WinGetPos failed: " posErr.Message)
            return 1 ; Default to primary monitor
        }

        ; Validate position values
        if (winX = "" || winY = "" || winWidth = "" || winHeight = "") {
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
                LogMessage("GetWindowMonitorIndex: Error getting monitor " A_Index " work area: " monErr.Message)
                ; Continue checking other monitors
            }
        }
    } catch Error as err {
        LogMessage("GetWindowMonitorIndex: Error processing window position: " err.Message)
        return 1 ; Default to primary monitor
    }

    ; If no monitor contains the window center, default to primary
    LogMessage("GetWindowMonitorIndex: Window not found on any monitor - using primary")
    return 1
}

GetActiveMonitor() { ; Gets the monitor index where the mouse cursor is located
    ; Reference global variables
    global 
    try {
        ; Get mouse cursor position
        MouseGetPos(&mouseX, &mouseY)

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
                    LogMessage("SaveWindowLayout: Window " hwnd " no longer exists")
                    return
                }
            } catch Error as existErr {
                LogMessage("SaveWindowLayout: Error checking window existence: " existErr.Message)
                return
            }

            ; Get window position with better error handling
            try {
                WinGetPos(&x, &y, &width, &height, "ahk_id " hwnd) ; Captures current window coordinates and dimensions to save in layout
            } catch Error as posErr {
                LogMessage("SaveWindowLayout: WinGetPos failed: " posErr.Message)
                return
            }

            ; Make sure the values are valid
            if (x = "" || y = "" || width = "" || height = "") {
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

            LogMessage("SaveWindowLayout: Saved layout for window " hwnd " in workspace " workspaceID)
        } catch Error as err {
            LogMessage("Error getting window information in SaveWindowLayout: " err.Message)
        }
    } catch Error as err {
        LogMessage("Error in SaveWindowLayout: " err.Message)
    }
}

RestoreWindowLayout(hwnd, workspaceID) { ; Restores a window to its saved position and state
    ; Check if window exists and is valid
    if !IsWindowValid(hwnd) {
        LogMessage("RESTORE FAILED: Window " hwnd " is not valid")
        return
    }

    title := WinGetTitle(hwnd)
    LogMessage("Attempting to restore window: " title " (" hwnd ")")

    try {
        ; First ensure the window is restored from minimized state
        winState := WinGetMinMax(hwnd) ; Gets window state (-1=minimized, 0=normal, 1=maximized)
        if (winState = -1) { ; If window is currently minimized, restore it first before applying layout
            LogMessage("Window is minimized, restoring first")

            try {
                WinRestore("ahk_id " hwnd) ; Restores window from minimized state so we can apply position/size
                Sleep(100) ; Allow time for the window to restore

                ; Verify the restore worked
                if (WinGetMinMax(hwnd) = -1) {
                    LogMessage("Window restore failed, retrying...")
                    Sleep(200)
                    WinRestore("ahk_id " hwnd) ; Try again
                    Sleep(100)
                }
            } catch Error as err {
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
                
                if (useRelativePositioning)
                    LogMessage("Monitor changed: Original=" layout.monitorIndex ", Current=" currentMonitorIndex ". Using relative positioning.")
                else
                    LogMessage("Found saved layout for window: x=" layout.x ", y=" layout.y ", w=" layout.width ", h=" layout.height)

                ; Apply saved layout
                if (layout.isMaximized) { ; If window was previously maximized
                    LogMessage("Maximizing window")

                    try {
                        WinMaximize("ahk_id " hwnd) ; Restore window to maximized state

                        ; Verify maximize worked
                        if (WinGetMinMax(hwnd) != 1) {
                            LogMessage("Window maximize failed, retrying...")
                            Sleep(200)
                            WinMaximize("ahk_id " hwnd) ; Try again
                        }
                    } catch Error as err {
                        LogMessage("ERROR maximizing window: " err.Message)
                    }
                } else {
                    ; Move window to saved position
                    try {
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
                            LogMessage("Window position out of bounds, using default position")
                            WinActivate("ahk_id " hwnd)
                        }
                    } catch Error as err {
                        LogMessage("ERROR moving window: " err.Message)
                    }
                }
            } else {
                LogMessage("No saved layout found for this window, using default position")
                WinActivate("ahk_id " hwnd) ; At least activate the window
            }
        } else {
            LogMessage("No layouts saved for workspace " workspaceID)
        }

        ; Ensure window is visible and brought to front
        try {
            WinActivate("ahk_id " hwnd) ; Brings window to foreground and gives it keyboard focus
        } catch Error as err {
            LogMessage("ERROR activating window: " err.Message)
        }
    } catch Error as err {
        LogMessage("CRITICAL ERROR in RestoreWindowLayout: " err.Message)
    }
}

; ----- Utility Functions -----

; Function to log messages either to file or debug output
LogMessage(message) {
    global LOG_TO_FILE, LOG_FILE, SHOW_WINDOW_EVENT_TOOLTIPS, SHOW_TRAY_NOTIFICATIONS

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
    global SCRIPT_EXITING
    ; Skip if script is exiting
    if (SCRIPT_EXITING) {
        LogMessage("Script is exiting, ignoring delayed window check")
        return
    }

    ; Only call AssignNewWindow if window is still valid
    try {
        ; More careful check for window existence to avoid errors
        try {
            if (WinExist("ahk_id " hwnd))
                AssignNewWindow(hwnd)
            else
                LogMessage("Skipping delayed assignment for window " hwnd " - no longer exists")
        } catch Error as existErr {
            LogMessage("Error checking window existence in DelayedWindowCheck: " existErr.Message)
        }
    } catch Error as err {
        LogMessage("Error in delayed window assignment timer: " err.Message)
    }
}

SendWindowToWorkspace(targetWorkspaceID) { ; Sends active window to specified workspace
    ; Reference global variables
    global SWITCH_IN_PROGRESS, MAX_WORKSPACES, MonitorWorkspaces, WindowWorkspaces, WorkspaceLayouts

    ; Early exit conditions
    if (targetWorkspaceID < 1 || targetWorkspaceID > MAX_WORKSPACES)
        return

    ; Check if another switch operation is already in progress
    if (SWITCH_IN_PROGRESS) {
        LogMessage("Another workspace operation in progress, ignoring send window request")
        return
    }

    ; Set the flag to indicate operation is in progress
    SWITCH_IN_PROGRESS := True

    try {
        ; Log the start of window movement
        LogMessage("------------- SEND WINDOW TO WORKSPACE START -------------")

        ; Get active window
        activeHwnd := WinExist("A")
        if (!activeHwnd || !IsWindowValid(activeHwnd)) {
            LogMessage("No valid active window to move")
            SWITCH_IN_PROGRESS := False
            return
        }

        ; Get window title for logging
        title := WinGetTitle(activeHwnd)
        LogMessage("Sending window '" title "' to workspace " targetWorkspaceID)

        ; Update window workspace assignment
        prevWorkspaceID := WindowWorkspaces.Has(activeHwnd) ? WindowWorkspaces[activeHwnd] : 0
        
        ; Save the current window layout before moving it
        SaveWindowLayout(activeHwnd, prevWorkspaceID)
        
        ; Now update the workspace assignment
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
            LogMessage("Target workspace " targetWorkspaceID " is visible on monitor " targetMonitor)

            ; Get target monitor dimensions
            MonitorGetWorkArea(targetMonitor, &mLeft, &mTop, &mRight, &mBottom)
            LogMessage(mTop " " mLeft " " mBottom " " mRight)

            ; Get current window position and size
            try {
                WinGetPos(&x, &y, &width, &height, "ahk_id " activeHwnd)

                ; Check for valid dimensions
                if (x = "" || y = "" || width = "" || height = "") {
                    LogMessage("SendWindowToWorkspace: Invalid position values for window")

                    ; Use default sizes if we couldn't get valid values
                    width := width ? width : 800
                    height := height ? height : 600
                    x := x ? x : 0
                    y := y ? y : 0
                }
            } catch Error as err {
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
            if (prevWorkspaceID > 0 && WorkspaceLayouts.Has(prevWorkspaceID) && 
                WorkspaceLayouts[prevWorkspaceID].Has(activeHwnd)) {
                
                ; Get existing layout data with relative positioning
                existingLayout := WorkspaceLayouts[prevWorkspaceID][activeHwnd]
                
                LogMessage("Found existing layout data for window from workspace " prevWorkspaceID ", using relative positioning")
                
                ; Use relative positioning to calculate new position on target monitor
                absolutePos := RelativeToAbsolutePosition(
                    existingLayout.relX, existingLayout.relY, existingLayout.relWidth, existingLayout.relHeight, targetMonitor)
                
                newX := absolutePos.x
                newY := absolutePos.y
                newWidth := absolutePos.width
                newHeight := absolutePos.height
                LogMessage(absolutePos.x " " absolutePos.y " " absolutePos.width " " absolutePos.height)
                LogMessage("Using relative position: new x=" newX ", y=" newY ", w=" newWidth ", h=" newHeight)
            } else {
                ; No previous layout data - use current window dimensions and maintain proportions
                LogMessage("No existing layout data, using current window proportions")
                
                ; Convert current position to relative on source monitor
                relativePos := AbsoluteToRelativePosition(x, y, width, height, sourceMonitorIndex)
                
                ; Convert relative position to absolute on target monitor
                absolutePos := RelativeToAbsolutePosition(
                    relativePos.relX, relativePos.relY, relativePos.relWidth, relativePos.relHeight, targetMonitor)
                
                newX := absolutePos.x
                newY := absolutePos.y
                newWidth := absolutePos.width
                newHeight := absolutePos.height
                LogMessage("Calculated relative position from current: new x=" newX ", y=" newY ", w=" newWidth ", h=" newHeight)
            }

            ; Move the window to target monitor
            try {
                WinMove(newX, newY, newWidth, newHeight, "ahk_id " activeHwnd)
            } catch Error as err {
                LogMessage("SendWindowToWorkspace: Error moving window: " err.Message)
            }

            ; Save the new layout
            SaveWindowLayout(activeHwnd, targetWorkspaceID)

            ; Activate the window to bring it to front
            WinActivate("ahk_id " activeHwnd)

            LogMessage("Moved window to monitor " targetMonitor " with workspace " targetWorkspaceID)
        } else {
            ; Target workspace not visible on any monitor - minimize the window
            LogMessage("Target workspace " targetWorkspaceID " is not visible - minimizing window")

            ; Minimize the window
            WinMinimize("ahk_id " activeHwnd)

            ; No need to save layout here as it was already saved at the beginning
        }


        LogMessage("Window successfully assigned to workspace " targetWorkspaceID)
        
        ; Save the workspace state after successful assignment
        SaveWorkspaceState()

        LogMessage("------------- SEND WINDOW TO WORKSPACE END -------------")
    } catch Error as err {
        LogMessage("ERROR in SendWindowToWorkspace: " err.Message)
    } finally {
        ; Always clear the switch in progress flag
        SWITCH_IN_PROGRESS := False
    }
}

SwitchToWorkspace(requestedID) { ; Changes active workspace on current monitor
    ; Reference global variables
    global SWITCH_IN_PROGRESS, MAX_WORKSPACES, MonitorWorkspaces, WindowWorkspaces, WorkspaceLayouts

    ; Early exit conditions
    if (requestedID < 1 || requestedID > MAX_WORKSPACES)
        return

    ; Check if another switch operation is already in progress
    if (SWITCH_IN_PROGRESS) {
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
        LogWorkspaceWindowContents("BEFORE SWITCH:")

        ; Get active monitor
        activeMonitor := GetActiveMonitor() ; Gets the monitor index that contains the currently active (focused) window
        LogMessage("Active monitor: " activeMonitor)

        ; Get current workspace ID for active monitor
        currentWorkspaceID := MonitorWorkspaces.Has(activeMonitor) ? MonitorWorkspaces[activeMonitor] : 1 ; Gets current workspace ID for active monitor, defaults to 1 if not found
        LogMessage("Current workspace on active monitor: " currentWorkspaceID)

        ; If already on requested workspace, do nothing
        if (currentWorkspaceID = requestedID) {
            LogMessage("Already on requested workspace. No action needed.")
            SWITCH_IN_PROGRESS := False ; Clear flag before early return
            return
        }

        ; Check if the requested workspace is already on another monitor - direct swap approach
        otherMonitor := 0
        for monIndex, workspaceID in MonitorWorkspaces {
            if (monIndex != activeMonitor && workspaceID = requestedID) {
                otherMonitor := monIndex
                LogMessage("Found requested workspace on monitor: " otherMonitor)
                break
            }
        }

        if (otherMonitor > 0) {
            ; === PERFORMING WORKSPACE EXCHANGE BETWEEN MONITORS ===
            LogMessage("Performing workspace exchange between monitors " activeMonitor " and " otherMonitor)

            ; Get monitor dimensions
            MonitorGetWorkArea(activeMonitor, &aLeft, &aTop, &aRight, &aBottom)
            MonitorGetWorkArea(otherMonitor, &oLeft, &oTop, &oRight, &oBottom)
            
            ; Calculate offset between monitors (to maintain relative positions)
            offsetX := aLeft - oLeft
            offsetY := aTop - oTop
            
            ; Get all open windows
            windows := WinGetList()
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
            
            LogMessage("Found " activeMonitorWindows.Length " windows on active monitor and " 
                otherMonitorWindows.Length " windows on other monitor")
            
            ; Step 1: Save all window layouts before switching
            LogMessage("Saving all window layouts before workspace exchange")
            
            ; Save layouts for windows on active monitor
            for index, hwnd in activeMonitorWindows {
                try {
                    SaveWindowLayout(hwnd, currentWorkspaceID)
                } catch Error as err {
                    LogMessage("ERROR saving layout for window: " err.Message)
                }
            }
            
            ; Save layouts for windows on other monitor
            for index, hwnd in otherMonitorWindows {
                try {
                    SaveWindowLayout(hwnd, requestedID)
                } catch Error as err {
                    LogMessage("ERROR saving layout for window: " err.Message)
                }
            }
            
            ; Step 2: Swap workspace IDs between monitors
            LogMessage("Swapping workspace IDs: " currentWorkspaceID " and " requestedID)
            MonitorWorkspaces[otherMonitor] := currentWorkspaceID
            MonitorWorkspaces[activeMonitor] := requestedID

            ; Update overlays immediately after changing workspace IDs
            UpdateAllOverlays()
            
            ; Step 3: Move windows from active monitor to other monitor using relative positioning
            for index, hwnd in activeMonitorWindows {
                try {
                    title := WinGetTitle(hwnd)
                    LogMessage("Moving window from active to other monitor: " title)
                    
                    ; Get current window state
                    isMaximized := WinGetMinMax(hwnd) = 1
                    
                    ; If maximized, restore first
                    if (isMaximized) {
                        WinRestore("ahk_id " hwnd)
                        Sleep(30)
                    }
                    
                    ; Get saved layout data
                    if (WorkspaceLayouts.Has(currentWorkspaceID) && 
                        WorkspaceLayouts[currentWorkspaceID].Has(hwnd)) {
                        
                        layout := WorkspaceLayouts[currentWorkspaceID][hwnd]
                        
                        ; Convert relative position to absolute position on the target monitor
                        absolutePos := RelativeToAbsolutePosition(
                            layout.relX, layout.relY, layout.relWidth, layout.relHeight, otherMonitor)
                        
                        ; Move window to new position
                        WinMove(absolutePos.x, absolutePos.y, absolutePos.width, absolutePos.height, "ahk_id " hwnd)
                        
                        LogMessage("Moved window using relative positioning to monitor " otherMonitor)
                    } else {
                        ; Fallback to centering if no layout data
                        MonitorGetWorkArea(otherMonitor, &mLeft, &mTop, &mRight, &mBottom)
                        WinGetPos(&x, &y, &width, &height, "ahk_id " hwnd)
                        centerX := mLeft + (mRight - mLeft - width) / 2
                        centerY := mTop + (mBottom - mTop - height) / 2
                        WinMove(centerX, centerY, width, height, "ahk_id " hwnd)
                        LogMessage("No layout data - centered window on monitor " otherMonitor)
                    }
                    
                    ; Maximize again if it was maximized
                    if (isMaximized) {
                        Sleep(30)
                        WinMaximize("ahk_id " hwnd)
                    }
                    
                    ; Save the new layout after moving
                    SaveWindowLayout(hwnd, currentWorkspaceID)
                    
                    Sleep(30) ; Short delay to prevent overwhelming the system
                } catch Error as err {
                    LogMessage("ERROR moving window: " err.Message)
                }
            }
            
            ; Step 4: Move windows from other monitor to active monitor using relative positioning
            for index, hwnd in otherMonitorWindows {
                try {
                    title := WinGetTitle(hwnd)
                    LogMessage("Moving window from other to active monitor: " title)
                    
                    ; Get current window state
                    isMaximized := WinGetMinMax(hwnd) = 1
                    
                    ; If maximized, restore first
                    if (isMaximized) {
                        WinRestore("ahk_id " hwnd)
                        Sleep(30)
                    }
                    
                    ; Get saved layout data
                    if (WorkspaceLayouts.Has(requestedID) && 
                        WorkspaceLayouts[requestedID].Has(hwnd)) {
                        
                        layout := WorkspaceLayouts[requestedID][hwnd]
                        
                        ; Convert relative position to absolute position on the target monitor
                        absolutePos := RelativeToAbsolutePosition(
                            layout.relX, layout.relY, layout.relWidth, layout.relHeight, activeMonitor)
                        
                        ; Move window to new position
                        WinMove(absolutePos.x, absolutePos.y, absolutePos.width, absolutePos.height, "ahk_id " hwnd)
                        
                        LogMessage("Moved window using relative positioning to monitor " activeMonitor)
                    } else {
                        ; Fallback to centering if no layout data
                        MonitorGetWorkArea(activeMonitor, &mLeft, &mTop, &mRight, &mBottom)
                        WinGetPos(&x, &y, &width, &height, "ahk_id " hwnd)
                        centerX := mLeft + (mRight - mLeft - width) / 2
                        centerY := mTop + (mBottom - mTop - height) / 2
                        WinMove(centerX, centerY, width, height, "ahk_id " hwnd)
                        LogMessage("No layout data - centered window on monitor " activeMonitor)
                    }
                    
                    ; Maximize again if it was maximized
                    if (isMaximized) {
                        Sleep(30)
                        WinMaximize("ahk_id " hwnd)
                    }
                    
                    ; Save the new layout after moving
                    SaveWindowLayout(hwnd, requestedID)
                    
                    Sleep(30) ; Short delay to prevent overwhelming the system
                } catch Error as err {
                    LogMessage("ERROR moving window: " err.Message)
                }
            }
            
            LogMessage("Moved windows between monitors while preserving layout")
        }
        else {
            ; === STANDARD WORKSPACE SWITCH (NO EXCHANGE) ===
            LogMessage("Standard workspace switch - no exchange needed")

            ; ====== STEP 1: Identify and minimize windows that don't belong to requested workspace ======
            ; Get all open windows
            windows := WinGetList() ; Gets a list of all open windows
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
                    LogMessage("MINIMIZING window (workspace " workspaceID ") on active monitor: " title)

                    ; Force the window to minimize
                    try {
                        WinMinimize("ahk_id " hwnd)
                        Sleep(50) ; Delay to allow minimize operation to complete
                    } catch Error as err {
                        LogMessage("ERROR minimizing window: " err.Message)
                    }
                }
            }

            ; ====== STEP 2: Change workspace ID for active monitor ======
            ; Update the workspace ID for the active monitor
            MonitorWorkspaces[activeMonitor] := requestedID
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
                        ; Try to use saved layout data with relative positioning
                        moved := false
                        
                        if (WorkspaceLayouts.Has(requestedID) && 
                            WorkspaceLayouts[requestedID].Has(hwnd)) {
                            
                            layout := WorkspaceLayouts[requestedID][hwnd]
                            
                            ; Convert relative position to absolute position on the active monitor
                            absolutePos := RelativeToAbsolutePosition(
                                layout.relX, layout.relY, layout.relWidth, layout.relHeight, activeMonitor)
                            
                            ; Move window to new position
                            WinMove(absolutePos.x, absolutePos.y, absolutePos.width, absolutePos.height, "ahk_id " hwnd)
                            
                            LogMessage("MOVING window from monitor " windowMonitor " to active monitor " activeMonitor " using relative positioning: " title)
                            moved := true
                        }
                        
                        ; Fallback to centering if no layout data
                        if (!moved) {
                            ; Get monitor dimensions
                            MonitorGetWorkArea(activeMonitor, &mLeft, &mTop, &mRight, &mBottom)

                            ; Get window size
                            WinGetPos(&x, &y, &width, &height, "ahk_id " hwnd)

                            ; Center window on active monitor
                            newX := mLeft + (mRight - mLeft - width) / 2
                            newY := mTop + (mBottom - mTop - height) / 2

                            ; Move window to active monitor
                            WinMove(newX, newY, width, height, "ahk_id " hwnd)

                            LogMessage("MOVING window from monitor " windowMonitor " to active monitor " activeMonitor " (centered): " title)
                        }
                    }

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

                                LogMessage("MOVED restored window to active monitor: " title)

                                Sleep(30) ; Allow time for the move operation to complete
                            }
                        } catch Error as moveErr {
                            LogMessage("ERROR moving window to correct monitor: " moveErr.Message)
                        }

                        ; Note: WindowWorkspaces is now updated by event handlers, not directly here
                        SaveWindowLayout(hwnd, requestedID)

                        restoreCount++
                        Sleep(30) ; Delay to allow operations to complete
                    } catch Error as err {
                        LogMessage("ERROR restoring window: " err.Message)
                    }
                }
            }

            LogMessage("Restored " restoreCount " windows for workspace " requestedID)
        }
    }
    catch Error as err {
        ; Log the error
        LogMessage("ERROR during workspace switch: " err.Message)
    }
    finally {
        ; Always update overlays to ensure they reflect the current workspace state,
        ; even if there was an error or early return in the switch logic
        UpdateAllOverlays()

        ; Log workspace window contents AFTER the switch
        LogWorkspaceWindowContents("AFTER SWITCH:")

        ; Log that the workspace switch is complete
        LogMessage("------------- WORKSPACE SWITCH END -------------")

        ; Always clear the switch in progress flag, even if there was an error
        SWITCH_IN_PROGRESS := False
    }
}

; Clean up stale window references to prevent memory leaks
CleanupWindowReferences() {
    ; Reference global variables
    global SCRIPT_EXITING, WindowWorkspaces, WorkspaceLayouts

    ; Skip if script is exiting
    if (SCRIPT_EXITING) {
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
        if (layoutStaleCount > 0) {
            LogMessage("Cleaned up " layoutStaleCount " stale layout entries for workspace " workspaceID)
            layoutTotalStaleCount += layoutStaleCount
        }
    }
    
    if (workspaceStaleCount > 0 || layoutTotalStaleCount > 0) {
        LogMessage("Cleaned up " workspaceStaleCount " workspace entries, and " layoutTotalStaleCount " layout entries")
        
        ; Save workspace state after cleanup
        SaveWorkspaceState()
    }
}

AssignNewWindow(hwnd) { ; Assigns a new window to appropriate workspace (delayed follow-up check)
    ; Reference global variables
    global MonitorWorkspaces, WindowWorkspaces

    ; Validate the hwnd parameter
    try {
        if (!hwnd || hwnd = 0) {
            LogMessage("AssignNewWindow: Invalid window handle (null or zero)")
            return
        }
    } catch Error as err {
        LogMessage("AssignNewWindow: Error validating handle parameter: " err.Message)
        return
    }

    ; Verify window still exists
    try {
        if (!WinExist("ahk_id " hwnd)) {
            LogMessage("AssignNewWindow: Window " hwnd " no longer exists")
            return
        }
    } catch Error as existErr {
        LogMessage("AssignNewWindow: Error checking window existence: " existErr.Message)
        return
    }

    ; Check again if the window exists and is valid - it might have closed already
    if (!IsWindowValid(hwnd)) {
        LogMessage("AssignNewWindow: Window " hwnd " is not valid")
        return
    }

    ; Get window info safely
    try {
        title := WinGetTitle("ahk_id " hwnd)
        class := WinGetClass("ahk_id " hwnd)

        LogMessage("Follow-up check for window - Title: " title ", Class: " class ", hwnd: " hwnd)
    } catch Error as err {
        LogMessage("Error getting window info in delayed check: " err.Message)
        return
    }

    ; Check the window's current monitor (it may have moved since initial creation)
    try {
        monitorIndex := GetWindowMonitor(hwnd) ; Gets which monitor the window is on now
        LogMessage("Window is now on monitor: " monitorIndex)
    } catch Error as err {
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
                LogMessage("Window assigned in delayed check to workspace " workspaceID " on monitor " monitorIndex)
                
                ; Save workspace state after new assignment
                SaveWorkspaceState()

                ; Check visibility
                currentWorkspaceID := MonitorWorkspaces[monitorIndex]
                if (workspaceID != currentWorkspaceID) {
                    try {
                        WinMinimize("ahk_id " hwnd)
                        LogMessage("Minimized window belonging to non-visible workspace (delayed check)")
                    } catch Error as minErr {
                        LogMessage("Error minimizing window in delayed check: " minErr.Message)
                    }
                }
            } catch Error as err {
                LogMessage("Error assigning window in delayed check: " err.Message)
            }
        } else {
            try {
                ; Verify the window still exists again before updating
                try {
                    if (!WinExist("ahk_id " hwnd)) {
                        LogMessage("AssignNewWindow: Window disappeared during processing")
                        return
                    }
                } catch Error as existErr {
                    LogMessage("AssignNewWindow: Error rechecking window: " existErr.Message)
                    return
                }

                ; Window already has workspace assignment, but may need updating if it moved monitors
                currentWorkspaceID := WindowWorkspaces[hwnd]
                
                ; IMPORTANT: Always save the layout, even for existing windows
                ; This ensures we always have layout data for relative positioning
                SaveWindowLayout(hwnd, currentWorkspaceID)
                LogMessage("Updated layout for existing window in workspace " currentWorkspaceID)

                ; If window's current workspace doesn't match its monitor's workspace, update it
                if (currentWorkspaceID != workspaceID) {
                    WindowWorkspaces[hwnd] := workspaceID
                    SaveWindowLayout(hwnd, workspaceID)
                    LogMessage("Updated window workspace from " currentWorkspaceID " to " workspaceID " (delayed check)")
                    
                    ; Save workspace state after update
                    SaveWorkspaceState()

                    ; Check if it needs to be minimized due to workspace mismatch
                    currentMonitorWorkspace := MonitorWorkspaces[monitorIndex]
                    if (workspaceID != currentMonitorWorkspace) {
                        try {
                            if (WinGetMinMax("ahk_id " hwnd) != -1) {
                                WinMinimize("ahk_id " hwnd)
                                LogMessage("Minimized moved window for workspace consistency (delayed check)")
                            }
                        } catch Error as minErr {
                            LogMessage("Error handling window minimization: " minErr.Message)
                        }
                    }
                }
            } catch Error as err {
                LogMessage("Error updating window workspace in delayed check: " err.Message)
            }
        }
    } else {
        ; Default to unassigned if monitor has no workspace
        try {
            ; Verify window still exists
            if (WinExist("ahk_id " hwnd)) {
                WindowWorkspaces[hwnd] := 0
                LogMessage("Assigned window to unassigned workspace (0) - monitor not tracked (delayed check)")
                
                ; Save workspace state after assignment
                SaveWorkspaceState()
            }
        } catch Error as err {
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

RefreshMonitorConfiguration() { ; Refreshes overlays and monitor workspaces when monitors are connected/disconnected
    ; Reference global variables
    global MonitorWorkspaces, WorkspaceOverlays, BorderOverlay, BORDER_VISIBLE, LAST_ACTIVE_MONITOR, MAX_WORKSPACES
    
    LogMessage("============ REFRESHING MONITOR CONFIGURATION ============")
    
    ; Get current monitor count
    newMonitorCount := MonitorGetCount()
    oldMonitorCount := MonitorWorkspaces.Count
    
    LogMessage("Monitor count - Old: " oldMonitorCount ", New: " newMonitorCount)
    
    ; Step 1: Destroy all existing overlays
    LogMessage("Destroying existing overlays...")
    
    ; Destroy workspace overlays
    for monitorIndex, overlay in WorkspaceOverlays {
        try {
            overlay.Destroy()
            LogMessage("Destroyed workspace overlay for monitor " monitorIndex)
        } catch Error as err {
            LogMessage("Error destroying workspace overlay: " err.Message)
        }
    }
    WorkspaceOverlays := Map()
    
    ; Destroy border overlays
    for monitorIndex, edges in BorderOverlay {
        for edge, gui in edges {
            try {
                gui.Destroy()
            } catch Error as err {
                LogMessage("Error destroying border overlay: " err.Message)
            }
        }
    }
    BorderOverlay := Map()
    
    ; Step 2: Update MonitorWorkspaces mapping
    LogMessage("Updating MonitorWorkspaces mapping...")
    
    ; Create a new map for monitor workspaces
    newMonitorWorkspaces := Map()
    
    ; Preserve existing workspace assignments where possible
    loop newMonitorCount {
        monitorIndex := A_Index
        
        ; If this monitor had a workspace assignment before, preserve it
        if (MonitorWorkspaces.Has(monitorIndex)) {
            newMonitorWorkspaces[monitorIndex] := MonitorWorkspaces[monitorIndex]
            LogMessage("Preserved workspace " MonitorWorkspaces[monitorIndex] " for monitor " monitorIndex)
        } else {
            ; Assign new monitors to their index as workspace (or 1 if index > MAX_WORKSPACES)
            if (monitorIndex <= MAX_WORKSPACES) {
                newMonitorWorkspaces[monitorIndex] := monitorIndex
            } else {
                newMonitorWorkspaces[monitorIndex] := 1
            }
            LogMessage("Assigned new monitor " monitorIndex " to workspace " newMonitorWorkspaces[monitorIndex])
        }
    }
    
    ; Replace the old mapping
    MonitorWorkspaces := newMonitorWorkspaces
    
    ; Step 3: Recreate all overlays
    LogMessage("Recreating overlays for " newMonitorCount " monitors...")
    
    ; Create workspace overlays for each monitor
    loop newMonitorCount {
        monitorIndex := A_Index
        CreateOverlay(monitorIndex)
        LogMessage("Created workspace overlay for monitor " monitorIndex)
    }
    
    ; Create border overlays for all monitors
    InitializeMonitorBorders()
    
    ; Step 4: Update overlay display
    UpdateAllOverlays()
    
    ; Reset last active monitor to force border update
    LAST_ACTIVE_MONITOR := 0
    UpdateActiveMonitorBorder()
    
    ; Show a notification
    TrayTip("Monitor Configuration Refreshed", "Detected " newMonitorCount " monitors")
    
    LogMessage("============ MONITOR REFRESH COMPLETE ============")
}

InitializeMonitorBorders() { ; Creates border overlays for all monitors
    ; Reference global variables
    global BorderOverlay, BORDER_COLOR, BORDER_THICKNESS

    ; Clear any existing border overlays
    for _, overlay in BorderOverlay {
        try {
            overlay.Destroy()
        } catch Error as err {
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

        LogMessage("Added " windowCount " windows to workspace list")
    } catch Error as err {
        LogMessage("Error gathering window information: " err.Message)
    }

    ; Check the window counts for debugging
    if (DEBUG_MODE) {
        totalWindows := 0
        for i in [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19] {
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
    global MAX_WORKSPACES, WindowWorkspaces, DEBUG_MODE

    if (!DEBUG_MODE)
        return

    ; Get window information
    windowsByWorkspace := GetWorkspaceWindowInfo()

    ; Start log message
    LogMessage(prefix " ===== WORKSPACE WINDOW CONTENTS =====")

    ; Log each workspace's windows
    totalWindows := 0
    for workspaceID in [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19] {
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
    global BorderOverlay
    try {
        if (BorderOverlay.Has(monitorIndex)) {
            edges := BorderOverlay[monitorIndex]

            for edge, gui in edges {
                gui.Show("NoActivate")
            }
        }
    } catch Error as err {
        LogMessage("Error showing monitor border: " err.Message)
    }
}

HideMonitorBorder(monitorIndex) { ; Hides the border for a specific monitor
    ; Reference global variables
    global BorderOverlay
    try {
        if (BorderOverlay.Has(monitorIndex)) {
            edges := BorderOverlay[monitorIndex]

            for edge, gui in edges {
                gui.Hide()
            }

            LogMessage("Hid border for monitor " monitorIndex)
        }
    } catch Error as err {
        LogMessage("Error hiding monitor border: " err.Message)
    }
}

UpdateActiveMonitorBorder() { ; Updates the active monitor border based on current mouse position
    ; Reference global variables
    global LAST_ACTIVE_MONITOR, BORDER_VISIBLE

    ; If borders are toggled off, do nothing
    if (!BORDER_VISIBLE)
        return

    ; Get current active monitor based on mouse position
    currentMonitor := GetActiveMonitor()

    ; Check if we need to update the border
    if (currentMonitor != LAST_ACTIVE_MONITOR || LAST_ACTIVE_MONITOR == 0) {
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
    global BorderOverlay, BORDER_VISIBLE, LAST_ACTIVE_MONITOR

    ; Toggle the visibility state
    BORDER_VISIBLE := !BORDER_VISIBLE

    LogMessage("Monitor borders toggled: " (BORDER_VISIBLE ? "ON" : "OFF"))

    if (BORDER_VISIBLE) {
        ; Get the current active monitor
        currentMonitor := GetActiveMonitor()

        ; Force show active monitor border regardless of whether it has changed
        ShowMonitorBorder(currentMonitor)

        ; Update last active monitor
        LAST_ACTIVE_MONITOR := currentMonitor

        LogMessage("Showing border for monitor " currentMonitor)
    } else {
        ; Hide all borders
        for monitorIndex in BorderOverlay {
            HideMonitorBorder(monitorIndex)
        }
    }
}

; ----- Dialog Functions -----

ShowInstructionsDialog() {
    ; Update window workspace assignments before showing dialog
    CleanupWindowReferences()
    
    ; Create instructions dialog
    dlg := Gui("+AlwaysOnTop +OwnDialogs")
    dlg.Opt("+SysMenu")
    dlg.Title := "Cerberus v" . APP_VERSION
    
    ; Add instructions text
    dlg.SetFont("s9", "Segoe UI")
    dlg.Add("Text", "w382", "Cerberus Instructions:")
    dlg.Add("Text", "w382 y+0", "Press Ctrl+1 through Ctrl+9 to switch to workspaces 1-9.")
    dlg.Add("Text", "w382 y+0", "Press Ctrl+Alt+0 through Ctrl+Alt+9 to switch to workspaces 10-19.")
    dlg.Add("Text", "w382 y+0", "Press Ctrl+Shift+[Number] to send window to workspaces 1-9.")
    dlg.Add("Text", "w382 y+0", "Press Ctrl+Shift+Alt+[Number] to send window to workspaces 10-19.")
    dlg.Add("Text", "w382 y+0", "Press Ctrl+0 to toggle workspace number overlays and monitor border.")
    dlg.Add("Text", "w382 y+0", "Press Alt+Shift+R to refresh overlays when monitors are connected/disconnected.")
    dlg.Add("Text", "w382 y+0", "Press Ctrl+Alt+H to show this help dialog.")
    dlg.Add("Text", "w382 y+0", "Press Ctrl+` to show window workspace map.")
    dlg.Add("Text", "w382 y+0", "Active monitor (based on mouse position) is highlighted with a border.")
    
    ; Add OK button
    buttonContainer := dlg.Add("Text", "w382 h1 Center y+15")
    dlg.Add("Button", "Default w80 Section xp+151 yp+0", "OK").OnEvent("Click", (*) => dlg.Destroy())
    
    ; Show dialog
    dlg.Show()
}

ShowWorkspaceMapDialog() {
    ; Update window workspace assignments before showing dialog
    CleanupWindowReferences()
    
    ; Create dialog
    dlg := Gui("+AlwaysOnTop +OwnDialogs +Resize")
    dlg.Opt("+SysMenu")
    dlg.Title := "Cerberus Workspace Map - v" . APP_VERSION
    
    ; Make dialog larger to accommodate window list
    dlg.SetFont("s9", "Segoe UI")
    
    ; Add instructions at the top
    dlg.Add("Text", "w600", "=== INSTRUCTIONS ===")
    dlg.Add("Text", "w600 y+5", "• Ctrl+1-9: Switch to workspace 1-9")
    dlg.Add("Text", "w600 y+0", "• Ctrl+Alt+0-9: Switch to workspace 10-19")
    dlg.Add("Text", "w600 y+0", "• Ctrl+Shift+[Number]: Send window to workspace")
    dlg.Add("Text", "w600 y+0", "• Ctrl+0: Toggle overlays | Alt+Shift+R: Refresh | Ctrl+Alt+H: Help | Ctrl+`: This dialog")
    
    dlg.Add("Text", "w600 y+10", "=== CURRENT WINDOW-WORKSPACE ASSIGNMENTS ===")
    
    ; Build workspace map text
    workspaceMap := Map()
    
    ; Group windows by workspace
    for hwnd, workspaceID in WindowWorkspaces {
        try {
            if (!WinExist("ahk_id " hwnd))
                continue
                
            title := WinGetTitle(hwnd)
            if (title = "")
                continue
                
            ; Truncate long titles
            if (StrLen(title) > 60)
                title := SubStr(title, 1, 57) . "..."
                
            if (!workspaceMap.Has(workspaceID))
                workspaceMap[workspaceID] := []
                
            workspaceMap[workspaceID].Push(title)
        } catch {
            ; Skip windows that can't be accessed
        }
    }
    
    ; Create scrollable text area for window list
    editControl := dlg.Add("Edit", "w600 h400 ReadOnly VScroll")
    mapText := ""
    
    ; Add monitor workspace assignments
    mapText .= "MONITOR ASSIGNMENTS:`n"
    monitorCount := MonitorGetCount()
    loop monitorCount {
        if (MonitorWorkspaces.Has(A_Index)) {
            mapText .= "  Monitor " . A_Index . " → Workspace " . MonitorWorkspaces[A_Index] . "`n"
        }
    }
    mapText .= "`n"
    
    ; Sort workspaces numerically
    sortedWorkspaces := []
    for workspaceID in workspaceMap {
        sortedWorkspaces.Push(workspaceID)
    }
    
    ; Simple bubble sort for numeric sorting
    loop sortedWorkspaces.Length - 1 {
        i := A_Index
        loop sortedWorkspaces.Length - i {
            j := A_Index
            if (sortedWorkspaces[j] > sortedWorkspaces[j + 1]) {
                temp := sortedWorkspaces[j]
                sortedWorkspaces[j] := sortedWorkspaces[j + 1]
                sortedWorkspaces[j + 1] := temp
            }
        }
    }
    
    ; Display windows by workspace
    for workspaceID in sortedWorkspaces {
        windows := workspaceMap[workspaceID]
        
        if (workspaceID = 0) {
            mapText .= "UNASSIGNED WINDOWS:`n"
        } else {
            ; Check if workspace is visible on any monitor
            visibleOn := ""
            for monIndex, wsID in MonitorWorkspaces {
                if (wsID = workspaceID) {
                    visibleOn .= (visibleOn = "" ? "" : ", ") . "Monitor " . monIndex
                }
            }
            
            mapText .= "WORKSPACE " . workspaceID
            if (visibleOn != "") {
                mapText .= " (visible on " . visibleOn . ")"
            }
            mapText .= ":`n"
        }
        
        for windowTitle in windows {
            mapText .= "  • " . windowTitle . "`n"
        }
        mapText .= "`n"
    }
    
    ; Add empty workspaces
    loop MAX_WORKSPACES {
        if (!workspaceMap.Has(A_Index)) {
            ; Check if workspace is visible
            visibleOn := ""
            for monIndex, wsID in MonitorWorkspaces {
                if (wsID = A_Index) {
                    visibleOn .= (visibleOn = "" ? "" : ", ") . "Monitor " . monIndex
                }
            }
            
            if (visibleOn != "") {
                mapText .= "WORKSPACE " . A_Index . " (visible on " . visibleOn . "): [Empty]`n`n"
            }
        }
    }
    
    editControl.Text := mapText
    
    ; Add close button
    dlg.Add("Button", "Default w80 x260 y+10", "Close").OnEvent("Click", (*) => dlg.Destroy())
    
    ; Show dialog
    dlg.Show()
}

; ====== Configuration ======
MAX_WORKSPACES := 19  ; Maximum number of workspaces (1-19)
MAX_MONITORS := 9    ; Maximum number of monitors (adjust as needed)

; ====== Global Variables ======
; ===== DEBUG SETTINGS =====
; Set this to True to enable detailed logging for troubleshooting
global DEBUG_MODE := True  ; Change to True to enable debugging
global LOG_TO_FILE := False  ; Set to True to log to file instead of Debug output
global LOG_FILE := A_ScriptDir "\cerberus.log"  ; Path to log file
global SHOW_WINDOW_EVENT_TOOLTIPS := False  ; Set to False to hide tooltips for window events
global SHOW_TRAY_NOTIFICATIONS := False  ; Set to True to show tray notifications for window events

; ===== PERSISTENCE SETTINGS =====
; Configuration directory and file for saving workspace state
global CONFIG_DIR := A_ScriptDir "\config"
global WORKSPACE_STATE_FILE := CONFIG_DIR "\workspace_state.json"

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
    global SCRIPT_EXITING, WorkspaceOverlays, WindowListOverlay, WindowListVisible

    ; Set flag to prevent handlers from running during exit
    SCRIPT_EXITING := True

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
        LogMessage("Error cleaning up window list overlay: " err.Message)
    }
    
    ; Clean up any open tool tips
    ToolTip()
    
    ; Clean up static maps in handlers to prevent memory leaks
    try {
        ; Clean global maps to release references to window handles
        WindowWorkspaces := Map()
        WorkspaceLayouts := Map()
    } catch Error as err {
        LogMessage("Error cleaning up handler static variables: " err.Message)
    }
    
    ; Log successful exit
    LogMessage("Successfully cleaned up resources, script terminating cleanly")
    try {
        ; Hide all workspace overlays
        for monitorIndex, overlay in WorkspaceOverlays {
            try overlay.Destroy()
            catch Error as err {
                LogMessage("Error destroying workspace overlay: " err.Message)
            }
        }

        ; Hide workspace window list if visible
        if (WindowListOverlay && WinExist("ahk_id " WindowListOverlay.Hwnd)) {
            try WindowListOverlay.Destroy()
            catch Error as err {
                LogMessage("Error destroying window list overlay: " err.Message)
            }
        }

        ; Clean up monitor borders
        for monitorIndex, edges in BorderOverlay {
            for edge, gui in edges {
                try gui.Destroy()
                catch Error as err {
                    LogMessage("Error destroying border: " err.Message)
                }
            }
        }
    } catch Error as err {
        LogMessage("Error in cleanup: " err.Message)
    }

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
; Show the instructions dialog using the reusable function
ShowInstructionsDialog()

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
    global SCRIPT_EXITING, BORDER_VISIBLE
    ; Skip if script is exiting
    if (SCRIPT_EXITING) {
        LogMessage("Script is exiting, ignoring mouse movement check")
        return
    }

    ; Only check for active monitor updates when border is visible
    if (BORDER_VISIBLE) {
        try {
            UpdateActiveMonitorBorder()
        } catch Error as err {
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

; Ctrl+Alt+0 through Ctrl+Alt+9 for switching to workspaces 10-19
^!0::SwitchToWorkspace(10) ; Ctrl+Alt+0 hotkey to switch to workspace 10
^!1::SwitchToWorkspace(11) ; Ctrl+Alt+1 hotkey to switch to workspace 11
^!2::SwitchToWorkspace(12) ; Ctrl+Alt+2 hotkey to switch to workspace 12
^!3::SwitchToWorkspace(13) ; Ctrl+Alt+3 hotkey to switch to workspace 13
^!4::SwitchToWorkspace(14) ; Ctrl+Alt+4 hotkey to switch to workspace 14
^!5::SwitchToWorkspace(15) ; Ctrl+Alt+5 hotkey to switch to workspace 15
^!6::SwitchToWorkspace(16) ; Ctrl+Alt+6 hotkey to switch to workspace 16
^!7::SwitchToWorkspace(17) ; Ctrl+Alt+7 hotkey to switch to workspace 17
^!8::SwitchToWorkspace(18) ; Ctrl+Alt+8 hotkey to switch to workspace 18
^!9::SwitchToWorkspace(19) ; Ctrl+Alt+9 hotkey to switch to workspace 19

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

; Ctrl+Shift+Alt+0 through Ctrl+Shift+Alt+9 for sending active window to workspaces 10-19
^+!0::SendWindowToWorkspace(10) ; Ctrl+Shift+Alt+0 hotkey to send active window to workspace 10
^+!1::SendWindowToWorkspace(11) ; Ctrl+Shift+Alt+1 hotkey to send active window to workspace 11
^+!2::SendWindowToWorkspace(12) ; Ctrl+Shift+Alt+2 hotkey to send active window to workspace 12
^+!3::SendWindowToWorkspace(13) ; Ctrl+Shift+Alt+3 hotkey to send active window to workspace 13
^+!4::SendWindowToWorkspace(14) ; Ctrl+Shift+Alt+4 hotkey to send active window to workspace 14
^+!5::SendWindowToWorkspace(15) ; Ctrl+Shift+Alt+5 hotkey to send active window to workspace 15
^+!6::SendWindowToWorkspace(16) ; Ctrl+Shift+Alt+6 hotkey to send active window to workspace 16
^+!7::SendWindowToWorkspace(17) ; Ctrl+Shift+Alt+7 hotkey to send active window to workspace 17
^+!8::SendWindowToWorkspace(18) ; Ctrl+Shift+Alt+8 hotkey to send active window to workspace 18
^+!9::SendWindowToWorkspace(19) ; Ctrl+Shift+Alt+9 hotkey to send active window to workspace 19

; Ctrl+0 to toggle workspace overlays and monitor border
^0::ToggleBordersAndOverlays() ; Ctrl+0 hotkey to show/hide workspace overlays and monitor border

; Alt+Shift+R to refresh monitor configuration
!+r::RefreshMonitorConfiguration() ; Alt+Shift+R hotkey to refresh overlays when monitors are connected/disconnected

; Ctrl+Alt+H to show help/instructions dialog
^!h::ShowInstructionsDialog() ; Ctrl+Alt+H hotkey to show instructions dialog

; Ctrl+` to show window workspace map dialog
^`::ShowWorkspaceMapDialog() ; Ctrl+` hotkey to show window workspace map

; Function to toggle both workspace overlays and monitor borders with Ctrl+0
ToggleBordersAndOverlays() {
    ; Toggle workspace number overlays
    ToggleOverlays()

    ; Toggle monitor borders separately
    ToggleMonitorBorders()
}
