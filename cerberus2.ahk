#Requires AutoHotkey v2.0

; Configuration
MAX_WORKSPACES := 20
MAX_MONITORS := 9
DEBUG_MODE := true
LOG_TO_FILE := false
LOG_FILE := A_ScriptDir "\cerberus.log"
OVERLAY_SIZE := 60
OVERLAY_MARGIN := 20
OVERLAY_TIMEOUT := 0
OVERLAY_OPACITY := 220
OVERLAY_POSITION := "BottomRight"
BORDER_COLOR := "33FFFF"
BORDER_THICKNESS := 3
SHOW_WINDOW_EVENT_TOOLTIPS := false
SHOW_TRAY_NOTIFICATIONS := false

; Global data structures
MonitorWorkspaces := Map()
WindowWorkspaces := Map()
WorkspaceLayouts := Map()
WorkspaceOverlays := Map()
MonitorBorders := Map()
lastWindowState := Map()
overlaysVisible := true
windowListOverlay := 0
activeMonitorTimer := 0
STATE_FILE := A_ScriptDir "\cerberus_state.json"
FIRST_RUN_FILE := A_ScriptDir "\.cerberus_shown"
detailedMapOverlay := 0

; Skip these window classes
SKIP_CLASSES := [
    "Shell_TrayWnd", "Progman", "Button", "DV2ControlHost",
    "SysListView32", "WorkerW", "Shell_SecondaryTrayWnd",
    "Windows.UI.Core.CoreWindow", "ApplicationFrameWindow",
    "NotifyIconOverflowWindow", "MSTaskSwWClass", "MSTaskListWClass"
]

; Main initialization
try {
    CheckAdminPrivileges()
    ShowFirstRunInstructions()
    LoadWorkspaceState()
    InitializeWorkspaces()
    InitializeOverlays()
    SetupEventHandlers()
    RegisterHotkeys()
    UpdateActiveMonitor()
    SetTimer(UpdateActiveMonitor, 100)
    SetTimer(AutoSaveState, 300000) ; Auto-save every 5 minutes
    OnExit(ExitHandler)
    LogMessage("Cerberus initialized successfully")
} catch as e {
    MsgBox("Failed to initialize Cerberus: " . e.Message, "Error", 48)
    ExitApp
}

; Initialize workspaces
InitializeWorkspaces() {
    global
    
    CoordMode("Mouse", "Screen")
    SetWinDelay(10)
    DetectHiddenWindows(false)
    
    monitorCount := MonitorGetCount()
    LogMessage("Detected " . monitorCount . " monitor(s)")
    
    ; Initialize monitor to workspace mappings
    Loop Min(monitorCount, MAX_MONITORS) {
        if (A_Index <= MAX_WORKSPACES) {
            MonitorWorkspaces[A_Index] := A_Index
        } else {
            MonitorWorkspaces[A_Index] := 1
        }
        LogMessage("Monitor " . A_Index . " assigned to workspace " . MonitorWorkspaces[A_Index])
    }
    
    ; Process existing windows
    windows := WinGetList()
    validWindows := []
    
    for hwnd in windows {
        if (IsWindowValid(hwnd)) {
            validWindows.Push(hwnd)
        }
    }
    
    ; Assign windows to workspaces
    for hwnd in validWindows {
        try {
            if (WinGetMinMax(hwnd) = -1) {
                WindowWorkspaces[hwnd] := 0
            } else {
                monitor := GetWindowMonitor(hwnd)
                if (MonitorWorkspaces.Has(monitor)) {
                    workspace := MonitorWorkspaces[monitor]
                    WindowWorkspaces[hwnd] := workspace
                    SaveWindowLayout(hwnd, workspace)
                }
            }
        } catch {
            LogMessage("Error processing window " . hwnd)
        }
    }
    
    LogMessage("Workspace initialization complete")
}

; Initialize visual overlays
InitializeOverlays() {
    global
    monitorCount := MonitorGetCount()
    
    Loop monitorCount {
        CreateOverlay(A_Index)
        CreateMonitorBorder(A_Index)
    }
    
    UpdateAllOverlays()
}

; Check if window is valid for tracking
IsWindowValid(hwnd) {
    global SKIP_CLASSES
    
    try {
        if (!WinExist(hwnd))
            return false
            
        title := WinGetTitle(hwnd)
        class := WinGetClass(hwnd)
        
        if (title = "" || class = "")
            return false
            
        for skipClass in SKIP_CLASSES {
            if (class = skipClass)
                return false
        }
        
        if (hwnd = A_ScriptHwnd)
            return false
            
        if (InStr(title, "NVIDIA GeForce Overlay") || InStr(title, "Windows Input Experience"))
            return false
            
        style := WinGetStyle(hwnd)
        if (style & 0x40000000) ; WS_CHILD
            return false
            
        return true
    } catch {
        return false
    }
}

; Get monitor containing window
GetWindowMonitor(hwnd) {
    monitorCount := MonitorGetCount()
    
    if (monitorCount = 1)
        return 1
        
    try {
        WinGetPos(&x, &y, &w, &h, hwnd)
        centerX := x + w // 2
        centerY := y + h // 2
        
        Loop monitorCount {
            MonitorGetWorkArea(A_Index, &left, &top, &right, &bottom)
            if (centerX >= left && centerX <= right && centerY >= top && centerY <= bottom)
                return A_Index
        }
    } catch {
        ; Ignore errors
    }
    
    return 1
}

; Get active monitor based on mouse position
GetActiveMonitor() {
    MouseGetPos(&mouseX, &mouseY)
    monitorCount := MonitorGetCount()
    
    Loop monitorCount {
        MonitorGetWorkArea(A_Index, &left, &top, &right, &bottom)
        if (mouseX >= left && mouseX <= right && mouseY >= top && mouseY <= bottom)
            return A_Index
    }
    
    return 1
}

