---
change: dockit
phase: verify
status: pass
archived: 2026-10-19
---

# Verify Report — dockit (MVP)

Status: **PASS** (headless). No blockers. Several WARNINGs documented below (none
blocking; all are evidence-quality / boundary-attribution / cosmetic).

Change: dockit — standalone dock state machine (park focused window at its own
screen's left/right edge, `dockOffsetPx` sliver, expand-on-activation /
re-dock-on-blur, release-all), plus config surface (`config-helper.sh` +
`ConfigEditor.qml`) and README docs. Delivered as a stacked-to-main 3-PR chain
applied to the working tree (not committed).

Specs: 8 requirements / 20 scenarios (`specs/dock/spec.md`). Design: `design.md`
(§3–§13). Tasks: `tasks.md` (areas T0 + A + B + C + D + E). Testing: `testing.enabled:
false` → verification is per-repo-policy manual smoke (tasks Area E, design §11). No
runner exists; headless mock harnesses used for the functional smoke.

---

## 1. Spec coverage

All 8 requirements map to implemented code; the 20 scenarios are covered by mock
harness assertions or are explicitly scheduled for a live-KWin session (headless
environment cannot exercise them). No requirement is unimplemented.

| Req | Implementation | Evidence |
| --- | --- | --- |
| Dock focused window to screen edge | `dockWindow` (step 2 re-dock / gate / collision / snapshot / `dockScreenFor` / `moveDocked`), `parkRectFor`, `dockScreenFor` | smoke2: dock-left/right math, own-screen multi-monitor, re-dock edge switch, snapshot immutability |
| Expand on activation / re-dock on blur | `workspace.windowActivated` sweep → `expandDocked` / `redockDocked`; no oscillation (flags flip before move); no `activeWindow = win` (D8) | smoke2: expand→snapshot, re-dock after drift from current geometry |
| Release all docked windows | `releaseAllDocked` (idempotent, OSD count) + `releaseDockEntry(cls, true)` | smoke2: release-all restores snapshot, second press no-op |
| Configurable global shortcuts | 3 × `registerShortcut` (`DropdownDockLeft/Right/ReleaseAll`, defaults Ctrl+Shift+Left/Right/H) + cheat-sheet rows | cheatsheet harness 4/4; config round-trip |
| Configurable dock offset | `readDockOffset` (NaN→24, <1→1) + SpinBox (1–400) | config round-trip (offset 48); QML SpinBox from 1 |
| Isolated dock tracking | separate `dockedWindows` (class-keyed) + `isDockedClass` gates; cleanup via windowRemoved/screensChanged/class-collision/release-all | smoke2: close cleanup, monitor-removal guarded release, slot toggle no-op |
| Animated transitions via existing slide effect | `moveDocked` skip-flag schedule (set→move→clear), `skipSwitcher` fallback for non-managed classes | static confirm of effect `onWindowFrameGeometryChanged` reading skipSwitcher at signal time (T0 item 4) |
| Precedence — plain windows only | `dockable` gate (min/max/fullscreen/shell skip; tiled passes) + 5 `isDockedClass` gates (toggleWindow, toggleTile, 3 autoHide) | smoke2 (max/shell/fullscreen skip), b4 (autoHide/slot/tile skip + hand-off) |

---

## 2. Task completion

| Area | Task | Status |
| --- | --- | --- |
| T0 | KWin 6 API spike (6 unknowns) | Done — 5 resolved statically/live, 1/2/6 hedged with load-bearing fallbacks; live re-check deferred to KWin session |
| A1 | tracker + offset helpers + geometry | Done |
| A2 | lifecycle fns (`dockWindow`, `releaseDockEntry`, `expand/redock`, `releaseAll`) | Done |
| A3 | 3 shortcuts + offset read + cheat-sheet rows | Done |
| B1 | `windowActivated` expand/re-dock sweep | Done |
| B2 | `windowRemoved` cleanup | Done |
| B3 | `screensChanged` handler + lazy fallback | Done |
| B4 | 5 precedence gates | Done (all 5 sites verified present) |
| C1–C5 | config-helper load/save + QML properties/card/rows | Done (round-trip verified) |
| D1 | README Dock section | Done (headings unique) |
| E (V1–V3) | apply-phase smoke | V1 static PASS, V2 harness PASS (see §4), V3 rollback drill PASS (§5) |

