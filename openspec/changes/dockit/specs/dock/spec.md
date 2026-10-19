# Dock Specification

## Purpose

Docking parks any focused application window at the left or right edge of the
window's own screen — at its original size — leaving a configurable pixel sliver
visible. Clicking the sliver expands the window back to its pre-dock geometry
(normal activation); losing focus re-docks it. A dedicated shortcut releases
every docked window and restores all pre-dock geometries. The dock is a
standalone state machine that applies to any focusable window; it does not
require slot/tile configuration and does not modify the existing dropdown
(hide/temp/tile) machinery beyond precedence gating.

## Requirements

### Requirement: Dock Focused Window to Screen Edge

The system MUST dock the currently focused window to the left or right edge of
the window's own screen (never the virtual multi-screen union) when the
corresponding dock shortcut is pressed, with these guarantees:

- The window's original width and height MUST be preserved; only its position changes.
- Exactly `dockOffsetPx` pixels of the window MUST remain visible past the chosen
  screen edge (the "sliver").
- The window's pre-dock geometry MUST be snapshotted before the move and MUST be
  associated with the docked entry.
- Pressing a dock shortcut on an already-docked window MUST re-dock it to the
  requested edge, preserving the original snapshot.

#### Scenario: Dock the focused window to the left edge

- GIVEN a focused, plain window on a screen with `dockOffsetPx` set to 24
- WHEN the user presses the Left dock shortcut
- THEN the window is parked at its own screen's left edge with 24px of it visible past the edge
- AND the window's width and height are unchanged
- AND the pre-dock geometry is snapshotted

#### Scenario: Dock the focused window to the right edge

- GIVEN a focused, plain window
- WHEN the user presses the Right dock shortcut
- THEN the window is parked at its own screen's right edge with `dockOffsetPx` pixels visible past the edge

#### Scenario: Dock against the window's own screen on a multi-monitor setup

- GIVEN a focused window whose screen is the right-hand monitor of two
- WHEN the user presses the Left dock shortcut
- THEN the window is parked against the left edge of its own (right-hand) monitor
- AND no part of the window is placed onto the left-hand monitor

#### Scenario: Re-dock an already-docked window to the other edge

- GIVEN a window docked to the left edge of its screen
- WHEN the user presses the Right dock shortcut
- THEN the window is re-parked at the right edge of its screen with `dockOffsetPx` visible
- AND the pre-dock snapshot recorded at the original dock time is preserved

### Requirement: Expand on Intentional Activation and Re-dock on Blur

The system MUST expand a docked window to its snapshotted pre-dock geometry when
the user deliberately activates it by clicking the visible sliver, and MUST
re-dock it to the same edge and offset when it loses focus. Re-docking MUST
re-park the window using its current geometry and MUST NOT modify its
width or height.

An activation the dock did not ask for MUST leave the window parked. KWin
focuses the topmost window of the desktop it lands on, so switching desktops can
activate a parked window on its own. Expansion therefore requires the pointer
inside the parked sliver's rectangle, and the activation must not be the switch
itself: a desktop switch observed in the preceding 500 ms is rejected, and on a
build that exposes no desktop-change signal at all, an activation arriving on a
different desktop than the one the entry was parked on is rejected (the entry
re-arms to that desktop). Docking, re-docking, and expanding record the desktop
they happened on.

#### Scenario: Clicking the sliver expands the window

- GIVEN a window docked at the left edge with a pre-dock snapshot
- WHEN the user clicks the visible sliver (the window becomes the active window)
- THEN the window is restored to its pre-dock geometry (position and size)

#### Scenario: Switching desktops does not expand the dock

- GIVEN a window docked on desktop 1, with desktop 1 recorded as its parked desktop
- WHEN the user switches to desktop 2, where KWin activates the parked window
- THEN the window stays parked with `dockOffsetPx` visible
- AND the entry records desktop 2 as its parked desktop

#### Scenario: Activation away from the sliver does not expand the dock

