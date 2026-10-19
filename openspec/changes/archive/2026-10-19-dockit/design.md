---
change: dockit
phase: design
---

# Design — dockit (MVP)

## 1. Purpose

Technical design for the dock MVP specified in `specs/dock/spec.md`: a standalone
dock state machine in `contents/code/main.js` that parks the focused window against
the left/right edge of **its own screen** (never the virtual union), preserves its
size, exposes a configurable global `dockOffsetPx` sliver, expands on activation,
re-docks on blur, releases all via a dedicated shortcut, animates through the
existing slide effect, and interacts with the hide/temp/tile state machines only
through explicit precedence gating.

This document resolves every open item carried from proposal/spec: tracker shape,
geometry math, handler wiring, skip-flag schedule, precedence semantics, config
surface (including whether `main.xml` is touched), shortcut defaults vs. conflicts,
and cleanup on window close / monitor removal.

## 2. Architecture Summary

### 2.1 One new state machine, zero new infrastructure

Everything is built from proven, in-repo primitives:

| Need | Reused primitive |
| --- | --- |
| Tracker pattern | `hiddenWindows` class-keyed tracker (main.js ~166) — shape only, NOT reused (see §6) |
| Interaction model | `workspace.windowActivated` blur→park / focus→restore (main.js 560–567, 587–597, 656–662) |
| Geometry mutation | `win.frameGeometry = {x,y,width,height}` object-literal (main.js 80–87) |
| Multi-screen math reference | `workspace.screens[i].geometry` (virtualScreenBounds, main.js 213–224) |
| Animation gate | skip flags set before each move, cleared after (show path, main.js ~344–382); effect's skipSwitcher fallback |
| Shortcut plumbing | `readConfig` + `registerShortcut` (KGlobalAccel) + kglobalshortcutsrc `[kwin]` (config-helper.sh global_shortcuts) |
| Config UI | ConfigEditor.qml Global-shortcuts Repeater + `_buildConfig` JSON |

### 2.2 Data-flow diagram

```
 User input                                   Runtime state                     Geometry
 ────────────────────────────────           ───────────────────────          ─────────────────
 [Ctrl+Shift+Left/Right]  ──► dockWindow("left"|"right")               dockable() gate
 [Ctrl+Shift+H]           ──► releaseAllDocked()                       skip min/max/fs/shells
 [sliver click/Alt+Tab]   ──► workspace.windowActivated  ──► expand/re-dock sweep
 [window closed]          ──► workspace.windowRemoved    ──► releaseDockEntry(restore=false)
 [monitor removed]        ──► workspace.screensChanged   ──► validate/restore+release
                                                                                    │
                       dockedWindows[cls] ──────────────────────────────────────────┤
                       { x,y,width,height, edge, offsetPx, expanded, screenName }   │
                                                                                    ▼
                                              moveDocked(): skip* = true → frameGeometry = … → skip* = false
                                                                                    │
                                                                                    ▼
                                            slide effect animates the transition (skipSwitcher fallback)

 Config (plasmoid)                                          Runtime read
 ─────────────────────                                    ─────────────────
 ConfigEditor.qml properties ⇄ _buildConfig JSON ⇄ config-helper.sh load/save ⇄ kwinrc
   dockOffsetPx                             [Script-plasma-dropdown-any] ──► main.js readConfig
   dockLeftShortcut/…                       ⇄ kglobalshortcutsrc [kwin] ──► registerShortcut
```

## 3. Runtime state model — `dockedWindows` tracker

### 3.1 Shape

```js
var dockedWindows = {}; // resourceClass.toLowerCase() → entry

// entry:
{
  x, y, width, height,   // immutable pre-dock snapshot (frameGeometry at dock time)
  edge:      "left" | "right",
  offsetPx:  Number,     // global offset captured at dock time
  expanded:  Boolean,    // false = parked at edge; true = at snapshot geometry
  screenName: String     // outputKey() of the window's own screen at dock time
}
```

Keying: **lowercased `resourceClass`**, consistent with `findByClass()` matching and
with the class-keyed tracker precedent. One docked window per class (spec business
rule); docking a second window of the same class releases the existing entry first
(class-collision release).

### 3.2 Lifecycle

