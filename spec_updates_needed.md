# Specification Updates Needed for Cerberus AHK

Based on the implementation session, the following clarifications and additions are needed in the specification:

## 1. Hidden Workspace Behavior

### Original Issue
- Hidden workspaces were not persisting properly across sessions
- Windows assigned to hidden workspaces would lose their assignments

### Spec Clarification Needed
- **Hidden workspaces must persist their window assignments** even when no windows are visible
- **Window-to-workspace mappings must be maintained** for all 10 workspaces (1-9 + 0) regardless of visibility
- **Hidden workspace state must be saved** in the JSON file even if empty

### Implementation Detail to Document
```
HiddenWorkspaces := Map()  ; Maps workspace number to Set of window IDs
WindowToWorkspace := Map()  ; Maps window ID to workspace number
```

## 2. State Persistence and Loading

### Original Issue
- LoadWorkspaceState was failing due to JSON parsing errors
- UpdateWindowMaps was being called after LoadWorkspaceState, overwriting loaded data

### Spec Clarification Needed
- **Order of operations on startup:**
  1. Initialize empty data structures
  2. Load saved state from JSON
  3. Update window maps based on current windows
  4. DO NOT overwrite loaded hidden workspace data
  
- **JSON structure must be clearly defined:**
  ```json
  {
    "WindowToWorkspace": {
      "0x12345": 1,
      "0x67890": 2
    },
    "HiddenWorkspaces": {
      "1": ["0x12345", "0x67890"],
      "2": ["0xABCDE"]
    }
  }
  ```

## 3. Window Position Restoration

### Original Issue
- Windows were being maximized during restoration
- Restored positions were sometimes incorrect

### Spec Clarification Needed
- **Window restoration must preserve exact state:**
  - Position (X, Y)
  - Size (Width, Height)
  - State (Normal, Minimized - NOT Maximized unless originally maximized)
- **Maximized windows should NOT be restored** unless they were originally maximized
- **Position validation needed** to ensure windows are restored within monitor bounds

## 4. Utility Functions and Data Structure Updates

### Original Issue
- UpdateWindowMaps was overwriting data
- Utility functions were modifying global state inappropriately

### Spec Clarification Needed
- **UpdateWindowMaps behavior:**
  - Should ADD new windows to existing mappings
  - Should NOT remove windows from HiddenWorkspaces
  - Should only update WindowToWorkspace for visible windows
  
- **Utility function contracts:**
  - AssignWindowToWorkspace: Updates BOTH maps
  - RemoveWindowFromWorkspace: Updates BOTH maps
  - Clear separation between "update" and "overwrite" operations

## 5. Current Workspace Management

### Original Issue
- Current workspace tracking was not clearly defined
- Switching behavior was ambiguous

### Spec Clarification Needed
- **CurrentWorkspace variable:**
  - Must always reflect the active workspace (1-9, 0)
  - Must be persisted in state
  - Must be restored on startup
  
- **Workspace switching behavior:**
  - Hide all windows from current workspace
  - Show all windows from target workspace
  - Update CurrentWorkspace variable
  - Save state after switch

## 6. Window Filtering

### Original Issue
- Some system windows were being tracked inappropriately
- Explorer windows needed special handling

### Spec Clarification Needed
- **Window inclusion criteria:**
  - Must have a title
  - Must be Alt-Tab eligible
  - Must not be cloaked
  - Explorer.exe windows: Only include if title != "Program Manager"
  
- **System window exclusion:**
  - Shell_TrayWnd
  - Shell_SecondaryTrayWnd
  - Program Manager

## 7. Error Handling and Recovery

### Original Issue
- JSON parsing errors were causing complete state loss
- No graceful degradation

### Spec Clarification Needed
- **Error recovery strategy:**
  - If JSON parse fails, log error and start with empty state
  - If window operations fail, log and continue
  - Never crash the entire script due to individual window errors
  
- **Logging requirements:**
  - All state changes should be logged
  - All errors should be logged with context
  - File operations should log success/failure

## 8. Tiling Function Integration

### Original Issue
- Tiling function was mentioned but not clearly integrated

### Spec Clarification Needed
- **Tiling behavior:**
  - Only affects windows in current workspace
  - Should work with filtered window list
  - Should respect monitor boundaries
  - Integration point with workspace system

## 9. Performance Considerations

### Not Addressed in Original Spec
- **State save frequency:**
  - After each workspace switch
  - After window assignment changes
  - On script exit
  - NOT on every window event
  
- **Window enumeration:**
  - Cache results where appropriate
  - Avoid redundant WinGet calls

## 10. Testing Requirements

### Not Addressed in Original Spec
- **Key test scenarios:**
  - Start with no saved state
  - Start with corrupted JSON
  - Window closed while in hidden workspace
  - Multiple windows from same application
  - Workspace switching rapid succession
  - Script restart with windows in various states

## Summary of Critical Changes

1. **Data Structure Clarity**: Explicitly define Map structures and their relationships
2. **Operation Order**: Clear startup sequence to prevent data loss
3. **State Persistence**: Exact JSON format and when to save
4. **Window Filtering**: Precise criteria for trackable windows
5. **Error Handling**: Graceful degradation strategy
6. **Hidden Workspace Persistence**: Must maintain assignments even when empty

These specifications should be incorporated into the main design document to prevent the implementation issues encountered during development.