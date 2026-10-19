# Apply Progress — dockit (PR 1/3: main.js dock core + PR 2/3: config surface + PR 3/3: README docs)

Change: `dockit` | Phase: apply | Work units: PR 1 — `contents/code/main.js` (areas A + B); PR 2 — `config-helper.sh` + `ConfigEditor.qml` (area C); PR 3 — `README.md` (area D, D1)
Delivery: ask-on-risk → resolved by orchestrator: **Chained PRs**, `chain_strategy=stacked-to-main`, `review_budget=400`.
Workload gate: `Decision needed before apply: Yes` → resolved by parent prompt (chained PRs chosen). `400-line budget risk: High` → contained: PR 1 = 370 added / 0 deleted lines; PR 2 = **91 added / 3 deleted lines** (< 400); PR 3 = **22 added / 0 deleted lines**. Chained PRs recommended: Yes → PR 3 (README) applied below (final stacked-to-main PR).

## PR 3 — README Dock section (area D · D1)

| Task | Status | Verification |
| --- | --- | --- |
| D1 — README `## Dock` section after the "Live resize shortcuts" subsection, before "Finding a window's resource class" | Done | headings unique (no duplicate `^#{1,6}` titles — scan below); shortcut table matches PR1 A3 / PR2 C2 key-name contract exactly (`Ctrl+Shift+Left` / `Ctrl+Shift+Right` / `Ctrl+Shift+H`, mirroring `DropdownDockLeft/Right/ReleaseAll` registrations and config-helper JSON keys); `git diff --check` clean; diff touches **only** `README.md` (+22 / −0) |

Files changed (PR 3): `README.md` (+22 / −0). Untouched: `contents/code/main.js`, `config-helper.sh`, `ConfigEditor.qml`, `effect/`, `contents/config/main.xml`.

Content coverage vs D1 spec (all present):

- **Summary** — any focused window docked to its own screen's left/right edge; size kept; 24 px default sliver, editable (1–400) in the widget's **Dock** card, read on script load (applies on reload — matches C5 hint wording).
- **Shortcut table** — 3 rows with defaults; note that all three are KWin global shortcuts, re-bindable in the widget's **Global shortcuts** section (same list as live-resize) or **System Settings → Shortcuts → KWin**.
- **Precedence** — skip minimized/maximized/fullscreen + panel/shell windows (`plasmashell`, System Settings, `ksmserver`); tiled windows dock (visual detile, tiling state persists); autoHide/temp-slot/tile-pair toggles skip docked windows.
- **Interaction** — click sliver (activation) → expand to pre-dock snapshot; blur → re-dock to same edge from current geometry; `Ctrl+Shift+H` release-all restores each snapshot's position+size; second press with nothing docked = no-op.
- **Animation** — dock/expand/re-dock use the same skip-flag schedule as the show/hide path; non-`ManagedClasses` windows animate via the bundled effect's `skipSwitcher` fallback (same mechanism as temporary slots — wording matches effect/contents/code/main.js header).
- **Collision / remap hint** — inline note grounded in T0 item 5: `Ctrl+Shift+Left/Right` overlap editors'/terminals' in-app "select/move by word" (an app-level overlap, not a KGlobalAccel one) → remap hint to a `Meta`-based combo.

**Known Plasma 6 gotchas table NOT extended** — decided per the D1 gate "extend the table if T0 found real collisions". T0 item 5 found **no** real KGlobalAccel collisions on the target install (kglobalshortcutsrc has no primary bindings for the three defaults; only `Meta+Ctrl+Shift+Left/Right` desktop moves exist), so the condition is false. The editor/terminal word-selection overlap is an in-app binding overlap and is documented inline in the Dock section instead of as a platform-gotcha row.

## PR 3 verification evidence (strict_tdd declared, testing.enabled=false → manual evidence; docs-only, no code surfaces)

