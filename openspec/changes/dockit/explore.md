---
change: dockit
phase: explore
---

# Explore — dockit

## Exploration Goal

Validate feasibility and scope for a "dock" feature in plasma-dropdown-any (KWin 6):

- Ctrl+Shift+Left / Ctrl+Shift+Right docks the currently-focused window to the
  corresponding screen edge, keeping its original size, leaving a global
  configurable pixel offset (a "sliver") visible.
- Clicking the sliver activates the window → it expands to its original
  geometry; on blur it re-docks.
- Ctrl+Shift+H releases every docked window, restoring pre-dock geometry.
- Animation rides the existing plasma-dropdown-any-slide effect (animates any
  frameGeometry transition).

This phase only explores; proposal is out of scope. No implementation done.

## Context & Discovery

### Overview

Dock is a third state beside the existing "dropdown off-screen" states of
main.js. The core mechanism already exists as the autoHide pattern: a
`workspace.windowActivated` handler that parks a window on blur and restores
it on focus. Dock differs from hide in two ways only: (1) the parked position
is at a screen edge with `offsetPx` visible instead of fully off-screen, and
(2) restore is transient — losing focus re-docks instead of staying restored.

### Current Implementation

Verified primitives available for reuse:

| Primitive | Location | Role in dock |
| --- | --- | --- |
| `hiddenWindows` tracker `{x,y,width,height,savedOpacity}` per class | contents/code/main.js:166, 226–263 | Reference pattern for a separate `dockedWindows` tracker (must NOT be reused — see Risks) |
| `virtualScreenBounds()` — union of all `screens[i].geometry` | main.js:213–224 | Multi-monitor reference; dock parks against the window's own screen edge, hide pushes past the union |
| `workspace.windowActivated` autoHide handlers | main.js:560–567 (temp), 587–597 (slot), 656–662 (tile) | The exact click-to-expand / blur-re-dock signal; gates on tracker + `activeWin === win` |
| `workspace.activeWindow`, `findByClass()` (resourceClass/resourceName) | main.js:31–46, 315 | Docking target = focused window; tracker keyed by class |
| Geometry mutation `win.frameGeometry = {x,y,width,height}` (no `Qt.rect()`) | main.js:80–87, 226–263 | Dock/expand/restore reuse this; slide effect animates the transition automatically |
| `skipTaskbar/skipPager/skipSwitcher` set before every geometry move, cleared after | main.js:344–382 (show path) | Keeps the effect's animation gate satisfied at geometry-change time; windows stay usable in taskbar while expanded |
| Slide effect: class-listed windows always animated; non-listed + `skipSwitcher=true` animated via TempSlotStyle fallback | effect/contents/code/main.js (`matchClass`, `onWindowFrameGeometryChanged`) | Dock on arbitrary windows animates through the skipSwitcher fallback for free |
| Global-shortcut plumbing: `readConfig` default + `registerShortcut` (KGlobalAccel), kglobalshortcutsrc `[kwin]`, plasmoid UI | main.js (~575–600, 700–780); config-helper.sh:309–325; ConfigEditor.qml:47–55, 119–125, 396–402, 1536–1561 | Adding dock shortcuts = one row per shortcut in the existing Global shortcuts section |
| `windowRemoved` cleanup of tracker entries | main.js:606–620 | Same cleanup needed for `dockedWindows` |

Platform constraints (agents.md "Critical KWin JS constraints"): no
`setTimeout`/timers; no `Qt` namespace; no `exec()` (callDBus only);
`registerShortcut` = KGlobalAccel (all shortcuts public in System Settings);
effect context has no `callDBus` (console.log via `journalctl -t kwin_wayland`).

### Prior Art

- Informal exploration (gentle-ai-explore, pre-flight): dock/restore/animation/
  shortcuts/config all viable; continuous hover blocked without polling/timer
  (0 QTimer in repo; `workspace.cursorPos` point-in-time only); MVP
  click-to-expand 100% viable; real hover requires verifying the KWin 6
  effect-side pointer API.
- In-repo precedent: autoHide slots ARE the dock interaction model (focus-in →
  show, focus-out → park) minus the sliver. `workspace.cursorPos` +
  `workspace.screenAt` (main.js:50–56) is a one-shot read, not a signal.

## Viability Assessment

### Viability Summary

| MVP item | Verdict | Basis |
| --- | --- | --- |
| Dock focused window to left/right edge, original size, `offsetPx` sliver | ✅ Viable | `frameGeometry` mutation + per-screen edge math; snapshot before move |
| Click sliver → expand; blur → re-dock | ✅ Viable | `windowActivated` proven in autoHide handlers; gate on `activeWin === win` + docked state |
| Ctrl+Shift+H restore-all | ✅ Viable | Iterate `dockedWindows`, restore saved geometry (hideWindow restore pattern) |
| Animation | ✅ Viable | Effect animates any frameGeometry change (ManagedClasses or skipSwitcher fallback); dock sets skip* before each move (show-path precedent) |
| Shortcuts (configurable) | ✅ Viable | Existing readConfig + config-helper.sh dict + KGlobalAccel pattern |
| Config UI / offset | ✅ Viable | ConfigEditor global-shortcuts section + one `dockOffsetPx` key |
| Real hover-expand (no click) | ❌ Not in MVP | No timer API in workspace scripting; effect-side pointer API unverified (see Research) |

### Key Risks / Unknowns

1. **Hover (real auto-expand) is blocked today.** No `setTimeout` in KWin JS
   scripts; `workspace.cursorPos` is a point-in-time read. Future path: verify
   KWin 6 effect-side pointer API (pointer position property / pointer-motion
   signal in the QJSEngine effect context) or an effect-side timer — both
   unverified. MVP click-to-expand needs none of this.
