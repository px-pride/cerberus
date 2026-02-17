(function () {
"use strict";

// Forward declarations to satisfy V4 engine strict ordering
var Persistence;
var UI;

// State helper D-Bus service for persistence (writeConfig doesn't exist in KWin JS scripts)
var STATE_DBUS = {
    service: "com.cerberus.StateHelper",
    path: "/com/cerberus/StateHelper",
    iface: "com.cerberus.StateHelper"
};

// UI helper D-Bus service for overlays and dialogs
var UI_DBUS = {
    service: "com.cerberus.UI",
    path: "/com/cerberus/UI",
    iface: "com.cerberus.UI"
};

// ============================================================================
// CONFIG
// ============================================================================
var CONFIG = {
    MAX_WORKSPACES: 20,
    VERSION: "1.0.0",
    DEBUG: true,

    init: function () {
        var userDebug = (typeof readConfig !== 'undefined') ? readConfig("debug", "true") : "true";
        CONFIG.DEBUG = (userDebug === "true");
    }
};

// ============================================================================
// STATE
// ============================================================================
var State = {
    // {outputName: cerberusWsId} e.g. {"eDP-1": 1, "DP-1": 3}
    monitorWorkspaces: {},

    // {windowInternalId: cerberusWsId}
    windowWorkspaces: {},

    // {cerberusWsId: {windowId: {xPercent, yPercent, widthPercent, heightPercent, maximized}}}
    workspaceLayouts: {},

    // {windowId: zOrderIndex}
    windowZOrder: {},

    // {cerberusWsId: name}
    workspaceNames: {},

    // Reference to KDE Desktop 1 (the stage)
    stageDesktop: null,

    // Single KDE VirtualDesktop used to park all hidden windows
    parkingDesktop: null,

    // Lock to prevent reentrant switching
    switchInProgress: false,

    // Sorted list of output name strings
    outputOrder: []
};

// ============================================================================
// LOG
// ============================================================================
var Log = {
    debug: function (msg) {
        if (CONFIG.DEBUG) {
            print("[Cerberus] " + msg);
        }
    },

    info: function (msg) {
        print("[Cerberus] " + msg);
    },

    error: function (msg) {
        print("[Cerberus ERROR] " + msg);
    }
};

// ============================================================================
// PARKING MANAGER
// ============================================================================
var ParkingManager = {
    init: function () {
        var desktops = workspace.desktops;
        var needed = 2; // 1 stage + 1 parking

        Log.info("ParkingManager.init: found " + desktops.length + " desktops, need " + needed);

        // Create the parking desktop if only 1 exists
        if (desktops.length < needed) {
            try {
                workspace.createDesktop(desktops.length, "Cerberus Parking");
            } catch (e) {
                Log.error("ParkingManager.init: createDesktop failed: " + e);
            }
        }

        // Refresh desktops reference after creation
        desktops = workspace.desktops;
        Log.info("ParkingManager.init: now have " + desktops.length + " desktops");

        // Desktop 1 (index 0) = stage
        State.stageDesktop = desktops[0];
        Log.debug("ParkingManager.init: stage desktop = " + State.stageDesktop.id);

        // Desktop 2 (index 1) = single parking desktop for all hidden windows
        if (desktops.length >= 2) {
            State.parkingDesktop = desktops[1];
            Log.debug("ParkingManager.init: parking desktop = " + State.parkingDesktop.id);
        } else {
            Log.error("ParkingManager.init: could not create parking desktop!");
        }
    },

    parkWindow: function (win, wsId) {
        if (!State.parkingDesktop) {
            Log.error("parkWindow: no parking desktop available");
            return;
        }
        win.desktops = [State.parkingDesktop];
        Log.debug("parkWindow: parked '" + win.caption + "' to workspace " + wsId);
    },

    unparkWindow: function (win) {
        win.desktops = [State.stageDesktop];
        Log.debug("unparkWindow: unparked '" + win.caption + "' to stage");
    },

    isParked: function (win) {
        var desktops = win.desktops;
        if (!desktops || desktops.length === 0) {
            return false;
        }
        for (var i = 0; i < desktops.length; i++) {
            if (desktops[i] === State.stageDesktop) {
                return false;
            }
        }
        return true;
    }
};

// ============================================================================
// WINDOW UTILS
// ============================================================================
var WindowUtils = {
    isValid: function (win) {
        if (!win || !win.normalWindow) {
            return false;
        }
        if (win.desktopWindow || win.dock) {
            return false;
        }
        if (win.onAllDesktops) {
            return false;
        }
        // Skip windows with special resource classes
        var skipClasses = ["plasmashell", "krunner", "kded5", "kded6", "cerberus-ui"];
        var cls = (win.resourceClass || "").toLowerCase();
        var resName = (win.resourceName || "").toLowerCase();
        for (var i = 0; i < skipClasses.length; i++) {
            if (cls === skipClasses[i]) {
                return false;
            }
        }
        // Filter cerberus-ui windows by resourceName or caption
        if (resName === "cerberus-ui" || resName === "cerberus_ui") {
            return false;
        }
        var caption = (win.caption || "").toLowerCase();
        if (caption === "cerberus-ui" || caption.indexOf("cerberus \u2014") === 0) {
            return false;
        }
        return true;
    },

    getId: function (win) {
        return String(win.internalId);
    },

    findById: function (id) {
        var windows = workspace.windowList();
        for (var i = 0; i < windows.length; i++) {
            if (String(windows[i].internalId) === id) {
                return windows[i];
            }
        }
        return null;
    }
};

// ============================================================================
// OUTPUT UTILS
// ============================================================================
var OutputUtils = {
    getActiveOutput: function () {
        var cursor = workspace.cursorPos;
        var screens = workspace.screens;
        for (var i = 0; i < screens.length; i++) {
            var geo = screens[i].geometry;
            if (cursor.x >= geo.x && cursor.x < geo.x + geo.width &&
                cursor.y >= geo.y && cursor.y < geo.y + geo.height) {
                return screens[i];
            }
        }
        // Fallback: active window's screen
        return workspace.activeScreen;
    },

    getActiveOutputName: function () {
        var screen = OutputUtils.getActiveOutput();
        if (screen && screen.name) {
            return screen.name;
        }
        if (State.outputOrder.length > 0) {
            return State.outputOrder[0];
        }
        return "unknown";
    },

    getWorkArea: function (output) {
        return workspace.clientArea(KWin.MaximizeArea, output, State.stageDesktop);
    },

    getOutputByName: function (name) {
        var screens = workspace.screens;
        for (var i = 0; i < screens.length; i++) {
            if (screens[i].name === name) {
                return screens[i];
            }
        }
        return null;
    },

    getWindowOutputName: function (win) {
        if (win.output && win.output.name) {
            return win.output.name;
        }
        return "unknown";
    },

    buildOutputOrder: function () {
        var screens = workspace.screens;
        var names = [];
        for (var i = 0; i < screens.length; i++) {
            names.push(screens[i].name);
        }
        // Sort left-to-right by geometry
        names.sort(function (a, b) {
            var sa = OutputUtils.getOutputByName(a);
            var sb = OutputUtils.getOutputByName(b);
            if (!sa || !sb) return 0;
            var ga = sa.geometry;
            var gb = sb.geometry;
            if (ga.x !== gb.x) return ga.x - gb.x;
            return ga.y - gb.y;
        });
        State.outputOrder = names;
        Log.info("buildOutputOrder: " + JSON.stringify(names));
    }
};

// ============================================================================
// POSITION MATH
// ============================================================================
var PositionMath = {
    absoluteToRelative: function (x, y, w, h, output) {
        var area = OutputUtils.getWorkArea(output);
        var monW = area.width;
        var monH = area.height;
        return {
            xPercent: (x - area.x) / monW,
            yPercent: (y - area.y) / monH,
            widthPercent: w / monW,
            heightPercent: h / monH
        };
    },

    relativeToAbsolute: function (layout, output) {
        var area = OutputUtils.getWorkArea(output);
        var monW = area.width;
        var monH = area.height;
        return {
            x: Math.round(area.x + (layout.xPercent * monW)),
            y: Math.round(area.y + (layout.yPercent * monH)),
            width: Math.round(layout.widthPercent * monW),
            height: Math.round(layout.heightPercent * monH)
        };
    }
};

// ============================================================================
// WORKSPACE SWITCHER
// ============================================================================
var WorkspaceSwitcher = {
    _updateWindowMaps: function () {
        var windows = workspace.windowList();

        for (var i = 0; i < windows.length; i++) {
            var win = windows[i];
            if (!WindowUtils.isValid(win)) continue;

            var id = WindowUtils.getId(win);

            // Skip parked windows — they're already assigned
            if (ParkingManager.isParked(win)) continue;

            // Window is on the stage — assign to its monitor's workspace
            var outputName = OutputUtils.getWindowOutputName(win);
            var wsId = State.monitorWorkspaces[outputName];
            if (!wsId) continue;

            var oldWs = State.windowWorkspaces[id];
            if (oldWs && oldWs !== wsId) {
                // Window moved to different monitor — remove from old layout
                if (State.workspaceLayouts[oldWs]) {
                    delete State.workspaceLayouts[oldWs][id];
                }
            }

            State.windowWorkspaces[id] = wsId;

            // Save layout
            if (!State.workspaceLayouts[wsId]) {
                State.workspaceLayouts[wsId] = {};
            }

            var output = OutputUtils.getOutputByName(outputName);
            if (output) {
                var geo = win.frameGeometry;
                var rel = PositionMath.absoluteToRelative(geo.x, geo.y, geo.width, geo.height, output);
                State.workspaceLayouts[wsId][id] = {
                    xPercent: rel.xPercent,
                    yPercent: rel.yPercent,
                    widthPercent: rel.widthPercent,
                    heightPercent: rel.heightPercent,
                    maximized: (win.fullScreen || (geo.width >= output.geometry.width && geo.height >= output.geometry.height))
                };
            }
        }

        // Save Z-order for stage windows
        var stacking = workspace.stackingOrder;
        for (var z = 0; z < stacking.length; z++) {
            var sw = stacking[z];
            if (WindowUtils.isValid(sw) && !ParkingManager.isParked(sw)) {
                State.windowZOrder[WindowUtils.getId(sw)] = z;
            }
        }
    },

    switchWorkspace: function (targetWsId) {
        if (State.switchInProgress) {
            Log.debug("switchWorkspace: already in progress, skipping");
            return;
        }
        if (targetWsId < 1 || targetWsId > CONFIG.MAX_WORKSPACES) {
            Log.debug("switchWorkspace: invalid workspace " + targetWsId);
            return;
        }

        State.switchInProgress = true;

        try {
            WorkspaceSwitcher._updateWindowMaps();

            var activeOutputName = OutputUtils.getActiveOutputName();
            var currentWsId = State.monitorWorkspaces[activeOutputName];

            if (currentWsId === targetWsId) {
                Log.debug("switchWorkspace: already on workspace " + targetWsId);
                return;
            }

            // Is the target workspace visible on another monitor?
            var targetOutputName = null;
            for (var outName in State.monitorWorkspaces) {
                if (State.monitorWorkspaces[outName] === targetWsId) {
                    targetOutputName = outName;
                    break;
                }
            }

            // Ensure activeScreen matches cursor
            var activeOutput = OutputUtils.getActiveOutput();
            var allWins = workspace.windowList();
            for (var wi = allWins.length - 1; wi >= 0; wi--) {
                if (WindowUtils.isValid(allWins[wi]) && !ParkingManager.isParked(allWins[wi]) && allWins[wi].output === activeOutput) {
                    workspace.activeWindow = allWins[wi];
                    break;
                }
            }

            if (targetOutputName === null) {
                // Target is hidden — do park/unpark switch
                WorkspaceSwitcher._switchToHiddenWorkspace(activeOutputName, currentWsId, targetWsId);
            } else {
                // Target is visible on another monitor — swap
                WorkspaceSwitcher._swapWorkspaces(activeOutputName, currentWsId, targetOutputName, targetWsId);
            }

            Persistence.scheduleSave();
            UI.updateIndicators();
            Log.info("switchWorkspace: " + activeOutputName + " now on workspace " + targetWsId);

        } finally {
            State.switchInProgress = false;
        }
    },

    _switchToHiddenWorkspace: function (activeOutputName, currentWsId, targetWsId) {
        var activeOutput = OutputUtils.getOutputByName(activeOutputName);
        Log.debug("_switchToHidden: " + activeOutputName + " ws " + currentWsId + " -> " + targetWsId);

        // 1. Park current windows on this monitor
        if (currentWsId) {
            var windows = workspace.windowList();
            for (var i = 0; i < windows.length; i++) {
                var win = windows[i];
                if (!WindowUtils.isValid(win)) continue;
                if (ParkingManager.isParked(win)) continue;

                var id = WindowUtils.getId(win);
                if (State.windowWorkspaces[id] === currentWsId) {
                    // Save layout before parking
                    if (activeOutput) {
                        var geo = win.frameGeometry;
                        var rel = PositionMath.absoluteToRelative(geo.x, geo.y, geo.width, geo.height, activeOutput);
                        if (!State.workspaceLayouts[currentWsId]) {
                            State.workspaceLayouts[currentWsId] = {};
                        }
                        State.workspaceLayouts[currentWsId][id] = {
                            xPercent: rel.xPercent,
                            yPercent: rel.yPercent,
                            widthPercent: rel.widthPercent,
                            heightPercent: rel.heightPercent,
                            maximized: (win.fullScreen || (win.width >= activeOutput.geometry.width))
                        };
                    }
                    ParkingManager.parkWindow(win, currentWsId);
                }
            }
        }

        // 2. Update monitor assignment
        State.monitorWorkspaces[activeOutputName] = targetWsId;

        // 3. Unpark target workspace windows, restoring geometry
        var windowsToRestore = [];
        var allWindows = workspace.windowList();
        for (var j = 0; j < allWindows.length; j++) {
            var tw = allWindows[j];
            if (!WindowUtils.isValid(tw)) continue;

            var tid = WindowUtils.getId(tw);
            if (State.windowWorkspaces[tid] === targetWsId && ParkingManager.isParked(tw)) {
                var zOrder = State.windowZOrder[tid] || 999999;
                windowsToRestore.push({ win: tw, id: tid, zOrder: zOrder });
            }
        }

        // Sort by z-order (lower = bottom of stack)
        windowsToRestore.sort(function (a, b) { return a.zOrder - b.zOrder; });

        // Restore bottom-to-top
        for (var k = 0; k < windowsToRestore.length; k++) {
            var item = windowsToRestore[k];
            ParkingManager.unparkWindow(item.win);

            var layout = (State.workspaceLayouts[targetWsId] || {})[item.id];
            if (layout && activeOutput) {
                var abs = PositionMath.relativeToAbsolute(layout, activeOutput);
                if (layout.maximized) {
                    item.win.setMaximize(false, false);
                    item.win.frameGeometry = {
                        x: abs.x, y: abs.y, width: abs.width, height: abs.height
                    };
                    item.win.setMaximize(true, true);
                } else {
                    item.win.setMaximize(false, false);
                    item.win.frameGeometry = {
                        x: abs.x, y: abs.y, width: abs.width, height: abs.height
                    };
                }
            }

            // Raise to restore z-order
            workspace.raiseWindow(item.win);
        }

        // Activate top window
        if (windowsToRestore.length > 0) {
            workspace.activeWindow = windowsToRestore[windowsToRestore.length - 1].win;
        }
    },

    _swapWorkspaces: function (activeOutputName, currentWsId, targetOutputName, targetWsId) {
        var activeOutput = OutputUtils.getOutputByName(activeOutputName);
        var targetOutput = OutputUtils.getOutputByName(targetOutputName);
        Log.debug("_swapWorkspaces: " + activeOutputName + "(ws" + currentWsId + ") <-> " + targetOutputName + "(ws" + targetWsId + ")");

        if (!activeOutput || !targetOutput) {
            Log.error("_swapWorkspaces: could not find outputs");
            return;
        }

        // Save fresh layouts for both workspaces
        WorkspaceSwitcher._updateWindowMaps();

        // Collect windows for each workspace
        var currentWindows = []; // on activeOutput, belong to currentWsId
        var targetWindows = [];  // on targetOutput, belong to targetWsId
        var allWindows = workspace.windowList();

        for (var i = 0; i < allWindows.length; i++) {
            var win = allWindows[i];
            if (!WindowUtils.isValid(win)) continue;
            if (ParkingManager.isParked(win)) continue;

            var id = WindowUtils.getId(win);
            var ws = State.windowWorkspaces[id];
            if (ws === currentWsId) {
                currentWindows.push(win);
            } else if (ws === targetWsId) {
                targetWindows.push(win);
            }
        }

        // Swap monitor assignments
        State.monitorWorkspaces[activeOutputName] = targetWsId;
        State.monitorWorkspaces[targetOutputName] = currentWsId;

        // Move current workspace windows to target monitor
        for (var c = 0; c < currentWindows.length; c++) {
            var cw = currentWindows[c];
            var cid = WindowUtils.getId(cw);
            var cLayout = (State.workspaceLayouts[currentWsId] || {})[cid];
            if (cLayout) {
                var cAbs = PositionMath.relativeToAbsolute(cLayout, targetOutput);
                if (cLayout.maximized) {
                    cw.setMaximize(false, false);
                    cw.frameGeometry = { x: cAbs.x, y: cAbs.y, width: cAbs.width, height: cAbs.height };
                    cw.setMaximize(true, true);
                } else {
                    cw.frameGeometry = { x: cAbs.x, y: cAbs.y, width: cAbs.width, height: cAbs.height };
                }
            }
            workspace.sendClientToScreen(cw, targetOutput);
        }

        // Move target workspace windows to active monitor
        for (var t = 0; t < targetWindows.length; t++) {
            var tw = targetWindows[t];
            var tid = WindowUtils.getId(tw);
            var tLayout = (State.workspaceLayouts[targetWsId] || {})[tid];
            if (tLayout) {
                var tAbs = PositionMath.relativeToAbsolute(tLayout, activeOutput);
                if (tLayout.maximized) {
                    tw.setMaximize(false, false);
                    tw.frameGeometry = { x: tAbs.x, y: tAbs.y, width: tAbs.width, height: tAbs.height };
                    tw.setMaximize(true, true);
                } else {
                    tw.frameGeometry = { x: tAbs.x, y: tAbs.y, width: tAbs.width, height: tAbs.height };
                }
            }
            workspace.sendClientToScreen(tw, activeOutput);
        }

        // Activate top window of target workspace on active monitor
        if (targetWindows.length > 0) {
            workspace.activeWindow = targetWindows[targetWindows.length - 1];
        }
    }
};

// ============================================================================
// WINDOW SENDER
// ============================================================================
var WindowSender = {
    sendToWorkspace: function (targetWsId) {
        if (State.switchInProgress) return;
        if (targetWsId < 1 || targetWsId > CONFIG.MAX_WORKSPACES) return;

        State.switchInProgress = true;
        try {
            WorkspaceSwitcher._updateWindowMaps();

            var win = workspace.activeWindow;
            if (!win || !WindowUtils.isValid(win)) {
                Log.debug("sendToWorkspace: no valid active window");
                return;
            }

            var id = WindowUtils.getId(win);
            var currentWsId = State.windowWorkspaces[id];
            if (currentWsId === targetWsId) {
                Log.debug("sendToWorkspace: window already on workspace " + targetWsId);
                return;
            }

            var sourceOutputName = OutputUtils.getWindowOutputName(win);
            var sourceOutput = OutputUtils.getOutputByName(sourceOutputName);

            // Save layout from current position
            if (sourceOutput) {
                var geo = win.frameGeometry;
                var rel = PositionMath.absoluteToRelative(geo.x, geo.y, geo.width, geo.height, sourceOutput);
                if (!State.workspaceLayouts[targetWsId]) {
                    State.workspaceLayouts[targetWsId] = {};
                }
                State.workspaceLayouts[targetWsId][id] = {
                    xPercent: rel.xPercent,
                    yPercent: rel.yPercent,
                    widthPercent: rel.widthPercent,
                    heightPercent: rel.heightPercent,
                    maximized: (win.fullScreen || (geo.width >= sourceOutput.geometry.width))
                };
            }

            // Remove from old workspace layout
            if (currentWsId && State.workspaceLayouts[currentWsId]) {
                delete State.workspaceLayouts[currentWsId][id];
            }

            // Check if last window leaving source workspace
            if (currentWsId) {
                var remaining = 0;
                for (var wid in State.windowWorkspaces) {
                    if (State.windowWorkspaces[wid] === currentWsId && wid !== id) {
                        remaining++;
                    }
                }
                if (remaining === 0 && State.workspaceNames[currentWsId]) {
                    delete State.workspaceNames[currentWsId];
                    Log.debug("sendToWorkspace: cleared name from empty workspace " + currentWsId);
                }
            }

            // Is target workspace visible on a monitor?
            var targetOutputName = null;
            for (var outName in State.monitorWorkspaces) {
                if (State.monitorWorkspaces[outName] === targetWsId) {
                    targetOutputName = outName;
                    break;
                }
            }

            State.windowWorkspaces[id] = targetWsId;

            if (targetOutputName !== null) {
                // Target visible — move window to that monitor
                var targetOutput = OutputUtils.getOutputByName(targetOutputName);
                if (targetOutput) {
                    var layout = State.workspaceLayouts[targetWsId][id];
                    var abs = PositionMath.relativeToAbsolute(layout, targetOutput);
                    if (layout.maximized) {
                        win.setMaximize(false, false);
                        win.frameGeometry = { x: abs.x, y: abs.y, width: abs.width, height: abs.height };
                        win.setMaximize(true, true);
                    } else {
                        win.frameGeometry = { x: abs.x, y: abs.y, width: abs.width, height: abs.height };
                    }
                    workspace.sendClientToScreen(win, targetOutput);
                }
            } else {
                // Target hidden — park the window
                ParkingManager.parkWindow(win, targetWsId);

                // Auto-name workspace after the process
                if (!State.workspaceNames[targetWsId]) {
                    var name = win.resourceClass || win.resourceName || "";
                    if (name) {
                        name = name.charAt(0).toUpperCase() + name.slice(1);
                        State.workspaceNames[targetWsId] = name;
                        Log.debug("sendToWorkspace: named workspace " + targetWsId + " as '" + name + "'");
                    }
                }
            }

            Log.info("sendToWorkspace: sent '" + win.caption + "' to workspace " + targetWsId);
            Persistence.scheduleSave();
            UI.updateIndicators();

        } finally {
            State.switchInProgress = false;
        }
    }
};

// ============================================================================
// NAVIGATION
// ============================================================================
var Navigation = {
    getEmptyWorkspaces: function () {
        var windowCounts = {};
        for (var wid in State.windowWorkspaces) {
            var ws = State.windowWorkspaces[wid];
            if (ws > 0) {
                windowCounts[ws] = (windowCounts[ws] || 0) + 1;
            }
        }
        var empty = [];
        for (var i = 1; i <= CONFIG.MAX_WORKSPACES; i++) {
            if (!windowCounts[i]) {
                empty.push(i);
            }
        }
        return empty;
    },

    switchToNextEmptyWorkspace: function () {
        WorkspaceSwitcher._updateWindowMaps();
        var activeOutputName = OutputUtils.getActiveOutputName();
        var currentWsId = State.monitorWorkspaces[activeOutputName] || 0;
        var empty = Navigation.getEmptyWorkspaces();

        if (empty.length === 0) {
            Log.debug("switchToNextEmpty: no empty workspaces");
            return;
        }

        var next = 0;
        for (var i = 0; i < empty.length; i++) {
            if (empty[i] > currentWsId) {
                next = empty[i];
                break;
            }
        }
        if (next === 0) next = empty[0]; // wrap

        WorkspaceSwitcher.switchWorkspace(next);
    },

    switchToPreviousEmptyWorkspace: function () {
        WorkspaceSwitcher._updateWindowMaps();
        var activeOutputName = OutputUtils.getActiveOutputName();
        var currentWsId = State.monitorWorkspaces[activeOutputName] || 0;
        var empty = Navigation.getEmptyWorkspaces();

        if (empty.length === 0) {
            Log.debug("switchToPrevEmpty: no empty workspaces");
            return;
        }

        var prev = 0;
        for (var i = empty.length - 1; i >= 0; i--) {
            if (empty[i] < currentWsId) {
                prev = empty[i];
                break;
            }
        }
        if (prev === 0) prev = empty[empty.length - 1]; // wrap

        WorkspaceSwitcher.switchWorkspace(prev);
    },

    sendToNextEmptyWorkspace: function () {
        WorkspaceSwitcher._updateWindowMaps();

        var win = workspace.activeWindow;
        if (!win || !WindowUtils.isValid(win)) return;

        var id = WindowUtils.getId(win);
        var currentWsId = State.windowWorkspaces[id] || 0;
        var empty = Navigation.getEmptyWorkspaces();

        if (empty.length === 0) {
            Log.debug("sendToNextEmpty: no empty workspaces");
            return;
        }

        var next = 0;
        for (var i = 0; i < empty.length; i++) {
            if (empty[i] > currentWsId) {
                next = empty[i];
                break;
            }
        }
        if (next === 0) next = empty[0];

        WindowSender.sendToWorkspace(next);
    },

    sendToPreviousEmptyWorkspace: function () {
        WorkspaceSwitcher._updateWindowMaps();

        var win = workspace.activeWindow;
        if (!win || !WindowUtils.isValid(win)) return;

        var id = WindowUtils.getId(win);
        var currentWsId = State.windowWorkspaces[id] || 0;
        var empty = Navigation.getEmptyWorkspaces();

        if (empty.length === 0) {
            Log.debug("sendToPrevEmpty: no empty workspaces");
            return;
        }

        var prev = 0;
        for (var i = empty.length - 1; i >= 0; i--) {
            if (empty[i] < currentWsId) {
                prev = empty[i];
                break;
            }
        }
        if (prev === 0) prev = empty[empty.length - 1];

        WindowSender.sendToWorkspace(prev);
    }
};

// ============================================================================
// TILING
// ============================================================================
var Tiling = {
    tileWindows: function () {
        WorkspaceSwitcher._updateWindowMaps();

        var activeOutputName = OutputUtils.getActiveOutputName();
        var activeOutput = OutputUtils.getOutputByName(activeOutputName);
        var wsId = State.monitorWorkspaces[activeOutputName];
        if (!wsId || !activeOutput) {
            Log.debug("tileWindows: no workspace on active output");
            return;
        }

        // Collect non-parked windows on this workspace
        var wins = [];
        var allWindows = workspace.windowList();
        for (var i = 0; i < allWindows.length; i++) {
            var win = allWindows[i];
            if (!WindowUtils.isValid(win)) continue;
            if (ParkingManager.isParked(win)) continue;
            var id = WindowUtils.getId(win);
            if (State.windowWorkspaces[id] === wsId) {
                wins.push(win);
            }
        }

        var count = wins.length;
        if (count === 0) {
            Log.debug("tileWindows: no windows to tile");
            return;
        }

        var area = OutputUtils.getWorkArea(activeOutput);
        var cols = Math.ceil(Math.sqrt(count));
        var rows = Math.ceil(count / cols);
        var tileW = Math.floor(area.width / cols);
        var tileH = Math.floor(area.height / rows);

        for (var idx = 0; idx < count; idx++) {
            var col = idx % cols;
            var row = Math.floor(idx / cols);
            var x = area.x + (col * tileW);
            var y = area.y + (row * tileH);
            var w = (col === cols - 1) ? (area.width - col * tileW) : tileW;
            var h = (row === rows - 1) ? (area.height - row * tileH) : tileH;

            wins[idx].setMaximize(false, false);
            wins[idx].frameGeometry = { x: x, y: y, width: w, height: h };

            // Update layout
            var wid = WindowUtils.getId(wins[idx]);
            if (!State.workspaceLayouts[wsId]) State.workspaceLayouts[wsId] = {};
            var rel = PositionMath.absoluteToRelative(x, y, w, h, activeOutput);
            State.workspaceLayouts[wsId][wid] = {
                xPercent: rel.xPercent,
                yPercent: rel.yPercent,
                widthPercent: rel.widthPercent,
                heightPercent: rel.heightPercent,
                maximized: false
            };
        }

        Log.info("tileWindows: tiled " + count + " windows in " + cols + "x" + rows + " grid");
        Persistence.scheduleSave();
    }
};

// ============================================================================
// UI — Overlay and dialog integration via cerberus-ui D-Bus service
// ============================================================================
UI = {
    _lastBorderOutput: "",
    _borderTimer: null,

    updateIndicators: function () {
        var monitors = {};
        var screens = workspace.screens;
        for (var i = 0; i < screens.length; i++) {
            var scr = screens[i];
            var name = scr.name;
            var area = OutputUtils.getWorkArea(scr);
            var wsId = State.monitorWorkspaces[name] || 0;
            var wsName = State.workspaceNames[wsId] || "";
            monitors[name] = {
                wsId: wsId,
                wsName: wsName,
                x: area.x,
                y: area.y,
                w: area.width,
                h: area.height
            };
        }
        var json = JSON.stringify({ monitors: monitors });
        try {
            callDBus(UI_DBUS.service, UI_DBUS.path, UI_DBUS.iface, "UpdateIndicators", json);
        } catch (e) {
            Log.debug("UI.updateIndicators: " + e);
        }
    },

    updateBorder: function (outputName) {
        try {
            callDBus(UI_DBUS.service, UI_DBUS.path, UI_DBUS.iface, "UpdateBorder", outputName);
        } catch (e) {
            Log.debug("UI.updateBorder: " + e);
        }
    },

    toggleOverlays: function () {
        try {
            callDBus(UI_DBUS.service, UI_DBUS.path, UI_DBUS.iface, "ToggleOverlays");
        } catch (e) {
            Log.debug("UI.toggleOverlays: " + e);
        }
    },

    showNameDialog: function () {
        var activeOutputName = OutputUtils.getActiveOutputName();
        var wsId = State.monitorWorkspaces[activeOutputName];
        if (!wsId) {
            Log.debug("showNameDialog: no workspace on active output");
            return;
        }
        var currentName = State.workspaceNames[wsId] || "";

        try {
            callDBus(UI_DBUS.service, UI_DBUS.path, UI_DBUS.iface,
                "ShowNameDialog", wsId, currentName,
                function (result) {
                    try {
                        var data = JSON.parse(result);
                        if (data.ok) {
                            if (data.name) {
                                State.workspaceNames[wsId] = data.name;
                            } else {
                                delete State.workspaceNames[wsId];
                            }
                            UI.updateIndicators();
                            Persistence.scheduleSave();
                            Log.info("nameDialog: workspace " + wsId + " named '" + (data.name || "") + "'");
                        }
                    } catch (e) {
                        Log.error("showNameDialog callback: " + e);
                    }
                }
            );
        } catch (e) {
            Log.debug("UI.showNameDialog: " + e);
        }
    },

    showMap: function () {
        WorkspaceSwitcher._updateWindowMaps();

        var monitors = {};
        var screens = workspace.screens;
        for (var i = 0; i < screens.length; i++) {
            var name = screens[i].name;
            var wsId = State.monitorWorkspaces[name] || 0;
            monitors[name] = {
                wsId: wsId,
                wsName: State.workspaceNames[wsId] || ""
            };
        }

        // Build workspace contents
        var workspaces_data = {};
        // Collect windows per workspace
        var windowsByWs = {};
        var allWindows = workspace.windowList();
        for (var w = 0; w < allWindows.length; w++) {
            var win = allWindows[w];
            if (!WindowUtils.isValid(win)) continue;
            var wid = WindowUtils.getId(win);
            var ws = State.windowWorkspaces[wid];
            if (!ws) continue;
            if (!windowsByWs[ws]) windowsByWs[ws] = [];
            windowsByWs[ws].push({ title: win.caption || "Unknown" });
        }

        for (var wsKey in windowsByWs) {
            var wsIdNum = parseInt(wsKey, 10);
            // Check if visible
            var visible = false;
            for (var outName in State.monitorWorkspaces) {
                if (State.monitorWorkspaces[outName] === wsIdNum) {
                    visible = true;
                    break;
                }
            }
            workspaces_data[wsKey] = {
                name: State.workspaceNames[wsIdNum] || "",
                visible: visible,
                windows: windowsByWs[wsKey]
            };
        }

        var json = JSON.stringify({ monitors: monitors, workspaces: workspaces_data });
        try {
            callDBus(UI_DBUS.service, UI_DBUS.path, UI_DBUS.iface, "ShowMap", json);
        } catch (e) {
            Log.debug("UI.showMap: " + e);
        }
    },

    showHelp: function () {
        try {
            callDBus(UI_DBUS.service, UI_DBUS.path, UI_DBUS.iface, "ShowHelp");
        } catch (e) {
            Log.debug("UI.showHelp: " + e);
        }
    },

    startBorderTracking: function () {
        UI._borderTimer = new QTimer();
        UI._borderTimer.interval = 100;
        UI._borderTimer.timeout.connect(function () {
            var current = OutputUtils.getActiveOutputName();
            if (current !== UI._lastBorderOutput) {
                UI._lastBorderOutput = current;
                UI.updateBorder(current);
            }
        });
        UI._borderTimer.start();
    }
};

// ============================================================================
// PERSISTENCE
// ============================================================================
Persistence = {
    _saveTimer: null,

    scheduleSave: function () {
        if (Persistence._saveTimer) {
            Persistence._saveTimer.stop();
        }
        Persistence._saveTimer = new QTimer();
        Persistence._saveTimer.interval = 500;
        Persistence._saveTimer.singleShot = true;
        Persistence._saveTimer.timeout.connect(function () {
            Persistence.save();
        });
        Persistence._saveTimer.start();
    },

    save: function () {
        var state = {
            version: CONFIG.VERSION,
            monitorWorkspaces: State.monitorWorkspaces,
            windowWorkspaces: {},
            workspaceLayouts: State.workspaceLayouts,
            windowZOrder: State.windowZOrder,
            workspaceNames: State.workspaceNames,
            windowInfo: {}
        };

        // Save window matching info (resourceClass + caption)
        var windows = workspace.windowList();
        for (var i = 0; i < windows.length; i++) {
            var win = windows[i];
            if (!WindowUtils.isValid(win)) continue;
            var id = WindowUtils.getId(win);
            if (State.windowWorkspaces[id]) {
                state.windowWorkspaces[id] = State.windowWorkspaces[id];
                state.windowInfo[id] = {
                    resourceClass: win.resourceClass || "",
                    caption: win.caption || "",
                    resourceName: win.resourceName || ""
                };
            }
        }

        try {
            var json = JSON.stringify(state);
            callDBus(STATE_DBUS.service, STATE_DBUS.path, STATE_DBUS.iface, "Save", json);
            Log.debug("save: state persisted (" + json.length + " chars)");
        } catch (e) {
            Log.error("save: failed - " + e);
        }
    },

    load: function () {
        // Load is synchronous at init — use callDBus with callback
        Persistence._loadPending = true;
        callDBus(STATE_DBUS.service, STATE_DBUS.path, STATE_DBUS.iface, "Load",
            function (json) {
                Persistence._loadPending = false;
                if (!json) {
                    Log.info("load: no saved state");
                    Persistence._assignDefaults();
                    UI.updateIndicators();
                    return;
                }
                try {
                    Persistence._applyState(json);
                } catch (e) {
                    Log.error("load: failed to parse - " + e);
                    Persistence._assignDefaults();
                }
                UI.updateIndicators();
            }
        );
        return false; // async — caller should not assume state is loaded yet
    },

    _applyState: function (json) {
        try {
            var state = JSON.parse(json);
            Log.info("load: parsed state v" + state.version);

            // Restore monitor assignments (only for outputs that still exist)
            if (state.monitorWorkspaces) {
                for (var outName in state.monitorWorkspaces) {
                    if (OutputUtils.getOutputByName(outName)) {
                        State.monitorWorkspaces[outName] = state.monitorWorkspaces[outName];
                    }
                }
            }

            // Restore workspace names
            if (state.workspaceNames) {
                for (var wsKey in state.workspaceNames) {
                    State.workspaceNames[wsKey] = state.workspaceNames[wsKey];
                }
            }

            // Restore layouts
            if (state.workspaceLayouts) {
                State.workspaceLayouts = state.workspaceLayouts;
            }

            // Match saved windows to current windows by resourceClass + caption
            var matchedIds = {};
            var currentWindows = workspace.windowList();

            if (state.windowInfo && state.windowWorkspaces) {
                for (var savedId in state.windowWorkspaces) {
                    var info = state.windowInfo[savedId];
                    if (!info) continue;

                    var wsId = state.windowWorkspaces[savedId];
                    var matched = false;

                    for (var w = 0; w < currentWindows.length; w++) {
                        var cw = currentWindows[w];
                        if (!WindowUtils.isValid(cw)) continue;
                        var cid = WindowUtils.getId(cw);
                        if (matchedIds[cid]) continue;

                        if (cw.resourceClass === info.resourceClass &&
                            (cid === savedId || cw.caption === info.caption)) {
                            // Match found
                            State.windowWorkspaces[cid] = wsId;
                            matchedIds[cid] = true;

                            // Remap layout if ID changed
                            if (cid !== savedId && State.workspaceLayouts[wsId]) {
                                if (State.workspaceLayouts[wsId][savedId]) {
                                    State.workspaceLayouts[wsId][cid] = State.workspaceLayouts[wsId][savedId];
                                    delete State.workspaceLayouts[wsId][savedId];
                                }
                            }

                            Log.debug("load: matched '" + cw.caption + "' to workspace " + wsId);
                            matched = true;
                            break;
                        }
                    }

                    if (!matched) {
                        Log.debug("load: no match for saved window '" + (info.caption || savedId) + "'");
                    }
                }
            }

            // Restore Z-order
            if (state.windowZOrder) {
                State.windowZOrder = state.windowZOrder;
            }

            // Ensure all current monitors have an assignment
            var screens = workspace.screens;
            var usedWorkspaces = {};
            for (var o in State.monitorWorkspaces) {
                usedWorkspaces[State.monitorWorkspaces[o]] = true;
            }
            for (var s = 0; s < screens.length; s++) {
                var sName = screens[s].name;
                if (!State.monitorWorkspaces[sName]) {
                    for (var nw = 1; nw <= CONFIG.MAX_WORKSPACES; nw++) {
                        if (!usedWorkspaces[nw]) {
                            State.monitorWorkspaces[sName] = nw;
                            usedWorkspaces[nw] = true;
                            break;
                        }
                    }
                }
            }

            // Now park/unpark windows according to restored state
            Persistence._restoreWindowPositions();
            WorkspaceSwitcher._updateWindowMaps();
            Log.info("load: state restored — " + JSON.stringify(State.monitorWorkspaces));
        } catch (e) {
            Log.error("load: failed to apply state - " + e);
        }
    },

    _assignDefaults: function () {
        var screens = workspace.screens;
        for (var i = 0; i < screens.length; i++) {
            State.monitorWorkspaces[screens[i].name] = i + 1;
            Log.info("Default: " + screens[i].name + " -> workspace " + (i + 1));
        }
    },

    _restoreWindowPositions: function () {
        var windows = workspace.windowList();

        for (var i = 0; i < windows.length; i++) {
            var win = windows[i];
            if (!WindowUtils.isValid(win)) continue;

            var id = WindowUtils.getId(win);
            var wsId = State.windowWorkspaces[id];
            if (!wsId) continue;

            // Is this workspace visible?
            var visibleOutput = null;
            for (var outName in State.monitorWorkspaces) {
                if (State.monitorWorkspaces[outName] === wsId) {
                    visibleOutput = outName;
                    break;
                }
            }

            if (visibleOutput) {
                // Unpark to stage and restore position
                ParkingManager.unparkWindow(win);
                var output = OutputUtils.getOutputByName(visibleOutput);
                var layout = (State.workspaceLayouts[wsId] || {})[id];
                if (layout && output) {
                    var abs = PositionMath.relativeToAbsolute(layout, output);
                    if (layout.maximized) {
                        win.setMaximize(false, false);
                        win.frameGeometry = { x: abs.x, y: abs.y, width: abs.width, height: abs.height };
                        win.setMaximize(true, true);
                    } else {
                        win.setMaximize(false, false);
                        win.frameGeometry = { x: abs.x, y: abs.y, width: abs.width, height: abs.height };
                    }
                }
            } else {
                // Park to its workspace's parking desktop
                ParkingManager.parkWindow(win, wsId);
            }
        }
    }
};

// ============================================================================
// SIGNALS
// ============================================================================
var Signals = {
    _desktopChangeLock: false,

    init: function () {
        // Window added — auto-assign to active monitor's workspace
        workspace.windowAdded.connect(function (win) {
            if (State.switchInProgress) return;
            if (!WindowUtils.isValid(win)) return;

            var id = WindowUtils.getId(win);
            // Don't reassign already-tracked windows (e.g. returning from park)
            if (State.windowWorkspaces[id]) return;

            // Make sure window is on stage
            ParkingManager.unparkWindow(win);

            var outputName = OutputUtils.getWindowOutputName(win);
            var wsId = State.monitorWorkspaces[outputName];
            if (wsId) {
                State.windowWorkspaces[id] = wsId;
                Log.debug("windowAdded: '" + win.caption + "' assigned to workspace " + wsId + " on " + outputName);
                Persistence.scheduleSave();
            }
        });

        // Window removed — cleanup
        workspace.windowRemoved.connect(function (win) {
            var id = WindowUtils.getId(win);
            var wsId = State.windowWorkspaces[id];

            delete State.windowWorkspaces[id];
            delete State.windowZOrder[id];

            if (wsId && State.workspaceLayouts[wsId]) {
                delete State.workspaceLayouts[wsId][id];
            }

            // Clear workspace name if last window left
            if (wsId) {
                var remaining = 0;
                for (var wid in State.windowWorkspaces) {
                    if (State.windowWorkspaces[wid] === wsId) {
                        remaining++;
                    }
                }
                if (remaining === 0 && State.workspaceNames[wsId]) {
                    delete State.workspaceNames[wsId];
                    Log.debug("windowRemoved: cleared name from empty workspace " + wsId);
                }
            }

            Log.debug("windowRemoved: cleaned up '" + (win.caption || id) + "'");
            Persistence.scheduleSave();
        });

        // Screen configuration changed
        workspace.screensChanged.connect(function () {
            Log.info("screensChanged: rebuilding output order");
            OutputUtils.buildOutputOrder();

            // Assign defaults to new monitors
            var screens = workspace.screens;
            var usedWorkspaces = {};
            for (var o in State.monitorWorkspaces) {
                usedWorkspaces[State.monitorWorkspaces[o]] = true;
            }

            for (var s = 0; s < screens.length; s++) {
                var name = screens[s].name;
                if (!State.monitorWorkspaces[name]) {
                    // Find first unused workspace
                    for (var w = 1; w <= CONFIG.MAX_WORKSPACES; w++) {
                        if (!usedWorkspaces[w]) {
                            State.monitorWorkspaces[name] = w;
                            usedWorkspaces[w] = true;
                            Log.info("screensChanged: assigned workspace " + w + " to new output " + name);
                            break;
                        }
                    }
                }
            }

            // Remove assignments for disconnected outputs
            for (var outName in State.monitorWorkspaces) {
                if (!OutputUtils.getOutputByName(outName)) {
                    Log.info("screensChanged: removed assignment for disconnected output " + outName);
                    delete State.monitorWorkspaces[outName];
                }
            }

            Persistence.scheduleSave();
            UI.updateIndicators();
        });

        // Force back to stage desktop if user switches via pager
        workspace.currentDesktopChanged.connect(function (newDesktop, oldDesktop) {
            if (Signals._desktopChangeLock) return;

            if (newDesktop !== State.stageDesktop) {
                Log.debug("currentDesktopChanged: intercepting switch to parking desktop, forcing back to stage");
                Signals._desktopChangeLock = true;
                workspace.currentDesktop = State.stageDesktop;
                Signals._desktopChangeLock = false;
            }
        });

        // Per-window output changes (dragged between monitors)
        workspace.windowList().forEach(function (win) {
            Signals._connectWindowOutput(win);
        });

        // Also connect for future windows
        workspace.windowAdded.connect(function (win) {
            Signals._connectWindowOutput(win);
        });

        Log.info("Signals.init: all signals connected");
    },

    _connectWindowOutput: function (win) {
        if (!WindowUtils.isValid(win)) return;

        win.outputChanged.connect(function () {
            if (State.switchInProgress) return;
            if (!WindowUtils.isValid(win)) return;
            if (ParkingManager.isParked(win)) return;

            var id = WindowUtils.getId(win);
            var oldWs = State.windowWorkspaces[id];
            var newOutputName = OutputUtils.getWindowOutputName(win);
            var newWs = State.monitorWorkspaces[newOutputName];

            if (oldWs && newWs && oldWs !== newWs) {
                // Remove from old layout
                if (State.workspaceLayouts[oldWs]) {
                    delete State.workspaceLayouts[oldWs][id];
                }
                State.windowWorkspaces[id] = newWs;
                Log.debug("outputChanged: '" + win.caption + "' moved from ws " + oldWs + " to ws " + newWs);
                Persistence.scheduleSave();
            }
        });
    }
};

// ============================================================================
// HOTKEYS
// ============================================================================
var Hotkeys = {
    init: function () {
        // Alt+1 through Alt+9: Switch to workspace 1-9
        for (var i = 1; i <= 9; i++) {
            (function (ws) {
                registerShortcut(
                    "Cerberus: Switch to Workspace " + ws,
                    "Cerberus: Switch to Workspace " + ws,
                    "Alt+" + ws,
                    function () { WorkspaceSwitcher.switchWorkspace(ws); }
                );
            })(i);
        }
        // Alt+0: Switch to workspace 10
        registerShortcut(
            "Cerberus: Switch to Workspace 10",
            "Cerberus: Switch to Workspace 10",
            "Alt+0",
            function () { WorkspaceSwitcher.switchWorkspace(10); }
        );

        // Ctrl+Alt+1 through Ctrl+Alt+9: Switch to workspace 11-19
        for (var j = 1; j <= 9; j++) {
            (function (n, ws) {
                registerShortcut(
                    "Cerberus: Switch to Workspace " + ws,
                    "Cerberus: Switch to Workspace " + ws,
                    "Ctrl+Alt+" + n,
                    function () { WorkspaceSwitcher.switchWorkspace(ws); }
                );
            })(j, j + 10);
        }
        // Ctrl+Alt+0: Switch to workspace 20
        registerShortcut(
            "Cerberus: Switch to Workspace 20",
            "Cerberus: Switch to Workspace 20",
            "Ctrl+Alt+0",
            function () { WorkspaceSwitcher.switchWorkspace(20); }
        );

        // Alt+Shift+1 through Alt+Shift+0: Send to workspace 1-10
        // On US layout, Shift changes number keysyms: 1->! 2->@ 3-># 4->$ 5->% 6->^ 7->& 8->* 9->( 0->)
        // KWin/Wayland matches against the resolved keysym, so register with shifted characters
        var shiftedDigits = [")", "!", "@", "#", "$", "%", "^", "&", "*", "("];
        for (var k = 1; k <= 9; k++) {
            (function (ws, key) {
                registerShortcut(
                    "Cerberus: Send to Workspace " + ws,
                    "Cerberus: Send to Workspace " + ws,
                    "Alt+" + key,
                    function () { WindowSender.sendToWorkspace(ws); }
                );
            })(k, shiftedDigits[k]);
        }
        registerShortcut(
            "Cerberus: Send to Workspace 10",
            "Cerberus: Send to Workspace 10",
            "Alt+" + shiftedDigits[0],
            function () { WindowSender.sendToWorkspace(10); }
        );

        // Ctrl+Alt+Shift+1 through Ctrl+Alt+Shift+0: Send to workspace 11-20
        for (var m = 1; m <= 9; m++) {
            (function (ws, key) {
                registerShortcut(
                    "Cerberus: Send to Workspace " + ws,
                    "Cerberus: Send to Workspace " + ws,
                    "Ctrl+Alt+" + key,
                    function () { WindowSender.sendToWorkspace(ws); }
                );
            })(m + 10, shiftedDigits[m]);
        }
        registerShortcut(
            "Cerberus: Send to Workspace 20",
            "Cerberus: Send to Workspace 20",
            "Ctrl+Alt+" + shiftedDigits[0],
            function () { WindowSender.sendToWorkspace(20); }
        );

        // Alt+Up/Down: Navigate empty workspaces
        registerShortcut(
            "Cerberus: Next Empty Workspace",
            "Cerberus: Next Empty Workspace",
            "Alt+Up",
            function () { Navigation.switchToNextEmptyWorkspace(); }
        );
        registerShortcut(
            "Cerberus: Previous Empty Workspace",
            "Cerberus: Previous Empty Workspace",
            "Alt+Down",
            function () { Navigation.switchToPreviousEmptyWorkspace(); }
        );

        // Alt+Shift+Up/Down: Send to empty workspaces
        registerShortcut(
            "Cerberus: Send to Next Empty Workspace",
            "Cerberus: Send to Next Empty Workspace",
            "Alt+Shift+Up",
            function () { Navigation.sendToNextEmptyWorkspace(); }
        );
        registerShortcut(
            "Cerberus: Send to Previous Empty Workspace",
            "Cerberus: Send to Previous Empty Workspace",
            "Alt+Shift+Down",
            function () { Navigation.sendToPreviousEmptyWorkspace(); }
        );

        // Alt+Shift+T: Tile windows
        registerShortcut(
            "Cerberus: Tile Windows",
            "Cerberus: Tile Windows",
            "Alt+Shift+T",
            function () { Tiling.tileWindows(); }
        );

        // Alt+Shift+R: Refresh monitors
        registerShortcut(
            "Cerberus: Refresh Monitors",
            "Cerberus: Refresh Monitors",
            "Alt+Shift+R",
            function () {
                OutputUtils.buildOutputOrder();
                WorkspaceSwitcher._updateWindowMaps();
                UI.updateIndicators();
                Log.info("Refresh: monitors rebuilt");
            }
        );

        // Alt+Shift+O: Toggle overlays
        registerShortcut(
            "Cerberus: Toggle Overlays",
            "Cerberus: Toggle Overlays",
            "Alt+Shift+O",
            function () { UI.toggleOverlays(); }
        );

        // Alt+Shift+N: Name workspace
        registerShortcut(
            "Cerberus: Name Workspace",
            "Cerberus: Name Workspace",
            "Alt+Shift+N",
            function () { UI.showNameDialog(); }
        );

        // Alt+Shift+W: Show workspace map
        registerShortcut(
            "Cerberus: Show Workspace Map",
            "Cerberus: Show Workspace Map",
            "Alt+Shift+W",
            function () { UI.showMap(); }
        );

        // Alt+Shift+H: Show help
        registerShortcut(
            "Cerberus: Show Help",
            "Cerberus: Show Help",
            "Alt+Shift+H",
            function () { UI.showHelp(); }
        );

        Log.info("Hotkeys.init: all shortcuts registered");
    }
};

// ============================================================================
// INIT
// ============================================================================
var Init = {
    run: function () {
        Log.info("Cerberus v" + CONFIG.VERSION + " starting");

        CONFIG.init();
        OutputUtils.buildOutputOrder();
        ParkingManager.init();

        // Ensure we're on the stage desktop
        workspace.currentDesktop = State.stageDesktop;

        // Set up defaults first (load callback will override if state exists)
        Persistence._assignDefaults();

        Signals.init();
        Hotkeys.init();

        // Initial window map update
        WorkspaceSwitcher._updateWindowMaps();

        // Start UI border tracking (100ms poll for active output changes)
        UI.startBorderTracking();

        // Initial indicator update
        UI.updateIndicators();

        Log.info("Cerberus v" + CONFIG.VERSION + " initialized");
        Log.info("Monitors: " + JSON.stringify(State.monitorWorkspaces));

        // Try to load saved state (async — will restore when D-Bus responds)
        Persistence.load();
    }
};

// ============================================================================
// START
// ============================================================================
Init.run();

})();