```
                           dock shortcut (new window)
  ┌──────────────────────────────────────────────────────────────┐
  ▼                                                              │ class collision (same class docked again)
 None ──► dockWindow() gate ok ──► [ Docked ] ── release/restore order:
                                     │
        sliver click (windowActivated, win === activeWin)        │
                                     ▼
                                [ Expanded ] ── blur (win !== activeWin) ──► re-dock to same edge/offset
                                     │
        release-all / screen-removed / becomes min|max|fs ──► restore snapshot (or no-op) ──► None
        windowRemoved ──► delete entry, no geometry action ──► None
```

Entry removal happens through **exactly one** of: release-all, window close
(`windowRemoved`), monitor removal (`screensChanged`), or class-collision release.
After any of these, no stale entry survives (spec invariant).

| Event | State change | Geometry action |
| --- | --- | --- |
| Dock shortcut, new window | None → Docked | snapshot + park (skip-flag schedule) |
| Dock shortcut, already docked | any → Docked | re-park to requested edge; **snapshot preserved** |
| activation (win === activeWin) | Docked → Expanded | restore snapshot |
| blur (win !== activeWin) | Expanded → Docked | re-park using **current** geometry/size |
| blur while now minimized/maximized/fullscreen | → None | release, **no geometry mutation** |
| release-all | any → None (all) | restore every snapshot (identity for drifted expanded) |
| window close | → None | delete entry only |
| screen removed | → None | guarded snapshot restore (see §5.5) |
| second same-class window docked | old → None | restore old snapshot, then dock new |

## 4. Geometry calculation (per-screen, size-preserving)

### 4.1 Resolving "the window's own screen"

New helper `dockScreenFor(win)` — pure geometry, no QPoint construction (the `Qt`
namespace is unavailable; `workspace.screenAt` needs a QPoint that object literals
may not convert to):

1. Take the center of `win.frameGeometry` (the window is fully on-screen at every
   dock/expand/re-dock decision point, so its center is inside its own screen).
2. Return the `workspace.screens[i]` whose `geometry` contains the center.
3. Fallback if the center is outside every screen (edge case): the screen with the
   nearest center, else `null` → abort the dock cleanly (no entry, spec error
   handling).

This exactly implements the spec's "window's own screen, never the virtual
multi-screen union" (the multi-monitor scenario in the spec): on a two-monitor
setup the window parks against its own monitor's edge and never lands on the
neighbor.

### 4.2 Park position

`parkRectFor(win, screen, edge)` — keeps `width`, `height`, and `y` unchanged;
only `x` changes:

```
Left edge (sliver pokes INTO the screen from the left edge):
   window's right edge at screen.x + offset
   x = screen.x + offset − win.width

Right edge (sliver pokes INTO the screen from the right edge):
   window's left edge at screen.x + screen.width − offset
   x = screen.x + screen.width − offset
```

```
Left-edge dock, screen width W, window width w (w >> offset):

 screen.x+0 ──────────────────────────────────────────────── screen.x+W
            │  window (w × h) mostly OFF-screen to the left
            │
            │  ▓▓▓▓   visible sliver = offset px (window's rightmost offset px)
            │  window right edge at screen.x + offset
            │
 park x = screen.x + offset − w        (compare hideWindow left: bounds.x − w)
```

Notes:

- The push is exactly **w − offset** less than the off-screen hide push
  (`hideWindow`: `offX = bounds.x - g.width`), which is the whole point of dock vs
  hide.
- `y` is preserved (window keeps its current vertical position). Tradeoff in §10.
- If `win.width <= offset` the whole window sits on-screen near the edge; accepted
  degenerate case (offset is clamped ≥ 1 per spec, width is user-controlled).
- Offset is captured into the entry at dock time (`entry.offsetPx`) — "same edge
  and offset" for every re-dock, matching the spec wording; the globav value only
  changes on script reload (spec scenario: applies on reload), which wipes tracker
  state anyway.
- Expanded windows that the user moved to another monitor re-dock against the
  **new** screen's edge (current-geometry semantics), which is the useful behavior;
  the snapshot is untouched.

## 5. Handlers

### 5.1 Shortcut handlers (KGlobalAccel)

```js
registerShortcut("DropdownDockLeft",      "Dropdown Any: Dock focused window to left edge",  dockLeftSc,  function () { dockWindow("left");  });
registerShortcut("DropdownDockRight",     "Dropdown Any: Dock focused window to right edge", dockRightSc, function () { dockWindow("right"); });
registerShortcut("DropdownDockReleaseAll", "Dropdown Any: Release all docked windows",       dockReleaseSc, releaseAllDocked);
```

