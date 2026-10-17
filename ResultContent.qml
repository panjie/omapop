import QtQuick 6.11 // omacvm #376: QtQuick's own Color (Qt 6.12) would hide Omarchy's
import QtQuick.Controls
import qs.Commons
import "Markdown.js" as Markdown

// Scroll both axes: wide Markdown tables and code must remain accessible.
Flickable {
    id: root
    property string text: ""
    property real maxHeight: 400
    readonly property int baseSize: Style.font.title
    readonly property int padding: Style.spacing.xxl
    readonly property color cardBg: root.popupBackground()
    readonly property var palette: ({
        text: root.hexColor(Color.popups.text),
        muted: root.hexColor(Color.popups.text, 0.62),
        heading: root.hexColor(Color.accent),
        link: root.hexColor(Color.accent),
        codeText: root.hexColor(Color.accent),
        codeBg: root.hexColor(Color.popups.text, 0.08),
        blockBg: root.hexColor(Color.popups.text, 0.06),
        border: root.hexColor(Color.popups.text, 0.2),
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
            if (Color.popups && Color.popups.background !== undefined)
                return Color.popups.background
        } catch (e) {}
        return Color.background
    }

    function resetScroll() {
        contentX = 0
        contentY = 0
    }
    onTextChanged: resetScroll()
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
        color: Color.popups.text
        selectedTextColor: root.cardBg
        selectionColor: Color.accent
        font.family: Style.font.family
        font.pixelSize: root.baseSize
    }
}
