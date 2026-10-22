pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import "../../"

Item {
    id: root

    property int subscribers: 0
    signal updated()

    property var windows: []
    property var groups: ({})
    property var groupOrder: []
    property var activeWorkspaceByOutput: ({})

    readonly property bool isHyprland: Boolean(Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE")) || ((typeof SystemInfo !== "undefined" && SystemInfo.desktopEnv) ? (SystemInfo.desktopEnv.toLowerCase().indexOf("hyprland") !== -1) : false)

    property var _mruTimestamps: ({})
    property int _seqCounter: 0

    Component.onCompleted: {
        _requestRebuild();
    }

    function subscribe() {
        subscribers++;
        if (subscribers === 1) {
            _requestRebuild();
        }
    }

    function unsubscribe() {
        subscribers = Math.max(0, subscribers - 1);
    }

    Timer {
        id: debounceTimer
        interval: 40
        repeat: false
        onTriggered: root._rebuild()
    }

    function _requestRebuild() {
        if (!debounceTimer.running) {
            debounceTimer.restart();
        }
    }

    function _recordFocus(nativeId) {
        if (!nativeId) return;
        _mruTimestamps[String(nativeId)] = Date.now();
    }

    function _getMru(nativeId) {
        if (!nativeId) return 0;
        return _mruTimestamps[String(nativeId)] || 0;
    }

    function _rebuild() {
        let rawList = [];

        if (isHyprland && typeof Hyprland !== "undefined" && Hyprland.toplevels && Hyprland.toplevels.values) {
            rawList = root._collectHyprlandWindows();
        } else if (typeof ToplevelManager !== "undefined" && ToplevelManager.toplevels && ToplevelManager.toplevels.values) {
            rawList = root._collectWaylandWindows();
        }

        let newGroups = {};
        let newGroupOrder = [];

        for (let i = 0; i < rawList.length; i++) {
            let win = rawList[i];
            let gk = win.groupKey;
            if (!newGroups[gk]) {
                newGroups[gk] = {
                    groupKey: gk,
                    desktopId: win.desktopId,
                    appId: win.appId,
                    windows: [],
                    count: 0,
                    focused: false,
                    activeWindow: null
                };
                newGroupOrder.push(gk);
            }
            let grp = newGroups[gk];
            grp.windows.push(win);
            grp.count++;
            if (win.focused) {
                grp.focused = true;
            }
        }

        for (let k in newGroups) {
            let grp = newGroups[k];
            grp.windows.sort(function(a, b) {
                if (a.focused !== b.focused) return a.focused ? -1 : 1;
                return b.lastFocus - a.lastFocus;
            });
            grp.activeWindow = grp.windows.length > 0 ? grp.windows[0] : null;
        }

        root.windows = rawList;
        root.groups = newGroups;
        root.groupOrder = newGroupOrder;
        root.updated();
    }

    function _collectHyprlandWindows() {
        let list = [];
        let toplevels = Hyprland.toplevels.values;
        for (let i = 0; i < toplevels.length; i++) {
            let t = toplevels[i];
            if (!t) continue;
            let addr = t.address ? String(t.address) : String(i);
            let rawApp = (t.wayland && t.wayland.appId) ? t.wayland.appId : ((t.lastIpcObject && (t.lastIpcObject["class"] || t.lastIpcObject["initialClass"])) ? (t.lastIpcObject["class"] || t.lastIpcObject["initialClass"]) : "");
            let appKey = AppMatcher.normalizeKey(rawApp);
            let dId = AppMatcher.resolve(rawApp);
            let cid = dId !== "" ? AppMatcher.canonicalId(dId) : AppMatcher.canonicalId(rawApp);
            let gKey = cid !== "" ? cid : (appKey !== "" ? appKey : ("win:" + addr));
            let isFoc = Boolean(t.activated || (typeof Hyprland !== "undefined" && Hyprland.activeToplevel && Hyprland.activeToplevel.address === t.address));
            if (isFoc) _recordFocus(addr);

            let wsObj = t.workspace || (t.lastIpcObject ? t.lastIpcObject.workspace : null);
            let rawWsId = (wsObj && wsObj.id !== undefined) ? wsObj.id : -1;
            let wsId = (rawWsId > 0) ? (rawWsId - 1) : -1;
            let wsName = (wsObj && wsObj.name) ? String(wsObj.name) : (rawWsId >= 0 ? String(rawWsId) : "");
            let monName = (t.monitor && t.monitor.name) ? String(t.monitor.name) : ((t.lastIpcObject && t.lastIpcObject.monitor !== undefined) ? String(t.lastIpcObject.monitor) : "");

            list.push({
                id: "hypr:" + addr,
                nativeId: addr,
                seq: ++_seqCounter,
                appId: rawApp,
                appKey: appKey,
                title: t.title || (t.lastIpcObject && t.lastIpcObject.title ? t.lastIpcObject.title : ""),
                workspace: wsId,
                workspaceLabel: wsName,
                output: monName,
                focused: isFoc,
                lastFocus: _getMru(addr),
                desktopId: dId !== "" ? (dId.endsWith(".desktop") ? dId : (dId + ".desktop")) : (rawApp ? (rawApp + ".desktop") : ""),
                canonicalId: cid,
                groupKey: gKey,
                native: t
            });
        }
        return list;
    }

    function _collectWaylandWindows() {
        let list = [];
        let toplevels = ToplevelManager.toplevels.values;
        for (let i = 0; i < toplevels.length; i++) {
            let t = toplevels[i];
            if (!t) continue;
            let addr = String(i);
            let rawApp = t.appId || "";
            let appKey = AppMatcher.normalizeKey(rawApp);
            let dId = AppMatcher.resolve(rawApp);
            let cid = dId !== "" ? AppMatcher.canonicalId(dId) : AppMatcher.canonicalId(rawApp);
            let gKey = cid !== "" ? cid : (appKey !== "" ? appKey : ("win:" + addr));
            let isFoc = Boolean(t.activated);
            if (isFoc) _recordFocus(addr);

            let monName = "";
            if (t.screens && t.screens.length > 0 && t.screens[0]) {
                monName = t.screens[0].name || "";
            }

            list.push({
                id: "wayland:" + addr,
                nativeId: addr,
                seq: ++_seqCounter,
                appId: rawApp,
                appKey: appKey,
                title: t.title || "",
                workspace: -1,
                workspaceLabel: "",
                output: monName,
                focused: isFoc,
                lastFocus: _getMru(addr),
                desktopId: dId !== "" ? (dId.endsWith(".desktop") ? dId : (dId + ".desktop")) : (rawApp ? (rawApp + ".desktop") : ""),
                canonicalId: cid,
                groupKey: gKey,
                native: t
            });
        }
        return list;
    }

    function _formatHyprAddress(nid) {
        if (!nid) return "";
        let s = String(nid).trim();
        if (s.startsWith("address:")) {
            s = s.substring(8).trim();
        }
        if (!s.startsWith("0x")) {
            s = "0x" + s;
        }
        return "address:" + s;
    }

    function _focusHyprland(win) {
        if (!win) return;
        let nid = (typeof win === "object") ? win.nativeId : win;
        if (nid === undefined || nid === null || nid === "") return;
        let addr = root._formatHyprAddress(nid);
        if (typeof Hyprland !== "undefined") {
            if (Hyprland.usingLua !== false) {
                Hyprland.dispatch("hl.dsp.focus({ window = \"" + addr + "\" })");
            } else {
                Hyprland.dispatch("focuswindow " + addr);
            }
            return;
        }
        Quickshell.execDetached(["sh", "-c", "hyprctl dispatch 'hl.dsp.focus({ window = \"" + addr + "\" })' 2>/dev/null || hyprctl dispatch focuswindow " + addr]);
    }

    function _closeHyprland(win) {
        if (!win) return;
        let nid = (typeof win === "object") ? win.nativeId : win;
        if (nid === undefined || nid === null || nid === "") return;
        let addr = root._formatHyprAddress(nid);
        if (typeof Hyprland !== "undefined") {
            if (Hyprland.usingLua !== false) {
                Hyprland.dispatch("hl.dsp.window.close({ window = \"" + addr + "\" })");
            } else {
                Hyprland.dispatch("closewindow " + addr);
            }
            return;
        }
        Quickshell.execDetached(["sh", "-c", "hyprctl dispatch 'hl.dsp.window.close({ window = \"" + addr + "\" })' 2>/dev/null || hyprctl dispatch closewindow " + addr]);
    }

    function focusWindow(win) {
        if (!win) return;
        let nid = (typeof win === "object") ? win.nativeId : win;
        if (nid) _recordFocus(nid);

        if (isHyprland) {
            root._focusHyprland(win);
            return;
        }

        if (typeof win === "object" && win && win.native && typeof win.native.activate === "function") {
            win.native.activate();
            return;
        }
    }

    function activate(win) {
        root.focusWindow(win);
    }

    function activateWindow(win) {
        root.focusWindow(win);
    }

    function close(win) {
        if (!win) return;
        if (typeof win === "object" && win && win.native && typeof win.native.close === "function") {
            win.native.close();
            return;
        }
        if (isHyprland) {
            root._closeHyprland(win);
            return;
        }
    }

    Connections {
        target: (typeof ToplevelManager !== "undefined" && ToplevelManager.toplevels) ? ToplevelManager.toplevels : null
        function onValuesChanged() { root._requestRebuild(); }
    }

    Connections {
        target: (typeof ToplevelManager !== "undefined") ? ToplevelManager : null
        function onActiveToplevelChanged() { root._requestRebuild(); }
    }

    Connections {
        target: (typeof Hyprland !== "undefined" && Hyprland.toplevels) ? Hyprland.toplevels : null
        function onValuesChanged() { root._requestRebuild(); }
    }

    Connections {
        target: (typeof Hyprland !== "undefined") ? Hyprland : null
        function onActiveToplevelChanged() { root._requestRebuild(); }
        function onFocusedMonitorChanged() { root._requestRebuild(); }
        function onFocusedWorkspaceChanged() { root._requestRebuild(); }
        function onRawEvent(event) {
            if (!event || !event.name) return;
            let n = event.name;
            if (n === "activewindow" || n === "activewindowv2" || n === "openwindow" || n === "closewindow" || n === "movewindow" || n === "workspace" || n === "focusedmon") {
                root._requestRebuild();
            }
        }
    }

    Connections {
        target: AppMatcher
        function onIndexChanged() { root._requestRebuild(); }
    }
}
