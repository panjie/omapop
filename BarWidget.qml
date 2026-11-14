import QtQuick 6.11 // omacvm #376: QtQuick's own Color (Qt 6.12) would hide Omarchy's
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Actions.js" as Actions

// Bar icon for Omapop. Left click opens a small panel listing the installed
// extensions with on/off switches, the JavaScript runtime in use, and a few
// maintenance actions; right click pauses or resumes the selection bar.
Panel {
    id: root
    moduleName: "io.github.jondkinney.omapop"

    Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

    // The service owns the plugin's IPC target; one widget per monitor would
    // otherwise register competing handlers.
    manageIpc: false

    readonly property string pluginId: "io.github.jondkinney.omapop"
    readonly property var service: bar && bar.shell && typeof bar.shell.serviceFor === "function" ? bar.shell.serviceFor(pluginId) : null
    readonly property bool paused: service ? service.paused : false
    readonly property bool engineReady: service ? service.engineReady : false
    // AI is built in, but belongs beside installed extensions in the manager.
    readonly property var extensions: [{
        identifier: "omapop.builtin.ai", builtinAi: true,
        enabled: service ? service.setting("aiEnabled", true) !== false : true,
        name: strings.t("ai.title"), description: strings.t("settings.aiTooltip"), icon: "AI"
    }].concat(service ? service.extensions : [])
    readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
    readonly property color secondaryText: Qt.rgba(Commons.Color.popups.text.r, Commons.Color.popups.text.g, Commons.Color.popups.text.b, Commons.Color.popups.text.a * 0.68)
    readonly property bool showIcon: service ? service.setting("showBarIcon", true) !== false : setting("showBarIcon", true) !== false
    property string expandedId: ""
    property bool directorySeeded: false
    property string confirmInstallId: ""
    property bool settingsOpen: false
    property bool aiOpen: false
    readonly property string panelScreenName: panel.screen ? panel.screen.name : ""

    function openSettings() {
        aiOpen = false
        settingsOpen = true
        open()
    }

    function syncServiceSettings() {
        if (service) service.widgetSettings = settings
    }
    onSettingsChanged: syncServiceSettings()
    onServiceChanged: syncServiceSettings()

    Connections {
        target: root.service
        function onSettingsRequested() { root.aiOpen = false; root.settingsOpen = true }
        function onAiSettingsRequested() { root.settingsOpen = false; root.aiOpen = true }
    }

    component RowSeparator: Rectangle {
        Layout.fillWidth: true
        implicitHeight: 1
        color: Qt.rgba(Commons.Color.popups.text.r, Commons.Color.popups.text.g, Commons.Color.popups.text.b, Commons.Color.popups.text.a * 0.12)
    }

    component SectionHeading: RowLayout {
        id: heading
        required property string title
        property int count: -1
        Layout.fillWidth: true
        Layout.topMargin: Style.spacing.xxl
        Layout.bottomMargin: Style.spacing.xs
        spacing: Style.spacing.lg

        Text {
            Layout.fillWidth: true
            text: heading.title
            textFormat: Text.PlainText
            color: Commons.Color.popups.text
            font.family: root.fontFamily
            font.pixelSize: Style.font.subtitle
            font.weight: Font.DemiBold
        }
        Rectangle {
            visible: heading.count >= 0
            implicitWidth: countLabel.implicitWidth + Style.spacing.xxl
            implicitHeight: countLabel.implicitHeight + Style.spacing.md
            radius: height / 2
            color: Qt.rgba(Commons.Color.popups.text.r, Commons.Color.popups.text.g, Commons.Color.popups.text.b, Commons.Color.popups.text.a * 0.07)
            Text {
                id: countLabel
                anchors.centerIn: parent
                text: String(heading.count)
                textFormat: Text.PlainText
                color: root.secondaryText
                font.family: root.fontFamily
                font.pixelSize: Math.max(1, Style.font.caption - 1)
            }
        }
    }

    // The scanner's notes are lower-case clauses ("needs macOS (...)"); start a caption with one.
    function sentence(text) {
        var s = String(text || "")
        return s ? s.charAt(0).toUpperCase() + s.slice(1) : ""
    }

    onOpenedChanged: {
        if (!opened) confirmInstallId = ""
        if (!opened && settingsOpen)
            settingsPage.finishEditing()
        // Re-read on every open: the catalogue may have been refreshed in the
        // background since last time. Keeps whatever query is already typed.
        if (opened && service && !settingsOpen) {
            directorySeeded = true
            service.searchDirectory(service.directoryQuery)
        }
    }

    visible: showIcon
    implicitWidth: showIcon ? button.implicitWidth : 0
    implicitHeight: button.implicitHeight

    BarIconButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        iconComponent: Component {
            BarIcon {
                // Omarchy 4.5 measures this component inside a zero-sized Loader.
                // Filling that loader collapses the icon; declare its canvas instead.
                width: button.opticalSize
                height: button.opticalSize
                color: button.foreground
                paused: root.paused
            }
        }
        foreground: root.paused || !root.engineReady ? Qt.darker(root.barForeground, 1.55) : root.barForeground
        tooltipText: strings.t(root.paused ? "bar.tooltip.paused" : root.engineReady ? "bar.tooltip.ready" : "bar.tooltip.waiting")
            + "\n" + strings.t("bar.tooltip.hint").arg(strings.t(root.paused ? "bar.action.resume" : "bar.action.pause"))
        onPressed: function (button) {
            if (button === Qt.LeftButton)
                root.toggle()
            else if (button === Qt.RightButton && root.service)
                root.service.paused = !root.service.paused
        }
    }

    KeyboardPanel {
        id: panel
        anchorItem: button
        owner: root
        bar: root.bar
        open: root.opened
        contentWidth: panel.fittedContentWidth(Style.space(root.aiOpen ? 520 : 400))
        contentHeight: panel.fittedContentHeight(root.aiOpen ? aiPage.implicitHeight : root.settingsOpen ? settingsPage.implicitHeight : content.implicitHeight, Math.round(panel.screenH * 0.9))

        // Nothing scrolls the panel as a whole: the status at the top and the
        // Reload / Open folder row at the bottom stay put, and each list scrolls
        // inside its own bounded area. Both lists fill the leftover height, so a
        // long installed list can no longer push the footer off the bottom.
        ColumnLayout {
            id: content
            anchors.fill: parent
            visible: !root.settingsOpen && !root.aiOpen
            spacing: Style.space(6)

            ColumnLayout {
                Layout.fillWidth: true
                visible: !!root.service && root.service.ai.history.length > 0
                Text {
                    text: strings.t("ai.history")
                    color: Commons.Color.popups.text
                    font.family: root.fontFamily
                    textFormat: Text.PlainText
                }
                Repeater {
                    model: root.service ? root.service.ai.history : []
                    delegate: Button {
                        required property int index
                        required property var modelData
                        Layout.fillWidth: true
                        text: modelData.title
                        onClicked: { root.close(); root.service.ai.restore(index) }
                    }
                }
                Button { text: strings.t("ai.clearHistory"); onClicked: root.service.ai.history = [] }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.bottomMargin: Style.spacing.xs
                spacing: Style.spacing.xl

                BarIcon {
                    Layout.preferredWidth: Math.round(Style.space(24))
                    Layout.preferredHeight: Math.round(Style.space(24))
                    color: root.paused ? root.secondaryText : Commons.Color.accent
                    paused: root.paused
                }
                Text {
                    Layout.fillWidth: true
                    text: "Omapop"
                    textFormat: Text.PlainText
                    color: Commons.Color.popups.text
                    font.family: root.fontFamily
                    font.pixelSize: Math.round(Style.font.heading * 1.125)
                    font.weight: Font.DemiBold
                }
                Button {
                    iconText: "\u{F0493}"
                    focusable: true
                    tooltipText: strings.t("common.settings")
                    Accessible.role: Accessible.Button
                    Accessible.name: strings.t("common.settings")
                    enabled: !!root.service
                    onClicked: root.openSettings()
                }
            }

            Toggle {
                Layout.fillWidth: true
                label: strings.t("bar.enabled")
                description: root.paused ? strings.t("bar.enabled.paused")
                    : root.engineReady ? strings.t("bar.enabled.ready")
                    : strings.t("bar.enabled.connecting")
                titleSize: Style.font.bodySmall
                fontFamily: root.fontFamily
                foreground: Commons.Color.popups.text
                checked: !root.paused
                enabled: !!root.service
                onClicked: root.service.paused = !root.service.paused
            }

            Text {
                Layout.fillWidth: true
                visible: root.service && root.service.lastError !== ""
                text: root.service ? Actions.oneLine(root.service.lastError, 300) : ""
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
                color: Commons.Color.urgent
                font.family: root.fontFamily
                font.pixelSize: Math.max(1, Style.font.caption - 1)
            }

            // Only the broken case earns a place up here, and it is a warning:
            // without a runtime, JavaScript extensions silently do nothing.
            // Which runtime is in use is diagnostics, and sits in the footer.
            Text {
                Layout.fillWidth: true
                visible: !!(root.service && root.service.runtimeProbed && root.service.runtimeName === "")
                text: strings.t("bar.runtimeMissing")
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
                color: Commons.Color.urgent
                font.family: root.fontFamily
                font.pixelSize: Math.max(1, Style.font.caption - 1)
            }

            SectionHeading {
                title: strings.t("bar.installed")
                count: root.extensions.length
            }

            Text {
                Layout.fillWidth: true
                visible: root.extensions.length === 0
                text: strings.t("bar.empty")
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
                color: root.secondaryText
                font.family: root.fontFamily
                font.pixelSize: Math.max(1, Style.font.caption - 1)
            }

            ListView {
                id: installedList
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredHeight: Math.min(contentHeight, Math.round(panel.screenH * 0.40))
                Layout.minimumHeight: count ? Math.round(Style.space(64)) : 0
                visible: count > 0
                clip: true
                spacing: Style.spacing.sm
                boundsBehavior: Flickable.StopAtBounds
                reuseItems: true
                interactive: contentHeight > height
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                model: root.extensions
                delegate: ColumnLayout {
                    id: extRow
                    required property var modelData
                    required property int index
                    width: installedList.width
                    height: implicitHeight
                    spacing: Style.spacing.sm

                    RowLayout {
                        id: extensionHeader
                        Layout.fillWidth: true
                        spacing: Style.spacing.md

                        ActionIcon {
                            id: extensionIcon
                            Layout.alignment: Qt.AlignVCenter
                            size: Math.round(Style.space(20))
                            spec: modelData.icon || ""
                            filePath: modelData.iconPath || ""
                            fallbackText: modelData.name || ""
                            color: modelData.error ? Commons.Color.urgent : Commons.Color.popups.text
                            background: Commons.Color.popups.background
                            fontFamily: root.fontFamily
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Style.spacing.xxs
                            Text {
                                Layout.fillWidth: true
                                text: Actions.oneLine(modelData.name || modelData.identifier || "?", 200)
                                textFormat: Text.PlainText
                                wrapMode: Text.WordWrap
                                // Unusable here (every action needs macOS): present, but dimmed.
                                color: modelData.usable === false ? root.secondaryText : Commons.Color.popups.text
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.bodySmall
                                font.weight: Font.DemiBold
                            }
                            Text {
                                Layout.fillWidth: true
                                visible: text !== ""
                                text: {
                                    if (modelData.error)
                                        return strings.t("bar.error").arg(Actions.oneLine(modelData.error, 400))
                                    var note = root.sentence(modelData.platformNote)
                                    if (modelData.usable === false)
                                        return Actions.oneLine(note || strings.t("bar.cannotRun"), 400)
                                    var description = modelData.description || (modelData.source === "bundled" ? strings.t("bar.bundledExample") : "")
                                    if (modelData.trustStatus === "manual")
                                        description = strings.t("bar.localExtension").arg(description)
                                    return Actions.oneLine(note ? (description ? description + " " : "") + note + "." : description, 400)
                                }
                                textFormat: Text.PlainText
                                wrapMode: Text.WordWrap
                                color: modelData.error ? Commons.Color.urgent : root.secondaryText
                                font.family: root.fontFamily
                                font.pixelSize: Math.max(1, Style.font.caption - 1)
                            }
                        }

                        PanelActionButton {
                            Layout.alignment: Qt.AlignVCenter
                            visible: true
                            iconText: root.expandedId === modelData.identifier ? "\u{F0143}" : "\u{F0493}"
                            tooltipText: strings.t("common.settings")
                            onClicked: {
                                if (modelData.builtinAi) root.aiOpen = true
                                else root.expandedId = root.expandedId === modelData.identifier ? "" : modelData.identifier
                            }
                        }

                        ToggleSwitch {
                            Layout.alignment: Qt.AlignVCenter
                            interactive: !!root.service && !modelData.error && modelData.usable !== false
                            checked: !!modelData.enabled
                            onToggled: {
                                if (!root.service) return
                                if (modelData.builtinAi) {
                                    var error = root.service.setSetting("aiEnabled", !modelData.enabled)
                                    if (error) root.service.lastError = error
                                } else root.service.setExtensionEnabled(modelData.identifier, !modelData.enabled)
                            }
                        }
                    }

                    // The options belong to this delegate and scroll with its row.
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: extensionIcon.width + extensionHeader.spacing
                        visible: root.expandedId === extRow.modelData.identifier
                        spacing: Style.spacing.sm

                        Dropdown {
                            Layout.fillWidth: true
                            label: strings.t("bar.commandKey")
                            options: [{ value: "inherit", label: strings.t("bar.useGlobal") }, { value: "ctrl", label: strings.t("option.ctrl") }, { value: "super", label: strings.t("option.super") }]
                            value: extRow.modelData.commandKey || "inherit"
                            onChanged: function (next) {
                                if (root.service) root.service.setExtensionCommandKey(extRow.modelData.identifier, next)
                            }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: strings.t("bar.inherit")
                                  + (extRow.modelData.recommendedCommandKey === "ctrl" ? strings.t("bar.recommendedCtrl") : "")
                            textFormat: Text.PlainText
                            wrapMode: Text.WordWrap
                            color: root.secondaryText
                            font.family: root.fontFamily
                            font.pixelSize: Math.max(1, Style.font.caption - 1)
                        }

                        Repeater {
                            model: root.expandedId === extRow.modelData.identifier ? (extRow.modelData.options || []) : []
                            delegate: ColumnLayout {
                                required property var modelData
                                readonly property var ext: extRow.modelData
                                readonly property var currentValue: ext && ext.optionValues && ext.optionValues[modelData.identifier] !== undefined
                                    ? ext.optionValues[modelData.identifier] : modelData.defaultValue
                                Layout.fillWidth: true
                                visible: !modelData.hidden
                                spacing: Style.spacing.xxs

                                Text {
                                    Layout.fillWidth: true
                                    text: Actions.oneLine(modelData.label || modelData.identifier || "", 200)
                                    textFormat: Text.PlainText
                                    wrapMode: Text.WordWrap
                                    color: Commons.Color.popups.text
                                    font.family: root.fontFamily
                                    font.pixelSize: modelData.type === "heading" ? Style.font.subtitle : Style.font.bodySmall
                                    font.bold: modelData.type === "heading"
                                }

                                Text {
                                    Layout.fillWidth: true
                                    visible: (modelData.description || "") !== ""
                                    text: Actions.oneLine(modelData.description || "", 400)
                                    textFormat: Text.PlainText
                                    wrapMode: Text.WordWrap
                color: root.secondaryText
                                    font.family: root.fontFamily
                                    font.pixelSize: Math.max(1, Style.font.caption - 1)
                                }

                                ToggleSwitch {
                                    visible: modelData.type === "boolean"
                                    checked: currentValue === true || currentValue === "1" || currentValue === "true"
                                    onToggled: if (root.service) root.service.setExtensionOption(ext.identifier, modelData.identifier, !checked)
                                }

                                Dropdown {
                                    Layout.fillWidth: true
                                    visible: modelData.type === "multiple"
                                    showLabel: false
                                    options: {
                                        var list = []
                                        var values = modelData.values || []
                                        var labels = modelData.valueLabels || []
                                        if (modelData.allowNone)
                                            list.push({ value: "", label: strings.t("common.none") })
                                        for (var i = 0; i < values.length; i++)
                                            list.push({ value: values[i], label: labels[i] || values[i] })
                                        return list
                                    }
                                    value: String(currentValue === undefined || currentValue === null ? "" : currentValue)
                                    onChanged: function (v) { if (root.service) root.service.setExtensionOption(ext.identifier, modelData.identifier, v) }
                                }

                                TextField {
                                    Layout.fillWidth: true
                                    visible: modelData.type === "string" || modelData.type === "secret" || modelData.type === "password"
                                    password: modelData.type === "secret" || modelData.type === "password"
                                    text: String(currentValue === undefined || currentValue === null ? "" : currentValue)
                                    placeholderText: modelData.type === "secret" ? strings.t("common.secret") : ""
                                    onEditingFinished: if (root.service && text !== String(currentValue === undefined ? "" : currentValue)) root.service.setExtensionOption(ext.identifier, modelData.identifier, text)
                                }
                            }
                        }
                    }

                    RowSeparator { visible: extRow.index < installedList.count - 1 }
                }
            }

            // Browse and install published extensions. The service shells out
            // to bin/omapop-directory.py; this only renders what comes back.
            SectionHeading {
                title: strings.t("bar.available")
                count: root.service ? root.service.directoryTotal : -1
            }

            Timer {
                id: searchDebounce
                interval: 250
                onTriggered: if (root.service) root.service.searchDirectory(searchField.text)
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Style.spacing.md
                TextField {
                    id: searchField
                    Layout.fillWidth: true
                    placeholderText: strings.t("bar.searchPlaceholder")
                    onTextChanged: searchDebounce.restart()
                }
                Button {
                    text: strings.t("common.update")
                    tooltipText: strings.t("bar.updateTooltip")
                    onClicked: if (root.service) root.service.refreshDirectory(0)
                }
                PanelActionButton {
                    iconText: "\u{F03CC}"
                    tooltipText: strings.t("bar.openDirectoryTooltip")
                    onClicked: if (root.service) root.service.openDirectoryPage("https://www.popclip.app/extensions/")
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Style.spacing.md
                visible: statusText.text !== "" || macToggle.visible

                Text {
                    id: statusText
                    Layout.fillWidth: true
                    text: {
                        if (!root.service)
                            return ""
                        if (root.service.directoryStatus !== "")
                            return root.service.directoryStatus
                        if (root.service.directoryBusy)
                            return strings.t("bar.loadingCatalogue")
                        if (root.service.directoryTotal > 0) {
                            var s = strings.t("bar.shown").arg(root.service.directoryResults.length)
                            if (root.service.directoryShowMac)
                                s += strings.t("bar.unapprovedIncluded")
                            else if (root.service.directoryHidden > 0)
                                s += strings.t("bar.unapprovedHidden").arg(root.service.directoryHidden)
                            if (root.service.directoryClassifying)
                                s += strings.t("bar.checkingMac")
                            return s
                        }
                        return ""
                    }
                    textFormat: Text.PlainText
                    wrapMode: Text.WordWrap
                color: root.secondaryText
                    font.family: root.fontFamily
                    font.pixelSize: Math.max(1, Style.font.caption - 1)
                }

                // Extensions whose every action is AppleScript or a macOS
                // Service are left out; this shows them, marked, for the curious.
                Button {
                    id: macToggle
                    Layout.alignment: Qt.AlignVCenter
                    visible: !!(root.service && (root.service.directoryShowMac || root.service.directoryHidden > 0))
                    text: root.service && root.service.directoryShowMac ? strings.t("bar.hideUnapproved") : strings.t("bar.showUnapproved")
                    tooltipText: strings.t("bar.unapprovedTooltip")
                    onClicked: if (root.service) root.service.setDirectoryShowMac(!root.service.directoryShowMac)
                }
            }

            // A ListView, not a Repeater: the catalogue is ~270 rows and only the
            // visible handful should exist. It scrolls inside its own bounded
            // height so the panel does not grow without limit.
            ListView {
                id: dirList
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredHeight: Math.min(contentHeight, Math.round(panel.screenH * 0.34))
                Layout.minimumHeight: count ? Math.round(Style.space(64)) : 0
                visible: count > 0
                clip: true
                model: root.service ? root.service.directoryResults : []
                spacing: Style.spacing.sm
                boundsBehavior: Flickable.StopAtBounds
                reuseItems: true
                // Only take the wheel when there is something to scroll,
                // so the panel behind it stays scrollable on short screens.
                interactive: contentHeight > height
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                delegate: ColumnLayout {
                    id: dirRow
                    required property var modelData
                    required property int index
                    readonly property bool installing: !!(root.service && root.service.directoryInstalling[modelData.shortcode])
                    width: dirList.width
                    height: implicitHeight
                    spacing: Style.spacing.sm

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Style.spacing.md

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Style.spacing.xxs
                            Text {
                                Layout.fillWidth: true
                                text: modelData.name
                                textFormat: Text.PlainText
                                wrapMode: Text.WordWrap
                                color: modelData.needsMac ? root.secondaryText : Commons.Color.popups.text
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.bodySmall
                                font.weight: Font.DemiBold
                            }
                            Text {
                                Layout.fillWidth: true
                                visible: text !== ""
                                text: (modelData.approved ? (modelData.isPort ? strings.t("bar.linuxPortVersion").arg(modelData.version) : strings.t("bar.reviewedVersion").arg(modelData.version)) : strings.t("bar.notApproved"))
                                      + (modelData.needsMac ? strings.t("bar.needsMac") : "") + modelData.description
                                textFormat: Text.PlainText
                                wrapMode: Text.WordWrap
                color: root.secondaryText
                                font.family: root.fontFamily
                                font.pixelSize: Math.max(1, Style.font.caption - 1)
                            }
                        }

                        PanelActionButton {
                            Layout.alignment: Qt.AlignVCenter
                            visible: modelData.page !== ""
                            iconText: "\u{F03CC}"
                            tooltipText: strings.t("bar.openPageTooltip")
                            onClicked: if (root.service) root.service.openDirectoryPage(modelData.page)
                        }

                        Button {
                            Layout.alignment: Qt.AlignVCenter
                            text: dirRow.installing ? "\u2026" : root.confirmInstallId === modelData.shortcode ? strings.t("bar.confirmInstall") : strings.t("common.install")
                            enabled: !dirRow.installing && modelData.approved && !!(root.service && root.service.extensionDownloads)
                            tooltipText: root.service && !root.service.extensionDownloads ? strings.t("bar.enableDownloads")
                                         : strings.t("bar.installTooltip")
                            onClicked: {
                                if (root.confirmInstallId !== modelData.shortcode) {
                                    root.confirmInstallId = modelData.shortcode
                                    return
                                }
                                root.confirmInstallId = ""
                                if (root.service) root.service.installFromDirectory(modelData.shortcode)
                            }
                        }
                        PanelActionButton {
                            visible: root.confirmInstallId === modelData.shortcode
                            iconText: "\u{F0156}"
                            tooltipText: strings.t("bar.cancelInstall")
                            onClicked: root.confirmInstallId = ""
                        }
                    }

                    RowSeparator { visible: dirRow.index < dirList.count - 1 }
                }
            }

            // Flow, not RowLayout: a narrow panel wraps the buttons onto a
            // second line instead of clipping the last label.
            Flow {
                Layout.fillWidth: true
                Layout.topMargin: Style.spacing.sm
                spacing: Style.spacing.md
                Button {
                    text: strings.t("common.reload")
                    tooltipText: strings.t("bar.reloadTooltip")
                    onClicked: if (root.service) root.service.rescanExtensions()
                }
                Button {
                    text: strings.t("common.openFolder")
                    tooltipText: strings.t("bar.openFolderTooltip")
                    onClicked: if (root.service) root.service.openExtensionsFolder()
                }
            }

            Text {
                Layout.fillWidth: true
                visible: !!(root.service && root.service.runtimeName)
                text: root.service ? strings.t("bar.runtimeFooter").arg(root.service.runtimeName) : ""
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
                color: Qt.darker(Commons.Color.popups.text, 1.6)
                font.family: root.fontFamily
                font.pixelSize: Math.max(1, Style.font.caption - 1)
            }
        }

        Settings {
            id: settingsPage
            anchors.fill: parent
            visible: root.settingsOpen && !root.aiOpen
            service: root.service
            onBackRequested: {
                root.settingsOpen = false
                if (root.service) root.service.searchDirectory(root.service.directoryQuery)
            }
        }
        AiSettings {
            id: aiPage
            anchors.fill: parent
            visible: root.opened && root.aiOpen
            ai: root.service ? root.service.ai : null
            onBackRequested: {
                root.aiOpen = false
                if (root.service) root.service.searchDirectory(root.service.directoryQuery)
            }
        }
    }
}
