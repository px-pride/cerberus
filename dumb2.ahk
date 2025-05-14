#Requires AutoHotkey v2.0
#SingleInstance Force

OutputDebug("Test started")

; Register message handlers
OutputDebug("Registering message handlers")
OnMessage 0x0003, MoveHandler  ; WM_MOVE
OnMessage 0x0005, SizeHandler  ; WM_SIZE

; Message handlers
MoveHandler(wParam, lParam, msg, hwnd) {
    OutputDebug("WM_MOVE message received")
    return 0
}

SizeHandler(wParam, lParam, msg, hwnd) {
    OutputDebug("WM_SIZE message received")
    return 0
}

; Create timer for fallback
SetTimer MonitorActiveWindow, 500

MonitorActiveWindow() {
    static lastX := 0, lastY := 0, lastW := 0, lastH := 0

    try {
        hwnd := WinExist("A")  ; Get active window handle
        if hwnd {
            ; Correct WinGetPos syntax for AHK v2.0
            x := y := width := height := 0
            WinGetPos &x, &y, &width, &height, hwnd

            ; Check if position changed
            if (x != lastX || y != lastY) {
                OutputDebug("Timer: Window moved to " x "," y "")
                lastX := x
                lastY := y
            }

            ; Check if size changed
            if (width != lastW || height != lastH) {
                OutputDebug("Timer: Window resized to " width "x" height "")
                lastW := width
                lastH := height
            }
        }
    } catch as err {
        OutputDebug("Error: " err.Message "")
    }
}

; Create test window
testGui := Gui()
testGui.Title := "Test Window"
testGui.Add("Text",, "Move this window to test")
testGui.Show("w300 h200")

; Let user know
OutputDebug("Test running for 15 seconds. Move the window around.")

; Run for 15 seconds
Sleep 15000

; Done
OutputDebug("Test ended")
ExitApp
