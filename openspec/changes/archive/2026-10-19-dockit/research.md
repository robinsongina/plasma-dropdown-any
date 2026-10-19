---
change: dockit
phase: explore
---

# Research — dockit

## Research Summary

Two-layer research: (1) consolidate the informal gentle-ai-explore conclusions
already validated in pre-flight; (2) re-verify every claim against the current
repo during this phase. Outcome: MVP click-to-expand dock is viable end-to-end
on existing primitives; hover-expand remains blocked (no timer API in KWin
workspace scripting); the only external verification still open is the KWin 6
effect-side pointer API for a future hover mode.

## Prior Informal Exploration (gentle-ai-explore)

- dock/restore/animation/shortcuts/config: viable.
- Continuous hover: blocked without polling/timer — 0 QTimer in repo;
  `workspace.cursorPos` is point-in-time only.
- MVP click-to-expand: 100% viable.
- Real hover: requires verifying the KWin 6 effect-side pointer API.

## Validated In-Repo Facts (this phase)

- `workspace.windowActivated` is already used for blur→park in three places
  (main.js:560, 587, 656) with `hiddenWindows`/`hiddenTiles` gates — the exact
  interaction model dock needs.
- `frameGeometry = {x,y,width,height}` object-literal mutation is the
  established geometry API (main.js:80–87, 226–263); the slide effect animates
  any such transition for managed windows
  (effect/contents/code/main.js `onWindowFrameGeometryChanged`).
- `virtualScreenBounds()` (main.js:213–224) is the reference for off-screen
  pushes across monitors; dock parks against one screen edge instead, needing
  per-screen math.
- Effect animation gate: class in `ManagedClasses` (written by config-helper.sh
  on every save from slot/tile classes) OR `skipSwitcher===true` fallback
  (TempSlotStyle/TempSlotDurationMs). Dock on non-slot windows animates via the
  fallback if skip flags are set at the geometry-change instant (precedent:
  dropdown show path, main.js:344–382).
- `workspace.cursorPos` is used only in `resolveScreen` (main.js:52) — a single
  read; no pointer-motion signal exists in the workspace scripting surface used
  by this repo.
- No timer usage anywhere in the repo; agents.md documents "No setTimeout — No
  timers. Use fire-count guards on signals as expiry mechanism."
- Global-shortcut addition path is fully templated: main.js `readConfig` +
  `registerShortcut` (proposed names `DropdownDock-*`); config-helper.sh
  `global_shortcuts` dict (config-helper.sh:312–325) writing kwinrc group +
  kglobalshortcutsrc `[kwin]`; ConfigEditor.qml properties (47–55), load
  (119–125), `_buildConfig` (396–402), Global shortcuts UI section (1536–1561).

## External Verification Checklist (spike, before proposal/spec finalization)

1. **KWin 6 effect-side pointer API** (hover future): does the QJSEngine effect
   context expose a pointer-position property or pointer-motion signal (e.g.
   `effect.pointerPos`, `windowInputMouseEvent`)? Yes → hover-expand becomes
   feasible effect-side; No → hover stays blocked.
2. **Timer availability in the effect context**: any `setTimeout`/interval in
   KWin effect scripts (workspace scripts: confirmed none).
3. **KWin tiling state in scripting API**: is `quickTileMode` (or equivalent)
   readable from a KWin 6 script Window object to gate docking of tiled windows?
4. **KGlobalAccel default conflicts** for Ctrl+Shift+Left/Right on a stock
   Plasma 6 install and common apps (editors/terminals word-select).
5. **Wayland focus-stealing**: confirm `workspace.activeWindow = win` on expand
   works for arbitrary windows (dropdown show already does this).
6. **Skip-flag lifecycle**: verify the effect reads `skipSwitcher` at
   geometry-change-signal time, so clearing flags right after the move does not
   cancel the pending animation.

## Sources

- contents/code/main.js (state machines, geometry, autoHide handlers, shortcuts)
- effect/contents/code/main.js (ManagedClasses + skipSwitcher fallback)
- plasmoid/contents/ui/ConfigEditor.qml (load/save/shortcut UI)
- plasmoid/contents/code/config-helper.sh (kwinrc + kglobalshortcutsrc writes,
  ManagedClasses sync)
- contents/config/main.xml (kcfg surface — currently minimal; dock keys optional)
- README.md, agents.md (architecture + platform constraints)
- Pre-flight context (informal gentle-ai-explore results)
