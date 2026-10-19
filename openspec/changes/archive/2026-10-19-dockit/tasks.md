---
change: dockit
phase: tasks
status: draft
---

# Tasks — dockit (MVP)

Standalone dock state machine in `contents/code/main.js` (park focused window at its
own screen's left/right edge, `dockOffsetPx` sliver, expand on activation / re-dock on
blur, release-all shortcut), plus config surface (config-helper.sh + ConfigEditor.qml:
global offset + 3 shortcuts) and README docs. No formal test runner (`testing.enabled:
false`); verification is per-task manual smoke + the apply-phase smoke matrix.

## Review Workload Forecast

| Field | Value |
| ------- | ------- |
| Estimated changed lines | ~380–480 (almost all additions) |
| 400-line budget risk | High |
| Chained PRs recommended | Yes |
| Suggested split | PR 1: main.js (areas A+B) → PR 2: config-helper.sh + ConfigEditor.qml (area C) → PR 3: README (area D) |
| Delivery strategy | ask-on-risk |
| Chain strategy | pending — orchestrator declared `deferred`; resolves to a concrete strategy at apply time if the risk triggers |

```text
Decision needed before apply: Yes
Chained PRs recommended: Yes
Chain strategy: pending
400-line budget risk: High
```

Rationale: **PR 1 (~250–290 changed lines)** is the whole runtime feature (tracker,
geometry, handlers, gates, shortcuts) and is independently verifiable by
dock/expand/re-dock/release smoke. **PR 2 (~90–100 lines)** makes the config editable
from the plasmoid; its key names must match PR 1's `readConfig` keys. **PR 3 (~45–60
lines)** documents. Each PR has start/finish/verify/rollback boundaries (below). If a
single PR is insisted on, the estimate breaches the 400-line budget → ask-on-risk.

## Task conventions

- **TDD note:** repo has `strict_tdd: true` but `testing.enabled: false` (no runner).
  RED→GREEN→TRIANGULATE→REFACTOR sequencing does not apply; instead each task carries
  its own manual verification (journal grep, `bash -n`, DBus probes) and the
  apply-phase smoke matrix re-checks cross-cutting behavior.
- **Platform constraints** (agents.md, honored in every main.js task): no
  `setTimeout`/timers, no `Qt` namespace, no `exec()`; KGlobalAccel `registerShortcut`
  only; geometry via `frameGeometry = {x,y,width,height}` object literal; effect
  package untouched.
- Priorities inside a task, if they conflict: spec > design > this file.

## Dependency graph

```
T0 (KWin6 API spike)
  ├─► A1 tracker + offset helpers
  │     ├─► A2 release/expand/redock/dockWindow
  │     │     ├─► A3 shortcuts + cheat sheet ──┐ (fixes key names)
  │     │     └─► B1 windowActivated sweep      │
  │     └─► B4 precedence gates                 │
  B2 windowRemoved ── B3 screensChanged         │
  └─► B1, B2, B3, B4 all depend on A1           ▼
                                        C1, C2 (must match A3 key names)
                                              ├─► C3, C4, C5 (QML)
                                              ▼
                                        D1 (needs T0 conflict set + C results)
                                              ▼
                                        V1–V3 (apply-phase smoke matrix)
```

---

## Area 0 — Prerequisite: KWin 6 API verification spike

### T0 — Verify the 6 implementation-time unknowns before coding geometry

**Files (discovery targets):** `contents/code/main.js`; probe scripts under
`/tmp/*.js` loaded via `qdbus6 org.kde.KWin /Scripting` (reuse the existing
config-helper.sh `list-windows` load/run technique and README "Debugging §5");
`~/.config/kglobalshortcutsrc`.

Verify and record (comment in main.js dock section + feed wording to D1):

1. `workspace.screensChanged` exists in the KWin 6 scripting surface (design §5.4);
   if absent, ship the lazy `windowActivated` fallback instead.
2. Output identity: `output.name` on `workspace.screens[i]` vs geometry-string
   fallback (`outputKey()`).
3. Property spelling: `win.fullScreen` vs `win.fullscreen` (design §5.5).
4. Effect skip-flag timing: `skipSwitcher` is read at geometry-change time so the
   immediate clear after `moveDocked` does not cancel the animation.
5. KGlobalAccel collision set for `Ctrl+Shift+Left` / `Ctrl+Shift+Right` /
   `Ctrl+Shift+H` on the target install (informs README conflict wording).
6. Wayland: clicking a sliver fires `windowActivated` with `activeWin === win` for a
   window of an arbitrary (non-managed) class.