Commands run this apply: `grep -cE '^#{1,6} ' + sort | uniq -d` → no duplicate headings; `sed` extract of the Dock block → table rows read `Ctrl+Shift+Left/Right/H` with the A3/C2 action descriptions; `git diff --check` clean; `git diff --stat` → README only. No node/bash/qmllint surfaces apply (no JS/shell/QML touched).

## Deviations / notes (PR 3)

- **Document-outline note (flagged, not fixed):** the two `###` subsections that follow the inserted `## Dock` heading — "Finding a window's resource class" and "Manual config via terminal" — now sit under `## Dock` in a document outline until the next `##` (`## Behavior`). Placement and `##` level were taken verbatim from tasks.md D1 and the delivery brief ("`## Dock` section after 'Live resize shortcuts', before 'Finding a window's resource class'"). If the reviewer prefers those Configuration subsections to remain nested under `## Configuration`, the fix is a one-line relocation of the Dock heading below "Manual config via terminal" (or demoting Dock to `###`) — kept out of this PR to stay exactly per spec.
- Gotchas table extension intentionally omitted (rationale above).

## PR 3 → verify hand-off

Docs PR (D1) is content-complete; the README section's live claims (sliver click → activation expand on Wayland, effect animation via `skipSwitcher`) are scheduled for the verify smoke exactly as listed in tasks.md D1's Depends-on. See the cumulative `## Remaining work` section at the bottom for the V1–V3 matrix.

## PR 2 — config surface (area C), contract PR1 key names

| Task | Status | Verification |
| --- | --- | --- |
| C1 — `cmd_load` emits the 4 dock keys | Done | `bash -n` OK; `config-helper.sh load` JSON parsed with `dockOffsetPx:24`, `dockLeftShortcut:Ctrl+Shift+Left`, `dockRightShortcut:Ctrl+Shift+Right`, `dockReleaseAllShortcut:Ctrl+Shift+H` when kwinrc has none |
| C2 — `cmd_save` writes 3 global shortcuts + offset | Done | temp-XDG round-trip: kglobalshortcutsrc `[kwin]` gets `DropdownDockLeft/Right/ReleaseAll=…,none,description`; kwinrc gets `dockLeftShortcut/dockRightShortcut/dockReleaseAllShortcut` + `dockOffsetPx=48`; `load` round-trips the saved values (48 / Ctrl+Alt+Left) |
| C3 — ConfigEditor.qml properties / `_onLoad` / `_buildConfig` | Done | 4 properties added; `_onLoad` uses int-guard `!== undefined` (offset) + ` | | default` (shortcuts); `_buildConfig` payload includes all 4 keys; `qmllint` clean |
| C4 — Global shortcuts Repeater: 3 dock rows | Done | Rows `Dock focused window to left/right edge` + `Release all docked windows`; delegate binds `root[modelData.prop]` + `checkForConflictsAgainst: 2` unmodified; `qmllint` clean |
| C5 — Dock card with SpinBox + hint | Done | `Controls.SpinBox` from 1, stepSize 4, max 400, `px` suffix, `onValueModified → root.dockOffsetPx = value; dirty = true`; hint label (skipped window classes, collision remap note, applies on reload); `qmllint` clean |

Files changed (PR 2): `plasmoid/contents/code/config-helper.sh` (+20 / −3), `plasmoid/contents/ui/ConfigEditor.qml` (+74 / −0) = 91 changed lines. Untouched: `contents/code/main.js`, `README.md`, `contents/config/main.xml`, `effect/`.

Key-name re-check against PR 1 (must mirror exactly): main.js `readConfig("dockOffsetPx", 24)`, `readConfig("dockLeftShortcut", "Ctrl+Shift+Left")`, `readConfig("dockRightShortcut", …)`, `readConfig("dockReleaseAllShortcut", …)`, `registerShortcut("DropdownDockLeft"…)` / `DropdownDockRight` / `DropdownDockReleaseAll` — all confirmed to match the helper's load JSON keys, save kwinrc keys, and kglobalshortcutsrc object names (grep + round-trip).

