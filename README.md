# plasma-dropdown-any

KWin script para Plasma 6 que convierte cualquier ventana en un panel dropdown estilo Yakuake — activada y ocultada con un shortcut global configurable.

Funciona con **cualquier aplicación** identificada por su `resourceClass` (Konsole, Kitty, Sublime Text, Obsidian, etc.). Hasta 10 ventanas independientes, cada una con su propio shortcut.

---

## Instalación rápida

```bash
git clone <repo>
cd plasma-dropdown-any
bash install.sh
```

Después: **System Settings → Window Management → KWin Scripts → plasma-dropdown-any → Configure**

---

## Configuración

Cada slot tiene dos campos:

| Campo | Descripción | Ejemplo |
|-------|-------------|---------|
| Window class | El `resourceClass` de la ventana | `konsole`, `kitty`, `sublime_text` |
| Default shortcut | Tecla inicial (se puede cambiar luego en System Settings → Shortcuts) | `F12`, `Meta+F1`, `Ctrl+F12` |

**Encontrar el resourceClass de una ventana — forma rápida:**

Con el script activo, presioná `Meta+Shift+W`. Aparece un OSD con todas las clases de ventanas abiertas en ese momento (ej: `obsidian · sublime_text · vivaldi-stable`).

El shortcut es configurable en System Settings → Shortcuts → KWin → "Dropdown Any: List active window classes".

**Alternativa manual desde terminal:**

```bash
qdbus6 org.kde.KWin /KWin org.kde.KWin.supportInformation 2>/dev/null | grep -o 'resourceClass.*' | head -20
```

**Configurar manualmente desde terminal:**

```bash
kwriteconfig6 --file kwinrc --group "Script-plasma-dropdown-any" --key windowClass1 "konsole"
kwriteconfig6 --file kwinrc --group "Script-plasma-dropdown-any" --key shortcut1    "F12"
kwriteconfig6 --file kwinrc --group "Script-plasma-dropdown-any" --key heightPercent "50"
```

Recargar el script después de cambiar config:

```bash
qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript "plasma-dropdown-any"
qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.start
```

---

## Comportamiento

Al presionar el shortcut:

- **Ventana activa** → se minimiza.
- **Ventana minimizada o inactiva** → se posiciona en el top de la pantalla (ancho 100%, altura configurable), se activa con `keepAbove=true`.

La animación usa el efecto de minimizar configurado en KWin. Para el slide estilo Yakuake: activar **Desktop Effects → Slide** en System Settings.

---

## Arquitectura

```
plasma-dropdown-any/
├── metadata.json              # Manifest del plugin (X-Plasma-API: javascript)
├── contents/
│   ├── code/main.js           # Lógica principal
│   ├── config/main.xml        # Schema KConfigXT (10 slots + heightPercent)
│   └── ui/config.qml          # UI de configuración en System Settings
├── install.sh                 # kpackagetool6 wrapper
└── uninstall.sh
```

**Config** se almacena en `~/.config/kwinrc` bajo `[Script-plasma-dropdown-any]`.

**Shortcuts** se almacenan en `~/.config/kglobalshortcutsrc` bajo `[kwin]` con el ID `DropdownAny-<windowClass>`.

---

## Debugging

### 1. Verificar que el script cargó

```bash
qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.isScriptLoaded "plasma-dropdown-any"
# → true
```

### 2. Ver logs en tiempo real

```bash
journalctl -t kwin_wayland -f --no-pager | grep "DropdownAny"
```

El script loguea al cargar:
```
[DropdownAny] loaded — 1/10 slots active.
```

### 3. Disparar el shortcut manualmente (sin teclado)

```bash
qdbus6 org.kde.kglobalaccel /component/kwin \
  org.kde.kglobalaccel.Component.invokeShortcut "DropdownAny-<windowClass>"
# Ejemplo: "DropdownAny-konsole"
```

### 4. Verificar que el shortcut está registrado

```bash
grep "DropdownAny" ~/.config/kglobalshortcutsrc
# Debe mostrar: DropdownAny-<class>=<key>,<default>,<description>
```

Si aparece con shortcut vacío o `none`, forzar manualmente:

```bash
kwriteconfig6 --file kglobalshortcutsrc --group kwin \
  --key "DropdownAny-konsole" "F12,F12,Dropdown toggle: konsole"
```

### 5. Verificar la geometría de una ventana

```bash
cat > /tmp/kwin_check.js << 'EOF'
workspace.windowList().forEach(function(w) {
  if (w.resourceClass === "konsole") {
    var g = w.frameGeometry;
    console.log("[CHECK] min=" + w.minimized +
                " geo=" + g.x.toFixed(0) + "," + g.y.toFixed(0) +
                " " + g.width.toFixed(0) + "x" + g.height.toFixed(0) +
                " keepAbove=" + w.keepAbove);
  }
});
EOF

ID=$(qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript /tmp/kwin_check.js "check")
qdbus6 org.kde.KWin /Scripting/Script${ID} org.kde.kwin.Script.run
sleep 0.5
journalctl -t kwin_wayland -n 10 --no-pager | grep "CHECK"
```

### 6. Recargar el script

```bash
qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript "plasma-dropdown-any"
sleep 0.5
qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.start
```

> `start` solo carga scripts que **no están ya cargados**. Hay que hacer el unload primero.

### 7. Reinstalar desde cero

```bash
bash uninstall.sh
bash install.sh
```

---

## Gotchas conocidos de Plasma 6

| Problema | Causa | Solución |
|----------|-------|----------|
| `Qt is not defined` | `Qt` no está disponible en KWin JS scripts en Plasma 6 | Mutar el QRectF devuelto por `clientArea()` en lugar de `Qt.rect()` |
| `readConfig is not defined` en QML | Los globals de KWin no se inyectan en scripts `declarativescript` en algunas versiones | Usar `X-Plasma-API: javascript` con `main.js` |
| Shortcut registrado con `none` | El shortcut pedido ya estaba tomado por otra app (ej. F12 → Yakuake) | Usar otro shortcut o forzar en `kglobalshortcutsrc` manualmente |
| `unloadScript` retorna `false` | El script no estaba cargado (normal en el primer run) | Ignorar, seguir con `start` |
| Script no recarga con solo `start` | KWin no recarga scripts ya en memoria | Siempre hacer `unloadScript` + `start` |
| `metadata.json` sin `X-Plasma-MainScript` | KWin no sabe qué archivo ejecutar | Siempre incluir este campo |
| Botón **Configure** no aparece en System Settings | Falta `X-KDE-ConfigModule` en `metadata.json` | Agregar `"X-KDE-ConfigModule": "kwin/effects/configs/kcm_kwin4_genericscripted"` |

---

## Desinstalar

```bash
bash uninstall.sh
```
