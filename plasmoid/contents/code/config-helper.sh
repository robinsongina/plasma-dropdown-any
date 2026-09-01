#!/usr/bin/env bash
# config-helper.sh — shell bridge for plasma-dropdown-any plasmoid
#
# Subcommands:
#   load            Read all slots from kwinrc; emit JSON to stdout
#   save <json>     Write all slots and shortcuts from JSON argument
#   list-windows    List running window classes (one "class → title" per line)
#   list-screens    List screen names (one per line, first: "At cursor screen")
#   reload-script   Reload plasma-dropdown-any KWin script via DBus
#   check-tools     Check required tools; emit JSON to stdout
#
# Exit codes:
#   0   success
#   1   required tool missing from PATH
#   2   tool present but operation failed
#
# SPDX-License-Identifier: GPL-2.0-or-later

set -euo pipefail

# ─── constants ──────────────────────────────────────────────────────────────────
readonly KWIN_GROUP="Script-plasma-dropdown-any"

# ─── utility functions ──────────────────────────────────────────────────────────

usage() {
  cat >&2 <<'EOF'
Usage: config-helper.sh <subcommand> [args]

Subcommands:
  load                Read all slots from kwinrc; emit JSON to stdout
  save <json>         Write all slots + shortcuts from JSON argument
  list-windows        List running window classes (one "class → title" per line)
  list-screens        List screen names (one per line, first: "At cursor screen")
  reload-script       Reload plasma-dropdown-any KWin script via DBus
  check-tools         Check required tools; emit JSON to stdout

Exit codes:
  0   success
  1   required tool missing from PATH
  2   tool present but operation failed
EOF
  exit 1
}

require_tool() {
  local tool="$1"
  if ! command -v "$tool" &>/dev/null; then
    echo "ERROR: required tool '${tool}' not found on PATH" >&2
    exit 1
  fi
}

require_python3() {
  if ! command -v python3 &>/dev/null; then
    echo '{"error":"python3 not found on PATH — JSON operations unavailable"}' >&2
    exit 2
  fi
}

# Return the first available DBus command (qdbus6 preferred, qdbus fallback).
# Exits 1 if neither is found.
# Plasma5Support DataSource runs with a restricted PATH, so we also probe
# common Qt6 installation directories explicitly.
find_dbus_cmd() {
  local _candidates=(
    qdbus6 qdbus-qt6 qdbus
    /usr/bin/qdbus6 /usr/bin/qdbus-qt6 /usr/bin/qdbus
    /usr/lib/qt6/bin/qdbus6
    /usr/lib/x86_64-linux-gnu/qt6/bin/qdbus6
    /usr/lib64/qt6/bin/qdbus6
    /usr/local/lib/qt6/bin/qdbus6
    /usr/lib/qt/bin/qdbus6
  )
  local _c
  for _c in "${_candidates[@]}"; do
    if command -v "$_c" &>/dev/null 2>&1 || [[ -x "$_c" ]]; then
      echo "$_c"
      return 0
    fi
  done
  echo "ERROR: neither qdbus6 nor qdbus found on PATH or common Qt6 paths" >&2
  exit 1
}

# ─── subcommand: load ────────────────────────────────────────────────────────────
# Reads all slots from kwinrc [Script-plasma-dropdown-any].
# Emits a JSON object: { slotCount, debugMode, slots[] }
# Matches the C++ load() new-format (slotCount present) and legacy-format (scan
# up to 10, skip blank entries) behaviour exactly.

