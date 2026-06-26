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
find_dbus_cmd() {
    if command -v qdbus6 &>/dev/null; then
        echo "qdbus6"
    elif command -v qdbus &>/dev/null; then
        echo "qdbus"
    else
        echo "ERROR: neither qdbus6 nor qdbus found on PATH" >&2
        exit 1
    fi
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

    python3 << PYEOF
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
        })

debug_mode = kread("debugMode", "false") == "true"

print(json.dumps({
    "slotCount": len(slots),
    "debugMode":  debug_mode,
    "slots":      slots
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
    [[ $# -ge 1 ]] || { echo "ERROR: save requires a JSON argument" >&2; exit 2; }
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
    done

    # ── Step 2: write new config via Python (JSON parsing) ────────────────────
    local json_file=""
    json_file=$(mktemp /tmp/dropdown-save-XXXXXX.json)
    printf '%s' "$json_input" > "$json_file"

    local kwin_group="$KWIN_GROUP"

    python3 << PYEOF || { rm -f "${json_file}"; echo "ERROR: failed to write configuration" >&2; exit 2; }
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

# Write each slot; also write shortcuts for non-empty cls+sc pairs
for i, slot in enumerate(slots, 1):
    n       = str(i)
    cls     = slot.get("windowClass", "")
    sc      = slot.get("shortcut", "")
    w_pct   = str(slot.get("widthPercent",  100))
    h_pct   = str(slot.get("heightPercent", 50))
    screen  = str(slot.get("screenTarget",  0))
    opacity = str(slot.get("opacity",       100))
    all_d   = "true" if slot.get("allDesktops", False) else "false"
    auto_h  = "true" if slot.get("autoHide",    False) else "false"

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

    # Shortcut format: "Meta+F1,none,Dropdown toggle: Konsole"
    # Matches C++ kwinGroup.writeEntry("DropdownAny-Konsole", "Meta+F1,none,Dropdown toggle: Konsole")
    if cls and sc:
        kwrite("--file", "kglobalshortcutsrc", "--group", "kwin",
               "--key", f"DropdownAny-{cls}",
               f"{sc},none,Dropdown toggle: {cls}")

# Delete stale entries beyond the current slot count (mirrors C++ cleanup to 20)
for i in range(count + 1, 21):
    n = str(i)
    for key in ["windowClass", "shortcut", "widthPercent", "heightPercent",
                "screenTarget", "opacity", "allDesktops", "autoHide"]:
        subprocess.run(
            ["kwriteconfig6", "--file", "kwinrc", "--group", kwin_group,
             "--key", f"{key}{n}", "--delete"],
            capture_output=True
        )
PYEOF
    rm -f "$json_file"
}

# ─── subcommand: list-windows ────────────────────────────────────────────────────
# Uses a temporary KWin JS snippet (print → journal) to enumerate open windows.
# Approach from design R3: avoid DBus sink (needs compiled service); only a file
# path crosses DBus, eliminating all JS-escaping concerns.
#
# Output: one "class → title" line per unique window class (sorted).

cmd_list_windows() {
    local dbus_cmd=""
    if command -v qdbus6 &>/dev/null; then
        dbus_cmd="qdbus6"
    elif command -v qdbus &>/dev/null; then
        dbus_cmd="qdbus"
    else
        echo "ERROR: neither qdbus6 nor qdbus found on PATH" >&2
        exit 1
    fi

    local tag="DROPWIN_$$"
    local tmp_js="/tmp/dropdown-winlist-$$.js"

    # Write temp KWin script; ${tag} is expanded by bash here
    cat > "$tmp_js" << JSEOF
(function() {
  var seen = {};
  var skip = { plasmashell: 1, systemsettings: 1, ksmserver: 1 };
  var wins = workspace.windowList();
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
    cursor=$(journalctl --user -n0 --show-cursor 2>/dev/null | \
             grep '^-- cursor:' | sed 's/^-- cursor: //' || true)

    # Unload any previous temp script, then load and run the new one
    "$dbus_cmd" org.kde.KWin /Scripting \
        org.kde.kwin.Scripting.unloadScript dropdown-winlist-sh 2>/dev/null || true
    local script_id=""
    script_id=$("$dbus_cmd" org.kde.KWin /Scripting \
        org.kde.kwin.Scripting.loadScript "$tmp_js" dropdown-winlist-sh 2>/dev/null || true)

    if [[ -n "$script_id" && "$script_id" =~ ^[0-9]+$ ]]; then
        "$dbus_cmd" org.kde.KWin "/Scripting/Script${script_id}" \
            org.kde.kwin.Script.run 2>/dev/null || true
        sleep 1.2
    fi

    # Collect tagged output from the journal
    local raw_output=""
    if [[ -n "$cursor" ]]; then
        raw_output=$(journalctl --user "--after-cursor=${cursor}" 2>/dev/null | \
                     grep -oP "${tag}\t[^\n]+" || true)
    else
        raw_output=$(journalctl --user -n 500 2>/dev/null | \
                     grep -oP "${tag}\t[^\n]+" || true)
    fi

    # Cleanup: unload temp script and remove JS file
    "$dbus_cmd" org.kde.KWin /Scripting \
        org.kde.kwin.Scripting.unloadScript dropdown-winlist-sh 2>/dev/null || true
    rm -f "$tmp_js"

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
    if command -v qdbus6 &>/dev/null; then
        dbus_cmd="qdbus6"
    elif command -v qdbus &>/dev/null; then
        dbus_cmd="qdbus"
    else
        echo "ERROR: neither qdbus6 nor qdbus found on PATH" >&2
        exit 1
    fi

    # Unload current instance (ignore error; script may not be loaded)
    "$dbus_cmd" org.kde.KWin /Scripting \
        org.kde.kwin.Scripting.unloadScript plasma-dropdown-any 2>/dev/null || true

    # Locate main.js in XDG data directories (matches QStandardPaths::locate)
    local main_js=""
    local search_dirs=(
        "$HOME/.local/share/kwin/scripts/plasma-dropdown-any/contents/code"
        "/usr/share/kwin/scripts/plasma-dropdown-any/contents/code"
        "/usr/local/share/kwin/scripts/plasma-dropdown-any/contents/code"
    )
    local dir
    for dir in "${search_dirs[@]}"; do
        if [[ -f "${dir}/main.js" ]]; then
            main_js="${dir}/main.js"
            break
        fi
    done

    if [[ -z "$main_js" ]]; then
        echo "ERROR: could not locate plasma-dropdown-any main.js in XDG data dirs" >&2
        exit 2
    fi

    # Load and run — get the script ID from loadScript return value
    local script_id=""
    script_id=$("$dbus_cmd" org.kde.KWin /Scripting \
        org.kde.kwin.Scripting.loadScript "$main_js" plasma-dropdown-any 2>&1 || true)

    if [[ -z "$script_id" || ! "$script_id" =~ ^[0-9]+$ ]]; then
        echo "ERROR: loadScript returned unexpected value: ${script_id}" >&2
        exit 2
    fi

    "$dbus_cmd" org.kde.KWin "/Scripting/Script${script_id}" \
        org.kde.kwin.Script.run 2>/dev/null || true
}

# ─── subcommand: check-tools ─────────────────────────────────────────────────────
# Checks each required tool against PATH and emits a JSON object.
# Always exits 0; the QML layer interprets the JSON to disable features.

cmd_check_tools() {
    require_python3
    python3 << 'PYEOF'
import shutil, json
result = {
    "kreadconfig6":  shutil.which("kreadconfig6")  is not None,
    "kwriteconfig6": shutil.which("kwriteconfig6") is not None,
    "qdbus":         shutil.which("qdbus6") is not None or shutil.which("qdbus") is not None,
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
    load)          cmd_load          "$@" ;;
    save)          cmd_save          "$@" ;;
    list-windows)  cmd_list_windows  "$@" ;;
    list-screens)  cmd_list_screens  "$@" ;;
    reload-script) cmd_reload_script "$@" ;;
    check-tools)   cmd_check_tools   "$@" ;;
    -h|--help)     usage ;;
    *)
        echo "ERROR: unknown subcommand '${subcommand}'" >&2
        usage
        ;;
esac
