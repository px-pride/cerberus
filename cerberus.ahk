#Requires AutoHotkey v2.0
#SingleInstance Force

TraySetIcon("cerberus.ico")

global VERSION := "1.0.3"
global MAX_WORKSPACES := 20
global TASK_NAME := "CerberusWM"
global LAST_STATE_SAVE_TIME := 0

global DEBUG_MODE := True
global LOG_TO_FILE := True
global LOGS_DIR := A_ScriptDir "\logs"
global LOG_FILE := ""
global SHOW_WINDOW_EVENT_TOOLTIPS := True
global SHOW_TRAY_NOTIFICATIONS := True

global CONFIG_DIR := A_ScriptDir "\config"
global WORKSPACE_STATE_FILE := CONFIG_DIR "\workspace_state.json"

global OVERLAY_SIZE := 60

; Store app launcher mappings
global STORE_APP_LAUNCHERS := Map(
    "WindowsTerminal.exe", "wt.exe",
    "Calculator.exe", "calc.exe",
    "Photos.exe", "ms-photos:",
    "Mail.exe", "outlookmail:",
    "Calendar.exe", "outlookcal:",
    "Microsoft.Msn.Weather.exe", "ms-weather:",
    "Spotify.exe", "spotify:",
    "WhatsApp.exe", "whatsapp:",
    "Slack.exe", "slack:",
    "MicrosoftEdge.exe", "msedge.exe"
)
global OVERLAY_MARGIN := 20
global OVERLAY_TIMEOUT := 0
global OVERLAY_OPACITY := 220
global OVERLAY_POSITION := "BottomRight"
global BORDER_COLOR := "33FFFF"
global BORDER_THICKNESS := 3

global MonitorWorkspaces := Map()
global WindowWorkspaces := Map()
global WorkspaceLayouts := Map()
global WorkspaceOverlays := Map()
global WorkspaceNameOverlays := Map()
global BorderOverlay := Map()
global WorkspaceNames := Map()
global WindowZOrder := Map()

global SWITCH_IN_PROGRESS := False
global SCRIPT_EXITING := False
global BORDER_VISIBLE := True
global LAST_ACTIVE_MONITOR := 0

InitializeLogging() {
    global LOGS_DIR, LOG_FILE, VERSION
    
    ; Create logs directory if it doesn't exist
    if (!DirExist(LOGS_DIR)) {
        DirCreate(LOGS_DIR)
    }
    
    ; Create session-based log filename
    sessionTime := FormatTime(, "yyyy-MM-dd_HH-mm-ss")
    LOG_FILE := LOGS_DIR "\cerberus_" sessionTime ".log"
    
    ; Write initial log entry
    LogDebug("========================================")
    LogDebug("Cerberus v" VERSION " Session Started")
    LogDebug("Log file: " LOG_FILE)
    LogDebug("========================================")
}

LogDebug(msg) {
    global DEBUG_MODE, LOG_TO_FILE, LOG_FILE
    if (!DEBUG_MODE) {
        return
    }
    
    timestamp := FormatTime(, "yyyy-MM-dd HH:mm:ss.000")
    fullMsg := timestamp " - " msg
    
    if (LOG_TO_FILE && LOG_FILE) {
        try {
            FileAppend(fullMsg "`n", LOG_FILE)
        }
    } else {
        OutputDebug(fullMsg)
    }
}

IsValidWindow(hwnd) {
    if (!hwnd || !WinExist(hwnd)) {
        return false
    }
    
    try {
        title := WinGetTitle(hwnd)
        winClass := WinGetClass(hwnd)
        
        if (!title || !winClass) {
            return false
        }
        
        skipClasses := ["Progman", "Shell_TrayWnd", "WorkerW", "TaskListThumbnailWnd", 
                       "TaskManagerWindow", "Windows.UI.Core.CoreWindow", "NotifyIconOverflowWindow"]
        
        for skipClass in skipClasses {
            if (winClass == skipClass) {
                return false
            }
        }
        
        style := WinGetStyle(hwnd)
        exStyle := WinGetExStyle(hwnd)
        
        if (!(style & 0x10000000)) {
            return false
        }
        
        if ((exStyle & 0x00000080) && !(exStyle & 0x00040000)) {
            return false
        }
        
        if (style & 0x40000000) {
            parent := DllCall("GetParent", "Ptr", hwnd, "Ptr")
            if (parent) {
                return false
            }
        }
        
        return true
    } catch {
        return false
    }
}

GetActiveMonitor() {
    global LAST_ACTIVE_MONITOR
    
    CoordMode("Mouse", "Screen")
    MouseGetPos(&mx, &my)
    
    monitorCount := MonitorGetCount()
    Loop monitorCount {
        ; Use MonitorGet to include taskbar area
        MonitorGet(A_Index, &left, &top, &right, &bottom)
        if (mx >= left && mx < right && my >= top && my < bottom) {
            return A_Index
        }
    }
    
    ; If no monitor matched (cursor outside all monitors), return last known active monitor
    if (LAST_ACTIVE_MONITOR > 0 && LAST_ACTIVE_MONITOR <= monitorCount) {
        return LAST_ACTIVE_MONITOR
    }
    
    ; Fallback to primary only if we have no valid last active monitor
    return MonitorGetPrimary()
}

