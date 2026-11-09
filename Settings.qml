pragma ComponentBehavior: Bound
import QtQuick 6.11 // omacvm #376: QtQuick's own Color (Qt 6.12) would hide Omarchy's
import QtQuick.Layouts
import QtQuick.Controls as QQC
import QtQuick.Window
import qs.Commons
import qs.Commons as Commons
import qs.Ui

ColumnLayout {
    id: root

    Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

    property var service: null
    property string errorText: ""
    readonly property color secondaryText: Qt.rgba(Commons.Color.popups.text.r, Commons.Color.popups.text.g, Commons.Color.popups.text.b, 0.68)
    readonly property var groups: [
        { title: "settings.group.selection", keys: ["longPress", "requireTerminalShift", "position", "shortcut", "excludedApps"] },
        { title: "settings.group.search", keys: ["searchEngine", "searchUrl"] },
        { title: "settings.group.general", keys: ["showBarIcon", "extensionDownloads", "directoryRefresh"] },
        { title: "settings.group.advanced", keys: ["dragThreshold", "hideDistance", "maxSelectionKiB", "accessibilityProbe", "assumeEditable", "terminalClasses", "commandKey"] }
    ]
    readonly property var labels: ({
        longPress: "settings.label.longPress", requireTerminalShift: "settings.label.requireTerminalShift",
        position: "settings.label.position", shortcut: "settings.label.shortcut",
        excludedApps: "settings.label.excludedApps", searchEngine: "settings.label.searchEngine",
        searchUrl: "settings.label.searchUrl", showBarIcon: "settings.label.showBarIcon",
        extensionDownloads: "settings.label.extensionDownloads", directoryRefresh: "settings.label.directoryRefresh",
        dragThreshold: "settings.label.dragThreshold", hideDistance: "settings.label.hideDistance",
        maxSelectionKiB: "settings.label.maxSelectionKiB", accessibilityProbe: "settings.label.accessibilityProbe",
        assumeEditable: "settings.label.assumeEditable", terminalClasses: "settings.label.terminalClasses",
        commandKey: "settings.label.commandKey"
    })
    readonly property var descriptions: ({
        longPress: "settings.desc.longPress",
        requireTerminalShift: "settings.desc.requireTerminalShift",
        position: "settings.desc.position",
        shortcut: "settings.desc.shortcut",
        excludedApps: "settings.desc.excludedApps",
        searchEngine: "settings.desc.searchEngine",
        searchUrl: "settings.desc.searchUrl",
        showBarIcon: "settings.desc.showBarIcon",
        extensionDownloads: "settings.desc.extensionDownloads",
        directoryRefresh: "settings.desc.directoryRefresh",
        dragThreshold: "settings.desc.dragThreshold",
        hideDistance: "settings.desc.hideDistance",
        maxSelectionKiB: "settings.desc.maxSelectionKiB",
        accessibilityProbe: "settings.desc.accessibilityProbe",
        assumeEditable: "settings.desc.assumeEditable",
        terminalClasses: "settings.desc.terminalClasses",
        commandKey: "settings.desc.commandKey"
    })

    // Enum values are stored in English but shown in the shell's language.
    function optionLabel(field, value) {
        return strings.t("option." + value, value)
    }
    function optionList(field) {
        return field && field.options ? field.options.map(function (value) {
            return { value: value, label: root.optionLabel(field, value) }
        }) : []
    }

    signal backRequested()
    signal flushEdits()

    spacing: Style.spacing.lg

    function definition(key) {
        var schema = service ? service.settingsSchema : []
        for (var i = 0; i < schema.length; i++)
            if (schema[i].key === key) return schema[i]
        return null
    }

    function value(field) {
        return field && service ? service.setting(field.key, field.defaultValue) : undefined
    }

    function save(field, next) {
        if (!field || !service) return
        errorText = service.setSetting(field.key, next)
    }

    function finishEditing() {
        flushEdits()
    }

    function goBack() {
        finishEditing()
        backRequested()
    }

    function reveal(item) {
        if (!visible || !item) return
        var ancestor = item
        while (ancestor && ancestor !== form) ancestor = ancestor.parent
        if (!ancestor) return
        var y = item.mapToItem(form, 0, 0).y
        var margin = Style.spacing.md
        if (y < scroll.contentY + margin)
            scroll.contentY = Math.max(0, y - margin)
        else if (y + item.height > scroll.contentY + scroll.height - margin)
            scroll.contentY = Math.max(0, Math.min(scroll.contentHeight - scroll.height, y + item.height - scroll.height + margin))
    }

    onVisibleChanged: if (visible) Qt.callLater(function () { backButton.forceActiveFocus() })
    Keys.onEscapePressed: goBack()

    Connections {
        target: root.Window.window
        function onActiveFocusItemChanged() { root.reveal(root.Window.window.activeFocusItem) }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Style.spacing.md
        Button {
            id: backButton
            objectName: "settingsBack"
            text: strings.t("common.back")
            iconText: "\u{F004D}"
            focusable: true
            tooltipText: strings.t("settings.backTooltip")
            onClicked: root.goBack()
        }
        Text {
            Layout.fillWidth: true
            text: strings.t("settings.title")
            textFormat: Text.PlainText
            color: Commons.Color.popups.text
            font.family: Style.font.family
            font.pixelSize: Style.font.heading
            font.weight: Font.DemiBold
        }
    }

    Flickable {
        id: scroll
        objectName: "settingsScroll"
        Layout.fillWidth: true
        Layout.fillHeight: true
        // The containing panel applies the same screen-height cap as the
        // extensions page; let the form use all the space available to it.
        Layout.preferredHeight: contentHeight
        Layout.minimumHeight: Style.space(80)
        contentWidth: width
        contentHeight: form.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        clip: true
        QQC.ScrollBar.vertical: QQC.ScrollBar { policy: QQC.ScrollBar.AsNeeded }

        ColumnLayout {
            id: form
            width: scroll.width - Style.spacing.lg
            spacing: Style.spacing.huge * 2
            Repeater {
                model: root.groups
                delegate: ColumnLayout {
                    id: section
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: Style.spacing.huge
                    Text {
                        Layout.fillWidth: true
                        text: strings.t(section.modelData.title)
                        textFormat: Text.PlainText
                        color: root.secondaryText
                        font.family: Style.font.family
                        font.pixelSize: Style.font.subtitle
                        font.weight: Font.DemiBold
                    }
                    Repeater {
                        model: section.modelData.keys
                        delegate: SettingRow {
                            required property string modelData
                            field: root.definition(modelData)
                        }
                    }
                }
            }
        }
    }

    Text {
        Layout.fillWidth: true
        text: root.errorText || strings.t("settings.autosave")
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        color: root.errorText ? Commons.Color.urgent : root.secondaryText
        font.family: Style.font.family
        font.pixelSize: Math.max(1, Style.font.caption - 1)
    }

    component SettingRow: ColumnLayout {
        id: row
        required property var field
        readonly property var currentValue: root.value(field)
        readonly property string key: field ? field.key : ""
        readonly property string kind: field ? field.type : ""
        readonly property string title: root.labels[key] ? strings.t(root.labels[key]) : (field ? field.label : "")
        readonly property string description: root.descriptions[key] ? strings.t(root.descriptions[key]) : (field ? field.description : "")

        Layout.fillWidth: true
        visible: !!field && (key !== "searchUrl" || root.value(root.definition("searchEngine")) === "other")
        spacing: Style.spacing.md

        function commit() {
            if (!visible) return
            if (shortcutEditor.item) shortcutEditor.item.cancel()
            if (kind === "string" && key !== "excludedApps" && key !== "shortcut" && input.edited && input.text !== currentValue)
                root.save(field, input.text)
            if (kind === "integer" && number.edited && number.field.contentItem.acceptableInput) {
                var next = number.field.valueFromText(number.field.contentItem.text, number.field.locale)
                if (next !== currentValue) root.save(field, next)
            }
            input.edited = false
            number.edited = false
        }

        Connections {
            target: root
            function onFlushEdits() { row.commit() }
        }

        Toggle {
            objectName: "setting_" + row.key + "_toggle"
            Layout.fillWidth: true
            visible: row.kind === "boolean"
            label: row.title
            description: row.description
            titleSize: Style.font.bodySmall
            checked: row.currentValue === true
            onClicked: root.save(row.field, !checked)
        }

        Text {
            Layout.fillWidth: true
            visible: row.kind !== "boolean"
            text: row.title
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            color: Commons.Color.popups.text
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            font.weight: Font.DemiBold
        }
        Text {
            Layout.fillWidth: true
            visible: row.kind !== "boolean" && text !== ""
            text: row.description
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            color: root.secondaryText
            font.family: Style.font.family
            font.pixelSize: Math.max(1, Style.font.caption - 1)
        }

        Dropdown {
            objectName: "setting_" + row.key + "_dropdown"
            Layout.fillWidth: true
            visible: row.kind === "enum"
            showLabel: false
            options: root.optionList(row.field)
            value: typeof row.currentValue === "string" ? row.currentValue : ""
            onChanged: function (next) { root.save(row.field, next) }
        }
        NumberField {
            id: number
            property bool edited: false
            objectName: "setting_" + row.key + "_number"
            Layout.fillWidth: true
            visible: row.kind === "integer"
            fieldWidth: width
            from: row.field && row.field.min !== undefined ? row.field.min : 0
            to: row.field && row.field.max !== undefined ? row.field.max : 100
            value: row.kind === "integer" ? Number(row.currentValue) : 0
            onModified: function (next) { edited = false; root.save(row.field, next) }
            // Apply the initial value after the SpinBox receives its range;
            // its built-in 0..100 range would otherwise clamp larger defaults.
            Binding {
                target: number.field
                property: "value"
                value: number.value
                delayed: true
            }
            Connections {
                target: number.field.contentItem
                function onTextEdited() { number.edited = true }
            }
        }
        Loader {
            id: shortcutEditor
            Layout.fillWidth: true
            active: row.key === "shortcut"
            visible: active
            sourceComponent: ShortcutRecorder {
                value: typeof row.currentValue === "string" ? row.currentValue : ""
                onEdited: function (next) { root.save(row.field, next) }
            }
        }
        Loader {
            Layout.fillWidth: true
            active: row.key === "excludedApps"
            visible: active
            sourceComponent: ExcludedApps {
                value: typeof row.currentValue === "string" ? row.currentValue : ""
                windows: root.service ? root.service.runningWindows : []
                onEdited: function (next) { root.save(row.field, next) }
            }
        }
        TextField {
            id: input
            property bool edited: false
            objectName: "setting_" + row.key + "_input"
            Layout.fillWidth: true
            visible: row.kind === "string" && row.key !== "excludedApps" && row.key !== "shortcut"
            maximumLength: row.key === "shortcut" ? 64 : 4096
            text: typeof row.currentValue === "string" ? row.currentValue.slice(0, maximumLength) : ""
            placeholderText: row.key === "shortcut" ? "SUPER + SHIFT + P"
                : row.key === "searchUrl" ? "https://example.com/search?q=***" : ""
            onTextEdited: edited = true
            onEditingFinished: row.commit()
        }
    }
}
