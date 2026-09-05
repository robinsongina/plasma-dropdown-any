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

(() => {
    // ── Window lookup ─────────────────────────────────────────────────────────
    function getWindows() {
        if (typeof workspace.windowList === "function")
            return workspace.windowList();
        if (typeof workspace.clientList === "function")
            return workspace.clientList();
        return [];
    }

    function findByClass(cls) {
        var lc = cls.toLowerCase();
        var wins = getWindows();
        for (var i = 0; i < wins.length; i++) {
            var w = wins[i];
            if (
                w.resourceClass.toLowerCase() === lc ||
                w.resourceName.toLowerCase() === lc
            ) {
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
            return (
                workspace.screenAt(workspace.cursorPos) ||
                workspace.activeScreen
            );
        }
        var idx = screenTarget - 1;
        if (idx >= 0 && idx < workspace.screens.length)
            return workspace.screens[idx];
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
                return {
                    x: area.x + Math.round((area.width - w) / 2),
                    y: area.y + area.height - h,
                };
            case "left":
                return {
                    x: area.x,
                    y: area.y + Math.round((area.height - h) / 2),
                };
            case "right":
                return {
                    x: area.x + area.width - w,
                    y: area.y + Math.round((area.height - h) / 2),
                };
            case "center":
                return {
                    x: area.x + Math.round((area.width - w) / 2),
                    y: area.y + Math.round((area.height - h) / 2),
                };
            case "top":
            default:
                return {
                    x: area.x + Math.round((area.width - w) / 2),
                    y: area.y,
                };
        }
    }

    function applyDropdownGeometry(
        win,
        widthPct,
        heightPct,
        screenTarget,
        direction,
    ) {
        var screen = resolveScreen(screenTarget);
        var area = workspace.clientArea(
            KWin.MaximizeArea,
            screen,
            workspace.currentDesktop,
        );
        var w = Math.round(area.width * widthPct);
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
    function applyTileGeometry(
        winLeft,
        winRight,
        splitPct,
        widthPct,
        heightPct,
        screenTarget,
        direction,
        orientation,
    ) {
        var screen = resolveScreen(screenTarget);
        var area = workspace.clientArea(
            KWin.MaximizeArea,
            screen,
            workspace.currentDesktop,
        );
        var w = Math.round(area.width * widthPct);
        var h = Math.round(area.height * heightPct);
        var pos = anchoredPosition(area, w, h, direction);
        var x = pos.x,
            y = pos.y;

        if (orientation === "vertical") {
            var topH = Math.round(h * splitPct);
            var botH = h - topH;
            if (winLeft && winRight) {
                winLeft.frameGeometry = { x: x, y: y, width: w, height: topH };
                winRight.frameGeometry = {
                    x: x,
                    y: y + topH,
                    width: w,
                    height: botH,
                };
            } else if (winLeft) {
                winLeft.frameGeometry = { x: x, y: y, width: w, height: h };
            } else if (winRight) {
                winRight.frameGeometry = { x: x, y: y, width: w, height: h };
            }
            return;
        }

        if (winLeft && winRight) {
            var leftW = Math.round(w * splitPct);
            var rightW = w - leftW;
            winLeft.frameGeometry = { x: x, y: y, width: leftW, height: h };
            winRight.frameGeometry = {
                x: x + leftW,
                y: y,
                width: rightW,
                height: h,
            };
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
            "[DropdownAny]\n" + msg,
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
            msg,
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
        var minX = Infinity,
            minY = Infinity,
            maxX = -Infinity,
            maxY = -Infinity;
        for (var i = 0; i < screens.length; i++) {
            var g = screens[i].geometry;
            if (g.x < minX) minX = g.x;
            if (g.y < minY) minY = g.y;
            if (g.x + g.width > maxX) maxX = g.x + g.width;
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

        var slot = slotConfig[trackingKey];
        var direction = (slot && slot.direction) || "top";

        var g = win.frameGeometry;
        hiddenWindows[trackingKey] = {
            x: g.x,
            y: g.y,
            width: g.width,
            height: g.height,
            savedOpacity: win.opacity,
        };

        win.skipTaskbar = true;
        win.skipPager = true;
        win.skipSwitcher = true;

        // Restore user's original opacity BEFORE sliding out so the next show
        // re-snapshots a clean value and we never lose the original.
        win.opacity = hiddenWindows[trackingKey].savedOpacity;

        // Push the window a full window-dimension past the outer edge of ALL
        // screens combined, so the GeometryChange effect can animate the
        // slide back out that way without landing on another monitor or a panel.
        var bounds = virtualScreenBounds();
        var offX = g.x,
            offY = g.y;
        switch (direction) {
            case "bottom":
                offY = bounds.y + bounds.height;
                break;
            case "left":
                offX = bounds.x - g.width;
                break;
            case "right":
                offX = bounds.x + bounds.width;
                break;
            case "top":
            case "center": // no dedicated edge — reuse top's push
            default:
                offY = bounds.y - g.height;
                break;
        }

        win.frameGeometry = {
            x: offX,
            y: offY,
            width: g.width,
            height: g.height,
        };

        dbg(
            "auto/shortcut hide → " +
                cls +
                "\nAction: hidden (slide-out, " +
                direction +
                ")",
        );
    }

    // Hides both windows of a tile pair together, same direction, same
    // off-screen-push logic as hideWindow (past the full screen union).
    function hideTile(pairId) {
        if (hiddenTiles[pairId] !== undefined) return;
        var tile = tileConfig[pairId];
        if (!tile) return;
        var direction = tile.direction || "top";

        var winLeft = tile.classLeft ? findByClass(tile.classLeft) : null;
        var winRight = tile.classRight ? findByClass(tile.classRight) : null;
        if (!winLeft && !winRight) return;

        hiddenTiles[pairId] = true;

        var bounds = virtualScreenBounds();
        [winLeft, winRight].forEach((win) => {
            if (!win) return;
            win.skipTaskbar = true;
            win.skipPager = true;
            win.skipSwitcher = true;

            var g = win.frameGeometry;
            var offX = g.x,
                offY = g.y;
            switch (direction) {
                case "bottom":
                    offY = bounds.y + bounds.height;
                    break;
                case "left":
                    offX = bounds.x - g.width;
                    break;
                case "right":
                    offX = bounds.x + bounds.width;
                    break;
                case "top":
                default:
                    offY = bounds.y - g.height;
                    break;
            }
            win.frameGeometry = {
                x: offX,
                y: offY,
                width: g.width,
                height: g.height,
            };
        });

        dbg(
            "auto/shortcut hide → tile " +
                pairId +
                "\nAction: hidden (slide-out, " +
                direction +
                ")",
        );
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
                dbg(
                    shortcut +
                        " → temp slot " +
                        slot.idx +
                        "\nNo focused window to bind",
                );
                return;
            }
            slot.boundClass = activeWin.resourceClass;
            osdNotify(
                "emblem-pin",
                "Temp slot " + slot.idx + " bound to " + slot.boundClass,
            );
        }

        var cls = resolveClass(trackingKey);
        var win = findByClass(cls);
        if (!win) {
            dbg(shortcut + " → " + cls + "\nWindow not found");
            return;
        }

        lastActivated = { type: "slot", id: trackingKey };

        // Precedence gate (dockit B4): dock owns docked windows — slot
        // toggles skip them. Dock re-docks on blur; release-all hands the
        // window back to the slot machinery (design §6.2).
        if (isDockedClass(cls)) {
            dbg(
                shortcut +
                    " → " +
                    cls +
                    "\nDocked window — slot toggle skipped (dock owns it)",
            );
            return;
        }

        var isHidden = hiddenWindows[trackingKey] !== undefined;
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
        win.keepAbove = slot.keepAbove;
        win.skipTaskbar = true;
        win.skipPager = true;
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
        applyDropdownGeometry(
            win,
            slot.widthPct,
            slot.heightPct,
            slot.screenTarget,
            slot.direction,
        );

        win.onAllDesktops = slot.allDesktops;
        win.opacity = slot.opacity / 100.0;

        // Restore taskbar/pager/switcher visibility now that the window is on-screen.
        win.skipTaskbar = false;
        win.skipPager = false;
        win.skipSwitcher = false;

        workspace.activeWindow = win;

        dbg(
            shortcut +
                " → " +
                cls +
                " [" +
                (win.caption || "") +
                "]\nAction: shown (slide-in)",
        );
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
            win.frameGeometry = {
                x: saved.x,
                y: saved.y,
                width: saved.width,
                height: saved.height,
            };
            win.opacity = saved.savedOpacity;
        }
        if (win) {
            win.keepAbove = false;
            win.skipTaskbar = false;
            win.skipPager = false;
            win.skipSwitcher = false;
        }

        delete hiddenWindows[trackingKey];
        slot.boundClass = null;

        osdNotify(
            "edit-clear",
            "Temp slot " + slot.idx + " released (" + releasedClass + ")",
        );
    }

    // ── Tile toggle ───────────────────────────────────────────────────────────
    function toggleTile(pairId, shortcut) {
        var tile = tileConfig[pairId];
        if (!tile) return;

        var winLeft = tile.classLeft ? findByClass(tile.classLeft) : null;
        var winRight = tile.classRight ? findByClass(tile.classRight) : null;

        if (!winLeft && !winRight) {
            dbg(shortcut + " → tile " + pairId + "\nNeither window found");
            return;
        }

        lastActivated = { type: "tile", id: pairId };

        // Precedence gate (dockit B4): a docked window in the pair means the
        // tile toggle must not touch either half (design §6.2).
        if (isDockedClass(tile.classLeft) || isDockedClass(tile.classRight)) {
            dbg(
                shortcut +
                    " → tile " +
                    pairId +
                    "\nDocked window in pair — tile toggle skipped (dock owns it)",
            );
            return;
        }

        var isHidden = hiddenTiles[pairId] !== undefined;
        var anyActive =
            (winLeft && winLeft.active) || (winRight && winRight.active);

        // ── Hide ──────────────────────────────────────────────────────────────
        if (!isHidden && anyActive) {
            hideTile(pairId);
            return;
        }

        // ── Show ──────────────────────────────────────────────────────────────
        if (isHidden) delete hiddenTiles[pairId];

        [winLeft, winRight].forEach((win) => {
            if (!win) return;
            win.keepAbove = true;
            win.skipTaskbar = true;
            win.skipPager = true;
            win.skipSwitcher = true;
            if (win.minimized) win.minimized = false;
        });

        applyTileGeometry(
            winLeft,
            winRight,
            tile.splitPct,
            tile.widthPct,
            tile.heightPct,
            tile.screenTarget,
            tile.direction,
            tile.orientation,
        );

        [winLeft, winRight].forEach((win) => {
            if (!win) return;
            win.onAllDesktops = tile.allDesktops;
            win.opacity = tile.opacity / 100.0;
            win.skipTaskbar = false;
            win.skipPager = false;
            win.skipSwitcher = false;
        });

        workspace.activeWindow = winLeft || winRight;

        dbg(
            shortcut +
                " → tile " +
                pairId +
                " [" +
                (tile.classLeft || "—") +
                " | " +
                (tile.classRight || "—") +
                "]" +
                "\nAction: shown (slide-in)",
        );
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
        var lc = win.resourceClass.toLowerCase();
        var slot = null;
        var matchedClass = null;
        for (var wc in slotConfig) {
            var candidateCls = resolveClass(wc);
            if (candidateCls && candidateCls.toLowerCase() === lc) {
                slot = slotConfig[wc];
                matchedClass = candidateCls;
                break;
            }
        }
        if (!slot) return; // active window is not a managed dropdown

        slot.widthPct = Math.max(0.1, Math.min(1.0, slot.widthPct + dw));
        slot.heightPct = Math.max(0.1, Math.min(1.0, slot.heightPct + dh));

        applyDropdownGeometry(
            win,
            slot.widthPct,
            slot.heightPct,
            slot.screenTarget,
            slot.direction,
        );

        // Persist to kwinrc so the new values survive script reload.
        writeConfig("widthPercent" + slot.idx, Math.round(slot.widthPct * 100));
        writeConfig(
            "heightPercent" + slot.idx,
            Math.round(slot.heightPct * 100),
        );

        dbg(
            "Resize " +
                matchedClass +
                " → w:" +
                Math.round(slot.widthPct * 100) +
                "%" +
                " h:" +
                Math.round(slot.heightPct * 100) +
                "%",
        );
    }

    // ── Shortcut registration ─────────────────────────────────────────────────
    var registered = 0;
    var hasTempSlots = false;
    for (var i = 1; i <= 10; i++) {
        var cls = readConfig("windowClass" + i, "").trim();
        var sc = readConfig("shortcut" + i, "").trim();
        var wPct = readConfig("widthPercent" + i, 100) / 100.0;
        var hPct = readConfig("heightPercent" + i, 50) / 100.0;
        var sPct = readConfig("screenTarget" + i, 0);
        var opc = readConfig("opacity" + i, 100);
        var allD = readConfig("allDesktops" + i, false);
        var aHide = readConfig("autoHide" + i, false);
        var dir = readConfig("direction" + i, "top").trim() || "top";
        var temp = readConfig("temporary" + i, false);
        var kAbove = readConfig("keepAbove" + i, true);

        if (sc === "") continue; // no shortcut → unusable regardless
        if (cls === "" && !temp) continue; // empty class only valid for temp slots

        var entry = {
            idx: i,
            shortcut: sc,
            widthPct: wPct,
            heightPct: hPct,
            screenTarget: sPct,
            opacity: opc,
            allDesktops: allD,
            autoHide: aHide,
            direction: dir,
            keepAbove: kAbove,
        };

        // ── Temporary slot: no fixed class — binds to whatever window is
        // focused the first time its shortcut is pressed (see toggleWindow),
        // and un-binds itself once that window closes (see windowRemoved
        // listener below), ready to bind to a different app next time.
        if (temp) {
            entry.temporary = true;
            entry.boundClass = null;
            hasTempSlots = true;

            var tempKey = "temp:" + i;
            slotConfig[tempKey] = entry;

            ((tempKey, shortcut, idx) => {
                registerShortcut(
                    "DropdownAny-Temp" + idx,
                    "Dropdown temp slot " + idx + " (binds to focused app)",
                    shortcut,
                    () => {
                        toggleWindow(tempKey, shortcut);
                    },
                );

                if (entry.autoHide === true) {
                    workspace.windowActivated.connect((activeWin) => {
                        var s = slotConfig[tempKey];
                        if (!s.boundClass) return; // not bound yet — nothing to hide
                        if (hiddenWindows[tempKey] !== undefined) return;
                        var win = findByClass(s.boundClass);
                        if (!win) return;
                        // Precedence gate (dockit B4): docked windows are owned by
                        // the dock — autoHide must not park them (design §6.2).
                        if (isDockedClass(s.boundClass)) return;
                        if (activeWin === win) return;
                        hideWindow(tempKey);
                    });
                }
            })(tempKey, sc, i);

            registered++;
            continue;
        }

        slotConfig[cls] = entry;

        ((windowClass, shortcut) => {
            registerShortcut(
                "DropdownAny-" + windowClass,
                "Dropdown toggle: " + windowClass,
                shortcut,
                () => {
                    toggleWindow(windowClass, shortcut);
                },
            );

            if (slotConfig[windowClass].autoHide === true) {
                workspace.windowActivated.connect((activeWin) => {
                    // Already parked off-screen — don't re-hide.
                    if (hiddenWindows[windowClass] !== undefined) return;
                    var win = findByClass(windowClass);
                    if (!win) return;
                    // Precedence gate (dockit B4): docked windows are owned by
                    // the dock — autoHide must not park them (design §6.2).
                    if (isDockedClass(windowClass)) return;
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
        workspace.windowRemoved.connect((removedWindow) => {
            var removedClass = removedWindow.resourceClass;
            if (!removedClass) return;
            for (var key in slotConfig) {
                var slot = slotConfig[key];
                if (!slot.temporary || !slot.boundClass) continue;
                if (slot.boundClass !== removedClass) continue;
                if (findByClass(slot.boundClass)) continue; // another window of that class remains open
                delete hiddenWindows[key];
                dbg(
                    "temp slot " +
                        slot.idx +
                        " → " +
                        slot.boundClass +
                        " closed, slot freed",
                );
                slot.boundClass = null;
            }
        });
    }

    // ── Tile pair registration ────────────────────────────────────────────────
    var tilesRegistered = 0;
    for (var t = 1; t <= 10; t++) {
        var tClsL = readConfig("tileClassLeft" + t, "").trim();
        var tClsR = readConfig("tileClassRight" + t, "").trim();
        var tSc = readConfig("tileShortcut" + t, "").trim();
        var tSplit = readConfig("tileSplitPercent" + t, 50) / 100.0;
        var tWPct = readConfig("tileWidthPercent" + t, 100) / 100.0;
        var tHPct = readConfig("tileHeightPercent" + t, 100) / 100.0;
        var tSPct = readConfig("tileScreenTarget" + t, 0);
        var tOpc = readConfig("tileOpacity" + t, 100);
        var tAllD = readConfig("tileAllDesktops" + t, false);
        var tAHide = readConfig("tileAutoHide" + t, false);
        var tDir = readConfig("tileDirection" + t, "top").trim() || "top";
        var tOrient =
            readConfig("tileOrientation" + t, "horizontal").trim() ||
            "horizontal";
        // A tile pair needs at least one class configured, plus a shortcut.
        if ((tClsL === "" && tClsR === "") || tSc === "") continue;

        var pairId = String(t);
        tileConfig[pairId] = {
            idx: t,
            shortcut: tSc,
            classLeft: tClsL,
            classRight: tClsR,
            splitPct: tSplit,
            widthPct: tWPct,
            heightPct: tHPct,
            screenTarget: tSPct,
            opacity: tOpc,
            allDesktops: tAllD,
            autoHide: tAHide,
            direction: tDir,
            orientation: tOrient,
        };

        ((id, shortcut, classLeft, classRight) => {
            registerShortcut(
                "DropdownTile-" + id,
                "Dropdown tile: " +
                    (classLeft || "—") +
                    " | " +
                    (classRight || "—"),
                shortcut,
                () => {
                    toggleTile(id, shortcut);
                },
            );

            if (tileConfig[id].autoHide === true) {
                workspace.windowActivated.connect((activeWin) => {
                    if (hiddenTiles[id] !== undefined) return;
                    var wL = classLeft ? findByClass(classLeft) : null;
                    var wR = classRight ? findByClass(classRight) : null;
                    // Precedence gate (dockit B4): a docked window in the pair
                    // means autoHide must not park either half (design §6.2).
                    if (isDockedClass(classLeft) || isDockedClass(classRight))
                        return;
                    // We are (one of) the newly-active window(s) — don't self-hide.
                    if (activeWin === wL || activeWin === wR) return;
                    hideTile(id);
                });
            }
        })(pairId, tSc, tClsL, tClsR);

        tilesRegistered++;
    }

    // ── Dock state machine ───────────────────────────────────────────────────
    //
    // Standalone dock: parks the FOCUSED window against its own screen's left
    // or right edge (never the virtual multi-screen union), preserving size and
    // leaving a configurable dockOffsetPx "sliver" visible; clicking the sliver
    // expands to the pre-dock snapshot (ordinary activation), losing focus
    // re-docks; the release-all shortcut restores every snapshot. Tracked
    // separately from hide/temp/tile (spec: at most one state machine per
    // window; precedence via isDockedClass gates below).
    //
    // T0 spike notes (KWin 6.7.4 target — resolved at apply time):
    //  1. workspace.screensChanged — hedged: registered when present, else a
    //     lazy validation inside the windowActivated sweep (design §5.4). Live
    //     confirm deferred to the verify smoke (DBus loadScript probe was
    //     inert in the spike session; the fallback is load-bearing either way).
    //  2. Output identity: outputKey() prefers output.name, falls back to the
    //     geometry-rect string (T0 item 2).
    //  3. fullScreen spelling: checked as fullScreen OR fullscreen via
    //     isFullScreenWindow() (T0 item 3; KWin 6 Window uses fullScreen).
    //  4. skipSwitcher timing: the slide effect reads skipSwitcher at
    //     geometry-change-SIGNAL time (effect main.js onWindowFrameGeometry-
    //     Changed), so clearing it right after the move cannot cancel the
    //     pending animation — the exact schedule the show path (toggleWindow)
    //     already relies on in production (T0 item 4).
    //  5. KGlobalAccel collisions: Ctrl+Shift+Left/Right/H are unclaimed on the
    //     target install (~/.config/kglobalshortcutsrc only has
    //     Meta+Ctrl+Shift+Left/Right for desktop moves) — clean (T0 item 5;
    //     README conflict wording lands in PR3). A losing registration is
    //     non-fatal: the other dock shortcuts still work and the conflict is
    //     surfaced by System Settings → Shortcuts (spec error handling).
    //  6. Wayland activation: clicking the sliver fires windowActivated with
    //     activeWin === win for any class — same exposure as the three proven
    //     autoHide handlers (T0 item 6; re-checked in verify smoke V6/V15).
    //
    // Tracker: lowercased resourceClass → entry; one docked window per class
    // (spec business rule) — docking a second same-class window releases the
    // first. Runtime-only: KWin reload wipes the tracker; parked windows keep
    // geometry but are untracked (spec rule).
    //
    var dockedWindows = {}; // cls → { x,y,width,height, edge, offsetPx, expanded, screenName }

    // Global sliver width, read once at load (spec: offset applies on reload).
    function readDockOffset() {
        var raw = parseInt(readConfig("dockOffsetPx", 24), 10);
        if (isNaN(raw)) return 24; // missing / non-numeric → default 24 (spec)
        return raw < 1 ? 1 : raw; // below 1 → 1 so the sliver stays visible
    }
    var DOCK_OFFSET_PX = readDockOffset();

    // Shared predicate for the precedence gates (design §6.2) and the sweep.
    function isDockedClass(cls) {
        return !!(cls && dockedWindows[String(cls).toLowerCase()]);
    }

    // T0 item 3: KWin 6 Window exposes fullScreen; hedge both spellings.
    function isFullScreenWindow(win) {
        return !!(win && (win.fullScreen || win.fullscreen));
    }

    // Shell/panel classes never dock — same literal as config-helper.sh.
    var DOCK_SHELL_SKIP = {
        plasmashell: 1,
        systemsettings: 1,
        ksmserver: 1,
        plasmawindowed: 1,
    };

    // Precedence gate: plain, non-shell windows only. Tiled windows PASS —
    // they visually detile while the tiling state persists (documented).
    function dockable(win) {
        if (!win) return false;
        if (win.minimized || win.maximized || isFullScreenWindow(win))
            return false;
        return !DOCK_SHELL_SKIP[String(win.resourceClass || "").toLowerCase()];
    }

    // The window's own screen: center-of-frameGeometry containment over
    // workspace.screens[i].geometry, nearest-screen fallback, null → clean
    // abort. No Qt namespace, no QPoint construction (design §4.1).
    function dockScreenFor(win) {
        var g = win.frameGeometry;
        var cx = g.x + g.width / 2;
        var cy = g.y + g.height / 2;
        var screens = workspace.screens;
        var best = null,
            bestD = Infinity;
        for (var i = 0; i < screens.length; i++) {
            var sg = screens[i].geometry;
            if (
                cx >= sg.x &&
                cx < sg.x + sg.width &&
                cy >= sg.y &&
                cy < sg.y + sg.height
            ) {
                return screens[i];
            }
            var dx = cx - (sg.x + sg.width / 2);
            var dy = cy - (sg.y + sg.height / 2);
            var d = dx * dx + dy * dy;
            if (d < bestD) {
                bestD = d;
                best = screens[i];
            }
        }
        return best;
    }

    // Park position: only x changes — width/height/y preserved (design §4.2).
    // Left: window's right edge at screen.x + offset. Right: window's left
    // edge at screen.x + screen.width − offset. offsetPx = entry.offsetPx
    // captured at dock time ("same edge and offset" per re-dock, spec);
    // defaults to the load-time global for callers without an entry.
    function parkRectFor(win, screen, edge, offsetPx) {
        var offset = typeof offsetPx === "number" ? offsetPx : DOCK_OFFSET_PX;
        var g = win.frameGeometry;
        var x =
            edge === "right"
                ? screen.geometry.x + screen.geometry.width - offset
                : screen.geometry.x + offset - g.width;
        return { x: x, y: g.y, width: g.width, height: g.height };
    }

    // Sole geometry-mutation path for dock. Skip-flag schedule (design §7):
    // the effect gate reads skipSwitcher at geometry-change time (T0 item 4),
    // and the spec requires docked windows to STAY visible in taskbar/pager/
    // switcher in both parked and expanded states — so the flags are set only
    // for the instant of the move, never while idle.
    function moveDocked(win, rect) {
        win.skipTaskbar = true;
        win.skipPager = true;
        win.skipSwitcher = true;
        win.frameGeometry = {
            x: rect.x,
            y: rect.y,
            width: rect.width,
            height: rect.height,
        };
        // Keep skipSwitcher true until the effect has read it at
        // windowFrameGeometryChanged time. Clearing synchronously races
        // with the signal delivery and makes the fallback gate miss,
        // so the window pops instead of sliding from the edge.
        // Use an async DBus round-trip to clear after the effect handler.
        try {
            callDBus(
                "org.kde.KWin",
                "/KWin",
                "org.kde.KWin",
                "supportInformation",
                () => {
                    try {
                        win.skipTaskbar = false;
                        win.skipPager = false;
                        win.skipSwitcher = false;
                    } catch (_e) {
                        void _e;
                    }
                },
            );
        } catch (_e) {
            void _e;
            win.skipTaskbar = false;
            win.skipPager = false;
            win.skipSwitcher = false;
        }
    }

    // Screen identity key (T0 item 2): output.name when present, else the
    // geometry rect as a string (position changes then rotate the key).
    function outputKey(output) {
        if (!output) return "";
        if (output.name !== undefined && output.name !== "")
            return String(output.name);
        var g = output.geometry;
        if (g) return g.x + "," + g.y + "," + g.width + "," + g.height;
        return "";
    }

    // Guard for snapshot restore: only restore toward a snapshot whose center
    // still lies on a current screen — a monitor change can't strand the
    // window in dead coordinates (design §5.5, decision D5).
    function snapshotCenterOnAnyCurrentScreen(entry) {
        var cx = entry.x + entry.width / 2;
        var cy = entry.y + entry.height / 2;
        var screens = workspace.screens;
        for (var i = 0; i < screens.length; i++) {
            var g = screens[i].geometry;
            if (
                cx >= g.x &&
                cx < g.x + g.width &&
                cy >= g.y &&
                cy < g.y + g.height
            )
                return true;
        }
        return false;
    }

    // Single exit point for every dock entry removal (spec invariant: removed
    // exactly once). restore=true restores the immutable snapshot, but never
    // fights minimized/maximized/fullscreen and never restores into the void.
    function releaseDockEntry(cls, restore) {
        var entry = dockedWindows[cls];
        if (!entry) return;
        delete dockedWindows[cls];
        var win = findByClass(cls);
        if (!win) return;
        win.skipTaskbar = false; // hygiene: no skip flag survives untracked
        win.skipPager = false;
        win.skipSwitcher = false;
        if (!restore) return; // windowRemoved: delete only, never move a sibling
        if (win.minimized || win.maximized || isFullScreenWindow(win)) return;
        if (!snapshotCenterOnAnyCurrentScreen(entry)) return;
        moveDocked(win, {
            x: entry.x,
            y: entry.y,
            width: entry.width,
            height: entry.height,
        });
    }

    // Flip expanded BEFORE the move so a re-entrant signal can't double-expand
    // (design §5.2 no-oscillation rule). No workspace.activeWindow = win on
    // expand — the activation that fired the signal already happened (D8).
    function expandDocked(win, entry) {
        entry.expanded = true;
        // Expanded dock must sit flush against its dock edge (screen.x for left,
        // screen.x+width-win.width for right), preserving y/width/height from
        // the pre-dock snapshot. Snapshot is kept for releaseAll, not for expand.
        var scr = null;
        for (var i = 0; i < workspace.screens.length; i++) {
            if (outputKey(workspace.screens[i]) === entry.screenName) {
                scr = workspace.screens[i];
                break;
            }
        }
        if (!scr) scr = dockScreenFor(win);
        if (scr) {
            var x =
                entry.edge === "right"
                    ? scr.geometry.x + scr.geometry.width - entry.width
                    : scr.geometry.x;
            moveDocked(win, {
                x: x,
                y: entry.y,
                width: entry.width,
                height: entry.height,
            });
        } else {
            moveDocked(win, {
                x: entry.x,
                y: entry.y,
                width: entry.width,
                height: entry.height,
            });
        }
        dbg(
            "dock expand → " + win.resourceClass + " (" + entry.edge + " edge)",
        );
    }

    function redockDocked(win, entry) {
        entry.expanded = false;
        var scr = dockScreenFor(win);
        if (!scr) {
            // Screen vanished mid-flight — clean abort: no entry, no partial
            // geometry (spec error handling / design §5.2).
            releaseDockEntry(
                String(win.resourceClass || "").toLowerCase(),
                false,
            );
            return;
        }
        moveDocked(win, parkRectFor(win, scr, entry.edge, entry.offsetPx));
        dbg(
            "dock re-dock → " +
                win.resourceClass +
                " (" +
                entry.edge +
                ", " +
                entry.offsetPx +
                "px)",
        );
    }

    function dockWindow(edge) {
        var win = workspace.activeWindow;
        if (!win) return;
        var cls = String(win.resourceClass || "").toLowerCase();
        if (!cls) return;

        // 2. Already docked → re-dock to the requested edge, snapshot
        //    preserved. Runs BEFORE the dockable() gate so a tracked window
        //    whose state drifted still re-docks (design §5.1).
        if (dockedWindows[cls]) {
            var existing = dockedWindows[cls];
            existing.edge = edge;
            existing.expanded = false;
            var scr = dockScreenFor(win);
            if (scr)
                moveDocked(win, parkRectFor(win, scr, edge, existing.offsetPx));
            dbg("dock re-dock → " + cls + " (" + edge + ")");
            return;
        }

        // 3. Gate: only plain, non-shell windows (design §6.1). Tiled windows
        //    pass (visual detile, tiling state persists — documented).
        if (!dockable(win)) {
            dbg(
                "dock skip → " +
                    cls +
                    " (minimized/maximized/fullscreen/shell)",
            );
            return;
        }

        // 4. Class collision: release a previous entry of this class first
        //    (restore its snapshot). Unreachable after step 2's return except
        //    under re-entrancy; kept for the spec invariant.
        if (dockedWindows[cls]) releaseDockEntry(cls, true);

        // 5. Snapshot the immutable pre-dock geometry.
        var g = win.frameGeometry;

        // 6. Resolve the window's own screen; null → abort cleanly (no entry).
        var scr = dockScreenFor(win);
        if (!scr) {
            dbg("dock abort → " + cls + " (no current screen)");
            return;
        }

        // 7. Create entry (current edge, load-time offset, not expanded).
        var entry = {
            x: g.x,
            y: g.y,
            width: g.width,
            height: g.height,
            edge: edge,
            offsetPx: DOCK_OFFSET_PX,
            expanded: false,
            screenName: outputKey(scr),
        };
        dockedWindows[cls] = entry;

        // 8. Park against the chosen edge.
        moveDocked(win, parkRectFor(win, scr, edge, entry.offsetPx));
        dbg(
            "dock → " +
                cls +
                " (" +
                edge +
                ", " +
                entry.offsetPx +
                "px sliver)",
        );
    }

    // Idempotent release-all: restore every snapshot (parked or expanded),
    // clear the tracker; no-op when empty; OSD confirmation with the count
    // (design D12, mirrors the temp-slot release precedent).
    function releaseAllDocked() {
        var keys = Object.keys(dockedWindows);
        if (keys.length === 0) {
            dbg("release all → nothing docked");
            return;
        }
        keys.forEach((cls) => {
            releaseDockEntry(cls, true);
        });
        osdNotify(
            "edit-clear",
            "Released " +
                keys.length +
                " docked window" +
                (keys.length > 1 ? "s" : ""),
        );
    }

    // ── Dock handlers (B1–B3) ────────────────────────────────────────────────
    //
    // B1 — single windowActivated sweep. Expand only when parked + still plain;
    // re-dock (or release) every expanded entry that lost focus — including
    // activeWin === null (desktop). At most one transition per entry per
    // emission; flags flip synchronously before each move → no oscillation.
    workspace.windowActivated.connect((activeWin) => {
        Object.keys(dockedWindows).forEach((cls) => {
            var entry = dockedWindows[cls];
            var win = findByClass(cls);
            if (!win) return;
            if (win === activeWin) {
                // Sliver clicked (ordinary activation): expand when parked.
                if (
                    !entry.expanded &&
                    !win.minimized &&
                    !win.maximized &&
                    !isFullScreenWindow(win)
                ) {
                    expandDocked(win, entry);
                }
            } else if (entry.expanded) {
                // Focus went elsewhere: re-dock, or release without geometry
                // mutation if the window is no longer plain.
                if (win.minimized || win.maximized || isFullScreenWindow(win)) {
                    releaseDockEntry(cls, false);
                } else {
                    redockDocked(win, entry);
                }
            }
        });

        // B3 lazy fallback (T0 item 1): if screensChanged is unavailable,
        // validate stored screenName membership per activation event — same
        // semantics, slightly later cleanup (design §5.4).
        if (!dockScreensChangedAvailable) validateDockedScreens();
    });

    // B2 — window close: delete the entry only, never move a surviving
    // same-class sibling into a dead window's slot (design §5.3, decision D4).
    workspace.windowRemoved.connect((removedWindow) => {
        var cls = String(removedWindow.resourceClass || "").toLowerCase();
        if (!cls || !dockedWindows[cls]) return;
        releaseDockEntry(cls, false);
    });

    // B3 — monitor removal / resolution drift (design §5.4): stored screen
    // gone → guarded restore + release; screen still present but the parked
    // sliver invariant broke → re-park quietly; dockScreenFor null → restore
    // + release.
    var dockScreensChangedAvailable = !!(
        workspace.screensChanged && workspace.screensChanged.connect
    );
    function validateDockedScreens() {
        var current = {}; // outputKey(screen) → true for every current screen
        var screens = workspace.screens;
        for (var i = 0; i < screens.length; i++)
            current[outputKey(screens[i])] = true;
        Object.keys(dockedWindows).forEach((cls) => {
            var entry = dockedWindows[cls];
            var win = findByClass(cls);
            if (entry.screenName && !current[entry.screenName]) {
                releaseDockEntry(cls, true); // its screen is gone → restore + release
                return;
            }
            if (!win || entry.expanded) return;
            var scr = dockScreenFor(win);
            if (!scr) {
                releaseDockEntry(cls, true);
                return;
            }
            var expected = parkRectFor(win, scr, entry.edge, entry.offsetPx);
            var g = win.frameGeometry;
            if (g.x !== expected.x || g.y !== expected.y)
                moveDocked(win, expected);
        });
    }
    if (dockScreensChangedAvailable)
        workspace.screensChanged.connect(validateDockedScreens);

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
            lines.length > 0 ? lines.join("\n") : "(no windows found)",
        );
    }

    registerShortcut(
        "DropdownAny-ListWindows",
        "Dropdown Any: List active window classes",
        "Meta+Shift+W",
        listWindowClasses,
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

    var repeatLastSc =
        readConfig("repeatLastShortcut", "Meta+Shift+R").trim() ||
        "Meta+Shift+R";
    registerShortcut(
        "DropdownAny-ToggleLast",
        "Dropdown Any: Toggle last activated slot/tile",
        repeatLastSc,
        toggleLastActivated,
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

        dbg(
            shortcut +
                " → Release temp slot\nNo bound temp slot found (focused window isn't one, and none was recently toggled)",
        );
    }

    var releaseTempSc =
        readConfig("releaseTempSlotShortcut", "Meta+Shift+X").trim() ||
        "Meta+Shift+X";
    registerShortcut(
        "DropdownAny-ReleaseTempSlot",
        "Dropdown Any: Release active temp slot",
        releaseTempSc,
        () => {
            releaseActiveTempSlot("Release temp slot");
        },
    );

    // ── Resize shortcuts ──────────────────────────────────────────────────────
    var resizeHeightIncSc =
        readConfig("resizeHeightIncShortcut", "Alt+Shift+Up").trim() ||
        "Alt+Shift+Up";
    var resizeHeightDecSc =
        readConfig("resizeHeightDecShortcut", "Alt+Shift+Down").trim() ||
        "Alt+Shift+Down";
    var resizeWidthIncSc =
        readConfig("resizeWidthIncShortcut", "Alt+Shift+Right").trim() ||
        "Alt+Shift+Right";
    var resizeWidthDecSc =
        readConfig("resizeWidthDecShortcut", "Alt+Shift+Left").trim() ||
        "Alt+Shift+Left";
    registerShortcut(
        "DropdownAny-ResizeHeightInc",
        "Dropdown: Increase height",
        resizeHeightIncSc,
        () => {
            resizeActive(0, RESIZE_STEP);
        },
    );
    registerShortcut(
        "DropdownAny-ResizeHeightDec",
        "Dropdown: Decrease height",
        resizeHeightDecSc,
        () => {
            resizeActive(0, -RESIZE_STEP);
        },
    );
    registerShortcut(
        "DropdownAny-ResizeWidthInc",
        "Dropdown: Increase width",
        resizeWidthIncSc,
        () => {
            resizeActive(RESIZE_STEP, 0);
        },
    );
    registerShortcut(
        "DropdownAny-ResizeWidthDec",
        "Dropdown: Decrease width",
        resizeWidthDecSc,
        () => {
            resizeActive(-RESIZE_STEP, 0);
        },
    );

    // ── Dock shortcuts (A3) ────────────────────────────────────────────────────
    //
    // Three KGlobalAccel-registered shortcuts (KGlobalAccel only; no
    // setTimeout/Qt/exec). Ids MUST equal the kglobalshortcutsrc keys
    // config-helper.sh writes (PR2 key contract keeps these fixed:
    // dockOffsetPx, dockLeftShortcut, dockRightShortcut,
    // dockReleaseAllShortcut). Shortcut strings live in kwinrc
    // [Script-plasma-dropdown-any].
    var dockLeftSc =
        readConfig("dockLeftShortcut", "Ctrl+Shift+Left").trim() ||
        "Ctrl+Shift+Left";
    var dockRightSc =
        readConfig("dockRightShortcut", "Ctrl+Shift+Right").trim() ||
        "Ctrl+Shift+Right";
    var dockReleaseSc =
        readConfig("dockReleaseAllShortcut", "Ctrl+Shift+H").trim() ||
        "Ctrl+Shift+H";

    registerShortcut(
        "DropdownDockLeft",
        "Dropdown Any: Dock focused window to left edge",
        dockLeftSc,
        () => {
            dockWindow("left");
        },
    );
    registerShortcut(
        "DropdownDockRight",
        "Dropdown Any: Dock focused window to right edge",
        dockRightSc,
        () => {
            dockWindow("right");
        },
    );
    registerShortcut(
        "DropdownDockReleaseAll",
        "Dropdown Any: Release all docked windows",
        dockReleaseSc,
        releaseAllDocked,
    );

    // ── Shortcuts cheat sheet ─────────────────────────────────────────────────
    //
    // OSD listing every configured slot/tile with its shortcut, plus the
    // fixed global shortcuts — a quick reference without opening the widget.
    function listConfiguredShortcuts() {
        var lines = [];

        var slotIdxs = [];
        for (var key in slotConfig) slotIdxs.push(key);
        slotIdxs.sort((a, b) => slotConfig[a].idx - slotConfig[b].idx);
        slotIdxs.forEach((key) => {
            var slot = slotConfig[key];
            var label = slot.temporary ? "(temporary)" : key;
            lines.push(
                "Slot " + slot.idx + ": " + label + " → " + slot.shortcut,
            );
        });

        var tileIds = Object.keys(tileConfig).sort(
            (a, b) => tileConfig[a].idx - tileConfig[b].idx,
        );
        tileIds.forEach((id) => {
            var tile = tileConfig[id];
            lines.push(
                "Tile " +
                    tile.idx +
                    ": " +
                    (tile.classLeft || "—") +
                    " | " +
                    (tile.classRight || "—") +
                    " → " +
                    tile.shortcut,
            );
        });

        lines.push("—");
        lines.push("List active windows → Meta+Shift+W");
        lines.push("Repeat last activated → " + repeatLastSc);
        lines.push("Release active temp slot → " + releaseTempSc);
        lines.push("Increase height → " + resizeHeightIncSc);
        lines.push("Decrease height → " + resizeHeightDecSc);
        lines.push("Increase width → " + resizeWidthIncSc);
        lines.push("Decrease width → " + resizeWidthDecSc);
        lines.push("Dock focused left → " + dockLeftSc);
        lines.push("Dock focused right → " + dockRightSc);
        lines.push("Release all docked → " + dockReleaseSc);

        callDBus(
            "org.kde.plasmashell",
            "/org/kde/osdService",
            "org.kde.osdService",
            "showText",
            "preferences-desktop-keyboard-shortcuts",
            lines.join("\n"),
        );
    }

    registerShortcut(
        "DropdownAny-ListShortcuts",
        "Dropdown Any: List configured slots/tiles and global shortcuts",
        readConfig("listShortcutsShortcut", "Meta+Shift+S").trim() ||
            "Meta+Shift+S",
        listConfiguredShortcuts,
    );

    console.log(
        "[DropdownAny] loaded — " +
            registered +
            "/10 slots, " +
            tilesRegistered +
            "/10 tile pairs active.",
    );
})();