GetMonitorForWindow(hwnd) {
    try {
        WinGetPos(&x, &y, &w, &h, hwnd)
        centerX := x + (w // 2)
        centerY := y + (h // 2)
        
        monitorCount := MonitorGetCount()
        Loop monitorCount {
            MonitorGetWorkArea(A_Index, &left, &top, &right, &bottom)
            if (centerX >= left && centerX < right && centerY >= top && centerY < bottom) {
                return A_Index
            }
        }
    } catch {
        LogDebug("Error getting monitor for window: " hwnd)
    }
    return 0
}

; Window placement functions to fix maximize/unmaximize position cache
GetWindowPlacement(hwnd) {
    ; WINDOWPLACEMENT structure is 44 bytes
    wp := Buffer(44, 0)
    NumPut("UInt", 44, wp, 0)  ; Set structure size
    
    if (!DllCall("GetWindowPlacement", "Ptr", hwnd, "Ptr", wp)) {
        LogDebug("GetWindowPlacement failed for hwnd: " hwnd)
        return false
    }
    
    ; Return object with placement data
    return {
        showCmd: NumGet(wp, 8, "UInt"),
        minPosX: NumGet(wp, 12, "Int"),
        minPosY: NumGet(wp, 16, "Int"),
        maxPosX: NumGet(wp, 20, "Int"),
        maxPosY: NumGet(wp, 24, "Int"),
        left: NumGet(wp, 28, "Int"),
        top: NumGet(wp, 32, "Int"),
        right: NumGet(wp, 36, "Int"),
        bottom: NumGet(wp, 40, "Int")
    }
}

SetWindowPlacementEx(hwnd, x, y, width, height, showCmd := 0) {
    ; WINDOWPLACEMENT structure is 44 bytes
    wp := Buffer(44, 0)
    NumPut("UInt", 44, wp, 0)  ; Set structure size
    
    ; Get current placement to preserve minimize/maximize positions
    if (!DllCall("GetWindowPlacement", "Ptr", hwnd, "Ptr", wp)) {
        LogDebug("GetWindowPlacement failed in SetWindowPlacementEx for hwnd: " hwnd)
        return false
    }
    
    ; Update show command if specified
    if (showCmd > 0) {
        NumPut("UInt", showCmd, wp, 8)
    }
    
    ; Update normal position (restored window position)
    NumPut("Int", x, wp, 28)           ; left
    NumPut("Int", y, wp, 32)           ; top
    NumPut("Int", x + width, wp, 36)  ; right
    NumPut("Int", y + height, wp, 40) ; bottom
    
    ; Set the window placement
    if (!DllCall("SetWindowPlacement", "Ptr", hwnd, "Ptr", wp)) {
        LogDebug("SetWindowPlacement failed for hwnd: " hwnd)
        return false
    }
    
    LogDebug("SetWindowPlacement succeeded for hwnd " hwnd " at " x "," y " " width "x" height)
    return true
}

; Wrapper function that moves window and updates placement cache
MoveWindowWithPlacement(hwnd, x, y, width, height) {
    try {
        ; Get current window state
        minMax := WinGetMinMax(hwnd)
        
        if (minMax == 1) {
            ; Window is maximized - restore, move, and re-maximize
            WinRestore(hwnd)
            SetWindowPlacementEx(hwnd, x, y, width, height, 9)  ; 9 = SW_RESTORE
            WinMove(x, y, width, height, hwnd)
            WinMaximize(hwnd)
        } else if (minMax == -1) {
            ; Window is minimized - just update placement
            SetWindowPlacementEx(hwnd, x, y, width, height)
        } else {
            ; Window is normal - update placement and move
            SetWindowPlacementEx(hwnd, x, y, width, height, 9)  ; 9 = SW_RESTORE
            WinMove(x, y, width, height, hwnd)
        }
        
        return true
    } catch as e {
        LogDebug("MoveWindowWithPlacement error: " e.Message)
        return false
    }
}

AbsoluteToRelativePosition(x, y, w, h, monitorIndex) {
    MonitorGetWorkArea(monitorIndex, &left, &top, &right, &bottom)
    monitorWidth := right - left
    monitorHeight := bottom - top
    
    return {
        xPercent: (x - left) / monitorWidth,
        yPercent: (y - top) / monitorHeight,
        widthPercent: w / monitorWidth,
        heightPercent: h / monitorHeight
    }
}

RelativeToAbsolutePosition(layout, monitorIndex) {
    MonitorGetWorkArea(monitorIndex, &left, &top, &right, &bottom)
    monitorWidth := right - left
    monitorHeight := bottom - top
    
    ; Handle both Map (from JSON) and Object (from AbsoluteToRelativePosition)
    if (layout is Map) {
        return {
            x: left + (layout["xPercent"] * monitorWidth),
            y: top + (layout["yPercent"] * monitorHeight),
            width: layout["widthPercent"] * monitorWidth,
            height: layout["heightPercent"] * monitorHeight
        }
    } else {
        return {
            x: left + (layout.xPercent * monitorWidth),
            y: top + (layout.yPercent * monitorHeight),
            width: layout.widthPercent * monitorWidth,
            height: layout.heightPercent * monitorHeight
        }
    }
}

UpdateWindowMaps() {
    global MonitorWorkspaces, WindowWorkspaces, WorkspaceLayouts
    
    LogDebug("UpdateWindowMaps: Called - Stack trace:")
    LogDebug("  Called from: " A_LineFile ":" A_LineNumber)
    
    ; Log windows on hidden workspaces before processing
    hiddenWindowCount := 0
    for hwnd, wsId in WindowWorkspaces {
        isHidden := true
        for monIdx, monWsId in MonitorWorkspaces {
            if (monWsId == wsId) {
                isHidden := false
                break
            }
        }
        if (isHidden) {
            try {
                title := WinGetTitle(hwnd)
                LogDebug("UpdateWindowMaps: Window on hidden workspace " wsId " BEFORE processing: " title)
                hiddenWindowCount++
            } catch {
            }
        }
    }
    LogDebug("UpdateWindowMaps: " hiddenWindowCount " windows on hidden workspaces before processing")
    
    ; Build a set of visible workspaces for quick lookup
    visibleWorkspaces := Map()
    for monIdx, wsId in MonitorWorkspaces {
        if (wsId > 0) {
            visibleWorkspaces[wsId] := monIdx
        }
    }
    
    ; Process all windows
    windows := WinGetList()
    for hwnd in windows {
        if (!IsValidWindow(hwnd)) {
            continue
        }
        
        try {
            minMax := WinGetMinMax(hwnd)
            
            ; If window is minimized
            if (minMax == -1) {
                ; If it's assigned to a visible workspace, unassign it
                if (WindowWorkspaces.Has(hwnd)) {
                    wsId := WindowWorkspaces[hwnd]
                    if (visibleWorkspaces.Has(wsId)) {
                        WindowWorkspaces.Delete(hwnd)
                        if (WorkspaceLayouts.Has(wsId)) {
                            WorkspaceLayouts[wsId].Delete(hwnd)
                        }
                        try {
                            title := WinGetTitle(hwnd)
                            LogDebug("UpdateWindowMaps: Unassigned minimized window '" title "' from visible workspace " wsId)
                        } catch {
                            LogDebug("UpdateWindowMaps: Unassigned minimized window " hwnd " from visible workspace " wsId)
                        }
                    }
                }
            } else {
                ; Window is open - assign it to its current monitor's workspace
                currentMonitor := GetMonitorForWindow(hwnd)
                if (currentMonitor > 0 && MonitorWorkspaces.Has(currentMonitor)) {
                    targetWorkspace := MonitorWorkspaces[currentMonitor]
                    if (targetWorkspace > 0) {
                        ; Check if reassignment is needed
                        needsReassignment := !WindowWorkspaces.Has(hwnd) || WindowWorkspaces[hwnd] != targetWorkspace
                        
                        if (needsReassignment) {
                            ; Remove from old workspace if exists
                            if (WindowWorkspaces.Has(hwnd)) {
                                oldWorkspace := WindowWorkspaces[hwnd]
                                if (WorkspaceLayouts.Has(oldWorkspace)) {
                                    WorkspaceLayouts[oldWorkspace].Delete(hwnd)
                                }
                            }
                            
                            ; Assign to new workspace
                            WindowWorkspaces[hwnd] := targetWorkspace
                            try {
                                title := WinGetTitle(hwnd)
                                LogDebug("UpdateWindowMaps: Assigned window '" title "' to workspace " targetWorkspace)
                            } catch {
                                LogDebug("UpdateWindowMaps: Assigned window " hwnd " to workspace " targetWorkspace)
                            }
                        }
                        
                        ; Update layout information
                        if (!WorkspaceLayouts.Has(targetWorkspace)) {
                            WorkspaceLayouts[targetWorkspace] := Map()
                        }
                        
                        WinGetPos(&x, &y, &w, &h, hwnd)
                        relPos := AbsoluteToRelativePosition(x, y, w, h, currentMonitor)
                        
                        WorkspaceLayouts[targetWorkspace][hwnd] := {
                            xPercent: relPos.xPercent,
                            yPercent: relPos.yPercent,
                            widthPercent: relPos.widthPercent,
                            heightPercent: relPos.heightPercent,
                            state: minMax
                        }
                    }
                }
            }
        } catch {
            LogDebug("Error processing window: " hwnd)
        }
    }
    
    SaveWorkspaceState()
}

CreateWorkspaceOverlay(monitorIndex, workspaceId) {
    global WorkspaceOverlays, OVERLAY_SIZE, OVERLAY_MARGIN, OVERLAY_POSITION, OVERLAY_OPACITY, BORDER_COLOR, BORDER_THICKNESS
    
    LogDebug("CreateWorkspaceOverlay: Creating overlay for monitor " monitorIndex " with workspace " workspaceId)
    
    if (WorkspaceOverlays.Has(monitorIndex)) {
        try {
            ; Destroy both border and main overlay if they exist
            if (WorkspaceOverlays[monitorIndex].HasOwnProp("border") && WorkspaceOverlays[monitorIndex].border) {
                WorkspaceOverlays[monitorIndex].border.Destroy()
            }
            if (WorkspaceOverlays[monitorIndex].HasOwnProp("main") && WorkspaceOverlays[monitorIndex].main) {
                WorkspaceOverlays[monitorIndex].main.Destroy()
            }
            LogDebug("CreateWorkspaceOverlay: Destroyed existing overlay for monitor " monitorIndex)
        } catch {
            LogDebug("CreateWorkspaceOverlay: Failed to destroy existing overlay for monitor " monitorIndex)
        }
    }
    
    MonitorGetWorkArea(monitorIndex, &left, &top, &right, &bottom)
    
    switch OVERLAY_POSITION {
        case "TopLeft":
            x := left + OVERLAY_MARGIN
            y := top + OVERLAY_MARGIN
        case "TopRight":
            x := right - OVERLAY_SIZE - OVERLAY_MARGIN
            y := top + OVERLAY_MARGIN
        case "BottomLeft":
            x := left + OVERLAY_MARGIN
            y := bottom - OVERLAY_SIZE - OVERLAY_MARGIN
        case "BottomRight":
            x := right - OVERLAY_SIZE - OVERLAY_MARGIN
            y := bottom - OVERLAY_SIZE - OVERLAY_MARGIN
    }
    
    ; Create border overlay first (behind main overlay)
    borderGui := Gui("+AlwaysOnTop -Caption +ToolWindow")
    borderGui.BackColor := BORDER_COLOR
    borderGui.Show("x" x " y" y " w" OVERLAY_SIZE " h" OVERLAY_SIZE " NoActivate")
    WinSetTransparent(OVERLAY_OPACITY, borderGui)
    
    ; Create main overlay with dark background and text
    mainOverlay := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x80000")
    mainOverlay.BackColor := "1E1E1E"
    mainOverlay.MarginX := 0
    mainOverlay.MarginY := 0
    
    ; Add the workspace number text with proper vertical centering
    innerSize := OVERLAY_SIZE - BORDER_THICKNESS * 2
    ; Add a small vertical offset to center the text better (2 pixels works well for this font size)
    verticalOffset := 2
    textCtrl := mainOverlay.Add("Text", "x0 y" verticalOffset " w" innerSize " h" innerSize " Center c33FFFF", String(workspaceId))
    textCtrl.SetFont("s24 Bold", "Segoe UI")
    
    ; Show main overlay with offset for border
    mainOverlay.Show("x" (x + BORDER_THICKNESS) " y" (y + BORDER_THICKNESS) " w" (OVERLAY_SIZE - BORDER_THICKNESS * 2) " h" (OVERLAY_SIZE - BORDER_THICKNESS * 2) " NoActivate")
    WinSetTransparent(OVERLAY_OPACITY, mainOverlay)
    
    ; Store both overlays
    WorkspaceOverlays[monitorIndex] := {border: borderGui, main: mainOverlay}
    LogDebug("CreateWorkspaceOverlay: Overlay created and shown at x=" x " y=" y " for monitor " monitorIndex)
    
    ; Create name overlay if workspace has a name
    CreateWorkspaceNameOverlay(monitorIndex, workspaceId)
}

CreateWorkspaceNameOverlay(monitorIndex, workspaceId) {
    global WorkspaceNameOverlays, WorkspaceNames, OVERLAY_MARGIN, OVERLAY_OPACITY, BORDER_COLOR, BORDER_THICKNESS
    
    ; Destroy existing name overlay if any
    if (WorkspaceNameOverlays.Has(monitorIndex)) {
        try {
            if (WorkspaceNameOverlays[monitorIndex].HasOwnProp("border") && WorkspaceNameOverlays[monitorIndex].border) {
                WorkspaceNameOverlays[monitorIndex].border.Destroy()
            }
            if (WorkspaceNameOverlays[monitorIndex].HasOwnProp("main") && WorkspaceNameOverlays[monitorIndex].main) {
                WorkspaceNameOverlays[monitorIndex].main.Destroy()
            }
        } catch {
        }
        WorkspaceNameOverlays.Delete(monitorIndex)
    }
    
    ; Check if workspace has a name
    if (!WorkspaceNames.Has(workspaceId) || WorkspaceNames[workspaceId] == "") {
        return
    }
    
    workspaceName := WorkspaceNames[workspaceId]
    LogDebug("CreateWorkspaceNameOverlay: Creating name overlay for monitor " monitorIndex " with name: '" workspaceName "'")
    
    MonitorGetWorkArea(monitorIndex, &left, &top, &right, &bottom)
    
    ; Use a monospace font for predictable character widths
    fontSize := 14
    fontName := "Consolas"  ; Monospace font
    
    ; Calculate text dimensions using character count
    ; For Consolas at size 14, use larger dimensions to ensure text fits
    ; Add extra buffer to ensure no clipping occurs
    charWidth := 10.0
    charHeight := 21
    calculatedTextWidth := StrLen(workspaceName) * charWidth
    textHeight := charHeight
    
    ; Add padding
    padding := 10
    overlayWidth := Ceil(calculatedTextWidth) + padding * 2 + BORDER_THICKNESS * 2
    overlayHeight := textHeight + padding * 2 + BORDER_THICKNESS * 2
    
    ; Position in lower-left corner
    x := left + OVERLAY_MARGIN
    y := bottom - overlayHeight - OVERLAY_MARGIN
    
    ; Create border overlay
    borderGui := Gui("+AlwaysOnTop -Caption +ToolWindow")
    borderGui.BackColor := BORDER_COLOR
    borderGui.Show("x" x " y" y " w" overlayWidth " h" overlayHeight " NoActivate")
    WinSetTransparent(OVERLAY_OPACITY, borderGui)
    
    ; Create main overlay
    mainOverlay := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x80000")
    mainOverlay.BackColor := "1E1E1E"
    mainOverlay.MarginX := 0
    mainOverlay.MarginY := 0
    
    ; Add the workspace name text with explicit dimensions and position
    innerWidth := overlayWidth - BORDER_THICKNESS * 2
    innerHeight := overlayHeight - BORDER_THICKNESS * 2
    textControlWidth := innerWidth - padding * 2
    textControlHeight := innerHeight - padding * 2
    textCtrl := mainOverlay.Add("Text", "x" padding " y" padding " w" textControlWidth " h" textControlHeight " Left c33FFFF", workspaceName)
    textCtrl.SetFont("s" fontSize, fontName)
    
    ; Show main overlay with offset for border
    mainOverlay.Show("x" (x + BORDER_THICKNESS) " y" (y + BORDER_THICKNESS) " w" innerWidth " h" innerHeight " NoActivate")
    WinSetTransparent(OVERLAY_OPACITY, mainOverlay)
    
    ; Store both overlays
    WorkspaceNameOverlays[monitorIndex] := {border: borderGui, main: mainOverlay}
    LogDebug("CreateWorkspaceNameOverlay: Name overlay created at x=" x " y=" y " with dimensions " overlayWidth "x" overlayHeight)
    LogDebug("CreateWorkspaceNameOverlay: Text control width=" textControlWidth " for string length=" StrLen(workspaceName) " chars")
}

UpdateWorkspaceOverlays() {
    global MonitorWorkspaces, BORDER_VISIBLE
    
    LogDebug("UpdateWorkspaceOverlays: Called, BORDER_VISIBLE=" BORDER_VISIBLE)
    
    if (!BORDER_VISIBLE) {
        LogDebug("UpdateWorkspaceOverlays: Exiting early - BORDER_VISIBLE is false")
        return
    }
    
    monitorCount := MonitorGetCount()
    LogDebug("UpdateWorkspaceOverlays: Processing " monitorCount " monitors")
    
    Loop monitorCount {
        if (MonitorWorkspaces.Has(A_Index)) {
            LogDebug("UpdateWorkspaceOverlays: Creating overlay for monitor " A_Index)
            CreateWorkspaceOverlay(A_Index, MonitorWorkspaces[A_Index])
        } else {
            LogDebug("UpdateWorkspaceOverlays: Monitor " A_Index " not in MonitorWorkspaces")
        }
    }
}

CreateBorderOverlay(monitorIndex) {
    global BorderOverlay, BORDER_COLOR, BORDER_THICKNESS, BORDER_VISIBLE
    
    LogDebug("CreateBorderOverlay: Called for monitor " monitorIndex ", BORDER_VISIBLE=" BORDER_VISIBLE)
    
    if (!BORDER_VISIBLE) {
        LogDebug("CreateBorderOverlay: Exiting early - BORDER_VISIBLE is false")
        return
    }
    
    if (BorderOverlay.Has(monitorIndex)) {
        DestroyBorderOverlay(monitorIndex)
    }
    
    MonitorGetWorkArea(monitorIndex, &left, &top, &right, &bottom)
    width := right - left
    height := bottom - top
    
    LogDebug("CreateBorderOverlay: Monitor " monitorIndex " bounds: " left "," top " to " right "," bottom)
    
    borders := Map()
    
    topBorder := Gui("+AlwaysOnTop -Caption +ToolWindow")
    topBorder.BackColor := BORDER_COLOR
    topBorder.Show("x" left " y" top " w" width " h" BORDER_THICKNESS " NoActivate")
    borders["top"] := topBorder
    
    bottomBorder := Gui("+AlwaysOnTop -Caption +ToolWindow")
    bottomBorder.BackColor := BORDER_COLOR
    bottomBorder.Show("x" left " y" (bottom - BORDER_THICKNESS) " w" width " h" BORDER_THICKNESS " NoActivate")
    borders["bottom"] := bottomBorder
    
    leftBorder := Gui("+AlwaysOnTop -Caption +ToolWindow")
    leftBorder.BackColor := BORDER_COLOR
    leftBorder.Show("x" left " y" top " w" BORDER_THICKNESS " h" height " NoActivate")
    borders["left"] := leftBorder
    
    rightBorder := Gui("+AlwaysOnTop -Caption +ToolWindow")
    rightBorder.BackColor := BORDER_COLOR
    rightBorder.Show("x" (right - BORDER_THICKNESS) " y" top " w" BORDER_THICKNESS " h" height " NoActivate")
    borders["right"] := rightBorder
    
    BorderOverlay[monitorIndex] := borders
    LogDebug("CreateBorderOverlay: Successfully created border overlay for monitor " monitorIndex)
}

DestroyBorderOverlay(monitorIndex) {
    global BorderOverlay
    
    if (BorderOverlay.Has(monitorIndex)) {
        for _, borderGui in BorderOverlay[monitorIndex] {
            try {
                borderGui.Destroy()
            } catch {
            }
        }
        BorderOverlay.Delete(monitorIndex)
    }
}

UpdateActiveMonitorBorder() {
    global LAST_ACTIVE_MONITOR, BORDER_VISIBLE
    
    if (!BORDER_VISIBLE) {
        return
    }
    
    activeMonitor := GetActiveMonitor()
    
    if (activeMonitor != LAST_ACTIVE_MONITOR) {
        LogDebug("UpdateActiveMonitorBorder: Active monitor changed from " LAST_ACTIVE_MONITOR " to " activeMonitor)
        
        if (LAST_ACTIVE_MONITOR > 0) {
            DestroyBorderOverlay(LAST_ACTIVE_MONITOR)
        }
        
        CreateBorderOverlay(activeMonitor)
        LAST_ACTIVE_MONITOR := activeMonitor
    }
}

SwitchWorkspace(targetWorkspace) {
    global SWITCH_IN_PROGRESS, MonitorWorkspaces, WindowWorkspaces, WorkspaceLayouts
    
    if (SWITCH_IN_PROGRESS) {
        LogDebug("Switch already in progress, skipping")
        return
    }
    
    SWITCH_IN_PROGRESS := True
    
    try {
        UpdateWindowMaps()
        
        activeMonitor := GetActiveMonitor()
        
        if (MonitorWorkspaces.Has(activeMonitor) && MonitorWorkspaces[activeMonitor] == targetWorkspace) {
            LogDebug("Monitor " activeMonitor " already on workspace " targetWorkspace)
            return
        }
        
        targetMonitor := 0
        for monIdx, wsId in MonitorWorkspaces {
            if (wsId == targetWorkspace) {
                targetMonitor := monIdx
                break
            }
        }
        
        if (targetMonitor == 0) {
            LogDebug("Switching monitor " activeMonitor " to hidden workspace " targetWorkspace)
            
            currentWorkspace := MonitorWorkspaces.Has(activeMonitor) ? MonitorWorkspaces[activeMonitor] : 0
            
            if (currentWorkspace > 0 && WorkspaceLayouts.Has(currentWorkspace)) {
                for hwnd, _ in WorkspaceLayouts[currentWorkspace] {
                    try {
                        WinMinimize(hwnd)
                    } catch {
                        LogDebug("Error minimizing window: " hwnd)
                    }
                }
            }
            
            MonitorWorkspaces[activeMonitor] := targetWorkspace
            
            if (WorkspaceLayouts.Has(targetWorkspace)) {
                ; Collect windows with their Z-order for proper restoration
                windowsToRestore := []
                
                for hwnd, layout in WorkspaceLayouts[targetWorkspace] {
                    if (WinExist(hwnd)) {
                        zOrder := WindowZOrder.Has(hwnd) ? WindowZOrder[hwnd] : 999999
                        windowsToRestore.Push({hwnd: hwnd, layout: layout, zOrder: zOrder})
                        try {
                            title := WinGetTitle(hwnd)
                            LogDebug("SwitchWorkspace: Window '" title "' (hwnd: " hwnd ") has Z-order: " zOrder)
                        } catch {
                            LogDebug("SwitchWorkspace: Window hwnd " hwnd " has Z-order: " zOrder)
                        }
                    }
                }
                
                ; Sort by Z-order (lower number = higher in stack)
                if (windowsToRestore.Length > 1) {
                    LogDebug("SwitchWorkspace: Sorting " windowsToRestore.Length " windows by Z-order")
                    Loop windowsToRestore.Length - 1 {
                        i := A_Index
                        Loop windowsToRestore.Length - i {
                            j := i + A_Index
                            if (windowsToRestore[i].zOrder > windowsToRestore[j].zOrder) {
                                temp := windowsToRestore[i]
                                windowsToRestore[i] := windowsToRestore[j]
                                windowsToRestore[j] := temp
                            }
                        }
                    }
                    ; Log sorted order
                    LogDebug("SwitchWorkspace: Sorted window order:")
                    for idx, win in windowsToRestore {
                        try {
                            title := WinGetTitle(win.hwnd)
                            LogDebug("  " idx ": '" title "' (Z-order: " win.zOrder ")")
                        } catch {
                            LogDebug("  " idx ": hwnd " win.hwnd " (Z-order: " win.zOrder ")")
                        }
                    }
                }
                
                ; Restore windows in reverse Z-order (bottom to top) to preserve stacking
                LogDebug("SwitchWorkspace: Restoring windows in reverse order")
                Loop windowsToRestore.Length {
                    idx := windowsToRestore.Length - A_Index + 1
                    hwnd := windowsToRestore[idx].hwnd
                    layout := windowsToRestore[idx].layout
                    
                    try {
                        title := WinGetTitle(hwnd)
                        LogDebug("SwitchWorkspace: Restoring window " idx " of " windowsToRestore.Length ": '" title "'")
                    } catch {
                        LogDebug("SwitchWorkspace: Restoring window " idx " of " windowsToRestore.Length ": hwnd " hwnd)
                    }
                    
                    try {
                        ; Check if window needs to be moved to active monitor
                        windowMonitor := GetMonitorForWindow(hwnd)
                        
                        ; Calculate position on active monitor
                        absPos := RelativeToAbsolutePosition(layout, activeMonitor)
                        
                        ; Handle both Map (from JSON) and Object
                        state := (layout is Map) ? layout["state"] : layout.state
                        
                        if (state == 1) {
                            WinRestore(hwnd)
                            
                            ; If on different monitor, move first then maximize
                            if (windowMonitor != activeMonitor) {
                                MoveWindowWithPlacement(hwnd, absPos.x, absPos.y, absPos.width, absPos.height)
                                Sleep(30)
                            }
                            
                            WinMaximize(hwnd)
                        } else {
                            WinRestore(hwnd)
                            MoveWindowWithPlacement(hwnd, absPos.x, absPos.y, absPos.width, absPos.height)
                        }
                        
                        ; Activate to restore Z-order
                        WinActivate(hwnd)
                        
                        if (windowMonitor != activeMonitor) {
                            LogDebug("Moved window from monitor " windowMonitor " to monitor " activeMonitor ": " WinGetTitle(hwnd))
                        }
                    } catch as e {
                        LogDebug("Error restoring window: " hwnd " - " e.Message)
                    }
                }
            }
            
            UpdateWorkspaceOverlays()
            
        } else {
            LogDebug("Swapping workspaces between monitors " activeMonitor " and " targetMonitor)
            
            currentWorkspace := MonitorWorkspaces.Has(activeMonitor) ? MonitorWorkspaces[activeMonitor] : 0
            
            windowOrder := []
            windows := WinGetList()
            for hwnd in windows {
                if (WindowWorkspaces.Has(hwnd) && 
                    (WindowWorkspaces[hwnd] == currentWorkspace || WindowWorkspaces[hwnd] == targetWorkspace)) {
                    windowOrder.Push(hwnd)
                }
            }
            
            MonitorWorkspaces[activeMonitor] := targetWorkspace
            MonitorWorkspaces[targetMonitor] := currentWorkspace
            
            if (WorkspaceLayouts.Has(currentWorkspace)) {
                for hwnd, layout in WorkspaceLayouts[currentWorkspace] {
                    try {
                        if (WinExist(hwnd)) {
                            absPos := RelativeToAbsolutePosition(layout, targetMonitor)
                            
                            if (layout.state == 1) {
                                WinRestore(hwnd)
                                MoveWindowWithPlacement(hwnd, absPos.x, absPos.y, absPos.width, absPos.height)
                                WinMaximize(hwnd)
                            } else {
                                MoveWindowWithPlacement(hwnd, absPos.x, absPos.y, absPos.width, absPos.height)
                            }
                            
                            layout.monitor := targetMonitor
                        }
                    } catch {
                        LogDebug("Error moving window to target monitor: " hwnd)
                    }
                }
            }
            
            if (WorkspaceLayouts.Has(targetWorkspace)) {
                for hwnd, layout in WorkspaceLayouts[targetWorkspace] {
                    try {
                        if (WinExist(hwnd)) {
                            absPos := RelativeToAbsolutePosition(layout, activeMonitor)
                            
                            if (layout.state == 1) {
                                WinRestore(hwnd)
                                MoveWindowWithPlacement(hwnd, absPos.x, absPos.y, absPos.width, absPos.height)
                                WinMaximize(hwnd)
                            } else {
                                MoveWindowWithPlacement(hwnd, absPos.x, absPos.y, absPos.width, absPos.height)
                            }
                            
                            layout.monitor := activeMonitor
                        }
                    } catch {
                        LogDebug("Error moving window to active monitor: " hwnd)
                    }
                }
            }
            
            ; Restore Z-order by activating windows in reverse order (bottom to top)
            Loop windowOrder.Length {
                idx := windowOrder.Length - A_Index + 1
                try {
                    WinActivate(windowOrder[idx])
                } catch {
                }
            }
            
            UpdateWorkspaceOverlays()
        }
        
        SaveWorkspaceState()
        
    } finally {
        SWITCH_IN_PROGRESS := False
    }
}

SendWindowToWorkspace(targetWorkspace) {
    global WindowWorkspaces, WorkspaceLayouts, MonitorWorkspaces, SWITCH_IN_PROGRESS, WorkspaceNames
    
    if (SWITCH_IN_PROGRESS) {
        return
    }
    
    SWITCH_IN_PROGRESS := True
    
    try {
        UpdateWindowMaps()
        
        ; Get active window with error handling
        hwnd := 0
        try {
            hwnd := WinGetID("A")
        } catch {
            LogDebug("No active window to send to workspace")
            return
        }
        
        if (!hwnd || !IsValidWindow(hwnd)) {
            LogDebug("Invalid active window")
            return
        }
        
        currentWorkspace := WindowWorkspaces.Has(hwnd) ? WindowWorkspaces[hwnd] : 0
        if (currentWorkspace == targetWorkspace) {
            LogDebug("Window already on workspace " targetWorkspace)
            return
        }
        
        targetMonitor := 0
        for monIdx, wsId in MonitorWorkspaces {
            if (wsId == targetWorkspace) {
                targetMonitor := monIdx
                break
            }
        }
        
        ; Check if this is the last window on the current workspace
        windowsOnCurrentWorkspace := 0
        if (currentWorkspace > 0) {
            for winHwnd, wsId in WindowWorkspaces {
                if (wsId == currentWorkspace && WinExist(winHwnd)) {
                    windowsOnCurrentWorkspace++
                }
            }
        }
        
        ; Check if target workspace is unused (not assigned to any monitor)
        targetIsUnused := targetMonitor == 0
        
        ; If target workspace is unused and unnamed, name it after the program
        if (targetIsUnused && (!WorkspaceNames.Has(targetWorkspace) || WorkspaceNames[targetWorkspace] == "")) {
            try {
                processName := WinGetProcessName(hwnd)
                programName := StrReplace(processName, ".exe", "")
                ; Capitalize first letter
                if (StrLen(programName) > 0) {
                    programName := StrUpper(SubStr(programName, 1, 1)) . SubStr(programName, 2)
                }
                WorkspaceNames[targetWorkspace] := programName
                LogDebug("SendWindowToWorkspace: Named workspace " targetWorkspace " as '" programName "'")
            } catch {
                LogDebug("SendWindowToWorkspace: Failed to get process name for naming")
            }
        }
        
        if (currentWorkspace > 0 && WorkspaceLayouts.Has(currentWorkspace)) {
            WorkspaceLayouts[currentWorkspace].Delete(hwnd)
        }
        
        WindowWorkspaces[hwnd] := targetWorkspace
        try {
            title := WinGetTitle(hwnd)
            LogDebug("SendWindowToWorkspace: Moved window '" title "' (hwnd: " hwnd ") to workspace " targetWorkspace)
        } catch {
            LogDebug("SendWindowToWorkspace: Moved window hwnd " hwnd " to workspace " targetWorkspace)
        }
        
        ; If this was the last window on the source workspace, remove its name
        if (currentWorkspace > 0 && windowsOnCurrentWorkspace <= 1 && WorkspaceNames.Has(currentWorkspace)) {
            WorkspaceNames.Delete(currentWorkspace)
            LogDebug("SendWindowToWorkspace: Removed name from workspace " currentWorkspace " (no windows remaining)")
        }
        
        if (!WorkspaceLayouts.Has(targetWorkspace)) {
            WorkspaceLayouts[targetWorkspace] := Map()
        }
        
        if (targetMonitor > 0) {
            WinGetPos(&x, &y, &w, &h, hwnd)
            currentMonitor := GetMonitorForWindow(hwnd)
            relPos := AbsoluteToRelativePosition(x, y, w, h, currentMonitor)
            
            absPos := RelativeToAbsolutePosition(relPos, targetMonitor)
            MoveWindowWithPlacement(hwnd, absPos.x, absPos.y, absPos.width, absPos.height)
            
            WorkspaceLayouts[targetWorkspace][hwnd] := {
                xPercent: relPos.xPercent,
                yPercent: relPos.yPercent,
                widthPercent: relPos.widthPercent,
                heightPercent: relPos.heightPercent,
                state: WinGetMinMax(hwnd)
            }
        } else {
            WinGetPos(&x, &y, &w, &h, hwnd)
            currentMonitor := GetMonitorForWindow(hwnd)
            relPos := AbsoluteToRelativePosition(x, y, w, h, currentMonitor)
            
            WorkspaceLayouts[targetWorkspace][hwnd] := {
                xPercent: relPos.xPercent,
                yPercent: relPos.yPercent,
                widthPercent: relPos.widthPercent,
                heightPercent: relPos.heightPercent,
                state: WinGetMinMax(hwnd)
            }
            
            WinMinimize(hwnd)
        }
        
        SaveWorkspaceState()
        UpdateWorkspaceOverlays()
        
    } finally {
        SWITCH_IN_PROGRESS := False
    }
}

TileWindows() {
    global MonitorWorkspaces, WorkspaceLayouts, SHOW_TRAY_NOTIFICATIONS
    
    UpdateWindowMaps()
    
    activeMonitor := GetActiveMonitor()
    LogDebug("TileWindows: Active monitor is " activeMonitor)
    
    if (!MonitorWorkspaces.Has(activeMonitor)) {
        LogDebug("TileWindows: Monitor " activeMonitor " not in MonitorWorkspaces map")
        if (SHOW_TRAY_NOTIFICATIONS) {
            TrayTip("No workspace assigned to this monitor", "Cerberus", 1)
        }
        return
    }
    
    workspace := MonitorWorkspaces[activeMonitor]
    LogDebug("TileWindows: Workspace " workspace " on monitor " activeMonitor)
    
    if (!WorkspaceLayouts.Has(workspace)) {
        LogDebug("TileWindows: No windows in workspace " workspace)
        if (SHOW_TRAY_NOTIFICATIONS) {
            TrayTip("No windows to tile", "Cerberus", 1)
        }
        return
    }
    
    windows := []
    for hwnd, _ in WorkspaceLayouts[workspace] {
        if (WinExist(hwnd) && WinGetMinMax(hwnd) != -1) {
            windows.Push(hwnd)
        }
    }
    
    count := windows.Length
    if (count == 0) {
        return
    }
    
    cols := Ceil(Sqrt(count))
    rows := Ceil(count / cols)
    
    MonitorGetWorkArea(activeMonitor, &left, &top, &right, &bottom)
    monitorWidth := right - left
    monitorHeight := bottom - top
    
    tileWidth := monitorWidth / cols
    tileHeight := monitorHeight / rows
    
    ; Calculate empty tiles and give them to first window
    totalTiles := cols * rows
    emptyTiles := totalTiles - count
    firstWindowRows := 1 + emptyTiles
    
    index := 0
    ; Handle first window specially if it spans multiple rows
    if (count > 0 && emptyTiles > 0) {
        hwnd := windows[1]
        index := 1
        
        x := left
        y := top
        w := tileWidth
        h := tileHeight * firstWindowRows
        
        try {
            WinRestore(hwnd)
            WinMove(x, y, w, h, hwnd)
            
            relPos := AbsoluteToRelativePosition(x, y, w, h, activeMonitor)
            WorkspaceLayouts[workspace][hwnd] := {
                xPercent: relPos.xPercent,
                yPercent: relPos.yPercent,
                widthPercent: relPos.widthPercent,
                heightPercent: relPos.heightPercent,
                state: 0
            }
        } catch {
            LogDebug("Error tiling window: " hwnd)
        }
    }
    
    ; Handle remaining windows
    Loop rows {
        row := A_Index - 1
        Loop cols {
            col := A_Index - 1
            
            ; Skip the first column for all rows if first window spans multiple rows
            if (emptyTiles > 0 && col == 0) {
                continue
            }
            
            if (++index > count) {
                break
            }
            
            hwnd := windows[index]
            
            x := left + (col * tileWidth)
            y := top + (row * tileHeight)
            w := tileWidth
            h := tileHeight
            
            ; Adjust width for last column
            if (col == cols - 1) {
                w := monitorWidth - (col * tileWidth)
            }
            
            ; Adjust height for last row
            if (row == rows - 1) {
                h := monitorHeight - (row * tileHeight)
            }
            
            try {
                WinRestore(hwnd)
                WinMove(x, y, w, h, hwnd)
                
                relPos := AbsoluteToRelativePosition(x, y, w, h, activeMonitor)
                WorkspaceLayouts[workspace][hwnd] := {
                    xPercent: relPos.xPercent,
                    yPercent: relPos.yPercent,
                    widthPercent: relPos.widthPercent,
                    heightPercent: relPos.heightPercent,
                    state: 0
                }
            } catch {
                LogDebug("Error tiling window: " hwnd)
            }
        }
    }
    
    SaveWorkspaceState()
    
    if (SHOW_TRAY_NOTIFICATIONS) {
        TrayTip("Tiled " count " windows", "Cerberus", 1)
    }
}

GetUnusedWorkspaces() {
    global MonitorWorkspaces, MAX_WORKSPACES
    
    unusedWorkspaces := []
    
    ; Create a set of used workspaces
    usedWorkspaces := Map()
    for monitorIndex, workspaceId in MonitorWorkspaces {
        if (workspaceId > 0) {
            usedWorkspaces[workspaceId] := true
        }
    }
    
    ; Find unused workspaces (1 through MAX_WORKSPACES, excluding 0)
    Loop MAX_WORKSPACES {
        if (!usedWorkspaces.Has(A_Index)) {
            unusedWorkspaces.Push(A_Index)
        }
    }
    
    return unusedWorkspaces
}

GetEmptyWorkspaces() {
    global WindowWorkspaces, MAX_WORKSPACES
    
    emptyWorkspaces := []
    
    ; Count windows in each workspace
    workspaceWindowCount := Map()
    for hwnd, workspace in WindowWorkspaces {
        if (workspace > 0) {
            if (!workspaceWindowCount.Has(workspace)) {
                workspaceWindowCount[workspace] := 0
            }
            workspaceWindowCount[workspace]++
        }
    }
    
    ; Find workspaces with no windows (1 through MAX_WORKSPACES, excluding 0)
    Loop MAX_WORKSPACES {
        workspaceId := A_Index
        if (!workspaceWindowCount.Has(workspaceId)) {
            emptyWorkspaces.Push(workspaceId)
        }
    }
    
    return emptyWorkspaces
}

SwitchToNextUnusedWorkspace() {
    global MonitorWorkspaces, SHOW_TRAY_NOTIFICATIONS
    
    activeMonitor := GetActiveMonitor()
    currentWorkspace := MonitorWorkspaces.Has(activeMonitor) ? MonitorWorkspaces[activeMonitor] : 0
    emptyWorkspaces := GetEmptyWorkspaces()
    
    if (emptyWorkspaces.Length == 0) {
        LogDebug("No empty workspaces available")
        if (SHOW_TRAY_NOTIFICATIONS) {
            TrayTip("No empty workspaces", "All workspaces have windows", 1)
        }
        return
    }
    
    ; Find the next empty workspace higher than current
    nextWorkspace := 0
    for workspace in emptyWorkspaces {
        if (workspace > currentWorkspace) {
            nextWorkspace := workspace
            break
        }
    }
    
    ; If no higher workspace found, wrap to the lowest empty
    if (nextWorkspace == 0) {
        nextWorkspace := emptyWorkspaces[1]
    }
    
    LogDebug("Switching to next empty workspace: " nextWorkspace)
    if (SHOW_TRAY_NOTIFICATIONS) {
        TrayTip("Workspace " nextWorkspace, "Switching to empty workspace", 1)
    }
    
    SwitchWorkspace(nextWorkspace)
}

SwitchToPreviousUnusedWorkspace() {
    global MonitorWorkspaces, SHOW_TRAY_NOTIFICATIONS
    
    activeMonitor := GetActiveMonitor()
    currentWorkspace := MonitorWorkspaces.Has(activeMonitor) ? MonitorWorkspaces[activeMonitor] : 0
    emptyWorkspaces := GetEmptyWorkspaces()
    
    if (emptyWorkspaces.Length == 0) {
        LogDebug("No empty workspaces available")
        if (SHOW_TRAY_NOTIFICATIONS) {
            TrayTip("No empty workspaces", "All workspaces have windows", 1)
        }
        return
    }
    
    ; Find the previous empty workspace lower than current
    previousWorkspace := 0
    ; Iterate in reverse to find the highest workspace lower than current
    Loop emptyWorkspaces.Length {
        idx := emptyWorkspaces.Length - A_Index + 1
        workspace := emptyWorkspaces[idx]
        if (workspace < currentWorkspace) {
            previousWorkspace := workspace
            break
        }
    }
    
    ; If no lower workspace found, wrap to the highest empty
    if (previousWorkspace == 0) {
        previousWorkspace := emptyWorkspaces[emptyWorkspaces.Length]
    }
    
    LogDebug("Switching to previous empty workspace: " previousWorkspace)
    if (SHOW_TRAY_NOTIFICATIONS) {
        TrayTip("Workspace " previousWorkspace, "Switching to empty workspace", 1)
    }
    
    SwitchWorkspace(previousWorkspace)
}

SendWindowToNextUnusedWorkspace() {
    global WindowWorkspaces, WorkspaceLayouts, MonitorWorkspaces, WorkspaceNames, SHOW_TRAY_NOTIFICATIONS
    
    ; Get active window
    hwnd := 0
    try {
        hwnd := WinGetID("A")
    } catch as e {
        LogDebug("SendWindowToNextUnusedWorkspace: Error getting active window - " e.Message)
        if (SHOW_TRAY_NOTIFICATIONS) {
            TrayTip("No active window", "Please focus a window first", 1)
        }
        return
    }
    
    if (!hwnd || !IsValidWindow(hwnd)) {
        LogDebug("SendWindowToNextUnusedWorkspace: No valid active window found")
        return
    }
    
    currentWorkspace := WindowWorkspaces.Has(hwnd) ? WindowWorkspaces[hwnd] : 0
    emptyWorkspaces := GetEmptyWorkspaces()
    
    if (emptyWorkspaces.Length == 0) {
        LogDebug("No empty workspaces available")
        if (SHOW_TRAY_NOTIFICATIONS) {
            TrayTip("No empty workspaces", "All workspaces have windows", 1)
        }
        return
    }
    
    ; Find the next empty workspace higher than current
    nextWorkspace := 0
    for workspace in emptyWorkspaces {
        if (workspace > currentWorkspace) {
            nextWorkspace := workspace
            break
        }
    }
    
    ; If no higher workspace found, wrap to the lowest empty
    if (nextWorkspace == 0) {
        nextWorkspace := emptyWorkspaces[1]
    }
    
    ; If the workspace is unnamed, name it after the program
    if (!WorkspaceNames.Has(nextWorkspace) || WorkspaceNames[nextWorkspace] == "") {
        try {
            processName := WinGetProcessName(hwnd)
            programName := StrReplace(processName, ".exe", "")
            ; Capitalize first letter
            if (StrLen(programName) > 0) {
                programName := StrUpper(SubStr(programName, 1, 1)) . SubStr(programName, 2)
            }
            WorkspaceNames[nextWorkspace] := programName
            LogDebug("SendWindowToNextUnusedWorkspace: Named workspace " nextWorkspace " as '" programName "'")
        } catch {
            LogDebug("SendWindowToNextUnusedWorkspace: Failed to get process name for naming")
        }
    }
    
    LogDebug("Sending window to next empty workspace: " nextWorkspace)
    SendWindowToWorkspace(nextWorkspace)
    
    if (SHOW_TRAY_NOTIFICATIONS) {
        workspaceName := WorkspaceNames.Has(nextWorkspace) ? WorkspaceNames[nextWorkspace] : ""
        if (workspaceName != "") {
            TrayTip("Sent to Workspace " nextWorkspace, workspaceName, 1)
        } else {
            TrayTip("Sent to Workspace " nextWorkspace, "Window moved to empty workspace", 1)
        }
    }
}

SendWindowToPreviousUnusedWorkspace() {
    global WindowWorkspaces, WorkspaceLayouts, MonitorWorkspaces, WorkspaceNames, SHOW_TRAY_NOTIFICATIONS
    
    ; Get active window
    hwnd := 0
    try {
        hwnd := WinGetID("A")
    } catch as e {
        LogDebug("SendWindowToPreviousUnusedWorkspace: Error getting active window - " e.Message)
        if (SHOW_TRAY_NOTIFICATIONS) {
            TrayTip("No active window", "Please focus a window first", 1)
        }
        return
    }
    
    if (!hwnd || !IsValidWindow(hwnd)) {
        LogDebug("SendWindowToPreviousUnusedWorkspace: No valid active window found")
        return
    }
    
    currentWorkspace := WindowWorkspaces.Has(hwnd) ? WindowWorkspaces[hwnd] : 0
    emptyWorkspaces := GetEmptyWorkspaces()
    
    if (emptyWorkspaces.Length == 0) {
        LogDebug("No empty workspaces available")
        if (SHOW_TRAY_NOTIFICATIONS) {
            TrayTip("No empty workspaces", "All workspaces have windows", 1)
        }
        return
    }
    
    ; Find the previous empty workspace lower than current
    previousWorkspace := 0
    ; Iterate in reverse to find the highest workspace lower than current
    Loop emptyWorkspaces.Length {
        idx := emptyWorkspaces.Length - A_Index + 1
        workspace := emptyWorkspaces[idx]
        if (workspace < currentWorkspace) {
            previousWorkspace := workspace
            break
        }
    }
    
    ; If no lower workspace found, wrap to the highest empty
    if (previousWorkspace == 0) {
        previousWorkspace := emptyWorkspaces[emptyWorkspaces.Length]
    }
    
    ; If the workspace is unnamed, name it after the program
    if (!WorkspaceNames.Has(previousWorkspace) || WorkspaceNames[previousWorkspace] == "") {
        try {
            processName := WinGetProcessName(hwnd)
            programName := StrReplace(processName, ".exe", "")
            ; Capitalize first letter
            if (StrLen(programName) > 0) {
                programName := StrUpper(SubStr(programName, 1, 1)) . SubStr(programName, 2)
            }
            WorkspaceNames[previousWorkspace] := programName
            LogDebug("SendWindowToPreviousUnusedWorkspace: Named workspace " previousWorkspace " as '" programName "'")
        } catch {
            LogDebug("SendWindowToPreviousUnusedWorkspace: Failed to get process name for naming")
        }
    }
    
    LogDebug("Sending window to previous empty workspace: " previousWorkspace)
    SendWindowToWorkspace(previousWorkspace)
    
    if (SHOW_TRAY_NOTIFICATIONS) {
        workspaceName := WorkspaceNames.Has(previousWorkspace) ? WorkspaceNames[previousWorkspace] : ""
        if (workspaceName != "") {
            TrayTip("Sent to Workspace " previousWorkspace, workspaceName, 1)
        } else {
            TrayTip("Sent to Workspace " previousWorkspace, "Window moved to empty workspace", 1)
        }
    }
}

NameWorkspace() {
    global MonitorWorkspaces, WorkspaceNames, SHOW_TRAY_NOTIFICATIONS
    
    ; Get the active monitor and its current workspace
    activeMonitor := GetActiveMonitor()
    currentWorkspace := MonitorWorkspaces.Has(activeMonitor) ? MonitorWorkspaces[activeMonitor] : 0
    
    if (currentWorkspace == 0) {
        LogDebug("NameWorkspace: No active workspace to name")
        if (SHOW_TRAY_NOTIFICATIONS) {
            TrayTip("No active workspace", "Cannot name workspace 0", 1)
        }
        return
    }
    
    ; Get current name if exists
    currentName := WorkspaceNames.Has(currentWorkspace) ? WorkspaceNames[currentWorkspace] : ""
    
    ; Show input dialog
    result := InputBox("Enter a name for workspace " currentWorkspace ":", "Name Workspace " currentWorkspace, "w300 h120", currentName)
    
    if (result.Result == "Cancel") {
        return
    }
    
    newName := Trim(result.Value)
    
    if (newName == "") {
        ; Remove name if empty
        if (WorkspaceNames.Has(currentWorkspace)) {
            WorkspaceNames.Delete(currentWorkspace)
            LogDebug("NameWorkspace: Removed name for workspace " currentWorkspace)
        }
    } else {
        ; Set new name
        WorkspaceNames[currentWorkspace] := newName
        LogDebug("NameWorkspace: Set name for workspace " currentWorkspace " to: " newName)
    }
    
    ; Save state and refresh overlays
    SaveWorkspaceState()
    UpdateWorkspaceOverlays()
    
    if (SHOW_TRAY_NOTIFICATIONS) {
        if (newName == "") {
            TrayTip("Workspace " currentWorkspace, "Name removed", 1)
        } else {
            TrayTip("Workspace " currentWorkspace, "Named: " newName, 1)
        }
    }
}

SaveWorkspaceState() {
    global CONFIG_DIR, WORKSPACE_STATE_FILE, WindowWorkspaces, WorkspaceLayouts, MonitorWorkspaces, WorkspaceNames, LAST_STATE_SAVE_TIME
    
    LogDebug("SaveWorkspaceState: Called - WindowWorkspaces has " WindowWorkspaces.Count " windows, WindowZOrder has " WindowZOrder.Count " entries")
    
    ; Don't save empty state during startup to avoid overwriting good state
    if (WindowWorkspaces.Count == 0 && IsStartedByTaskScheduler()) {
        LogDebug("SaveWorkspaceState: Skipping save - no windows and started by Task Scheduler")
        return
    }
    
    ; Update last save time
    LAST_STATE_SAVE_TIME := A_TickCount
    
    if (!DirExist(CONFIG_DIR)) {
        DirCreate(CONFIG_DIR)
    }
    
    state := {
        version: VERSION,
        timestamp: A_Now,
        monitors: Map(),
        windows: [],
        workspaceNames: Map()
    }
    
    for monitor, workspace in MonitorWorkspaces {
        state.monitors[monitor] := workspace
    }
    
    ; Get windows in Z-order (top to bottom)
    windowsInZOrder := WinGetList()
    zOrderMap := Map()
    
    ; Create Z-order index for each window and update global tracking
    ; Only track Z-order for managed windows on visible workspaces
    visibleWorkspaces := Map()
    for monitor, workspace in MonitorWorkspaces {
        visibleWorkspaces[workspace] := true
    }
    
    zOrderIndex := 0
    for hwnd in windowsInZOrder {
        ; Only track if window is managed AND on a visible workspace
        if (WindowWorkspaces.Has(hwnd)) {
            workspace := WindowWorkspaces[hwnd]
            if (visibleWorkspaces.Has(workspace)) {
                zOrderIndex++
                zOrderMap[hwnd] := zOrderIndex
                ; Update global Z-order tracking
                WindowZOrder[hwnd] := zOrderIndex
                try {
                    title := WinGetTitle(hwnd)
                    LogDebug("SaveWorkspaceState: Set Z-order for '" title "' (hwnd: " hwnd ", workspace: " workspace ") to " zOrderIndex)
                } catch {
                    LogDebug("SaveWorkspaceState: Set Z-order for hwnd " hwnd " (workspace: " workspace ") to " zOrderIndex)
                }
            }
        }
    }
    
    ; Save assigned windows with Z-order
    for hwnd, workspace in WindowWorkspaces {
        try {
            windowData := {
                hwnd: hwnd,
                workspace: workspace,
                title: WinGetTitle(hwnd),
                class: WinGetClass(hwnd),
                process: WinGetProcessName(hwnd),
                exePath: ""
            }
            
            ; Try to get the executable path
            try {
                pid := WinGetPID(hwnd)
                windowData.exePath := ProcessGetPath(pid)
            } catch {
                LogDebug("Could not get executable path for window: " hwnd)
            }
            
            ; Add Z-order if available
            if (zOrderMap.Has(hwnd)) {
                windowData.zOrder := zOrderMap[hwnd]
            }
            
            if (WorkspaceLayouts.Has(workspace) && WorkspaceLayouts[workspace].Has(hwnd)) {
                windowData.layout := WorkspaceLayouts[workspace][hwnd]
            }
            
            state.windows.Push(windowData)
            LogDebug("SaveWorkspaceState: Saved window '" windowData.title "' to workspace " workspace)
        } catch {
            LogDebug("Error saving window state: " hwnd)
        }
    }
    
    ; Save workspace names
    for workspaceId, name in WorkspaceNames {
        state.workspaceNames[workspaceId] := name
    }
    
    try {
        json := Jxon_Dump(state, 2)
        if (FileExist(WORKSPACE_STATE_FILE)) {
            FileDelete(WORKSPACE_STATE_FILE)
        }
        FileAppend(json, WORKSPACE_STATE_FILE)
        LogDebug("Workspace state saved")
    } catch as e {
        LogDebug("Error saving workspace state: " e.Message)
    }
}

LoadWorkspaceState() {
    global WORKSPACE_STATE_FILE, WindowWorkspaces, WorkspaceLayouts, MonitorWorkspaces, WorkspaceNames
    
    LogDebug("LoadWorkspaceState: Called")
    
    if (!FileExist(WORKSPACE_STATE_FILE)) {
        LogDebug("LoadWorkspaceState: No saved workspace state found")
        return false
    }
    
    try {
        jsonStr := FileRead(WORKSPACE_STATE_FILE)
        LogDebug("LoadWorkspaceState: Read JSON string length: " StrLen(jsonStr))
        
        ; Log first 200 chars of JSON for debugging
        LogDebug("LoadWorkspaceState: JSON preview: " SubStr(jsonStr, 1, 200))
        
        stateData := Jxon_Load(&jsonStr)
        
        LogDebug("LoadWorkspaceState: JSON parsed successfully")
        LogDebug("LoadWorkspaceState: stateData type: " Type(stateData))
        
        ; Better debugging of parsed object
        if (stateData is Map) {
            LogDebug("LoadWorkspaceState: Map has " stateData.Count " entries")
            for key, value in stateData {
                LogDebug("LoadWorkspaceState: Found key: " key)
            }
        }
        
        windows := WinGetList()
        for hwnd in windows {
            if (IsValidWindow(hwnd)) {
                try {
                    WinMinimize(hwnd)
                } catch {
                }
            }
        }
        
        ; Allow time for all windows to finish minimizing
        Sleep(100)
        
        LogDebug("LoadWorkspaceState: Checking for monitors property...")
        if (stateData.Has("monitors")) {
            for monIdx, wsId in stateData["monitors"] {
                MonitorWorkspaces[Number(monIdx)] := wsId
            }
            LogDebug("LoadWorkspaceState: Monitors loaded successfully")
        }
        
        LogDebug("LoadWorkspaceState: Checking for windows property...")
        if (stateData.Has("windows")) {
            LogDebug("LoadWorkspaceState: Found windows array with " stateData["windows"].Length " entries")
            ; Track which windows have been matched to prevent duplicates
            matchedWindows := Map()
            
            for windowData in stateData["windows"] {
                found := false
                LogDebug("LoadWorkspaceState: Processing saved window - Title: '" windowData["title"] "', Workspace: " windowData["workspace"] ", Process: " windowData["process"])
                
                windows := WinGetList()
                for hwnd in windows {
                    ; Skip if already matched
                    if (matchedWindows.Has(hwnd)) {
                        continue
                    }
                    
                    try {
                        currentTitle := WinGetTitle(hwnd)
                        currentClass := WinGetClass(hwnd)
                        currentProcess := WinGetProcessName(hwnd)
                        
                        if (currentClass == windowData["class"] && 
                            currentProcess == windowData["process"] &&
                            (hwnd == windowData["hwnd"] || currentTitle == windowData["title"])) {
                            
                            ; Load all windows including unassigned (workspace 0)
                            WindowWorkspaces[hwnd] := windowData["workspace"]
                            LogDebug("LoadWorkspaceState: Matched window " hwnd " '" currentTitle "' to workspace " windowData["workspace"] " (saved as '" windowData["title"] "')")
                            
                            ; Check if workspace is visible
                            isVisibleWorkspace := false
                            for monIdx, monWsId in MonitorWorkspaces {
                                if (monWsId == windowData["workspace"]) {
                                    isVisibleWorkspace := true
                                    LogDebug("LoadWorkspaceState: Window is on VISIBLE workspace " windowData["workspace"] " (monitor " monIdx ")")
                                    break
                                }
                            }
                            if (!isVisibleWorkspace && windowData["workspace"] != 0) {
                                LogDebug("LoadWorkspaceState: Window is on HIDDEN workspace " windowData["workspace"])
                            }
                            
                            if (windowData.Has("layout")) {
                                if (!WorkspaceLayouts.Has(windowData["workspace"])) {
                                    WorkspaceLayouts[windowData["workspace"]] := Map()
                                }
                                WorkspaceLayouts[windowData["workspace"]][hwnd] := windowData["layout"]
                                LogDebug("LoadWorkspaceState: Stored layout for window '" windowData["title"] "' in workspace " windowData["workspace"])
                            }
                            
                            matchedWindows[hwnd] := true
                            found := true
                            LogDebug("Restored window: " windowData["title"] " to workspace " windowData["workspace"])
                            break
                        } else if (currentClass == windowData["class"] && currentProcess == windowData["process"]) {
                            ; Log near-misses where class and process match but title differs
                            LogDebug("LoadWorkspaceState: Near-miss for " windowData["title"])
                            LogDebug("  Saved title: '" windowData["title"] "'")
                            LogDebug("  Current title: '" currentTitle "'")
                        }
                    } catch {
                    }
                }
                
                if (!found) {
                    LogDebug("Window not found: '" windowData["title"] "' (class: " windowData["class"] ", process: " windowData["process"] ")")
                }
            }
        }
        
        ; Position windows on visible workspaces
        LogDebug("LoadWorkspaceState: Beginning window positioning for visible workspaces")
        for monIdx, wsId in MonitorWorkspaces {
            LogDebug("LoadWorkspaceState: Processing monitor " monIdx " with workspace " wsId)
            if (WorkspaceLayouts.Has(wsId)) {
                LogDebug("LoadWorkspaceState: Found layout data for workspace " wsId " with " WorkspaceLayouts[wsId].Count " windows")
                for hwnd, layout in WorkspaceLayouts[wsId] {
                    try {
                        if (WinExist(hwnd)) {
                            title := WinGetTitle(hwnd)
                            LogDebug("LoadWorkspaceState: Positioning window '" title "' (hwnd: " hwnd ") on monitor " monIdx)
                            absPos := RelativeToAbsolutePosition(layout, monIdx)
                            
                            ; Handle both Map (from JSON) and Object
                            state := (layout is Map) ? layout["state"] : layout.state
                            if (state == 1) {
                                WinRestore(hwnd)
                                ; Move to correct monitor before maximizing
                                MoveWindowWithPlacement(hwnd, absPos.x, absPos.y, absPos.width, absPos.height)
                                WinMaximize(hwnd)
                                LogDebug("LoadWorkspaceState: Maximized window '" title "' on monitor " monIdx)
                            } else {
                                WinRestore(hwnd)
                                MoveWindowWithPlacement(hwnd, absPos.x, absPos.y, absPos.width, absPos.height)
                                LogDebug("LoadWorkspaceState: Positioned window '" title "' at x:" absPos.x " y:" absPos.y)
                            }
                        } else {
                            LogDebug("LoadWorkspaceState: Window hwnd " hwnd " no longer exists")
                        }
                    } catch as e {
                        LogDebug("Error restoring window: " hwnd " - " e.Message)
                    }
                }
            } else {
                LogDebug("LoadWorkspaceState: No layout data for workspace " wsId)
            }
        }
        
        ; Log windows that couldn't be positioned
        LogDebug("LoadWorkspaceState: Checking for unpositioned windows")
        for hwnd, wsId in WindowWorkspaces {
            ; Check if this window's workspace is visible
            isVisible := false
            for monIdx, monWsId in MonitorWorkspaces {
                if (monWsId == wsId) {
                    isVisible := true
                    break
                }
            }
            
            if (isVisible && (!WorkspaceLayouts.Has(wsId) || !WorkspaceLayouts[wsId].Has(hwnd))) {
                try {
                    title := WinGetTitle(hwnd)
                    LogDebug("LoadWorkspaceState: WARNING - Window '" title "' (hwnd: " hwnd ") on visible workspace " wsId " has no layout data and wasn't positioned")
                } catch {
                    LogDebug("LoadWorkspaceState: WARNING - Window hwnd " hwnd " on visible workspace " wsId " has no layout data and wasn't positioned")
                }
            }
        }
        
        ; Restore Z-order for windows on visible workspaces
        LogDebug("LoadWorkspaceState: Restoring Z-order")
        windowsToReorder := []
        
        ; Collect windows with Z-order information
        if (stateData.Has("windows")) {
            for windowData in stateData["windows"] {
                if (windowData.Has("zOrder") && WindowWorkspaces.Has(windowData["hwnd"])) {
                    hwnd := windowData["hwnd"]
                    workspace := WindowWorkspaces[hwnd]
                    
                    ; Check if this workspace is visible (assigned to a monitor)
                    isVisible := false
                    for monIdx, monWsId in MonitorWorkspaces {
                        if (monWsId == workspace) {
                            isVisible := true
                            break
                        }
                    }
                    
                    if (isVisible && WinExist(hwnd)) {
                        windowsToReorder.Push({hwnd: hwnd, zOrder: windowData["zOrder"]})
                        ; Update global Z-order tracking
                        WindowZOrder[hwnd] := windowData["zOrder"]
                    }
                }
            }
        }
        
        ; Sort windows by Z-order (lower number = higher in stack)
        if (windowsToReorder.Length > 0) {
            ; Manual sort since AHK v2 doesn't have built-in array sort
            Loop windowsToReorder.Length - 1 {
                i := A_Index
                Loop windowsToReorder.Length - i {
                    j := i + A_Index
                    if (windowsToReorder[i].zOrder > windowsToReorder[j].zOrder) {
                        temp := windowsToReorder[i]
                        windowsToReorder[i] := windowsToReorder[j]
                        windowsToReorder[j] := temp
                    }
                }
            }
            
            ; Activate windows in reverse order (bottom to top) to restore stacking
            Loop windowsToReorder.Length {
                i := windowsToReorder.Length - A_Index + 1
                try {
                    WinActivate(windowsToReorder[i].hwnd)
                    LogDebug("LoadWorkspaceState: Restored Z-order for window " windowsToReorder[i].hwnd)
                } catch {
                    LogDebug("LoadWorkspaceState: Failed to restore Z-order for window " windowsToReorder[i].hwnd)
                }
            }
        }
        
        LogDebug("LoadWorkspaceState: Successfully loaded - WindowWorkspaces has " WindowWorkspaces.Count " windows")
        
        ; Log windows on hidden workspaces
        hiddenCount := 0
        for hwnd, wsId in WindowWorkspaces {
            isVisible := false
            for monIdx, monWsId in MonitorWorkspaces {
                if (monWsId == wsId) {
                    isVisible := true
                    break
                }
            }
            if (!isVisible) {
                hiddenCount++
                try {
                    title := WinGetTitle(hwnd)
                    LogDebug("LoadWorkspaceState: Window on hidden workspace " wsId ": " title)
                } catch {
                    LogDebug("LoadWorkspaceState: Window on hidden workspace " wsId ": hwnd " hwnd)
                }
            }
        }
        LogDebug("LoadWorkspaceState: " hiddenCount " windows on hidden workspaces")
        
        ; Load workspace names
        if (stateData.Has("workspaceNames")) {
            LogDebug("LoadWorkspaceState: Loading workspace names")
            for workspaceId, name in stateData["workspaceNames"] {
                WorkspaceNames[Number(workspaceId)] := name
                LogDebug("LoadWorkspaceState: Workspace " workspaceId " named: " name)
            }
        }
        
        return true
        
    } catch as e {
        LogDebug("LoadWorkspaceState: Exception caught - Type: " Type(e) " Message: " e.Message)
        LogDebug("LoadWorkspaceState: Stack: " e.Stack)
        return false
    }
}

ShowInstructions() {
    instructionText := "
    (

CONCEPTS:
• Active Monitor: The monitor where your mouse cursor is located
• Active Window: The window that currently has focus
• Workspace: A numbered group of windows (1-20) that appear together

Workspace Switching (changes workspace on active monitor):
• Alt+1-9: Switch to workspaces 1-9
• Alt+0: Switch to workspace 10
• Ctrl+Alt+1-9: Switch to workspaces 11-19
• Ctrl+Alt+0: Switch to workspace 20
• Alt+Up/Down: Cycle through unused workspaces

Window Sending (moves active window to workspace):
• Alt+Shift+1-9: Send to workspaces 1-9
• Alt+Shift+0: Send to workspace 10
• Ctrl+Shift+Alt+1-9: Send to workspaces 11-19
• Ctrl+Shift+Alt+0: Send to workspace 20
• Alt+Shift+Up/Down: Send window to next/previous unused workspace

Utility Functions:
• Alt+Shift+O: Toggle overlays and borders
• Alt+Shift+W: Show workspace map
• Alt+Shift+T: Tile windows on active monitor
• Alt+Shift+H: Show this help
• Alt+Shift+R: Refresh monitor configuration
• Alt+Shift+N: Name the current workspace
    )"
    
    MsgBox(instructionText, "Cerberus Instructions", "OK")
}

ShowWorkspaceMap() {
    global MonitorWorkspaces, WindowWorkspaces, WorkspaceLayouts, WorkspaceNames
    
    UpdateWindowMaps()
    
    mapText := "MONITOR → WORKSPACE ASSIGNMENTS:`n`n"
    
    monitorCount := MonitorGetCount()
    Loop monitorCount {
        workspace := MonitorWorkspaces.Has(A_Index) ? MonitorWorkspaces[A_Index] : "None"
        workspaceName := ""
        if (workspace != "None" && WorkspaceNames.Has(workspace)) {
            workspaceName := " (" WorkspaceNames[workspace] ")"
        }
        mapText .= "Monitor " A_Index " → Workspace " workspace workspaceName "`n"
    }
    
    mapText .= "`n`nWORKSPACE CONTENTS:`n`n"
    
    Loop MAX_WORKSPACES {
        if (WorkspaceLayouts.Has(A_Index)) {
            windowCount := WorkspaceLayouts[A_Index].Count
            if (windowCount > 0) {
                visible := false
                for monitor, workspace in MonitorWorkspaces {
                    if (workspace == A_Index) {
                        visible := true
                        break
                    }
                }
                
                status := visible ? "VISIBLE" : "HIDDEN"
                workspaceName := ""
                if (WorkspaceNames.Has(A_Index)) {
                    workspaceName := " - " WorkspaceNames[A_Index]
                }
                mapText .= "Workspace " A_Index workspaceName " (" status ", " windowCount " windows):`n"
                
                for hwnd, _ in WorkspaceLayouts[A_Index] {
                    try {
                        title := WinGetTitle(hwnd)
                        if (StrLen(title) > 50) {
                            title := SubStr(title, 1, 47) "..."
                        }
                        mapText .= "  - " title "`n"
                    } catch {
                        mapText .= "  - [Invalid Window]`n"
                    }
                }
                mapText .= "`n"
            }
        }
    }
    
    ; Add unassigned windows section
    mapText .= "`nUNASSIGNED WINDOWS:`n`n"
    unassignedCount := 0
    windows := WinGetList()
    for hwnd in windows {
        if (IsValidWindow(hwnd) && (!WindowWorkspaces.Has(hwnd) || WindowWorkspaces[hwnd] == 0)) {
            try {
                title := WinGetTitle(hwnd)
                if (StrLen(title) > 50) {
                    title := SubStr(title, 1, 47) "..."
                }
                mapText .= "  - " title "`n"
                unassignedCount++
            } catch {
            }
        }
    }
    
    if (unassignedCount == 0) {
        mapText .= "  (none)`n"
    }
    
    mapWindow := Gui("+Resize", "Workspace Map")
    mapWindow.SetFont("s10", "Consolas")
    textCtrl := mapWindow.Add("Edit", "ReadOnly w600 h400", mapText)
    mapWindow.Add("Button", "w100", "OK").OnEvent("Click", (*) => mapWindow.Destroy())
    mapWindow.Show()
}

ToggleOverlays() {
    global BORDER_VISIBLE, WorkspaceOverlays, WorkspaceNameOverlays, BorderOverlay, LAST_ACTIVE_MONITOR
    
    UpdateWindowMaps()
    
    BORDER_VISIBLE := !BORDER_VISIBLE
    
    if (!BORDER_VISIBLE) {
        for _, overlay in WorkspaceOverlays {
            try {
                if (overlay.HasOwnProp("border") && overlay.border) {
                    overlay.border.Destroy()
                }
                if (overlay.HasOwnProp("main") && overlay.main) {
                    overlay.main.Destroy()
                }
            } catch {
            }
        }
        WorkspaceOverlays.Clear()
        
        for _, overlay in WorkspaceNameOverlays {
            try {
                if (overlay.HasOwnProp("border") && overlay.border) {
                    overlay.border.Destroy()
                }
                if (overlay.HasOwnProp("main") && overlay.main) {
                    overlay.main.Destroy()
                }
            } catch {
            }
        }
        WorkspaceNameOverlays.Clear()
        
        for monitor, _ in BorderOverlay {
            DestroyBorderOverlay(monitor)
        }
        BorderOverlay.Clear()
    } else {
        LAST_ACTIVE_MONITOR := 0
        UpdateWorkspaceOverlays()
        UpdateActiveMonitorBorder()
    }
    
    status := BORDER_VISIBLE ? "visible" : "hidden"
    if (SHOW_TRAY_NOTIFICATIONS) {
        TrayTip("Overlays " status, "Cerberus", 1)
    }
}

RefreshMonitors() {
    global MonitorWorkspaces, MAX_WORKSPACES, SHOW_TRAY_NOTIFICATIONS
    
    LogDebug("RefreshMonitors: Starting refresh")
    
    monitorCount := MonitorGetCount()
    LogDebug("RefreshMonitors: Detected " monitorCount " monitors")
    
    for monitor, _ in MonitorWorkspaces.Clone() {
        if (monitor > monitorCount) {
            MonitorWorkspaces.Delete(monitor)
        }
    }
    
    Loop monitorCount {
        if (!MonitorWorkspaces.Has(A_Index)) {
            MonitorWorkspaces[A_Index] := A_Index <= MAX_WORKSPACES ? A_Index : 1
            LogDebug("RefreshMonitors: Assigned workspace " MonitorWorkspaces[A_Index] " to monitor " A_Index)
        }
    }
    
    LogDebug("RefreshMonitors: MonitorWorkspaces now has " MonitorWorkspaces.Count " entries")
    
    ; Ensure at least one monitor is initialized
    if (MonitorWorkspaces.Count == 0 && monitorCount > 0) {
        LogDebug("RefreshMonitors: No monitors initialized, forcing monitor 1")
        MonitorWorkspaces[1] := 1
    }
    
    UpdateWorkspaceOverlays()
    UpdateActiveMonitorBorder()
    
    if (SHOW_TRAY_NOTIFICATIONS) {
        TrayTip("Detected " monitorCount " monitors", "Cerberus", 1)
    }
}

CleanupWindowReferences() {
    global WindowWorkspaces, WorkspaceLayouts, WindowZOrder
    
    LogDebug("CleanupWindowReferences: Called")
    windowsToRemove := []
    
    for hwnd, _ in WindowWorkspaces {
        if (!WinExist(hwnd)) {
            windowsToRemove.Push(hwnd)
        }
    }
    
    for hwnd in windowsToRemove {
        WindowWorkspaces.Delete(hwnd)
        
        ; Clean up Z-order tracking
        if (WindowZOrder.Has(hwnd)) {
            WindowZOrder.Delete(hwnd)
        }
        
        for workspace, layouts in WorkspaceLayouts {
            if (layouts.Has(hwnd)) {
                layouts.Delete(hwnd)
            }
        }
    }
    
    LogDebug("Cleaned up " windowsToRemove.Length " stale window references")
}

CheckMouseMovement() {
    UpdateActiveMonitorBorder()
}

IsSystemShuttingDown() {
    ; Check Windows Event Log for recent shutdown events
    ; Event ID 1074 = System shutdown/restart initiated
    ; Event ID 6006 = Event log service stopping (clean shutdown)
    ; Event ID 6008 = Unexpected shutdown (we don't care about this)
    
    try {
        ; Check for shutdown events in the last 60 seconds
        cmd := 'powershell.exe -NoProfile -Command "'
        cmd .= '$shutdownTime = (Get-Date).AddSeconds(-60); '
        cmd .= '$events = Get-WinEvent -FilterHashtable @{LogName=\"System\"; ID=1074,6006; StartTime=$shutdownTime} -ErrorAction SilentlyContinue; '
        cmd .= 'if ($events) { \"SHUTDOWN_DETECTED\" } else { \"NO_SHUTDOWN\" }'
        cmd .= '"'
        
        ; Run PowerShell and capture output
        tempFile := A_Temp . "\cerberus_shutdown_check.txt"
        RunWait(cmd . " > `"" . tempFile . "`"",, "Hide")
        
        ; Read the output
        output := ""
        if (FileExist(tempFile)) {
            output := Trim(FileRead(tempFile))
            try {
                FileDelete(tempFile)
            } catch {
            }
        }
        
        LogDebug("IsSystemShuttingDown: PowerShell output = " . output)
        
        return (output == "SHUTDOWN_DETECTED")
        
    } catch as e {
        LogDebug("IsSystemShuttingDown: Error checking shutdown status - " . e.Message)
        ; If we can't determine, assume no shutdown to preserve data
        return false
    }
}

ExitHandler(reason, code) {
    global SCRIPT_EXITING, WorkspaceOverlays, WorkspaceNameOverlays, BorderOverlay
    
    SCRIPT_EXITING := True
    
    ; Check if system is shutting down
    isShutdown := IsSystemShuttingDown()
    
    ; Additional check: if we saved state very recently (within 2 seconds), 
    ; and we're exiting, it might be a shutdown scenario
    timeSinceLastSave := A_TickCount - LAST_STATE_SAVE_TIME
    if (!isShutdown && timeSinceLastSave < 2000) {
        LogDebug("ExitHandler: State was saved " . timeSinceLastSave . "ms ago - possible rapid shutdown")
        ; Do an additional shutdown check with a shorter timeframe
        isShutdown := IsSystemShuttingDown()
    }
    
    if (isShutdown) {
        LogDebug("ExitHandler: System shutdown detected - skipping workspace state save")
    } else {
        LogDebug("ExitHandler: Normal exit - saving workspace state")
        UpdateWindowMaps()
        SaveWorkspaceState()
    }
    
    for _, overlay in WorkspaceOverlays {
        try {
            if (overlay.HasOwnProp("border") && overlay.border) {
                overlay.border.Destroy()
            }
            if (overlay.HasOwnProp("main") && overlay.main) {
                overlay.main.Destroy()
            }
        } catch {
        }
    }
    
    for _, overlay in WorkspaceNameOverlays {
        try {
            if (overlay.HasOwnProp("border") && overlay.border) {
                overlay.border.Destroy()
            }
            if (overlay.HasOwnProp("main") && overlay.main) {
                overlay.main.Destroy()
            }
        } catch {
        }
    }
    
    for monIdx, _ in BorderOverlay {
        DestroyBorderOverlay(monIdx)
    }
    
    LogDebug("Cerberus exiting: " reason)
}

IsStartupEnabled() {
    global TASK_NAME
    
    try {
        ; Check if the task exists using schtasks
        cmd := 'schtasks.exe /Query /TN "' . TASK_NAME . '" /FO LIST'
        result := RunWait(cmd,, "Hide")
        
        ; If result is 0, the task exists
        return (result == 0)
    } catch {
        LogDebug("IsStartupEnabled: Error checking task status")
    }
    
    return false
}

EnableStartup() {
    global TASK_NAME, SHOW_TRAY_NOTIFICATIONS
    
    exePath := A_ScriptFullPath
    
    ; Create the scheduled task XML
    taskXml := '<?xml version="1.0" encoding="UTF-16"?>'
    taskXml .= '<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">'
    taskXml .= '  <RegistrationInfo>'
    taskXml .= '    <Description>Cerberus Window Manager - Multi-monitor workspace manager</Description>'
    taskXml .= '  </RegistrationInfo>'
    taskXml .= '  <Triggers>'
    taskXml .= '    <LogonTrigger>'
    taskXml .= '      <Enabled>true</Enabled>'
    taskXml .= '    </LogonTrigger>'
    taskXml .= '  </Triggers>'
    taskXml .= '  <Principals>'
    taskXml .= '    <Principal id="Author">'
    taskXml .= '      <UserId>' . A_UserName . '</UserId>'
    taskXml .= '      <LogonType>InteractiveToken</LogonType>'
    taskXml .= '      <RunLevel>HighestAvailable</RunLevel>'
    taskXml .= '    </Principal>'
    taskXml .= '  </Principals>'
    taskXml .= '  <Settings>'
    taskXml .= '    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>'
    taskXml .= '    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>'
    taskXml .= '    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>'
    taskXml .= '    <AllowHardTerminate>false</AllowHardTerminate>'
    taskXml .= '    <StartWhenAvailable>true</StartWhenAvailable>'
    taskXml .= '    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>'
    taskXml .= '    <IdleSettings>'
    taskXml .= '      <StopOnIdleEnd>false</StopOnIdleEnd>'
    taskXml .= '      <RestartOnIdle>false</RestartOnIdle>'
    taskXml .= '    </IdleSettings>'
    taskXml .= '    <AllowStartOnDemand>true</AllowStartOnDemand>'
    taskXml .= '    <Enabled>true</Enabled>'
    taskXml .= '    <Hidden>false</Hidden>'
    taskXml .= '    <RunOnlyIfIdle>false</RunOnlyIfIdle>'
    taskXml .= '    <WakeToRun>false</WakeToRun>'
    taskXml .= '    <ExecutionTimeLimit>PT0S</ExecutionTimeLimit>'
    taskXml .= '    <Priority>7</Priority>'
    taskXml .= '  </Settings>'
    taskXml .= '  <Actions Context="Author">'
    taskXml .= '    <Exec>'
    taskXml .= '      <Command>' . exePath . '</Command>'
    taskXml .= '      <Arguments>/startup</Arguments>'
    taskXml .= '      <WorkingDirectory>' . A_ScriptDir . '</WorkingDirectory>'
    taskXml .= '    </Exec>'
    taskXml .= '  </Actions>'
    taskXml .= '</Task>'
    
    ; Save XML to temp file
    tempFile := A_Temp . "\cerberus_task.xml"
    try {
        FileDelete(tempFile)
    } catch {
    }
    FileAppend(taskXml, tempFile, "UTF-16")
    
    ; Create the scheduled task
    cmd := 'schtasks.exe /Create /TN "' . TASK_NAME . '" /XML "' . tempFile . '" /F'
    result := RunWait(cmd,, "Hide")
    
    ; Clean up temp file
    try {
        FileDelete(tempFile)
    } catch {
    }
    
    if (result == 0) {
        LogDebug("EnableStartup: Task created successfully")
        if (SHOW_TRAY_NOTIFICATIONS) {
            TrayTip("Startup enabled", "Cerberus will start with Windows", 1)
        }
        return true
    } else {
        LogDebug("EnableStartup: Failed to create task, error code: " . result)
        if (SHOW_TRAY_NOTIFICATIONS) {
            TrayTip("Failed to enable startup", "Please run Cerberus as administrator", 2)
        }
        return false
    }
}

DisableStartup() {
    global TASK_NAME, SHOW_TRAY_NOTIFICATIONS
    
    cmd := 'schtasks.exe /Delete /TN "' . TASK_NAME . '" /F'
    result := RunWait(cmd,, "Hide")
    
    if (result == 0) {
        LogDebug("DisableStartup: Task deleted successfully")
        if (SHOW_TRAY_NOTIFICATIONS) {
            TrayTip("Startup disabled", "Cerberus will not start with Windows", 1)
        }
        return true
    } else {
        LogDebug("DisableStartup: Failed to delete task, error code: " . result)
        return false
    }
}

ToggleStartup(*) {
    if (IsStartupEnabled()) {
        DisableStartup()
    } else {
        EnableStartup()
    }
    
    ; Refresh the menu to update the checkmark
    CreateTrayMenu()
}

IsStartedByTaskScheduler() {
    ; Check if we were started with the /startup argument
    for i, arg in A_Args {
        if (arg == "/startup") {
            return true
        }
    }
    return false
}

CreateTrayMenu() {
    trayMenu := A_TrayMenu
    trayMenu.Delete()  ; Clear default menu items
    
    ; Add custom menu items
    trayMenu.Add("&Show Instructions", ShowInstructionsMenu)
    trayMenu.Add("Show &Workspace Map", ShowWorkspaceMapMenu)
    trayMenu.Add()  ; Separator
    
    ; Add startup toggle
    trayMenu.Add("Start with &Windows", ToggleStartup)
    if (IsStartupEnabled()) {
        trayMenu.Check("Start with &Windows")
    }
    
    trayMenu.Add()  ; Separator
    trayMenu.Add("&Refresh Monitors", RefreshMonitorsMenu)
    trayMenu.Add()  ; Separator
    trayMenu.Add("E&xit", DoExitApp)
    
    ; Set default action (double-click tray icon)
    trayMenu.Default := "&Show Instructions"
}

ShowInstructionsMenu(*) {
    UpdateWindowMaps()
    ShowInstructions()
}

ShowWorkspaceMapMenu(*) {
    UpdateWindowMaps()
    ShowWorkspaceMap()
}

RefreshMonitorsMenu(*) {
    UpdateWindowMaps()
    RefreshMonitors()
}

DoExitApp(*) {
    ExitHandler("User requested exit", 0)
    ExitApp()  ; This calls the built-in ExitApp command
}

Initialize() {
    global MonitorWorkspaces, WindowWorkspaces, SHOW_TRAY_NOTIFICATIONS
    
    InitializeLogging()
    
    LogDebug("Initialize: Starting Cerberus initialization")
    
    if (!IsAdmin()) {
        if (SHOW_TRAY_NOTIFICATIONS) {
            TrayTip("Warning: Running without administrator privileges. Some windows may not be manageable.", "Cerberus", 2)
        }
    }
    
    OnExit(ExitHandler)
    
    ; Create tray menu
    CreateTrayMenu()
    
    LogDebug("Initialize: Calling RefreshMonitors")
    RefreshMonitors()
    
    ; Initialize last active monitor
    global LAST_ACTIVE_MONITOR
    LAST_ACTIVE_MONITOR := GetActiveMonitor()
    LogDebug("Initialize: Initial active monitor: " LAST_ACTIVE_MONITOR)
    
    LogDebug("Initialize: MonitorWorkspaces after RefreshMonitors: " MonitorWorkspaces.Count " monitors")
    
    if (IsStartedByTaskScheduler()) {
        ; For Task Scheduler startup, handle everything in LaunchProgramsFromWorkspaceState
        LogDebug("Initialize: Started by Task Scheduler - launching programs and restoring state")
        LaunchProgramsFromWorkspaceState()
    } else {
        ; Normal startup - just load existing windows
        if (!LoadWorkspaceState()) {
            windows := WinGetList()
            for hwnd in windows {
                if (IsValidWindow(hwnd)) {
                    try {
                        minMax := WinGetMinMax(hwnd)
                        if (minMax == -1) {
                            WindowWorkspaces[hwnd] := 0
                        }
                    } catch {
                    }
                }
            }
            
            UpdateWindowMaps()
        }
    }
    
    UpdateWorkspaceOverlays()
    UpdateActiveMonitorBorder()
    
    SetTimer(CleanupWindowReferences, 120000)
    SetTimer(CheckMouseMovement, 100)
    
    ; Only show instructions for manual startup
    if (!IsStartedByTaskScheduler()) {
        ShowInstructions()
    }
    
    if (SHOW_TRAY_NOTIFICATIONS) {
        TrayTip("Cerberus initialized", "Multi-monitor workspace manager ready", 1)
    }
    
    LogDebug("Cerberus initialized successfully")
    LogDebug("Running cerberus4.ahk version " VERSION)
}

LaunchProgramsFromWorkspaceState() {
    global WORKSPACE_STATE_FILE, SHOW_TRAY_NOTIFICATIONS, MonitorWorkspaces, WindowWorkspaces, WorkspaceLayouts, WorkspaceNames
    
    LogDebug("LaunchProgramsFromWorkspaceState: Starting program launch and state restoration")
    
    if (!FileExist(WORKSPACE_STATE_FILE)) {
        LogDebug("LaunchProgramsFromWorkspaceState: No workspace state file found")
        return
    }
    
    try {
        json := FileRead(WORKSPACE_STATE_FILE)
        LogDebug("LaunchProgramsFromWorkspaceState: Read state file, length: " StrLen(json))
        
        state := Jxon_Load(&json)
        LogDebug("LaunchProgramsFromWorkspaceState: Parsed JSON successfully")
        
        ; First, restore monitor workspace assignments
        if (state.Has("monitors")) {
            LogDebug("LaunchProgramsFromWorkspaceState: Restoring monitor workspace assignments")
            for monIdx, wsId in state["monitors"] {
                MonitorWorkspaces[Number(monIdx)] := wsId
                LogDebug("LaunchProgramsFromWorkspaceState: Monitor " monIdx " -> Workspace " wsId)
            }
        }
        
        ; Load workspace names
        if (state.Has("workspaceNames")) {
            LogDebug("LaunchProgramsFromWorkspaceState: Loading workspace names")
            for workspaceId, name in state["workspaceNames"] {
                WorkspaceNames[Number(workspaceId)] := name
            }
        }
        
        if (!state.Has("windows")) {
            LogDebug("LaunchProgramsFromWorkspaceState: No windows property in state")
            return
        }
        
        LogDebug("LaunchProgramsFromWorkspaceState: Found " state["windows"].Length " windows in state")
        
        ; Create a map to track unique executables to launch
        programsToLaunch := Map()
        windowInfoByExe := Map()  ; Track all windows for each exe
        launchOrder := []
        
        ; Group windows by executable path
        for window in state["windows"] {
            if (window.Has("exePath") && window["exePath"] != "") {
                ; Skip system processes and certain applications
                skipList := ["explorer.exe", "dwm.exe", "taskmgr.exe", "SystemSettings.exe"]
                processName := window["process"]
                
                shouldSkip := false
                for skipProc in skipList {
                    if (StrLower(processName) == StrLower(skipProc)) {
                        shouldSkip := true
                        break
                    }
                }
                
                if (!shouldSkip && FileExist(window["exePath"])) {
                    exePath := window["exePath"]
                    if (!programsToLaunch.Has(exePath)) {
                        programsToLaunch[exePath] := {
                            path: exePath,
                            process: window["process"]
                        }
                        windowInfoByExe[exePath] := []
                        launchOrder.Push(exePath)
                    }
                    windowInfoByExe[exePath].Push(window)
                    LogDebug("LaunchProgramsFromWorkspaceState: Will launch " exePath . " for window '" . window["title"] . "' on workspace " . window["workspace"])
                }
            }
        }
        
        launchedCount := 0
        failedLaunches := []
        
        ; Launch programs and assign windows
        for exePath in launchOrder {
            programInfo := programsToLaunch[exePath]
            windowInfos := windowInfoByExe[exePath]
            
            try {
                ; Check if this is a Store app that needs special launcher
                launchPath := exePath
                if (InStr(exePath, "\WindowsApps\") && STORE_APP_LAUNCHERS.Has(programInfo.process)) {
                    launchPath := STORE_APP_LAUNCHERS[programInfo.process]
                    LogDebug("LaunchProgramsFromWorkspaceState: Using Store app launcher '" . launchPath . "' for " . programInfo.process)
                }
                
                LogDebug("LaunchProgramsFromWorkspaceState: Launching " launchPath)
                Run(launchPath)
                launchedCount++
                
                ; Wait for the program to create windows
                Sleep(2000)
                
                ; Find and assign windows created by this program
                windows := WinGetList()
                for hwnd in windows {
                    try {
                        if (WinGetProcessName(hwnd) == programInfo.process) {
                            currentTitle := WinGetTitle(hwnd)
                            currentClass := WinGetClass(hwnd)
                            
                            ; Try to match this window with saved window info
                            for windowInfo in windowInfos {
                                if (currentClass == windowInfo["class"]) {
                                    ; Assign to workspace
                                    workspace := windowInfo["workspace"]
                                    WindowWorkspaces[hwnd] := workspace
                                    LogDebug("LaunchProgramsFromWorkspaceState: Assigned window '" . currentTitle . "' (hwnd: " . hwnd . ") to workspace " . workspace)
                                    
                                    ; Store layout if available
                                    if (windowInfo.Has("layout")) {
                                        if (!WorkspaceLayouts.Has(workspace)) {
                                            WorkspaceLayouts[workspace] := Map()
                                        }
                                        WorkspaceLayouts[workspace][hwnd] := windowInfo["layout"]
                                        LogDebug("LaunchProgramsFromWorkspaceState: Stored layout for window")
                                    }
                                    
                                    ; Position window if it's on a visible workspace
                                    isVisibleWorkspace := false
                                    visibleMonitor := 0
                                    for monIdx, wsId in MonitorWorkspaces {
                                        if (wsId == workspace) {
                                            isVisibleWorkspace := true
                                            visibleMonitor := monIdx
                                            break
                                        }
                                    }
                                    
                                    if (isVisibleWorkspace && windowInfo.Has("layout")) {
                                        absPos := RelativeToAbsolutePosition(windowInfo["layout"], visibleMonitor)
                                        if (windowInfo["layout"]["state"] == 1) {
                                            WinRestore(hwnd)
                                            MoveWindowWithPlacement(hwnd, absPos.x, absPos.y, absPos.width, absPos.height)
                                            WinMaximize(hwnd)
                                            LogDebug("LaunchProgramsFromWorkspaceState: Maximized window on monitor " . visibleMonitor)
                                        } else {
                                            WinRestore(hwnd)
                                            MoveWindowWithPlacement(hwnd, absPos.x, absPos.y, absPos.width, absPos.height)
                                            LogDebug("LaunchProgramsFromWorkspaceState: Positioned window at x:" . absPos.x . " y:" . absPos.y)
                                        }
                                    } else if (!isVisibleWorkspace) {
                                        ; Hide windows on hidden workspaces
                                        WinMinimize(hwnd)
                                        LogDebug("LaunchProgramsFromWorkspaceState: Minimized window on hidden workspace " . workspace)
                                    }
                                    
                                    break  ; Found a match, move to next window
                                }
                            }
                        }
                    } catch as e {
                        LogDebug("LaunchProgramsFromWorkspaceState: Error processing window - " . e.Message)
                    }
                }
                
            } catch as e {
                LogDebug("LaunchProgramsFromWorkspaceState: Failed to launch " . programInfo.path . ": " . e.Message)
                failedLaunches.Push({
                    path: programInfo.path,
                    process: programInfo.process,
                    error: e.Message
                })
            }
        }
        
        ; After launching programs, check for already-running windows that need workspace assignment
        LogDebug("LaunchProgramsFromWorkspaceState: Checking for already-running windows to restore")
        restoredCount := 0
        
        ; Get all current windows
        allWindows := WinGetList()
        for hwnd in allWindows {
            if (!IsValidWindow(hwnd)) {
                continue
            }
            
            ; Skip if already assigned
            if (WindowWorkspaces.Has(hwnd)) {
                continue
            }
            
            try {
                currentTitle := WinGetTitle(hwnd)
                currentClass := WinGetClass(hwnd)
                currentProcess := WinGetProcessName(hwnd)
                
                ; Try to match with saved windows
                for window in state["windows"] {
                    ; Match by process and class (title might change)
                    if (window["process"] == currentProcess && window["class"] == currentClass) {
                        workspace := window["workspace"]
                        WindowWorkspaces[hwnd] := workspace
                        LogDebug("LaunchProgramsFromWorkspaceState: Restored already-running window '" . currentTitle . "' (hwnd: " . hwnd . ") to workspace " . workspace)
                        restoredCount++
                        
                        ; Store layout if available
                        if (window.Has("layout")) {
                            if (!WorkspaceLayouts.Has(workspace)) {
                                WorkspaceLayouts[workspace] := Map()
                            }
                            WorkspaceLayouts[workspace][hwnd] := window["layout"]
                            LogDebug("LaunchProgramsFromWorkspaceState: Stored layout for restored window")
                        }
                        
                        ; Position window if it's on a visible workspace
                        isVisibleWorkspace := false
                        visibleMonitor := 0
                        for monIdx, wsId in MonitorWorkspaces {
                            if (wsId == workspace) {
                                isVisibleWorkspace := true
                                visibleMonitor := monIdx
                                break
                            }
                        }
                        
                        if (isVisibleWorkspace && window.Has("layout")) {
                            absPos := RelativeToAbsolutePosition(window["layout"], visibleMonitor)
                            if (window["layout"]["state"] == 1) {
                                WinRestore(hwnd)
                                MoveWindowWithPlacement(hwnd, absPos.x, absPos.y, absPos.width, absPos.height)
                                WinMaximize(hwnd)
                                LogDebug("LaunchProgramsFromWorkspaceState: Maximized restored window on monitor " . visibleMonitor)
                            } else {
                                WinRestore(hwnd)
                                MoveWindowWithPlacement(hwnd, absPos.x, absPos.y, absPos.width, absPos.height)
                                LogDebug("LaunchProgramsFromWorkspaceState: Positioned restored window at x:" . absPos.x . " y:" . absPos.y)
                            }
                        } else if (!isVisibleWorkspace) {
                            ; Hide windows on hidden workspaces
                            WinMinimize(hwnd)
                            LogDebug("LaunchProgramsFromWorkspaceState: Minimized restored window on hidden workspace " . workspace)
                        }
                        
                        break  ; Found a match, move to next window
                    }
                }
            } catch as e {
                LogDebug("LaunchProgramsFromWorkspaceState: Error processing existing window - " . e.Message)
            }
        }
        
        if (SHOW_TRAY_NOTIFICATIONS && (launchedCount > 0 || restoredCount > 0)) {
            msg := ""
            if (launchedCount > 0 && restoredCount > 0) {
                msg := "Launched " launchedCount " programs, restored " restoredCount " windows"
            } else if (launchedCount > 0) {
                msg := "Launched " launchedCount " programs"
            } else if (restoredCount > 0) {
                msg := "Restored " restoredCount " windows"
            }
            if (msg != "") {
                TrayTip(msg, "Cerberus restored your workspace", 1)
            }
        }
        
        ; Show warning dialog for failed launches
        if (failedLaunches.Length > 0) {
            warningMsg := "Cerberus couldn't launch the following programs:`n`n"
            for failed in failedLaunches {
                warningMsg .= "• " . failed.process . "`n"
                if (InStr(failed.path, "\WindowsApps\")) {
                    warningMsg .= "  (Windows Store app - will try to restore if already running)`n"
                }
            }
            warningMsg .= "`nThese programs may need to be started manually."
            
            MsgBox(warningMsg, "Program Launch Warning", "Iconx")
            
            LogDebug("LaunchProgramsFromWorkspaceState: Showed warning for " . failedLaunches.Length . " failed launches")
        }
        
        LogDebug("LaunchProgramsFromWorkspaceState: Completed - launched " . launchedCount . " programs, restored " . restoredCount . " windows")
        
    } catch as e {
        LogDebug("LaunchProgramsFromWorkspaceState: Error - " . e.Message)
    }
}

!1::SwitchWorkspace(1)
!2::SwitchWorkspace(2)
!3::SwitchWorkspace(3)
!4::SwitchWorkspace(4)
!5::SwitchWorkspace(5)
!6::SwitchWorkspace(6)
!7::SwitchWorkspace(7)
!8::SwitchWorkspace(8)
!9::SwitchWorkspace(9)
!0::SwitchWorkspace(10)

^!1::SwitchWorkspace(11)
^!2::SwitchWorkspace(12)
^!3::SwitchWorkspace(13)
^!4::SwitchWorkspace(14)
^!5::SwitchWorkspace(15)
^!6::SwitchWorkspace(16)
^!7::SwitchWorkspace(17)
^!8::SwitchWorkspace(18)
^!9::SwitchWorkspace(19)
^!0::SwitchWorkspace(20)

!+1::SendWindowToWorkspace(1)
!+2::SendWindowToWorkspace(2)
!+3::SendWindowToWorkspace(3)
!+4::SendWindowToWorkspace(4)
!+5::SendWindowToWorkspace(5)
!+6::SendWindowToWorkspace(6)
!+7::SendWindowToWorkspace(7)
!+8::SendWindowToWorkspace(8)
!+9::SendWindowToWorkspace(9)
!+0::SendWindowToWorkspace(10)

^+!1::SendWindowToWorkspace(11)
^+!2::SendWindowToWorkspace(12)
^+!3::SendWindowToWorkspace(13)
^+!4::SendWindowToWorkspace(14)
^+!5::SendWindowToWorkspace(15)
^+!6::SendWindowToWorkspace(16)
^+!7::SendWindowToWorkspace(17)
^+!8::SendWindowToWorkspace(18)
^+!9::SendWindowToWorkspace(19)
^+!0::SendWindowToWorkspace(20)

!Up::SwitchToNextUnusedWorkspace()
!Down::SwitchToPreviousUnusedWorkspace()

!+Up::SendWindowToNextUnusedWorkspace()
!+Down::SendWindowToPreviousUnusedWorkspace()

!+o::{
    UpdateWindowMaps()
    ToggleOverlays()
}

!+w::{
    UpdateWindowMaps()
    ShowWorkspaceMap()
}


!+t::{
    UpdateWindowMaps()
    TileWindows()
}

!+h::{
    UpdateWindowMaps()
    ShowInstructions()
}

!+r::{
    UpdateWindowMaps()
    RefreshMonitors()
}

!+n::{
    NameWorkspace()
}

IsAdmin() {
    return A_IsAdmin
}

Jxon_Load(&src, args*) {
    key := "", is_key := false
    stack := [ tree := [] ]
    next := '"{[01234567890-tfn'
    pos := 0
    
    while ( (ch := SubStr(src, ++pos, 1)) != "" ) {
        if InStr(" `t`n`r", ch)
            continue
        if !InStr(next, ch, true) {
            testArr := StrSplit(SubStr(src, 1, pos), "`n")
            
            lineNum := testArr.Length
            col := pos - InStr(src, "`n",, -(StrLen(src)-pos+1))
            
            msg := Format("{}: line {} col {} (char {})"
            ,   (next == "")      ? ["Extra data", ch := SubStr(src, pos)][1]
            : (next == "'")     ? "Unterminated string starting at"
            : (next == "\")     ? "Invalid \escape"
            : (next == ":")     ? "Expecting ':' delimiter"
            : (next == '"')     ? "Expecting object key enclosed in double quotes"
            : (next == '"}')    ? "Expecting object key enclosed in double quotes or object closing '}'"
            : (next == ',}')    ? "Expecting ',' delimiter or object closing '}'"
            : (next == ',]')    ? "Expecting ',' delimiter or array closing ']'"
            : [ "Expecting JSON value(string, number, [true, false, null], object or array)"
            , ch := SubStr(src, pos, (SubStr(src, pos)~="[\]\},\s]|$")-1) ][1]
            , lineNum, col, pos)
            
            throw Error(msg, -1, ch)
        }
        
        is_array := (obj := stack[1]) is Array
        
        if i := InStr("{[", ch) {
            val := (i = 1) ? Map() : Array()
            
            is_array ? obj.Push(val) : obj[key] := val
            stack.InsertAt(1, val)
            
            next := '"' ((is_key := (ch == "{")) ? "}" : "{[]0123456789-tfn")
        } else if InStr("}]", ch) {
            stack.RemoveAt(1)
            next := (stack[1] is Array) ? ",]" : ",}"
        } else if InStr(",:", ch) {
            is_key := (!is_array && ch == ",")
            next := (is_key) ? '"' : '"{[0123456789-tfn'
        } else {
            if (ch == '"') {
                i := pos
                while i := InStr(src, '"',, i+1) {
                    val := StrReplace(SubStr(src, pos+1, i-pos-1), "\\", "\u005C")
                    if (SubStr(val, -1) != "\")
                        break
                }
                if !i ? (pos--, next := "'") : 0
                    continue
                
                pos := i
                
                val := StrReplace(val, "\/", "/")
                val := StrReplace(val, '\"', '"')
                , val := StrReplace(val, "\b", "`b")
                , val := StrReplace(val, "\f", "`f")
                , val := StrReplace(val, "\n", "`n")
                , val := StrReplace(val, "\r", "`r")
                , val := StrReplace(val, "\t", "`t")
                
                i := 0
                while i := InStr(val, "\",, i+1) {
                    if (SubStr(val, i+1, 1) != "u") ? (pos -= StrLen(SubStr(val, i)), next := "\") : 0
                        continue 2
                    
                    xxxx := Abs("0x" . SubStr(val, i+2, 4))
                    if (xxxx < 0x100)
                        val := SubStr(val, 1, i-1) . Chr(xxxx) . SubStr(val, i+6)
                }
                
                if is_key {
                    key := val, next := ":"
                    continue
                }
            } else {
                val := SubStr(src, pos, i := RegExMatch(src, "[\]\},\s]|$",, pos)-pos)
                
                if IsInteger(val)
                    val += 0
                else if IsFloat(val)
                    val += 0
                else if (val == "true" || val == "false")
                    val := (val == "true")
                else if (val == "null")
                    val := ""
                else if is_key {
                    pos--, next := "#"
                    continue
                }
                
                pos += i-1
            }
            
            is_array ? obj.Push(val) : obj[key] := val
            next := (obj is Array) ? ",]" : ",}"
        }
    }
    
    return tree[1]
}

Jxon_Dump(obj, indent:="", lvl:=1) {
    if IsObject(obj) {
        If !(obj is Array || obj is Map || obj is Object)
            throw Error("Object type not supported.", -1, Format("<Object at 0x{:p}>", ObjPtr(obj)))
        
        if IsInteger(indent) {
            if (indent < 0)
                throw Error("Indent parameter must be a positive integer.", -1, indent)
            spaces := indent, indent := ""
            
            Loop spaces
                indent .= " "
        }
        indt := ""
        
        Loop indent ? lvl : 0
            indt .= indent
        
        is_array := (obj is Array)
        
        lvl += 1, out := ""
        
        if (obj is Map) {
            for k, v in obj {
                if IsObject(k) || (k == "")
                    throw Error("Invalid object key.", -1, k ? Format("<Object at 0x{:p}>", ObjPtr(obj)) : "<blank>")
                
                out .= (out ? "," : "") . (indent ? "`n" . indt : "") . '"' . k . '": '
                out .= Jxon_Dump(v, indent, lvl)
            }
        } else if (is_array) {
            for v in obj {
                out .= (out ? "," : "") . (indent ? "`n" . indt : "")
                out .= Jxon_Dump(v, indent, lvl)
            }
        } else {
            for k, v in obj.OwnProps() {
                if IsObject(k) || (k == "")
                    throw Error("Invalid object key.", -1, k ? Format("<Object at 0x{:p}>", ObjPtr(obj)) : "<blank>")
                
                out .= (out ? "," : "") . (indent ? "`n" . indt : "") . '"' . k . '": '
                out .= Jxon_Dump(v, indent, lvl)
            }
        }
        
        if (out != "") {
            out := Rtrim(out, ",`n" . indent)
            if (indent != "")
                out := "`n" . indt . out . "`n" . SubStr(indt, StrLen(indent)+1)
        }
        
        return is_array ? "[" . out . "]" : "{" . out . "}"
    } else if (IsInteger(obj) || IsFloat(obj))
        return obj
    else if (obj == true || obj == false)
        return obj ? "true" : "false"
    else if (obj == "")
        return "null"
    else {
        obj := StrReplace(obj, "\", "\\")
        obj := StrReplace(obj, "`t", "\t")
        obj := StrReplace(obj, "`r", "\r")
        obj := StrReplace(obj, "`n", "\n")
        obj := StrReplace(obj, "`b", "\b")
        obj := StrReplace(obj, "`f", "\f")
        obj := StrReplace(obj, "/", "\/")
        obj := StrReplace(obj, '"', '\"')
        
        return '"' . obj . '"'
    }
}

Initialize()