; Update active monitor indicator
UpdateActiveMonitor() {
    global MonitorBorders
    static lastActiveMonitor := 0
    
    currentMonitor := GetActiveMonitor()
    
    if (currentMonitor != lastActiveMonitor) {
        ; Hide all borders
        for idx, border in MonitorBorders {
            if (border)
                border.Hide()
        }
        
        ; Show active monitor border
        if (overlaysVisible && MonitorBorders.Has(currentMonitor)) {
            MonitorBorders[currentMonitor].Show("NoActivate")
        }
        
        lastActiveMonitor := currentMonitor
    }
}

; Save window layout
SaveWindowLayout(hwnd, workspaceID) {
    global WorkspaceLayouts
    
    if (!IsWindowValid(hwnd) || workspaceID < 1 || workspaceID > MAX_WORKSPACES)
        return
        
    if (!WorkspaceLayouts.Has(workspaceID))
        WorkspaceLayouts[workspaceID] := Map()
        
    try {
        WinGetPos(&x, &y, &w, &h, hwnd)
        isMinimized := WinGetMinMax(hwnd) = -1
        isMaximized := WinGetMinMax(hwnd) = 1
        
        WorkspaceLayouts[workspaceID][hwnd] := {
            x: x, y: y, width: w, height: h,
            isMinimized: isMinimized, isMaximized: isMaximized
        }
    } catch {
        LogMessage("Error saving layout for window " . hwnd)
    }
}

; Restore window layout
RestoreWindowLayout(hwnd, workspaceID) {
    global WorkspaceLayouts
    
    if (!IsWindowValid(hwnd))
        return
        
    try {
        if (WinGetMinMax(hwnd) = -1) {
            WinRestore(hwnd)
            Sleep(50)
        }
        
        if (WorkspaceLayouts.Has(workspaceID) && WorkspaceLayouts[workspaceID].Has(hwnd)) {
            layout := WorkspaceLayouts[workspaceID][hwnd]
            
            if (layout.isMaximized) {
                WinMaximize(hwnd)
            } else {
                WinMove(layout.x, layout.y, layout.width, layout.height, hwnd)
            }
        } else {
            WinActivate(hwnd)
        }
        
        WinShow(hwnd)
        WinActivate(hwnd)
    } catch {
        LogMessage("Error restoring layout for window " . hwnd)
    }
}

; Switch to workspace
SwitchToWorkspace(requestedID) {
    global
    
    if (requestedID < 1 || requestedID > MAX_WORKSPACES)
        return
        
    activeMonitor := GetActiveMonitor()
    currentWorkspace := MonitorWorkspaces.Get(activeMonitor, 1)
    
    if (currentWorkspace = requestedID)
        return
        
    ; Check if requested workspace is on another monitor
    otherMonitor := 0
    for monitor, workspace in MonitorWorkspaces {
        if (workspace = requestedID && monitor != activeMonitor) {
            otherMonitor := monitor
            break
        }
    }
    
    if (otherMonitor) {
        ; Exchange workspaces between monitors
        LogMessage("Exchanging workspace " . requestedID . " on monitor " . otherMonitor . " with workspace " . currentWorkspace . " on monitor " . activeMonitor)
        
        ; Minimize all windows on both monitors
        windows := WinGetList()
        for hwnd in windows {
            if (IsWindowValid(hwnd)) {
                monitor := GetWindowMonitor(hwnd)
                if (monitor = activeMonitor || monitor = otherMonitor) {
                    WinMinimize(hwnd)
                    Sleep(5)
                }
            }
        }
        
        ; Swap workspace IDs
        MonitorWorkspaces[otherMonitor] := currentWorkspace
        MonitorWorkspaces[activeMonitor] := requestedID
        
        ; Restore windows on both monitors
        windows := WinGetList()
        for hwnd in windows {
            if (IsWindowValid(hwnd)) {
                windowMonitor := GetWindowMonitor(hwnd)
                
                if (windowMonitor = activeMonitor) {
                    WindowWorkspaces[hwnd] := requestedID
                    if (WinGetMinMax(hwnd) = -1) {
                        RestoreWindowLayout(hwnd, requestedID)
                    }
                } else if (windowMonitor = otherMonitor) {
                    WindowWorkspaces[hwnd] := currentWorkspace
                    if (WinGetMinMax(hwnd) = -1) {
                        RestoreWindowLayout(hwnd, currentWorkspace)
                    }
                }
            }
        }
    } else {
        ; Standard workspace switch
        LogMessage("Switching monitor " . activeMonitor . " from workspace " . currentWorkspace . " to " . requestedID)
        
        ; Minimize windows on current workspace
        windows := WinGetList()
        for hwnd in windows {
            if (IsWindowValid(hwnd) && GetWindowMonitor(hwnd) = activeMonitor) {
                WinMinimize(hwnd)
                Sleep(5)
            }
        }
        
        ; Update monitor workspace
        MonitorWorkspaces[activeMonitor] := requestedID
        
        ; Restore windows on new workspace
        windows := WinGetList()
        for hwnd in windows {
            if (IsWindowValid(hwnd) && GetWindowMonitor(hwnd) = activeMonitor) {
                RestoreWindowLayout(hwnd, requestedID)
                WindowWorkspaces[hwnd] := requestedID
                SaveWindowLayout(hwnd, requestedID)
            }
        }
    }
    
    UpdateAllOverlays()
}