cmd_load() {
  require_tool kreadconfig6
  require_python3

  local slot_count_raw=""
  slot_count_raw=$(kreadconfig6 --file kwinrc \
    --group "$KWIN_GROUP" --key slotCount 2>/dev/null || true)

  local kwin_group="$KWIN_GROUP"
  local sc_raw="${slot_count_raw}"

  python3 <<PYEOF
import subprocess, json, sys

KWIN_GROUP = "${kwin_group}"

def kread(key, default=""):
    r = subprocess.run(
        ["kreadconfig6", "--file", "kwinrc", "--group", KWIN_GROUP, "--key", key],
        capture_output=True, text=True)
    v = r.stdout.strip()
    return v if v else default

def to_int(val, default):
    try:
        return int(val)
    except (ValueError, TypeError):
        return default

sc_str = "${sc_raw}".strip()
slot_count = int(sc_str) if sc_str.lstrip("-").isdigit() else -1

slots = []
if slot_count >= 0:
    # New format: read exactly slot_count slots
    for i in range(1, slot_count + 1):
        n = str(i)
        slots.append({
            "windowClass":   kread(f"windowClass{n}"),
            "shortcut":      kread(f"shortcut{n}"),
            "widthPercent":  to_int(kread(f"widthPercent{n}",  "100"), 100),
            "heightPercent": to_int(kread(f"heightPercent{n}", "50"),  50),
            "screenTarget":  to_int(kread(f"screenTarget{n}",  "0"),   0),
            "opacity":       to_int(kread(f"opacity{n}",       "100"), 100),
            "allDesktops":   kread(f"allDesktops{n}", "false") == "true",
            "autoHide":      kread(f"autoHide{n}",    "false") == "true",
            "keepAbove":     kread(f"keepAbove{n}",   "true")  == "true",
            "direction":     kread(f"direction{n}",   "top"),
            "animationStyle": kread(f"animationStyle{n}", "Smooth"),
            "animationDuration": to_int(kread(f"animationDuration{n}", "250"), 250),
            "temporary":     kread(f"temporary{n}", "false") == "true",
        })
else:
    # Legacy format: no slotCount key; scan up to 10, skip blank entries
    for i in range(1, 11):
        n = str(i)
        cls = kread(f"windowClass{n}")
        sc  = kread(f"shortcut{n}")
        if not cls and not sc:
            continue
        slots.append({
            "windowClass":   cls,
            "shortcut":      sc,
            "widthPercent":  to_int(kread(f"widthPercent{n}",  "100"), 100),
            "heightPercent": to_int(kread(f"heightPercent{n}", "50"),  50),
            "screenTarget":  to_int(kread(f"screenTarget{n}",  "0"),   0),
            "opacity":       to_int(kread(f"opacity{n}",       "100"), 100),
            "allDesktops":   kread(f"allDesktops{n}", "false") == "true",
            "autoHide":      kread(f"autoHide{n}",    "false") == "true",
            "keepAbove":     kread(f"keepAbove{n}",   "true")  == "true",
            "direction":     kread(f"direction{n}",   "top"),
            "animationStyle": kread(f"animationStyle{n}", "Smooth"),
            "animationDuration": to_int(kread(f"animationDuration{n}", "250"), 250),
            "temporary":     kread(f"temporary{n}", "false") == "true",
        })

debug_mode = kread("debugMode", "false") == "true"

# Fixed global shortcuts (not per-slot) — repeat-last and live resize.
# Defaults match the hardcoded values main.js used before these became
# configurable, so existing installs keep behaving the same until changed.
repeat_last_shortcut       = kread("repeatLastShortcut",       "Meta+Shift+R")
resize_height_inc_shortcut = kread("resizeHeightIncShortcut",  "Alt+Shift+Up")
resize_height_dec_shortcut = kread("resizeHeightDecShortcut",  "Alt+Shift+Down")
resize_width_inc_shortcut  = kread("resizeWidthIncShortcut",   "Alt+Shift+Right")
resize_width_dec_shortcut  = kread("resizeWidthDecShortcut",   "Alt+Shift+Left")
release_temp_slot_shortcut = kread("releaseTempSlotShortcut",  "Meta+Shift+X")

# Shared fallback animation for temporary slots — the effect can't look up
# a per-slot style/duration for these since their class isn't known until
# runtime (see effect/contents/code/main.js header comment).
temp_slot_animation_style    = kread("tempSlotAnimationStyle",    "Smooth")
temp_slot_animation_duration = to_int(kread("tempSlotAnimationDuration", "250"), 250)

# Tile pairs: always new-format (no legacy data predates this feature).
tile_count_str = kread("tileCount", "0")
tile_count = int(tile_count_str) if tile_count_str.lstrip("-").isdigit() else 0

tiles = []
for i in range(1, tile_count + 1):
    n = str(i)
    tiles.append({
        "classLeft":     kread(f"tileClassLeft{n}"),
        "classRight":    kread(f"tileClassRight{n}"),
        "shortcut":      kread(f"tileShortcut{n}"),
        "splitPercent":  to_int(kread(f"tileSplitPercent{n}",  "50"),  50),
        "widthPercent":  to_int(kread(f"tileWidthPercent{n}",  "100"), 100),
        "heightPercent": to_int(kread(f"tileHeightPercent{n}", "100"), 100),
        "screenTarget":  to_int(kread(f"tileScreenTarget{n}",  "0"),   0),
        "opacity":       to_int(kread(f"tileOpacity{n}",       "100"), 100),
        "allDesktops":   kread(f"tileAllDesktops{n}", "false") == "true",
        "autoHide":      kread(f"tileAutoHide{n}",    "false") == "true",
        "direction":     kread(f"tileDirection{n}",   "top"),
        "orientation":   kread(f"tileOrientation{n}", "horizontal"),
        "animationStyle": kread(f"tileAnimationStyle{n}", "Smooth"),
        "animationDuration": to_int(kread(f"tileAnimationDuration{n}", "250"), 250),
    })

print(json.dumps({
    "slotCount": len(slots),
    "debugMode":  debug_mode,
    "slots":      slots,
    "tileCount":  len(tiles),
    "tiles":      tiles,
    "repeatLastShortcut":       repeat_last_shortcut,
    "resizeHeightIncShortcut":  resize_height_inc_shortcut,
    "resizeHeightDecShortcut":  resize_height_dec_shortcut,
    "resizeWidthIncShortcut":   resize_width_inc_shortcut,
    "resizeWidthDecShortcut":   resize_width_dec_shortcut,
    "releaseTempSlotShortcut":  release_temp_slot_shortcut,
    "tempSlotAnimationStyle":    temp_slot_animation_style,
    "tempSlotAnimationDuration": temp_slot_animation_duration
}))
PYEOF
}