`dockWindow(edge)` logic order (important):

1. `win = workspace.activeWindow`; `cls = resourceClass.toLowerCase()`; no window/class → return.
2. **Existing entry branch first** (spec: dock shortcut on an already-docked window
   re-docks to the requested edge, snapshot preserved): set `edge`, `expanded=false`,
   re-park via `parkRectFor` + `moveDocked`, return. This intentionally runs before the
   `dockable()` gate so re-docking an already-tracked window still works if its state
   drifted (e.g. it was re-parked while the trailing minimize case was pending).
3. Else `dockable(win)` gate (see §6): minimized / maximized / fullscreen /
   shell-class → silent skip (`dbg` only), no entry, no geometry.
4. Class-collision: if `dockedWindows[cls]` exists → release it (restore snapshot).
5. Snapshot `{x,y,width,height}` from `win.frameGeometry`.
6. `dockScreenFor(win)`; null → abort cleanly.
7. Create entry (`edge`, current offset, `expanded=false`, `screenName = outputKey(screen)`).
8. `moveDocked(win, parkRectFor(...))`.

`releaseAllDocked()` — iterates keys, `releaseDockEntry(cls, restore=true)` each;
no entries → no-op (idempotent, spec). OSD notify with the count (pattern of
temp-slot release, which is user-visible).

### 5.2 `windowActivated` — expand/re-dock sweep (single handler)

```js
workspace.windowActivated.connect(function (activeWin) {
    Object.keys(dockedWindows).forEach(function (cls) {
        var entry = dockedWindows[cls];
        var win = findByClass(cls);
        if (!win) return;
        if (win === activeWin) {
            // sliver clicked (ordinary activation): expand only when parked + still plain
            if (!entry.expanded && !win.minimized && !win.maximized && !win.fullScreen) {
                expandDocked(win, entry);
            }
        } else if (entry.expanded) {
            // focus moved elsewhere (including null = desktop): re-dock,
            // or release if the window is no longer a plain window
            if (win.minimized || win.maximized || win.fullScreen) releaseDockEntry(cls, false);
            else redockDocked(win, entry);
        }
    });
});
```

Why this shape:

- Uses the exact `activeWin === win` idiom the three autoHide handlers already rely
  on — no dependency on `.active` timing semantics.
- `activeWin === null` (desktop focused) is handled: every expanded entry re-docks.
- **No oscillation** (spec error handling): each signal emission performs at most
  one action per entry, flags flip synchronously before the move, and expand/re-dock
  are mutually exclusive branches. A rapid click-away/click-back is two separate
  emissions, each a single transition.
- The expand path does **not** call `workspace.activeWindow = win` — the activation
  that fired the signal already happened; re-setting focus is redundant on Wayland
  and risks a focus-steal loop (exposure the show path already carries, but
  unnecessary here). Documented deviation from the show path.

