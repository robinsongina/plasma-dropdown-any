# plasma-dropdown-any

KWin script for Plasma 6 that turns any window into a Yakuake-style dropdown panel — shown and hidden with a configurable global shortcut.

Works with **any application** identified by its `resourceClass` (Konsole, Kitty, Sublime Text, Obsidian, etc.). Up to 10 independent slots, each with its own shortcut and settings.

---

## Dependencies

### Runtime

| Dependency | Notes |
|-----------|-------|
| **Plasma 6 / KWin 6** | Required — the script runs inside the KWin scripting engine |
| **kpackagetool6** | Required — used by `install.sh` to register the script package |
| **qdbus6** | Required — used by `install.sh` to reload KWin after install |

### Build (KCM configuration module)

The KCM is a C++ plugin that must be compiled before installing. You need:

| Dependency | Min version | Arch package | Fedora package |
|-----------|------------|--------------|----------------|
| CMake | 3.20 | `cmake` | `cmake` |
| Extra CMake Modules | 6.0 | `extra-cmake-modules` | `extra-cmake-modules` |
| GCC or Clang | C++17 | `gcc` | `gcc` |
| Qt6 (Core, Quick, DBus) | 6.x | `qt6-base` `qt6-declarative` | `qt6-qtbase-devel` `qt6-qtdeclarative-devel` |
| KF6 KCMUtils | 6.x | `kcmutils` | `kf6-kcmutils-devel` |
| KF6 Config | 6.x | `kconfig` | `kf6-kconfig-devel` |
| KF6 CoreAddons | 6.x | `kcoreaddons` | `kf6-kcoreaddons-devel` |

**Arch / CachyOS / Manjaro:**
```bash
sudo pacman -S cmake extra-cmake-modules gcc qt6-base qt6-declarative \
               kcmutils kconfig kcoreaddons
```

**Fedora:**
```bash
sudo dnf install cmake extra-cmake-modules gcc-c++ \
                 qt6-qtbase-devel qt6-qtdeclarative-devel \
                 kf6-kcmutils-devel kf6-kconfig-devel kf6-kcoreaddons-devel
```

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

Then **log out and log back in** so the KCM plugin path is picked up by Plasma. After that:

**System Settings → Window Management → KWin Scripts → plasma-dropdown-any → Configure**

> If the **Configure** button doesn't appear after logging back in, make sure all build dependencies were installed before running `install.sh`. Missing KF6 packages cause the KCM to silently skip compilation.

---

## Configuration

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

### Live resize shortcuts

While a dropdown window is active (focused), four shortcuts adjust its size in real time:

| Shortcut | Action |
|----------|--------|
| `Alt+Shift+Up` | Increase height by 5 % |
| `Alt+Shift+Down` | Decrease height by 5 % |
| `Alt+Shift+Right` | Increase width by 5 % |
| `Alt+Shift+Left` | Decrease width by 5 % |

Changes apply immediately and are persisted to `kwinrc` — the new percentages survive script reloads and system restarts. The Configure dialog reflects the updated values on next open.

The shortcuts only do anything when the active window is a managed dropdown. If any other window is focused, they are silently ignored.

> **Note:** KWin scripting requires all shortcuts to be registered with KDE's global shortcut system (KGlobalAccel). These four shortcuts will appear in **System Settings → Keyboard → Shortcuts → KWin**. This is a platform limitation — there is no way to have "private" shortcuts in a KWin script. The default key bindings can be changed or removed from that dialog.

### Finding a window's resource class

With the script active, press **`Meta+Shift+W`**. An OSD lists all open windows and their resource classes (e.g. `obsidian · sublime_text · vivaldi-stable`).

The shortcut is configurable in System Settings → Shortcuts → KWin → *"Dropdown Any: List active window classes"*.

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

## Project structure

```
plasma-dropdown-any/
├── metadata.json              # Plugin manifest (X-Plasma-API: javascript)
├── contents/
│   └── code/main.js           # Core KWin script logic
├── kcm/                       # System Settings configuration module (C++ + QML)
│   ├── CMakeLists.txt
│   ├── kcm_dropdown_any.h
│   ├── kcm_dropdown_any.cpp
│   └── ui/main.qml
├── install.sh                 # Build KCM + install script + reload KWin
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
workspace.windowList().forEach(function(w) {
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

---

## Known Plasma 6 gotchas

| Issue | Cause | Fix |
|-------|-------|-----|
| `Qt is not defined` | `Qt` namespace is not available in KWin JS scripts on Plasma 6 | Mutate the `QRectF` returned by `clientArea()` instead of using `Qt.rect()` |
| `readConfig is not defined` in QML | KWin globals are not injected into `declarativescript` in some versions | Use `X-Plasma-API: javascript` with `main.js` |
| Shortcut registered as `none` | The requested key was already taken by another app (e.g. F12 → Yakuake) | Use a different shortcut or set it manually in `kglobalshortcutsrc` |
| `unloadScript` returns `false` | Script was not loaded (normal on first run) | Ignore, proceed with `start` |
| Script does not reload with just `start` | KWin does not reload scripts already in memory | Always run `unloadScript` + `start` |
| **Configure** button missing in System Settings | Missing `X-KDE-ConfigModule` in `metadata.json` | Add `"X-KDE-ConfigModule": "kwin/effects/configs/kcm_dropdown_any"` |

---

## Uninstall

```bash
bash uninstall.sh
```
