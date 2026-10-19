---
change: dockit
phase: proposal
---

# Proposal — dockit

## Intent

Add a "dock" mode to plasma-dropdown-any (KWin 6): dock the currently focused
window to the left or right screen edge (keeping its original size), leaving a
global, configurable pixel offset visible as a sliver. Clicking the sliver
expands the window back to its original geometry (via `windowActivated`); losing
focus re-docks it. A third shortcut releases all docked windows, restoring
pre-dock geometry. This is a **standalone dock state machine** applying to
**any focused window** (Approach A of explore) — it is independent of the
slot/tile state machines.

This proposal covers MVP scope only. Real hover-to-expand, per-window offsets,
top/bottom docking, and deep tiling integration are explicitly out of scope
(non-goals below).

## Business Problem

Users of dropdown-style launchers (Yakuake/Guake) already get an off-screen
dropdown for configured classes. The dock feature addresses a different,
adjacent workflow: keeping a window — any window, not just slot-configured
classes — parked at a screen edge as a persistent, animated sliver, instantly
expandable on click and automatically re-docked on blur. Gecko-style
edge-docking tools (e.g. DockBar-like utilities) either don't exist on KWin 6 or
require separate daemons; this proposal delivers the behavior inside plasma-
dropdown-any with already-proven primitives and zero new infrastructure.

The exploration phase validated end-to-end viability: every primitive required
(multi-monitor geometry math, `windowActivated` blur→park model, `frameGeometry`
snapshot/restore, slide-effect animation gate, KGlobalAccel shortcut plumbing)
already exists in the codebase. The previously-flagged hover blocker applies only
to a future hover mode; click-to-expand is unaffected.

## Scope

### In scope (MVP)

- **Dock to edge, one global offset.** A single global offset value (default
  `24px`), configurable from the plasmoid settings UI, applies to all docked
  windows. The window's geometry keeps its original width/height; only the
  position changes so that `offsetPx` of the window remains visible past the
  chosen screen edge.
- **Left/right edges only.** `Ctrl+Shift+Left` docks the focused window to the
  left edge of **its own screen** (per-screen math, not the virtual union used by
  off-screen hide); `Ctrl+Shift+Right` docks to the right edge.
- **Click-sliver → expand, blur → re-dock.** Expanding sets the window back to
  its pre-dock geometry (snapshot taken at dock time). Re-docking re-parks it.
  The interaction rides `workspace.windowActivated` exactly like the existing
  autoHide handlers: expand on `activeWin === win`, re-dock on blur.
- **Release all.** `Ctrl+Shift+H` releases every docked window, restoring each
  saved pre-dock geometry and clearing the tracker.
