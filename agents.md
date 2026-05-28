# Agent Guide — plasma-dropdown-any

Instructions for AI agents working on this project. Read this before touching any file.

---

## What this project is

A **KWin 6 workspace script** (JavaScript) + a **KCM plugin** (C++ / QML) for Plasma 6.

The script registers global shortcuts that show/hide any window as a Yakuake-style dropdown. The KCM provides the System Settings UI to configure up to 10 slots.

There are no automated tests. Verification is always manual: build → install → reload KWin → trigger shortcut → observe behavior.

---

## Stack

| Layer | Technology |
|-------|-----------|
| Script runtime | KWin 6 JavaScript scripting engine (QJSEngine) |
| Script API | `workspace.*`, `registerShortcut`, `readConfig`, `writeConfig`, `callDBus` |
| KCM | C++17 + Qt6 + KF6 (KCMUtils, ConfigCore, CoreAddons) |
| KCM UI | Qt Quick / QML with Kirigami and PlasmaExtras |
| Config storage | `~/.config/kwinrc` → `[Script-plasma-dropdown-any]` |
| Shortcut storage | `~/.config/kglobalshortcutsrc` → `[kwin]` |
| Build | CMake + KDEInstallDirs6, installed to `~/.local` |

---

## Project structure

```
plasma-dropdown-any/
├── metadata.json              # Plugin manifest — X-Plasma-API: javascript
├── contents/
│   └── code/main.js           # KWin script — all runtime logic lives here
├── kcm/
│   ├── CMakeLists.txt
│   ├── kcm_dropdown_any.h     # SlotData struct, Q_PROPERTYs, signals
│   ├── kcm_dropdown_any.cpp   # load(), save(), slots(), setSlot(), addSlot()
│   ├── kcm_resources.qrc
│   └── ui/main.qml            # SlotRow delegate, syncSlots(), pushSlot()
├── install.sh                 # cmake build + kpackagetool6 + KWin reload
├── uninstall.sh
├── README.md
└── agents.md                  # ← you are here
```

---

## Critical KWin JS constraints

These are non-obvious platform limitations. Violating them produces silent failures.

| Constraint | Detail |
|-----------|--------|
| No `Qt` namespace | `Qt.rect()` etc. are unavailable. Mutate the `QRectF` from `clientArea()` directly. |
| No `exec()` | Cannot run shell commands. External calls go through `callDBus()` only. |
| No `setTimeout` | No timers. Use fire-count guards on signals as expiry mechanism. |
| `registerShortcut` = KGlobalAccel | All shortcuts appear in System Settings → Shortcuts. There is no "private" shortcut mechanism. |
| `workspace.windowList()` | Use this (Plasma 6). Fall back to `workspace.clientList()` for older builds. |
| Signal disconnect requires named functions | Anonymous lambdas passed to `connect()` cannot be reliably disconnected. Always store a named reference. |
| `writeConfig` is available | Writes to the script's KConfig group in kwinrc. Complement to `readConfig`. Both are confirmed working in KWin 6. |
| `callDBus` with callback | The optional trailing callback argument IS supported. Use it for error detection. |

---

## Architecture — main.js

### Key globals

```
hiddenWindows   windowClass → { x, y, width, height, savedOpacity }
                Defined ⟺ window is parked off-screen at y = -height by us.

slotConfig      windowClass → { idx, widthPct, heightPct, screenTarget,
                                opacity, allDesktops, autoHide }
                Mutable. Populated at registration. Used by toggleWindow and
                resizeActive. Source of truth for current slot params.
```

### Call graph

```
registerShortcut callback
  └─ toggleWindow(windowClass, shortcut)
       reads slotConfig[windowClass]
       hide path → hideWindow(windowClass)
       show path → applyDropdownGeometry(win, widthPct, heightPct, screenTarget)
                   win.onAllDesktops, win.opacity

workspace.windowActivated handler (autoHide slots only)
  └─ hideWindow(windowClass)

resizeActive(dw, dh)
  reads workspace.activeWindow → looks up slotConfig
  → applyDropdownGeometry
  → writeConfig("widthPercentN", ...) + writeConfig("heightPercentN", ...)
```