Static verification summary (this apply): `bash -n plasmoid/contents/code/config-helper.sh` OK; both embedded Python blocks `py_compile`-clean; `qmllint plasmoid/contents/ui/ConfigEditor.qml` exit 0; `git diff --check` clean. No live KWin mutation performed (config files written only to a temp `XDG_CONFIG_HOME` sandbox for the round-trip test).

## Deviations from design (PR 2, documented)

- **Dock card indentation** (C5): the inserted card block sits 4 spaces deeper than sibling cards in the QML source. QML ignores indentation; internally consistent; `qmllint` clean. Cosmetic only. (edit tool normalization prevented a pure-dedent pass.)
- **SpinBox `to: 400`** (C5): design/tasks specify `from: 1, stepSize 4` without an upper bound; picked max 400 px as a sane sanity cap (main.js clamps only <1 at runtime; an absurd offset would just leave a wider sliver). Reviewer may want the cap documented in the hint.

## PR 2 TDD Cycle Evidence (strict_tdd declared, testing.enabled=false → per tasks.md conventions, manual smoke replaces RED/GREEN)

PR 2 RED-equivalent = key-name contract from A3 + round-trip expectations; GREEN evidence: temp-sandbox `save` → grep kglobalshortcutsrc/kwinrc → `load` round-trip (values survive); `bash -n`, `py_compile` of both heredocs, `qmllint` exit 0, `git diff --check` clean. Live widget dirty-flag/conflict-UI behavior deferred to verify phase (V-render), as no plasmoid session exists in the apply environment.

## Scope delivered (tasks.md areas T0 + A + B)

| Task | Status | Verification |
| --- | --- | --- |
| T0 — KWin 6 API spike (6 unknowns) | Done (5 resolved statically/live, 3 hedged, live re-check deferred to verify) | see T0 findings below |
| A1 — `dockedWindows` tracker + `DOCK_OFFSET_PX`, `readDockOffset`, `isDockedClass`, `dockable`, `dockScreenFor`, `parkRectFor`, `moveDocked`, `outputKey` (+ `isFullScreenWindow`, `snapshotCenterOnAnyCurrentScreen`) | Done | node --check; mock-harness geometry math |
| A2 — `dockWindow` (design §5.1 order), `releaseDockEntry`, `expandDocked`, `redockDocked`, `releaseAllDocked` (osdNotify + idempotent no-op) | Done | mock harness: dock/expand/re-dock/drift/release/close |
| A3 — `DropdownDockLeft/Right/ReleaseAll` via `registerShortcut` + `readConfig` defaults `Ctrl+Shift+Left/Right/H`; cheat-sheet rows; `dbg()` on dock/expand/re-dock | Done | harness assert on registration defaults + cheat-sheet OSD payload |
| B1 — single `windowActivated` expand/re-dock sweep (no `workspace.activeWindow = win`, no oscillation) | Done | harness: expand on activation, re-dock on blur/null, single transition per emission |
| B2 — `windowRemoved` cleanup (`releaseDockEntry(cls, false)`) | Done | harness: no geometry mutation, tracker cleaned |
| B3 — `screensChanged` handler with lazy fallback (T0 hedge) | Done | harness: monitor-removal releases entry + guarded restore refuses dead coordinates |
| B4 — precedence gates at 5 sites (toggleWindow, toggleTile, 3 autoHide handlers) via `isDockedClass` | Done | harness: autoHide skips docked window; slot toggle no-op; hand-off resumes after release-all |

Files changed (PR 1): `contents/code/main.js` (+370 / −0). Untouched: `config-helper.sh`, `ConfigEditor.qml`, `README.md`, `contents/config/main.xml`, `effect/`.

## T0 spike findings (recorded in main.js dock-section comment)

