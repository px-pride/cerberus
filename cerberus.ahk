#Requires AutoHotkey v2.0
#SingleInstance Force
#Warn All

TraySetIcon("cerberus.ico")
A_MenuMaskKey := "vkFF"

global VERSION := "1.0.0"
global MAX_WORKSPACES := 20

global DEBUG_MODE := True
global LOG_TO_FILE := True
global LOGS_DIR := A_ScriptDir "\logs"
global LOG_FILE := ""
global SHOW_WINDOW_EVENT_TOOLTIPS := True
global SHOW_TRAY_NOTIFICATIONS := True
global SHOW_DIALOG_BOXES := False

global CONFIG_DIR := A_ScriptDir "\config"
global WORKSPACE_STATE_FILE := CONFIG_DIR "\workspace_state.json"

global OVERLAY_SIZE := 60
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
global BorderOverlay := Map()

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
    
    timestamp := FormatTime(, "yyyy-MM-dd HH:mm:ss")
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
    CoordMode("Mouse", "Screen")
    MouseGetPos(&mx, &my)
    
    monitorCount := MonitorGetCount()
    Loop monitorCount {
        MonitorGetWorkArea(A_Index, &left, &top, &right, &bottom)
        if (mx >= left && mx < right && my >= top && my < bottom) {
            return A_Index
        }
    }
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
    
    return {
        x: left + (layout.xPercent * monitorWidth),
        y: top + (layout.yPercent * monitorHeight),
        width: layout.widthPercent * monitorWidth,
        height: layout.heightPercent * monitorHeight
    }
}

UpdateWindowMaps() {
    global MonitorWorkspaces, WindowWorkspaces, WorkspaceLayouts
    
    LogDebug("UpdateWindowMaps called")
    
    monitorCount := MonitorGetCount()
    Loop monitorCount {
        monitorIndex := A_Index
        
        if (!MonitorWorkspaces.Has(monitorIndex)) {
            continue
        }
        
        activeWorkspace := MonitorWorkspaces[monitorIndex]
        if (activeWorkspace == 0) {
            continue
        }
        
        if (WorkspaceLayouts.Has(activeWorkspace)) {
            windowsToRemove := []
            for hwnd, layout in WorkspaceLayouts[activeWorkspace] {
                if (!WinExist(hwnd)) {
                    windowsToRemove.Push(hwnd)
                    continue
                }
                
                try {
                    minMax := WinGetMinMax(hwnd)
                    if (minMax == -1) {
                        windowsToRemove.Push(hwnd)
                        continue
                    }
                    
                    currentMonitor := GetMonitorForWindow(hwnd)
                    if (currentMonitor != monitorIndex) {
                        windowsToRemove.Push(hwnd)
                        continue
                    }
                } catch {
                    windowsToRemove.Push(hwnd)
                }
            }
            
            for hwnd in windowsToRemove {
                WorkspaceLayouts[activeWorkspace].Delete(hwnd)
                if (WindowWorkspaces.Has(hwnd)) {
                    WindowWorkspaces.Delete(hwnd)
                }
            }
        }
        
        windows := WinGetList()
        for hwnd in windows {
            if (!IsValidWindow(hwnd)) {
                continue
            }
            
            currentMonitor := GetMonitorForWindow(hwnd)
            if (currentMonitor != monitorIndex) {
                continue
            }
            
            try {
                minMax := WinGetMinMax(hwnd)
                if (minMax == -1) {
                    continue
                }
                
                if (!WindowWorkspaces.Has(hwnd) || WindowWorkspaces[hwnd] != activeWorkspace) {
                    WindowWorkspaces[hwnd] := activeWorkspace
                    
                    if (!WorkspaceLayouts.Has(activeWorkspace)) {
                        WorkspaceLayouts[activeWorkspace] := Map()
                    }
                    
                    WinGetPos(&x, &y, &w, &h, hwnd)
                    relPos := AbsoluteToRelativePosition(x, y, w, h, monitorIndex)
                    
                    WorkspaceLayouts[activeWorkspace][hwnd] := {
                        xPercent: relPos.xPercent,
                        yPercent: relPos.yPercent,
                        widthPercent: relPos.widthPercent,
                        heightPercent: relPos.heightPercent,
                        monitor: monitorIndex,
                        state: minMax
                    }
                }
            } catch {
                LogDebug("Error processing window: " hwnd)
            }
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
                for hwnd, layout in WorkspaceLayouts[targetWorkspace] {
                    try {
                        if (WinExist(hwnd)) {
                            absPos := RelativeToAbsolutePosition(layout, activeMonitor)
                            
                            if (layout.state == 1) {
                                WinRestore(hwnd)
                                WinMaximize(hwnd)
                            } else {
                                WinRestore(hwnd)
                                WinMove(absPos.x, absPos.y, absPos.width, absPos.height, hwnd)
                            }
                        }
                    } catch {
                        LogDebug("Error restoring window: " hwnd)
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
                                WinMove(absPos.x, absPos.y, absPos.width, absPos.height, hwnd)
                                WinMaximize(hwnd)
                            } else {
                                WinMove(absPos.x, absPos.y, absPos.width, absPos.height, hwnd)
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
                                WinMove(absPos.x, absPos.y, absPos.width, absPos.height, hwnd)
                                WinMaximize(hwnd)
                            } else {
                                WinMove(absPos.x, absPos.y, absPos.width, absPos.height, hwnd)
                            }
                            
                            layout.monitor := activeMonitor
                        }
                    } catch {
                        LogDebug("Error moving window to active monitor: " hwnd)
                    }
                }
            }
            
            Loop windowOrder.Length {
                idx := windowOrder.Length - A_Index + 1
                try {
                    WinMoveBottom(windowOrder[idx])
                } catch {
                }
            }
            
            UpdateWorkspaceOverlays()
        }
        
    } finally {
        SWITCH_IN_PROGRESS := False
    }
}

