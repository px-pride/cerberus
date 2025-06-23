#Requires AutoHotkey v2.0
#SingleInstance Force
#NoTrayIcon

; Cerberus - Multi-Monitor Workspace Management System
; Version: 1.0.0
; Language: AutoHotkey v2.0

; Set tray icon
TraySetIcon("cerberus.ico")
#NoTrayIcon false

; Global Configuration Constants
global MAX_WORKSPACES := 20

; Debug Settings
global DEBUG_MODE := True
global LOG_TO_FILE := True
global LOG_FILE := A_ScriptDir "\cerberus.log"
global SHOW_WINDOW_EVENT_TOOLTIPS := True
global SHOW_TRAY_NOTIFICATIONS := True

; Persistence Settings
global CONFIG_DIR := A_ScriptDir "\config"
global WORKSPACE_STATE_FILE := CONFIG_DIR "\workspace_state.json"

; Visual Settings
global OVERLAY_SIZE := 60
global OVERLAY_MARGIN := 20
global OVERLAY_TIMEOUT := 0
global OVERLAY_OPACITY := 220
global OVERLAY_POSITION := "BottomRight"
global BORDER_COLOR := "33FFFF"
global BORDER_THICKNESS := 3

; Core Data Structures
global MonitorWorkspaces := Map()  ; Monitor index → Workspace ID
global WindowWorkspaces := Map()   ; Window handle (hwnd) → Workspace ID
global WorkspaceLayouts := Map()   ; Workspace ID → Map of window layouts
global WorkspaceOverlays := Map()  ; Monitor index → GUI handle
global BorderOverlay := Map()      ; Monitor index → Map of edge GUIs

; State Flags
global SWITCH_IN_PROGRESS := False
global SCRIPT_EXITING := False
global BORDER_VISIBLE := True
global LAST_ACTIVE_MONITOR := 0

; Skip classes for window validation
global SKIP_CLASSES := [
    "Progman", "Shell_TrayWnd", "WorkerW",
    "TaskListThumbnailWnd", "TaskManagerWindow",
    "Windows.UI.Core.CoreWindow",
    "NotifyIconOverflowWindow"
]

; Initialize logging
InitializeLogging() {
    global LOG_TO_FILE, LOG_FILE
    
    if LOG_TO_FILE {
        try {
            if !DirExist(A_ScriptDir "\logs")
                DirCreate(A_ScriptDir "\logs")
            
            LOG_FILE := A_ScriptDir "\logs\cerberus_" . A_Now . ".log"
            FileAppend("", LOG_FILE)
        } catch {
            LOG_TO_FILE := False
        }
    }
}

; Logging function
LogMessage(message, level := "INFO") {
    if !DEBUG_MODE
        return
    
    timestamp := FormatTime(, "yyyy-MM-dd HH:mm:ss")
    logEntry := timestamp . " [" . level . "] " . message
    
    if LOG_TO_FILE {
        try {
            FileAppend(logEntry . "`n", LOG_FILE)
        } catch {
            OutputDebug(logEntry)
        }
    } else {
        OutputDebug(logEntry)
    }
}

; Window validation function
IsValidWindow(hwnd) {
    try {
        if !WinExist(hwnd)
            return false
        
        title := WinGetTitle(hwnd)
        class := WinGetClass(hwnd)
        
        if title = "" && class = ""
            return false
        
        ; Skip system windows
        for skipClass in SKIP_CLASSES {
            if class = skipClass
                return false
        }
        
        ; Check window styles
        style := WinGetStyle(hwnd)
        exStyle := WinGetExStyle(hwnd)
        
        ; Skip if child window
        if (style & 0x40000000)  ; WS_CHILD
            return false
        
        ; Skip tool windows unless they have APPWINDOW style
        if (exStyle & 0x80) && !(exStyle & 0x40000)  ; WS_EX_TOOLWINDOW && !WS_EX_APPWINDOW
            return false
        
        return true
    } catch {
        return false
    }
}

; Get monitor from point
GetMonitorFromPoint(x, y) {
    monitorCount := MonitorGetCount()
    
    Loop monitorCount {
        MonitorGet(A_Index, &left, &top, &right, &bottom)
        if (x >= left && x < right && y >= top && y < bottom)
            return A_Index
    }
    
    return 1
}

