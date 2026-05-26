"use strict";

// plasma-dropdown-any — KWin Script for Plasma 6
//
// Registers a configurable dropdown toggle for any window by its resource class.
// Up to 10 window/shortcut pairs can be configured via System Settings → KWin Scripts.
//
// Option C — slide animation via kwin4_effect_geometry_change:
//   The GeometryChange effect automatically animates any frameGeometry transition.
//   We hide windows by moving them off-screen (y = -height) instead of minimizing,
//   so the effect can animate the slide. Minimized windows are skipped by the effect.
//
// Option C install:
//   cp this file to ~/.local/share/kwin/scripts/plasma-dropdown-any/contents/code/main.js
//   Enable "GeometryChange" in System Settings → Desktop Effects
//   Reload script via KWin Scripts settings
//
// NOTE: Qt namespace is not available in KWin JavaScript scripts (Plasma 6).
//       Geometry is set by mutating the QRectF returned by clientArea() and
//       assigning it back, which works because Q_GADGETs are mutable in
//       Qt 6's QJSEngine.

(function () {

    // ── Window lookup ─────────────────────────────────────────────────────────
    function getWindows() {
        if (typeof workspace.windowList === "function") return workspace.windowList();
        if (typeof workspace.clientList === "function") return workspace.clientList();
        return [];
    }

    function findByClass(cls) {
        var lc = cls.toLowerCase();
        var wins = getWindows();
        for (var i = 0; i < wins.length; i++) {
            var w = wins[i];
            if (w.resourceClass.toLowerCase() === lc || w.resourceName.toLowerCase() === lc) {
                return w;
            }
        }
        return null;
    }

    // ── Geometry ──────────────────────────────────────────────────────────────
    //
    // Qt.rect() is unavailable in KWin JS scripts. Instead we mutate the QRectF
    // returned by clientArea() — this works because Qt 6's QJSEngine exposes
    // Q_GADGETs as mutable JavaScript values.
    //
    function applyDropdownGeometry(win, widthPct, heightPct) {
        var area = workspace.clientArea(KWin.MaximizeArea, workspace.activeScreen, workspace.currentDesktop);
        var fullW = area.width;
        var fullH = area.height;
        area.width  = Math.round(fullW * widthPct);
        area.height = Math.round(fullH * heightPct);
        // Center horizontally when width < 100%
        area.x = area.x + Math.round((fullW - area.width) / 2);
        win.frameGeometry = area;
    }

    // ── Debug ─────────────────────────────────────────────────────────────────
    var dbgMode = readConfig("debugMode", false);

    function dbg(msg) {
        console.log("[DropdownAny] " + msg);
        if (!dbgMode) return;
        callDBus(
            "org.kde.plasmashell",
            "/org/kde/osdService",
            "org.kde.osdService",
            "showText",
            "utilities-terminal",
            "[DropdownAny]\n" + msg
        );
    }

    // ── Hidden-windows tracker ────────────────────────────────────────────────
    //
    // Stores the on-screen geometry for each window we've moved off-screen.
    // Key: windowClass string  Value: { x, y, width, height }
    //
    var hiddenWindows = {}; // windowClass → { x, y, width, height }

    // ── Toggle ────────────────────────────────────────────────────────────────
    function toggleWindow(windowClass, shortcut, widthPct, heightPct) {
        var win = findByClass(windowClass);
        if (!win) {
            dbg(shortcut + " → " + windowClass + "\nWindow not found");
            return;
        }

        var isHidden    = hiddenWindows[windowClass] !== undefined;
        var isMinimized = win.minimized;

        // ── Hide ──────────────────────────────────────────────────────────────
        // Window is visible (not in our off-screen tracker, not minimized) and focused.
        if (!isHidden && !isMinimized && win.active) {
            // Save the current on-screen geometry so we can restore it later.
            var g = win.frameGeometry;
            hiddenWindows[windowClass] = { x: g.x, y: g.y, width: g.width, height: g.height };

            // Remove from taskbar/pager/switcher so it doesn't appear as an
            // accessible window while it is parked off-screen.
            win.skipTaskbar  = true;
            win.skipPager    = true;
            win.skipSwitcher = true;

            // Move off-screen — kwin4_effect_geometry_change animates this slide-out.
            win.frameGeometry = { x: g.x, y: -g.height, width: g.width, height: g.height };

            dbg(shortcut + " → " + windowClass + " [" + (win.caption || "") + "]\nAction: hidden (slide-out)");
            return;
        }

        // ── Show ──────────────────────────────────────────────────────────────
        var savedGeom = hiddenWindows[windowClass];

        // Always keep the dropdown above other windows and hidden from
        // taskbar/pager/switcher while we reposition it.
        win.keepAbove    = true;
        win.skipTaskbar  = true;
        win.skipPager    = true;
        win.skipSwitcher = true;

        if (isMinimized) {
            // Window was minimized by the user (not by our script).
            // Unminimize first so KWin treats it as a real window again,
            // then let the geometry path below position it correctly.
            win.minimized = false;
        }

        if (savedGeom) {
            // The window is currently parked at y = -height (off-screen).
            // Setting frameGeometry to the saved on-screen rect triggers the
            // slide-in animation from the effect — it sees the geometry change
            // from off-screen → visible and animates it.
            win.frameGeometry = savedGeom;
            delete hiddenWindows[windowClass];
        } else {
            // First show (or window was minimized by the user): size and position
            // the window as a dropdown, then animate from wherever it currently is.
            applyDropdownGeometry(win, widthPct, heightPct);
        }

        // Restore taskbar/pager/switcher visibility now that the window is on-screen.
        win.skipTaskbar  = false;
        win.skipPager    = false;
        win.skipSwitcher = false;

        workspace.activeWindow = win;

        dbg(shortcut + " → " + windowClass + " [" + (win.caption || "") + "]\nAction: shown (slide-in)");
    }

    // ── Shortcut registration ─────────────────────────────────────────────────
    var registered = 0;
    for (var i = 1; i <= 10; i++) {
        var cls  = readConfig("windowClass"   + i, "").trim();
        var sc   = readConfig("shortcut"      + i, "").trim();
        var wPct = readConfig("widthPercent"  + i, 100) / 100.0;
        var hPct = readConfig("heightPercent" + i, 50)  / 100.0;
        if (cls === "" || sc === "") continue;

        (function (windowClass, shortcut, widthPct, heightPct) {
            registerShortcut(
                "DropdownAny-" + windowClass,
                "Dropdown toggle: " + windowClass,
                shortcut,
                function () { toggleWindow(windowClass, shortcut, widthPct, heightPct); }
            );
        })(cls, sc, wPct, hPct);

        registered++;
    }

    // ── Window class scanner ──────────────────────────────────────────────────
    //
    // Press Meta+Shift+W to see an OSD listing every open window's
    // resourceClass and title. Use this to find the class name for any app
    // before entering it in the Configure dialog.
    //
    function listWindowClasses() {
        var wins = getWindows();
        var seen = {};
        var lines = [];
        for (var i = 0; i < wins.length; i++) {
            var w = wins[i];
            var cls = w.resourceClass;
            if (!cls || cls === "" || seen[cls]) continue;
            seen[cls] = true;
            var title = w.caption || "";
            // Truncate long titles
            if (title.length > 40) title = title.substring(0, 38) + "…";
            lines.push(cls + " → " + title);
        }
        lines.sort();

        callDBus(
            "org.kde.plasmashell",
            "/org/kde/osdService",
            "org.kde.osdService",
            "showText",
            "dialog-information",
            lines.length > 0 ? lines.join("\n") : "(no windows found)"
        );
    }

    registerShortcut(
        "DropdownAny-ListWindows",
        "Dropdown Any: List active window classes",
        "Meta+Shift+W",
        listWindowClasses
    );

    console.log("[DropdownAny] loaded — " + registered + "/10 slots active.");
})();
