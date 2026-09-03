# plasma-dropdown-any

KWin script for Plasma 6 that turns any window into a Yakuake-style dropdown panel — shown and hidden with a configurable global shortcut.

Works with **any application** identified by its `resourceClass` (Konsole, Kitty, Sublime Text, Obsidian, etc.). Up to 10 independent slots, each with its own shortcut and settings.

---

## Dependencies

No build step, no compiler, no `-dev`/`-devel` packages. The KWin script is plain JavaScript and the settings UI is a QML Plasma widget — everything below ships with any stock Plasma 6 desktop.

### Runtime

| Dependency | Notes |
|-----------|-------|
| **Plasma 6 / KWin 6** | Required — the script runs inside the KWin scripting engine |
| **kpackagetool6** | Required — installs both the KWin/Script and Plasma/Applet packages |
| **qdbus6** (or `qdbus-qt6` / `qdbus`) | Required — used to reload KWin and to drive the widget's window-list detection. `install.sh`/`config-helper.sh` probe all three names, so any one is enough |
| **kreadconfig6** / **kwriteconfig6** | Required — the widget reads/writes `kwinrc` through these instead of a compiled config backend |
| **python3** | Required — used internally by `config-helper.sh` for JSON (de)serialization between the widget and `kwinrc` |
| **kscreen-doctor** | Optional — used to list screen names in the widget; without it, only "At cursor screen" is offered |

### Optional

| Dependency | Purpose |
|-----------|---------|
| **[kwin4_effect_geometry_change](https://github.com/peterfajdiga/kwin4_effect_geometry_change)** | Slide animation — without it the window still appears/disappears but without a transition |

---

## Slide animation

The script hides windows by moving them off-screen (`y = -height`) instead of minimizing, so any geometry-change effect can animate the slide.

For a smooth Yakuake-style slide, install **[kwin4_effect_geometry_change](https://github.com/peterfajdiga/kwin4_effect_geometry_change)** and enable it in:

**System Settings → Desktop Effects → GeometryChange**

---

## Quick install

```bash
git clone <repo>
cd plasma-dropdown-any
bash install.sh
```

`install.sh` installs the KWin script, the Plasma widget, and the slide effect via `kpackagetool6`, enables the ones it installs in `kwinrc`, and reloads KWin — no logout required for the script itself.

To install/upgrade only some of them, pass their names:

```bash
bash install.sh effect           # only the slide effect
bash install.sh script plasmoid  # script + widget, skip the effect
```

With no arguments it installs all three (`script`, `plasmoid`, `effect`), same as before.

Then open the settings window:

```bash
bash configure
# equivalent to: plasmawindowed org.kde.plasma.dropdownany
```

You can also add **Dropdown Any** as a panel widget from the usual "Add Widgets" picker if you'd rather keep it pinned somewhere.

> After **Apply**, KWin doesn't pick up the new slot config automatically. The widget will tell you to disable and re-enable the script from **System Settings → KWin Scripts → "Dropdown Any Window"** — that one step still needs to be manual. If you're using the bundled slide effect (see below) and changed a slot's animation style, also disable and re-enable **Desktop Effects → "Dropdown Any — Slide"**.

---

## Configuration

The widget's settings window has three tabs — **Slots**, **Temporary slots**, and **Tile pairs** — each backed by its own list, so a slot never has to carry an unused "temporary" checkbox or an unused class field.

Each slot row in the Slots and Temporary slots tabs shows only the basics — App (or a fixed label for temporary slots), Shortcut, Width %, Height % — plus a ▼ button that expands the row to reveal Screen, Opacity, Slides from, Style, Duration, All workspaces, and Auto-hide.

Each slot is configured independently with the following fields:

| Field | Description | Example |
|-------|-------------|---------|
| Window class | The window's `resourceClass` | `konsole`, `kitty`, `sublime_text` |
| Shortcut | Global shortcut key | `F12`, `Meta+F1`, `Ctrl+F12` |
| Width % | Window width as a percentage of the screen | `100` |
| Height % | Window height as a percentage of the screen | `50` |
| Screen | Where the dropdown opens | Cursor screen, Screen 1, Screen 2… |
| Opacity % | Window alpha on show (0–100) | `90` |
| All workspaces | Pin the window to all virtual desktops | ✓ |
| Auto-hide on focus loss | Hide automatically when the window loses focus | ✓ |
| Keep above other windows | Stay floating on top when focus moves to another app; unchecked, it falls behind like a normal window instead. Only matters while shown and not hidden by auto-hide. Default: on | ✓ |

The **Temporary slots** tab has every field above except Window class — see below.

### Temporary slots

A regular slot (Slots tab) always toggles the same window class. A **temporary slot** (Temporary slots tab) has every other field (width, height, screen, opacity, direction, style…) but no class field — it binds to whatever app is focused the first time you press its shortcut:

1. Go to the **Temporary slots** tab, click **Add temporary slot**, set a shortcut.
2. Focus any app and press that shortcut — it binds to that app's class and immediately slides it away (same as a normal slot's hide).
3. Press the same shortcut again to show/hide it like any other slot.
4. Close the app entirely — the slot un-binds itself and goes back to empty, ready to bind to a different app next time.

The binding lives only in the running KWin script (never written to `kwinrc`), so it doesn't survive a script reload — you rebind by triggering the shortcut again.

**Releasing without closing the app:** a single global shortcut, **Release active temp slot** (default `Meta+Shift+X`, configurable in **Global shortcuts** alongside Repeat last activated and the resize shortcuts), un-binds whichever temp slot's window is currently focused/active — without closing the app — restoring the window to normal if it was currently hidden. That slot goes back to empty and is ready to bind to a different app on its next trigger. With several temp slots bound at once, this targets only the one that's currently active — show it first (its own toggle shortcut) if it isn't already.

Binding and releasing a temp slot each show a brief OSD confirmation (e.g. "Temp slot 1 bound to konsole" / "Temp slot 1 released (konsole)") — regular show/hide toggles don't, to stay unobtrusive.

**Animation:** since a temporary slot's class isn't known ahead of time, it can't get a per-slot style/duration like regular slots do. Instead, all temporary slots share one fallback style/duration, set at the bottom of the **Temporary slots** tab (separate from each regular slot's own Style/Duration fields). The bundled slide effect recognizes a temporary slot's window by behavior — it always has `skipSwitcher` set while being moved (the only one of `skipTaskbar`/`skipPager`/`skipSwitcher` actually exposed to KWin effects) — rather than by a pre-registered class list.