**Verification:** journal shows no errors from the probe script; each finding recorded
as a code comment or design note. Exit gate: these claims are re-checked *during* each
task, not a hard blocker for draft implementation (fallbacks designed for each).

**Rollback:** probe scripts are `/tmp` only; no repo files modified.

---

## Area A — `contents/code/main.js`: dock tracker + geometry core

### A1 — Add `dockedWindows` tracker, `DOCK_OFFSET_PX`, and pure geometry helpers

**File:** `contents/code/main.js` — new "Dock" section after the tile registration
block (~line 700), mirroring existing section layout.

Implement (design §3, §4, §5.6, §7):

- `var dockedWindows = {};` — key: lowercased `resourceClass`; entry
  `{x, y, width, height, edge: "left"|"right", offsetPx, expanded, screenName}`.
- `DOCK_OFFSET_PX = readDockOffset()` + `readDockOffset()`: `parseInt(readConfig(
  "dockOffsetPx", 24))`, NaN → 24, <1 → 1 (spec error handling).
- `isDockedClass(cls)` — the shared predicate for precedence gates.
- `dockable(win)` — gate: null, `minimized`, `maximized`, `fullScreen`/`fullscreen`
  (per T0), shell skip-list `{plasmashell, systemsettings, ksmserver,
  plasmawindowed}` (same literals as config-helper.sh). Tiled windows **pass**
  (visual detile, documented).
- `dockScreenFor(win)` — center-of-frameGeometry containment over
  `workspace.screens[i].geometry`; nearest-screen fallback; `null` → clean abort
  (no `Qt` namespace, no QPoint).
- `parkRectFor(win, screen, edge)` — size+`y` preserved:
  left: `x = screen.x + offset − win.width`; right:
  `x = screen.x + screen.width − offset`.
- `moveDocked(win, rect)` — the skip-flag schedule (§7): set the three skip flags,
  assign `frameGeometry = {…}`, clear the flags (spec: docked windows stay visible in
  taskbar/pager/switcher in both states). Sole geometry-mutation path for dock.
- `outputKey(output)` — `output.name` or geometry-string fallback.

**Depends on:** T0 (items 2, 3). **Verification:** `qdbus6 … isScriptLoaded` → true;
journal clean `[DropdownAny] loaded`; `readConfig` of a bogus `dockOffsetPx` falls
back to 24/1 via a temporary unit-ish console invocation if feasible; geometry math
spot-checked against a documented two-monitor example (design §4.2). **Rollback:**
remove the dock section; no other code touches these identifiers yet.

### A2 — Add lifecycle functions: `releaseDockEntry`, `expandDocked`, `redockDocked`, `dockWindow`, `releaseAllDocked`

**File:** `contents/code/main.js` — same dock section, after A1 helpers.

Implement (design §3.2, §5.1, §5.5):

- `dockWindow(edge)` — exact order: (1) `workspace.activeWindow` + class; (2) existing
  entry branch *first* (re-dock to requested edge, snapshot preserved, no gate); (3)
  `dockable()` gate → silent skip; (4) class-collision: release existing entry
  (restore); (5) snapshot `frameGeometry`; (6) `dockScreenFor` null → abort; (7) create
  entry (`edge`, current offset, `expanded=false`, `screenName`); (8) `moveDocked`.
- `releaseDockEntry(cls, restore)` — single exit point: delete entry, reset skip flags
  (hygiene), skip restore when minimized/maximized/fullscreen, guard restore by
  "snapshot center on any current screen" (`snapshotCenterOnAnyCurrentScreen` helper).
- `expandDocked(win, entry)` — flip `expanded=true` **before** `moveDocked(snapshot)`.
- `redockDocked(win, entry)` — flip `expanded=false`; `dockScreenFor` null →
  `releaseDockEntry(cls, false)`; else `moveDocked(parkRectFor(current geometry))`.
- `releaseAllDocked()` — iterate keys, restore every snapshot, clear tracker;
  idempotent no-op when empty; `osdNotify` with count (D12 precedent).

**Depends on:** A1. **Verification:** code review against design §5.1 order + spec
invariants (snapshot immutable; exactly-one removal path). First live check happens
with A3 (shortcut trigger). **Rollback:** remove functions; unreferenced by other
code.

### A3 — Register the 3 dock shortcuts + offset read + cheat-sheet rows

**File:** `contents/code/main.js` — with the fixed global shortcuts block (resize/
release/list, ~line 761) and `listConfiguredShortcuts` (~line 786).

