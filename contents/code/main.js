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
    function resolveScreen(screenTarget) {
        if (screenTarget === 0) {
            return workspace.screenAt(workspace.cursorPos) || workspace.activeScreen;
        }
        var idx = screenTarget - 1;
        if (idx >= 0 && idx < workspace.screens.length) return workspace.screens[idx];
        return workspace.activeScreen;
    }

    function applyDropdownGeometry(win, widthPct, heightPct, screenTarget) {
        var screen = resolveScreen(screenTarget);
        var area = workspace.clientArea(KWin.MaximizeArea, screen, workspace.currentDesktop);
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
    // Key: windowClass string  Value: { x, y, width, height, savedOpacity }
    //
    var hiddenWindows = {}; // windowClass → { x, y, width, height, savedOpacity }

    // ── Hide helper ───────────────────────────────────────────────────────────
    function hideWindow(windowClass) {
        var win = findByClass(windowClass);
        if (!win) return;
        // Guard: already off-screen — don't re-hide / re-snapshot.
        if (hiddenWindows[windowClass] !== undefined) return;

        var g = win.frameGeometry;
        hiddenWindows[windowClass] = {
            x: g.x, y: g.y, width: g.width, height: g.height,
            savedOpacity: win.opacity
        };

        win.skipTaskbar  = true;
        win.skipPager    = true;
        win.skipSwitcher = true;

        // Restore user's original opacity BEFORE sliding out so the next show
        // re-snapshots a clean value and we never lose the original.
        win.opacity = hiddenWindows[windowClass].savedOpacity;

        win.frameGeometry = { x: g.x, y: -g.height, width: g.width, height: g.height };

        dbg("auto/shortcut hide → " + windowClass + "\nAction: hidden (slide-out)");
    }

    // ── Toggle ────────────────────────────────────────────────────────────────
    function toggleWindow(windowClass, shortcut, widthPct, heightPct, screenTarget,
                          opacity, allDesktops, autoHide) {
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
            hideWindow(windowClass);
            return;
        }

        // ── Show ──────────────────────────────────────────────────────────────

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

        if (isHidden) {
            // Window is parked at y = -height (off-screen by our script).
            // Always recompute geometry for the target screen — restoring the
            // saved position would put the window on the wrong screen if the
            // user changed screenTarget since the last hide.
            delete hiddenWindows[windowClass];
        }

        // Always position on the configured screen (cursor screen, Screen 1, etc.).
        // The effect sees the geometry change from off-screen → visible and
        // animates the slide-in regardless of how we got here.
        applyDropdownGeometry(win, widthPct, heightPct, screenTarget);

        win.onAllDesktops = allDesktops;
        win.opacity = opacity / 100.0;

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
        var sPct  = readConfig("screenTarget"  + i, 0);
        var opc   = readConfig("opacity"       + i, 100);
        var allD  = readConfig("allDesktops"   + i, false);
        var aHide = readConfig("autoHide"      + i, false);
        if (cls === "" || sc === "") continue;

        (function (windowClass, shortcut, widthPct, heightPct, screenTarget,
                   opacity, allDesktops, autoHide) {
            registerShortcut(
                "DropdownAny-" + windowClass,
                "Dropdown toggle: " + windowClass,
                shortcut,
                function () {
                    toggleWindow(windowClass, shortcut, widthPct, heightPct, screenTarget,
                                 opacity, allDesktops, autoHide);
                }
            );

            if (autoHide === true) {
                workspace.windowActivated.connect(function (activeWin) {
                    // Already parked off-screen — don't re-hide.
                    if (hiddenWindows[windowClass] !== undefined) return;
                    var win = findByClass(windowClass);
                    if (!win) return;
                    // We are the newly-active window — don't self-hide.
                    if (activeWin === win) return;
                    // Any other focus target (including null = desktop) → hide.
                    hideWindow(windowClass);
                });
            }
        })(cls, sc, wPct, hPct, sPct, opc, allD, aHide);

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