### Live resize shortcuts

While a dropdown window is active (focused), four shortcuts adjust its size in real time:

| Shortcut (default) | Action |
|----------|--------|
| `Alt+Shift+Up` | Increase height by 5 % |
| `Alt+Shift+Down` | Decrease height by 5 % |
| `Alt+Shift+Right` | Increase width by 5 % |
| `Alt+Shift+Left` | Decrease width by 5 % |

Changes apply immediately and are persisted to `kwinrc` — the new percentages survive script reloads and system restarts. The Configure dialog reflects the updated values on next open.

The shortcuts only do anything when the active window is a managed dropdown (including a bound temporary slot). If any other window is focused, they are silently ignored.

There's also a **Repeat last activated** shortcut (default `Meta+Shift+R`) that re-triggers whichever slot or tile pair you last toggled via its own shortcut — handy for a keyboard-only "do that again" without remembering which key belongs to it.

There's also **Release active temp slot** (default `Meta+Shift+X`) — see [Temporary slots](#temporary-slots) above.

**List slots/tiles + shortcuts** (default `Meta+Shift+S`) shows an OSD cheat sheet of every configured slot and tile pair with its shortcut, plus all the global shortcuts below — a quick reference without opening the widget.

All seven of these are configurable from the widget's **Global shortcuts** section, alongside the per-slot ones.

> **Note:** KWin scripting requires all shortcuts to be registered with KDE's global shortcut system (KGlobalAccel). They will also appear in **System Settings → Keyboard → Shortcuts → KWin**. This is a platform limitation — there is no way to have "private" shortcuts in a KWin script.

### Finding a window's resource class

The settings window's "Window class" field is a dropdown auto-populated with every currently open window — pick one instead of typing it by hand. It refreshes on open, or with the refresh button next to it.

Independently of the widget, you can also press **`Meta+Shift+W`** anywhere to get an OSD listing all open windows and their resource classes (e.g. `obsidian · sublime_text · vivaldi-stable`). The shortcut is configurable in System Settings → Shortcuts → KWin → *"Dropdown Any: List active window classes"*.