- GIVEN a parked dock whose pointer is outside the sliver rectangle
- WHEN the window becomes active without a sliver click (taskbar, task switcher, or KWin's own focus)
- THEN the window stays parked

#### Scenario: Clicking the sliver on a freshly switched desktop still expands

- GIVEN a parked dock whose parked desktop was re-armed to the current desktop
- WHEN the user clicks the visible sliver
- THEN the window is restored to its pre-dock geometry

#### Scenario: Losing focus re-docks the window

- GIVEN a docked window currently expanded
- WHEN the user activates another window (the docked window loses focus)
- THEN the window is re-parked at the same edge and offset
- AND the window's width and height are unchanged from its expanded state

#### Scenario: Re-dock after the user moved the expanded window

- GIVEN a docked window currently expanded
- WHEN the user moves it to a new position and then activates another window
- THEN the window is re-parked at its dock edge using its current geometry
- AND the original pre-dock snapshot is left unchanged and is still used for the next expand

### Requirement: Release All Docked Windows

The system MUST, on the release-all shortcut, restore every docked window —
whether currently parked or expanded — to its snapshotted pre-dock geometry and
MUST clear all dock state. Release-all MUST be idempotent: with no docked
windows it MUST change nothing.

#### Scenario: Release all restores every docked window

- GIVEN two docked windows, one parked and one expanded
- WHEN the user presses the release-all shortcut
- THEN both windows are restored to their pre-dock geometry
- AND no window remains in dock state

#### Scenario: Release all with no docked windows is a no-op

- GIVEN no window is docked
- WHEN the user presses the release-all shortcut
- THEN no window geometry is changed

### Requirement: Configurable Global Shortcuts

The system MUST register three dock shortcuts through KGlobalAccel with the
following defaults and MUST expose them for editing in System Settings →
Shortcuts and in the plasmoid Global Shortcuts section:

| Shortcut id | Default binding |
| --- | --- |
| `DropdownDockLeft` | `Ctrl+Shift+Left` |
| `DropdownDockRight` | `Ctrl+Shift+Right` |
| `DropdownDockReleaseAll` | `Ctrl+Shift+H` |

#### Scenario: Defaults present on fresh install

- GIVEN a freshly installed configuration with no overrides
- WHEN the user opens System Settings → Shortcuts
- THEN the three dock shortcuts are listed with their default bindings
- AND the same three shortcuts appear in the plasmoid Global Shortcuts section

#### Scenario: Shortcut remap changes the effective binding

- GIVEN the user remaps `DropdownDockLeft` to `Meta+Ctrl+Left` in System Settings
- WHEN the user presses the new binding
- THEN the focused window docks to the left edge
- AND pressing the old default binding no longer docks

### Requirement: Configurable Dock Offset

The system MUST read a single global `dockOffsetPx` value (default `24`) that
applies to every docked window, MUST make it editable from the plasmoid settings
UI, and MUST apply changes on script reload. Per-window or per-edge offsets are
out of scope.

#### Scenario: Offset change applies on reload

- GIVEN `dockOffsetPx` set to 48 in the plasmoid settings
- WHEN the KWin script is reloaded and a window is docked
- THEN 48 pixels of the window remain visible past the chosen edge

### Requirement: Isolated Dock Tracking

The system MUST track docked windows separately from the off-screen hide,
temp-slot, and tile trackers so that dock operations never interfere with the
existing dropdown state machines and vice versa. The system MUST remove a dock
entry exactly once, through one of: release-all, window close, monitor removal,
or class-collision release. After any of these events no stale dock state MUST
remain for that window.

#### Scenario: autoHide handler skips a docked window

- GIVEN a window of an autoHide-configured class that is currently docked
- WHEN the window loses focus
- THEN the autoHide blur handler does not park or hide the window (no double management)
- AND only the dock state machine re-docks it

#### Scenario: Temp-slot toggle does not act on a docked window

- GIVEN a window docked and its class also configured for a temp slot
- WHEN the user toggles the temp slot while the window is docked
- THEN no slot geometry action is performed on the window
- AND the window remains in dock state until released

#### Scenario: Docked window closes

- GIVEN a docked window
- WHEN the window is closed
- THEN its dock entry is removed
- AND no further geometry action is attempted on it

#### Scenario: Docked window's screen is removed

- GIVEN a window docked on monitor A
- WHEN monitor A is disconnected
- THEN the window is restored to its pre-dock geometry and released
- AND its dock entry is cleared

#### Scenario: Docking a second window of the same class

- GIVEN a class that already has one docked window
- WHEN the user docks another window of the same class
- THEN the prior docked window is restored to its pre-dock geometry and released
- AND the new window is docked and snapshotted

### Requirement: Animated Transitions via the Existing Slide Effect

Dock, expand, re-dock, and release transitions MUST animate through the existing
slide effect without any change to the effect package. Windows whose class is
not in the slot/tile managed list MUST still animate through the established
fallback path.

#### Scenario: Non-slot window docks with animation

- GIVEN a focused window whose class is not in the slot/tile managed list
- WHEN the window is docked
- THEN the dock transition is animated by the existing slide effect fallback path
- AND the effect package code is unchanged

### Requirement: Precedence — Dock Applies Only to Plain Windows

The system MUST skip docking (no geometry change, no entry) when the focused
window at shortcut time is minimized, maximized, or fullscreen, or is a
shell/panel window (plasmashell, systemsettings, ksmserver, plasmawindowed). For
a tiled window, docking MUST still apply: the window visually detiles while its
tiling state persists underneath (documented limitation, not engineered).

#### Scenario: Minimized window is not docked

- GIVEN a focused window that is minimized
- WHEN the user presses a dock shortcut
- THEN no geometry change occurs and no dock entry is created

#### Scenario: Maximized window is not docked

- GIVEN a focused window that is maximized
- WHEN the user presses a dock shortcut
- THEN no geometry change occurs and no dock entry is created

#### Scenario: Fullscreen window is not docked

- GIVEN a focused window that is fullscreen
- WHEN the user presses a dock shortcut
- THEN no geometry change occurs and no dock entry is created

#### Scenario: Shell window is not docked

- GIVEN a focused window that is plasmashell, systemsettings, ksmserver, or plasmawindowed
- WHEN the user presses a dock shortcut
- THEN no geometry change occurs and no dock entry is created

#### Scenario: Tiled window docks and visually detiles

- GIVEN a focused window managed by the KWin tiling system
- WHEN the user presses a dock shortcut
- THEN the window docks with the configured sliver visible
- AND the window is no longer visually tiled
- AND the underlying tiling state persists (documented limitation)

## Business Rules

- **One docked window per class.** The dock tracker holds at most one entry per
  window class (see requirement "Isolated Dock Tracking", class-collision scenario).
- **Expand restores the immutable dock-time snapshot.** The snapshot taken at dock
  time is used for every expand; there is no per-cycle re-snapshot in the MVP
  (user-moved expanded windows are re-parked from their current geometry on blur,
  but the snapshot is unchanged).
- **Re-dock preserves size.** Re-docking re-parks the window using its current
  width/height; it never resizes the window and never overwrites the snapshot.
- **Single global offset.** `dockOffsetPx` is one global value; all docked
  windows on all edges use it. Per-window and per-edge offsets are non-goals.
- **Taskbar/switcher presence.** Docking MUST NOT remove the window from the
  taskbar, pager, or task switcher in either the parked or expanded state.
- **keepAbove / allDesktops untouched.** Docking MUST NOT change a window's
  `keepAbove` or `allDesktops` settings; "docked implies pinned above" is a
  documented non-decision for the MVP.
- **No new input plumbing.** Expands occur only through ordinary window
  activation, gated to an intentional sliver click: pointer hit-test, plus a
  rejection of the desktop-switch activation itself (a switch in the preceding
  500 ms, or — when the build exposes no desktop-change signal — a different
  desktop than the one the entry was parked on). Re-docks happen only through
  focus loss. The gates read `workspace.cursorPos` and `Date.now()` at event
  time; no timers, polling, or pointer tracking are used.
- **Runtime-only state.** Dock state is not persisted; a docked window left
  parked when KWin restarts keeps its parked geometry but is no longer tracked.

## Invariants

- At any moment, a window is managed by at most one state machine: dock, hide
  (autoHide), temp slot, or tile. A docked window is never simultaneously in the
  off-screen hide/temp/tile trackers.
- A parked window always exposes exactly `dockOffsetPx` of itself past the
  chosen edge of its own screen, computed from the window's current
  width/height.
- A dock entry's snapshot is immutable for the lifetime of the entry.
- Every dock entry is removed by exactly one of: release-all, window close,
  monitor removal, or class-collision release; no stale entry survives these
  events.
- The dock tracker stores only plain, focusable, non-shell windows that were in
  a dockable state at dock time.
- Release-all restores every entry's snapshot regardless of parked/expanded
  state and clears all entries.

## Precedence

| Triggering condition | Action |
| --- | --- |
| Dock shortcut, focused window minimized | Skip — no geometry change, no entry |
| Dock shortcut, focused window maximized | Skip — no geometry change, no entry |
| Dock shortcut, focused window fullscreen | Skip — no geometry change, no entry |
| Dock shortcut, focused window is shell/panel (plasmashell, systemsettings, ksmserver, plasmawindowed) | Skip — no geometry change, no entry |
| Dock shortcut, focused window tiled | Dock applies; window visually detiles; tiling state persists underneath (documented) |
| Dock shortcut, focused window already docked | Re-dock to requested edge; snapshot preserved |
| Docked window loses focus while autoHide/temp-slot/tile handlers are active for it | Dock owns the window: those handlers skip it; dock re-docks it |
| Docked window becomes minimized or fullscreen | Dock entry released without geometry mutation |
| Docked window closes | Entry removed; no geometry action |
| Docked window's screen removed | Restore pre-dock geometry and release |
| Release-all with no entries | No-op |

## Error Handling

- **Unregistered or colliding shortcut.** If a dock shortcut cannot be
  registered (KGlobalAccel conflict), the remaining dock shortcuts and the rest
  of the feature MUST still operate; the collision is surfaced by System
  Settings → Shortcuts.
- **Invalid `dockOffsetPx`.** A missing or non-numeric value MUST fall back to
  the default 24. A value below 1 MUST be treated as 1 so the sliver remains
  visible. Larger values are accepted as-is (they simply expose more of the
  window).
- **Focus race during expand/blur.** When activation and blur follow each other
  closely, the system MUST NOT oscillate between expand and re-dock: re-dock
  MUST only act when the window is confirmed non-active.
- **Aborted dock operation.** If docking cannot complete because the window
  closed or its screen disappeared mid-transition, the system MUST abort cleanly
  and MUST leave no dock entry and no partial geometry behind.
- **Non-dockable target.** Any skip case in the precedence table MUST be
  silently ignored (no error surface, no geometry change).

## Non-goals (MVP boundary)

- Real hover-to-expand without click (requires timer or effect-side pointer API;
  tracked as a future research item, not part of this change).
- Per-window or per-edge offsets.
- Top/bottom docking.
- Deep tiling integration (visual detile documented only, no tiling API usage).
- Changes to the `effect/` package.
- Changes to the off-screen hide internals (interaction limited to precedence gating).
- A formal automated test suite (manual smoke test per repo policy).

## Success Criteria

1. `Ctrl+Shift+Left/Right` docks the focused window (any application, no slot
   config required) to its own screen's left/right edge, original size intact,
   with the configured offset (default 24px) visible as a sliver.
2. Clicking the sliver expands the window to its pre-dock geometry; switching
   focus away re-docks it to the same edge and offset.
3. `Ctrl+Shift+H` restores every docked window to its pre-dock geometry and
   clears all dock state.
4. All three shortcuts are editable via System Settings → Shortcuts (KGlobalAccel)
   and shown in the plasmoid Global Shortcuts section; `dockOffsetPx` is editable
   from the plasmoid and takes effect on reload.
5. Docking, expanding, re-docking, and releasing all animate via the existing
   slide effect; non-slot classes animate through the fallback path; the
   `effect/` package is untouched.
6. No regressions in hide/temp/tile behavior: docked windows are skipped by
   autoHide handlers and slot toggles; window-close and monitor-removal cleanup
   leave no stale dock entries.
7. Manual smoke test passes: `bash -n` on touched shell scripts,
   `kpackagetool6` install of KWin/Script + Plasma/Applet packages,
   `kwin6 --replace`, and a full dock/expand/re-dock/release cycle.
