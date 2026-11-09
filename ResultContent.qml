import QtQuick 6.11 // omacvm #376: QtQuick's own Color (Qt 6.12) would hide Omarchy's
import QtQuick.Controls
import qs.Commons
import qs.Commons as Commons
import "Markdown.js" as Markdown

// Scroll both axes: wide Markdown tables and code must remain accessible.
Flickable {
    id: root
    property string text: ""
    property bool streaming: false
    property bool followTail: true
    onMovementEnded: followTail = contentY + height >= contentHeight - 30
    onContentHeightChanged: if (streaming && followTail) contentY = Math.max(0, contentHeight - height)
    property real maxHeight: 400
    readonly property int baseSize: Style.font.body
    readonly property int padding: Style.spacing.xxl
    readonly property color cardBg: root.popupBackground()
    readonly property var palette: ({
        text: root.hexColor(Commons.Color.popups.text),
        muted: root.hexColor(Commons.Color.popups.text, 0.62),
        heading: root.hexColor(Commons.Color.accent),
        link: root.hexColor(Commons.Color.accent),
        codeText: root.hexColor(Commons.Color.accent),
        codeBg: root.hexColor(Commons.Color.popups.text, 0.08),
        blockBg: root.hexColor(Commons.Color.popups.text, 0.06),
        border: root.hexColor(Commons.Color.popups.text, 0.2),
        baseSize: root.baseSize,
        paragraphGap: Style.spacing.md
    })
    readonly property string richText: Markdown.toHtml(text, palette)

    function hexColor(c, alpha) {
        var f = c || Qt.rgba(0, 0, 0, 1)
        var b = root.cardBg || Qt.rgba(0, 0, 0, 1)
        var a = alpha === undefined ? (f.a === undefined ? 1 : f.a) : alpha
        function channel(value) {
            var n = Math.round(Math.max(0, Math.min(1, value)) * 255).toString(16)
            return n.length < 2 ? "0" + n : n
        }
        return "#" + channel(f.r * a + b.r * (1 - a))
            + channel(f.g * a + b.g * (1 - a))
            + channel(f.b * a + b.b * (1 - a))
    }

    function popupBackground() {
        try {
            if (Commons.Color.popups && Commons.Color.popups.background !== undefined)
                return Commons.Color.popups.background
        } catch (e) {}
        return Commons.Color.background
    }

    function resetScroll() {
        contentX = 0
        contentY = 0
    }
    onTextChanged: if (!streaming || !text) { resetScroll(); followTail = true }
    implicitHeight: Math.min(body.implicitHeight + padding * 2, maxHeight)
    height: implicitHeight
    contentWidth: Math.max(width, body.contentWidth + padding * 2)
    contentHeight: body.implicitHeight + padding * 2
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar { }
    ScrollBar.horizontal: ScrollBar { }

    TextEdit {
        id: body
        x: root.padding
        y: root.padding
        width: Math.max(1, root.width - root.padding * 2)
        text: root.richText
        textFormat: TextEdit.RichText
        readOnly: true
        activeFocusOnPress: false
        wrapMode: TextEdit.Wrap
        color: Commons.Color.popups.text
        selectedTextColor: root.cardBg
        selectionColor: Commons.Color.accent
        font.family: Style.font.family
        font.pixelSize: root.baseSize
    }
}