Implement (design §5.1, §8.2):

- Three `registerShortcut` calls:
  `DropdownDockLeft` (id must equal kglobalshortcutsrc key, design §8.1) →
  `dockWindow("left")`; `DropdownDockRight` → `dockWindow("right")`;
  `DropdownDockReleaseAll` → `releaseAllDocked`. Shortcut strings read via
  `readConfig("dockLeftShortcut", "Ctrl+Shift+Left")`,
  `readConfig("dockRightShortcut", "Ctrl+Shift+Right")`,
  `readConfig("dockReleaseAllShortcut", "Ctrl+Shift+H")` with `|| default` guard.
- Three rows in the cheat-sheet OSD (dock left / dock right / release all).
- `dbg()` on dock/expand/re-dock instants.

**Depends on:** A2; fixes the four key names (`dockOffsetPx`, `dockLeftShortcut`,
`dockRightShortcut`, `dockReleaseAllShortcut`) that C1/C2 must mirror. **Verification:**
shortcuts listed via `qdbus6 org.kde.kglobalaccel /component/kwin … listAllShortcuts`;
`grep DropdownDock ~/.config/kglobalshortcutsrc` (after C2 write); journal has no
registration errors; `Ctrl+Shift+H` with nothing docked is a no-op. **Rollback:**
remove the three registrations (entries persist in kglobalshortcutsrc until next
save — harmless leftovers, self-healing on save).

---

## Area B — `contents/code/main.js`: handlers + precedence gates

### B1 — `windowActivated` expand/re-dock sweep (single handler)

**File:** `contents/code/main.js` — dock section (IIFE top-level, after A2).

Single `workspace.windowActivated.connect(function (activeWin) {…})` iterating
`dockedWindows`: `win === activeWin` → expand only when parked + still plain
(`!minimized && !maximized && !fullScreen` — spelling per A1); else if `entry.expanded`
→ release (no geometry mutation) when window became minimized/maximized/fullscreen,
else re-dock. `activeWin === null` (desktop) must re-dock. No
`workspace.activeWindow = win` on expand (D8). At most one transition per entry per
emission (no oscillation — flags flip synchronously before each move).

**Depends on:** A1, A2. **Verification:** journal dbg lines show expand on sliver
click, re-dock on Alt+Tab away; no frame-fight between expand and re-dock on rapid
click-away/click-back. **Rollback:** disconnect or remove the connect block.

### B2 — `windowRemoved` dock cleanup

**File:** `contents/code/main.js` — near existing `windowRemoved` handler (~line 606)
or in dock section.

`workspace.windowRemoved.connect` → lowercase class; if in `dockedWindows`, call
`releaseDockEntry(cls, false)` (delete only, no geometry action — spec: closed window
never moves a surviving sibling).

**Depends on:** A1. **Verification:** dock then close the app; `Object.keys`-style
journal probe shows no stale entry; no geometry call fired. **Rollback:** remove
connect block.

### B3 — `screensChanged` monitor-removal / resolution-drift handler

**File:** `contents/code/main.js` — dock section.

Per design §5.4: build current `outputKey → true` set; stored `entry.screenName`
missing → guarded restore + release; still-present screen + non-expanded entry →
re-park if sliver invariant broke (`parkRectFor` x/y mismatch); `dockScreenFor` null →
restore + release. If T0 shows `screensChanged` unavailable, register instead a lazy
validation inside B1's sweep (same semantics, later cleanup).

**Depends on:** A1, A2, T0 (item 1). **Verification:** dock on monitor A, disconnect A
→ window restored (guarded) + entry cleared, journal clean; resolution change on the
surviving monitor re-parks quietly without releasing. **Rollback:** remove connect
block / fallback branch.

### B4 — Precedence gates in existing handlers (5 sites)

**File:** `contents/code/main.js` — `toggleWindow` (~line 307), `toggleTile` (~line
426), autoHide handlers at temp (~line 560), regular (~line 587), tile (~line 656).

Insert `isDockedClass(...)` skip-gates (design §6.2):

1. `toggleWindow`: after resolving `win`, before hide/show branches → skip.
2. `toggleTile`: before hide/show branches when `tile.classLeft` or `classRight` is
   docked → skip.
3. Three autoHide blur branches: skip `hideWindow`/`hideTile` when the resolved
   class(es) are docked.

Also: expanded docked window resize via `resizeActive` stays **allowed** (D9 — no
edit needed, document in code comment). No changes to `releaseTempSlot` (dock is
orthogonal).