- **Separate `dockedWindows` tracker.** Keyed by class like `hiddenWindows` but a
  distinct structure: `dockedWindows[cls] → {x, y, width, height, edge,
  offsetPx, expanded}`. `hiddenWindows` is NOT reused (its invariant is "parked
  fully off-screen by us"; a docked window is on-screen). Same guard disciplines:
  check-before-dock, delete on release-all and on `windowRemoved`.
- **Animation via existing slide effect.** No changes to the effect package.
  Docked windows animate through the existing class-list path where applicable
  and the `skipSwitcher` fallback otherwise; `skipTaskbar/skipPager/skipSwitcher`
  are set before each geometry mutation and cleared after, following the show-path
  precedent.
- **Configurable shortcuts.** `DropdownDockLeft` / `DropdownDockRight` /
  `DropdownDockReleaseAll` registered through the existing `readConfig` +
  `registerShortcut` (KGlobalAccel) path, editable in System Settings → Shortcuts,
  with a Global-shortcuts section entry in ConfigEditor.qml and defaults in
  config-helper.sh (kglobalshortcutsrc `[kwin]`).
- **Precedence rules** for dock interacting with existing states (see
  Implications).
- **Cleanup on window close / monitor removal** (restore-then-release when the
  window's screen disappears).

### Affected areas

- `contents/code/main.js` — new dock state machine + `dockedWindows` tracker,
  dock/release handlers, `windowActivated` blur handling, `windowRemoved`
  cleanup, three new shortcut registrations, `dockOffsetPx` config read.
- `plasmoid/contents/code/config-helper.sh` — global-shortcut dictionary entries
  for the three dock shortcuts, kwinrc/`[kwin]` default keys, `dockOffsetPx`
  sync.
- `plasmoid/contents/ui/ConfigEditor.qml` — Global shortcuts section rows for the
  three dock shortcuts; offset value control (e.g. spinbox) for `dockOffsetPx`.
- `contents/config/main.xml` — optional `dockOffsetPx` kcfg surface if the
  plasmoid reads it via kcfg rather than kwinrc (decision at spec/design time).
- `README.md` — feature docs + shortcut-conflict tradeoff notes.
- **Not touched (MVP):** `effect/` package, KCM package.

## Non-goals

- **Real hover-to-expand without click.** Blocked: no timer API in KWin workspace
  scripting; `workspace.cursorPos` is point-in-time. Requires an effect-side
  pointer API spike (KWin 6 QJSEngine effect context: pointer-position property /
  pointer-motion signal) — tracked as a future research item, not part of this
  change.
- **Per-window / per-edge offsets.** Single global offset for MVP.
- **Top/bottom docking** (no "dock to top/bottom" shortcuts or math).
- **Deep tiling integration.** No tiling-controller API usage; visual detiling
  behavior is documented, not engineered (see Risks).
- **Changes to the slide effect** — the MVP rides the effect exactly as it
  exists today; no animation-tuning knobs per dock.
- **Off-screen hide integration** — `hiddenWindows`/autoHide internals are not
  modified; dock only interacts via precedence gating.
- **No formal test suite** — consistent with repo policy; verification is the
  manual smoke test (install script + `kwin6 --replace`), plus `bash -n` on
  edited shell files.

## Alternatives Considered

| Alternative | Verdict | Rationale |
| --- | --- | --- |
| **A. Standalone dock state machine for ANY focused window** | ✅ Selected | Matches the feature promise exactly; independent of slot/tile config; reuses proven primitives; slides via skipSwitcher fallback for non-managed classes. |
| B. Dock only for slot/tile-managed windows | ❌ | Contradicts "dock the focused window" for arbitrary apps; narrower usefulness. |
| C. Fold dock into `hiddenWindows`/autoHide state machine | ❌ | Breaks the `hiddenWindows` invariant ("parked fully off-screen"); would corrupt hide/show gating and precedence between hide and dock. |
| D. Hover-expand mode | ⏸ Post-MVP/future spike | Best UX but requires timer or effect-side pointer API — unverified; MVP click-to-expand needs none of it. |

The explore phase independently confirmed approach B and C are non-compliant or
unsafe, and D is a separate future change. No other architectural routes were
found viable during exploration.

## Risks

1. **Shortcut conflicts (documented tradeoff).** Ctrl+Shift+Left/Right are common
   in-app combos (word/line selection in editors, terminals, browsers);
   KGlobalAccel surfaces collisions in System Settings → Shortcuts, and a second
   registration loses until resolved. Mitigation: configurable defaults (KGlobalAccel),
   documentation note in README + settings UI, and confirming the exact collision
   set on the target system at implementation time (research checklist item 4).
2. **KWin tiling interaction.** KWin's tiling controller may re-apply geometry to
   windows it considers tiled on activate/resize; no tiling API is used in the
   repo. MVP behavior: docking visually detiles; tiling state persists underneath.
   Verify `quickTileMode` readability in the KWin 6 scripting API; otherwise
   document the behavior (research checklist item 3).
3. **Precedence bugs between dock and existing states.** autoHide / temp slot /
   tile / minimized / maximized / fullscreen each have their own
   `windowActivated` and geometry gate; a docked window must not be double-
   managed. Required: docking only applies to plain, non-minimized, non-
   maximized, non-fullscreen windows; autoHide handlers skip docked windows;
   `windowRemoved` cleans `dockedWindows`. Enforced by explicit precedence rules
   (Implications) and the separate tracker.
4. **Wayland focus semantics on expand.** `workspace.activeWindow = win` is
   subject to focus-stealing prevention (same exposure the dropdown show path
   already has). Blur re-dock must guard against `activeWin === win` races
   (signal order when clicking the sliver vs. another window).
5. **Multi-monitor removal.** Docked window's screen disappearing → define
   fallback (restore pre-dock geometry and release). Per-screen edge math must
   use the window's own screen, not `virtualScreenBounds()` (that is for off-
   screen pushes).
6. **Skip-flag lifecycle.** Effect animation gate reads skip flags at geometry-
   change time; clearing flags right after the move must not cancel the pending
   animation (show-path precedent — verify at implementation, research checklist
   item 6).
7. **Expanded-window drift.** User moves/resizes a window while expanded —
   re-dock re-parks to which geometry? MVP decision: snapshot only at dock time;
   re-dock re-parks the expanded geometry (documented; per-cycle re-snapshot is
   a post-MVP option).

## Implications

### Precedence rules (dock × existing states)

| Existing state | When target focused window is… | Action |
| --- | --- | --- |
| autoHide (temp) | in dock state | autoHide blur handler skips; dock alone owns it |
| temp slot | toggled while docked | slot toggle is ignored for docked windows (or releases dock first — spec decision); autoHide skip-gate includes dock check |
| tile | tiled when dock shortcut pressed | dock applies; visually detiles; tiling state persists (Risk 2) |
| minimized | minimized when dock shortcut pressed | skip (no dock) |
| maximized | maximized when dock shortcut pressed | skip (direct geometry fights maximized state); spec may allow unmaximize-then-dock post-MVP |
| fullscreen | fullscreen when dock shortcut pressed | skip |
| `windowRemoved` | any | delete `dockedWindows[cls]` (same pattern as hidden windows) |
| screen removed | docked | restore pre-dock geometry + release |

### State/lifecycle

- `dockedWindows[cls]` holds the pre-dock snapshot `{x, y, width, height}` plus
  `edge`, `offsetPx`, `expanded` per entry; one docked window per class
  (consistent with the class-keyed tracker model).
- Skip flags (`skipTaskbar/skipPager/skipSwitcher`) are set before every geometry
  mutation and cleared after, at both dock and expand instants, to satisfy the
  effect animation gate.
- Docked/expanded taskbar visibility follows the dropdown precedent (skip* set at
  geometry-change instant); expanded windows remain usable in the taskbar/
  switcher. `keepAbove`/`allDesktops` behavior is a spec/design decision
  (dock implies pinned-above? default: no change to either for MVP).

### Interaction

- Clicking the sliver = normal window activation → `windowActivated` fires with
  `activeWin === win` → expand. Losing focus → blur → re-dock. No new input
  plumbing, no timers, no effect changes.

### Shortcuts + config

- Three new KGlobalAccel shortcuts (configurable, editable in System Settings):
  `DropdownDockLeft` (Ctrl+Shift+Left), `DropdownDockRight` (Ctrl+Shift+Right),
  `DropdownDockReleaseAll` (Ctrl+Shift+H).
- One new global config key `dockOffsetPx` (default 24) editable from the
  plasmoid settings UI (Global Shortcuts section + a numeric control).

### Platform constraints honored

- No `setTimeout`/timers, no `Qt` namespace, no `exec()`; `registerShortcut`
  (KGlobalAccel) only; all geometry via `frameGeometry = {x,y,width,height}`
  object-literal mutation; effect untouched.

## Proposed Defaults

| Item | Default | Notes |
| --- | --- | --- |
| `dockOffsetPx` | `24` | Global, single value for MVP; editable from plasmoid |
| `DropdownDockLeft` | `Ctrl+Shift+Left` | KGlobalAccel-configurable; conflict tradeoff documented |
| `DropdownDockRight` | `Ctrl+Shift+Right` | KGlobalAccel-configurable; conflict tradeoff documented |
| `DropdownDockReleaseAll` | `Ctrl+Shift+H` | KGlobalAccel-configurable |
| Docked skip flags | set at geometry-change instant, cleared after | show-path precedent for the effect gate |
| Docked window on removed screen | restore pre-dock geometry + release | cleanup path |
| Minimized/maximized/fullscreen at dock time | skip | precedence table above |

## Rollback

- **Reverse**: remove the three shortcut registrations and the dock state
  machine from `main.js`, revert `dockOffsetPx` additions across
  config-helper.sh / ConfigEditor.qml / main.xml; geometry effects are confined
  to docked windows and self-clearing (`windowRemoved` + release-all), so a
  disable restores every affected window by pressing `Ctrl+Shift+H` or via the
  tracker cleanup on reload.
- **No persistence burden**: dock state is runtime-only (no stored dock
  geometry); config keys are additive defaults.
- **Feature toggle**: any existing config/shortcut mechanism (e.g. "Dock enabled"
  checkbox read from kwinrc) can gate the whole feature; default **enabled** with
  shortcuts active.
- **Smoke test to validate rollback**: `kwin6 --replace`, dock a window, release
  all, uninstall/revert, confirm restored geometry and no lingering skip flags.

## Success Criteria

1. `Ctrl+Shift+Left/Right` docks the focused window (any application, no slot
   config required) to its own screen's left/right edge, original size intact,
   `24px` (or configured value) sliver visible.
2. Clicking the sliver expands the window to its pre-dock geometry; switching
   focus away re-docks it to the same edge/offset.
3. `Ctrl+Shift+H` restores every docked window to its pre-dock geometry and
   clears the tracker.
4. All three shortcuts are editable via System Settings → Shortcuts (KGlobalAccel)
   and shown in the plasmoid Global shortcuts section; `dockOffsetPx` is editable
   from the plasmoid and takes effect on reload without touching the effect.
5. Docking, expanding, and releasing all animate via the existing slide effect
   (no changes to the `effect/` package); non-slot classes animate through the
   skipSwitcher fallback.
6. No regression in hide/temp/tile behavior: docked windows are skipped by
   autoHide handlers; `windowRemoved` and monitor-removal cleanup leave no stale
   `dockedWindows` entries.
7. Manual smoke test passes: `bash -n` on touched shell scripts,
   `kpackagetool6` install of KWin/Script + Plasma/Applet packages, `kwin6
   --replace`, dock/expand/release cycle verified.

## Open Items for spec/design (carried from explore)

- Docked vs expanded taskbar/switcher/`keepAbove`/`allDesktops` policy (explore
  Open Question 2) — spec decision.
- Expand-restore semantics: always pre-dock snapshot vs re-snapshot per
  expand/blur cycle (explore Open Question 4) — MVP default: pre-dock snapshot
  (Risk 7).
- Skip-list for shell windows (plasmashell/systemsettings/ksmserver/
  plasmawindowed) per config-helper.sh precedent (explore Open Question 8).
- `dockOffsetPx` surfacing: kwinrc-only vs kcfg (`main.xml`) — design decision.
- External verification checklist items (research.md) before/at implementation:
  effect-side pointer API (future hover), timer availability in effect context,
  tiling-state API, KGlobalAccel collision set, focus-stealing on expand,
  skip-flag timing.

## Next Step

Spec — no implementation performed in this phase.
