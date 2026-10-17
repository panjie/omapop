import QtQuick 6.11 // omacvm #376: QtQuick's own Color (Qt 6.12) would hide Omarchy's
import QtQuick.Controls
import qs.Commons

// Scroll both axes: wide Markdown tables and code must remain accessible.
Flickable {
    id: root
    property string text: ""
    property real maxHeight: 400
    function resetScroll() {
        contentX = 0
        contentY = 0
    }
    onTextChanged: resetScroll()
    implicitHeight: Math.min(body.implicitHeight + Style.spacing.md * 2, maxHeight)
    height: implicitHeight
    contentWidth: Math.max(width, body.contentWidth + Style.spacing.md * 2)
    contentHeight: body.implicitHeight + Style.spacing.md * 2
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar { }
    ScrollBar.horizontal: ScrollBar { }

    TextEdit {
        id: body
        x: Style.spacing.md
        y: Style.spacing.md
        width: Math.max(1, root.width - Style.spacing.md * 2)
        text: root.text
        textFormat: TextEdit.MarkdownText
        readOnly: true
        activeFocusOnPress: false
        wrapMode: TextEdit.Wrap
        color: Color.popups.text
        selectedTextColor: Color.popups.background
        selectionColor: Color.accent
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        renderType: Text.NativeRendering
    }
}