---

## 3. V1 — Static checks (all PASS)

| Command | Result |
| --- | --- |
| `bash -n plasmoid/contents/code/config-helper.sh` | PASS (exit 0) |
| `node --check contents/code/main.js` | PASS (exit 0) |
| `qmllint plasmoid/contents/ui/ConfigEditor.qml` | PASS (exit 0) |
| `git diff --check` | clean (exit 0) |
| README unique headings (`^#{1,6}` scan) | no duplicates |
| apply-progress.md unique headings | no duplicates |
| Platform constraints in dock section (904–1577) | no `setTimeout` / `Qt.` / `exec(` / `activeWindow = win` in code (comment-only refs) |
| Non-goals untouched | `effect/`, `kcm/`, `contents/config/main.xml` → `git diff --name-only` empty |

**Key-name contract (cross-file, mirrors exactly):** `dockOffsetPx` (kwinrc
`[Script-plasma-dropdown-any]`, default 24), `dockLeftShortcut` / `dockRightShortcut` /
`dockReleaseAllShortcut` (defaults Ctrl+Shift+Left/Right/H), kglobalshortcutsrc `[kwin]`
ids `DropdownDockLeft` / `DropdownDockRight` / `DropdownDockReleaseAll` — confirmed
identical across `main.js` (`readConfig`/`registerShortcut`), `config-helper.sh`
(load reads + save dict entries + kglobalshortcutsrc write), and `ConfigEditor.qml`
(properties, `_onLoad`, `_buildConfig`, Repeater rows).

---

## 4. V2 — Functional smoke (headless; mock-harness + config sandbox)

Re-ran the apply-phase harnesses in `/tmp/dockit-*.js` (all read the real
`contents/code/main.js`):

| Harness | Result |
| --- | --- |
| `dockit-smoke2.js` (canonical PR1 core) | **19 passed / 0 failed** |
| `dockit-b4-smoke.js` (precedence gates) | **6 passed / 0 failed** |
| `dockit-cheatsheet-smoke.js` (A3 cheat-sheet rows) | **4 passed / 0 failed** |
| `dockit-smoke.js` (earlier draft) | 18 passed / 1 failed — see WARNING-1 |

**Config save→load round-trip** (temporary `XDG_CONFIG_HOME` sandbox, no live KWin
mutation):

- `load` with empty kwinrc → `dockOffsetPx:24`, three shortcuts = Ctrl+Shift+Left/Right/H.
- `save '{"slotCount":0,"dockOffsetPx":48,"dockLeftShortcut":"Meta+Ctrl+Left",…}'` →
  kwinrc `dockOffsetPx=48`, `dockLeftShortcut=Meta+Ctrl+Left`; kglobalshortcutsrc
  `[kwin]` gets `DropdownDockLeft=Meta+Ctrl+Left,none,Dropdown Any: Dock focused
  window to left edge` (+ Right / ReleaseAll).
- `load` after save → values round-trip (48 / Meta+Ctrl+Left / Ctrl+Shift+Right /
  Ctrl+Shift+H).
- Fresh-XDG missing-offset → fallback default 24 (PASS).

**Requires a live KWin session (cannot be run headless — documented, not performed):**

- `kwin6 --replace` + journal `[DropdownAny] loaded` with no JS errors (V1/V3).
- Real sliver-click → `windowActivated` with `activeWin === win` expand on Wayland
  (T0 item 6 — design relies on the proven autoHide idiom).
- KGlobalAccel remap end-to-end (new binding docks, old inert) + conflict UI in the
  plasmoid (V8/V16).
- Offset change applies on script reload in a live session (V9).
- Live multi-monitor dock/expand/re-dock/release cycle with animation via the slide
  effect + taskbar/switcher visibility in both states (V4–V7, V15).