# ─── subcommand: save ────────────────────────────────────────────────────────────
# Accepts a JSON string: { slotCount, debugMode, slots[] }
# 1. Reads old slot classes from kwinrc and deletes their shortcuts from
#    kglobalshortcutsrc [kwin] (mirrors C++ save() cleanup step).
# 2. Writes all slot fields to kwinrc; writes shortcuts for non-empty cls+sc.
# 3. Deletes stale entries (slots N+1 to 20) from kwinrc.

cmd_save() {
  [[ $# -ge 1 ]] || {
    echo "ERROR: save requires a JSON argument" >&2
    exit 2
  }
  require_tool kreadconfig6
  require_tool kwriteconfig6
  require_python3

  local json_input="$1"

  # ── Step 1: delete old shortcuts from kglobalshortcutsrc ──────────────────
  local old_count=""
  old_count=$(kreadconfig6 --file kwinrc \
    --group "$KWIN_GROUP" --key slotCount 2>/dev/null || true)
  [[ "$old_count" =~ ^[0-9]+$ ]] || old_count=10

  local i old_cls
  for i in $(seq 1 "$old_count"); do
    old_cls=$(kreadconfig6 --file kwinrc \
      --group "$KWIN_GROUP" --key "windowClass${i}" 2>/dev/null || true)
    if [[ -n "$old_cls" ]]; then
      kwriteconfig6 --file kglobalshortcutsrc --group kwin \
        --key "DropdownAny-${old_cls}" --delete 2>/dev/null || true
    fi
    # Temp slots never persist a class, so their shortcut is keyed by index
    # instead — delete unconditionally (harmless no-op if it wasn't temp).
    kwriteconfig6 --file kglobalshortcutsrc --group kwin \
      --key "DropdownAny-Temp${i}" --delete 2>/dev/null || true
  done

  # Tile shortcuts are keyed by pair index (not class — a pair has two
  # classes), so just delete DropdownTile-{i} for every previously-known slot.
  local old_tile_count=""
  old_tile_count=$(kreadconfig6 --file kwinrc \
    --group "$KWIN_GROUP" --key tileCount 2>/dev/null || true)
  [[ "$old_tile_count" =~ ^[0-9]+$ ]] || old_tile_count=10

  for i in $(seq 1 "$old_tile_count"); do
    kwriteconfig6 --file kglobalshortcutsrc --group kwin \
      --key "DropdownTile-${i}" --delete 2>/dev/null || true
  done

  # ── Step 2: write new config via Python (JSON parsing) ────────────────────
  local json_file=""
  json_file=$(mktemp /tmp/dropdown-save-XXXXXX.json)
  printf '%s' "$json_input" >"$json_file"

  local kwin_group="$KWIN_GROUP"

  python3 <<PYEOF || {
import json, subprocess

def kwrite(*args):
    subprocess.run(["kwriteconfig6"] + list(args), check=True, capture_output=True)

kwin_group = "${kwin_group}"

with open("${json_file}") as f:
    data = json.load(f)

slots      = data.get("slots", [])
debug_mode = data.get("debugMode", False)
count      = len(slots)

# Write slotCount and debugMode
kwrite("--file", "kwinrc", "--group", kwin_group,
       "--key", "slotCount", str(count))
kwrite("--file", "kwinrc", "--group", kwin_group,
       "--key", "debugMode", "--type", "bool",
       "true" if debug_mode else "false")

# ── Fixed global shortcuts (repeat-last + live resize) ─────────────────────
# Objects names below (DropdownAny-ToggleLast, etc.) must match the first
# argument of the matching registerShortcut() calls in contents/code/main.js.
global_shortcuts = {
    "repeatLastShortcut":      ("DropdownAny-ToggleLast",      "Meta+Shift+R",   "Dropdown Any: Toggle last activated slot/tile"),
    "resizeHeightIncShortcut": ("DropdownAny-ResizeHeightInc", "Alt+Shift+Up",   "Dropdown: Increase height"),
    "resizeHeightDecShortcut": ("DropdownAny-ResizeHeightDec", "Alt+Shift+Down", "Dropdown: Decrease height"),
    "resizeWidthIncShortcut":  ("DropdownAny-ResizeWidthInc",  "Alt+Shift+Right", "Dropdown: Increase width"),
    "resizeWidthDecShortcut":  ("DropdownAny-ResizeWidthDec",  "Alt+Shift+Left", "Dropdown: Decrease width"),
    "releaseTempSlotShortcut": ("DropdownAny-ReleaseTempSlot", "Meta+Shift+X",   "Dropdown Any: Release active temp slot"),
}
for key, (object_name, default_sc, description) in global_shortcuts.items():
    sc = data.get(key, "") or default_sc
    kwrite("--file", "kwinrc", "--group", kwin_group, "--key", key, sc)
    kwrite("--file", "kglobalshortcutsrc", "--group", "kwin",
           "--key", object_name, f"{sc},none,{description}")

# ── Temp slot fallback animation ────────────────────────────────────────────
# Kept here (window script's own group) as the source of truth for this
# plasmoid's load/save round-trip, and cross-written into the effect's own
# group below (same pattern as ManagedClasses) so it can actually read it.
temp_style    = data.get("tempSlotAnimationStyle", "Smooth") or "Smooth"
temp_duration = str(data.get("tempSlotAnimationDuration", 250))
kwrite("--file", "kwinrc", "--group", kwin_group, "--key", "tempSlotAnimationStyle", temp_style)
kwrite("--file", "kwinrc", "--group", kwin_group, "--key", "tempSlotAnimationDuration", temp_duration)
kwrite("--file", "kwinrc", "--group", "Effect-plasma-dropdown-any-slide",
       "--key", "TempSlotStyle", temp_style)
kwrite("--file", "kwinrc", "--group", "Effect-plasma-dropdown-any-slide",
       "--key", "TempSlotDurationMs", temp_duration)

# Write each slot; also write shortcuts for non-empty cls+sc pairs
for i, slot in enumerate(slots, 1):
    n       = str(i)
    is_temp = bool(slot.get("temporary", False))
    # A temp slot binds its class at runtime in the KWin script — never
    # persist a leftover class for one, regardless of what the UI sent.
    cls     = "" if is_temp else slot.get("windowClass", "")
    sc      = slot.get("shortcut", "")
    w_pct   = str(slot.get("widthPercent",  100))
    h_pct   = str(slot.get("heightPercent", 50))
    screen  = str(slot.get("screenTarget",  0))
    opacity = str(slot.get("opacity",       100))
    all_d   = "true" if slot.get("allDesktops", False) else "false"
    auto_h  = "true" if slot.get("autoHide",    False) else "false"
    keep_above = "true" if slot.get("keepAbove", True) else "false"
    direction = slot.get("direction", "top") or "top"
    anim_style = slot.get("animationStyle", "Smooth") or "Smooth"
    anim_duration = str(slot.get("animationDuration", 250))

    kwrite("--file", "kwinrc", "--group", kwin_group, "--key", f"windowClass{n}", cls)
    kwrite("--file", "kwinrc", "--group", kwin_group, "--key", f"shortcut{n}", sc)
    kwrite("--file", "kwinrc", "--group", kwin_group, "--key", f"widthPercent{n}", w_pct)
    kwrite("--file", "kwinrc", "--group", kwin_group, "--key", f"heightPercent{n}", h_pct)
    kwrite("--file", "kwinrc", "--group", kwin_group, "--key", f"screenTarget{n}", screen)
    kwrite("--file", "kwinrc", "--group", kwin_group, "--key", f"opacity{n}", opacity)
    kwrite("--file", "kwinrc", "--group", kwin_group, "--key", f"allDesktops{n}",
           "--type", "bool", all_d)
    kwrite("--file", "kwinrc", "--group", kwin_group, "--key", f"autoHide{n}",
           "--type", "bool", auto_h)
    kwrite("--file", "kwinrc", "--group", kwin_group, "--key", f"keepAbove{n}",
           "--type", "bool", keep_above)
    kwrite("--file", "kwinrc", "--group", kwin_group, "--key", f"direction{n}", direction)
    kwrite("--file", "kwinrc", "--group", kwin_group, "--key", f"animationStyle{n}", anim_style)
    kwrite("--file", "kwinrc", "--group", kwin_group, "--key", f"animationDuration{n}", anim_duration)
    kwrite("--file", "kwinrc", "--group", kwin_group, "--key", f"temporary{n}",
           "--type", "bool", "true" if is_temp else "false")

    # Shortcut format: "Meta+F1,none,Dropdown toggle: Konsole"
    # Matches C++ kwinGroup.writeEntry("DropdownAny-Konsole", "Meta+F1,none,Dropdown toggle: Konsole")
    # Temp slots have no persisted class, so they're keyed by index instead
    # (must match "DropdownAny-Temp" + idx in contents/code/main.js).
    if is_temp and sc:
        kwrite("--file", "kglobalshortcutsrc", "--group", "kwin",
               "--key", f"DropdownAny-Temp{n}",
               f"{sc},none,Dropdown temp slot {n} (binds to focused app)")
    if not is_temp and cls and sc:
        kwrite("--file", "kglobalshortcutsrc", "--group", "kwin",
               "--key", f"DropdownAny-{cls}",
               f"{sc},none,Dropdown toggle: {cls}")

# Delete stale entries beyond the current slot count (mirrors C++ cleanup to 20)
for i in range(count + 1, 21):
    n = str(i)
    for key in ["windowClass", "shortcut", "widthPercent", "heightPercent",
                "screenTarget", "opacity", "allDesktops", "autoHide", "keepAbove",
                "direction", "animationStyle", "animationDuration", "temporary"]:
        subprocess.run(
            ["kwriteconfig6", "--file", "kwinrc", "--group", kwin_group,
             "--key", f"{key}{n}", "--delete"],
            capture_output=True
        )

# ── Tile pairs ──────────────────────────────────────────────────────────────
tiles      = data.get("tiles", [])
tile_count = len(tiles)

kwrite("--file", "kwinrc", "--group", kwin_group,
       "--key", "tileCount", str(tile_count))

for i, tile in enumerate(tiles, 1):
    n          = str(i)
    cls_l      = tile.get("classLeft", "")
    cls_r      = tile.get("classRight", "")
    sc         = tile.get("shortcut", "")
    split_pct  = str(tile.get("splitPercent",  50))
    w_pct      = str(tile.get("widthPercent",  100))
    h_pct      = str(tile.get("heightPercent", 100))
    screen     = str(tile.get("screenTarget",  0))
    opacity    = str(tile.get("opacity",       100))
    all_d      = "true" if tile.get("allDesktops", False) else "false"
    auto_h     = "true" if tile.get("autoHide",    False) else "false"
    direction  = tile.get("direction", "top") or "top"
    orientation = tile.get("orientation", "horizontal") or "horizontal"
    anim_style = tile.get("animationStyle", "Smooth") or "Smooth"
    anim_duration = str(tile.get("animationDuration", 250))

    kwrite("--file", "kwinrc", "--group", kwin_group, "--key", f"tileClassLeft{n}", cls_l)
    kwrite("--file", "kwinrc", "--group", kwin_group, "--key", f"tileClassRight{n}", cls_r)
    kwrite("--file", "kwinrc", "--group", kwin_group, "--key", f"tileShortcut{n}", sc)
    kwrite("--file", "kwinrc", "--group", kwin_group, "--key", f"tileSplitPercent{n}", split_pct)
    kwrite("--file", "kwinrc", "--group", kwin_group, "--key", f"tileWidthPercent{n}", w_pct)
    kwrite("--file", "kwinrc", "--group", kwin_group, "--key", f"tileHeightPercent{n}", h_pct)
    kwrite("--file", "kwinrc", "--group", kwin_group, "--key", f"tileScreenTarget{n}", screen)
    kwrite("--file", "kwinrc", "--group", kwin_group, "--key", f"tileOpacity{n}", opacity)
    kwrite("--file", "kwinrc", "--group", kwin_group, "--key", f"tileAllDesktops{n}",
           "--type", "bool", all_d)
    kwrite("--file", "kwinrc", "--group", kwin_group, "--key", f"tileAutoHide{n}",
           "--type", "bool", auto_h)
    kwrite("--file", "kwinrc", "--group", kwin_group, "--key", f"tileDirection{n}", direction)
    kwrite("--file", "kwinrc", "--group", kwin_group, "--key", f"tileOrientation{n}", orientation)
    kwrite("--file", "kwinrc", "--group", kwin_group, "--key", f"tileAnimationStyle{n}", anim_style)
    kwrite("--file", "kwinrc", "--group", kwin_group, "--key", f"tileAnimationDuration{n}", anim_duration)

    # Shortcut is keyed by pair index, not class (a pair has two classes).
    if (cls_l or cls_r) and sc:
        kwrite("--file", "kglobalshortcutsrc", "--group", "kwin",
               "--key", f"DropdownTile-{n}",
               f"{sc},none,Dropdown tile: {cls_l or '—'} | {cls_r or '—'}")

# Delete stale tile entries beyond the current tile count
for i in range(tile_count + 1, 21):
    n = str(i)
    for key in ["tileClassLeft", "tileClassRight", "tileShortcut", "tileSplitPercent",
                "tileWidthPercent", "tileHeightPercent", "tileScreenTarget", "tileOpacity",
                "tileAllDesktops", "tileAutoHide", "tileDirection", "tileOrientation",
                "tileAnimationStyle", "tileAnimationDuration"]:
        subprocess.run(
            ["kwriteconfig6", "--file", "kwinrc", "--group", kwin_group,
             "--key", f"{key}{n}", "--delete"],
            capture_output=True
        )

# ── plasma-dropdown-any-slide effect: keep its managed-class list in sync ──
# The scoped slide effect can't read our kwinrc group itself (KWin's
# effect.readConfig() only sees the effect's OWN config group), so we push
# every slot's and every tile pair's window class(es) + chosen animation
# style/duration ("class:Style:DurationMs" triples) into its group here, on
# every save. A tile pair's style/duration applies to both of its windows;
# a slot's own choice always wins if the same class also appears in a tile
# pair.
managed_classes = {}
for slot in slots:
    cls = slot.get("windowClass", "").strip()
    if cls:
        managed_classes[cls] = (
            slot.get("animationStyle", "Smooth") or "Smooth",
            slot.get("animationDuration", 250),
        )
for tile in tiles:
    tile_style = tile.get("animationStyle", "Smooth") or "Smooth"
    tile_duration = tile.get("animationDuration", 250)
    for key in ("classLeft", "classRight"):
        cls = tile.get(key, "").strip()
        if cls and cls not in managed_classes:
            managed_classes[cls] = (tile_style, tile_duration)

encoded = ",".join(f"{cls}:{style}:{duration}"
                    for cls, (style, duration) in sorted(managed_classes.items()))
kwrite("--file", "kwinrc", "--group", "Effect-plasma-dropdown-any-slide",
       "--key", "ManagedClasses", encoded)
PYEOF
    rm -f "${json_file}"
    echo "ERROR: failed to write configuration" >&2
    exit 2
  }
  rm -f "$json_file"
}

# ─── subcommand: list-windows ────────────────────────────────────────────────────
# Uses a temporary KWin JS snippet (print → journal) to enumerate open windows.
# Approach from design R3: avoid DBus sink (needs compiled service); only a file
# path crosses DBus, eliminating all JS-escaping concerns.
#
# Some KWin builds don't route script print() output to the user journal at
# all (observed on Fedora: DBus load/run succeeds and callDBus side effects
# work fine, but print() never reaches `journalctl --user`, for reasons that
# didn't trace back to SELinux, logging categories, or KWin version — all
# ruled out). When the journal yields nothing, _list_windows_fallback_via_clipboard
# re-scans and pushes the result out via callDBus instead: an OSD popup so
# the user sees something happened, and Klipper's clipboard as the data
# channel back to this shell script. A "FALLBACK_CLIPBOARD_OSD" marker is
# emitted on stderr so the plasmoid can tell the user auto-detection used
# the fallback path (and that their clipboard was overwritten).
#
# Output: one "class → title" line per unique window class (sorted).

# Re-scans open windows and pushes the class list out via callDBus instead
# of print()+journal: shows an OSD (org.kde.osdService) so the user sees
# something happened, and writes the same class list to the clipboard via
# Klipper so this shell script can read it back over DBus. The user's
# previous clipboard content is saved before the overwrite and restored
# once the class list has been read back, so this is transparent.
# Echoes one window class per line (no title — the clipboard channel only
# carries class names) on stdout, or nothing if the clipboard round-trip
# failed.
_list_windows_fallback_via_clipboard() {
  local dbus_cmd="$1"
  local tmp_js="/tmp/dropdown-winlist-fallback-$$.js"

  local prev_clipboard=""
  prev_clipboard=$("$dbus_cmd" org.kde.klipper /klipper org.kde.klipper.klipper \
    getClipboardContents 2>/dev/null || true)

  cat >"$tmp_js" <<'JSEOF'
(function() {
  var seen = {};
  var skip = { plasmashell: 1, systemsettings: 1, ksmserver: 1, plasmawindowed: 1 };
  var wins = (typeof workspace.windows !== 'undefined') ? workspace.windows
             : (typeof workspace.windowList === 'function') ? workspace.windowList()
             : (typeof workspace.clientList === 'function') ? workspace.clientList()
             : [];
  var classes = [];
  for (var i = 0; i < wins.length; i++) {
    var w   = wins[i];
    var cls = String(w.resourceClass || '');
    if (!cls || skip[cls] || seen[cls]) continue;
    seen[cls] = 1;
    classes.push(cls);
  }
  callDBus('org.kde.plasmashell', '/org/kde/osdService', 'org.kde.osdService',
           'showText', 'dialog-information',
           classes.length > 0 ? classes.join('\n') : '(no windows found)');
  callDBus('org.kde.klipper', '/klipper', 'org.kde.klipper.klipper',
           'setClipboardContents', classes.join('\n'));
})();
JSEOF

  "$dbus_cmd" org.kde.KWin /Scripting \
    org.kde.kwin.Scripting.unloadScript dropdown-winlist-fb >/dev/null 2>&1 || true
  local script_id=""
  script_id=$("$dbus_cmd" org.kde.KWin /Scripting \
    org.kde.kwin.Scripting.loadScript "$tmp_js" dropdown-winlist-fb 2>/dev/null || true)

  if [[ -n "$script_id" && "$script_id" =~ ^[0-9]+$ ]]; then
    "$dbus_cmd" org.kde.KWin "/Scripting/Script${script_id}" \
      org.kde.kwin.Script.run >/dev/null 2>&1 || true
    sleep 1.2
  fi

  "$dbus_cmd" org.kde.KWin /Scripting \
    org.kde.kwin.Scripting.unloadScript dropdown-winlist-fb >/dev/null 2>&1 || true
  rm -f "$tmp_js"

  local result=""
  result=$("$dbus_cmd" org.kde.klipper /klipper org.kde.klipper.klipper \
    getClipboardContents 2>/dev/null || true)

  "$dbus_cmd" org.kde.klipper /klipper org.kde.klipper.klipper \
    setClipboardContents "$prev_clipboard" >/dev/null 2>&1 || true

  printf '%s' "$result"
}

cmd_list_windows() {
  local dbus_cmd=""
  dbus_cmd=$(find_dbus_cmd)

  local tag="DROPWIN_$$"
  local tmp_js="/tmp/dropdown-winlist-$$.js"

  # Write temp KWin script; ${tag} is expanded by bash here.
  # KWin 6 renamed workspace.windowList() to workspace.windows (list
  # property, not a function) — fall back through windowList()/clientList()
  # for older KWin.
  cat >"$tmp_js" <<JSEOF
(function() {
  var seen = {};
  var skip = { plasmashell: 1, systemsettings: 1, ksmserver: 1, plasmawindowed: 1 };
  var wins = (typeof workspace.windows !== 'undefined') ? workspace.windows
             : (typeof workspace.windowList === 'function') ? workspace.windowList()
             : (typeof workspace.clientList === 'function') ? workspace.clientList()
             : [];
  for (var i = 0; i < wins.length; i++) {
    var w   = wins[i];
    var cls = String(w.resourceClass || '');
    if (!cls || skip[cls] || seen[cls]) continue;
    seen[cls] = 1;
    var cap = String(w.caption || '').substring(0, 60);
    print('${tag}\t' + cls + '\t' + cap);
  }
})();
JSEOF

  # Record current journal cursor so we only read new output
  local cursor=""
  cursor=$(journalctl --user -n0 --show-cursor 2>/dev/null |
    grep '^-- cursor:' | sed 's/^-- cursor: //' || true)

  # Unload any previous temp script, then load and run the new one
  "$dbus_cmd" org.kde.KWin /Scripting \
    org.kde.kwin.Scripting.unloadScript dropdown-winlist-sh >/dev/null 2>&1 || true
  local script_id=""
  script_id=$("$dbus_cmd" org.kde.KWin /Scripting \
    org.kde.kwin.Scripting.loadScript "$tmp_js" dropdown-winlist-sh 2>/dev/null || true)

  if [[ -n "$script_id" && "$script_id" =~ ^[0-9]+$ ]]; then
    "$dbus_cmd" org.kde.KWin "/Scripting/Script${script_id}" \
      org.kde.kwin.Script.run >/dev/null 2>&1 || true
    sleep 1.2
  fi

  # Collect tagged output from the journal.
  # --output=cat strips the date/host/pid prefix so tabs are preserved exactly
  # as KWin's print() emitted them.
  local raw_output=""
  if [[ -n "$cursor" ]]; then
    raw_output=$(journalctl --user --output=cat "--after-cursor=${cursor}" 2>/dev/null |
      grep -P "^${tag}\t" || true)
  else
    raw_output=$(journalctl --user --output=cat -n 500 2>/dev/null |
      grep -P "^${tag}\t" || true)
  fi

  # Cleanup: unload temp script and remove JS file
  "$dbus_cmd" org.kde.KWin /Scripting \
    org.kde.kwin.Scripting.unloadScript dropdown-winlist-sh >/dev/null 2>&1 || true
  rm -f "$tmp_js"

  # Journal produced nothing — fall back to OSD + Klipper (see comment above).
  # This channel carries plain class names only (no tag, no title), so it's
  # handled separately from the tag\tcls\ttitle journal format below.
  if [[ -z "$raw_output" ]]; then
    local clip_result=""
    clip_result=$(_list_windows_fallback_via_clipboard "$dbus_cmd")
    if [[ -n "$clip_result" ]]; then
      echo "FALLBACK_CLIPBOARD_OSD" >&2
      printf '%s\n' "$clip_result" | sort -u
    fi
    return 0
  fi

  # Parse and output deduplicated results
  if [[ -n "$raw_output" ]]; then
    declare -A _seen_cls
    while IFS=$'\t' read -r _dropped_tag cls title; do
      [[ -z "$cls" ]] && continue
      [[ -n "${_seen_cls[$cls]+x}" ]] && continue
      _seen_cls["$cls"]=1
      if [[ -n "$title" ]]; then
        echo "${cls} → ${title}"
      else
        echo "$cls"
      fi
    done < <(printf '%s\n' "$raw_output" | sort)
  fi

  return 0
}

# ─── subcommand: list-screens ────────────────────────────────────────────────────
# Uses kscreen-doctor -o to enumerate enabled outputs.
# Mirrors C++ rebuildScreenNames(): "At cursor screen" + "Screen N".

cmd_list_screens() {
  require_tool kscreen-doctor

  echo "At cursor screen"

  local count=0
  while IFS= read -r line; do
    # kscreen-doctor -o lines for enabled outputs match: "Output: N name enabled ..."
    if [[ "$line" =~ ^Output:.*[[:space:]]enabled([[:space:]]|$) ]]; then
      count=$((count + 1))
      echo "Screen ${count}"
    fi
  done < <(kscreen-doctor -o 2>/dev/null || true)

  # Fallback: emit at least "Screen 1" if kscreen-doctor returned nothing useful
  if [[ $count -eq 0 ]]; then
    echo "Screen 1"
  fi
}

# ─── subcommand: reload-script ───────────────────────────────────────────────────
# Unloads and re-loads the plasma-dropdown-any KWin script via DBus.
# Mirrors C++ save() reload sequence exactly.

cmd_reload_script() {
  local dbus_cmd=""
  dbus_cmd=$(find_dbus_cmd)

  # /KWin reconfigure is the same action System Settings triggers when you
  # toggle a script — it causes KWin to re-read kwinrc and reload all enabled
  # scripts, picking up the new slot config immediately.
  "$dbus_cmd" org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || {
    echo "ERROR: KWin reconfigure failed" >&2
    exit 2
  }
}

# ─── subcommand: check-tools ─────────────────────────────────────────────────────
# Checks each required tool against PATH and emits a JSON object.
# Always exits 0; the QML layer interprets the JSON to disable features.

cmd_check_tools() {
  require_python3
  python3 <<'PYEOF'
import shutil, json
result = {
    "kreadconfig6":  shutil.which("kreadconfig6")  is not None,
    "kwriteconfig6": shutil.which("kwriteconfig6") is not None,
    "qdbus":         any(shutil.which(b) for b in ("qdbus6", "qdbus-qt6", "qdbus")),
    "kscreen-doctor": shutil.which("kscreen-doctor") is not None,
    "python3":       True,
}
print(json.dumps(result))
PYEOF
}

# ─── main dispatch ────────────────────────────────────────────────────────────────
[[ $# -ge 1 ]] || usage

subcommand="$1"
shift

case "$subcommand" in
load) cmd_load "$@" ;;
save) cmd_save "$@" ;;
list-windows) cmd_list_windows "$@" ;;
list-screens) cmd_list_screens "$@" ;;
reload-script) cmd_reload_script "$@" ;;
check-tools) cmd_check_tools "$@" ;;
-h | --help) usage ;;
*)
  echo "ERROR: unknown subcommand '${subcommand}'" >&2
  usage
  ;;
esac