**Depends on:** A1 (`isDockedClass`). **Verification:** spec scenario — autoHide-class
window docked + blur → re-docks, never hides; slot/tile toggles while docked are
no-ops; after release-all, autoHide behavior resumes on next blur. **Rollback:**
remove the inserted guards; dock remains functional but double-management returns.

---

## Area C — config-helper.sh + ConfigEditor.qml (global offset + 3 shortcuts)

Key-name contract (fixed by A3, must match exactly): `dockOffsetPx`,
`dockLeftShortcut`, `dockRightShortcut`, `dockReleaseAllShortcut` (kwinrc group
`Script-plasma-dropdown-any`); kglobalshortcutsrc keys `DropdownDockLeft` /
`DropdownDockRight` / `DropdownDockReleaseAll` under `[kwin]`. `main.xml` is **not
touched** (design §8.5).

### C1 — config-helper.sh: `cmd_load` emits the four dock keys

**File:** `plasmoid/contents/code/config-helper.sh` — `cmd_load` python block (four
reads near the fixed-shortcut reads ~line 130; emit near the JSON payload ~line 190).

Add `dock_offset_px = to_int(kread("dockOffsetPx", "24"), 24)` and the three shortcut
reads with the A3 defaults; include `dockOffsetPx`, `dockLeftShortcut`,
`dockRightShortcut`, `dockReleaseAllShortcut` in the printed JSON.

**Depends on:** A3 key names. **Verification:** `bash -n
plasmoid/contents/code/config-helper.sh`; `bash config-helper.sh load | python3 -m json.tool` shows the four keys with defaults when kwinrc has none. **Rollback:**
revert the read block — load JSON just omits the keys (QML falls back to defaults).

### C2 — config-helper.sh: `cmd_save` writes the three global shortcuts + offset

**File:** `plasmoid/contents/code/config-helper.sh` — `global_shortcuts` dict (~line
315) and the shortcut-write loop, plus one `kwrite` for the offset.

Extend `global_shortcuts` with:
`"dockLeftShortcut": ("DropdownDockLeft", "Ctrl+Shift+Left", "Dropdown Any: Dock focused window to left edge")`,
`"dockRightShortcut": ("DropdownDockRight", "Ctrl+Shift+Right", "Dropdown Any: Dock focused window to right edge")`,
`"dockReleaseAllShortcut": ("DropdownDockReleaseAll", "Ctrl+Shift+H", "Dropdown Any: Release all docked windows")`,
and add `kwrite("--file","kwinrc","--group",kwin_group,"--key","dockOffsetPx",
str(data.get("dockOffsetPx", 24)))`.

**Depends on:** C1, A3 (object names must match `registerShortcut` first arguments).
**Verification:** `bash -n`; one save round-trip then `grep DropdownDock
~/.config/kglobalshortcutsrc` shows all three `key,default,description` entries and
`dockOffsetPx` in kwinrc. **Rollback:** drop the dict entries + kwrite; stale
shortcut entries in kglobalshortcutsrc are inert until re-registered.

### C3 — ConfigEditor.qml: properties, `_onLoad`, `_buildConfig`

**File:** `plasmoid/contents/ui/ConfigEditor.qml` — properties block (~line 47),
`_onLoad` (~line 119), `_buildConfig` (~line 332).

- 4 properties: `property int dockOffsetPx: 24` + three string properties with A3
  defaults.
- `_onLoad`: assign from `data` with same defaults (int-guard `!== undefined` pattern).
- `_buildConfig`: add the four keys to the JSON payload.

**Depends on:** C1 (JSON keys). **Verification:** load round-trip survives a save
with no key loss (apply then re-open settings); dirty flag set on edits. **Rollback:**
revert the three blocks — QML keeps defaults, save payload omits keys (C2 defaults).

### C4 — ConfigEditor.qml: three rows in the Global shortcuts Repeater

**File:** `plasmoid/contents/ui/ConfigEditor.qml` — Global shortcuts Repeater model
(~line 1550).

Add rows: `Dock focused window to left edge → dockLeftShortcut`,
`Dock focused window to right edge → dockRightShortcut`,
`Release all docked windows → dockReleaseAllShortcut`. Delegate already binds
`root[modelData.prop]` with `checkForConflictsAgainst: 2` (GlobalShortcuts) — no
delegate change expected.

**Depends on:** C3. **Verification:** the three rows render in the widget with correct
defaults; a deliberately conflicting binding surfaces the existing conflict UI.
**Rollback:** remove the three model entries.