`expandDocked`: flip `expanded=true` **before** the geometry move (so a re-entrant
signal can't double-expand), then `moveDocked(win, snapshot rect)`.

`redockDocked`: flip `expanded=false`, `scr = dockScreenFor(win)`; null (screen
gone mid-flight) → `releaseDockEntry(cls, false)` (clean abort: no entry, no
partial geometry); else `moveDocked(win, parkRectFor(win, scr, entry.edge))`.

### 5.3 `windowRemoved` — cleanup

```js
workspace.windowRemoved.connect(function (removedWindow) {
    var cls = String(removedWindow.resourceClass || "").toLowerCase();
    if (!cls || !dockedWindows[cls]) return;
    releaseDockEntry(cls, false); // restore=false: never move a surviving sibling into a dead window's slot
});
```

Unconditional release for the class (spec: "entry removed; no geometry action").
Tradeoff vs. sibling-guard in §10.

### 5.4 `screensChanged` — monitor-removal / resolution drift

```js
workspace.screensChanged.connect(function () {
    var current = {}; // outputKey(screen) → true for every workspace.screens[i]
    Object.keys(dockedWindows).forEach(function (cls) {
        var entry = dockedWindows[cls];
        var win = findByClass(cls);
        if (entry.screenName && !current[entry.screenName]) {
            releaseDockEntry(cls, true); // its screen is gone → spec: restore + release
            return;
        }
        if (!win || entry.expanded) return;
        // Screen still present: re-park if the sliver invariant broke
        // (resolution/position change), otherwise leave it alone.
        var scr = dockScreenFor(win);
        if (!scr) { releaseDockEntry(cls, true); return; }
        var expected = parkRectFor(win, scr, entry.edge);
        var g = win.frameGeometry;
        if (g.x !== expected.x || g.y !== expected.y) moveDocked(win, expected);
    });
});
```

- Removal detection is by **stored output identity** (`outputKey` = `output.name`,
  falling back to the geometry rect string if `.name` is unavailable — verify at
  implementation). When the stored screen no longer exists the entry is restored
  and released **regardless of where KWin relocated the window** (spec scenario).
- The snapshot restore is guarded: `releaseDockEntry(restore=true)` only restores
  if the snapshot center still intersects a current screen (see §5.6), so a
  relocate-to-dead-monitor-coordinates can't strand the window off the surviving
  screens.
- Resolution/position changes on a surviving screen re-park quietly (keeps the
  sliver invariant honest) without releasing — the friendlier interpretation of the
  spec, documented as a decision.
- **Verification item**: confirm `workspace.screensChanged` exists in the KWin 6
  scripting surface (see §12). If unavailable, fall back to lazy validation inside
  the `windowActivated` sweep (re-check stored `screenName` membership per event) —
  same semantics, slightly later cleanup.

### 5.5 `releaseDockEntry(cls, restore)` — single exit point

```js
function releaseDockEntry(cls, restore) {
    var entry = dockedWindows[cls];
    if (!entry) return;
    delete dockedWindows[cls];
    var win = findByClass(cls);
    if (!win) return;
    win.skipTaskbar = false; win.skipPager = false; win.skipSwitcher = false; // hygiene
    if (!restore) return;
    if (win.minimized || win.maximized || win.fullScreen) return; // never fight these
    if (!snapshotCenterOnAnyCurrentScreen(entry)) return;          // don't restore into the void
    moveDocked(win, { x: entry.x, y: entry.y, width: entry.width, height: entry.height });
}
```

Every release path funnels here, guaranteeing "removed exactly once" and
"no geometry mutation" for the minimized/maximized/fullscreen cases.

### 5.6 Helpers

- `dockable(win)` — precedence gate: `!win`, `minimized`, `maximized`, `fullScreen`
  (verify property name §12), shell skip-list `{plasmashell, systemsettings,
  ksmserver, plasmawindowed}` (same literal as config-helper.sh). Tiled windows are
  **allowed** (visual detile, tiling state persists — documented limitation).
- `moveDocked(win, rect)` — the effect-gate schedule (§7).
- `readDockOffset()` — `parseInt(readConfig("dockOffsetPx", 24))`; NaN → 24; <1 → 1
  (spec error handling). Read once at load into `DOCK_OFFSET_PX`.
- `outputKey(output)` — `output.name` or geometry-string fallback.
- `isDockedClass(cls)` — `!!(cls && dockedWindows[cls.toLowerCase()])`; the shared
  predicate used by the precedence gates in existing handlers (§6.2).

## 6. Precedence

### 6.1 Precedence table (dock × existing states)

| Situation | Action | Where |
| --- | --- | --- |
| Dock shortcut, focused window minimized / maximized / fullscreen | skip — no geometry, no entry | `dockable()` |
| Dock shortcut, focused window is shell/panel (plasmashell, systemsettings, ksmserver, plasmawindowed) | skip | `dockable()` |
| Dock shortcut, focused window tiled | dock applies; window visually detiles; tiling state persists (documented) | `dockable()` passes |
| Dock shortcut, focused window already docked | re-dock to requested edge; snapshot preserved | `dockWindow` branch 2 |
| Docked window loses focus (autoHide class) | autoHide handler skips; dock re-docks | `isDockedClass` gate in autoHide handlers |
| Docked window's class toggled as temp slot | no slot action; stays docked | `isDockedClass` gate in `toggleWindow` |
| Docked window's class as tile half, tile toggled | no tile action on either half | `isDockedClass` gate in `toggleTile` |
| Docked window becomes minimized/maximized/fullscreen while expanded | entry released, no geometry mutation (on next blur; also possible via release-all guard) | `windowActivated` sweep / `releaseDockEntry` |
| Docked window closes | entry removed, no geometry action | `windowRemoved` |
| Docked window's screen removed | guarded snapshot restore + release | `screensChanged` |
| Second same-class window docked | old entry restored + released, new window docked | `dockWindow` step 4 |
| Release-all, no entries | no-op | `releaseAllDocked` |

Explicit non-interactions (documented decisions):

- `resizeActive` on an expanded docked window is **allowed** — it's a deliberate
  live interaction on the expanded window; the parked position is always recomputed
  from current geometry at park time, and drift is restored by release-all per spec.
- `releaseTempSlot` does **not** touch dock state (dock is orthogonal, owned by
  release-all/blur). The scenario in the spec only requires the *toggle* to skip.
- `keepAbove` / `allDesktops` / `opacity` are **never modified** by any dock
  operation (spec business rules).

### 6.2 Gating edits in existing handlers (3 sites)

1. `toggleWindow` (main.js ~339): after resolving `win`, before either hide/show
   branch: `if (isDockedClass(resolveClass(trackingKey))) { dbg skip; return; }`.
2. `toggleTile` (main.js ~490): before the hide/show branches:
   `if (isDockedClass(tile.classLeft) || isDockedClass(tile.classRight)) return;`.
3. autoHide handlers (3 registration sites: temp 560–567, regular 587–597, tile
   656–662): in the blur branch, skip `hideWindow`/`hideTile` when the resolved
   class(es) are docked.

These gates are what make the spec scenario "autoHide handler skips a docked
window" hold, and they make dock→autoHide handoff safe: after release-all, the next
blur for an autoHide class parks it normally again.

### 6.3 Why `hiddenWindows` is NOT reused

`hiddenWindows` has one hard invariant: **entry exists ⟺ window parked fully
off-screen by us**. A docked window is on-screen (sliver), which breaks every
consumer of that invariant:

- `toggleWindow` treats `hiddenWindows[tk] !== undefined` as "hidden" and would
  take the *show* branch (reposition via `applyDropdownGeometry` + `delete`),
  fighting the dock's parked position on the very next toggle.
- The blur→hide path (`hideWindow`) re-snapshots geometry and pushes the window
  past the virtual union — a docked window would get *hidden* instead of re-docked
  (double management, exactly what the spec forbids).
- Keying differs too: `hiddenWindows` is keyed by trackingKey (temp slots use
  synthetic `"temp:<idx>"` keys), dock is keyed by class.
- Extending `hiddenWindows` would put dock-aware branches in every existing gate
  (toggleWindow/toggleTile/autoHide/`releaseTempSlot`/`windowRemoved`) — the same
  work as a separate tracker, but with high regression risk on the dropdown core
  and no upside. The spec mandates isolated tracking; the separate `dockedWindows`
  tracker plus explicit `isDockedClass` gates is the low-risk route.

## 7. skip-flag schedule (effect gate)

The slide effect animates a geometry change only when the window's class is in
`ManagedClasses` OR `skipSwitcher === true` at the moment
`windowFrameGeometryChanged` fires (effect main.js `onWindowFrameGeometryChanged`).
Dock targets arbitrary windows, so it must ride the **skipSwitcher fallback**
(TempSlotStyle/TempSlotDurationMs) for non-managed classes.

`moveDocked()` encapsulates the schedule, mirroring the show-path precedent
(main.js ~344–382):

```js
function moveDocked(win, rect) {
    win.skipTaskbar  = true;
    win.skipPager    = true;
    win.skipSwitcher = true;          // effect gate — read at geometry-change time
    win.frameGeometry = { x: rect.x, y: rect.y, width: rect.width, height: rect.height };
    win.skipTaskbar  = false;         // spec: docked windows STAY visible in
    win.skipPager    = false;         //   taskbar/pager/switcher in both states
    win.skipSwitcher = false;
}
```

Every dock transition (park, expand, re-dock, release restore) goes through
`moveDocked` — there is no other geometry mutation path, and no skip flag is left
set while idle. This satisfies both the effect gate and the spec business rule
"docking MUST NOT remove the window from the taskbar, pager, or task switcher in
either the parked or expanded state" (unlike hidden windows, which keep skip flags
while parked).

