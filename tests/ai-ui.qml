import QtQuick 6.11
import QtQuick.Window
import QtTest
import Quickshell
import ".." as Plugin
import qs.Commons as Commons

TestCase {
    id: test
    name: "AiSettings"
    when: test.Window.window !== null && test.Window.window.visible
    visible: true
    width: 460
    height: 650
    QtObject {
        id: fake
        property var config: ({version: 1, defaultConnection: "", connections: [], buttons: []})
        property string error: ""
        property bool saving: false
        property var host: ({setExtensionEnabled: function() {}})
        function save(config, keys) {}
        function importPopai() {}
    }
    Rectangle {
        id: canvas
        anchors.fill: parent
        color: Commons.Color.popups.background
        Plugin.AiSettings { id: settings; anchors.fill: parent; anchors.margins: 16; ai: fake; visible: false }
    }
    onCompletedChanged: if (completed) console.log("OMAPOP_AI_TESTS " + JSON.stringify({passed:qtest_results.passCount,failed:qtest_results.failCount}))
    function init() { settings.refresh() }
    function test_connections_and_default() {
        settings.add("connections")
        compare(settings.connection.provider, "deepseek")
        compare(settings.draft.defaultConnection, settings.connection.id)
        settings.change("connections", "name", "My DeepSeek")
        compare(settings.connection.name, "My DeepSeek")
        settings.remove("connections")
        compare(settings.connectionIndex, -1)
        compare(settings.draft.defaultConnection, "")
    }
    function test_buttons_are_editable_and_reorderable() {
        settings.add("buttons")
        settings.change("buttons", "title", "Translate")
        settings.change("buttons", "prompt", "翻译\n{{text}}")
        wait(2)
        settings.add("buttons")
        settings.change("buttons", "title", "Explain")
        settings.move(-1)
        compare(settings.draft.buttons[0].title, "Explain")
        compare(settings.draft.buttons[1].prompt, "翻译\n{{text}}")
    }
    function test_delete_connection_resets_button_reference() {
        settings.add("connections")
        var id = settings.connection.id
        settings.add("buttons")
        settings.change("buttons", "connection", id)
        settings.remove("connections")
        compare(settings.action.connection, "")
    }
    function test_provider_selection_keeps_binding_when_switching_connections() {
        settings.add("connections")
        var provider = findChild(settings, "aiProvider")
        verify(provider !== null)
        provider.changed("1")
        compare(settings.connection.provider, "openai")
        compare(settings.connection.baseUrl, "https://api.openai.com/v1")
        compare(settings.connection.model, "")
        wait(2)
        settings.add("connections")
        compare(provider.currentIndex, 0)
        settings.connectionIndex = 0
        compare(provider.currentIndex, 1)
    }
    function test_popup_page_renders_with_form() {
        settings.add("connections")
        settings.add("buttons")
        settings.visible = true
        wait(100)
        verify(settings.visible)
        compare(settings.draft.connections.length, 0) // Opening reloads saved configuration.
        settings.add("connections")
        settings.add("buttons")
        wait(100)
        var captureDir = Quickshell.env("OMAPOP_SETTINGS_CAPTURE_DIR")
        if (captureDir) grabImage(canvas).save(captureDir + "/ai-settings.png")
        settings.tabIndex = 1
        wait(100)
        if (captureDir) grabImage(canvas).save(captureDir + "/ai-buttons.png")
        settings.visible = false
    }
    function test_prompt_scrolls_to_cursor() {
        settings.visible = true
        settings.tabIndex = 1
        settings.add("buttons")
        var editor = findChild(settings, "aiPrompt")
        var scroll = findChild(settings, "aiFormScroll")
        editor.forceActiveFocus()
        editor.selectAll()
        keyClick(Qt.Key_Backspace)
        for (var i = 0; i < 40; ++i) {
            keyClick(Qt.Key_A)
            keyClick(Qt.Key_Return)
        }
        function cursorIsVisible() {
            var cursor = editor.mapToItem(scroll, editor.cursorRectangle.x, editor.cursorRectangle.y)
            return cursor.y >= 0 && cursor.y + editor.cursorRectangle.height <= scroll.height
        }
        tryVerify(cursorIsVisible)
        verify(scroll.contentY > 0)
        compare(settings.action.prompt, editor.text)
        keyClick(Qt.Key_Home, Qt.ControlModifier)
        tryVerify(cursorIsVisible)
        keyClick(Qt.Key_End, Qt.ControlModifier)
        tryVerify(cursorIsVisible)
        // A pasted paragraph also grows through wrapping, without explicit newlines.
        editor.remove(0, editor.length)
        editor.insert(0, new Array(150).join("多行提示词自动换行 "))
        editor.cursorPosition = editor.length
        tryVerify(cursorIsVisible)
        compare(settings.action.prompt, editor.text)
        settings.visible = false
    }
}