### C5 — ConfigEditor.qml: Dock card with offset SpinBox + hint

**File:** `plasmoid/contents/ui/ConfigEditor.qml` — insert after the Global shortcuts
card (~line 1588), before Developer options.

New `Kirigami.Card` "Dock": `Controls.SpinBox` for `dockOffsetPx` (from 1, stepSize 4,
`px` suffix, `onValueModified → root.dockOffsetPx = value; dirty = true`) plus hint
label: applies to any focused window; minimized/maximized/fullscreen and panel windows
skipped; Ctrl+Shift+Left/Right may collide with in-app shortcuts — remap in System
Settings → Shortcuts if a second registration loses; offset applies on script reload
(save already reloads).

**Depends on:** C3. **Verification:** set 48, Apply, dock → 48px sliver (spec
scenario); value survives reload round-trip. **Rollback:** remove the card.

---

## Area D — README

### D1 — README Dock section

**File:** `README.md` — new `## Dock` section after the "Live resize shortcuts"
subsection (before "Finding a window's resource class"); also extend the "Known
Plasma 6 gotchas" table if T0 found real collisions.

Content: feature summary (any focused window, own-screen edges, sliver offset default
24px editable in the widget); the three shortcuts with defaults + "editable in System
Settings → Shortcuts / widget Global shortcuts" note; precedence summary (skip:
minimized/maximized/fullscreen/panel; tiled visually detiles, state persists;
autoHide/temp/tile handlers skip docked windows); expand-on-click / re-dock-on-blur
interaction; release-all (`Ctrl+Shift+H`) restores snapshots; animation via existing
slide effect (skipSwitcher fallback for non-managed classes); conflict tradeoff wording
grounded in T0 item 5.

**Depends on:** T0 (item 5), area C (final shortcut keys). **Verification:** render
check — headings unique, shortcut table matches A3/C2 defaults, no stale claims.
**Rollback:** remove the section + table row.

---

## Area E — Apply-phase verification (single work unit, after apply)

### V1 — Static + install checks

`bash -n plasmoid/contents/code/config-helper.sh`; `bash install.sh script plasmoid`
per install.sh; `kwin6 --replace`; journal `[DropdownAny] loaded` with no JS errors.

### V2 — Functional smoke (design V4–V16, condensed)

- Dock left/right on single + multi-monitor (own-screen edge; size unchanged; 24px
  sliver; nothing on neighbor monitor).
- Sliver click → expand to snapshot; Alt+Tab away → re-dock same edge/offset; both
  animate.
- Drift: move expanded window, blur → re-park from current geometry, snapshot intact.
- `Ctrl+Shift+H` with parked + expanded + drifted → all restored, tracker empty,
  second press is a no-op; OSD count shown.
- Offset 48 in widget, Apply, dock → 48px sliver.
- Precedence: autoHide-class docked + blur → re-dock (not hide); temp/tile toggles
  while docked → no-ops; minimized/maximized/fullscreen/plasmashell at dock time →
  no-op; tiled window docks + visually detiles.
- Cleanup: close docked window → no stale entry; dock on monitor A, disconnect A →
  guarded restore + release; second same-class window docked → first restored.
- Non-managed class dock → animated via skipSwitcher fallback; effect package
  untouched (`git diff --name-only effect/` empty).
- KGlobalAccel: remap one dock shortcut in System Settings → new binding docks, old
  inert; collision set documented (T0 item 5).

### V3 — Rollback drill

`Ctrl+Shift+H`; `kwin6 --replace`; verify all windows restored, no lingering skip
flags; revert option documented per area rollback notes; `bash uninstall.sh
--keep-config` + reinstall leaves no stale dock entries.

**Depends on:** all areas. Deliverable: verification report per design §11 table.

---

## Rollback summary by work unit

| Work unit | Rollback |
| --- | --- |
| A1–A3 (main.js core) | Remove dock section + 3 registrations; `Ctrl+Shift+H` restores any parked window before unload; KWin reload wipes runtime tracker (parked windows keep geometry, untracked — documented) |
| B1–B4 (handlers/gates) | Remove connect blocks + guards; no behavior change for existing states |
| C1–C5 (config/QML) | Revert helper dict/reads + QML blocks; additive kwinrc defaults only; stale kglobalshortcutsrc entries inert until re-registered |
| D1 (README) | Remove section |
| Whole change | Revert main.js dock section + helper/QML additions (rollback section of proposal.md); `kwin6 --replace` smoke confirms restoration |
