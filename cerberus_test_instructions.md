# Testing Proportional Window Resizing in Cerberus

## Test Scenarios

### Test 1: Different Monitor Sizes
1. Set up two monitors with different resolutions (e.g., 1920x1080 and 2560x1440)
2. Place a window on Monitor 1 (1920x1080) at 50% width and height
3. Switch workspaces using Ctrl+[Num] where the target workspace is on Monitor 2
4. **Expected**: Window should maintain 50% width and height on Monitor 2 (1280x720)

### Test 2: Exchange Workspaces Between Monitors
1. Set up Workspace 1 on Monitor 1 (1920x1080) with a window at top-left quarter
2. Set up Workspace 2 on Monitor 2 (2560x1440) with a window at bottom-right quarter
3. While on Monitor 1, press Ctrl+2 to switch to Workspace 2
4. **Expected**: 
   - Windows from Monitor 1 should move to Monitor 2 maintaining relative positions
   - Windows from Monitor 2 should move to Monitor 1 maintaining relative positions
   - Top-left quarter window should still be in top-left quarter on new monitor
   - Bottom-right quarter window should still be in bottom-right quarter on new monitor

### Test 3: Maximized Windows
1. Maximize a window on Monitor 1
2. Switch workspaces to one on Monitor 2  
3. **Expected**: Window should be maximized on Monitor 2

### Test 4: Send Window to Different Monitor (Same Resolution)
1. Open a window on Monitor 1 at top-left quarter (25% width, 25% height)
2. Use Ctrl+Shift+[Num] to send it to a workspace on Monitor 2 (same resolution)
3. **Expected**: Window should maintain top-left quarter position and size

### Test 4b: Send Window to Different Monitor (Different Resolution)
1. Open a window on Monitor 1 (1920x1080) at 50% width and height
2. Use Ctrl+Shift+[Num] to send it to a workspace on Monitor 2 (2560x1440)
3. **Expected**: Window should be 1280x720 on Monitor 2 (still 50% of monitor)

### Test 4c: Send Window to Hidden Workspace
1. Open a window on any monitor
2. Use Ctrl+Shift+[Num] to send it to a workspace that's not visible on any monitor
3. **Expected**: Window should minimize but remember its relative position
4. Switch to that workspace later
5. **Expected**: Window should restore with proper relative size/position

### Test 5: Multiple Windows
1. Open 3 windows on Monitor 1 at different positions
2. Switch to a workspace on Monitor 2
3. **Expected**: All windows should maintain their relative positions on Monitor 2

## Debug Mode
To enable detailed logging for troubleshooting:
1. Edit cerberus.ahk line 1905: `global DEBUG_MODE := True`
2. Run DebugView++ or similar to capture debug output
3. Check for "Using relative positioning" messages in the log

## Common Issues
- If windows don't maintain proportions, check that SaveWindowLayout is being called
- If windows jump to wrong positions, verify RelativeToAbsolutePosition calculations
- If maximized windows lose state, check isMaximized flag handling