1. **`workspace.screensChanged`** — live probe via `loadScript` (config-helper.sh technique) was **inert** in the spike session (KWin 6.7.4): script reported loaded (`isScriptLoaded=true`) but produced no journal output and no `writeConfig`/klipper/OSD side effects across multiple channel attempts. Resolution: the design's hedge is implemented — `dockScreensChangedAvailable = !!(workspace.screensChanged && workspace.screensChanged.connect)`; when unavailable, a lazy per-activation validation runs inside the sweep (proven working in the mock harness). Live confirm at verify smoke.
2. **Output identity** — `outputKey()` prefers `output.name`, falls back to `g.x,g.y,width,height` string. `.name` availability live-check deferred (hedge is load-bearing).
3. **fullScreen spelling** — KWin 6 `Window` exposes `fullScreen`; code hedges both spellings via `isFullScreenWindow()` (harness exercised the `fullScreen=true` path).
4. **skipSwitcher timing** — **verified statically**: `effect/contents/code/main.js` `onWindowFrameGeometryChanged` reads `window.skipSwitcher` at geometry-change-signal time; `moveDocked`'s set→move→clear mirrors the production `toggleWindow` show path, which the live session journal confirms runs animated (`[DropdownAny] auto/shortcut hide/show` lines observed during the spike).
5. **KGlobalAccel collisions** — **verified live**: `~/.config/kglobalshortcutsrc` has no primary bindings for `Ctrl+Shift+Left` / `Ctrl+Shift+Right` / `Ctrl+Shift+H` (only `Meta+Ctrl+Shift+Left/Right` desktop moves exist) → defaults are unclaimed on the target install. README conflict wording deferred to PR3 (D1).
6. **Wayland windowActivated** — same `activeWin === win` idiom as the three production autoHide handlers; live click-sliver confirm deferred to verify smoke V6/V15 (hedge: design relies on this pattern already being proven).

## TDD Cycle Evidence (strict_tdd declared, testing.enabled=false → per tasks.md conventions, manual smoke replaces RED/GREEN)

No formal runner exists. Evidence per task (all commands executed this apply):

| Task | RED-equivalent (expected behavior) | GREEN evidence (observed) |
| --- | --- | --- |
| A1/A2 (core) | Geometry math must satisfy design §4.2 + spec scenarios | `node --check contents/code/main.js` OK; mock-harness `dockit-smoke2.js`: 19/19 (dock left/right math incl. own-screen multi-monitor, expand, re-dock w/ drift, snapshot immutability, release-all restore + idempotent, close cleanup, monitor-removal guarded release) |
| A3 (shortcuts) | Three shortcuts registered; cheat-sheet rows rendered | harness asserts `DropdownDockLeft/Right/ReleaseAll` defaults; `dockit-cheatsheet-smoke.js`: 4/4 (rows present with `Ctrl+Shift+Left/Right/H`, existing globals intact) |
| B1–B3 (handlers) | Single-transition sweep; cleanup paths | covered in `dockit-smoke2.js` (19/19) incl. `activeWin === null` re-dock, lazy screensChanged fallback cleanup |
| B4 (gates) | autoHide/slot handlers skip docked windows; hand-off resumes after release | `dockit-b4-smoke.js`: 6/6 (autoHide blur leaves window parked, no skip flags; slot toggle while docked is a no-op; after release-all autoHide hides again) |
| Static | — | `git diff --check contents/code/main.js` clean; `node --check` clean ×N |

Partial smoke V2 = the three node harnesses above (main.js only, mock KWin API). Full journal/install smoke (`[DropdownAny] loaded`, kpackagetool6, `kwin6 --replace`) is intentionally left to the verify phase — installing/mutating the live KWin is outside this PR's allowed edit surfaces.

## Deviations from design (documented)

