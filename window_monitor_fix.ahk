; This is a function that can be added to fix window monitor detection issues
; Replace any GetWindowMonitorIndex function with this implementation

GetWindowMonitorIndex(windowHandle) {
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

; Similarly, if HandleNewWindow function exists, it should have proper error handling:

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

; And if WindowCreationCheck exists, it should also have proper error handling:

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