Verification item: confirm the effect reads `skipSwitcher` at
geometry-change-signal time so the immediate clear does not cancel the pending
animation (research checklist item 6; the show path already relies on this).

## 8. Config integration (global offset + 3 shortcuts)

### 8.1 Key surface

| Key | kwinrc group | Default | Consumed by |
| --- | --- | --- | --- |
| `dockOffsetPx` | `Script-plasma-dropdown-any` | `24` | main.js `readDockOffset()` |
| `dockLeftShortcut` | `Script-plasma-dropdown-any` | `Ctrl+Shift+Left` | main.js readConfig → registerShortcut |
| `dockRightShortcut` | `Script-plasma-dropdown-any` | `Ctrl+Shift+Right` | main.js readConfig → registerShortcut |
| `dockReleaseAllShortcut` | `Script-plasma-dropdown-any` | `Ctrl+Shift+H` | main.js readConfig → registerShortcut |
| kglobalshortcutsrc `[kwin]` entries | `DropdownDockLeft` / `DropdownDockRight` / `DropdownDockReleaseAll` | same defaults | KGlobalAccel (System Settings → Shortcuts) |

Shortcut object names **must** match `registerShortcut`'s first argument exactly
(config-helper.sh writes `"{sc},none,{description}"`, same as the existing
`global_shortcuts` dict entries).

