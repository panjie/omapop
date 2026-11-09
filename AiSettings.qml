import QtQuick 6.11
import QtQuick.Layouts
import QtQuick.Controls as C
import qs.Commons
import qs.Commons as Commons
import qs.Ui as Ui

ColumnLayout {
    id: root
    required property var ai
    signal backRequested()
    spacing: Style.spacing.lg
    readonly property color foreground: Commons.Color.popups.text
    readonly property color secondaryText: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.68)
    property alias tabIndex: tabs.currentIndex

    component Label: Text {
        textFormat: Text.PlainText
        color: root.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
    }
    component ActionButton: Ui.Button {
        bordered: true
        focusable: true
        foreground: root.foreground
        fontFamily: Style.font.family
        fontSize: Style.font.body
    }
    component Field: Ui.TextField {
        foreground: root.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.body
    }
    component Choice: Ui.Dropdown {
        property var model: []
        property int currentIndex: -1
        signal activated(int index)
        showLabel: false
        foreground: root.foreground
        options: model.map(function(label, index) { return {value: String(index), label: label} })
        value: currentIndex < 0 ? "" : String(currentIndex)
        onChanged: function(next) { activated(Number(next)) }
    }
    property var draft: ({version: 1, defaultConnection: "", connections: [], buttons: []})
    property var keys: ({})
    property int connectionIndex: -1
    property int buttonIndex: -1
    readonly property var connection: connectionIndex >= 0 ? draft.connections[connectionIndex] : null
    readonly property var action: buttonIndex >= 0 ? draft.buttons[buttonIndex] : null
    readonly property var providers: ["deepseek", "openai", "claude", "gemini", "compatible"]
    readonly property var urls: ["https://api.deepseek.com", "https://api.openai.com/v1", "https://api.anthropic.com/v1", "https://generativelanguage.googleapis.com/v1beta", "http://localhost:11434/v1"]
    function refresh() {
        if (!ai) return
        draft = JSON.parse(JSON.stringify(ai.config))
        keys = ({})
        connectionIndex = draft.connections.length ? 0 : -1
        buttonIndex = draft.buttons.length ? 0 : -1
    }
    function change(kind, field, value) {
        var next = JSON.parse(JSON.stringify(draft))
        var index = kind === "connections" ? connectionIndex : buttonIndex
        if (index < 0) return
        next[kind][index][field] = value
        draft = next
    }
    function add(kind) {
        var next = JSON.parse(JSON.stringify(draft))
        var id = "item-" + Date.now()
        if (kind === "connections") {
            next.connections.push({id: id, name: "DeepSeek", provider: "deepseek", baseUrl: urls[0], model: "deepseek-flash", maxTokens: 4096})
            if (!next.defaultConnection) next.defaultConnection = id
        } else next.buttons.push({id: id, title: "新按钮", icon: "AI", prompt: "请处理以下文字：\n\n{{text}}", connection: "", enabled: true, placement: "toolbar", output: "preview"})
        draft = next
        if (kind === "connections") connectionIndex = next.connections.length - 1
        else buttonIndex = next.buttons.length - 1
    }
    function remove(kind) {
        var next = JSON.parse(JSON.stringify(draft))
        var index = kind === "connections" ? connectionIndex : buttonIndex
        if (index < 0) return
        var id = next[kind][index].id
        next[kind].splice(index, 1)
        if (kind === "connections") {
            if (next.defaultConnection === id) next.defaultConnection = next.connections.length ? next.connections[0].id : ""
            next.buttons.forEach(function(b) { if (b.connection === id) b.connection = "" })
            connectionIndex = -1
        } else buttonIndex = -1
        draft = next
        if (kind === "connections") connectionIndex = next.connections.length ? 0 : -1
        else buttonIndex = next.buttons.length ? 0 : -1
    }
    function move(offset) {
        var next = JSON.parse(JSON.stringify(draft))
        var to = buttonIndex + offset
        if (buttonIndex < 0 || to < 0 || to >= next.buttons.length) return
        var b = next.buttons.splice(buttonIndex, 1)[0]
        next.buttons.splice(to, 0, b)
        draft = next
        buttonIndex = to
    }
    Connections {
        target: root.ai
        function onConfigChanged() { if (root.visible) root.refresh() }
    }
    onVisibleChanged: if (visible) refresh()
    RowLayout {
        Layout.fillWidth: true
        spacing: Style.spacing.lg
        ActionButton { text: "返回"; onClicked: root.backRequested() }
        Label { Layout.fillWidth: true; text: "AI 文本处理"; font.pixelSize: Style.font.heading; font.weight: Font.DemiBold }
    }
        Label { Layout.fillWidth: true; text: "点击按钮时才发送选中文字。API 用量由服务商计费。"; wrapMode: Text.Wrap; color: root.secondaryText }
    RowLayout {
        id: tabs
        property int currentIndex: 0
        Layout.fillWidth: true
        spacing: Style.spacing.sm
        ActionButton { Layout.fillWidth: true; text: "服务商与模型"; selected: tabs.currentIndex === 0; onClicked: tabs.currentIndex = 0 }
        ActionButton { Layout.fillWidth: true; text: "提示词按钮"; selected: tabs.currentIndex === 1; onClicked: tabs.currentIndex = 1 }
    }
        Flickable {
            id: scroll
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: Style.space(460)
            Layout.minimumHeight: Style.space(120)
            contentWidth: width
            contentHeight: form.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            C.ScrollBar.vertical: C.ScrollBar { }
            ColumnLayout {
                id: form
                width: scroll.width - Style.spacing.lg
                spacing: Style.spacing.lg
                ColumnLayout {
                    visible: tabs.currentIndex === 0
                    Layout.fillWidth: true
                    RowLayout {
                        Choice { Layout.fillWidth: true; model: root.draft.connections.map(function(c) { return c.name }); currentIndex: root.connectionIndex; onActivated: function(index) { root.connectionIndex = index } }
                        ActionButton { text: "新增"; onClicked: root.add("connections") }
                        ActionButton { text: "删除"; enabled: !!root.connection; onClicked: root.remove("connections") }
                    }
                    GridLayout {
                        visible: !!root.connection
                        Layout.fillWidth: true
                        columns: 2
                        columnSpacing: Style.spacing.lg
                        rowSpacing: Style.spacing.lg
                        Label { text: "名称" }
                        Field { Layout.fillWidth: true; text: root.connection ? root.connection.name : ""; onTextEdited: root.change("connections", "name", text) }
                        Label { text: "服务商" }
                        Choice {
                            objectName: "aiProvider"
                            Layout.fillWidth: true
                            model: ["DeepSeek", "OpenAI", "Claude", "Gemini", "兼容接口 / 本地模型"]
                            currentIndex: root.connection ? root.providers.indexOf(root.connection.provider) : 0
                            onActivated: function(index) { root.change("connections", "provider", root.providers[index]); root.change("connections", "baseUrl", root.urls[index]); root.change("connections", "model", index === 0 ? "deepseek-flash" : "") }
                        }
                        Label { text: "API Base URL" }
                        Field { Layout.fillWidth: true; text: root.connection ? root.connection.baseUrl : ""; onTextEdited: root.change("connections", "baseUrl", text) }
                        Label { text: "模型名称" }
                        Field { Layout.fillWidth: true; placeholderText: "填写服务商支持的模型 ID"; text: root.connection ? root.connection.model : ""; onTextEdited: root.change("connections", "model", text) }
                        Label { text: "API Key" }
                        Field {
                            Layout.fillWidth: true
                            echoMode: TextInput.Password
                            placeholderText: root.connection && root.connection.hasKey ? "已保存；留空保留，输入可替换" : "填写 API Key（本地模型可留空）"
                            text: root.connection ? (root.keys[root.connection.id] || "") : ""
                            onTextEdited: { if (root.connection) { var k = Object.assign({}, root.keys); if (text) k[root.connection.id] = text; else delete k[root.connection.id]; root.keys = k } }
                        }
                        Label { text: "输出 tokens 上限" }
                        Ui.NumberField { Layout.fillWidth: true; fieldWidth: width; from: 1; to: 65536; value: root.connection ? root.connection.maxTokens : 4096; onModified: function(next) { root.change("connections", "maxTokens", next) } }
                    }
                    ActionButton {
                        visible: !!root.connection
                        text: root.connection && root.draft.defaultConnection === root.connection.id ? "当前默认连接" : "设为默认连接"
                        onClicked: { var next = Object.assign({}, root.draft); next.defaultConnection = root.connection.id; root.draft = next }
                    }
                }
                ColumnLayout {
                    visible: tabs.currentIndex === 1
                    Layout.fillWidth: true
                    RowLayout {
                        Choice { Layout.fillWidth: true; model: root.draft.buttons.map(function(b) { return b.title }); currentIndex: root.buttonIndex; onActivated: function(index) { root.buttonIndex = index } }
                        ActionButton { text: "新增"; onClicked: root.add("buttons") }
                        ActionButton { text: "删除"; enabled: !!root.action; onClicked: root.remove("buttons") }
                    }
                    RowLayout {
                        enabled: !!root.action
                        ActionButton { text: "复制"; onClicked: { var next = JSON.parse(JSON.stringify(root.draft)); var b = Object.assign({}, root.action); b.id = "copy-" + Date.now(); b.title = b.title.slice(0, 35) + " 副本"; next.buttons.push(b); root.draft = next; root.buttonIndex = next.buttons.length - 1 } }
                        ActionButton { text: "上移"; onClicked: root.move(-1) }
                        ActionButton { text: "下移"; onClicked: root.move(1) }
                        Ui.Toggle { Layout.fillWidth: true; label: "启用"; titleSize: Style.font.bodySmall; checked: root.action ? root.action.enabled : false; onClicked: root.change("buttons", "enabled", !checked) }
                    }
                    GridLayout {
                        visible: !!root.action
                        Layout.fillWidth: true
                        columns: 2
                        columnSpacing: Style.spacing.lg
                        rowSpacing: Style.spacing.lg
                        Label { text: "按钮名称" }
                        Field { Layout.fillWidth: true; text: root.action ? root.action.title : ""; onTextEdited: root.change("buttons", "title", text) }
                        Label { text: "图标文字 / Emoji" }
                        Field { Layout.fillWidth: true; maximumLength: 8; text: root.action ? root.action.icon : ""; onTextEdited: root.change("buttons", "icon", text) }
                        Label { text: "AI 连接" }
                        Choice {
                            Layout.fillWidth: true
                            model: ["使用默认连接"].concat(root.draft.connections.map(function(c) { return c.name }))
                            currentIndex: root.action ? root.draft.connections.map(function(c) { return c.id }).indexOf(root.action.connection) + 1 : 0
                            onActivated: function(index) { root.change("buttons", "connection", index ? root.draft.connections[index - 1].id : "") }
                        }
                        Label { text: "显示位置" }
                        Choice { Layout.fillWidth: true; model: ["工具栏", "AI 菜单"]; currentIndex: root.action && root.action.placement === "menu" ? 1 : 0; onActivated: function(index) { root.change("buttons", "placement", index ? "menu" : "toolbar") } }
                        Label { text: "结果方式" }
                        Choice { Layout.fillWidth: true; model: ["预览", "仅复制", "替换原文（校验选区）"]; currentIndex: root.action ? ["preview", "copy", "replace"].indexOf(root.action.output) : 0; onActivated: function(index) { root.change("buttons", "output", ["preview", "copy", "replace"][index]) } }
                    }
                    Label { text: "提示词 · {{text}} 表示选中文字" }
                    C.TextArea {
                        visible: !!root.action
                        Layout.fillWidth: true
                        Layout.preferredHeight: Style.space(170)
                        font.family: Style.font.family
                        font.pixelSize: Style.font.body
                        color: root.foreground
                        selectionColor: Style.selectionFillFor(root.foreground, Commons.Color.accent)
                        selectedTextColor: root.foreground
                        padding: Style.spacing.lg
                        background: Ui.BorderSurface {
                            color: Style.controlFill(parent.activeFocus, false, root.foreground, Commons.Color.accent)
                            borderSpec: Border.controlSpec(parent.activeFocus ? "focus" : "normal", root.foreground, Commons.Color.accent)
                            radius: Style.cornerRadius
                        }
                        wrapMode: TextEdit.Wrap
                        selectByMouse: true
                        text: root.action ? root.action.prompt : ""
                        onTextChanged: if (activeFocus && root.action && root.action.prompt !== text) root.change("buttons", "prompt", text)
                    }
                }
            }
        }
        Label { Layout.fillWidth: true; text: root.ai ? root.ai.error : ""; color: text === "已保存。" ? root.secondaryText : Commons.Color.urgent; wrapMode: Text.Wrap; visible: text !== "" }
        Label { Layout.fillWidth: true; text: "修改后点击保存。密钥单独保存在本机。"; wrapMode: Text.Wrap; color: root.secondaryText }
        RowLayout {
            enabled: !!root.ai && !root.ai.saving
            Item { Layout.fillWidth: true }
            ActionButton { objectName: "aiSave"; text: "保存"; onClicked: root.ai.save(root.draft, root.keys) }

        }
}
