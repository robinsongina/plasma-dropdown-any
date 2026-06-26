// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick
import org.kde.plasma.plasma5support as Plasma5Support

/**
 * ExecBridge — subprocess wrapper for config-helper.sh
 *
 * Wraps org.kde.plasma.plasma5support DataSource (engine: "executable").
 * Commands are queued and executed serially; a single DataSource instance
 * is kept alive for the component's lifetime.
 *
 * Usage:
 *   ExecBridge { id: bridge }
 *   bridge.run("load")              // reads config
 *   bridge.run("save", jsonString)  // saves config (JSON as first arg)
 *   bridge.run("reload-script")     // reloads KWin script via DBus
 *   bridge.run("list-windows")      // enumerates running windows
 *   bridge.run("check-tools")       // checks required tools on PATH
 *
 * Signal:
 *   finished(string verb, int exitCode, string stdout, string stderr)
 *   Emitted when each queued command completes. stdout and stderr are
 *   trimmed of surrounding whitespace.
 */
Item {
    id: bridge
    visible: false

    // ── public signal ────────────────────────────────────────────────────────
    signal finished(string verb, int exitCode, string stdout, string stderr)

    // ── public API ───────────────────────────────────────────────────────────

    /**
     * Enqueue a config-helper.sh subcommand.
     * @param verb   Subcommand name (e.g. "load", "save", "list-windows").
     * @param arg    Optional single argument; shell-escaped and quoted.
     */
    function run(verb, arg) {
        var cmd = _helperPath + " " + verb
        if (arg !== undefined && arg !== null && String(arg).length > 0) {
            // Wrap in single quotes; escape any embedded single quotes.
            var escaped = String(arg).replace(/'/g, "'\\''")
            cmd = cmd + " '" + escaped + "'"
        }
        _queue.push({ verb: verb, cmd: cmd })
        if (!_busy) {
            _processNext()
        }
    }

    // ── private ──────────────────────────────────────────────────────────────

    // Absolute filesystem path to config-helper.sh.
    // Qt.resolvedUrl resolves relative to THIS file's location
    // (contents/ui/ExecBridge.qml → ../code/ = contents/code/).
    readonly property string _helperPath: {
        var url = Qt.resolvedUrl("../code/config-helper.sh").toString()
        // Strip the file:// scheme on Linux
        return url.replace(/^file:\/\//, "")
    }

    // Command queue — one item per pending run() call
    property var    _queue:      []
    property bool   _busy:       false
    property string _activeVerb: ""

    function _processNext() {
        if (_queue.length === 0) {
            _busy = false
            return
        }
        _busy = true
        var item = _queue.shift()
        _activeVerb = item.verb
        _exec.connectedSources = [item.cmd]
    }

    // Single DataSource; we rotate connectedSources to drive each command.
    Plasma5Support.DataSource {
        id: _exec
        engine: "executable"
        connectedSources: []

        onNewData: function(sourceName, data) {
            var exitCode = data["exit code"] !== undefined
                           ? parseInt(data["exit code"], 10) : 0
            var out  = data["stdout"] !== undefined ? String(data["stdout"]).trim() : ""
            var err  = data["stderr"] !== undefined ? String(data["stderr"]).trim() : ""
            var verb = bridge._activeVerb

            disconnectSource(sourceName)
            bridge.finished(verb, exitCode, out, err)
            bridge._processNext()
        }
    }
}