- **`parkRectFor` signature**: takes optional 4th param `offsetPx` (entry-captured; defaults to `DOCK_OFFSET_PX`). Design §5.2 snippet calls it with 3 args; entry.offsetPx (§3.1) and spec "same edge and offset" require the captured value — both call shapes valid.
- **toggleTile gate placement**: inserted after `lastActivated = { type: "tile", … }` and before the hide/show branches (design §6.2 says "before the hide/show branches"; `lastActivated` is set but unused when the gate fires — harmless).
- **T0 items 1/2/6 not conclusively live-proven** in the spike session (DBus scripting probe inert); implemented exactly the designed hedges. This is the tasks.md-sanctioned posture ("fallbacks designed for each"); live re-check scheduled in verify smoke.
- **No live KWin mutation performed during apply** (no install / `kwin6 --replace` / kglobalshortcutsrc writes): those are verify-phase actions and out of the allowed edit surfaces.

## Key-name contract fixed for PR2 (must mirror exactly)

`dockOffsetPx` (kwinrc `[Script-plasma-dropdown-any]`, default 24), `dockLeftShortcut` / `dockRightShortcut` / `dockReleaseAllShortcut` (same group; defaults `Ctrl+Shift+Left` / `Ctrl+Shift+Right` / `Ctrl+Shift+H`); kglobalshortcutsrc `[kwin]` ids `DropdownDockLeft` / `DropdownDockRight` / `DropdownDockReleaseAll` (registerShortcut first args match). `main.xml` not touched (design §8.5).

## Rollback (work unit A/C-prereq)

- PR 1: remove the dock section + 3 registrations + 5 gates from `contents/code/main.js` (single revert of that diff).
- PR 2 (area C already applied): revert `config-helper.sh` load reads/JSON keys + save dict entries/`dockOffsetPx` kwrite and the QML blocks; additive kwinrc defaults only; stale `DropdownDock*` entries in kglobalshortcutsrc are inert until the script re-registers them (self-healing on next save).

## Remaining work (PR 1–3 all applied — only verify phase left)

- Verify phase: V1–V3 matrix (install, `kwin6 --replace`, journal `[DropdownAny] loaded`, live dock/expand/re-dock/release cycle, KGlobalAccel remap, offset change on reload, widget render + dirty flag + conflict UI).

## Post-verify amendment — expand requires an intentional click

**User report (verbatim, this session):** "Se esta activando hay veces cuando cambio de workspace, que solo se active cuando se presione click" — preceded by: "cuando una app esta activa en todos lo escritorio y esta oculta, cuando paso a un workspace sin ventanas, se esta activando sola".

**Cause.** The B1 sweep expanded on *any* activation of the parked window. KWin focuses the topmost window of the desktop it lands on, so a desktop switch activates an `onAllDesktops` parked dock on its own and the dock popped out. A first attempt (debounce on `currentDesktopChanged`/`currentDesktopChanging` + `workspace.cursorPos` hit-test) was installed live on 2026-09-07 11:03 and the report repeated afterwards, so the sweep now gates expansion on three conditions, checked in this order inside `win === activeWin`:

1. **Parked desktop match** (`currentDesktopKey()` vs `entry.parkedDesktop`, set at dock time, re-armed in `redockDocked()` and in `dockWindow()`'s already-docked branch): an activation arriving while the current desktop differs from the parked one is the switch itself — the entry re-arms to the new desktop and stays parked. Time-scoped to keep it from swallowing a real click: it only rejects when no desktop-change signal has ever fired in this session (the build that can never catch the switch) or when one fired in the preceding 500 ms. Signal- and timing-independent fallback, deliberate trade: without any signal evidence the first click after a switch is consumed, which is better than the dock popping out on every switch.
2. **Desktop-switch debounce** (500 ms timestamp on `currentDesktopChanged`/`currentDesktopChanging`, both hedged): catches the same event burst when the signal exists.
3. **Sliver hit-test** (`cursorOverSliver(win, entry)`): the pointer must be inside the parked sliver rectangle; `null` (no `workspace.cursorPos`) degrades to the two guards above instead of making the dock impossible to expand.

Each rejected activation logs a distinct `dbg()` line (`activated by desktop switch` / `desktop switch debounce` / `cursor not over sliver`), so a live session with `debugMode=true` identifies which gate fired.

**Documented consequence.** After a desktop switch the parked window can already be the active one, and a click on an already-active window produces no activation event — click anywhere else first, then grab the sliver. README's Interaction bullet states this.

**Spec.** `specs/dock/spec.md`: requirement renamed to "Expand on Intentional Activation and Re-dock on Blur", three new scenarios (desktop switch, activation away from the sliver, click after a switch), and the "No new input plumbing" business rule amended to describe the gates. No timers or polling were added (`Date.now()` at event time only, per `agents.md`).

**Re-run before closing.** Verify smoke V6/V15 (click-sliver expand, Wayland activation) plus a new desktop-switch check: dock a window, switch to an empty desktop with the pointer parked over the sliver, and confirm it stays parked.

**Inline harness evidence (scratch, never committed — `/tmp/dockit-guards-UupY/`).** No runner exists in this repo, so `contents/code/main.js` was loaded in Node under a mock KWin environment (mocked `workspace`, `readConfig`, `registerShortcut`, `callDBus`, and a controllable `Date.now()`), driving the registered dock shortcuts and the captured `windowActivated` handler:

| Harness | Coverage | Result |
| --- | --- | --- |
| `harness.js` (desktop-change signals present) | park left/right (+ sliver math both edges), click-expand, blur→re-dock, switch debounce, quiet-switch first click, cursor outside the sliver, shortcut re-dock re-arm, minimized no-expand, other-window activation, release-all restore ×3 | 24/24 PASS |
| `harness2.js` (neither `currentDesktopChanged` nor `currentDesktopChanging` exists) | park, switch activation stays parked via the parked-desktop fallback, click after the switch expands, second switch, click again | 8/8 PASS |

Two defects the harness caught and this change fixes:

- **False skip on a quiet switch.** With the parked-desktop comparison unconditional, docking on desktop A, switching to a busy desktop B (no auto-activation) and then clicking the sliver had `parkedDesktop` still A → the first click was swallowed. Fixed by time-scoping guard 1 as described above; `harness.js` S6 pins it.
- **Stale parked desktop after a shortcut re-dock.** `dockWindow()`'s already-docked branch re-parked the window without updating `parkedDesktop`, so a shortcut re-dock on a new desktop also ate the next click. Fixed; `harness.js` S10 pins it.

**Still only provable live:** whether KWin emits `windowActivated` when the user clicks an already-active parked window (it does not for an already-active window in KWin's activation path), and whether the desktop-change signals actually fire on KWin 6.7.4 — the harness covers both branches of that hedge, but not which one the live session takes.

## Delivery slice boundary (feat/dockit vs origin/master)

| Commit | Subject | Changed lines |
| --- | --- | --- |
| `682374e` | feat(dockit): dock lateral con sliver, hover expand y slide desde borde | 3554 insertions / 207 deletions (15 files) |
| `b79efa4` | feat(dockit): dock animation selector + hover discarded | 124 / 115 (3 files) |
| `b44446a` | fix(dock): expand only on an intentional sliver click | 189 / 8 (4 files) |

The dock feature landed in one 3554-line commit, far past the ~400-line review slice. `682374e` is the slice boundary that needs a delivery decision before any further commit on this branch: either split it into the PR1/PR2/PR3 work units the design already describes (main.js dock section + gates / config + widget / verify-phase docs), or accept it as a single reviewed unit. Nothing was pushed for `b44446a`; `origin/feat/dockit` still points at `b79efa4`.

## Live smoke — desktop-switch gate confirmed

After the copy-install + D-Bus reload of the final `main.js` (`cmp` identical to `HEAD`), the user reproduced the original scenario on the live KWin 6.7.4 session and reported (verbatim): "Listo quedo bien". The parked dock no longer expands when switching workspaces, and the sliver click still expands it. V6/V15 and the desktop-switch check above are therefore satisfied live; the remaining verify-phase items (KGlobalAccel remap, offset change on reload, widget render) were already covered by the earlier verify report.