### 8.2 `contents/code/main.js`

- `DOCK_OFFSET_PX = readDockOffset()` at load (spec: applies on reload).
- Three `registerShortcut` calls (§5.1), placed with the other fixed global
  shortcuts (resize/release/list block).
- Three new rows in `listConfiguredShortcuts()` cheat sheet.
- `dbg()` on dock/expand/re-dock; `osdNotify()` on release-all (user-visible
  confirmation, matching temp-slot release).

### 8.3 `plasmoid/contents/code/config-helper.sh`

- `cmd_load` (Python): add
  `dock_offset_px = to_int(kread("dockOffsetPx", "24"), 24)` and the three shortcut
  reads with defaults; include all four in the emitted JSON (same pattern as
  `repeatLastShortcut` etc.).
- `cmd_save` (Python): extend `global_shortcuts` dict with three entries

  ```python
  "dockLeftShortcut":        ("DropdownDockLeft", "Ctrl+Shift+Left",   "Dropdown Any: Dock focused window to left edge"),
  "dockRightShortcut":       ("DropdownDockRight", "Ctrl+Shift+Right", "Dropdown Any: Dock focused window to right edge"),
  "dockReleaseAllShortcut":  ("DropdownDockReleaseAll", "Ctrl+Shift+H", "Dropdown Any: Release all docked windows"),
  ```

  and write `kwrite("--file","kwinrc","--group",kwin_group,"--key","dockOffsetPx", str(data.get("dockOffsetPx", 24)))`.

### 8.4 `plasmoid/contents/ui/ConfigEditor.qml`

- Four properties (`dockOffsetPx: 24` int, three shortcut strings with defaults).
- `_onLoad`: assign from `data` with the same defaults.
- `_buildConfig`: include the four keys in the JSON payload.
- Global-shortcuts Repeater model: three new rows
  (`{ label: "Dock focused window to left edge", prop: "dockLeftShortcut" }`, etc.) —
  the delegate already binds `root[modelData.prop]` with
  `checkForConflictsAgainst: 2` (GlobalShortcuts), so conflicts surface in the
  plasmoid too.
- New "Dock" Kirigami.Card (placed near Global shortcuts): a
  `Controls.SpinBox` for `dockOffsetPx` (from 1, stepSize 4, `"px"` suffix,
  `onValueModified → root.dockOffsetPx = value; dirty = true`), plus a hint label
  documenting: applies to any focused window; minimized/maximized/fullscreen and
  panel windows are skipped; Ctrl+Shift+Left/Right may collide with in-app global
  shortcuts — remap in System Settings → Shortcuts if a second registration loses.

### 8.5 `contents/config/main.xml` — **decision: not modified**

Resolved here (proposal open item): the kcfg file mirrors kwinrc **only for the
per-slot surface consumed by the KCM** (ten `windowClassN`/`shortcutN`/
`widthPercentN` triplets). Every global config/shortcut added since the original
KCM surface — `repeatLastShortcut`, `resize*Shortcut`, `releaseTempSlotShortcut`,
`listShortcutsShortcut`, `tempSlotAnimation*` — deliberately bypasses main.xml and
lives in kwinrc via config-helper.sh. Adding dock keys to main.xml would create a
documented-but-unread config surface and imply KCM support that is explicitly out
of scope for this change. **All four dock keys ride the established
config-helper.sh round-trip exclusively.** If the KCM later learns dock, the four
entries are added to main.xml with zero migration (same kwinrc group).