- `workspace.screensChanged` availability live-confirm (T0 item 1 — fallback is
  load-bearing and proven in harness).

---

## 5. V3 — Rollback drill

- **Ctrl+Shift+H restore semantics:** verified in harness — `releaseAllDocked`
  restores every snapshot (parked or expanded), clears the tracker, second press is
  a no-op; `releaseDockEntry` funnels all removals and never fights
  minimized/maximized/fullscreen and never restores into a dead-screen snapshot
  (guarded restore).
- **Working-tree revertibility:** `git diff --stat` per file: README +22/−0,
  config-helper.sh +20/−3, ConfigEditor.qml +74/−0, main.js (cumulative working-tree
  +916/−175 — see WARNING-2). Rollback documented in `apply-progress.md`
  (rollback summary per work unit) and design §13. effect/kcm/main.xml not touched →
  no effect/KCM rollback surface.
- Docs by PR present (PR1 main.js dock section + registrations + gates; PR2 helper
  dict/reads + QML blocks; PR3 README section).

---

## 6. Strict TDD compliance (strict_tdd: true, testing.enabled: false)

- `apply-progress.md` contains TDD Cycle Evidence tables (PR1 and PR2).
- Convention honored: no runner exists, so RED→GREEN is replaced by per-task manual
  smoke (tasks.md "Task conventions" + config.yaml description) — this is the
  repo-sanctioned interpretation of strict TDD with no test framework.
- Reported harnesses cross-referenced against the real codebase: all read
  `contents/code/main.js` (verified by grep); re-run and GREEN re-confirmed
  (19/19, 6/6, 4/4). Config round-trip re-verified in a sandbox.
- Assertion quality: harnesses assert concrete geometry values / tracker state /
  skip-flag hygiene (no tautologies, no ghost loops, no type-only assertions, no
  implementation-detail CSS assertions). QML/README verified statically only (no
  QML unit harness exists in repo; per tasks.md D1/C verification is render/manual).

**No CRITICAL TDD findings.**

---

## 7. Review workload / PR boundary findings

- Chained stacked-to-main (3 PRs) delivered per `tasks.md` Review Workload Forecast
  (High, chained PRs recommended, review_budget 400). Only the assigned dockit slice
  was implemented; `effect/`, `kcm/`, `contents/config/main.xml` untouched → no
  scope creep across package boundaries.
- PR 2 / PR 3 line counts match apply claims exactly (config-helper +20/−3,
  ConfigEditor +74/−0 = 91; README +22/−0). The dock additions in main.js are
  self-contained (dock section ~904–1577 + 5 documented gate sites + cheat-sheet
  rows + 3 registrations).

---

## 8. Warnings (non-blocking)

