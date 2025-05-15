# Cerberus Changes - Proportional Window Resizing

## Problem
When switching workspaces between monitors with different sizes/resolutions, windows were maintaining their absolute pixel positions instead of being proportionally resized for the new monitor.

## Solution
Modified the workspace switching logic to use relative positioning (percentages) instead of absolute pixel values.

## Changes Made

### 1. Modified `SwitchToWorkspace` function (lines ~874-1009)
- Added layout saving before workspace exchange
- Replaced offset-based movement with relative positioning
- Used `RelativeToAbsolutePosition` for proper scaling
- Added `SaveWindowLayout` calls after moving windows

### 2. Enhanced standard workspace switching (lines ~1076-1114)  
- Added relative positioning when moving windows between monitors
- Fallback to centering only when no layout data exists

### 3. Fixed `SendWindowToWorkspace` function (lines ~671-783)
- Added layout saving before moving windows
- Fixed layout retrieval to use previous workspace ID instead of current
- Enhanced fallback to use current window proportions when no saved layout exists
- Removed redundant layout saving for minimized windows

### 4. Key improvements:
- Windows now maintain their relative size (e.g., 50% width stays 50%)
- Windows maintain their relative position (e.g., top-left quarter stays top-left)
- Maximized windows remain maximized on new monitor
- Proper handling of workspace exchanges between monitors

## Technical Details

### Relative Position Conversion
- `AbsoluteToRelativePosition`: Converts pixel coordinates to percentages (0.0-1.0)
- `RelativeToAbsolutePosition`: Converts percentages back to pixels for target monitor
- `SaveWindowLayout`: Stores both absolute and relative positions
- `RestoreWindowLayout`: Uses relative positions when monitor changes

### Example
- Window at 960x540 pixels on 1920x1080 monitor = 50% width, 50% height
- Same window on 2560x1440 monitor = 1280x720 pixels (still 50% width, 50% height)

## Testing
See cerberus_test_instructions.md for detailed test scenarios.

## Future Enhancements
- Consider DPI scaling differences between monitors
- Handle edge cases for ultra-wide monitors
- Add user preference for absolute vs relative positioning