## 9. File-by-file change map

| File | Change | Anchor |
| --- | --- | --- |
| `contents/code/main.js` | +`dockedWindows` tracker & helpers (`dockable`, `dockScreenFor`, `parkRectFor`, `moveDocked`, `outputKey`, `readDockOffset`, `isDockedClass`, `releaseDockEntry`, `expandDocked`, `redockDocked`, `dockWindow`, `releaseAllDocked`); `windowActivated` dock sweep; `windowRemoved` + `screensChanged` handlers; 3 shortcuts; `DOCK_OFFSET_PX`; cheat-sheet rows | after the tile/toggle section (~line 700), mirroring existing section layout; gates inserted at toggleWindow (~339), toggleTile (~490), 3 autoHide sites (560–567, 587–597, 656–662) |
| `plasmoid/contents/code/config-helper.sh` | load: 4 reads + JSON keys; save: 3 `global_shortcuts` dict entries + `dockOffsetPx` write | `cmd_load` python block; `global_shortcuts` dict (~309–325) |
| `plasmoid/contents/ui/ConfigEditor.qml` | 4 properties (47–55 area); `_onLoad` (119–125 area); `_buildConfig` (396–402 area); 3 Repeater rows (1536–1561 area); new Dock card + offset SpinBox | as listed |
| `contents/config/main.xml` | **unchanged** (decision §8.5) | — |
| `README.md` | Dock feature section: shortcuts, offset, precedence summary, conflict note | feature docs area |

Not touched: `effect/`, `kcm/`, off-screen hide internals.

## 10. Decisions & tradeoffs

| # | Decision | Chosen | Alternative | Tradeoff / rationale |
| --- | --- | --- | --- | --- |
| D1 | Config surface | kwinrc (config-helper.sh) only; `main.xml` untouched | add kcfg entries | Consistency with every post-KCM global key; avoids dead surface. KCM parity later = zero migration. |
| D2 | Shortcut defaults | `Ctrl+Shift+Left/Right/H` | `Meta+Ctrl+Left/Right/H` | Mnemonic and left-hand friendly; Ctrl+Shift+arrows are common **in-app** (word select in editors/terminals) but those are app-local — only conflicting **global** shortcuts matter to KGlobalAccel; conflicts surface in System Settings + plasmoid KeySequenceItem, remap is one click. Meta+Ctrl is heavier and Meta is already crowded by KWin window-management defaults. |
| D3 | Tracker keying | class (lowercased resourceClass) | window id | Matches `findByClass`/`hiddenWindows` precedent; allows "dock/release by class" semantics. Caveat: two same-class windows are ambiguous (documented, same exposure as hiddenWindows). |
| D4 | `windowRemoved` release | unconditional for the class (restore=false) | sibling-guard like temp slots | Spec text says "entry removed"; transferring dock to a never-docked sibling is speculative. Known caveat: if the *other* same-class window closes, the parked one is left untracked (stays parked until release-all). Rare; class-keyed limitation. |
| D5 | Screen-removal policy | restore + release, but restore guarded by "snapshot center on a current screen" | blind restore / blind re-park | Honors the spec scenario; guarded restore never strands a relocated window in dead-monitor coordinates. Re-park-on-resize for surviving screens keeps the sliver honest. |
| D6 | y position while parked | preserved (current y) | vertical centering / snapshot y | Minimal surprise, matches "only position changes" phrasing; centering adds a second dimension to re-park math for little value. |
| D7 | Offset capture | stored in entry at dock time | live-read every re-dock | "Same edge and offset" per re-dock; offset config only changes on reload (which clears the tracker anyway). |
| D8 | Expand signal handling | rely on the activation that fired `windowActivated`; no `workspace.activeWindow = win` | set activeWindow like the show path | Redundant on click (window is already active) and adds Wayland focus-steal exposure; no-op or hazard with no benefit. |
| D9 | `resizeActive` on expanded docked window | allowed | blocked | Deliberate live interaction; park math is recomputed from current geometry anyway; release-all undoes drift per spec. |
| D10 | `dockOffsetPx` clamp | NaN→24, <1→1 | reject/ignore | Spec error handling verbatim; sliver must remain visible. |
| D11 | Feature gate | none (shortcuts are the gate) | `dockEnabled` checkbox | Spec has no enabled key; remapping/unbinding the shortcuts is the existing off-switch. |
| D12 | Release-all feedback | OSD with count | silent / dbg only | Matches user-visible temp-slot release precedent; release-all is irreversible-ish (snapshot restore), so confirm visibly. |
| D13 | Screens changed listener | `workspace.screensChanged` + lazy fallback | per-event validation only | Cleanest trigger if available (verify §12); lazy fallback keeps identical semantics with zero scheduler. |

