# Cerberus Development Journal

This document tracks the development progress of the Cerberus multi-monitor workspace management system.

## Development Milestones

### Initial Setup (Complete)

- Created repository with cerberus.ahk
- Added .gitignore configuration to exclude non-essential files
- Set up basic project documentation structure (DESIGN.md, DOC.md, PSEUDOCODE.md)

### Core System Implementation (Complete)

- Implemented workspace management data structures
- Created workspace initialization logic
- Developed window tracking and validation system
- Built workspace switching functionality
- Implemented visual overlay system

### Codebase Refinement

- Added extensive comments to all function calls for improved readability
- Created comprehensive documentation including:
  - Architecture overview (DESIGN.md)
  - User and developer documentation (DOC.md)
  - Pseudocode representation of the system (PSEUDOCODE.md)

## Development Decisions

### Data Structure Choices

- **Maps vs. Arrays**: Chose to use Map objects instead of arrays for workspace tracking to allow for faster lookups by window handle and monitor index.
- **GUI for Overlays**: Selected the GUI framework for workspace indicators due to its transparency support and easy text rendering.

### Window Validation Strategy

Implemented a multi-step window validation process that:
1. Filters out system windows based on class and title
2. Excludes child windows using window style detection
3. Bypasses the script's own windows

This approach balances inclusivity (capturing most application windows) with exclusivity (avoiding system components).

### Workspace Switching Logic

The workspace switching algorithm presented two major design challenges:

1. **Multi-monitor Complexity**: Needed to handle both single-monitor workspace switching and cross-monitor workspace exchanges.
2. **Window State Preservation**: Required reliable saving and restoring of window positions, sizes, and states.

Resolution involved splitting the switching logic into two distinct pathways:
- Standard switching for single-monitor operations
- Exchange mode for swapping workspaces between monitors

### Performance Considerations

Several optimizations were implemented:
- Delayed window assignment (1000ms) to ensure window properties are stable
- Small delays between window operations to prevent overwhelming the system
- Minimizing redundant window operations

## Technical Debt & Future Work

### Current Limitations

- System does not handle applications that override window states in unusual ways
- Some edge cases in cross-monitor window management remain untested
- Window focus could be improved during rapid workspace switches

### Planned Improvements

1. **Configuration File**: External configuration to allow user customization
2. **Enhanced Window Filtering**: More sophisticated window detection rules
3. **Per-Workspace Wallpapers**: Support for different desktop backgrounds
4. **Application Rules**: Ability to assign specific apps to certain workspaces
5. **Visual Improvements**: Transition animations and better overlay styling
6. **Performance Optimization**: Especially for high-DPI multi-monitor setups

## Development Learnings

- **AutoHotkey v2 API**: Leveraged new capabilities in AHK v2 for window management
- **Event-Driven Design**: Successfully implemented event handlers for window tracking
- **Multi-Monitor Challenges**: Gained insights into cross-monitor window coordination
- **GUI Development**: Developed lightweight, non-intrusive visual indicators

## Future Development Roadmap

### Short-term (1-2 months)
- Add external configuration file support
- Improve error handling and logging
- Add basic installer

### Medium-term (2-4 months)
- Implement application workspace rules
- Add per-workspace wallpaper support
- Create transition animations

### Long-term (4+ months)
- Add workspace naming/tagging
- Develop saved workspace configurations
- Create diagnostic/debugging tools