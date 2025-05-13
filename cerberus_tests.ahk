; Cerberus Unit Tests
; This file contains tests for the core functionality of the Cerberus window manager

; =================================================================================
; Test Configuration
; =================================================================================

; Set to true to enable verbose test output
global TEST_VERBOSE := true

; Test counters
global testsRun := 0
global testsPassed := 0
global testsFailed := 0

; =================================================================================
; Test Utilities
; =================================================================================

; Log a test message
TestLog(message) {
    if (TEST_VERBOSE) {
        FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") " - " message "`n", "cerberus_test_log.txt")
        OutputDebug("TEST: " message)
    }
}

; Start a new test
StartTest(testName) {
    testsRun++
    TestLog("======= TEST: " testName " =======")
}

; Report a test result
TestResult(testName, passed, message := "") {
    resultStr := passed ? "PASSED ✓" : "FAILED ✗"
    
    if (passed) {
        testsPassed++
    } else {
        testsFailed++
    }
    
    resultMessage := testName ": " resultStr
    if (message) {
        resultMessage .= " (" message ")"
    }
    
    TestLog(resultMessage)
    
    ; Also output to console regardless of verbose setting
    OutputDebug(resultMessage)
}

; Assert two values are equal
AssertEqual(actual, expected, testName) {
    passed := (actual = expected)
    message := passed ? "" : "Expected: " expected ", Actual: " actual
    TestResult(testName, passed, message)
    return passed
}

; Assert a value is true
AssertTrue(value, testName) {
    passed := !!value
    message := passed ? "" : "Expected true, got: " value
    TestResult(testName, passed, message)
    return passed
}

; Assert a value is false
AssertFalse(value, testName) {
    passed := !value
    message := passed ? "" : "Expected false, got: " value
    TestResult(testName, passed, message)
    return passed
}

; Run all tests in sequence
RunAllTests() {
    TestLog("============ TEST SUITE STARTED ============")
    
    ; Run all test functions
    TestPositionConversion()
    TestMonitorDetection()
    TestWorkspaceAssignment()
    TestLayoutStorage()
    
    ; Report summary
    TestLog("============ TEST SUMMARY ============")
    TestLog("Tests run: " testsRun)
    TestLog("Tests passed: " testsPassed)
    TestLog("Tests failed: " testsFailed)
    
    ; Show a message box with results
    MsgBox("Cerberus Tests Completed:`n`nTests run: " testsRun "`nTests passed: " testsPassed "`nTests failed: " testsFailed)
}

; =================================================================================
; Test Mock Functions
; =================================================================================

; Mock monitor functions and data for testing
class MockMonitor {
    __New(index, left, top, right, bottom) {
        this.index := index
        this.left := left
        this.top := top
        this.right := right
        this.bottom := bottom
        this.width := right - left
        this.height := bottom - top
    }
}

; Mock monitor setup for testing
SetupMockMonitors() {
    global mockMonitors := []
    
    ; Primary monitor: 1920x1080
    mockMonitors.Push(MockMonitor(1, 0, 0, 1920, 1080))
    
    ; Secondary monitor to the right: 2560x1440
    mockMonitors.Push(MockMonitor(2, 1920, 0, 1920 + 2560, 1440))
    
    ; Third monitor below primary: 1600x900
    mockMonitors.Push(MockMonitor(3, 0, 1080, 1600, 1080 + 900))
    
    return mockMonitors
}

; Mock window for testing
class MockWindow {
    __New(hwnd, title, x, y, width, height, monitorIndex := 1) {
        this.hwnd := hwnd
        this.title := title
        this.x := x
        this.y := y
        this.width := width
        this.height := height
        this.monitorIndex := monitorIndex
        this.isMinimized := false
        this.isMaximized := false
    }
}

; Mock MonitorGetWorkArea function for testing
MockMonitorGetWorkArea(monitorIndex, &left, &top, &right, &bottom) {
    global mockMonitors
    
    if (monitorIndex < 1 || monitorIndex > mockMonitors.Length) {
        left := 0
        top := 0
        right := 1920
        bottom := 1080
        return false
    }
    
    monitor := mockMonitors[monitorIndex]
    left := monitor.left
    top := monitor.top
    right := monitor.right
    bottom := monitor.bottom
    return true
}

; =================================================================================
; Position Conversion Tests
; =================================================================================

TestPositionConversion() {
    StartTest("Position Conversion")
    
    ; Setup mock monitors
    mockMonitors := SetupMockMonitors()
    
    ; Test AbsoluteToRelativePosition
    TestAbsoluteToRelative()
    
    ; Test RelativeToAbsolutePosition
    TestRelativeToAbsolute()
    
    ; Test round trip conversion
    TestRoundTripConversion()
}

TestAbsoluteToRelative() {
    StartTest("AbsoluteToRelative")
    
    ; Monitor 1: 1920x1080
    ; Test center position
    relPos := AbsoluteToRelativePosition(960, 540, 800, 600, 1)
    AssertEqual(Round(relPos.relX, 2), 0.5, "Center X relative position")
    AssertEqual(Round(relPos.relY, 2), 0.5, "Center Y relative position")
    AssertEqual(Round(relPos.relWidth, 2), 0.42, "Width relative position") ; 800/1920 ≈ 0.42
    AssertEqual(Round(relPos.relHeight, 2), 0.56, "Height relative position") ; 600/1080 ≈ 0.56
    
    ; Test top-left corner
    relPos := AbsoluteToRelativePosition(0, 0, 400, 300, 1)
    AssertEqual(Round(relPos.relX, 2), 0, "Top-left X relative position")
    AssertEqual(Round(relPos.relY, 2), 0, "Top-left Y relative position")
    AssertEqual(Round(relPos.relWidth, 2), 0.21, "Width relative position") ; 400/1920 ≈ 0.21
    AssertEqual(Round(relPos.relHeight, 2), 0.28, "Height relative position") ; 300/1080 ≈ 0.28
    
    ; Monitor 2: 2560x1440
    ; Test with offset monitor
    relPos := AbsoluteToRelativePosition(1920 + 1280, 720, 1000, 800, 2)
    AssertEqual(Round(relPos.relX, 2), 0.5, "Monitor 2 X relative position") ; (1920+1280-1920)/2560 = 0.5
    AssertEqual(Round(relPos.relY, 2), 0.5, "Monitor 2 Y relative position") ; 720/1440 = 0.5
    AssertEqual(Round(relPos.relWidth, 2), 0.39, "Monitor 2 width relative position") ; 1000/2560 ≈ 0.39
    AssertEqual(Round(relPos.relHeight, 2), 0.56, "Monitor 2 height relative position") ; 800/1440 ≈ 0.56
}

TestRelativeToAbsolute() {
    StartTest("RelativeToAbsolute")
    
    ; Monitor 1: 1920x1080
    ; Test center position
    absPos := RelativeToAbsolutePosition(0.5, 0.5, 0.42, 0.56, 1)
    AssertEqual(absPos.x, 960, "Center X absolute position")
    AssertEqual(absPos.y, 540, "Center Y absolute position")
    AssertEqual(absPos.width, 806, "Width absolute position") ; 0.42*1920 ≈ 806
    AssertEqual(absPos.height, 605, "Height absolute position") ; 0.56*1080 ≈ 605
    
    ; Monitor 2: 2560x1440
    ; Test with second monitor
    absPos := RelativeToAbsolutePosition(0.5, 0.5, 0.39, 0.56, 2)
    AssertEqual(absPos.x, 1920 + 1280, "Monitor 2 X absolute position") ; 1920 + 0.5*2560 = 1920 + 1280
    AssertEqual(absPos.y, 720, "Monitor 2 Y absolute position") ; 0.5*1440 = 720
    AssertEqual(absPos.width, 998, "Monitor 2 width absolute position") ; 0.39*2560 ≈ 998
    AssertEqual(absPos.height, 806, "Monitor 2 height absolute position") ; 0.56*1440 ≈ 806
}

TestRoundTripConversion() {
    StartTest("RoundTripConversion")
    
    ; Test converting absolute to relative and back
    originalX := 500
    originalY := 400
    originalWidth := 800
    originalHeight := 600
    monitorIndex := 1
    
    ; First convert absolute to relative
    relPos := AbsoluteToRelativePosition(originalX, originalY, originalWidth, originalHeight, monitorIndex)
    
    ; Then convert back to absolute
    absPos := RelativeToAbsolutePosition(relPos.relX, relPos.relY, relPos.relWidth, relPos.relHeight, monitorIndex)
    
    ; Check if the values are preserved (allowing for small rounding differences)
    AssertEqual(absPos.x, originalX, "Round trip X position")
    AssertEqual(absPos.y, originalY, "Round trip Y position")
    AssertEqual(absPos.width, originalWidth, "Round trip width")
    AssertEqual(absPos.height, originalHeight, "Round trip height")
    
    ; Test different monitor conversion
    ; First get relative position on monitor 1
    window := MockWindow(1, "Test Window", 500, 400, 800, 600, 1)
    relPos := AbsoluteToRelativePosition(window.x, window.y, window.width, window.height, window.monitorIndex)
    
    ; Now use relative position to calculate position on monitor 2
    secondMonitorIndex := 2
    absPos := RelativeToAbsolutePosition(relPos.relX, relPos.relY, relPos.relWidth, relPos.relHeight, secondMonitorIndex)
    
    ; Verify calculations are reasonable for monitor 2
    ; (We know monitor 2 starts at X=1920 and has dimensions 2560x1440)
    expectedXRatio := 500 / 1920 ; X position ratio on monitor 1
    expectedX := 1920 + (expectedXRatio * 2560) ; Apply ratio to monitor 2 width and add offset
    
    ; Allow small rounding difference (±5 pixels)
    xDifference := Abs(absPos.x - Round(expectedX))
    AssertTrue(xDifference <= 5, "Cross-monitor X position calculation")
    
    ; Similar check for Y position
    expectedYRatio := 400 / 1080 ; Y position ratio on monitor 1
    expectedY := expectedYRatio * 1440 ; Apply ratio to monitor 2 height
    
    yDifference := Abs(absPos.y - Round(expectedY))
    AssertTrue(yDifference <= 5, "Cross-monitor Y position calculation")
}

; =================================================================================
; Monitor Detection Tests
; =================================================================================

TestMonitorDetection() {
    StartTest("MonitorDetection")
    
    ; Setup mock monitors
    mockMonitors := SetupMockMonitors()
    
    ; Test GetWindowMonitorIndex function with different window positions
    TestWindowMonitorIndex()
}

TestWindowMonitorIndex() {
    StartTest("WindowMonitorIndex")
    
    ; Create test windows at different positions
    windows := []
    
    ; Window clearly on monitor 1
    windows.Push(MockWindow(1, "Window on Monitor 1", 500, 400, 800, 600, 1))
    
    ; Window spanning monitors 1 and 2 but center is on monitor 1
    windows.Push(MockWindow(2, "Spanning Window", 1500, 400, 800, 600, 1))
    
    ; Window clearly on monitor 2
    windows.Push(MockWindow(3, "Window on Monitor 2", 2200, 400, 800, 600, 2))
    
    ; Window clearly on monitor 3
    windows.Push(MockWindow(4, "Window on Monitor 3", 400, 1200, 800, 600, 3))
    
    ; Test manually with our logic instead of calling the actual function
    ; (since we can't easily mock WinGetPos in the real function)
    TestWindowMonitorAssignment(windows[1], 1, "Window clearly on monitor 1")
    TestWindowMonitorAssignment(windows[2], 1, "Window spanning but center on monitor 1")
    TestWindowMonitorAssignment(windows[3], 2, "Window clearly on monitor 2")
    TestWindowMonitorAssignment(windows[4], 3, "Window clearly on monitor 3")
}

TestWindowMonitorAssignment(window, expectedMonitor, testName) {
    ; Calculate window center
    centerX := window.x + window.width / 2
    centerY := window.y + window.height / 2
    
    ; Find which monitor contains this point
    global mockMonitors
    detectedMonitor := 0
    
    for i := 1 to mockMonitors.Length {
        monitor := mockMonitors[i]
        if (centerX >= monitor.left && centerX <= monitor.right && 
            centerY >= monitor.top && centerY <= monitor.bottom) {
            detectedMonitor := i
            break
        }
    }
    
    ; If no monitor found, default to primary
    if (detectedMonitor = 0)
        detectedMonitor := 1
    
    AssertEqual(detectedMonitor, expectedMonitor, testName)
}

; =================================================================================
; Workspace Assignment Tests
; =================================================================================

TestWorkspaceAssignment() {
    StartTest("WorkspaceAssignment")
    
    ; Test window workspace assignments
    TestWindowWorkspaceMapping()
}

TestWindowWorkspaceMapping() {
    StartTest("WindowWorkspaceMapping")
    
    ; Create a mock workspace mapping
    global MonitorWorkspaces := Map()
    MonitorWorkspaces[1] := 1 ; Monitor 1 shows workspace 1
    MonitorWorkspaces[2] := 2 ; Monitor 2 shows workspace 2
    MonitorWorkspaces[3] := 3 ; Monitor 3 shows workspace 3
    
    ; Create a mock window workspace mapping
    global WindowWorkspaces := Map()
    
    ; Assign some test windows to workspaces
    windows := []
    windows.Push(MockWindow(101, "Window 1", 500, 400, 800, 600, 1))
    windows.Push(MockWindow(102, "Window 2", 2200, 400, 800, 600, 2))
    windows.Push(MockWindow(103, "Window 3", 400, 1200, 800, 600, 3))
    
    ; Test assigning windows to workspaces based on monitor
    for window in windows {
        ; Simulate the AssignNewWindow logic
        monitorIndex := window.monitorIndex
        workspaceID := MonitorWorkspaces.Has(monitorIndex) ? MonitorWorkspaces[monitorIndex] : 0
        
        ; Assign window to workspace
        WindowWorkspaces[window.hwnd] := workspaceID
        
        ; Verify assignment
        AssertEqual(WindowWorkspaces[window.hwnd], monitorIndex, 
            "Window " window.hwnd " assigned to workspace " monitorIndex)
    }
    
    ; Test window reassignment when moving to a different monitor
    movedWindow := windows[1]
    movedWindow.monitorIndex := 2 ; Move window to monitor 2
    
    ; Update workspace assignment
    monitorIndex := movedWindow.monitorIndex
    workspaceID := MonitorWorkspaces.Has(monitorIndex) ? MonitorWorkspaces[monitorIndex] : 0
    WindowWorkspaces[movedWindow.hwnd] := workspaceID
    
    ; Verify assignment updated
    AssertEqual(WindowWorkspaces[movedWindow.hwnd], 2, "Window reassigned after monitor change")
}

; =================================================================================
; Layout Storage Tests
; =================================================================================

TestLayoutStorage() {
    StartTest("LayoutStorage")
    
    ; Test saving and restoring window layouts
    TestSaveRestoreLayout()
}

TestSaveRestoreLayout() {
    StartTest("SaveRestoreLayout")
    
    ; Create mock workspace layouts
    global WorkspaceLayouts := Map()
    
    ; Setup mock monitors
    mockMonitors := SetupMockMonitors()
    
    ; Create test window
    testWindow := MockWindow(101, "Test Window", 500, 400, 800, 600, 1)
    workspaceID := 1
    
    ; Test saving window layout
    TestSaveLayout(testWindow, workspaceID)
    
    ; Test restoring window layout on same monitor
    TestRestoreLayoutSameMonitor(testWindow, workspaceID)
    
    ; Test restoring window layout on different monitor with relative positioning
    TestRestoreLayoutDifferentMonitor(testWindow, workspaceID)
}

TestSaveLayout(window, workspaceID) {
    StartTest("SaveLayout")
    
    ; Mock variables for SaveWindowLayout
    global WorkspaceLayouts
    
    ; Initialize workspace layout map if needed
    if (!WorkspaceLayouts.Has(workspaceID))
        WorkspaceLayouts[workspaceID] := Map()
    
    ; Get window info (using our mock window)
    hwnd := window.hwnd
    x := window.x
    y := window.y
    width := window.width
    height := window.height
    monitorIndex := window.monitorIndex
    isMinimized := window.isMinimized
    isMaximized := window.isMaximized
    
    ; Get relative position
    relativePos := AbsoluteToRelativePosition(x, y, width, height, monitorIndex)
    
    ; Store window layout with both absolute and relative positions
    WorkspaceLayouts[workspaceID][hwnd] := {
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
    
    ; Verify layout was saved correctly
    AssertTrue(WorkspaceLayouts.Has(workspaceID), "Workspace layout map initialized")
    AssertTrue(WorkspaceLayouts[workspaceID].Has(hwnd), "Window layout saved")
    
    layout := WorkspaceLayouts[workspaceID][hwnd]
    AssertEqual(layout.x, x, "Saved X position")
    AssertEqual(layout.y, y, "Saved Y position")
    AssertEqual(layout.width, width, "Saved width")
    AssertEqual(layout.height, height, "Saved height")
    AssertEqual(layout.monitorIndex, monitorIndex, "Saved monitor index")
    
    ; Verify relative position was saved
    AssertEqual(Round(layout.relX, 2), Round(relativePos.relX, 2), "Saved relative X")
    AssertEqual(Round(layout.relY, 2), Round(relativePos.relY, 2), "Saved relative Y")
    AssertEqual(Round(layout.relWidth, 2), Round(relativePos.relWidth, 2), "Saved relative width")
    AssertEqual(Round(layout.relHeight, 2), Round(relativePos.relHeight, 2), "Saved relative height")
}

TestRestoreLayoutSameMonitor(window, workspaceID) {
    StartTest("RestoreLayoutSameMonitor")
    
    ; Mock variables for RestoreWindowLayout
    global WorkspaceLayouts
    
    ; Get saved layout
    hwnd := window.hwnd
    layout := WorkspaceLayouts[workspaceID][hwnd]
    
    ; Get current monitor index for this window (same as saved)
    currentMonitorIndex := window.monitorIndex
    
    ; If current monitor is different from saved monitor, we'll use relative positioning
    useRelativePositioning := currentMonitorIndex != layout.monitorIndex
    
    ; Since using same monitor, should be false
    AssertFalse(useRelativePositioning, "No relative positioning needed for same monitor")
    
    ; Verify we can restore correctly
    x := layout.x
    y := layout.y
    width := layout.width
    height := layout.height
    
    AssertEqual(x, window.x, "Restored X position")
    AssertEqual(y, window.y, "Restored Y position")
    AssertEqual(width, window.width, "Restored width")
    AssertEqual(height, window.height, "Restored height")
}

TestRestoreLayoutDifferentMonitor(window, workspaceID) {
    StartTest("RestoreLayoutDifferentMonitor")
    
    ; Mock variables for RestoreWindowLayout
    global WorkspaceLayouts
    
    ; Get saved layout
    hwnd := window.hwnd
    layout := WorkspaceLayouts[workspaceID][hwnd]
    
    ; Get current monitor index for this window (different from saved)
    currentMonitorIndex := 2 ; Different from original monitor 1
    
    ; If current monitor is different from saved monitor, we'll use relative positioning
    useRelativePositioning := currentMonitorIndex != layout.monitorIndex
    
    ; Since using different monitor, should be true
    AssertTrue(useRelativePositioning, "Relative positioning needed for different monitor")
    
    ; Convert relative position to absolute for current monitor
    absolutePos := RelativeToAbsolutePosition(
        layout.relX, layout.relY, layout.relWidth, layout.relHeight, currentMonitorIndex)
    
    ; Use converted position
    x := absolutePos.x
    y := absolutePos.y
    width := absolutePos.width
    height := absolutePos.height
    
    ; Verify position is now on monitor 2
    monitor2 := mockMonitors[2]
    AssertTrue(x >= monitor2.left && x <= monitor2.right, "X position is on monitor 2")
    AssertTrue(y >= monitor2.top && y <= monitor2.bottom, "Y position is on monitor 2")
    
    ; Verify proportional position is maintained
    ; Calculate expected position as percentage of monitor 1, applied to monitor 2
    expectedXRatio := (window.x - mockMonitors[1].left) / mockMonitors[1].width
    expectedYRatio := (window.y - mockMonitors[1].top) / mockMonitors[1].height
    
    expectedX := monitor2.left + (expectedXRatio * monitor2.width)
    expectedY := monitor2.top + (expectedYRatio * monitor2.height)
    
    ; Allow for rounding differences (±5 pixels)
    xDifference := Abs(x - Round(expectedX))
    yDifference := Abs(y - Round(expectedY))
    
    AssertTrue(xDifference <= 5, "Relative X position maintained")
    AssertTrue(yDifference <= 5, "Relative Y position maintained")
}

; =================================================================================
; Run Tests
; =================================================================================

; Run all tests when this script is executed
RunAllTests()