> On some KWin builds, the widget's window-list detection can't read the script output back through the systemd journal (observed on Fedora — harmless, still unresolved upstream). When that happens it falls back to an on-screen popup plus a brief, automatically-restored use of your clipboard, and the widget shows a status message saying so. The "Window class" field stays fully usable either way — worst case, type the class in by hand.

If the field comes up empty and typing manually isn't convenient, run the same shortcut above (**`Meta+Shift+W`**) to read the class off the OSD.

### Manual config via terminal

```bash
kwriteconfig6 --file kwinrc --group "Script-plasma-dropdown-any" \
  --key windowClass1 "konsole" \
  --key shortcut1    "F12" \
  --key widthPercent1  "100" \
  --key heightPercent1 "50"
```

Reload the script after changing config manually:

```bash
qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript "plasma-dropdown-any"
qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.start
```

---

## Behavior

When the shortcut fires:

- **Window is active (focused)** → slides off-screen (hidden, removed from taskbar/switcher).
- **Window is off-screen or minimized** → repositioned on the configured screen at the configured size, shown above all other windows.

Config changes (screen, size, opacity) take effect on the next **show**. No reload required for most settings.

---

## App not running yet?

The script only toggles windows that already exist — it can't launch an app for you. If the target window isn't found, the shortcut just does nothing (or shows "Window not found" in debug mode).

This isn't a missing feature so much as a platform limitation: launching an arbitrary command requires a DBus call with a complex argument type (`systemd`'s `StartTransientUnit`, the standard way to spawn a managed process, needs a nested struct for `ExecStart`) that KWin's scripting `callDBus()` can't construct from plain JavaScript — only flat arguments (strings, numbers, string lists) marshal correctly. No simpler general-purpose "run this command" DBus method was found.

**Workaround — autostart the app minimized.** Instead of launching on demand, have the app start automatically (and get out of the way) when your session begins, so it's already there the first time you press the shortcut:

1. Add the app to **System Settings → Autostart** (or drop a `.desktop` file in `~/.config/autostart/`).
2. If the app supports a "start minimized"/"start in tray" flag (many terminals, chat clients, and note apps do), enable it — otherwise the very first show will just look like a slide-in of an already-open window.

This trades a bit of session startup cost and RAM for an instant, reliable toggle — no launch delay, no "press twice" step.

---

## Project structure

```
plasma-dropdown-any/
├── metadata.json                    # KWin/Script manifest (X-Plasma-API: javascript)
├── contents/
│   └── code/main.js                 # Core KWin script logic (toggle, shortcuts, geometry)
├── plasmoid/                        # Settings UI — Plasma/Applet package
│   ├── metadata.json                # org.kde.plasma.dropdownany
│   └── contents/
│       ├── ui/main.qml              # PlasmoidItem entry point
│       ├── ui/ConfigEditor.qml      # Slot list, fields, window-class picker
│       ├── ui/ExecBridge.qml        # Plasma5Support subprocess wrapper
│       └── code/config-helper.sh    # kwinrc/DBus bridge — no compiled backend
├── configure                        # Shortcut: opens the settings window standalone
├── install.sh                       # kpackagetool6 install (both packages) + reload KWin
└── uninstall.sh
```

Config is stored in `~/.config/kwinrc` under `[Script-plasma-dropdown-any]`.

Shortcuts are stored in `~/.config/kglobalshortcutsrc` under `[kwin]` with key `DropdownAny-<windowClass>`.

---

## Debugging

### 1. Verify the script loaded

```bash
qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.isScriptLoaded "plasma-dropdown-any"
# → true
```

### 2. Watch logs in real time

```bash
journalctl -t kwin_wayland -f --no-pager | grep "DropdownAny"
```

On load, the script prints:
```
[DropdownAny] loaded — 1/10 slots active.
```

### 3. Trigger a shortcut manually (no keyboard)

```bash
qdbus6 org.kde.kglobalaccel /component/kwin \
  org.kde.kglobalaccel.Component.invokeShortcut "DropdownAny-<windowClass>"
# Example: "DropdownAny-konsole"
```

### 4. Verify a shortcut is registered

```bash
grep "DropdownAny" ~/.config/kglobalshortcutsrc
# Should show: DropdownAny-<class>=<key>,<default>,<description>
```

If the entry shows an empty or `none` shortcut, set it manually:

```bash
kwriteconfig6 --file kglobalshortcutsrc --group kwin \
  --key "DropdownAny-konsole" "F12,F12,Dropdown toggle: konsole"
```

### 5. Check a window's geometry

```bash
cat > /tmp/kwin_check.js << 'EOF'
var wins = (typeof workspace.windows !== 'undefined') ? workspace.windows
           : workspace.windowList();  // pre-KWin-6 fallback
wins.forEach(function(w) {
  if (w.resourceClass === "konsole") {
    var g = w.frameGeometry;
    console.log("[CHECK] geo=" + g.x.toFixed(0) + "," + g.y.toFixed(0) +
                " " + g.width.toFixed(0) + "x" + g.height.toFixed(0) +
                " keepAbove=" + w.keepAbove + " opacity=" + w.opacity);
  }
});
EOF

ID=$(qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript /tmp/kwin_check.js)
qdbus6 org.kde.KWin /Scripting/Script${ID} org.kde.kwin.Script.run
sleep 0.5
journalctl -t kwin_wayland -n 10 --no-pager | grep "CHECK"
```

### 6. Reload the script

```bash
qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript "plasma-dropdown-any"
sleep 0.5
qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.start
```

> `start` only loads scripts that are **not already loaded**. Always unload first.

### 7. Reinstall from scratch

```bash
bash uninstall.sh
bash install.sh
```

`uninstall.sh` also wipes your slot/tile config (`kwinrc`'s `[Script-plasma-dropdown-any]` and `[Effect-plasma-dropdown-any-slide]` groups, plus this plugin's `kglobalshortcutsrc` entries) by default. To reinstall/upgrade without losing your configured slots, keep it:

```bash
bash uninstall.sh --keep-config
bash install.sh
```

Note this is only relevant to `uninstall.sh` — plain `bash install.sh` (upgrading in place, the normal workflow after a code change) never touches your config; it only replaces the package files and re-enables the plugins.

---

## Known Plasma 6 gotchas

| Issue | Cause | Fix |
|-------|-------|-----|
| `Qt is not defined` | `Qt` namespace is not available in KWin JS scripts on Plasma 6 | Mutate the `QRectF` returned by `clientArea()` instead of using `Qt.rect()` |
| `readConfig is not defined` in QML | KWin globals are not injected into `declarativescript` in some versions | Use `X-Plasma-API: javascript` with `main.js` |
| Shortcut registered as `none` | The requested key was already taken by another app (e.g. F12 → Yakuake) | Use a different shortcut or set it manually in `kglobalshortcutsrc` |
| `unloadScript` returns `false` | Script was not loaded (normal on first run) | Ignore, proceed with `start` |
| Script does not reload with just `start` | KWin does not reload scripts already in memory | Always run `unloadScript` + `start` |
| `workspace.windowList is not a function` | Renamed to `workspace.windows` (list property) in KWin 6 | `config-helper.sh` tries `workspace.windows` → `windowList()` → `clientList()` in that order |
| `qdbus: command not found` from the widget | Plasma5Support's `executable` engine runs with a restricted `PATH`; some distros ship `qdbus-qt6` instead of `qdbus6` | `find_dbus_cmd()` probes `qdbus6`, `qdbus-qt6`, `qdbus`, and common Qt6 install paths |
| Window-class dropdown stays empty, no error | The temp script's `print()` output never reaches `journalctl --user` on some KWin builds (seen on Fedora; SELinux, logging categories, and KWin version were all ruled out — root cause still unconfirmed) | Falls back to an OSD popup + a brief Klipper clipboard round-trip (restored after); type the class in manually as a last resort |
| Settings window itself shows up as a toggle target | The widget's own process (`org.kde.plasmawindowed`) wasn't excluded from the window scan | Excluded in `config-helper.sh`'s skip list alongside `plasmashell`/`systemsettings`/`ksmserver` |
| Config saved but nothing changes | KWin doesn't reload script config on `/KWin reconfigure` alone | Disable and re-enable the script in System Settings → KWin Scripts (the widget tells you this after every save) |

---

## Uninstall

```bash
bash uninstall.sh
```

Removes the packages and wipes your slot/tile config. Pass `--keep-config` to remove only the packages and leave your configured slots in `kwinrc` alone (useful for reinstalling — see [Reinstall from scratch](#7-reinstall-from-scratch)).
