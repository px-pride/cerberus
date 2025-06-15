# How I Built a Linux-Style Workspace Manager for Windows (And Why You Might Want One Too)

Ever find yourself Alt-Tabbing through dozens of windows trying to find that one specific browser tab? Or wishing you could keep documentation visible on one monitor while switching between different projects on another?

That's the problem I set out to solve with Cerberus, a workspace manager that brings Linux-style virtual desktop functionality to Windows with proper multi-monitor support.

## The Problem with Windows Virtual Desktops

Windows 10 introduced virtual desktops, which was a welcome addition. But there's one major limitation that makes them frustrating for multi-monitor setups: all monitors switch desktops together.

If you have two monitors and want to keep documentation on the right while cycling through different workspaces on the left, you're out of luck. Coming from Linux, where each monitor can display a different workspace independently, this felt like a significant step backward.

## A Different Approach

After spending too much time trying to extend Windows' built-in virtual desktop system, I realized I was overcomplicating things. Instead of creating actual virtual desktops, Cerberus takes a simpler approach: it manages window visibility.

When you press `Ctrl+2` to switch to workspace 2, Cerberus:
1. Hides all windows from the current workspace
2. Shows all windows assigned to workspace 2
3. Restores their saved positions and states

The key innovation is that each monitor maintains its own active workspace. Your primary monitor can show workspace 3 while your secondary shows workspace 7, exactly like a Linux desktop environment.

## Core Features

**Up to 19 Workspaces**: Originally 9, but expanded based on user feedback. It turns out people use workspaces for all sorts of organizational schemes - separating projects, communication tools, reference materials, and more.

**Smart Window Management**: New windows automatically join the active workspace. When you move a window between monitors, it maintains proper positioning even across different resolutions.

**Workspace Exchange**: If you try to switch to a workspace that's already visible on another monitor, Cerberus swaps them. This prevents the confusion of trying to access a workspace that's already displayed elsewhere.

**Visual Feedback**: Optional overlay indicators show which workspace each monitor is displaying, and the active monitor gets a subtle border highlight.

## Technical Implementation

Cerberus is built with AutoHotkey v2, which might seem like an unusual choice, but it's actually ideal for this use case. AHK provides deep Windows integration with minimal overhead - the entire workspace manager uses less memory than a typical web page.

The architecture is straightforward:
- Window handles (HWNDs) are tracked in hash maps for efficient lookups
- Windows message hooks catch window creation and destruction events
- Relative positioning handles different monitor resolutions
- Special window classes (tooltips, system dialogs) are filtered out

One interesting challenge was handling Windows' tooltip system. Tooltips are created as actual windows with handles, which initially caused them to be tracked as workspace windows. This led to memory bloat until I implemented proper window class filtering.

## Real-World Usage

After months of daily use, these are the patterns that have emerged:

- Dedicating workspaces to specific projects or contexts
- Using higher-numbered workspaces for reference materials and documentation
- Keeping communication tools isolated in their own workspace
- Setting up task-specific layouts that can be instantly recalled

The system is particularly effective for development workflows where you need to quickly context-switch between different projects while maintaining spatial memory of where everything is located.

## Why AutoHotkey?

Building this in AutoHotkey v2 has several advantages:
- No installation or dependencies required
- Easy to modify and customize
- Direct access to Windows APIs
- Negligible performance impact
- Quick iteration and debugging

The entire project is a single script file, making it simple to understand and modify for your specific needs.

## Try It Yourself

If you're frustrated with window management on Windows and want the flexibility of Linux-style workspaces, [Cerberus is available on GitHub](https://github.com/yourusername/cerberus_ahk). It's open source and designed to be hackable - take it and make it work for your workflow.

The main caveat is that it's a different paradigm from Windows' built-in virtual desktops. But if you're coming from Linux or just want better multi-monitor workspace management, it might be exactly what you're looking for.

---

*Note: There's currently a quirk where Spotify volume sometimes changes when switching workspaces. If anyone has insights into Windows audio session handling, I'd love to hear them.*