### Hide/show invariant

The `hiddenWindows[cls]` map is the single source of truth for "is this window currently parked off-screen by us?". Both `hideWindow()` and the `windowActivated` handler gate on it. Never check `win.active` to determine hidden state — it's volatile when focus changes.

---

## Architecture — KCM

### SlotData (C++ struct)

```cpp
struct SlotData {
    QString windowClass;
    QString shortcut;
    int  widthPercent  = 100;
    int  heightPercent = 50;
    int  screenTarget  = 0;    // 0 = cursor screen, 1..N = screen index
    int  opacity       = 100;
    bool allDesktops   = false;
    bool autoHide      = false;
};
```

### Adding a new per-slot field — checklist

When adding a field to `SlotData`, update ALL of these (use `screenTarget` as the reference pattern):

- [ ] `SlotData` struct field + default
- [ ] `setSlot()` declaration (kcm_dropdown_any.h) — add parameter
- [ ] `setSlot()` definition (kcm_dropdown_any.cpp) — assign field
- [ ] `slots()` — emit new map key
- [ ] `load()` new-format branch — `readEntry` with default
- [ ] `load()` old-format branch — same
- [ ] `save()` write loop — `writeEntry`
- [ ] `save()` cleanup loop (`i = m_slots.size()..19`) — `deleteEntry`
- [ ] `addSlot()` — extend literal
- [ ] `addSlotWithClass()` — extend literal
- [ ] `syncSlots()` in main.qml — copy field with `!== undefined` guard
- [ ] `pushSlot()` in main.qml — pass to `kcm.setSlot()`
- [ ] `SlotRow` in main.qml — add UI control
- [ ] `readConfig` loop in main.js — read new config key
- [ ] IIFE in main.js — capture and use new value

### QML ↔ C++ boundary

`pushSlot(idx)` reads from `slotModel` (ListModel) and calls `kcm.setSlot(...)`. Signature must be atomically consistent — if you add a parameter to `setSlot()` in C++, update `pushSlot()` in QML in the same commit.

---

## Build and install

```bash
bash install.sh
```

This compiles the KCM, installs it to `~/.local`, installs the KWin script package, and reloads the KWin scripting engine.

After editing `main.js` only (no C++ changes):

```bash
cp contents/code/main.js ~/.local/share/kwin/scripts/plasma-dropdown-any/contents/code/main.js
qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript "plasma-dropdown-any"
sleep 0.5
qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.start
```

---

## Slide animation

The script does NOT use KWin's built-in minimize animation. Windows are hidden by moving them to `y = -height` (off-screen). Animation is provided by the external effect **[kwin4_effect_geometry_change](https://github.com/peterfajdiga/kwin4_effect_geometry_change)**, which animates any `frameGeometry` transition.

Do not use `win.minimized = true` for hiding — the effect skips minimized windows.

---

## Engram memory

This project uses engram for persistent memory across sessions. Before starting significant work, search for prior context:

```
mem_search(query: "app-quake <topic>", project: "app-quake")
mem_context(project: "app-quake")
```

Key topic keys already in engram:

| Topic | Content |
|-------|---------|
| `architecture/live-resize-shortcuts` | slotConfig design, writeConfig confirmation, KGlobalAccel caveat |
| `sdd/screen-selection/*/` | Full SDD cycle for per-slot screen selection |
| `sdd/per-slot extras*/` | Full SDD cycle for opacity, allDesktops, autoHide |
| `sdd/find-or-start*/deferred` | Deferred feature: launch app if window not found (bundled Python D-Bus launcher approach) |

---

## Deferred features

**find-or-start** (engram obs #96): Per-slot checkbox + launch command. When the window isn't found, launch it. Blocked by KWin JS having no `exec()`. Planned approach: bundle a minimal Python D-Bus service inside the project (activated on demand). Full exploration is saved to engram — jump directly to proposal when ready.
