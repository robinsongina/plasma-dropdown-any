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

    // direction: "top" (default), "bottom", "left", or "right" — which screen
    // edge the dropdown is anchored to. The perpendicular axis is centered
    // (e.g. "left" centers vertically; "top" centers horizontally).
    function applyDropdownGeometry(win, widthPct, heightPct, screenTarget, direction) {
        var screen = resolveScreen(screenTarget);
        var area = workspace.clientArea(KWin.MaximizeArea, screen, workspace.currentDesktop);
        var fullW = area.width;
        var fullH = area.height;
        var w = Math.round(fullW * widthPct);
        var h = Math.round(fullH * heightPct);

        var x, y;
        switch (direction) {
            case "bottom":
                x = area.x + Math.round((fullW - w) / 2);
                y = area.y + fullH - h;
                break;
            case "left":
                x = area.x;
                y = area.y + Math.round((fullH - h) / 2);
                break;
            case "right":
                x = area.x + fullW - w;
                y = area.y + Math.round((fullH - h) / 2);
                break;
            case "top":
            default:
                x = area.x + Math.round((fullW - w) / 2);
                y = area.y;
                break;
        }

        area.x = x;
        area.y = y;
        area.width  = w;
        area.height = h;
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

    // ── Slot config (mutable) ─────────────────────────────────────────────────
    //
    // Populated during shortcut registration. Keeps live widthPct/heightPct so
    // the resize shortcuts can update them and have toggleWindow pick up the new
    // values immediately (without waiting for a script reload).
    //
    var slotConfig = {}; // windowClass → { idx, widthPct, heightPct, screenTarget, opacity, allDesktops, autoHide }

    // ── Hide helper ───────────────────────────────────────────────────────────

    // Raw pixel bounding box spanning every screen (union of Output.geometry,
    // NOT clientArea — panels/docks don't shrink this). Hiding must clear this
    // whole box: pushing a window just past ONE screen's edge either lands it
    // on a neighboring monitor placed edge-to-edge (multi-monitor layouts) or,
    // if computed from clientArea, right on top of a panel reservation instead
    // of truly off-screen.
    function virtualScreenBounds() {
        var screens = workspace.screens;
        var minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
        for (var i = 0; i < screens.length; i++) {
            var g = screens[i].geometry;
            if (g.x < minX) minX = g.x;
            if (g.y < minY) minY = g.y;
            if (g.x + g.width  > maxX) maxX = g.x + g.width;
            if (g.y + g.height > maxY) maxY = g.y + g.height;
        }
        return { x: minX, y: minY, width: maxX - minX, height: maxY - minY };
    }

    function hideWindow(windowClass) {
        var win = findByClass(windowClass);
        if (!win) return;
        // Guard: already off-screen — don't re-hide / re-snapshot.
        if (hiddenWindows[windowClass] !== undefined) return;

        var slot      = slotConfig[windowClass];
        var direction = (slot && slot.direction) || "top";

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

        // Push the window a full window-dimension past the outer edge of ALL
        // screens combined, so the GeometryChange effect can animate the
        // slide back out that way without landing on another monitor or a panel.
        var bounds = virtualScreenBounds();
        var offX = g.x, offY = g.y;
        switch (direction) {
            case "bottom": offY = bounds.y + bounds.height; break;
            case "left":   offX = bounds.x - g.width;       break;
            case "right":  offX = bounds.x + bounds.width;  break;
            case "top":
            default:       offY = bounds.y - g.height;      break;
        }

        win.frameGeometry = { x: offX, y: offY, width: g.width, height: g.height };

        dbg("auto/shortcut hide → " + windowClass + "\nAction: hidden (slide-out, " + direction + ")");
    }

    // ── Toggle ────────────────────────────────────────────────────────────────
    function toggleWindow(windowClass, shortcut) {
        var win = findByClass(windowClass);
        if (!win) {
            dbg(shortcut + " → " + windowClass + "\nWindow not found");
            return;
        }

        var slot        = slotConfig[windowClass];
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
        // Uses slotConfig so live resize changes take effect immediately.
        applyDropdownGeometry(win, slot.widthPct, slot.heightPct, slot.screenTarget, slot.direction);

        win.onAllDesktops = slot.allDesktops;
        win.opacity = slot.opacity / 100.0;

        // Restore taskbar/pager/switcher visibility now that the window is on-screen.
        win.skipTaskbar  = false;
        win.skipPager    = false;
        win.skipSwitcher = false;

        workspace.activeWindow = win;

        dbg(shortcut + " → " + windowClass + " [" + (win.caption || "") + "]\nAction: shown (slide-in)");
    }

    // ── Live resize ───────────────────────────────────────────────────────────
    //
    // Adjusts width or height of the currently active dropdown window by 5 %.
    // Updates slotConfig (in-session) and persists to kwinrc via writeConfig.
    //
    var RESIZE_STEP = 0.05;

    function resizeActive(dw, dh) {
        var win = workspace.activeWindow;
        if (!win) return;
        var lc   = win.resourceClass.toLowerCase();
        var slot = null;
        var matchedClass = null;
        for (var wc in slotConfig) {
            if (wc.toLowerCase() === lc) { slot = slotConfig[wc]; matchedClass = wc; break; }
        }
        if (!slot) return; // active window is not a managed dropdown

        slot.widthPct  = Math.max(0.10, Math.min(1.0, slot.widthPct  + dw));
        slot.heightPct = Math.max(0.10, Math.min(1.0, slot.heightPct + dh));

        applyDropdownGeometry(win, slot.widthPct, slot.heightPct, slot.screenTarget, slot.direction);

        // Persist to kwinrc so the new values survive script reload.
        writeConfig("widthPercent"  + slot.idx, Math.round(slot.widthPct  * 100));
        writeConfig("heightPercent" + slot.idx, Math.round(slot.heightPct * 100));

        dbg("Resize " + matchedClass +
            " → w:" + Math.round(slot.widthPct  * 100) + "%" +
            " h:" + Math.round(slot.heightPct * 100) + "%");
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
        var dir   = readConfig("direction"     + i, "top").trim() || "top";
        if (cls === "" || sc === "") continue;

        slotConfig[cls] = {
            idx: i, widthPct: wPct, heightPct: hPct, screenTarget: sPct,
            opacity: opc, allDesktops: allD, autoHide: aHide, direction: dir
        };

        (function (windowClass, shortcut) {
            registerShortcut(
                "DropdownAny-" + windowClass,
                "Dropdown toggle: " + windowClass,
                shortcut,
                function () { toggleWindow(windowClass, shortcut); }
            );

            if (slotConfig[windowClass].autoHide === true) {
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
        })(cls, sc);

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

    // ── Resize shortcuts ──────────────────────────────────────────────────────
    registerShortcut("DropdownAny-ResizeHeightInc", "Dropdown: Increase height", "Alt+Shift+Up",
        function () { resizeActive(0,  RESIZE_STEP); });
    registerShortcut("DropdownAny-ResizeHeightDec", "Dropdown: Decrease height", "Alt+Shift+Down",
        function () { resizeActive(0, -RESIZE_STEP); });
    registerShortcut("DropdownAny-ResizeWidthInc",  "Dropdown: Increase width",  "Alt+Shift+Right",
        function () { resizeActive( RESIZE_STEP, 0); });
    registerShortcut("DropdownAny-ResizeWidthDec",  "Dropdown: Decrease width",  "Alt+Shift+Left",
        function () { resizeActive(-RESIZE_STEP, 0); });

    console.log("[DropdownAny] loaded — " + registered + "/10 slots active.");
})();