; Create workspace overlay
CreateOverlay(monitorIndex) {
    global
    
    MonitorGetWorkArea(monitorIndex, &left, &top, &right, &bottom)
    
    ; Calculate position
    Switch OVERLAY_POSITION {
        case "TopLeft":
            x := left + OVERLAY_MARGIN
            y := top + OVERLAY_MARGIN
        case "TopRight":
            x := right - OVERLAY_SIZE - OVERLAY_MARGIN
            y := top + OVERLAY_MARGIN
        case "BottomLeft":
            x := left + OVERLAY_MARGIN
            y := bottom - OVERLAY_SIZE - OVERLAY_MARGIN
        default: ; BottomRight
            x := right - OVERLAY_SIZE - OVERLAY_MARGIN
            y := bottom - OVERLAY_SIZE - OVERLAY_MARGIN
    }
    
    overlay := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20")
    overlay.BackColor := "202020"
    overlay.MarginX := 0
    overlay.MarginY := 0
    
    workspaceID := MonitorWorkspaces.Get(monitorIndex, 1)
    textCtrl := overlay.Add("Text", "w" . OVERLAY_SIZE . " h" . OVERLAY_SIZE . " Center cWhite", workspaceID)
    textCtrl.SetFont("s24 bold", "Segoe UI")
    overlay.TextCtrl := textCtrl  ; Store reference to the text control
    
    overlay.Show("x" . x . " y" . y . " w" . OVERLAY_SIZE . " h" . OVERLAY_SIZE . " NoActivate")
    WinSetTransparent(OVERLAY_OPACITY, overlay)
    
    WorkspaceOverlays[monitorIndex] := overlay
}

; Create monitor border
CreateMonitorBorder(monitorIndex) {
    global MonitorBorders, BORDER_COLOR, BORDER_THICKNESS
    
    MonitorGetWorkArea(monitorIndex, &left, &top, &right, &bottom)
    
    border := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20")
    border.BackColor := BORDER_COLOR
    
    width := right - left
    height := bottom - top
    
    border.Show("x" . left . " y" . top . " w" . width . " h" . height . " NoActivate Hide")
    WinSetRegion("0-0 " . width . "-0 " . width . "-" . height . " 0-" . height . " 0-0 " . BORDER_THICKNESS . "-" . BORDER_THICKNESS . " " . BORDER_THICKNESS . "-" . (height - BORDER_THICKNESS) . " " . (width - BORDER_THICKNESS) . "-" . (height - BORDER_THICKNESS) . " " . (width - BORDER_THICKNESS) . "-" . BORDER_THICKNESS . " " . BORDER_THICKNESS . "-" . BORDER_THICKNESS, border)
    
    MonitorBorders[monitorIndex] := border
}

; Update all overlays
UpdateAllOverlays() {
    global WorkspaceOverlays, MonitorWorkspaces
    
    for monitor, overlay in WorkspaceOverlays {
        UpdateOverlay(monitor)
    }
}

; Update single overlay
UpdateOverlay(monitorIndex) {
    global WorkspaceOverlays, MonitorWorkspaces
    
    if (!WorkspaceOverlays.Has(monitorIndex))
        return
        
    overlay := WorkspaceOverlays[monitorIndex]
    workspaceID := MonitorWorkspaces.Get(monitorIndex, 1)
    
    if (overlay.HasProp("TextCtrl")) {
        overlay.TextCtrl.Text := workspaceID
    }
    
    if (overlaysVisible) {
        overlay.Show("NoActivate")
    }
}

; Toggle overlay visibility
ToggleOverlays() {
    global overlaysVisible, WorkspaceOverlays, MonitorBorders
    
    overlaysVisible := !overlaysVisible
    
    if (overlaysVisible) {
        UpdateAllOverlays()
        UpdateActiveMonitor()
    } else {
        for idx, overlay in WorkspaceOverlays {
            overlay.Hide()
        }
        for idx, border in MonitorBorders {
            border.Hide()
        }
    }
}

; Show workspace window list
ShowWorkspaceWindowList() {
    global windowListOverlay
    
    if (windowListOverlay) {
        windowListOverlay.Destroy()
        windowListOverlay := 0
        return
    }
    
    info := "WORKSPACE WINDOW ASSIGNMENTS`n"
    info .= "================================`n`n"
    
    workspaceWindows := Map()
    
    ; Initialize workspace lists
    Loop MAX_WORKSPACES {
        workspaceWindows[A_Index] := []
    }
    
    ; Collect windows by workspace
    for hwnd, workspace in WindowWorkspaces {
        if (workspace > 0 && workspace <= MAX_WORKSPACES && IsWindowValid(hwnd)) {
            try {
                title := WinGetTitle(hwnd)
                if (title != "") {
                    workspaceWindows[workspace].Push(title)
                }
            } catch {
                ; Skip invalid windows
            }
        }
    }
    
    ; Build display text
    Loop MAX_WORKSPACES {
        workspace := A_Index
        isActive := false
        
        for monitor, ws in MonitorWorkspaces {
            if (ws = workspace) {
                isActive := true
                break
            }
        }
        
        info .= "WORKSPACE " . workspace
        if (isActive) {
            info .= " [ACTIVE]"
        }
        info .= "`n"
        
        if (workspaceWindows[workspace].Length > 0) {
            for title in workspaceWindows[workspace] {
                info .= "  - " . title . "`n"
            }
        } else {
            info .= "  (empty)`n"
        }
        info .= "`n"
    }
    
    windowListOverlay := Gui("+AlwaysOnTop +ToolWindow -Caption +E0x20")
    windowListOverlay.BackColor := "000000"
    windowListOverlay.MarginX := 20
    windowListOverlay.MarginY := 20
    
    textCtrl := windowListOverlay.Add("Text", "cWhite", info)
    textCtrl.SetFont("s10", "Consolas")
    
    MouseGetPos(&mouseX, &mouseY)
    windowListOverlay.Show("x" . (mouseX + 20) . " y" . (mouseY + 20) . " NoActivate")
    WinSetTransparent(230, windowListOverlay)
    
    SetTimer(() => UpdateWindowList(), 1000)
}

; Update window list
UpdateWindowList() {
    global windowListOverlay
    
    if (!windowListOverlay)
        return
        
    ; Recreate the overlay with updated information
    windowListOverlay.Destroy()
    windowListOverlay := 0
    ShowWorkspaceWindowList()
}