2. **Shortcut conflicts.** Ctrl+Shift+Left/Right are common in-app combos
   (word/line selection in editors/terminals); KWin placement defaults
   (Meta+arrows quick-tile, screen-move combos) occupy adjacent space.
   KGlobalAccel: conflicts surface in System Settings → Shortcuts, second
   registration loses until resolved. Mitigation: configurable defaults +
   documentation; confirm exact collision set on target system at spike time.
3. **KWin tiling interaction.** No tiling/quick-tile API referenced anywhere in
   the repo; KWin's tiling controller may re-apply geometry for windows it
   considers tiled on activate/resize. Verify whether the target KWin exposes
   `quickTileMode`/tiling state in the scripting API; otherwise document
   "docking visually detiles; tiling state persists".
4. **Tracker separation.** `hiddenWindows` invariant is "parked fully
   off-screen by us"; a docked window is on-screen (sliver visible). Sharing
   the tracker breaks all hide/show gating. Required: separate
   `dockedWindows[cls] → {x,y,width,height,edge,offsetPx,expanded}` with the
   same guard disciplines (check before dock, delete on restore-all/windowRemoved).
5. **Effect animation scope for arbitrary windows.** Dock targets any focused
   window; `ManagedClasses` only lists slot/tile-configured classes (written by
   config-helper.sh on save). Non-managed classes animate via the skipSwitcher
   fallback → shared TempSlotStyle/DurationMs and the existing "any
   skipSwitcher window gets animated" caveat apply. Dock/expand transitions
   animate automatically; keep skip* flags set at geometry-change instant,
   clear after.
6. **Multi-monitor edges.** Off-screen push uses the virtual union; dock must
   park against the window's own screen edge (offset relative to that screen).
   Docked window on a removed monitor → decide fallback (restore or re-dock).
7. **Precedence vs existing states.** Dock × autoHide / temp slot / tile /
   minimized / maximized / fullscreen: define allowed vs skipped combos;
   autoHide handlers must skip docked windows; slot toggle must not fight a
   docked window; `windowRemoved` must clean `dockedWindows`.
8. **Focus semantics on Wayland.** `workspace.activeWindow = win` (restore) is
   subject to focus-stealing prevention — the existing show path already does
   this; same exposure. Blur re-dock must guard against `activeWin === win`
   races (signal order when clicking the sliver vs another window).
9. **Minimized/maximized/fullscreen windows.** Define: minimized → skip (or
   unminimize then dock); maximized → dock preserves size but maximized state
   may fight direct geometry; fullscreen → skip. `allDesktops`/`keepAbove`
   interplay is a design decision (docked implies above?).
10. **skip flags while docked vs expanded.** Expanded = user works with the
    window → taskbar/switcher presence wanted; docked = sliver → dropdown-like
    absence defensible. Lifecycle must keep skip* true at geometry-change
    instant for the effect gate.

## Possible Approaches

### Approach Comparison

| Approach | Scope | Pros | Cons | Verdict |
| --- | --- | --- | --- | --- |
| A. Standalone dock state machine in main.js for ANY focused window | Full MVP as described | Matches feature promise; independent of slots; sliver + expand/blur + release-all via 3 new global shortcuts; effect rides skipSwitcher fallback | Must handle fallback style for non-managed classes; tiling/precedence rules needed | ✅ Recommended |
| B. Dock only for slot/tile-managed windows | Narrower | Perfect animation (class-listed); simpler precedence | Contradicts "dock the focused window" for arbitrary apps | ❌ Not per spec |
| C. Fold dock into hiddenWindows/autoHide state machine | Narrower | One tracker, reuse hideWindow | Breaks hiddenWindows invariant ("fully off-screen") | ❌ Rejected (Risk 4) |
| D. Hover-expand | Post-MVP | Best UX | Requires timer or effect-side pointer API — both unverified today | ⏸ Future spike |

Recommended: A for MVP; D tracked as a research item before any hover proposal.

## Open Questions

1. Shortcut defaults: keep Ctrl+Shift+Left/Right, or migrate to less contended
   combos (e.g. Meta+Ctrl+Left/Right)? Offset default (suggest 24px)?
2. Docked-state taskbar/switcher/keepAbove: dropdown-like (hidden while docked)
   or normal (visible in taskbar)?
3. Precedence rules table (dock × autoHide × temp × tile × minimized ×
   maximized × fullscreen) — allowed vs skipped vs re-docked.
4. Expand restore: always pre-dock geometry, or re-snapshot each expand/blur
   cycle (user-moved windows while expanded)?
5. Docked window on a removed/disconnected monitor: restore or re-dock?
6. Offset scope: single global value for MVP; per-window/per-edge later?
7. Click-to-expand: is natural focus enough, or is `workspace.activeWindow =
   win` needed (Wayland focus-stealing exposure)?
8. Exclude plasmashell/systemsettings/ksmserver/plasmawindowed from dock targets
   (skip-list precedent in config-helper.sh)?

## Exploration Conclusion

The dockit MVP is **100% viable** using only existing, proven primitives: the
autoHide `windowActivated` interaction model, `frameGeometry` mutation +
snapshot/restore, `virtualScreenBounds` for multi-monitor math, the slide
effect's class-list + skipSwitcher fallback animation, and the established
global-shortcut/config plumbing. The only previously-flagged blocker — hover —
applies exclusively to a future hover-expand; click-to-expand is unaffected.
Main design work in proposal/spec: separate `dockedWindows` tracker,
precedence/interaction rules, docked-vs-expanded skip-flag lifecycle, and
shortcut/offset defaults.

Next step: proposal. No implementation performed in this phase.