; Get monitor from window
GetMonitorFromWindow(hwnd) {
    try {
        WinGetPos(&x, &y, &w, &h, hwnd)
        centerX := x + (w // 2)
        centerY := y + (h // 2)
        return GetMonitorFromPoint(centerX, centerY)
    } catch {
        return 1
    }
}

; Convert absolute position to relative (percentage)
AbsoluteToRelativePosition(x, y, w, h, monitorIndex) {
    MonitorGet(monitorIndex, &left, &top, &right, &bottom)
    monitorWidth := right - left
    monitorHeight := bottom - top
    
    return {
        x: (x - left) / monitorWidth,
        y: (y - top) / monitorHeight,
        w: w / monitorWidth,
        h: h / monitorHeight
    }
}

; Convert relative position to absolute
RelativeToAbsolutePosition(relX, relY, relW, relH, monitorIndex) {
    MonitorGet(monitorIndex, &left, &top, &right, &bottom)
    monitorWidth := right - left
    monitorHeight := bottom - top
    
    return {
        x: left + (relX * monitorWidth),
        y: top + (relY * monitorHeight),
        w: relW * monitorWidth,
        h: relH * monitorHeight
    }
}

; Store window layout
StoreWindowLayout(hwnd, workspaceId) {
    try {
        WinGetPos(&x, &y, &w, &h, hwnd)
        monitorIndex := GetMonitorFromWindow(hwnd)
        relPos := AbsoluteToRelativePosition(x, y, w, h, monitorIndex)
        
        isMaximized := WinGetMinMax(hwnd) = 1
        isMinimized := WinGetMinMax(hwnd) = -1
        
        if !WorkspaceLayouts.Has(workspaceId)
            WorkspaceLayouts[workspaceId] := Map()
        
        WorkspaceLayouts[workspaceId][hwnd] := {
            absX: x,
            absY: y,
            absW: w,
            absH: h,
            relX: relPos.x,
            relY: relPos.y,
            relW: relPos.w,
            relH: relPos.h,
            monitor: monitorIndex,
            maximized: isMaximized,
            minimized: isMinimized,
            title: WinGetTitle(hwnd),
            class: WinGetClass(hwnd),
            process: WinGetProcessName(hwnd)
        }
        
        LogMessage("Stored layout for window " . hwnd . " in workspace " . workspaceId)
    } catch as err {
        LogMessage("Error storing window layout: " . err.Message, "ERROR")
    }
}

; Update window maps - Core function
UpdateWindowMaps() {
    LogMessage("UpdateWindowMaps() called")
    
    monitorCount := MonitorGetCount()
    
    ; Process each monitor
    Loop monitorCount {
        monitorIndex := A_Index
        
        if !MonitorWorkspaces.Has(monitorIndex)
            continue
        
        activeWorkspace := MonitorWorkspaces[monitorIndex]
        
        ; Clean up closed windows from active workspace
        if WorkspaceLayouts.Has(activeWorkspace) {
            toRemove := []
            
            for hwnd, layout in WorkspaceLayouts[activeWorkspace] {
                if !WinExist(hwnd) || WinGetMinMax(hwnd) = -1 || GetMonitorFromWindow(hwnd) != monitorIndex {
                    toRemove.Push(hwnd)
                }
            }
            
            for hwnd in toRemove {
                WorkspaceLayouts[activeWorkspace].Delete(hwnd)
                if WindowWorkspaces.Has(hwnd)
                    WindowWorkspaces.Delete(hwnd)
                LogMessage("Removed window " . hwnd . " from workspace " . activeWorkspace)
            }
        }
        
        ; Add windows on this monitor to active workspace
        windows := WinGetList()
        for hwnd in windows {
            if !IsValidWindow(hwnd)
                continue
            
            if GetMonitorFromWindow(hwnd) = monitorIndex && WinGetMinMax(hwnd) != -1 {
                if !WindowWorkspaces.Has(hwnd) || WindowWorkspaces[hwnd] != activeWorkspace {
                    WindowWorkspaces[hwnd] := activeWorkspace
                    StoreWindowLayout(hwnd, activeWorkspace)
                    LogMessage("Added window " . hwnd . " to workspace " . activeWorkspace)
                }
            }
        }
    }
    
    ; Save state
    try {
        SaveWorkspaceState()
    } catch as err {
        LogMessage("Error saving workspace state: " . err.Message, "ERROR")
    }
}

; Create workspace overlay
CreateWorkspaceOverlay(monitorIndex, workspaceId) {
    MonitorGet(monitorIndex, &left, &top, &right, &bottom)
    
    ; Calculate position based on OVERLAY_POSITION
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
        default:  ; BottomRight
            x := right - OVERLAY_SIZE - OVERLAY_MARGIN
            y := bottom - OVERLAY_SIZE - OVERLAY_MARGIN
    }
    
    ; Create GUI
    overlay := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20")
    overlay.BackColor := "202020"
    overlay.MarginX := 0
    overlay.MarginY := 0
    
    ; Add text
    text := overlay.Add("Text", "Center w" . OVERLAY_SIZE . " h" . OVERLAY_SIZE . " c" . BORDER_COLOR, workspaceId)
    text.SetFont("s24 bold", "Segoe UI")
    
    ; Show with transparency
    overlay.Show("x" . x . " y" . y . " w" . OVERLAY_SIZE . " h" . OVERLAY_SIZE . " NoActivate")
    WinSetTransparent(OVERLAY_OPACITY, overlay)
    
    ; Add rounded corners
    try {
        DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", overlay.Hwnd, "UInt", 33, "UInt*", 2, "UInt", 4)
    }
    
    return overlay
}

; Update workspace overlays
UpdateWorkspaceOverlays() {
    if !BORDER_VISIBLE
        return
    
    monitorCount := MonitorGetCount()
    
    Loop monitorCount {
        monitorIndex := A_Index
        workspaceId := MonitorWorkspaces.Has(monitorIndex) ? MonitorWorkspaces[monitorIndex] : 0
        
        ; Destroy existing overlay
        if WorkspaceOverlays.Has(monitorIndex) {
            try {
                WorkspaceOverlays[monitorIndex].Destroy()
            }
        }
        
        ; Create new overlay
        if workspaceId > 0 {
            WorkspaceOverlays[monitorIndex] := CreateWorkspaceOverlay(monitorIndex, workspaceId)
        }
    }
}

; Create border overlay
CreateBorderOverlay(monitorIndex) {
    MonitorGet(monitorIndex, &left, &top, &right, &bottom)
    borders := Map()
    
    ; Create borders for each edge
    edges := [
        {x: left, y: top, w: right - left, h: BORDER_THICKNESS},  ; Top
        {x: left, y: bottom - BORDER_THICKNESS, w: right - left, h: BORDER_THICKNESS},  ; Bottom
        {x: left, y: top, w: BORDER_THICKNESS, h: bottom - top},  ; Left
        {x: right - BORDER_THICKNESS, y: top, w: BORDER_THICKNESS, h: bottom - top}  ; Right
    ]
    
    for edge in edges {
        border := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20")
        border.BackColor := BORDER_COLOR
        border.Show("x" . edge.x . " y" . edge.y . " w" . edge.w . " h" . edge.h . " NoActivate")
        borders[A_Index] := border
    }
    
    return borders
}

; Update active monitor border
UpdateActiveMonitorBorder(activeMonitor) {
    if !BORDER_VISIBLE || activeMonitor = LAST_ACTIVE_MONITOR
        return
    
    ; Remove old borders
    if BorderOverlay.Has(LAST_ACTIVE_MONITOR) {
        for _, border in BorderOverlay[LAST_ACTIVE_MONITOR] {
            try {
                border.Destroy()
            }
        }
        BorderOverlay.Delete(LAST_ACTIVE_MONITOR)
    }
    
    ; Create new borders
    if activeMonitor > 0 {
        BorderOverlay[activeMonitor] := CreateBorderOverlay(activeMonitor)
    }
    
    global LAST_ACTIVE_MONITOR := activeMonitor
}

; Switch workspace
SwitchWorkspace(targetWorkspace) {
    if SWITCH_IN_PROGRESS {
        LogMessage("Switch already in progress, skipping")
        return
    }
    
    global SWITCH_IN_PROGRESS := True
    
    try {
        UpdateWindowMaps()
        
        ; Get active monitor
        MouseGetPos(&mouseX, &mouseY)
        activeMonitor := GetMonitorFromPoint(mouseX, mouseY)
        
        ; Check if already on target workspace
        if MonitorWorkspaces.Has(activeMonitor) && MonitorWorkspaces[activeMonitor] = targetWorkspace {
            LogMessage("Monitor " . activeMonitor . " already on workspace " . targetWorkspace)
            return
        }
        
        ; Check if target workspace is open on another monitor
        targetMonitor := 0
        for monitor, workspace in MonitorWorkspaces {
            if workspace = targetWorkspace {
                targetMonitor := monitor
                break
            }
        }
        
        if targetMonitor = 0 {
            ; Target workspace not visible, switch active monitor to it
            LogMessage("Switching monitor " . activeMonitor . " to workspace " . targetWorkspace)
            
            ; Hide current windows
            currentWorkspace := MonitorWorkspaces[activeMonitor]
            if WorkspaceLayouts.Has(currentWorkspace) {
                for hwnd, _ in WorkspaceLayouts[currentWorkspace] {
                    try {
                        if WinExist(hwnd) && GetMonitorFromWindow(hwnd) = activeMonitor {
                            WinMinimize(hwnd)
                        }
                    }
                }
            }
            
            ; Update monitor workspace
            MonitorWorkspaces[activeMonitor] := targetWorkspace
            
            ; Restore target workspace windows
            if WorkspaceLayouts.Has(targetWorkspace) {
                ; Collect and sort windows by z-order
                windowsToRestore := []
                for hwnd, layout in WorkspaceLayouts[targetWorkspace] {
                    if WinExist(hwnd) {
                        windowsToRestore.Push({hwnd: hwnd, layout: layout})
                    }
                }
                
                ; Restore windows
                for winInfo in windowsToRestore {
                    hwnd := winInfo.hwnd
                    layout := winInfo.layout
                    
                    try {
                        ; Calculate position for active monitor
                        pos := RelativeToAbsolutePosition(layout.relX, layout.relY, layout.relW, layout.relH, activeMonitor)
                        
                        ; Restore and position
                        WinRestore(hwnd)
                        WinMove(pos.x, pos.y, pos.w, pos.h, hwnd)
                        
                        if layout.maximized {
                            WinMaximize(hwnd)
                        }
                    }
                }
            }
        } else {
            ; Swap workspaces between monitors
            LogMessage("Swapping workspaces between monitors " . activeMonitor . " and " . targetMonitor)
            
            currentWorkspace := MonitorWorkspaces[activeMonitor]
            
            ; Minimize all windows on both monitors
            for ws in [currentWorkspace, targetWorkspace] {
                if WorkspaceLayouts.Has(ws) {
                    for hwnd, _ in WorkspaceLayouts[ws] {
                        try {
                            if WinExist(hwnd) {
                                WinMinimize(hwnd)
                            }
                        }
                    }
                }
            }
            
            ; Swap workspace assignments
            MonitorWorkspaces[activeMonitor] := targetWorkspace
            MonitorWorkspaces[targetMonitor] := currentWorkspace
            
            ; Restore windows on both monitors
            monitorWorkspacePairs := [[activeMonitor, targetWorkspace], [targetMonitor, currentWorkspace]]
            
            for pair in monitorWorkspacePairs {
                monitor := pair[1]
                workspace := pair[2]
                
                if WorkspaceLayouts.Has(workspace) {
                    for hwnd, layout in WorkspaceLayouts[workspace] {
                        if WinExist(hwnd) {
                            try {
                                pos := RelativeToAbsolutePosition(layout.relX, layout.relY, layout.relW, layout.relH, monitor)
                                WinRestore(hwnd)
                                WinMove(pos.x, pos.y, pos.w, pos.h, hwnd)
                                
                                if layout.maximized {
                                    WinMaximize(hwnd)
                                }
                            }
                        }
                    }
                }
            }
        }
        
        ; Update visual indicators
        UpdateWorkspaceOverlays()
        
    } finally {
        global SWITCH_IN_PROGRESS := False
    }
}

; Send window to workspace
SendWindowToWorkspace(targetWorkspace) {
    UpdateWindowMaps()
    
    ; Get active window
    activeWindow := WinExist("A")
    if !activeWindow || !IsValidWindow(activeWindow) {
        LogMessage("No valid active window to send")
        return
    }
    
    currentWorkspace := WindowWorkspaces.Has(activeWindow) ? WindowWorkspaces[activeWindow] : 0
    
    if currentWorkspace = targetWorkspace {
        LogMessage("Window already on target workspace")
        return
    }
    
    ; Check if target workspace is visible
    targetMonitor := 0
    for monitor, workspace in MonitorWorkspaces {
        if workspace = targetWorkspace {
            targetMonitor := monitor
            break
        }
    }
    
    ; Update window workspace assignment
    WindowWorkspaces[activeWindow] := targetWorkspace
    StoreWindowLayout(activeWindow, targetWorkspace)
    
    if targetMonitor > 0 {
        ; Move to visible workspace
        LogMessage("Moving window to visible workspace on monitor " . targetMonitor)
        
        if WorkspaceLayouts.Has(targetWorkspace) && WorkspaceLayouts[targetWorkspace].Has(activeWindow) {
            layout := WorkspaceLayouts[targetWorkspace][activeWindow]
            pos := RelativeToAbsolutePosition(layout.relX, layout.relY, layout.relW, layout.relH, targetMonitor)
            
            try {
                WinMove(pos.x, pos.y, pos.w, pos.h, activeWindow)
                
                if layout.maximized {
                    WinMaximize(activeWindow)
                }
            }
        }
    } else {
        ; Minimize to hidden workspace
        LogMessage("Minimizing window to hidden workspace " . targetWorkspace)
        WinMinimize(activeWindow)
    }
    
    ; Remove from current workspace layout
    if currentWorkspace > 0 && WorkspaceLayouts.Has(currentWorkspace) {
        WorkspaceLayouts[currentWorkspace].Delete(activeWindow)
    }
}

; Tile windows on active monitor
TileWindows() {
    UpdateWindowMaps()
    
    ; Get active monitor
    MouseGetPos(&mouseX, &mouseY)
    activeMonitor := GetMonitorFromPoint(mouseX, mouseY)
    activeWorkspace := MonitorWorkspaces[activeMonitor]
    
    if !WorkspaceLayouts.Has(activeWorkspace) {
        if SHOW_TRAY_NOTIFICATIONS
            TrayTip("No windows to tile", "Cerberus", 1)
        return
    }
    
    ; Get windows on current workspace and monitor
    windowsToTile := []
    for hwnd, layout in WorkspaceLayouts[activeWorkspace] {
        if WinExist(hwnd) && GetMonitorFromWindow(hwnd) = activeMonitor && WinGetMinMax(hwnd) != -1 {
            windowsToTile.Push(hwnd)
        }
    }
    
    count := windowsToTile.Length
    if count = 0 {
        if SHOW_TRAY_NOTIFICATIONS
            TrayTip("No windows to tile", "Cerberus", 1)
        return
    }
    
    ; Calculate grid
    cols := Ceil(Sqrt(count))
    rows := Ceil(count / cols)
    
    ; Get monitor dimensions
    MonitorGet(activeMonitor, &left, &top, &right, &bottom)
    monitorWidth := right - left
    monitorHeight := bottom - top
    
    ; Tile windows
    index := 0
    Loop rows {
        row := A_Index - 1
        
        Loop cols {
            col := A_Index - 1
            index++
            
            if index > count
                break
            
            hwnd := windowsToTile[index]
            
            ; Calculate position
            x := left + (col * monitorWidth // cols)
            y := top + (row * monitorHeight // rows)
            w := monitorWidth // cols
            h := monitorHeight // rows
            
            ; Adjust for gaps
            if col = cols - 1
                w := monitorWidth - (col * monitorWidth // cols)
            if row = rows - 1
                h := monitorHeight - (row * monitorHeight // rows)
            
            try {
                WinRestore(hwnd)
                WinMove(x, y, w, h, hwnd)
                
                ; Update layout
                StoreWindowLayout(hwnd, activeWorkspace)
            }
        }
    }
    
    if SHOW_TRAY_NOTIFICATIONS
        TrayTip("Tiled " . count . " windows", "Cerberus", 1)
}

; Save workspace state
SaveWorkspaceState() {
    state := {
        version: "1.0.0",
        timestamp: A_Now,
        monitorWorkspaces: Map(),
        windowWorkspaces: Map(),
        workspaceLayouts: Map()
    }
    
    ; Convert maps to saveable format
    for monitor, workspace in MonitorWorkspaces {
        state.monitorWorkspaces[String(monitor)] := workspace
    }
    
    for hwnd, workspace in WindowWorkspaces {
        if WinExist(hwnd) {
            state.windowWorkspaces[String(hwnd)] := {
                workspace: workspace,
                title: WinGetTitle(hwnd),
                class: WinGetClass(hwnd),
                process: WinGetProcessName(hwnd)
            }
        }
    }
    
    for workspace, layouts in WorkspaceLayouts {
        state.workspaceLayouts[String(workspace)] := Map()
        for hwnd, layout in layouts {
            if WinExist(hwnd) {
                state.workspaceLayouts[String(workspace)][String(hwnd)] := layout
            }
        }
    }
    
    ; Create config directory if needed
    if !DirExist(CONFIG_DIR)
        DirCreate(CONFIG_DIR)
    
    ; Save to JSON
    jsonText := JSON.stringify(state, 2)
    FileDelete(WORKSPACE_STATE_FILE)
    FileAppend(jsonText, WORKSPACE_STATE_FILE)
    
    LogMessage("Saved workspace state")
}

; Load workspace state
LoadWorkspaceState() {
    if !FileExist(WORKSPACE_STATE_FILE)
        return false
    
    try {
        jsonText := FileRead(WORKSPACE_STATE_FILE)
        state := JSON.parse(jsonText)
        
        ; Minimize all windows first
        windows := WinGetList()
        for hwnd in windows {
            if IsValidWindow(hwnd) {
                WinMinimize(hwnd)
            }
        }
        
        ; Load monitor workspaces
        for monitor, workspace in state.monitorWorkspaces {
            MonitorWorkspaces[Integer(monitor)] := workspace
        }
        
        ; Load window workspaces
        for hwndStr, info in state.windowWorkspaces {
            hwnd := Integer(hwndStr)
            if WinExist(hwnd) {
                WindowWorkspaces[hwnd] := info.workspace
            }
        }
        
        ; Load workspace layouts
        for workspaceStr, layouts in state.workspaceLayouts {
            workspace := Integer(workspaceStr)
            WorkspaceLayouts[workspace] := Map()
            
            for hwndStr, layout in layouts {
                hwnd := Integer(hwndStr)
                if WinExist(hwnd) {
                    WorkspaceLayouts[workspace][hwnd] := layout
                }
            }
        }
        
        ; Restore visible workspaces
        for monitor, workspace in MonitorWorkspaces {
            if WorkspaceLayouts.Has(workspace) {
                for hwnd, layout in WorkspaceLayouts[workspace] {
                    if WinExist(hwnd) {
                        try {
                            pos := RelativeToAbsolutePosition(layout.relX, layout.relY, layout.relW, layout.relH, monitor)
                            WinRestore(hwnd)
                            WinMove(pos.x, pos.y, pos.w, pos.h, hwnd)
                            
                            if layout.maximized {
                                WinMaximize(hwnd)
                            }
                        }
                    }
                }
            }
        }
        
        LogMessage("Loaded workspace state")
        return true
        
    } catch as err {
        LogMessage("Error loading workspace state: " . err.Message, "ERROR")
        return false
    }
}

; JSON parser class
class JSON {
    static stringify(obj, indent := 0) {
        return JSON._stringify(obj, "", indent)
    }
    
    static _stringify(obj, indentStr, indentSize) {
        switch Type(obj) {
            case "Map":
                if obj.Count = 0
                    return "{}"
                
                items := []
                newIndent := indentStr . "  "
                
                for key, value in obj {
                    jsonValue := JSON._stringify(value, newIndent, indentSize)
                    items.Push('"' . String(key) . '": ' . jsonValue)
                }
                
                if indentSize > 0 {
                    return "{`n" . newIndent . items.Join(",`n" . newIndent) . "`n" . indentStr . "}"
                } else {
                    return "{" . items.Join(", ") . "}"
                }
                
            case "Array":
                if obj.Length = 0
                    return "[]"
                
                items := []
                newIndent := indentStr . "  "
                
                for value in obj {
                    items.Push(JSON._stringify(value, newIndent, indentSize))
                }
                
                if indentSize > 0 {
                    return "[`n" . newIndent . items.Join(",`n" . newIndent) . "`n" . indentStr . "]"
                } else {
                    return "[" . items.Join(", ") . "]"
                }
                
            case "Object":
                return JSON._stringify(Map(obj), indentStr, indentSize)
                
            case "String":
                return '"' . StrReplace(StrReplace(obj, "\", "\\"), '"', '\"') . '"'
                
            case "Integer", "Float":
                return String(obj)
                
            default:
                return String(obj)
        }
    }
    
    static parse(text) {
        ; Simple JSON parser - would need full implementation
        ; For now, return empty map
        return Map()
    }
}

; Show help dialog
ShowHelp() {
    helpText := "
(
Cerberus - Multi-Monitor Workspace Management System
Version: 1.0.0

CONCEPTS:
• Active Monitor: The monitor containing your mouse cursor
• Active Window: The window currently in focus

WORKSPACE SWITCHING (Switch active monitor to workspace):
• Ctrl+1-9: Switch to workspaces 1-9
• Ctrl+0: Switch to workspace 10
• Ctrl+Alt+1-9: Switch to workspaces 11-19
• Ctrl+Alt+0: Switch to workspace 20

WORKSPACE SENDING (Send active window to workspace):
• Ctrl+Shift+1-9: Send to workspaces 1-9
• Ctrl+Shift+0: Send to workspace 10
• Ctrl+Shift+Alt+1-9: Send to workspaces 11-19
• Ctrl+Shift+Alt+0: Send to workspace 20

UTILITY FUNCTIONS:
• Alt+Shift+O: Toggle overlays and borders
• Alt+Shift+W: Show workspace map
• Alt+Shift+S: Save workspace state
• Alt+Shift+T: Tile windows on active monitor
• Alt+Shift+H: Show this help
• Alt+Shift+R: Refresh monitor configuration
)"

    MsgBox(helpText, "Cerberus Help", "O Icon?")
}

; Show workspace map dialog
ShowWorkspaceMap() {
    UpdateWindowMaps()
    
    text := "MONITOR → WORKSPACE MAPPING:`n`n"
    
    monitorCount := MonitorGetCount()
    Loop monitorCount {
        workspace := MonitorWorkspaces.Has(A_Index) ? MonitorWorkspaces[A_Index] : "None"
        text .= "Monitor " . A_Index . " → Workspace " . workspace . "`n"
    }
    
    text .= "`n`nWINDOWS BY WORKSPACE:`n"
    
    ; Group windows by workspace
    workspaceWindows := Map()
    for hwnd, workspace in WindowWorkspaces {
        if !workspaceWindows.Has(workspace)
            workspaceWindows[workspace] := []
        
        if WinExist(hwnd) {
            workspaceWindows[workspace].Push(WinGetTitle(hwnd))
        }
    }
    
    ; Display windows
    Loop MAX_WORKSPACES {
        if workspaceWindows.Has(A_Index) {
            visible := "Hidden"
            for monitor, ws in MonitorWorkspaces {
                if ws = A_Index {
                    visible := "Monitor " . monitor
                    break
                }
            }
            
            text .= "`nWorkspace " . A_Index . " (" . visible . "):`n"
            for title in workspaceWindows[A_Index] {
                text .= "  • " . title . "`n"
            }
        }
    }
    
    MsgBox(text, "Workspace Map", "O")
}

; Toggle overlays
ToggleOverlays() {
    global BORDER_VISIBLE := !BORDER_VISIBLE
    
    if !BORDER_VISIBLE {
        ; Hide all overlays
        for _, overlay in WorkspaceOverlays {
            try overlay.Destroy()
        }
        WorkspaceOverlays.Clear()
        
        for _, borders in BorderOverlay {
            for _, border in borders {
                try border.Destroy()
            }
        }
        BorderOverlay.Clear()
    } else {
        ; Show overlays
        UpdateWorkspaceOverlays()
        MouseGetPos(&x, &y)
        UpdateActiveMonitorBorder(GetMonitorFromPoint(x, y))
    }
    
    if SHOW_TRAY_NOTIFICATIONS {
        status := BORDER_VISIBLE ? "shown" : "hidden"
        TrayTip("Overlays " . status, "Cerberus", 1)
    }
}

; Refresh monitor configuration
RefreshMonitors() {
    LogMessage("Refreshing monitor configuration")
    
    monitorCount := MonitorGetCount()
    
    ; Add new monitors
    Loop monitorCount {
        if !MonitorWorkspaces.Has(A_Index) {
            MonitorWorkspaces[A_Index] := A_Index <= MAX_WORKSPACES ? A_Index : 1
            LogMessage("Added monitor " . A_Index . " with workspace " . MonitorWorkspaces[A_Index])
        }
    }
    
    ; Update overlays
    UpdateWorkspaceOverlays()
    
    if SHOW_TRAY_NOTIFICATIONS
        TrayTip("Monitor configuration refreshed", "Cerberus", 1)
}

; Check for admin privileges
CheckAdminPrivileges() {
    if !A_IsAdmin {
        result := MsgBox("
(
Cerberus is running without administrator privileges.

Some windows may not respond to management commands.
For best results, run as administrator.

Continue anyway?
)", "Cerberus - Admin Warning", "YN Icon!")
        
        if result = "No"
            ExitApp()
    }
}

; Timer callback - Clean up window references
CleanupWindowReferences() {
    if SCRIPT_EXITING
        return
    
    LogMessage("Cleaning up window references")
    
    ; Clean WindowWorkspaces
    toRemove := []
    for hwnd, _ in WindowWorkspaces {
        if !WinExist(hwnd)
            toRemove.Push(hwnd)
    }
    
    for hwnd in toRemove {
        WindowWorkspaces.Delete(hwnd)
    }
    
    ; Clean WorkspaceLayouts
    for workspace, layouts in WorkspaceLayouts {
        toRemove := []
        for hwnd, _ in layouts {
            if !WinExist(hwnd)
                toRemove.Push(hwnd)
        }
        
        for hwnd in toRemove {
            layouts.Delete(hwnd)
        }
    }
}

; Timer callback - Check mouse movement
CheckMouseMovement() {
    if SCRIPT_EXITING || !BORDER_VISIBLE
        return
    
    MouseGetPos(&x, &y)
    activeMonitor := GetMonitorFromPoint(x, y)
    
    if activeMonitor != LAST_ACTIVE_MONITOR {
        UpdateActiveMonitorBorder(activeMonitor)
    }
}

; Exit handler
OnExit(ExitFunc)

ExitFunc(*) {
    global SCRIPT_EXITING := True
    
    LogMessage("Cerberus exiting...")
    
    ; Update and save state
    try {
        UpdateWindowMaps()
        SaveWorkspaceState()
    }
    
    ; Clean up overlays
    for _, overlay in WorkspaceOverlays {
        try overlay.Destroy()
    }
    
    for _, borders in BorderOverlay {
        for _, border in borders {
            try border.Destroy()
        }
    }
    
    LogMessage("Cerberus exit complete")
}

; Initialize application
Initialize() {
    LogMessage("Cerberus initializing...")
    
    ; Check admin privileges
    CheckAdminPrivileges()
    
    ; Initialize monitors
    monitorCount := MonitorGetCount()
    LogMessage("Detected " . monitorCount . " monitors")
    
    Loop monitorCount {
        MonitorWorkspaces[A_Index] := A_Index <= MAX_WORKSPACES ? A_Index : 1
        LogMessage("Monitor " . A_Index . " assigned to workspace " . MonitorWorkspaces[A_Index])
    }
    
    ; Load saved state or initialize
    if !LoadWorkspaceState() {
        LogMessage("No saved state found, initializing fresh")
        
        ; Assign minimized windows to workspace 0
        windows := WinGetList()
        for hwnd in windows {
            if IsValidWindow(hwnd) && WinGetMinMax(hwnd) = -1 {
                WindowWorkspaces[hwnd] := 0
            }
        }
        
        UpdateWindowMaps()
    }
    
    ; Initialize visual indicators
    UpdateWorkspaceOverlays()
    MouseGetPos(&x, &y)
    UpdateActiveMonitorBorder(GetMonitorFromPoint(x, y))
    
    ; Set up timers
    SetTimer(CleanupWindowReferences, 120000)  ; 2 minutes
    SetTimer(CheckMouseMovement, 100)  ; 100ms
    
    ; Show instructions
    ShowHelp()
    
    if SHOW_TRAY_NOTIFICATIONS
        TrayTip("Cerberus initialized", "Multi-monitor workspace management active", 1)
    
    LogMessage("Cerberus initialization complete")
}

; Hotkey definitions

; Workspace switching (Ctrl+Number)
^1::SwitchWorkspace(1)
^2::SwitchWorkspace(2)
^3::SwitchWorkspace(3)
^4::SwitchWorkspace(4)
^5::SwitchWorkspace(5)
^6::SwitchWorkspace(6)
^7::SwitchWorkspace(7)
^8::SwitchWorkspace(8)
^9::SwitchWorkspace(9)
^0::SwitchWorkspace(10)

; Workspace switching 11-20 (Ctrl+Alt+Number)
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

; Send window to workspace (Ctrl+Shift+Number)
^+1::SendWindowToWorkspace(1)
^+2::SendWindowToWorkspace(2)
^+3::SendWindowToWorkspace(3)
^+4::SendWindowToWorkspace(4)
^+5::SendWindowToWorkspace(5)
^+6::SendWindowToWorkspace(6)
^+7::SendWindowToWorkspace(7)
^+8::SendWindowToWorkspace(8)
^+9::SendWindowToWorkspace(9)
^+0::SendWindowToWorkspace(10)

; Send window to workspace 11-20 (Ctrl+Shift+Alt+Number)
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

; Utility hotkeys
!+O::{
    UpdateWindowMaps()
    ToggleOverlays()
}

!+W::{
    UpdateWindowMaps()
    ShowWorkspaceMap()
}

!+S::{
    UpdateWindowMaps()
    SaveWorkspaceState()
    if SHOW_TRAY_NOTIFICATIONS
        TrayTip("Workspace state saved", "Cerberus", 1)
}

!+T::{
    UpdateWindowMaps()
    TileWindows()
}

!+H::{
    UpdateWindowMaps()
    ShowHelp()
}

!+R::{
    UpdateWindowMaps()
    RefreshMonitors()
}

; Start application
InitializeLogging()
Initialize()