- **WARNING-1 (evidence quality, draft harness):** `dockit-smoke.js` reports
  18/19 with `FAIL release all: snapshot restored`. Root cause is a **harness-order
  artifact**, not a product defect: the draft harness unplugs the second monitor
  *before* release-all, so the lazy `validateDockedScreens` releases the entry via
  guarded restore (snapshot center now off the surviving screen → restore refused
  by design §5.5/D5), and the assertion then expects the *original pre-dock*
  snapshot of an earlier, already-released entry. The canonical `dockit-smoke2.js`
  treats this exact case ("monitor removal: no geometry mutation after guarded
  release (snapshot center off-screen)") as a PASS. Recommendation: delete or
  update the draft harness so the stale expectation can't be misread as a regression.
- **WARNING-2 (boundary attribution):** the working-tree `git diff` vs HEAD for
  `contents/code/main.js` is +916/−175, larger than the claimed PR1 +370/−0, because
  the working tree carries pre-existing uncommitted main.js development (HEAD main.js
  is 836 lines vs 1577 in the tree; the diff includes e.g. a `"use strict";` removal
  and non-dock edits). The dockit-attributable slice is self-contained and clean, but
  the exact PR1 line attribution cannot be independently confirmed from git alone in
  this uncommitted working tree. The orchestrator should confirm the PR1 boundary
  when auditing the 400-line budget / chain split.
- **WARNING-3 (cosmetic, doc outline):** the `### Finding a window's resource class`
  and `### Manual config via terminal` subsections now nest under `## Dock` in the
  README outline (flagged in apply-progress; placement taken verbatim from tasks.md
  D1). One-line relocation (or demote `## Dock` to `###`) if the reviewer prefers
  them under `## Configuration`.
- **WARNING-4 (out of change):** `.gitignore` shows a pre-existing `+2` (`.atl/`
  local runtime-state ignore), not part of dockit.

---

## 9. Live-KWin checklist (deferred to a session — documented for the reviewer)

1. `bash install.sh script plasmoid` + `kwin6 --replace`; journal `[DropdownAny] loaded`, no JS errors.
2. Dock left/right single + multi-monitor; 24px sliver; size unchanged; nothing on neighbor monitor.
3. Sliver click → expand; Alt+Tab → re-dock; both animate via slide effect; taskbar/switcher visible in both states.
4. `Ctrl+Shift+H` with parked + expanded + drifted; second press no-op; OSD count.
5. Offset 48 → apply → dock → 48px sliver (reload).
6. KGlobalAccel remap one dock shortcut → new binding docks, old inert.
7. Wayland click-sliver `windowActivated` with `activeWin === win` (T0 item 6).
8. `workspace.screensChanged` availability live-confirm (T0 item 1); fallback already proven.
9. Precedence: autoHide/temp/tile skip docked windows; min/max/fullscreen/shell no-op; tiled detiles.
10. Cleanup: close docked window, disconnect monitor, second same-class window.

---

## 10. Conclusion

**PASS.** Implementation is complete, self-contained, and conformant to spec/design
to the extent verifiable headless. V1 static checks all green; canonical functional
smoke harnesses green (19/19, 6/6, 4/4); config save→load round-trip verified in a
sandbox; strict-TDD evidence present and re-confirmed GREEN; non-goals untouched.
Remaining verification is the live-KWin session checklist (§9), which the headless
environment cannot perform. No blockers. WARNINGs 1–4 are evidence-quality /
boundary-attribution / cosmetic and should be actioned by the orchestrator before or
at merge of the stacked chain.

---

## 11. Final verification status — 2026-10-19 (post-merge, archived)

Recorded at archive time, on `master` at commit `28e4506`. Sections 1–10 above are
left unchanged; this section records the evidence that closed the headless gap and
the two items that remain **open**.

Status: **PASS** for the static/headless surface and for the live smoke recorded
below; **2 manual items remain open** (listed at the end — they are not passed).

### Evidence confirmed in the parent session (reported verbatim, not re-derived here)

Scratch mock-KWin harnesses (never committed; `/tmp/dockit-guards-UupY/`):

| Harness | Coverage | Result |
| --- | --- | --- |
| `harness.js` | dock / re-dock / expand / release, desktop-switch gates, false-skip + re-arm regressions | 24/24 |
| `harness2.js` | built without `currentDesktopChanged` / `currentDesktopChanging` | 8/8 |
| `harness3.js` | `dockOffsetPx` read at load: 24, 32, 1-floor, non-numeric → 24, missing → 24 | 5/5 |

- `node --check contents/code/main.js`: clean on the merged tree.
- **Live:** `~/.local/share/kwin/scripts/plasma-dropdown-any/contents/code/main.js` is
  byte-identical to `master` and loaded (`isScriptLoaded=true`, journal
  `[DropdownAny] loaded`); the user reproduced the original workspace-switch scenario
  and reported "Listo quedo bien".
- **KGlobalAccel registration:** `~/.config/kglobalshortcutsrc` `[kwin]` has
  `DropdownDockLeft=Ctrl+Shift+Left,none,…`,
  `DropdownDockRight=Ctrl+Shift+Right,none,…`,
  `DropdownDockReleaseAll=Ctrl+Shift+H,none,…`; `kwinrc [Script-plasma-dropdown-any]`
  has `dockOffsetPx=24`, `dockLeftShortcut`, `dockRightShortcut`,
  `dockReleaseAllShortcut`.
- **Widget (static evidence only):** `plasmoid/contents/ui/ConfigEditor.qml` has the
  Dock card (~line 1622), the three shortcut rows (~1586-1588), `dockOffsetPx`
  (default 24) and the shared `dirty` flag.

### Open manual items (NOT passed)

1. **Live KGlobalAccel rebinding from the widget / System Settings.** Registration is
   verified (see above and §4). A live remap was not re-run on 2026-10-19, so the
   end-to-end behavior of the scenario "Shortcut remap changes the effective binding"
   (new binding docks, old binding inert) is unconfirmed live.
2. **Visual confirmation of the Dock card.** That the Dock card renders, sets the
   shared `dirty` flag, and shows the conflict hint is confirmed statically only; no
   live render was observed.

Both items must be closed in a live KWin + plasmoid settings session before they are
claimed as passing.

> **Count drift (not fixed here):** §1 states "20 scenarios" while
> `specs/dock/spec.md` carries 26 `#### Scenario:` headings. Recorded so the next
> reader is not misled; the historical wording of §§1-10 is left untouched.

### Closure attempt — 2026-10-19, live GUI session (Orca computer-use, `plasmawindowed org.kde.plasma.dropdownany`)

Opened the standalone configuration window (`bash configure`) and drove it through the accessibility tree.

**Item 1 (live KGlobalAccel rebinding) — CLOSED at the registration layer.**
The widget's save path writes both `kwinrc [Script-plasma-dropdown-any] dockLeftShortcut`
and `kglobalshortcutsrc [kwin] DropdownDockLeft = "<sc>,none,<description>"`
(`config-helper.sh` lines 391-393). Reproducing exactly those two writes plus a script reload
changed the effective binding to `Ctrl+Shift+F10` in `kglobalshortcutsrc`, and repeating them
with `Ctrl+Shift+Left` restored it. Note the boundary: a remap that only edits `kwinrc` does
NOT move the binding, because KGlobalAccel keeps the stored active shortcut; the writethrough
to `kglobalshortcutsrc` is what makes a remap effective. A physical keypress on the remapped
combo was not performed.

**Item 2 (Dock card render) — render and conflict hint CONFIRMED; dirty-flag/Apply interaction still UNVERIFIED.**
The tree exposes the Dock card as a card containing: `Visible sliver width 24 px`,
`Style Smooth`, `Duration 250 ms`, the three rows `Dock focused window to left edge`
(`Ctrl+Shift+Left`), `Dock focused window to right edge` (`Ctrl+Shift+Right`),
`Release all docked windows` (`Ctrl+Shift+H`), the heading `Dock`, the collision hint
("Applies to any focused window … Ctrl+Shift+Left / Ctrl+Shift+Right may collide with in-app
shortcuts — remap in System Settings → Shortcuts …"), and an `Apply` button. Raising the
sliver spinbox by one step updated the row to `28 px`, so the control is live and bound to
`root.dockOffsetPx`.

The dirty flag itself is `enabled: dirty && !_saving` on Apply (`ConfigEditor.qml:1747`), and
this AT-SPI backend exposes neither enabled state nor checkbox state, so it is not observable
from the tree. Pressing `Apply` after that change (`click --element-index`, both with and
without `--restore-window`, reported `ok` but `unverified`) produced no `kwinrc` write and no
script reload, i.e. the accessibility click could not be shown to land on the button — it is
NOT evidence that the button is broken. Side effects of this session were reverted: both
`kwinrc` and `kglobalshortcutsrc` were restored byte-identically to their pre-session backups
(verified with `diff`), including a `debugMode` flip made while probing the checkbox and the
`DropdownAny-ListShortcuts` entry that a reload re-enables.

**Still open:** a human clicking `Apply` in the Dock card (or the panel widget's config dialog)
and a physical keypress on a remapped dock shortcut.
