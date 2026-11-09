import QtQuick
import qs.Commons as Commons

Item {
    id: root
    required property var host

    Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

    property var config: ({version: 1, defaultConnection: "", connections: [], buttons: []})
    property string error: ""
    property bool saving: false
    property bool running: false
    property bool active: false
    property bool contextValid: true
    property string text: ""
    property string status: ""
    property var task: null
    property int generation: 0
    property var session: null
    property var button: null
    property int selectionSerial: -1
    readonly property string helper: host.pluginDir + "/bin/omapop-ai.py"
    function command(action) { return ["/usr/bin/python3", "-I", helper, action, "--config-dir", host.configDir] }
    function settingsAction(action, request) {
        if (saving) return
        saving = true
        error = ""
        var spec = {command: command(action), limit: 1048576, deadline: 10000}
        if (request) spec.stdin = JSON.stringify(request)
        host.spawn(spec, function(result) {
            saving = false
            var reply = host.parseJson(result.stdout, 1048576)
            if (result.ok && reply && reply.type === "config") {
                config = reply.config
                error = action === "load" ? "" : strings.t("ai.status.saved")
            } else error = reply && reply.message ? reply.message : strings.t("ai.status.operationFailed")
        })
    }
    function save(next, keys) { settingsAction("save", {config: next, keys: keys}) }
    function importPopai() { settingsAction("import", null) }
    function openSettings() { host.openAiSettings() }
    function buttons(input) {
        if (host.setting("aiEnabled", true) === false || !input.text || !input.text.trim()) return []
        if (!config.connections.length) return [{id: "ai.setup", title: strings.t("ai.setupButtonTitle"), textLabel: "AI", showAs: "text", aiSetup: true}]
        var direct = [], menu = []
        config.buttons.forEach(function(b) {
            if (!b.enabled) return
            var item = {id: "ai." + b.id, title: b.title, showAs: "text", textLabel: b.icon || "AI", aiAction: b}
            if (b.placement === "menu") menu.push(item)
            else direct.push(item)
        })
        if (menu.length) direct.push({id: "ai.menu", title: strings.t("ai.menuButtonTitle"), textLabel: "AI…", showAs: "text", submenu: menu, isFolder: true})
        return direct
    }
    function cancel(close) {
        generation++
        if (task) task.cancel()
        task = null
        running = false
        host.busy = false
        if (close) { active = false; session = null }
        else { status = strings.t("ai.status.stopped"); host.updateAiResult() }
    }
    function run(action) {
        if (host.setting("aiEnabled", true) === false) return
        cancel(true)
        session = host.current
        if (!session) return
        button = JSON.parse(JSON.stringify(action))
        selectionSerial = host.selectionSerial
        active = true
        running = true
        host.busy = true
        contextValid = true
        text = ""
        var cid = button.connection || config.defaultConnection
        var connection = config.connections.find(function(c) { return c.id === cid })
        var prefix = button.title + (connection ? " · " + connection.model : "")
        status = strings.t("ai.status.generating").arg(prefix)
        host.beginAiResult()
        var token = generation
        var completed = false
        var failed = false
        task = host.spawn({command: command("run"), stdin: JSON.stringify({button: button.id, text: session.input.text, config: config}),
            lineMode: true, limit: 2097152, deadline: 185000,
            onLine: function(line) {
                if (token !== generation || session !== host.current) return
                var event = host.parseJson(line, 1048576)
                if (!event) return
                if (event.type === "delta") text += event.text || ""
                else if (event.type === "done") completed = true
                else if (event.type === "error") { failed = true; status = text ? strings.t("ai.status.partial").arg(event.message) : event.message }
                if (!flush.running) flush.start()
            }
        }, function(result) {
            if (token !== generation || session !== host.current) return
            task = null
            running = false
            host.busy = false
            flush.stop()
            if (result.ok && completed && !failed) {
                status = prefix
                host.updateAiResult()
                if (button.output === "copy") copy()
                else if (button.output === "replace") replace()
            } else {
                if (!failed) {
                    if (result.failedToStart) status = strings.t("ai.status.noProcess")
                    else if (result.timedOut) status = strings.t("ai.status.timeout")
                    else if (result.truncated) status = strings.t("ai.status.tooLarge")
                    else if (!result.ok) status = strings.t("ai.status.exited")
                    else status = strings.t("ai.status.noDone")
                }
                host.updateAiResult()
            }
        })
    }
    function retry() { if (button && session === host.current) run(button) }
    function copy() {
        if (!text) return
        var token = generation
        host.copyText(text, function(ok) {
            if (token !== generation) return
            status = ok ? strings.t("ai.status.copied") : strings.t("ai.status.copyFailed")
            host.updateAiResult()
        })
    }
    function replace() {
        if (running || !text || !session || session !== host.current) return
        var token = generation
        var original = session
        var valid = function() { return contextValid && token === generation && original === host.current && selectionSerial === host.selectionSerial }
        var reject = function() { if (token === generation) { status = strings.t("ai.status.replaceRejected"); host.updateAiResult() } }
        if (!original.context.canReplace || original.context.terminal || !valid()) { reject(); return }
        host.spawn({command: ["/usr/bin/hyprctl", "-j", "activewindow"], limit: 65536, deadline: 5000}, function(result) {
            var win = host.parseJson(result.stdout, 65536)
            if (!result.ok || !win || win.address !== original.context.windowAddress || !valid()) { reject(); return }
            host.queryContext(original.ctx, function(probe) {
                // Require a fresh, positive accessibility answer, never the assume-editable fallback.
                if (!probe || probe.editable !== true || probe.selection !== true || !valid()) { reject(); return }
                host.spawn({command: ["/usr/bin/python3", "-I", host.selectionHelper, "--max-bytes", "262144"], limit: 1048576, deadline: 6000}, function(read) {
                    var selection = host.parseJson(read.stdout, 1048576)
                    if (!read.ok || !selection || selection.text !== original.input.text || !valid()) { reject(); return }
                    host.copyText(text, function(ok) {
                        if (!ok || !valid()) { reject(); return }
                        host.sendKeys([host.pasteCombo(original.context)], original.context.windowAddress, function() {
                            if (token === generation) { status = strings.t("ai.status.replaced"); host.updateAiResult() }
                        })
                    })
                })
            })
        })
    }
    Timer { id: flush; interval: 50; onTriggered: root.host.updateAiResult() }
    Component.onCompleted: settingsAction("load", null)
    Component.onDestruction: if (task) task.cancel()
}