SendWindowToWorkspace(targetWorkspace) {
    global WindowWorkspaces, WorkspaceLayouts, MonitorWorkspaces, SWITCH_IN_PROGRESS
    
    if (SWITCH_IN_PROGRESS) {
        return
    }
    
    SWITCH_IN_PROGRESS := True
    
    try {
        UpdateWindowMaps()
        
        hwnd := WinGetID("A")
        if (!IsValidWindow(hwnd)) {
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
        
        if (currentWorkspace > 0 && WorkspaceLayouts.Has(currentWorkspace)) {
            WorkspaceLayouts[currentWorkspace].Delete(hwnd)
        }
        
        WindowWorkspaces[hwnd] := targetWorkspace
        
        if (!WorkspaceLayouts.Has(targetWorkspace)) {
            WorkspaceLayouts[targetWorkspace] := Map()
        }
        
        if (targetMonitor > 0) {
            WinGetPos(&x, &y, &w, &h, hwnd)
            currentMonitor := GetMonitorForWindow(hwnd)
            relPos := AbsoluteToRelativePosition(x, y, w, h, currentMonitor)
            
            absPos := RelativeToAbsolutePosition(relPos, targetMonitor)
            WinMove(absPos.x, absPos.y, absPos.width, absPos.height, hwnd)
            
            WorkspaceLayouts[targetWorkspace][hwnd] := {
                xPercent: relPos.xPercent,
                yPercent: relPos.yPercent,
                widthPercent: relPos.widthPercent,
                heightPercent: relPos.heightPercent,
                monitor: targetMonitor,
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
                monitor: currentMonitor,
                state: WinGetMinMax(hwnd)
            }
            
            WinMinimize(hwnd)
        }
        
        SaveWorkspaceState()
        
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
    
    index := 0
    Loop rows {
        row := A_Index - 1
        Loop cols {
            col := A_Index - 1
            
            if (++index > count) {
                break
            }
            
            hwnd := windows[index]
            
            x := left + (col * tileWidth)
            y := top + (row * tileHeight)
            w := tileWidth
            h := tileHeight
            
            if (col == cols - 1) {
                w := monitorWidth - (col * tileWidth)
            }
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
                    monitor: activeMonitor,
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

SaveWorkspaceState() {
    global CONFIG_DIR, WORKSPACE_STATE_FILE, WindowWorkspaces, WorkspaceLayouts, MonitorWorkspaces
    
    if (!DirExist(CONFIG_DIR)) {
        DirCreate(CONFIG_DIR)
    }
    
    state := {
        version: VERSION,
        timestamp: A_Now,
        monitors: Map(),
        windows: []
    }
    
    for monitor, workspace in MonitorWorkspaces {
        state.monitors[monitor] := workspace
    }
    
    for hwnd, workspace in WindowWorkspaces {
        try {
            windowData := {
                hwnd: hwnd,
                workspace: workspace,
                title: WinGetTitle(hwnd),
                class: WinGetClass(hwnd),
                process: WinGetProcessName(hwnd)
            }
            
            if (WorkspaceLayouts.Has(workspace) && WorkspaceLayouts[workspace].Has(hwnd)) {
                windowData.layout := WorkspaceLayouts[workspace][hwnd]
            }
            
            state.windows.Push(windowData)
        } catch {
            LogDebug("Error saving window state: " hwnd)
        }
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
    global WORKSPACE_STATE_FILE, WindowWorkspaces, WorkspaceLayouts, MonitorWorkspaces
    
    if (!FileExist(WORKSPACE_STATE_FILE)) {
        LogDebug("No saved workspace state found")
        return false
    }
    
    try {
        jsonStr := FileRead(WORKSPACE_STATE_FILE)
        stateData := Jxon_Load(&jsonStr)
        
        windows := WinGetList()
        for hwnd in windows {
            if (IsValidWindow(hwnd)) {
                try {
                    WinMinimize(hwnd)
                } catch {
                }
            }
        }
        
        if (stateData.HasOwnProp("monitors")) {
            for monIdx, wsId in stateData.monitors.OwnProps() {
                MonitorWorkspaces[Number(monIdx)] := wsId
            }
        }
        
        if (stateData.HasOwnProp("windows")) {
            for windowData in stateData.windows {
                found := false
                
                windows := WinGetList()
                for hwnd in windows {
                    try {
                        if (WinGetClass(hwnd) == windowData.class && 
                            WinGetProcessName(hwnd) == windowData.process) {
                            
                            WindowWorkspaces[hwnd] := windowData.workspace
                            
                            if (windowData.HasOwnProp("layout")) {
                                if (!WorkspaceLayouts.Has(windowData.workspace)) {
                                    WorkspaceLayouts[windowData.workspace] := Map()
                                }
                                WorkspaceLayouts[windowData.workspace][hwnd] := windowData.layout
                            }
                            
                            found := true
                            break
                        }
                    } catch {
                    }
                }
                
                if (!found) {
                    LogDebug("Window not found: " windowData.title)
                }
            }
        }
        
        for monIdx, wsId in MonitorWorkspaces {
            if (WorkspaceLayouts.Has(wsId)) {
                for hwnd, layout in WorkspaceLayouts[wsId] {
                    try {
                        if (WinExist(hwnd)) {
                            absPos := RelativeToAbsolutePosition(layout, monIdx)
                            
                            if (layout.state == 1) {
                                WinRestore(hwnd)
                                WinMaximize(hwnd)
                            } else {
                                WinRestore(hwnd)
                                WinMove(absPos.x, absPos.y, absPos.width, absPos.height, hwnd)
                            }
                        }
                    } catch {
                        LogDebug("Error restoring window: " hwnd)
                    }
                }
            }
        }
        
        LogDebug("Workspace state loaded")
        return true
        
    } catch as e {
        LogDebug("Error loading workspace state: " e.Message)
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
• Ctrl+1-9: Switch to workspaces 1-9
• Ctrl+0: Switch to workspace 10
• Ctrl+Alt+1-9: Switch to workspaces 11-19
• Ctrl+Alt+0: Switch to workspace 20

Window Sending (moves active window to workspace):
• Ctrl+Shift+1-9: Send to workspaces 1-9
• Ctrl+Shift+0: Send to workspace 10
• Ctrl+Shift+Alt+1-9: Send to workspaces 11-19
• Ctrl+Shift+Alt+0: Send to workspace 20

Utility Functions:
• Alt+Shift+O: Toggle overlays and borders
• Alt+Shift+W: Show workspace map
• Alt+Shift+S: Save workspace state
• Alt+Shift+T: Tile windows on active monitor
• Alt+Shift+H: Show this help
• Alt+Shift+R: Refresh monitor configuration
    )"
    
    MsgBox(instructionText, "Cerberus Instructions", "OK")
}

ShowWorkspaceMap() {
    global MonitorWorkspaces, WindowWorkspaces, WorkspaceLayouts
    
    UpdateWindowMaps()
    
    mapText := "MONITOR → WORKSPACE ASSIGNMENTS:`n`n"
    
    monitorCount := MonitorGetCount()
    Loop monitorCount {
        workspace := MonitorWorkspaces.Has(A_Index) ? MonitorWorkspaces[A_Index] : "None"
        mapText .= "Monitor " A_Index " → Workspace " workspace "`n"
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
                mapText .= "Workspace " A_Index " (" status ", " windowCount " windows):`n"
                
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
    
    mapWindow := Gui("+Resize", "Workspace Map")
    mapWindow.SetFont("s10", "Consolas")
    textCtrl := mapWindow.Add("Edit", "ReadOnly w600 h400", mapText)
    mapWindow.Add("Button", "w100", "OK").OnEvent("Click", (*) => mapWindow.Close())
    mapWindow.Show()
}

ToggleOverlays() {
    global BORDER_VISIBLE, WorkspaceOverlays, BorderOverlay
    
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
    
    UpdateWindowMaps()
    
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
    global WindowWorkspaces, WorkspaceLayouts
    
    windowsToRemove := []
    
    for hwnd, _ in WindowWorkspaces {
        if (!WinExist(hwnd)) {
            windowsToRemove.Push(hwnd)
        }
    }
    
    for hwnd in windowsToRemove {
        WindowWorkspaces.Delete(hwnd)
        
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

ExitHandler(reason, code) {
    global SCRIPT_EXITING, WorkspaceOverlays, BorderOverlay
    
    SCRIPT_EXITING := True
    
    UpdateWindowMaps()
    SaveWorkspaceState()
    
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
    
    for monIdx, _ in BorderOverlay {
        DestroyBorderOverlay(monIdx)
    }
    
    LogDebug("Cerberus exiting: " reason)
}

Initialize() {
    global MonitorWorkspaces, WindowWorkspaces, SHOW_TRAY_NOTIFICATIONS
    
    InitializeLogging()
    
    LogDebug("Initialize: Starting Cerberus initialization")
    
    if (!IsAdmin() && SHOW_DIALOG_BOXES) {
        MsgBox("Warning: Running without administrator privileges.`n`nSome windows may not be manageable.", "Cerberus", "Icon!")
    }
    
    OnExit(ExitHandler)
    
    LogDebug("Initialize: Calling RefreshMonitors")
    RefreshMonitors()
    
    LogDebug("Initialize: MonitorWorkspaces after RefreshMonitors: " MonitorWorkspaces.Count " monitors")
    
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
    
    UpdateWorkspaceOverlays()
    UpdateActiveMonitorBorder()
    
    SetTimer(CleanupWindowReferences, 120000)
    SetTimer(CheckMouseMovement, 100)
    
    if (SHOW_DIALOG_BOXES) {
        ShowInstructions()
    }
    
    if (SHOW_TRAY_NOTIFICATIONS) {
        TrayTip("Cerberus initialized", "Multi-monitor workspace manager ready", 1)
    }
    
    LogDebug("Cerberus initialized successfully")
    LogDebug("Running cerberus4.ahk version " VERSION)
}

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

!+o::{
    UpdateWindowMaps()
    ToggleOverlays()
}

!+w::{
    UpdateWindowMaps()
    ShowWorkspaceMap()
}

!+s::{
    UpdateWindowMaps()
    SaveWorkspaceState()
    if (SHOW_TRAY_NOTIFICATIONS) {
        TrayTip("Workspace state saved", "Cerberus", 1)
    }
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