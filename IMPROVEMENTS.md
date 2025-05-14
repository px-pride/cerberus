# Cerberus Workspace Manager - Improvement Plan

This document outlines potential enhancements and optimizations for the Cerberus Workspace Management System based on a comprehensive code review.

## High-Priority Improvements

### 1. Memory Management

- **Window Tracking Cleanup**: Implement a periodic cleanup mechanism for `lastWindowState` and `WindowWorkspaces` maps to remove references to closed windows.
- **Example Implementation**:
  ```ahk
  CleanupWindowReferences() {
      ; Loop through window references and remove invalid ones
      for hwnd, state in lastWindowState {
          if !WinExist(hwnd)
              lastWindowState.Delete(hwnd)
      }
      for hwnd, workspaceID in WindowWorkspaces {
          if !WinExist(hwnd)
              WindowWorkspaces.Delete(hwnd)
      }
  }
  
  ; Call this function periodically
  SetTimer(CleanupWindowReferences, 60000)  ; Every minute
  ```

### 2. Improved Window Validation

- **Enhanced `IsWindowValid()` Function**: Expand the window filtering logic to better handle modern applications and system windows.
- **Script Window Detection**: Use `A_ScriptHwnd` instead of `WinActive("A")` for more reliable script window detection.
- **Extended Window Style Checks**: Add extended style checking for more accurate window filtering.
- **Example Implementation**:
  ```ahk
  IsWindowValid(hwnd) {
      ; Skip invalid handles safely
      try {
          if !WinExist(hwnd)
              return false
      } catch {
          return false
      }
      
      ; Get window information (once)
      title := WinGetTitle(hwnd)
      class := WinGetClass(hwnd)
      
      ; Debug mode conditional output
      if DEBUG_MODE
          OutputDebug("Checking window - Title: " title ", Class: " class ", hwnd: " hwnd)
      
      ; Skip windows without a title or class (fast checks first)
      if (title = "" || class = "")
          return false
          
      ; Skip the script's own window reliably
      if (hwnd = A_ScriptHwnd)
          return false
      
      ; Extended class filtering
      static skipClasses := "Progman,Shell_TrayWnd,WorkerW,TaskListThumbnailWnd,ApplicationFrameWindow,Windows.UI.Core.CoreWindow"
      if (InStr(skipClasses, class))
          return false
      
      ; Skip system windows by title pattern
      if (RegExMatch(title, "i)^(Task View|Start Menu|Action Center|Cortana|Search|Notifications|Windows Shell Experience Host)$"))
          return false
      
      ; Check window styles
      WS_CHILD := 0x40000000
      WS_POPUP := 0x80000000
      WS_EX_TOOLWINDOW := 0x00000080
      WS_EX_APPWINDOW := 0x00040000
      
      style := WinGetStyle(hwnd)
      exStyle := WinGetExStyle(hwnd)
      
      ; Skip child windows
      if (style & WS_CHILD)
          return false
          
      ; Skip tool windows that don't appear in the taskbar
      if ((exStyle & WS_EX_TOOLWINDOW) && !(exStyle & WS_EX_APPWINDOW))
          return false
      
      ; Let most regular windows through
      return true
  }
  ```

### 3. Performance Optimization

- **Reduce Redundant API Calls**: Cache window properties where possible.
- **Batch Processing**: Process related windows in batches when switching workspaces.
- **Conditional Debug Output**: Add a DEBUG_MODE toggle for better performance in production.
- **Optimize Map Lookups**: Use Maps more efficiently and consider Array lookups for frequent operations.

## Medium-Priority Improvements

### 4. Enhanced Workspace Switching Logic

- **User Confirmation**: Add optional confirmations for workspace assignment changes.
- **Adaptive Sleep Timers**: Implement dynamic delays based on window count and system performance.
- **Transition Smoothing**: Add visual transitions during workspace switches.
- **Example Implementation**:
  ```ahk
  ; Add to SwitchToWorkspace()
  CalculateDelay(windowCount) {
      ; Base delay of 100ms
      baseDelay := 100
      ; Add 10ms per window, capped at 500ms
      return Min(baseDelay + (windowCount * 10), 500)
  }
  
  ; Then use in switching logic
  windowCount := windows.Length
  dynamicDelay := CalculateDelay(windowCount)
  Sleep(dynamicDelay)
  ```

### 5. Window Event Handling Improvements

- **Refined NewWindowHandler()**: Better handling of window initialization stages.
- **Window State Tracking**: More comprehensive tracking of window state changes.
- **Application-Specific Rules**: Special handling for known applications with unusual behavior.
- **Example Implementation**:
  ```ahk
  NewWindowHandler(wParam, lParam, msg, hwnd) {
      ; Skip early if window is invalid
      if (!IsWindowValid(hwnd))
          return
          
      ; Get window info
      title := WinGetTitle(hwnd)
      class := WinGetClass(hwnd)
      process := WinGetProcessName(hwnd)
      
      ; Application-specific handling
      if (process = "chrome.exe" || process = "msedge.exe") {
          ; Special handling for browser windows
          HandleBrowserWindow(hwnd, title, class)
          return
      }
      
      ; Standard handling (rest of current function)
      ; ...
  }
  ```

### 6. Error Handling and Recovery

- **Operation Verification**: Verify window operations succeed and retry if needed.
- **Error Logging**: Enhanced error reporting for debugging and stability monitoring.
- **Self-Healing**: Detect and attempt to fix inconsistent workspace states.

## Future Enhancements

### 7. User Experience Improvements

- **Transition Animations**: Smooth visual transitions between workspaces.
- **Enhanced Overlays**: More informative and visually appealing workspace indicators.
- **Notification System**: Unobtrusive notifications for workspace changes and errors.

### 8. Configuration and Customization

- **Settings GUI**: Create a simple settings interface for common parameters.
- **Per-Window Workspace Rules**: Allow setting specific windows to always open in certain workspaces.
- **Keyboard Shortcut Customization**: Allow users to redefine workspace switching keys.

### 9. System Integration

- **Session Management**: Preserve workspace assignments between computer restarts.
- **Third-Party Integration**: Allow interoperation with other window management tools.
- **Context Menu Extensions**: Add right-click options for workspace assignments.

## Implementation Strategy

1. Start with memory management and window validation improvements
2. Add performance optimizations next
3. Enhance the window event handling
4. Implement error handling and recovery
5. Add user experience improvements as resources allow

This approach prioritizes stability and performance before adding new features, ensuring the core functionality remains solid.