## 11. Verification plan (manual, per repo policy)

No formal runner (`testing.enabled: false`). Smoke matrix maps directly to spec
scenarios:

| # | Check | Pass criteria |
| --- | --- | --- |
| V1 | `bash -n plasmoid/contents/code/config-helper.sh` | exit 0 |
| V2 | Install: `kpackagetool6` KWin/Script + Plasma/Applet packages per install.sh | installs clean |
| V3 | `kwin6 --replace`, check journal `[DropdownAny] loaded` + effect config log | no JS errors |
| V4 | Dock focused window left/right on single monitor | parked at own-screen edge, 24px sliver, size unchanged (x changed only) |
| V5 | Multi-monitor: dock on the right monitor | parks against that monitor's edge; nothing lands on the left monitor |
| V6 | Click sliver → expand to pre-dock geometry; Alt+Tab away → re-dock same edge/offset | both transitions animate via slide effect |
| V7 | `Ctrl+Shift+H` with parked + expanded + drifted windows | all restored to snapshot; tracker empty; second press is no-op |
| V8 | Remap a dock shortcut in System Settings → Shortcuts; also in plasmoid | new binding docks; old binding inert |
| V9 | Set offset 48 in plasmoid, save (reload), dock | 48px sliver |
| V10 | Dock an autoHide/temp/tile-configured class; blur | window re-docks; is NOT hidden; slot/tile toggles while docked are no-ops; after release-all the autoHide behavior resumes |
| V11 | Minimized/maximized/fullscreen focused window → dock shortcut | no geometry change, no entry; shell window (plasmashell) → no-op |
| V12 | Dock a window; close it | no stale entry (journal clean); minimize an expanded docked window then blur | entry released, window stays minimized |
| V13 | Dock on monitor A; disconnect A | window restored (guarded) + released, no stale entry |
| V14 | Dock a second window of the same class | first restored+released, second docked |
| V15 | Non-slot class dock (e.g. a terminal not in ManagedClasses) | animation via skipSwitcher fallback (TempSlot style/duration) |
| V16 | KGlobalAccel conflict check on target system | collision set for Ctrl+Shift+Left/Right/H documented; conflict-free install registers all three |

## 12. Open verification items (implementation-time, from research.md)

1. `workspace.screensChanged` availability in the KWin 6 scripting surface
   (fallback designed in §5.4).
2. Output identity: `output.name` / `win.screen` property names on KWin 6
   (fallback: geometry-string key).
3. Window property spelling: `win.fullScreen` vs `win.fullscreen` (check both at
   implementation).
4. Effect skip-flag timing: `skipSwitcher` read at geometry-change time so the
   immediate clear doesn't cancel the animation (research item 6).
5. KGlobalAccel collision set for the three defaults on the target install
   (research item 4) — informs README wording.
6. Wayland focus transfer: click-sliver activation fires `windowActivated` with
   `activeWin === win` for arbitrary apps (same exposure as the show path).

## 13. Rollout & rollback

- Runtime-only state: no persisted dock geometry; config keys are additive defaults.
- Rollback: revert main.js dock section + config-helper.sh/QML additions; any
  currently-docked window is restored by `Ctrl+Shift+H` before unload, or tracked
  cleanly across reload (KWin reload wipes runtime tracker; parked windows keep
  geometry but are untracked — spec business rule).
- No feature gate shipped (D11); shortcuts themselves toggle the feature.

## 14. Scope re-affirmation (MVP boundary)

In: dock/expand/re-dock/release-all, per-screen edges + global offset, precedence
gates, cleanup, shortcuts/config UI, animation. Out: hover-expand, per-window/per-edge
offsets, top/bottom dock, tiling API integration, effect/KCM changes, formal tests.

Next step: tasks.
