# Cerberus Workspace Management System - Design Document

## Overview

Cerberus is a multi-monitor workspace management system built with AutoHotkey v2.0. It provides a virtual workspace system similar to those found in Linux desktop environments but tailored for Windows. Users can create up to 9 distinct workspaces, each capable of containing different applications, and easily switch between them using keyboard shortcuts.

## Core Design Principles

1. **Simplicity**: Straightforward keyboard shortcuts (Ctrl+1 through Ctrl+9) to switch workspaces.
2. **Visual Feedback**: Unobtrusive on-screen indicators showing the current workspace number.
3. **Window State Preservation**: Maintaining window positions, sizes, and states between workspace switches.
4. **Multi-monitor Support**: Handling multiple displays with independent workspace assignments.
5. **Minimal Interference**: Working alongside Windows without disrupting native window management.

## System Architecture

Cerberus is organized around several key components:

### 1. Workspace Management System

The core functionality revolves around tracking windows and their assignments to virtual workspaces. This is achieved through several global data structures:

- `MonitorWorkspaces`: Maps physical monitor indices to workspace IDs
- `WindowWorkspaces`: Maps window handles to workspace IDs
- `WorkspaceLayouts`: Stores window positions and states for each workspace

### 2. Window Tracking System

Cerberus implements a system to track window creation, movement, and resizing:

- **Window Filtering**: The `IsWindowValid()` function determines which windows should be tracked, excluding system components like the taskbar.
- **Window Events**: Monitors window creation (WM_CREATE), movement (WM_MOVE), and resizing (WM_SIZE) events.
- **Layout Storage**: Saves window positions, sizes, and states (minimized/maximized) for restoration when switching workspaces.

### 3. Workspace Switching System

The switching mechanism handles the transition between workspaces:

- **Single-Monitor Switching**: Changes which workspace is displayed on the active monitor.
- **Cross-Monitor Exchange**: Allows workspaces to be swapped between monitors if a requested workspace is already visible on another display.
- **Window Visibility Control**: Minimizes windows from the previous workspace and restores windows belonging to the new workspace.

### 4. Visual Feedback System

Provides visual cues about the current workspace assignment:

- **Workspace Overlays**: Small, semi-transparent GUI elements displaying the current workspace number.
- **Configurability**: Adjustable size, position, opacity, and display timeout.
- **Toggle Control**: Can be hidden/shown with a keyboard shortcut (Ctrl+0).

## Data Flow

1. **Initialization**:
   - Detect monitors and assign initial workspaces
   - Enumerate existing windows and assign to workspaces
   - Create visual overlays

2. **Workspace Switching**:
   - User presses keyboard shortcut (e.g., Ctrl+3)
   - System determines active monitor
   - Windows on current workspace are minimized
   - Monitor's workspace assignment is updated
   - Windows belonging to the new workspace are restored
   - Visual overlay is updated

3. **New Window Creation**:
   - Window creation event is detected
   - After a short delay for initialization, window is assigned to its monitor's current workspace
   - If window belongs to a non-visible workspace, it's minimized

4. **Window Movement/Resizing**:
   - Movement/resize events are captured
   - Window layout information is updated in the workspace layout map
   - This ensures window state is preserved when switching workspaces

## Configuration Parameters

The system provides several configurable parameters:

- `MAX_WORKSPACES`: Maximum number of workspaces (default: 9)
- `MAX_MONITORS`: Maximum number of supported monitors (default: 9)
- `OVERLAY_SIZE`: Size of workspace indicators in pixels
- `OVERLAY_MARGIN`: Margin from screen edge for indicators
- `OVERLAY_TIMEOUT`: Time before indicators fade (0 for permanent display)
- `OVERLAY_OPACITY`: Transparency level of indicators
- `OVERLAY_POSITION`: Position on screen ("TopLeft", "TopRight", "BottomLeft", "BottomRight")

## Technical Limitations

1. **Window State Tracking**: Some applications with non-standard window behavior may not be tracked correctly.
2. **Cross-Workspace Relationships**: Parent-child window relationships that span workspaces may cause unexpected behavior.
3. **System Integration**: As the tool operates at the window manipulation level, it may have conflicts with other window management tools.
4. **Performance**: Heavy window switching across multiple high-resolution monitors may experience brief delays.

## Future Architectural Considerations

1. **Configuration File**: Move configuration parameters to an external file.
2. **Per-Workspace Wallpapers**: Add support for different desktop backgrounds per workspace.
3. **Application Rules**: Allow specific applications to always open in designated workspaces.
4. **Workspace Naming**: Add support for naming workspaces beyond numeric identifiers.
5. **Transition Effects**: Implement smooth visual transitions when switching workspaces.