; Tile windows on active monitor
TileWindowsOnActiveMonitor() {
    activeMonitor := GetActiveMonitor()
    workspace := MonitorWorkspaces.Get(activeMonitor, 1)
    
    ; Get all windows on active monitor and workspace
    windows := []
    allWindows := WinGetList()
    
    for hwnd in allWindows {
        if (IsWindowValid(hwnd) && GetWindowMonitor(hwnd) = activeMonitor) {
            if (WindowWorkspaces.Get(hwnd, 0) = workspace) {
                if (WinGetMinMax(hwnd) != -1) { ; Not minimized
                    windows.Push(hwnd)
                }
            }
        }
    }
    
    if (windows.Length = 0)
        return
        
    MonitorGetWorkArea(activeMonitor, &left, &top, &right, &bottom)
    monitorWidth := right - left
    monitorHeight := bottom - top
    
    ; Calculate grid dimensions
    count := windows.Length
    cols := Ceil(Sqrt(count))
    rows := Ceil(count / cols)
    
    ; Tile windows
    index := 0
    Loop rows {
        row := A_Index - 1
        Loop cols {
            col := A_Index - 1
            index++
            
            if (index > windows.Length)
                break
                
            hwnd := windows[index]
            
            ; Calculate window position and size
            winX := left + (col * monitorWidth // cols)
            winY := top + (row * monitorHeight // rows)
            winWidth := monitorWidth // cols
            winHeight := monitorHeight // rows
            
            ; Restore if maximized
            if (WinGetMinMax(hwnd) = 1) {
                WinRestore(hwnd)
            }
            
            ; Move and resize window
            WinMove(winX, winY, winWidth, winHeight, hwnd)
            SaveWindowLayout(hwnd, workspace)
        }
    }
    
    LogMessage("Tiled " . windows.Length . " windows on monitor " . activeMonitor)
}

; Window move/resize handler
WindowMoveResizeHandler(wParam, lParam, msg, hwnd) {
    global WindowWorkspaces, WorkspaceLayouts, lastWindowState
    
    if (!IsWindowValid(hwnd))
        return
        
    ; Check if minimized
    isMinimized := WinGetMinMax(hwnd) = -1
    wasMinimized := lastWindowState.Get(hwnd, false)
    
    ; Track state changes
    if (wasMinimized && !isMinimized) {
        ; Window was restored from minimized state
        monitor := GetWindowMonitor(hwnd)
        if (MonitorWorkspaces.Has(monitor)) {
            workspace := MonitorWorkspaces[monitor]
            WindowWorkspaces[hwnd] := workspace
            LogMessage("Window " . hwnd . " restored on monitor " . monitor . ", assigned to workspace " . workspace)
        }
    }
    
    lastWindowState[hwnd] := isMinimized
    
    ; Save layout if not minimized
    if (!isMinimized && WindowWorkspaces.Has(hwnd)) {
        workspace := WindowWorkspaces[hwnd]
        if (workspace > 0 && workspace <= MAX_WORKSPACES) {
            SaveWindowLayout(hwnd, workspace)
        }
        
        ; Check if window moved to different monitor
        currentMonitor := GetWindowMonitor(hwnd)
        if (MonitorWorkspaces.Has(currentMonitor)) {
            newWorkspace := MonitorWorkspaces[currentMonitor]
            if (newWorkspace != workspace) {
                WindowWorkspaces[hwnd] := newWorkspace
                SaveWindowLayout(hwnd, newWorkspace)
                LogMessage("Window " . hwnd . " moved to monitor " . currentMonitor . ", reassigned to workspace " . newWorkspace)
            }
        }
    }
}

; New window handler
NewWindowHandler(wParam, lParam, msg, hwnd) {
    SetTimer(() => AssignNewWindow(hwnd), -1000)
}

; Assign new window to workspace
AssignNewWindow(hwnd) {
    global WindowWorkspaces, MonitorWorkspaces
    
    if (!IsWindowValid(hwnd))
        return
        
    monitor := GetWindowMonitor(hwnd)
    
    if (MonitorWorkspaces.Has(monitor)) {
        workspace := MonitorWorkspaces[monitor]
        
        if (!WindowWorkspaces.Has(hwnd)) {
            WindowWorkspaces[hwnd] := workspace
            SaveWindowLayout(hwnd, workspace)
            LogMessage("New window " . hwnd . " assigned to workspace " . workspace)
            
            ; Hide if not on current workspace
            currentWorkspace := MonitorWorkspaces[monitor]
            if (workspace != currentWorkspace) {
                WinMinimize(hwnd)
            }
        } else {
            ; Window already tracked, update if needed
            if (WindowWorkspaces[hwnd] != workspace) {
                WindowWorkspaces[hwnd] := workspace
                SaveWindowLayout(hwnd, workspace)
            }
        }
    } else {
        WindowWorkspaces[hwnd] := 0
    }
}

; Window close handler
WindowCloseHandler(wParam, lParam, msg, hwnd) {
    global WindowWorkspaces, WorkspaceLayouts, lastWindowState, windowListOverlay
    
    if (WindowWorkspaces.Has(hwnd))
        WindowWorkspaces.Delete(hwnd)
    
    if (lastWindowState.Has(hwnd))
        lastWindowState.Delete(hwnd)
    
    for workspace, layouts in WorkspaceLayouts {
        if (layouts.Has(hwnd))
            layouts.Delete(hwnd)
    }
    
    if (windowListOverlay) {
        UpdateWindowList()
    }
}

; Setup event handlers
SetupEventHandlers() {
    OnMessage(0x0005, WindowMoveResizeHandler) ; WM_SIZE
    OnMessage(0x0003, WindowMoveResizeHandler) ; WM_MOVE
    OnMessage(0x0001, NewWindowHandler)        ; WM_CREATE
    OnMessage(0x0002, WindowCloseHandler)      ; WM_DESTROY
    
    ; Periodic cleanup
    SetTimer(CleanupWindowReferences, 60000)
}

; Cleanup stale window references
CleanupWindowReferences() {
    global WindowWorkspaces, WorkspaceLayouts, lastWindowState
    
    ; Remove references to non-existent windows
    toDelete := []
    
    for hwnd in WindowWorkspaces {
        if (!WinExist(hwnd)) {
            toDelete.Push(hwnd)
        }
    }
    
    for hwnd in toDelete {
        if (WindowWorkspaces.Has(hwnd))
            WindowWorkspaces.Delete(hwnd)
        if (lastWindowState.Has(hwnd))
            lastWindowState.Delete(hwnd)
    }
    
    for workspace, layouts in WorkspaceLayouts {
        toDelete := []
        for hwnd in layouts {
            if (!WinExist(hwnd)) {
                toDelete.Push(hwnd)
            }
        }
        for hwnd in toDelete {
            if (layouts.Has(hwnd))
                layouts.Delete(hwnd)
        }
    }
}

; Register keyboard shortcuts
RegisterHotkeys() {
    ; Workspace switching (Ctrl+1 to Ctrl+0 for workspaces 1-10)
    HotKey("^1", (*) => SwitchToWorkspace(1))
    HotKey("^2", (*) => SwitchToWorkspace(2))
    HotKey("^3", (*) => SwitchToWorkspace(3))
    HotKey("^4", (*) => SwitchToWorkspace(4))
    HotKey("^5", (*) => SwitchToWorkspace(5))
    HotKey("^6", (*) => SwitchToWorkspace(6))
    HotKey("^7", (*) => SwitchToWorkspace(7))
    HotKey("^8", (*) => SwitchToWorkspace(8))
    HotKey("^9", (*) => SwitchToWorkspace(9))
    HotKey("^0", (*) => SwitchToWorkspace(10))
    
    ; Extended workspace switching (Ctrl+Alt+1 to Ctrl+Alt+0 for workspaces 11-20)
    HotKey("^!1", (*) => SwitchToWorkspace(11))
    HotKey("^!2", (*) => SwitchToWorkspace(12))
    HotKey("^!3", (*) => SwitchToWorkspace(13))
    HotKey("^!4", (*) => SwitchToWorkspace(14))
    HotKey("^!5", (*) => SwitchToWorkspace(15))
    HotKey("^!6", (*) => SwitchToWorkspace(16))
    HotKey("^!7", (*) => SwitchToWorkspace(17))
    HotKey("^!8", (*) => SwitchToWorkspace(18))
    HotKey("^!9", (*) => SwitchToWorkspace(19))
    HotKey("^!0", (*) => SwitchToWorkspace(20))
    
    ; Send window to workspace (Ctrl+Shift+1 to Ctrl+Shift+0 for workspaces 1-10)
    HotKey("^+1", (*) => SendWindowToWorkspace(1))
    HotKey("^+2", (*) => SendWindowToWorkspace(2))
    HotKey("^+3", (*) => SendWindowToWorkspace(3))
    HotKey("^+4", (*) => SendWindowToWorkspace(4))
    HotKey("^+5", (*) => SendWindowToWorkspace(5))
    HotKey("^+6", (*) => SendWindowToWorkspace(6))
    HotKey("^+7", (*) => SendWindowToWorkspace(7))
    HotKey("^+8", (*) => SendWindowToWorkspace(8))
    HotKey("^+9", (*) => SendWindowToWorkspace(9))
    HotKey("^+0", (*) => SendWindowToWorkspace(10))
    
    ; Send window to extended workspace (Ctrl+Shift+Alt+1 to Ctrl+Shift+Alt+0 for workspaces 11-20)
    HotKey("^+!1", (*) => SendWindowToWorkspace(11))
    HotKey("^+!2", (*) => SendWindowToWorkspace(12))
    HotKey("^+!3", (*) => SendWindowToWorkspace(13))
    HotKey("^+!4", (*) => SendWindowToWorkspace(14))
    HotKey("^+!5", (*) => SendWindowToWorkspace(15))
    HotKey("^+!6", (*) => SendWindowToWorkspace(16))
    HotKey("^+!7", (*) => SendWindowToWorkspace(17))
    HotKey("^+!8", (*) => SendWindowToWorkspace(18))
    HotKey("^+!9", (*) => SendWindowToWorkspace(19))
    HotKey("^+!0", (*) => SendWindowToWorkspace(20))
    
    ; Toggle overlays
    HotKey("!+o", (*) => ToggleOverlays())
    
    ; Refresh monitors
    HotKey("!+r", (*) => RefreshMonitors())
    
    ; Help dialog
    HotKey("!+h", (*) => ShowHelpDialog())
    
    ; Detailed workspace map
    HotKey("!+w", (*) => ShowDetailedWorkspaceMap())
    
    ; Save state
    HotKey("!+s", (*) => SaveWorkspaceState())
    
    ; Tile windows
    HotKey("!+t", (*) => TileWindowsOnActiveMonitor())
}

; Logging function
LogMessage(message) {
    global DEBUG_MODE, LOG_TO_FILE, LOG_FILE, SHOW_WINDOW_EVENT_TOOLTIPS, SHOW_TRAY_NOTIFICATIONS
    
    if (!DEBUG_MODE)
        return
        
    timestamp := FormatTime(, "yyyy-MM-dd HH:mm:ss")
    logEntry := "[" . timestamp . "] " . message
    
    if (LOG_TO_FILE) {
        try {
            FileAppend(logEntry . "`n", LOG_FILE)
        } catch {
            OutputDebug(logEntry)
        }
    } else {
        OutputDebug(logEntry)
    }
    
    if (SHOW_WINDOW_EVENT_TOOLTIPS) {
        ToolTip(message)
        SetTimer(() => ToolTip(), -2000)
    }
    
    if (SHOW_TRAY_NOTIFICATIONS) {
        TrayTip(message, "Cerberus", 1)
    }
}

; Check admin privileges
CheckAdminPrivileges() {
    if (!A_IsAdmin) {
        MsgBox("⚠️ WARNING: Cerberus is not running as Administrator!`n`n" .
               "Some features may not work properly without admin privileges:`n" .
               "- Unable to manage some system windows`n" .
               "- Cannot interact with elevated applications`n`n" .
               "For best results, please run as Administrator.", "Admin Privileges Required", 48)
    }
}

; Show first run instructions
ShowFirstRunInstructions() {
    global FIRST_RUN_FILE
    
    if (!FileExist(FIRST_RUN_FILE)) {
        instructions := "🚀 Welcome to Cerberus Workspace Manager v2.0!`n`n"
        instructions .= "Cerberus gives you 20 virtual workspaces to organize your windows.`n`n"
        instructions .= "🎯 BASIC USAGE:`n"
        instructions .= "• Each monitor has its own active workspace`n"
        instructions .= "• Windows belong to the workspace they were opened in`n"
        instructions .= "• Switching workspaces hides/shows relevant windows`n`n"
        instructions .= "⌨️ ESSENTIAL SHORTCUTS:`n"
        instructions .= "• Ctrl+1-9, Ctrl+0: Switch to workspaces 1-10`n"
        instructions .= "• Ctrl+Alt+1-9, Ctrl+Alt+0: Switch to workspaces 11-20`n"
        instructions .= "• Ctrl+Shift+Number: Send active window to workspace`n"
        instructions .= "• Alt+Shift+H: Show this help again`n"
        instructions .= "• Alt+Shift+W: Show detailed workspace map`n"
        instructions .= "• Alt+Shift+O: Toggle workspace indicators`n`n"
        instructions .= "💡 TIPS:`n"
        instructions .= "• Workspace state is automatically saved`n"
        instructions .= "• Move windows between monitors to reassign them`n"
        instructions .= "• Use Alt+Shift+T to tile windows on current monitor`n`n"
        instructions .= "Press OK to begin organizing your desktop!"
        
        MsgBox(instructions, "Cerberus Workspace Manager - First Run", 64)
        
        try {
            FileAppend("", FIRST_RUN_FILE)
        } catch {
            LogMessage("Could not create first run marker file")
        }
    }
}

; Send window to workspace
SendWindowToWorkspace(workspaceID) {
    global WindowWorkspaces, WorkspaceLayouts, MonitorWorkspaces
    
    if (workspaceID < 1 || workspaceID > MAX_WORKSPACES)
        return
        
    try {
        hwnd := WinGetID("A")
        if (!IsWindowValid(hwnd))
            return
            
        currentWorkspace := WindowWorkspaces.Get(hwnd, 0)
        if (currentWorkspace = workspaceID)
            return
            
        ; Update window assignment
        WindowWorkspaces[hwnd] := workspaceID
        
        ; Save current layout
        SaveWindowLayout(hwnd, workspaceID)
        
        ; Check if target workspace is active on any monitor
        targetIsActive := false
        for monitor, workspace in MonitorWorkspaces {
            if (workspace = workspaceID) {
                targetIsActive := true
                break
            }
        }
        
        ; Hide window if target workspace is not active
        if (!targetIsActive) {
            WinMinimize(hwnd)
        }
        
        title := WinGetTitle(hwnd)
        TrayTip("Window '" . title . "' sent to Workspace " . workspaceID, "Cerberus", 1)
        LogMessage("Sent window " . hwnd . " to workspace " . workspaceID)
        
    } catch as e {
        LogMessage("Error sending window to workspace: " . e.Message)
    }
}

; Update multiple window workspace assignments
UpdateWindowWorkspaces() {
    global WindowWorkspaces, MonitorWorkspaces
    
    windows := WinGetList()
    updatedCount := 0
    
    for hwnd in windows {
        if (IsWindowValid(hwnd)) {
            monitor := GetWindowMonitor(hwnd)
            if (MonitorWorkspaces.Has(monitor)) {
                workspace := MonitorWorkspaces[monitor]
                oldWorkspace := WindowWorkspaces.Get(hwnd, 0)
                
                if (oldWorkspace != workspace) {
                    WindowWorkspaces[hwnd] := workspace
                    SaveWindowLayout(hwnd, workspace)
                    updatedCount++
                }
            }
        }
    }
    
    LogMessage("Updated " . updatedCount . " window workspace assignments")
    return updatedCount
}

; Save workspace state to JSON
SaveWorkspaceState() {
    global STATE_FILE, MonitorWorkspaces, WindowWorkspaces, WorkspaceLayouts
    
    try {
        state := Map()
        state["version"] := "2.0"
        state["timestamp"] := A_Now
        
        ; Convert maps to objects for JSON serialization
        monitorData := {}
        for monitor, workspace in MonitorWorkspaces {
            monitorData.%monitor% := workspace
        }
        state["monitors"] := monitorData
        
        windowData := {}
        for hwnd, workspace in WindowWorkspaces {
            if (IsWindowValid(hwnd)) {
                try {
                    title := WinGetTitle(hwnd)
                    class := WinGetClass(hwnd)
                    process := WinGetProcessName(hwnd)
                    
                    windowData.%hwnd% := {
                        workspace: workspace,
                        title: title,
                        class: class,
                        process: process
                    }
                } catch {
                    ; Skip invalid windows
                }
            }
        }
        state["windows"] := windowData
        
        ; Save layouts
        layoutData := {}
        for workspace, layouts in WorkspaceLayouts {
            workspaceLayouts := {}
            for hwnd, layout in layouts {
                if (IsWindowValid(hwnd)) {
                    workspaceLayouts.%hwnd% := layout
                }
            }
            layoutData.%workspace% := workspaceLayouts
        }
        state["layouts"] := layoutData
        
        ; Convert to JSON
        json := JSON.stringify(state, 2)
        
        ; Write to file
        if (FileExist(STATE_FILE))
            FileDelete(STATE_FILE)
        FileAppend(json, STATE_FILE)
        
        LogMessage("Workspace state saved to " . STATE_FILE)
        return true
        
    } catch as e {
        LogMessage("Error saving workspace state: " . e.Message)
        return false
    }
}

; Load workspace state from JSON
LoadWorkspaceState() {
    global STATE_FILE, MonitorWorkspaces, WindowWorkspaces, WorkspaceLayouts
    
    if (!FileExist(STATE_FILE))
        return false
        
    try {
        json := FileRead(STATE_FILE)
        state := JSON.parse(json)
        
        ; Restore monitor workspaces
        if (state.Has("monitors")) {
            for monitor, workspace in state["monitors"].OwnProps() {
                MonitorWorkspaces[Integer(monitor)] := workspace
            }
        }
        
        ; Note: We don't restore window assignments as windows may have changed
        ; They will be reassigned based on current monitor workspace
        
        LogMessage("Workspace state loaded from " . STATE_FILE)
        return true
        
    } catch as e {
        LogMessage("Error loading workspace state: " . e.Message)
        return false
    }
}

; Auto-save state
AutoSaveState() {
    SaveWorkspaceState()
}

; Exit handler
ExitHandler(reason, exitCode) {
    LogMessage("Cerberus shutting down: " . reason)
    SaveWorkspaceState()
    
    ; Cleanup overlays
    global WorkspaceOverlays, MonitorBorders, windowListOverlay, detailedMapOverlay
    
    for idx, overlay in WorkspaceOverlays {
        overlay.Destroy()
    }
    
    for idx, border in MonitorBorders {
        border.Destroy()
    }
    
    if (windowListOverlay)
        windowListOverlay.Destroy()
        
    if (detailedMapOverlay)
        detailedMapOverlay.Destroy()
}

; Refresh monitor configuration
RefreshMonitors() {
    global
    
    LogMessage("Refreshing monitor configuration...")
    
    ; Save current state
    SaveWorkspaceState()
    
    ; Clear overlays
    for idx, overlay in WorkspaceOverlays {
        overlay.Destroy()
    }
    WorkspaceOverlays.Clear()
    
    for idx, border in MonitorBorders {
        border.Destroy()
    }
    MonitorBorders.Clear()
    
    ; Reinitialize
    InitializeWorkspaces()
    InitializeOverlays()
    UpdateAllOverlays()
    UpdateActiveMonitor()
    
    TrayTip("Monitor configuration refreshed", "Cerberus", 1)
}

; Show help dialog
ShowHelpDialog() {
    help := "🎮 CERBERUS WORKSPACE MANAGER - KEYBOARD SHORTCUTS`n`n"
    help .= "📂 WORKSPACE SWITCHING:`n"
    help .= "Ctrl+1-9, Ctrl+0: Switch to workspaces 1-10`n"
    help .= "Ctrl+Alt+1-9, Ctrl+Alt+0: Switch to workspaces 11-20`n`n"
    help .= "📤 SEND WINDOW TO WORKSPACE:`n"
    help .= "Ctrl+Shift+1-9, Ctrl+Shift+0: Send to workspaces 1-10`n"
    help .= "Ctrl+Shift+Alt+1-9, Ctrl+Shift+Alt+0: Send to workspaces 11-20`n`n"
    help .= "🛠️ UTILITY SHORTCUTS:`n"
    help .= "Alt+Shift+O: Toggle workspace indicators`n"
    help .= "Alt+Shift+W: Show detailed workspace map`n"
    help .= "Alt+Shift+T: Tile windows on active monitor`n"
    help .= "Alt+Shift+S: Save workspace state`n"
    help .= "Alt+Shift+R: Refresh monitor configuration`n"
    help .= "Alt+Shift+H: Show this help`n`n"
    help .= "💡 TIPS:`n"
    help .= "• Move windows between monitors to reassign them`n"
    help .= "• Minimized windows retain their workspace assignment`n"
    help .= "• State is auto-saved every 5 minutes`n"
    help .= "• Run as Administrator for best results"
    
    MsgBox(help, "Cerberus Help", 64)
}

; Show detailed workspace map
ShowDetailedWorkspaceMap() {
    global detailedMapOverlay, MonitorWorkspaces, WindowWorkspaces
    
    if (detailedMapOverlay) {
        detailedMapOverlay.Destroy()
        detailedMapOverlay := 0
        return
    }
    
    ; Build detailed information
    info := "═══════════════════════════════════════════════════════════════`n"
    info .= "                  CERBERUS WORKSPACE MAP`n"
    info .= "═══════════════════════════════════════════════════════════════`n`n"
    
    ; Monitor information
    info .= "📺 MONITOR CONFIGURATION:`n"
    monitorCount := MonitorGetCount()
    Loop monitorCount {
        MonitorGetWorkArea(A_Index, &left, &top, &right, &bottom)
        width := right - left
        height := bottom - top
        workspace := MonitorWorkspaces.Get(A_Index, "?")
        
        info .= Format("Monitor {}: {}x{} at ({},{}) → Workspace {}`n", 
                       A_Index, width, height, left, top, workspace)
    }
    info .= "`n"
    
    ; Workspace details
    workspaceInfo := Map()
    Loop MAX_WORKSPACES {
        workspaceInfo[A_Index] := {windows: [], isActive: false, activeMonitor: 0}
    }
    
    ; Mark active workspaces
    for monitor, workspace in MonitorWorkspaces {
        if (workspaceInfo.Has(workspace)) {
            workspaceInfo[workspace].isActive := true
            workspaceInfo[workspace].activeMonitor := monitor
        }
    }
    
    ; Collect windows
    for hwnd, workspace in WindowWorkspaces {
        if (workspace > 0 && workspace <= MAX_WORKSPACES && IsWindowValid(hwnd)) {
            try {
                title := WinGetTitle(hwnd)
                class := WinGetClass(hwnd)
                process := WinGetProcessName(hwnd)
                isMinimized := WinGetMinMax(hwnd) = -1
                
                windowInfo := Format("{} [{}] ({})", 
                                   StrLen(title) > 40 ? SubStr(title, 1, 40) . "..." : title,
                                   process,
                                   isMinimized ? "minimized" : "visible")
                
                workspaceInfo[workspace].windows.Push(windowInfo)
            } catch {
                ; Skip invalid windows
            }
        }
    }
    
    ; Display workspace information
    info .= "📁 WORKSPACE DETAILS:`n"
    Loop MAX_WORKSPACES {
        workspace := A_Index
        wsInfo := workspaceInfo[workspace]
        
        info .= "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`n"
        info .= "WORKSPACE " . workspace
        
        if (wsInfo.isActive) {
            info .= " 🟢 ACTIVE on Monitor " . wsInfo.activeMonitor
        }
        
        info .= " (" . wsInfo.windows.Length . " windows)`n"
        
        if (wsInfo.windows.Length > 0) {
            for window in wsInfo.windows {
                info .= "  • " . window . "`n"
            }
        } else {
            info .= "  (empty)`n"
        }
    }
    
    ; Create overlay
    detailedMapOverlay := Gui("+AlwaysOnTop +Resize -MaximizeBox -MinimizeBox")
    detailedMapOverlay.Title := "Cerberus Workspace Map"
    detailedMapOverlay.BackColor := "1a1a1a"
    
    ; Add scrollable edit control
    editCtrl := detailedMapOverlay.Add("Edit", "w800 h600 ReadOnly -Wrap vContent", info)
    editCtrl.SetFont("s10", "Consolas")
    
    ; Add close button
    closeBtn := detailedMapOverlay.Add("Button", "w100", "&Close")
    closeBtn.OnEvent("Click", (*) => detailedMapOverlay.Destroy())
    
    ; Show centered on screen
    detailedMapOverlay.Show()
    
    ; Handle close
    detailedMapOverlay.OnEvent("Close", CloseDetailedMap)
}

CloseDetailedMap(*) {
    global detailedMapOverlay
    detailedMapOverlay := 0
}

; JSON helper class (minimal implementation)
class JSON {
    static stringify(obj, indent := 0) {
        if (Type(obj) = "String")
            return '"' . StrReplace(StrReplace(obj, "\", "\\"), '"', '\"') . '"'
        else if (Type(obj) = "Integer" || Type(obj) = "Float")
            return String(obj)
        else if (Type(obj) = "Array") {
            items := []
            for item in obj
                items.Push(JSON.stringify(item, indent))
            return "[" . (items.Length ? "`n" . JSON._indent(indent+1) . JSON._join(items, ",`n" . JSON._indent(indent+1)) . "`n" . JSON._indent(indent) : "") . "]"
        }
        else if (Type(obj) = "Map" || Type(obj) = "Object") {
            items := []
            for key, value in (Type(obj) = "Map" ? obj : obj.OwnProps()) {
                items.Push('"' . key . '": ' . JSON.stringify(value, indent+1))
            }
            return "{" . (items.Length ? "`n" . JSON._indent(indent+1) . JSON._join(items, ",`n" . JSON._indent(indent+1)) . "`n" . JSON._indent(indent) : "") . "}"
        }
        return "null"
    }
    
    static parse(str) {
        ; Very basic JSON parser - for production use, consider a proper JSON library
        return JSON._parseValue(str, 1).value
    }
    
    static _parseValue(str, pos) {
        ; Skip whitespace
        while (pos <= StrLen(str) && InStr(" `t`n`r", SubStr(str, pos, 1)))
            pos++
            
        if (pos > StrLen(str))
            throw Error("Unexpected end of JSON")
            
        ch := SubStr(str, pos, 1)
        
        if (ch = '"')
            return JSON._parseString(str, pos)
        else if (ch = '{')
            return JSON._parseObject(str, pos)
        else if (InStr("0123456789-", ch))
            return JSON._parseNumber(str, pos)
        else if (SubStr(str, pos, 4) = "true")
            return {value: true, pos: pos + 4}
        else if (SubStr(str, pos, 5) = "false")
            return {value: false, pos: pos + 5}
        else if (SubStr(str, pos, 4) = "null")
            return {value: "", pos: pos + 4}
        else
            throw Error("Invalid JSON at position " . pos)
    }
    
    static _parseString(str, pos) {
        pos++ ; Skip opening quote
        value := ""
        
        while (pos <= StrLen(str)) {
            ch := SubStr(str, pos, 1)
            if (ch = '"')
                return {value: value, pos: pos + 1}
            else if (ch = '\')
                throw Error("Escape sequences not implemented")
            else
                value .= ch
            pos++
        }
        
        throw Error("Unterminated string")
    }
    
    static _parseNumber(str, pos) {
        match := RegExMatch(str, "-?\d+(\.\d+)?", &num, pos)
        if (!match)
            throw Error("Invalid number at position " . pos)
        return {value: Number(num[0]), pos: pos + StrLen(num[0])}
    }
    
    static _parseObject(str, pos) {
        obj := Map()
        pos++ ; Skip opening brace
        
        while (pos <= StrLen(str)) {
            ; Skip whitespace
            while (pos <= StrLen(str) && InStr(" `t`n`r", SubStr(str, pos, 1)))
                pos++
                
            if (SubStr(str, pos, 1) = '}')
                return {value: obj, pos: pos + 1}
                
            ; Parse key
            if (SubStr(str, pos, 1) != '"')
                throw Error("Expected string key at position " . pos)
                
            keyResult := JSON._parseString(str, pos)
            key := keyResult.value
            pos := keyResult.pos
            
            ; Skip whitespace and colon
            while (pos <= StrLen(str) && InStr(" `t`n`r", SubStr(str, pos, 1)))
                pos++
            if (SubStr(str, pos, 1) != ':')
                throw Error("Expected ':' at position " . pos)
            pos++
            
            ; Parse value
            valueResult := JSON._parseValue(str, pos)
            obj[key] := valueResult.value
            pos := valueResult.pos
            
            ; Skip whitespace
            while (pos <= StrLen(str) && InStr(" `t`n`r", SubStr(str, pos, 1)))
                pos++
                
            ch := SubStr(str, pos, 1)
            if (ch = ',')
                pos++
            else if (ch != '}')
                throw Error("Expected ',' or '}' at position " . pos)
        }
        
        throw Error("Unterminated object")
    }
    
    static _indent(level) {
        return StrRepeat("  ", level)
    }
    
    static _join(arr, delimiter) {
        result := ""
        for i, item in arr {
            if (i > 1)
                result .= delimiter
            result .= item
        }
        return result
    }
}

StrRepeat(str, count) {
    result := ""
    Loop count
        result .= str
    return result
}