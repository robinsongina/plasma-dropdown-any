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

    // direction: "top" (default), "bottom", "left", "right", or "center" —
    // which screen edge a box of size w×h is anchored to within area. The
    // perpendicular axis is centered (e.g. "left" centers vertically; "top"
    // centers horizontally). "center" centers on both axes — no edge.
    // Shared by applyDropdownGeometry and applyTileGeometry.
    function anchoredPosition(area, w, h, direction) {
        switch (direction) {
            case "bottom":
                return { x: area.x + Math.round((area.width - w) / 2), y: area.y + area.height - h };
            case "left":
                return { x: area.x, y: area.y + Math.round((area.height - h) / 2) };
            case "right":
                return { x: area.x + area.width - w, y: area.y + Math.round((area.height - h) / 2) };
            case "center":
                return { x: area.x + Math.round((area.width - w) / 2), y: area.y + Math.round((area.height - h) / 2) };
            case "top":
            default:
                return { x: area.x + Math.round((area.width - w) / 2), y: area.y };
        }
    }

    function applyDropdownGeometry(win, widthPct, heightPct, screenTarget, direction) {
        var screen = resolveScreen(screenTarget);
        var area = workspace.clientArea(KWin.MaximizeArea, screen, workspace.currentDesktop);
        var w = Math.round(area.width  * widthPct);
        var h = Math.round(area.height * heightPct);
        var pos = anchoredPosition(area, w, h, direction);
        win.frameGeometry = { x: pos.x, y: pos.y, width: w, height: h };
    }

    // Positions two windows as a tile pair inside a widthPct×heightPct box
    // anchored per direction (same rule as applyDropdownGeometry). orientation
    // "horizontal" (default) splits that box's width — winLeft | winRight,
    // left-to-right. orientation "vertical" splits its height instead —
    // winLeft on top, winRight on bottom. Either way splitPct is winLeft's
    // share, and if only one of the two is present it takes the full box
    // instead — the other slot just isn't there yet, not an error.
    function applyTileGeometry(winLeft, winRight, splitPct, widthPct, heightPct, screenTarget, direction, orientation) {
        var screen = resolveScreen(screenTarget);
        var area = workspace.clientArea(KWin.MaximizeArea, screen, workspace.currentDesktop);
        var w = Math.round(area.width  * widthPct);
        var h = Math.round(area.height * heightPct);
        var pos = anchoredPosition(area, w, h, direction);
        var x = pos.x, y = pos.y;

        if (orientation === "vertical") {
            var topH = Math.round(h * splitPct);
            var botH = h - topH;
            if (winLeft && winRight) {
                winLeft.frameGeometry  = { x: x, y: y,        width: w, height: topH };
                winRight.frameGeometry = { x: x, y: y + topH, width: w, height: botH };
            } else if (winLeft) {
                winLeft.frameGeometry = { x: x, y: y, width: w, height: h };
            } else if (winRight) {
                winRight.frameGeometry = { x: x, y: y, width: w, height: h };
            }
            return;
        }

        if (winLeft && winRight) {
            var leftW  = Math.round(w * splitPct);
            var rightW = w - leftW;
            winLeft.frameGeometry  = { x: x,         y: y, width: leftW,  height: h };
            winRight.frameGeometry = { x: x + leftW, y: y, width: rightW, height: h };
        } else if (winLeft) {
            winLeft.frameGeometry = { x: x, y: y, width: w, height: h };
        } else if (winRight) {
            winRight.frameGeometry = { x: x, y: y, width: w, height: h };
        }
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

    // Always-visible OSD, independent of debugMode — used for temp slot
    // bind/release events specifically (not regular toggles, which stay
    // debug-only via dbg() above).
    function osdNotify(icon, msg) {
        console.log("[DropdownAny] " + msg);
        callDBus(
            "org.kde.plasmashell",
            "/org/kde/osdService",
            "org.kde.osdService",
            "showText",
            icon,
            msg
        );
    }

    // ── Hidden-windows tracker ────────────────────────────────────────────────
    //
    // Stores the on-screen geometry for each window we've moved off-screen.
    // Key: windowClass string  Value: { x, y, width, height, savedOpacity }
    //
    var hiddenWindows = {}; // windowClass → { x, y, width, height, savedOpacity }

    // Marks a tile pair as currently off-screen. Key: tile pair id (string
    // "1".."10"). Just a boolean marker — unlike hiddenWindows, no geometry
    // is restored on show (tile geometry is always recomputed from the split
    // config, same as single-slot dropdowns already do on show).
    var hiddenTiles = {}; // pairId → true

    // Last slot/tile toggled via its own dedicated shortcut — lets the
    // "repeat last" shortcut re-trigger it without knowing which one it was.
    var lastActivated = null; // { type: "slot", id: windowClass } | { type: "tile", id: pairId }

    // ── Slot config (mutable) ─────────────────────────────────────────────────
    //
    // Populated during shortcut registration. Keeps live widthPct/heightPct so
    // the resize shortcuts can update them and have toggleWindow pick up the new
    // values immediately (without waiting for a script reload).
    //
    // Keyed by "trackingKey": for a normal slot this IS the window class; for
    // a temporary slot (temporary: true, no configured class) it's a stable
    // synthetic "temp:<idx>" key instead, since the real class isn't known
    // until the user triggers it while some window is focused (see
    // toggleWindow). boundClass holds that captured class, or null.
    var slotConfig = {}; // trackingKey → { idx, widthPct, heightPct, screenTarget, opacity, allDesktops, autoHide, keepAbove, temporary?, boundClass? }

    // Resolves a trackingKey to the actual window class to search for.
    // Regular slots: trackingKey already IS the class. Temp slots: the class
    // is whatever got bound at first trigger (or null if never triggered).
    function resolveClass(trackingKey) {
        var slot = slotConfig[trackingKey];
        if (slot && slot.temporary) return slot.boundClass;
        return trackingKey;
    }

    // ── Tile pair config (mutable) ────────────────────────────────────────────
    //
    // Populated during shortcut registration, same pattern as slotConfig.
    var tileConfig = {}; // pairId → { idx, classLeft, classRight, splitPct, heightPct, screenTarget, opacity, allDesktops, autoHide, direction }

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

    function hideWindow(trackingKey) {
        var cls = resolveClass(trackingKey);
        if (!cls) return; // temp slot, never bound — nothing to hide
        var win = findByClass(cls);
        if (!win) return;
        // Guard: already off-screen — don't re-hide / re-snapshot.
        if (hiddenWindows[trackingKey] !== undefined) return;

        var slot      = slotConfig[trackingKey];
        var direction = (slot && slot.direction) || "top";

        var g = win.frameGeometry;
        hiddenWindows[trackingKey] = {
            x: g.x, y: g.y, width: g.width, height: g.height,
            savedOpacity: win.opacity
        };

        win.skipTaskbar  = true;
        win.skipPager    = true;
        win.skipSwitcher = true;

        // Restore user's original opacity BEFORE sliding out so the next show
        // re-snapshots a clean value and we never lose the original.
        win.opacity = hiddenWindows[trackingKey].savedOpacity;

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
            case "center": // no dedicated edge — reuse top's push
            default:       offY = bounds.y - g.height;      break;
        }

        win.frameGeometry = { x: offX, y: offY, width: g.width, height: g.height };

        dbg("auto/shortcut hide → " + cls + "\nAction: hidden (slide-out, " + direction + ")");
    }

    // Hides both windows of a tile pair together, same direction, same
    // off-screen-push logic as hideWindow (past the full screen union).
    function hideTile(pairId) {
        if (hiddenTiles[pairId] !== undefined) return;
        var tile = tileConfig[pairId];
        if (!tile) return;
        var direction = tile.direction || "top";

        var winLeft  = tile.classLeft  ? findByClass(tile.classLeft)  : null;
        var winRight = tile.classRight ? findByClass(tile.classRight) : null;
        if (!winLeft && !winRight) return;

        hiddenTiles[pairId] = true;

        var bounds = virtualScreenBounds();
        [winLeft, winRight].forEach(function (win) {
            if (!win) return;
            win.skipTaskbar  = true;
            win.skipPager    = true;
            win.skipSwitcher = true;

            var g = win.frameGeometry;
            var offX = g.x, offY = g.y;
            switch (direction) {
                case "bottom": offY = bounds.y + bounds.height; break;
                case "left":   offX = bounds.x - g.width;       break;
                case "right":  offX = bounds.x + bounds.width;  break;
                case "top":
                default:       offY = bounds.y - g.height;      break;
            }
            win.frameGeometry = { x: offX, y: offY, width: g.width, height: g.height };
        });

        dbg("auto/shortcut hide → tile " + pairId + "\nAction: hidden (slide-out, " + direction + ")");
    }

    // ── Toggle ────────────────────────────────────────────────────────────────
    function toggleWindow(trackingKey, shortcut) {
        var slot = slotConfig[trackingKey];
        if (!slot) return;

        // Temp slot not yet bound: capture the focused window's class now,
        // then fall straight through — since that window is focused, the
        // "hide" branch below fires immediately (bind + hide in one press).
        if (slot.temporary && !slot.boundClass) {
            var activeWin = workspace.activeWindow;
            if (!activeWin) {
                dbg(shortcut + " → temp slot " + slot.idx + "\nNo focused window to bind");
                return;
            }
            slot.boundClass = activeWin.resourceClass;
            osdNotify("emblem-pin", "Temp slot " + slot.idx + " bound to " + slot.boundClass);
        }

        var cls = resolveClass(trackingKey);
        var win = findByClass(cls);
        if (!win) {
            dbg(shortcut + " → " + cls + "\nWindow not found");
            return;
        }

        lastActivated = { type: "slot", id: trackingKey };

        var isHidden    = hiddenWindows[trackingKey] !== undefined;
        var isMinimized = win.minimized;

        // ── Hide ──────────────────────────────────────────────────────────────
        // Window is visible (not in our off-screen tracker, not minimized) and focused.
        if (!isHidden && !isMinimized && win.active) {
            hideWindow(trackingKey);
            return;
        }

        // ── Show ──────────────────────────────────────────────────────────────

        // Hide from taskbar/pager/switcher while we reposition it — always,
        // regardless of keepAbove. keepAbove itself is per-slot: if on, the
        // window stays pinned above everything even after losing focus to
        // another app (unless autoHide hides it entirely first); if off, it
        // behaves like a normal window and falls behind whatever gets
        // focused next — workspace.activeWindow below still raises it once
        // now, for this show.
        win.keepAbove    = slot.keepAbove;
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
            delete hiddenWindows[trackingKey];
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

        dbg(shortcut + " → " + cls + " [" + (win.caption || "") + "]\nAction: shown (slide-in)");
    }

    // ── Release a temp slot's binding ────────────────────────────────────────
    //
    // Lets the user free a temporary slot on demand — without closing the
    // app — so a different app can bind to it next. If the window is
    // currently parked off-screen (hidden by us), restore it to its
    // original position first so it isn't left stranded; otherwise leave
    // it exactly where it is. Either way, the slot forgets its binding.
    function releaseTempSlot(trackingKey, shortcut) {
        var slot = slotConfig[trackingKey];
        if (!slot || !slot.temporary) return;
        if (!slot.boundClass) {
            dbg(shortcut + " → temp slot " + slot.idx + "\nAlready empty");
            return;
        }

        var releasedClass = slot.boundClass;
        var win = findByClass(releasedClass);

        if (win && hiddenWindows[trackingKey] !== undefined) {
            var saved = hiddenWindows[trackingKey];
            win.frameGeometry = { x: saved.x, y: saved.y, width: saved.width, height: saved.height };
            win.opacity = saved.savedOpacity;
        }
        if (win) {
            win.keepAbove    = false;
            win.skipTaskbar  = false;
            win.skipPager    = false;
            win.skipSwitcher = false;
        }

        delete hiddenWindows[trackingKey];
        slot.boundClass = null;

        osdNotify("edit-clear", "Temp slot " + slot.idx + " released (" + releasedClass + ")");
    }

    // ── Tile toggle ───────────────────────────────────────────────────────────
    function toggleTile(pairId, shortcut) {
        var tile = tileConfig[pairId];
        if (!tile) return;

        var winLeft  = tile.classLeft  ? findByClass(tile.classLeft)  : null;
        var winRight = tile.classRight ? findByClass(tile.classRight) : null;

        if (!winLeft && !winRight) {
            dbg(shortcut + " → tile " + pairId + "\nNeither window found");
            return;
        }

        lastActivated = { type: "tile", id: pairId };

        var isHidden  = hiddenTiles[pairId] !== undefined;
        var anyActive = (winLeft && winLeft.active) || (winRight && winRight.active);

        // ── Hide ──────────────────────────────────────────────────────────────
        if (!isHidden && anyActive) {
            hideTile(pairId);
            return;
        }

        // ── Show ──────────────────────────────────────────────────────────────
        if (isHidden) delete hiddenTiles[pairId];

        [winLeft, winRight].forEach(function (win) {
            if (!win) return;
            win.keepAbove    = true;
            win.skipTaskbar  = true;
            win.skipPager    = true;
            win.skipSwitcher = true;
            if (win.minimized) win.minimized = false;
        });

        applyTileGeometry(winLeft, winRight, tile.splitPct, tile.widthPct, tile.heightPct, tile.screenTarget, tile.direction, tile.orientation);

        [winLeft, winRight].forEach(function (win) {
            if (!win) return;
            win.onAllDesktops = tile.allDesktops;
            win.opacity       = tile.opacity / 100.0;
            win.skipTaskbar   = false;
            win.skipPager     = false;
            win.skipSwitcher  = false;
        });

        workspace.activeWindow = winLeft || winRight;

        dbg(shortcut + " → tile " + pairId +
            " [" + (tile.classLeft || "—") + " | " + (tile.classRight || "—") + "]" +
            "\nAction: shown (slide-in)");
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
            var candidateCls = resolveClass(wc);
            if (candidateCls && candidateCls.toLowerCase() === lc) {
                slot = slotConfig[wc]; matchedClass = candidateCls; break;
            }
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
    var hasTempSlots = false;
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
        var temp  = readConfig("temporary"     + i, false);
        var kAbove = readConfig("keepAbove"    + i, true);

        if (sc === "") continue;               // no shortcut → unusable regardless
        if (cls === "" && !temp) continue;     // empty class only valid for temp slots

        var entry = {
            idx: i, shortcut: sc, widthPct: wPct, heightPct: hPct, screenTarget: sPct,
            opacity: opc, allDesktops: allD, autoHide: aHide, direction: dir,
            keepAbove: kAbove
        };

        // ── Temporary slot: no fixed class — binds to whatever window is
        // focused the first time its shortcut is pressed (see toggleWindow),
        // and un-binds itself once that window closes (see windowRemoved
        // listener below), ready to bind to a different app next time.
        if (temp) {
            entry.temporary  = true;
            entry.boundClass = null;
            hasTempSlots = true;

            var tempKey = "temp:" + i;
            slotConfig[tempKey] = entry;

            (function (tempKey, shortcut, idx) {
                registerShortcut(
                    "DropdownAny-Temp" + idx,
                    "Dropdown temp slot " + idx + " (binds to focused app)",
                    shortcut,
                    function () { toggleWindow(tempKey, shortcut); }
                );

                if (entry.autoHide === true) {
                    workspace.windowActivated.connect(function (activeWin) {
                        var s = slotConfig[tempKey];
                        if (!s.boundClass) return; // not bound yet — nothing to hide
                        if (hiddenWindows[tempKey] !== undefined) return;
                        var win = findByClass(s.boundClass);
                        if (!win) return;
                        if (activeWin === win) return;
                        hideWindow(tempKey);
                    });
                }
            })(tempKey, sc, i);

            registered++;
            continue;
        }

        slotConfig[cls] = entry;

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

    // Free a temp slot's binding once its bound app has no windows left open,
    // so the slot goes back to "empty" and can bind to a different app next.
    if (hasTempSlots) {
        workspace.windowRemoved.connect(function (removedWindow) {
            var removedClass = removedWindow.resourceClass;
            if (!removedClass) return;
            for (var key in slotConfig) {
                var slot = slotConfig[key];
                if (!slot.temporary || !slot.boundClass) continue;
                if (slot.boundClass !== removedClass) continue;
                if (findByClass(slot.boundClass)) continue; // another window of that class remains open
                delete hiddenWindows[key];
                dbg("temp slot " + slot.idx + " → " + slot.boundClass + " closed, slot freed");
                slot.boundClass = null;
            }
        });
    }

    // ── Tile pair registration ────────────────────────────────────────────────
    var tilesRegistered = 0;
    for (var t = 1; t <= 10; t++) {
        var tClsL  = readConfig("tileClassLeft"    + t, "").trim();
        var tClsR  = readConfig("tileClassRight"   + t, "").trim();
        var tSc    = readConfig("tileShortcut"     + t, "").trim();
        var tSplit = readConfig("tileSplitPercent" + t, 50)  / 100.0;
        var tWPct  = readConfig("tileWidthPercent" + t, 100) / 100.0;
        var tHPct  = readConfig("tileHeightPercent" + t, 100) / 100.0;
        var tSPct  = readConfig("tileScreenTarget" + t, 0);
        var tOpc   = readConfig("tileOpacity"      + t, 100);
        var tAllD  = readConfig("tileAllDesktops"  + t, false);
        var tAHide = readConfig("tileAutoHide"     + t, false);
        var tDir   = readConfig("tileDirection"    + t, "top").trim() || "top";
        var tOrient = readConfig("tileOrientation" + t, "horizontal").trim() || "horizontal";
        // A tile pair needs at least one class configured, plus a shortcut.
        if ((tClsL === "" && tClsR === "") || tSc === "") continue;

        var pairId = String(t);
        tileConfig[pairId] = {
            idx: t, shortcut: tSc, classLeft: tClsL, classRight: tClsR,
            splitPct: tSplit, widthPct: tWPct, heightPct: tHPct, screenTarget: tSPct,
            opacity: tOpc, allDesktops: tAllD, autoHide: tAHide,
            direction: tDir, orientation: tOrient
        };

        (function (id, shortcut, classLeft, classRight) {
            registerShortcut(
                "DropdownTile-" + id,
                "Dropdown tile: " + (classLeft || "—") + " | " + (classRight || "—"),
                shortcut,
                function () { toggleTile(id, shortcut); }
            );

            if (tileConfig[id].autoHide === true) {
                workspace.windowActivated.connect(function (activeWin) {
                    if (hiddenTiles[id] !== undefined) return;
                    var wL = classLeft  ? findByClass(classLeft)  : null;
                    var wR = classRight ? findByClass(classRight) : null;
                    // We are (one of) the newly-active window(s) — don't self-hide.
                    if (activeWin === wL || activeWin === wR) return;
                    hideTile(id);
                });
            }
        })(pairId, tSc, tClsL, tClsR);

        tilesRegistered++;
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

    // ── Repeat last activated ─────────────────────────────────────────────────
    //
    // Re-triggers whichever slot or tile pair was last toggled via its own
    // dedicated shortcut (lastActivated is set inside toggleWindow/toggleTile).
    // No-op until at least one slot/tile has been toggled once.
    function toggleLastActivated() {
        if (!lastActivated) {
            dbg("Repeat last → nothing activated yet");
            return;
        }
        if (lastActivated.type === "slot") {
            toggleWindow(lastActivated.id, "Repeat last");
        } else if (lastActivated.type === "tile") {
            toggleTile(lastActivated.id, "Repeat last");
        }
    }

    var repeatLastSc = readConfig("repeatLastShortcut", "Meta+Shift+R").trim() || "Meta+Shift+R";
    registerShortcut(
        "DropdownAny-ToggleLast",
        "Dropdown Any: Toggle last activated slot/tile",
        repeatLastSc,
        toggleLastActivated
    );

    // ── Release active temp slot ─────────────────────────────────────────────
    //
    // One global shortcut instead of one per temp slot — releases whichever
    // bound temp slot's window is currently focused. Deliberately strict:
    // with several temp slots bound at once, a fuzzy "last touched" fallback
    // would be ambiguous (releasing whichever you interacted with most
    // recently, not necessarily the one you meant). Show the one you want
    // released first (its own toggle shortcut), then press this — same as
    // any other action that targets "the active dropdown".
    function releaseActiveTempSlot(shortcut) {
        var win = workspace.activeWindow;
        if (win) {
            var lc = win.resourceClass.toLowerCase();
            for (var key in slotConfig) {
                var slot = slotConfig[key];
                if (!slot.temporary || !slot.boundClass) continue;
                if (slot.boundClass.toLowerCase() === lc) {
                    releaseTempSlot(key, shortcut);
                    return;
                }
            }
        }

        dbg(shortcut + " → Release temp slot\nNo bound temp slot found (focused window isn't one, and none was recently toggled)");
    }

    var releaseTempSc = readConfig("releaseTempSlotShortcut", "Meta+Shift+X").trim() || "Meta+Shift+X";
    registerShortcut(
        "DropdownAny-ReleaseTempSlot",
        "Dropdown Any: Release active temp slot",
        releaseTempSc,
        function () { releaseActiveTempSlot("Release temp slot"); }
    );

    // ── Resize shortcuts ──────────────────────────────────────────────────────
    var resizeHeightIncSc = readConfig("resizeHeightIncShortcut", "Alt+Shift+Up").trim() || "Alt+Shift+Up";
    var resizeHeightDecSc = readConfig("resizeHeightDecShortcut", "Alt+Shift+Down").trim() || "Alt+Shift+Down";
    var resizeWidthIncSc  = readConfig("resizeWidthIncShortcut", "Alt+Shift+Right").trim() || "Alt+Shift+Right";
    var resizeWidthDecSc  = readConfig("resizeWidthDecShortcut", "Alt+Shift+Left").trim() || "Alt+Shift+Left";
    registerShortcut("DropdownAny-ResizeHeightInc", "Dropdown: Increase height", resizeHeightIncSc,
        function () { resizeActive(0,  RESIZE_STEP); });
    registerShortcut("DropdownAny-ResizeHeightDec", "Dropdown: Decrease height", resizeHeightDecSc,
        function () { resizeActive(0, -RESIZE_STEP); });
    registerShortcut("DropdownAny-ResizeWidthInc",  "Dropdown: Increase width",  resizeWidthIncSc,
        function () { resizeActive( RESIZE_STEP, 0); });
    registerShortcut("DropdownAny-ResizeWidthDec",  "Dropdown: Decrease width",  resizeWidthDecSc,
        function () { resizeActive(-RESIZE_STEP, 0); });

    // ── Shortcuts cheat sheet ─────────────────────────────────────────────────
    //
    // OSD listing every configured slot/tile with its shortcut, plus the
    // fixed global shortcuts — a quick reference without opening the widget.
    function listConfiguredShortcuts() {
        var lines = [];

        var slotIdxs = [];
        for (var key in slotConfig) slotIdxs.push(key);
        slotIdxs.sort(function (a, b) { return slotConfig[a].idx - slotConfig[b].idx; });
        slotIdxs.forEach(function (key) {
            var slot = slotConfig[key];
            var label = slot.temporary ? "(temporary)" : key;
            lines.push("Slot " + slot.idx + ": " + label + " → " + slot.shortcut);
        });

        var tileIds = Object.keys(tileConfig).sort(function (a, b) {
            return tileConfig[a].idx - tileConfig[b].idx;
        });
        tileIds.forEach(function (id) {
            var tile = tileConfig[id];
            lines.push("Tile " + tile.idx + ": " +
                (tile.classLeft || "—") + " | " + (tile.classRight || "—") +
                " → " + tile.shortcut);
        });

        lines.push("—");
        lines.push("List active windows → Meta+Shift+W");
        lines.push("Repeat last activated → " + repeatLastSc);
        lines.push("Release active temp slot → " + releaseTempSc);
        lines.push("Increase height → " + resizeHeightIncSc);
        lines.push("Decrease height → " + resizeHeightDecSc);
        lines.push("Increase width → " + resizeWidthIncSc);
        lines.push("Decrease width → " + resizeWidthDecSc);

        callDBus(
            "org.kde.plasmashell",
            "/org/kde/osdService",
            "org.kde.osdService",
            "showText",
            "preferences-desktop-keyboard-shortcuts",
            lines.join("\n")
        );
    }

    registerShortcut(
        "DropdownAny-ListShortcuts",
        "Dropdown Any: List configured slots/tiles and global shortcuts",
        readConfig("listShortcutsShortcut", "Meta+Shift+S").trim() || "Meta+Shift+S",
        listConfiguredShortcuts
    );

    console.log("[DropdownAny] loaded — " + registered + "/10 slots, " +
                tilesRegistered + "/10 tile pairs active.");
})();
