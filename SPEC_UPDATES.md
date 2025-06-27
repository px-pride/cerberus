# Critical SPEC Updates Required for Cerberus

Based on the implementation session, the following updates are required for the SPEC.MD file:

## 1. JSON Parsing and Data Structure Clarifications

### Issue Encountered
LoadWorkspaceState was failing because Jxon_Load returns AutoHotkey v2 Map objects, not objects with properties.

### Required SPEC Updates
Add to Section 3 (Core Data Structures):
```
#### JSON Parsing
- The Jxon library returns Map objects when parsing JSON
- Access JSON data using Map syntax: data["key"] NOT data.key
- Use Has() method to check for keys, NOT HasOwnProp()
- Example:
  ```ahk
  stateData := Jxon_Load(jsonString)
  if (stateData.Has("windows")) {
      for windowData in stateData["windows"] {
          ; Process window data using Map access
          hwnd := windowData["hwnd"]
          workspace := windowData["workspace"]
      }
  }
  ```
```

## 2. Initialization Order and UpdateWindowMaps Behavior

### Issue Encountered
UpdateWindowMaps was being called after LoadWorkspaceState, overwriting loaded window assignments.

### Required SPEC Updates
Replace Section 3.3 (Initialization) with:
```
### 3. Initialization
- Initialize logging system (create logs directory, session-based log file)
- Show admin warning if not running as administrator
- Set up exit handler
- Detects all connected monitors
- Assigns default MonitorWorkspaces (Monitor 1 → Workspace 1, etc.)
- If saved workspace state file exists:
  - Load workspace state from JSON
  - DO NOT call UpdateWindowMaps() after loading
  - Restore window positions for visible workspaces
  - Maintain assignments for hidden workspaces
- Else (no saved state):
  - Assign all minimized windows to workspace 0 ("unassigned")
  - Run UpdateWindowMaps() to populate initial state
```

Update Section 2 (UpdateWindowMaps) to clarify:
```
### 2. UpdateWindowMaps()
- Frequently used core function
- IMPORTANT: Should NOT reassign windows that already have workspace assignments
- Only assigns windows to VISIBLE workspaces (those currently on monitors)
- Runs:
  - on a timer
  - near the start of utility hotkeys (after checking lock variables)
  - on exit
  - NOT during initialization if saved state exists
- Procedure:
  - for each monitor, get workspace on monitor from MonitorWorkspaces
  - for windows WITHOUT existing workspace assignments:
    - if window is on this monitor, assign to monitor's workspace
  - for windows WITH existing workspace assignments:
    - update layout information but preserve workspace assignment
  - save workspace state
```

## 3. Hidden Workspace Persistence

### Issue Encountered
Windows assigned to hidden workspaces (e.g., workspace 12) were losing their assignments.

### Required SPEC Updates
Add new section after "Window Positioning":
```
### 5.5. Hidden Workspace Management
- Hidden workspaces are workspaces 5-20 that are not currently visible on any monitor
- Windows assigned to hidden workspaces must maintain their assignments
- WindowWorkspaces Map must persist ALL window-workspace mappings (visible and hidden)
- Hidden workspace windows remain minimized until their workspace becomes visible
- When saving state, include ALL windows regardless of workspace visibility
- When loading state, restore assignments for ALL windows, not just visible ones
```

## 4. Window Restoration Error Handling

### Issue Encountered
User explicitly forbade fallback code when window restoration failed.

### Required SPEC Updates
Update Error Handling section:
```
## Error Handling

### Window Operation Failures
- Log all errors with descriptive messages
- NO FALLBACK CODE - let operations fail gracefully
- Do not attempt alternative approaches if primary method fails
- Failed window restoration should leave window in current state
- Continue processing other windows even if one fails
- Example:
  ```ahk
  try {
      WinRestore(hwnd)
      WinMove(x, y, width, height, hwnd)
  } catch as e {
      LogDebug("Error restoring window: " hwnd " - " e.Message)
      ; DO NOT add fallback code here
  }
  ```
```

## 5. State Persistence Format

### Issue Encountered
JSON structure wasn't clearly defined, leading to parsing confusion.

### Required SPEC Updates
Update Persistence section with exact format:
```
### 9. Persistence

#### JSON State Format
```json
{
  "version": "1.0.0",
  "timestamp": 20240626120000,
  "monitors": {
    "1": 1,
    "2": 2,
    "3": 3,
    "4": 4
  },
  "windows": [
    {
      "hwnd": 123456,
      "workspace": 12,
      "title": "Window Title",
      "class": "WindowClass",
      "process": "process.exe",
      "layout": {
        "xPercent": 0.1,
        "yPercent": 0.1,
        "widthPercent": 0.8,
        "heightPercent": 0.8,
        "state": 0,
        "monitor": 1
      }
    }
  ]
}
```

#### State Loading Rules
- Match windows by class + title + process (NOT by hwnd which changes)
- Load ALL windows including workspace 0 (unassigned)
- Preserve assignments for windows on hidden workspaces
- Log detailed information about loading process
```

## 6. Utility Function Behavior

### Issue Encountered
Confusion about when UpdateWindowMaps should be called by utility functions.

### Required SPEC Updates
Clarify in Keyboard Shortcuts section:
```
### Utility Functions
All utility functions follow this pattern:
1. Call UpdateWindowMaps() first (as stated in original spec)
2. Perform their specific function
3. Save state if they made changes

This ensures current window state is accurate before operations.
```

## Summary of Critical Changes

1. **JSON Parsing**: Must use Map syntax with Jxon_Load results
2. **Initialization**: Don't call UpdateWindowMaps after LoadWorkspaceState
3. **Hidden Workspaces**: Must persist window assignments for all 20 workspaces
4. **Error Handling**: NO FALLBACK CODE - fail gracefully with logging
5. **State Format**: Clearly defined JSON structure with loading rules
6. **UpdateWindowMaps**: Only assigns unassigned windows, preserves existing assignments

These updates address all the implementation issues encountered during the debugging session.