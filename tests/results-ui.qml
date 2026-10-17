import QtQuick 6.11 // omacvm #376: QtQuick's own Color (Qt 6.12) would hide Omarchy's
import QtQuick.Window
import QtTest
import Quickshell
import qs.Commons
import ".." as Plugin

TestCase {
    id: test
    name: "MarkdownResults"
    when: test.Window.window !== null && test.Window.window.visible
    visible: true
    width: 460
    height: 650
    Rectangle {
        id: canvas
        width: 420
        height: result.height
        color: Color.popups.background
        Plugin.ResultContent { id: result; width: 420; maxHeight: 300 }
    }
    onCompletedChanged: if (completed) console.log("OMAPOP_RESULT_TESTS " + JSON.stringify({passed:qtest_results.passCount,failed:qtest_results.failCount}))
    function test_markdown_and_long_content() {
        result.text = "# Heading\n\n**Bold** and `code`\n\n" + "- List item\n".repeat(100)
        var document = result.contentItem.children[0]
        compare(document.textFormat, TextEdit.MarkdownText)
        verify(document.getText(0, document.length).indexOf("**Bold**") === -1)
        verify(document.getText(0, document.length).indexOf("Bold") >= 0)
        tryVerify(() => result.contentHeight > result.height)
        compare(result.height, 300)
        var captureDir = Quickshell.env("OMAPOP_SETTINGS_CAPTURE_DIR")
        if (captureDir) {
            waitForRendering(canvas)
            grabImage(canvas).save(captureDir + "/result.png")
        }
        result.contentY = 100
        result.text = "Short result"
        compare(result.contentY, 0)
        tryVerify(() => result.height < 300)
    }
    function test_table_and_code() {
        result.text = "| Name | Value |\n| --- | --- |\n| Answer | 42 |\n\n```js\nconst answer = 42;\n```"
        var document = result.contentItem.children[0]
        tryVerify(() => document.contentHeight > 0)
        verify(document.getText(0, document.length).indexOf("Answer") >= 0)
        verify(document.getText(0, document.length).indexOf("const answer = 42;") >= 0)
    }
}
