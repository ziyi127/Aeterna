import QtQuick 2.15
import "."
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Qt.labs.platform 1.1 as Platform
import Aeterna 1.0

ApplicationWindow {
    id: editorWindow
    width: 1080
    height: 760
    minimumWidth: 860
    minimumHeight: 540
    title: editorBackend.currentFilePath.length > 0
           ? "考试编辑器 - " + editorBackend.currentFilePath
           : "考试编辑器 - 未命名"
    color: Theme.materialBase

    
    AppInfo { id: appInfo }
    EditorBackend { id: editorBackend }

    // ── Editor state ──
    property int activePanel: 0
    property int currentExamIndex: -1
    property alias activeTabIndex: editorWindow.currentExamIndex
    property var openTabIndices: []
    property bool bottomPanelVisible: true
    property int bottomPanelHeight: 120
    property bool validationExpanded: true
    property bool examInfoExpanded: true
    property bool examListExpanded: true
    property int maxUndoSteps: 50
    property var undoStack: []
    property var redoStack: []
    property string pendingAction: ""   // "close", "new", "open", "start"
    property bool _syncing: false
    property int contextMenuIndex: -1

    // Validation counts derived from backend report
    readonly property var _validationReport: {
        if (!editorBackend.validationReportJson || editorBackend.validationReportJson.length === 0) {
            return { errors: [], warnings: [] }
        }
        try {
            return JSON.parse(editorBackend.validationReportJson)
        } catch (e) {
            return { errors: [], warnings: [] }
        }
    }
    readonly property int errorCount: _validationReport.errors ? _validationReport.errors.length : 0
    readonly property int warningCount: _validationReport.warnings ? _validationReport.warnings.length : 0

    // ── Actions ──
    Action {
        id: newFileAction
        text: "新建(&N)"
        shortcut: "Ctrl+N"
        onTriggered: newConfigWithCheck()
    }
    Action {
        id: openFileAction
        text: "打开(&O)..."
        shortcut: "Ctrl+O"
        onTriggered: openWithCheck()
    }
    Action {
        id: saveFileAction
        text: "保存(&S)"
        shortcut: "Ctrl+S"
        onTriggered: saveFile()
    }
    Action {
        id: saveAsAction
        text: "另存为(&A)..."
        shortcut: "Ctrl+Shift+S"
        onTriggered: saveAsDialog.open()
    }
    Action {
        id: importAction
        text: "导入 JSON(&I)..."
        onTriggered: importDialog.open()
    }
    Action {
        id: exportAction
        text: "导出 JSON(&E)..."
        onTriggered: exportDialog.open()
    }
    Action {
        id: closeAction
        text: "关闭(&C)"
        shortcut: "Ctrl+W"
        onTriggered: editorWindow.close()
    }

    Action {
        id: undoAction
        text: "撤销(&U)"
        shortcut: "Ctrl+Z"
        enabled: undoStack.length > 0
        onTriggered: undo()
    }
    Action {
        id: redoAction
        text: "重做(&R)"
        shortcut: "Ctrl+Shift+Z"
        enabled: redoStack.length > 0
        onTriggered: redo()
    }
    Action { id: cutAction;   text: "剪切(&T)"; shortcut: "Ctrl+X"; onTriggered: performClipboardOp("cut") }
    Action { id: copyAction;  text: "复制(&C)"; shortcut: "Ctrl+C"; onTriggered: performClipboardOp("copy") }
    Action { id: pasteAction; text: "粘贴(&P)"; shortcut: "Ctrl+V"; onTriggered: performClipboardOp("paste") }
    Action { id: findAction;  text: "查找(&F)..."; shortcut: "Ctrl+F"; onTriggered: { findBar.visible = true; findInput.forceActiveFocus() } }
    Action { id: replaceAction; text: "替换(&H)..."; shortcut: "Ctrl+H"; onTriggered: { findBar.visible = true; findInput.forceActiveFocus() } }

    Action { id: addExamAction;      text: "添加考试(&A)";  onTriggered: addExam() }
    Action { id: deleteExamAction;   text: "删除考试(&D)";  onTriggered: removeExam() }
    Action { id: duplicateExamAction;text: "复制考试(&C)";  onTriggered: duplicateExam() }
    Action { id: moveUpAction;       text: "上移(&U)";      onTriggered: moveExamUp() }
    Action { id: moveDownAction;     text: "下移(&D)";      onTriggered: moveExamDown() }


    Action {
        id: startPresentationAction
        text: "开始放映(&P)"
        shortcut: "F5"
        onTriggered: startPresentation()
    }

    Action { id: aboutAction; text: "关于 Aeterna(&A)"; onTriggered: aboutDialog.open() }

    menuBar: MenuBar {
        implicitHeight: 30
        background: Rectangle {
            color: Theme.materialBase
        }
        Menu {
            title: "文件(&F)"
            MenuItem { action: newFileAction }
            MenuItem { action: openFileAction }
            MenuItem { action: saveFileAction }
            MenuItem { action: saveAsAction }
            MenuSeparator {}
            MenuItem { action: importAction }
            MenuItem { action: exportAction }
            MenuSeparator {}
            MenuItem { action: closeAction }
        }
        Menu {
            title: "编辑(&E)"
            MenuItem { action: undoAction }
            MenuItem { action: redoAction }
            MenuSeparator {}
            MenuItem { action: cutAction }
            MenuItem { action: copyAction }
            MenuItem { action: pasteAction }
            MenuSeparator {}
            MenuItem { action: findAction }
            MenuItem { action: replaceAction }
        }
        Menu {
            title: "考试(&X)"
            MenuItem { action: addExamAction }
            MenuItem { action: deleteExamAction }
            MenuItem { action: duplicateExamAction }
            MenuSeparator {}
            MenuItem { action: moveUpAction }
            MenuItem { action: moveDownAction }
            MenuSeparator {}
            MenuItem { action: startPresentationAction }
        }
        Menu {
            title: "帮助(&H)"
            MenuItem { action: aboutAction }
        }
    }

    onClosing: function(close) {
        if (editorBackend.unsaved) {
            close.accepted = false
            promptUnsaved("close")
        }
    }

    // ── Debounce timer for field edits ──
    Timer {
        id: debounceTimer
        interval: 300
        repeat: false
        onTriggered: {
            pushSnapshot("编辑考试信息")
            editorBackend.markUnsaved()
            editorBackend.validateConfigWithDetails(buildConfigJson())
            editorBackend.update_exam_preview(-1)
        }
    }

    // ── Preview refresh timer — 每 30 秒更新预览倒计时 ──
    Timer {
        id: previewRefreshTimer
        interval: 30000
        running: true
        repeat: true
        onTriggered: editorBackend.update_exam_preview(-1)
    }

    // ═══════════════════════════════════════════════════════════════
    // Main layout: ActivityBar + Sidebar + Center + Bottom Panel + StatusBar
    // ═══════════════════════════════════════════════════════════════
    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ── Top row: ActivityBar + Sidebar + Center ──
        RowLayout {
            id: topRow
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

                // ── ActivityBar ──
                Item {
                    id: activityBar
                    Layout.preferredWidth: 44
                    Layout.fillHeight: true

                    Material {
                        anchors.fill: parent
                        tier: Material.Elevated
                        radius: 0
                        bordered: false
                    }

                    Rectangle {
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: 1
                        color: Theme.hairline
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.topMargin: Theme.spacing12
                        anchors.bottomMargin: Theme.spacing12
                        spacing: Theme.spacing8

                        Repeater {
                            model: [
                                { icon: "list.dash", label: "考试列表", panel: 0 },
                                { icon: "info",      label: "考试信息", panel: 1 },
                                { icon: "gear",      label: "设置",     panel: 2 }
                            ]

                            delegate: Rectangle {
                                Layout.alignment: Qt.AlignHCenter
                                width: Theme.sizeIconButtonMedium
                                height: Theme.sizeIconButtonMedium
                                radius: Theme.radiusSmall
                                color: editorWindow.activePanel === modelData.panel
                                       ? Qt.alpha(Theme.primary, 0.18)
                                       : "transparent"

                                Behavior on color {
                                    ColorAnimation { duration: Theme.motionShort; easing.type: Theme.motionStandard }
                                }

                                Icon {
                                    name: modelData.icon
                                    size: 20
                                    tier: editorWindow.activePanel === modelData.panel ? Icon.Accent : Icon.Secondary
                                    anchors.centerIn: parent
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    ToolTip.text: modelData.label
                                    ToolTip.delay: 500
                                    ToolTip.visible: containsMouse
                                    onClicked: editorWindow.activePanel = modelData.panel
                                }
                            }
                        }

                        Item { Layout.fillHeight: true }
                    }
                }

                // ── Primary Sidebar ──
                Item {
                    id: sidebarContainer
                    Layout.preferredWidth: sidebarSplitter.value
                    Layout.fillHeight: true

                    Material {
                        anchors.fill: parent
                        tier: Material.Elevated
                        radius: 0
                        bordered: false
                    }

                    Rectangle {
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: 1
                        color: Theme.hairline
                    }

                    StackLayout {
                        anchors.fill: parent
                        anchors.margins: Theme.spacing12
                        currentIndex: editorWindow.activePanel

                        // ── Panel 0: Exam List ──
                        ColumnLayout {
                            spacing: Theme.spacing12

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Theme.spacing12

                                Text {
                                    text: "考试列表"
                                    font.pixelSize: Theme.typeSubhead
                                    font.weight: Theme.weightSemibold
                                    color: Theme.foreground
                                    font.family: Theme.fontSans
                                    Layout.fillWidth: true
                                }

                                Icon {
                                    name: "arrow.right"
                                    size: 16
                                    tier: Icon.Secondary
                                    accessibleName: editorWindow.examListExpanded ? "折叠考试列表" : "展开考试列表"
                                    rotation: editorWindow.examListExpanded ? -90 : 90
                                    Layout.alignment: Qt.AlignVCenter
                                    Behavior on rotation {
                                        NumberAnimation { duration: Theme.motionShort; easing.type: Theme.motionStandard }
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: editorWindow.examListExpanded = !editorWindow.examListExpanded
                                    }
                                }
                            }

                            ListView {
                                id: examListView
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                model: examListModel
                                spacing: Theme.spacing4
                                clip: true
                                visible: editorWindow.examListExpanded

                                delegate: Rectangle {
                                    width: ListView.view.width
                                    height: Theme.sizeListItemXlarge
                                    radius: Theme.radiusSmall
                                    color: index === editorWindow.currentExamIndex
                                           ? Qt.alpha(Theme.primary, 0.18)
                                           : "transparent"

                                    Behavior on color {
                                        ColorAnimation { duration: Theme.motionShort; easing.type: Theme.motionStandard }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                                        onClicked: function(mouse) {
                                            if (mouse.button === Qt.RightButton) {
                                                editorWindow.contextMenuIndex = index
                                                examContextMenu.popup()
                                            } else {
                                                editorWindow.openExamTab(index)
                                            }
                                        }

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: Theme.spacing12
                                            anchors.rightMargin: Theme.spacing12
                                            spacing: Theme.spacing8

                                            ColumnLayout {
                                                spacing: Theme.spacing4
                                                Layout.fillWidth: true
                                                Layout.alignment: Qt.AlignVCenter

                                                Text {
                                                    text: name || "未命名考试"
                                                    color: Theme.foreground
                                                    font.family: Theme.fontSans
                                                    font.pixelSize: Theme.typeSubhead
                                                    font.weight: Theme.weightMedium
                                                    elide: Text.ElideRight
                                                    Layout.fillWidth: true
                                                }

                                                Text {
                                                    text: editorWindow.formatShortTimeRange(start, end)
                                                    color: Theme.mutedForeground
                                                    font.family: Theme.fontSans
                                                    font.pixelSize: Theme.typeCaption1
                                                    Layout.fillWidth: true
                                                }

                                                Rectangle {
                                                    visible: editorWindow.examStatusText(index).length > 0
                                                    height: 18
                                                    width: statusBadgeLabel.width + Theme.spacing12
                                                    radius: Theme.radiusPill
                                                    color: Qt.alpha(editorWindow.examStatusColor(index), 0.15)

                                                    Text {
                                                        id: statusBadgeLabel
                                                        anchors.centerIn: parent
                                                        text: editorWindow.examStatusText(index)
                                                        color: editorWindow.examStatusColor(index)
                                                        font.family: Theme.fontSans
                                                        font.pixelSize: Theme.typeCaption1
                                                        font.weight: Theme.weightMedium
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            PinguoButton {
                                text: "添加"
                                variant: PinguoButton.Primary
                                Layout.fillWidth: true
                                visible: editorWindow.examListExpanded
                                onClicked: addExam()
                            }
                        }

                        // ── Panel 1: Exam Info ──
                        ColumnLayout {
                            spacing: Theme.spacing12

                            Text {
                                text: "考试信息"
                                font.pixelSize: Theme.typeSubhead
                                font.weight: Theme.weightSemibold
                                color: Theme.foreground
                                font.family: Theme.fontSans
                            }

                            Item {
                                Layout.fillHeight: true
                                visible: editorWindow.currentExamIndex < 0 || editorWindow.currentExamIndex >= examListModel.count

                                Text {
                                    anchors.centerIn: parent
                                    text: "未选择考试"
                                    color: Qt.alpha(Theme.mutedForeground, 0.72)
                                    font.family: Theme.fontSans
                                    font.pixelSize: Theme.typeBody
                                }
                            }

                            ColumnLayout {
                                visible: editorWindow.currentExamIndex >= 0 && editorWindow.currentExamIndex < examListModel.count
                                spacing: Theme.spacing16
                                Layout.fillWidth: true

                                ColumnLayout {
                                    spacing: Theme.spacing8
                                    Layout.fillWidth: true
                                    Text { text: "考试名称"; color: Theme.mutedForeground; font.family: Theme.fontSans; font.pixelSize: Theme.typeCaption1 }
                                    Text {
                                        text: {
                                            var idx = editorWindow.currentExamIndex
                                            return (idx >= 0 && idx < examListModel.count)
                                                   ? (examListModel.get(idx).name || "未命名考试")
                                                   : "--"
                                        }
                                        color: Theme.foreground
                                        font.family: Theme.fontSans
                                        font.pixelSize: Theme.typeBody
                                        font.weight: Theme.weightMedium
                                        wrapMode: Text.Wrap
                                        Layout.fillWidth: true
                                    }
                                }

                                ColumnLayout {
                                    spacing: Theme.spacing8
                                    Layout.fillWidth: true
                                    Text { text: "时间范围"; color: Theme.mutedForeground; font.family: Theme.fontSans; font.pixelSize: Theme.typeCaption1 }
                                    Text {
                                        text: {
                                            var idx = editorWindow.currentExamIndex
                                            return (idx >= 0 && idx < examListModel.count)
                                                   ? editorWindow.formatShortTimeRange(
                                                         examListModel.get(idx).start,
                                                         examListModel.get(idx).end)
                                                   : "--"
                                        }
                                        color: Theme.foreground
                                        font.family: Theme.fontSans
                                        font.pixelSize: Theme.typeBody
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                }

                                Rectangle {
                                    height: 24
                                    width: infoStatusLabel.width + Theme.spacing16
                                    radius: Theme.radiusPill
                                    color: Qt.alpha(editorWindow.currentExamStatusColor(), 0.15)
                                    visible: editorWindow.currentExamIndex >= 0 && editorWindow.currentExamIndex < examListModel.count

                                    Text {
                                        id: infoStatusLabel
                                        anchors.centerIn: parent
                                        text: editorWindow.currentExamStatusText()
                                        color: editorWindow.currentExamStatusColor()
                                        font.family: Theme.fontSans
                                        font.pixelSize: Theme.typeCaption1
                                        font.weight: Theme.weightMedium
                                    }
                                }

                                ColumnLayout {
                                    spacing: Theme.spacing8
                                    Layout.fillWidth: true
                                    Text { text: "材料数量"; color: Theme.mutedForeground; font.family: Theme.fontSans; font.pixelSize: Theme.typeCaption1 }
                                    Text {
                                        text: {
                                            var idx = editorWindow.currentExamIndex
                                            var m = (idx >= 0 && idx < examListModel.count)
                                                    ? parseMaterials(examListModel.get(idx).materials)
                                                    : []
                                            return m.length + " 项"
                                        }
                                        color: Theme.foreground
                                        font.family: Theme.fontSans
                                        font.pixelSize: Theme.typeBody
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                }

                                Item { Layout.fillHeight: true }
                            }

                            // ── 实时预览卡片 ──
                            Material {
                                id: previewCard
                                Layout.fillWidth: true
                                Layout.preferredHeight: previewContent.implicitHeight + Theme.spacing24 * 2
                                tier: Material.Elevated
                                radius: Theme.radiusMedium
                                visible: previewData.status && previewData.status !== ""

                                readonly property var previewData: {
                                    if (!editorBackend.examPreviewJson || editorBackend.examPreviewJson.length === 0) {
                                        return {}
                                    }
                                    try {
                                        return JSON.parse(editorBackend.examPreviewJson)
                                    } catch (e) {
                                        return {}
                                    }
                                }

                                ColumnLayout {
                                    id: previewContent
                                    anchors.fill: parent
                                    anchors.margins: Theme.spacing16
                                    spacing: Theme.spacing12

                                    Text {
                                        text: "实时预览"
                                        font.pixelSize: Theme.typeCaption1
                                        font.weight: Theme.weightSemibold
                                        color: Theme.mutedForeground
                                        font.family: Theme.fontSans
                                    }

                                    // 状态徽章 + 倒计时
                                    RowLayout {
                                        spacing: Theme.spacing12

                                        Rectangle {
                                            height: 24
                                            width: previewStatusLabel.width + Theme.spacing16
                                            radius: Theme.radiusPill
                                            color: Qt.alpha(previewStatusColor(), 0.15)

                                            readonly property string statusText: previewCard.previewData.statusText || ""

                                            function previewStatusColor() {
                                                switch (previewCard.previewData.status) {
                                                    case "InProgress": return Theme.success
                                                    case "Pending": return Theme.warning
                                                    case "Completed": return Theme.warning
                                                    default: return Theme.mutedForeground
                                                }
                                            }

                                            Text {
                                                id: previewStatusLabel
                                                anchors.centerIn: parent
                                                text: parent.statusText
                                                color: parent.previewStatusColor()
                                                font.family: Theme.fontSans
                                                font.pixelSize: Theme.typeCaption1
                                                font.weight: Theme.weightMedium
                                            }
                                        }

                                        Text {
                                            text: previewCard.previewData.timeRange || ""
                                            color: Theme.mutedForeground
                                            font.family: Theme.fontSans
                                            font.pixelSize: Theme.typeCaption1
                                            Layout.alignment: Qt.AlignVCenter
                                        }
                                    }

                                    // 大字体倒计时
                                    Text {
                                        id: previewCountdownText
                                        text: previewCard.previewData.remainingTime || "--:--"
                                        font.pixelSize: Theme.typeTitle1
                                        font.weight: Theme.weightBold
                                        font.family: Theme.fontMono
                                        color: (previewCard.previewData.alertTime > 0
                                                && previewCard.previewData.remainingMs > 0
                                                && previewCard.previewData.remainingMs <= previewCard.previewData.alertTime * 60000)
                                               ? Theme.destructive
                                               : Theme.foreground
                                        Layout.fillWidth: true
                                    }

                                    // 进度条
                                    Item {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 6
                                        visible: previewCard.previewData.progress > 0

                                        Rectangle {
                                            anchors.fill: parent
                                            radius: 3
                                            color: Qt.alpha(Theme.foreground, 0.12)
                                        }
                                        Rectangle {
                                            width: parent.width * (previewCard.previewData.progress || 0)
                                            height: parent.height
                                            radius: 3
                                            color: Theme.primary
                                        }
                                    }
                                }
                            }
                        }

                        // ── Panel 2: Settings ──
                        ColumnLayout {
                            spacing: Theme.spacing12

                            Text {
                                text: "编辑器设置"
                                font.pixelSize: Theme.typeSubhead
                                font.weight: Theme.weightSemibold
                                color: Theme.foreground
                                font.family: Theme.fontSans
                            }

                            ColumnLayout {
                                spacing: Theme.spacing8
                                Layout.fillWidth: true

                                Text {
                                    text: "配置名称"
                                    font.pixelSize: Theme.typeCaption1
                                    color: Theme.mutedForeground
                                    font.family: Theme.fontSans
                                }
                                PinguoTextField {
                                    id: configNameField
                                    Layout.fillWidth: true
                                    placeholderText: "输入配置名称..."
                                    text: ""
                                    onTextChanged: { if (!_syncing) onFieldEdited() }
                                }
                            }

                            ColumnLayout {
                                spacing: Theme.spacing8
                                Layout.fillWidth: true

                                Text {
                                    text: "公告信息"
                                    font.pixelSize: Theme.typeCaption1
                                    color: Theme.mutedForeground
                                    font.family: Theme.fontSans
                                }
                                PinguoTextArea {
                                    id: configMessageField
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 80
                                    placeholderText: "输入公告信息..."
                                    text: ""
                                    onTextChanged: { if (!_syncing) onFieldEdited() }
                                }
                            }

                            Item { Layout.fillHeight: true }
                        }
                    }

                    ResizableSplitter {
                        id: sidebarSplitter
                        orientation: Qt.Vertical
                        minValue: 160
                        maxValue: 320
                        value: 220
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                    }
                }

                // ── Center area ──
                // Direct ColumnLayout (no extra Item wrapper) so that
                // Layout.fillWidth / fillHeight propagate correctly and the
                // loaded ExamForm gets the full available width.
                ColumnLayout {
                    id: centerArea
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumWidth: 480
                    spacing: 0

                    // Find bar
                    Rectangle {
                        id: findBar
                        Layout.fillWidth: true
                        Layout.preferredHeight: visible ? 40 : 0
                        visible: false
                        color: Qt.alpha(Theme.primary, 0.08)
                        radius: Theme.radiusSmall

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.spacing12
                            anchors.rightMargin: Theme.spacing12
                            spacing: Theme.spacing8

                            Icon {
                                name: "magnifyingglass"
                                size: 16
                                tier: Icon.Secondary
                                Layout.alignment: Qt.AlignVCenter
                            }
                            PinguoTextField {
                                id: findInput
                                Layout.fillWidth: true
                                placeholderText: "查找考试名称..."
                                inputItem.selectByMouse: true
                                onTextChanged: editorWindow.findInPage(text)
                                Keys.onEscapePressed: findBar.visible = false
                            }
                            Text {
                                id: findResultText
                                visible: false
                                text: ""
                                color: Theme.mutedForeground
                                font.pixelSize: Theme.typeCaption1
                                font.family: Theme.fontSans
                                Layout.alignment: Qt.AlignVCenter
                            }
                            Icon {
                                name: "xmark"
                                size: 16
                                tier: Icon.Secondary
                                accessibleName: "关闭查找"
                                Layout.alignment: Qt.AlignVCenter
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: { findBar.visible = false; findInput.text = "" }
                                }
                            }
                        }
                    }

                    // Tab bar with add button — uses ListView instead of TabBar
                    // to avoid KDE desktop style crash (contentModel.get(0) is null
                    // when content is briefly empty during creation).
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Theme.sizeTabBar
                        Layout.minimumHeight: Theme.sizeTabBar
                        Layout.maximumHeight: Theme.sizeTabBar
                        spacing: 0

                        ListView {
                            id: examTabBar
                            Layout.fillWidth: true
                            Layout.fillHeight: false
                            Layout.minimumWidth: 0
                            Layout.preferredHeight: Theme.sizeTabBar
                            visible: openTabIndices.length > 0
                            model: openTabIndices
                            orientation: ListView.Horizontal
                            clip: true
                            spacing: 0
                            boundsBehavior: Flickable.StopAtBounds
                            flickableDirection: Flickable.HorizontalFlick
                            height: parent.height

                            // Bottom hairline
                            Rectangle {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                height: 1
                                color: Theme.hairline
                            }

                            delegate: Item {
                                width: tabContent.implicitWidth + Theme.spacing12 * 2
                                height: ListView.view.height

                                property int examIndex: modelData
                                property bool isActive: ListView.isCurrentItem
                                property bool hovered: tabMouse.containsMouse

                                Rectangle {
                                    anchors.fill: parent
                                    color: parent.hovered && !parent.isActive
                                           ? Qt.alpha(Theme.primary, 0.08)
                                           : "transparent"
                                    Behavior on color {
                                        ColorAnimation { duration: Theme.motionShort; easing.type: Theme.motionStandard }
                                    }
                                }

                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    height: 2
                                    color: parent.isActive ? Theme.primary : "transparent"
                                }

                                RowLayout {
                                    id: tabContent
                                    anchors.fill: parent
                                    anchors.leftMargin: Theme.spacing12
                                    anchors.rightMargin: Theme.spacing12
                                    spacing: Theme.spacing8

                                    Text {
                                        text: examIndex >= 0 && examIndex < examListModel.count
                                              ? (examListModel.get(examIndex).name || "未命名考试")
                                              : "未命名考试"
                                        color: isActive ? Theme.primary : Theme.mutedForeground
                                        font.family: Theme.fontSans
                                        font.pixelSize: Theme.typeSubhead
                                        font.weight: isActive ? Theme.weightSemibold : Theme.weightRegular
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                        Layout.maximumWidth: 200
                                        verticalAlignment: Text.AlignVCenter
                                    }

                                    Icon {
                                        name: "xmark"
                                        size: 16
                                        tier: hovered ? Icon.Danger : Icon.Tertiary
                                        accessibleName: "关闭标签页"
                                        Layout.alignment: Qt.AlignVCenter
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onPressed: function(mouse) {
                                                mouse.accepted = true
                                            }
                                            onClicked: function(mouse) {
                                                mouse.accepted = true
                                                var pos = editorWindow.tabPositionForExam(examIndex)
                                                if (pos >= 0) editorWindow.closeTabAt(pos)
                                            }
                                        }
                                    }
                                }

                                MouseArea {
                                    id: tabMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: editorWindow.activateTab(examIndex)
                                }
                            }
                        }

                        Item {
                            Layout.fillWidth: true
                            visible: openTabIndices.length === 0

                            Rectangle {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                height: 1
                                color: Theme.hairline
                            }
                        }


                    }

                    // Empty state
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: openTabIndices.length === 0

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: Theme.spacing16

                            Icon {
                                name: "doc"
                                size: 24
                                tier: Icon.Tertiary
                                Layout.alignment: Qt.AlignHCenter
                            }

                            Text {
                                text: "请从左侧考试列表选择一个考试进行编辑"
                                color: Theme.mutedForeground
                                font.family: Theme.fontSans
                                font.pixelSize: Theme.typeBody
                                Layout.alignment: Qt.AlignHCenter
                            }

                            PinguoButton {
                                text: "添加第一个考试"
                                variant: PinguoButton.Hero
                                Layout.alignment: Qt.AlignHCenter
                                visible: examListModel.count === 0
                                onClicked: addExam()
                            }
                        }
                    }

                    // Active exam form — VSCode / browser-style tab content.
                    // ExamForm is a ColumnLayout; we place it directly inside
                    // the Flickable and bind both width and height to the
                    // Flickable's content area, avoiding the Loader+ColumnLayout
                    // width-collapse that previously compressed the form into
                    // a narrow strip.
                    Flickable {
                        id: examFormFlick
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: openTabIndices.length > 0
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        contentWidth: width
                        contentHeight: examForm.y + examForm.height + Theme.spacing24
                        ScrollBar.vertical: ScrollBar {
                            contentItem: Rectangle {
                                implicitWidth: 6
                                radius: 3
                                color: Qt.alpha(Theme.foreground, 0.24)
                            }
                        }

                        ExamForm {
                            id: examForm
                            x: Theme.spacing24
                            y: Theme.spacing16
                            width: examFormFlick.availableWidth - Theme.spacing24 * 2
                            height: implicitHeight
                            examListModel: examListModel
                            editorWindow: editorWindow
                            currentExamIndex: editorWindow.currentExamIndex
                        }
                    }
                }
            }

        // ── Bottom Panel splitter ──
        ResizableSplitter {
            id: bottomSplitter
            orientation: Qt.Horizontal
            minValue: 120
            maxValue: 400
            value: editorWindow.bottomPanelHeight
            Layout.fillWidth: true
            visible: editorWindow.bottomPanelVisible
        }

        // ── Bottom Panel ──
        Item {
            id: bottomPanel
            Layout.fillWidth: true
            Layout.preferredHeight: bottomSplitter.value
            visible: editorWindow.bottomPanelVisible

            Material {
                anchors.fill: parent
                tier: Material.Elevated
                radius: 0
                bordered: false
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: 1
                color: Theme.hairline
            }

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                // Header
                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Theme.sizeListItemSmall
                    Layout.leftMargin: Theme.spacing12
                    Layout.rightMargin: Theme.spacing12
                    spacing: Theme.spacing12

                    Text {
                        text: "问题"
                        color: Theme.foreground
                        font.family: Theme.fontSans
                        font.pixelSize: Theme.typeSubhead
                        font.weight: Theme.weightSemibold
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Text {
                        text: "(" + errorCount + "/" + warningCount + ")"
                        color: Theme.mutedForeground
                        font.family: Theme.fontSans
                        font.pixelSize: Theme.typeCaption1
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Item { Layout.fillWidth: true }

                    Icon {
                        name: "xmark"
                        size: 16
                        tier: Icon.Secondary
                        accessibleName: "关闭问题面板"
                        Layout.alignment: Qt.AlignVCenter
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: editorWindow.bottomPanelVisible = false
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    color: Theme.hairline
                }

                ValidationPanel {
                    id: validationPanel
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    showTitle: false
                    reportJson: editorBackend.validationReportJson
                    onJumpTo: {
                        editorWindow.openExamTab(examIndex)
                    }
                }
            }
        }

        // ── Status bar ──
        Material {
            id: statusBar
            Layout.fillWidth: true
            Layout.preferredHeight: 32
            tier: Material.Vibrant
            radius: 0
            bordered: false

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: 1
                color: Theme.hairline
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.spacing12
                anchors.rightMargin: Theme.spacing12
                spacing: Theme.spacing16

                // Left: total count
                Text {
                    text: "共 " + examListModel.count + " 个考试"
                    color: Theme.mutedForeground
                    font.family: Theme.fontSans
                    font.pixelSize: Theme.typeCaption1
                    Layout.alignment: Qt.AlignVCenter
                }

                Item { Layout.fillWidth: true }

                // Center: current exam + status
                RowLayout {
                    spacing: Theme.spacing12
                    Layout.alignment: Qt.AlignVCenter

                    Text {
                        text: editorWindow.currentExamIndex >= 0 && editorWindow.currentExamIndex < examListModel.count
                              ? "正在编辑: " + examListModel.get(editorWindow.currentExamIndex).name
                              : "未选择考试"
                        color: Theme.mutedForeground
                        font.family: Theme.fontSans
                        font.pixelSize: Theme.typeCaption1
                        Layout.alignment: Qt.AlignVCenter
                        elide: Text.ElideRight
                        Layout.maximumWidth: 300
                    }

                    Rectangle {
                        visible: editorWindow.currentExamIndex >= 0 && editorWindow.currentExamIndex < examListModel.count
                        height: 20
                        width: statusLabel.width + Theme.spacing16
                        radius: Theme.radiusPill
                        color: Qt.alpha(statusColor, 0.15)

                        readonly property string statusText: editorWindow.currentExamStatusText()
                        readonly property color statusColor: editorWindow.currentExamStatusColor()

                        Text {
                            id: statusLabel
                            anchors.centerIn: parent
                            text: parent.statusText
                            color: parent.statusColor
                            font.family: Theme.fontSans
                            font.pixelSize: Theme.typeCaption1
                            font.weight: Theme.weightMedium
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                // Right: validation status + save state
                RowLayout {
                    spacing: Theme.spacing16
                    Layout.alignment: Qt.AlignVCenter

                    RowLayout {
                        id: validationStatusRow
                        spacing: Theme.spacing8
                        Layout.alignment: Qt.AlignVCenter

                        Icon {
                            name: errorCount > 0 ? "xmark"
                                                 : (warningCount > 0 ? "exclamationmark.triangle"
                                                                     : "checkmark.circle")
                            size: 16
                            tier: errorCount > 0 ? Icon.Danger
                                                 : (warningCount > 0 ? Icon.Warning : Icon.Success)
                            Layout.alignment: Qt.AlignVCenter
                        }
                        Text {
                            text: errorCount > 0 ? (errorCount + " 个错误")
                                                 : (warningCount > 0 ? (warningCount + " 个警告") : "就绪")
                            color: errorCount > 0 ? Theme.destructive
                                                  : (warningCount > 0 ? Theme.warning : Theme.success)
                            font.family: Theme.fontSans
                            font.pixelSize: Theme.typeCaption1
                            Layout.alignment: Qt.AlignVCenter
                        }

                        MouseArea {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: editorWindow.bottomPanelVisible = !editorWindow.bottomPanelVisible
                        }
                    }

                    Rectangle {
                        width: 1
                        height: 16
                        color: Theme.hairline
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Text {
                        text: editorBackend.unsaved ? "已修改" : "已保存"
                        color: editorBackend.unsaved ? Theme.warning : Theme.success
                        font.family: Theme.fontSans
                        font.pixelSize: Theme.typeCaption1
                        Layout.alignment: Qt.AlignVCenter
                    }
                }
            }
        }
    }

    // ── Data model ──
    ListModel {
        id: examListModel
    }

    // ── Exam list context menu ──
    Menu {
        id: examContextMenu
        MenuItem {
            text: "删除"
            enabled: contextMenuIndex >= 0
            onTriggered: removeExam(contextMenuIndex)
        }
        MenuItem {
            text: "复制"
            enabled: contextMenuIndex >= 0
            onTriggered: duplicateExam(contextMenuIndex)
        }
        MenuSeparator {}
        MenuItem {
            text: "上移"
            enabled: contextMenuIndex > 0
            onTriggered: moveExamUp(contextMenuIndex)
        }
        MenuItem {
            text: "下移"
            enabled: contextMenuIndex >= 0 && contextMenuIndex < examListModel.count - 1
            onTriggered: moveExamDown(contextMenuIndex)
        }
    }

    // ── File dialogs ──
    Platform.FileDialog {
        id: openFileDialog
        title: "打开考试配置"
        nameFilters: ["Aeterna 配置文件 (*.aeterna *.json)", "所有文件 (*)"]
        onAccepted: {
            editorBackend.loadFile(file)
            syncFromBackendJson()
            editorBackend.addRecentFile(file)
        }
    }

    Platform.FileDialog {
        id: saveAsDialog
        title: "另存为"
        nameFilters: ["Aeterna 配置文件 (*.aeterna)", "JSON 文件 (*.json)"]
        fileMode: Platform.FileDialog.SaveFile
        onAccepted: {
            performSaveAs(file)
            executePendingAction()
        }
        onRejected: {
            pendingAction = ""
        }
    }

    Platform.FileDialog {
        id: importDialog
        title: "导入 JSON"
        nameFilters: ["JSON 文件 (*.json)", "Aeterna 配置文件 (*.aeterna)", "所有文件 (*)"]
        onAccepted: {
            editorBackend.importFromFile(file)
            syncFromBackendJson()
        }
    }

    Platform.FileDialog {
        id: exportDialog
        title: "导出 JSON"
        nameFilters: ["JSON 文件 (*.json)"]
        fileMode: Platform.FileDialog.SaveFile
        onAccepted: {
            editorBackend.exportToFile(file, buildConfigJson())
        }
    }

    // ── Unsaved changes dialog ──
    ConfirmDialog {
        id: unsavedDialog
        titleText: "未保存的更改"
        messageText: "在继续之前，是否要保存当前配置？"

        footer: RowLayout {
            spacing: Theme.spacing12
            Layout.margins: Theme.spacing16

            Item { Layout.fillWidth: true }

            PinguoButton {
                text: "取消"
                variant: PinguoButton.Text
                onClicked: {
                    pendingAction = ""
                    unsavedDialog.reject()
                }
            }
            PinguoButton {
                text: "不保存"
                variant: PinguoButton.Secondary
                onClicked: unsavedDialog.discardChanges()
            }
            PinguoButton {
                text: "保存"
                variant: PinguoButton.Primary
                onClicked: unsavedDialog.saveAndContinue()
            }
        }

        function saveAndContinue() {
            if (editorBackend.currentFilePath.length > 0) {
                if (performSave()) {
                    executePendingAction()
                    unsavedDialog.close()
                }
            } else {
                unsavedDialog.close()
                saveAsDialog.open()
            }
        }

        function discardChanges() {
            editorBackend.markSaved()
            executePendingAction()
            unsavedDialog.close()
        }

        onRejected: pendingAction = ""
    }

    // ── Delete exam confirmation dialog ──
    ConfirmDialog {
        id: confirmDeleteDialog
        titleText: "删除考试"
        messageText: "确定要删除当前考试吗？此操作不可撤销。"

        footer: RowLayout {
            spacing: Theme.spacing12
            Layout.margins: Theme.spacing16

            Item { Layout.fillWidth: true }

            PinguoButton {
                text: "取消"
                variant: PinguoButton.Text
                onClicked: confirmDeleteDialog.reject()
            }
            PinguoButton {
                text: "删除"
                variant: PinguoButton.Primary
                onClicked: {
                    confirmDeleteDialog.close()
                    doRemoveExam()
                }
            }
        }

        onRejected: confirmDeleteDialog.close()
    }

    // ── About dialog ──
    AboutDialog {
        id: aboutDialog
    }

    // ═══════════════════════════════════════════════════════════════
    // Functions
    // ═══════════════════════════════════════════════════════════════

    // ── Clipboard operations ──
    function findFocusedTextInput(obj) {
        if (!obj) return null
        if (obj.hasOwnProperty("selectedText") && typeof obj.selectAll === "function") {
            return obj
        }
        if (obj.hasOwnProperty("inputItem") && obj.inputItem) {
            return findFocusedTextInput(obj.inputItem)
        }
        for (var i = 0; i < obj.children.length; i++) {
            var child = obj.children[i]
            if (child.activeFocus) {
                var result = findFocusedTextInput(child)
                if (result) return result
            }
        }
        return null
    }

    function performClipboardOp(op) {
        var focused = findFocusedTextInput(editorWindow.contentItem)
        if (!focused) return
        if (op === "cut") {
            focused.cut()
        } else if (op === "copy") {
            focused.copy()
        } else if (op === "paste") {
            focused.paste()
        }
    }

    // ── Find in page ──
    function findInPage(text) {
        if (!text || text.length === 0) {
            findResultText.visible = false
            return
        }
        // Search through exam names and content
        var found = false
        for (var i = 0; i < examListModel.count; i++) {
            var ex = examListModel.get(i)
            if (ex.name.toLowerCase().indexOf(text.toLowerCase()) >= 0) {
                openExamTab(i)
                found = true
                break
            }
        }
        findResultText.text = found ? "已找到匹配项" : "未找到匹配项"
        findResultText.visible = true
    }

    // ── Tab management ──
    // openTabIndices is a JS array — QML cannot bind to JS array mutations.
    // Every mutation MUST call notifyTabsChanged() to trigger UI refresh.
    function tabPositionForExam(examIndex) {
        for (var i = 0; i < openTabIndices.length; i++) {
            if (openTabIndices[i] === examIndex) return i
        }
        return -1
    }

    function syncTabBarCurrentIndex() {
        examTabBar.currentIndex = tabPositionForExam(currentExamIndex)
    }

    function notifyTabsChanged() {
        openTabIndices = openTabIndices.slice()
    }

    function openExamTab(index) {
        if (index < 0 || index >= examListModel.count) return
        var pos = tabPositionForExam(index)
        if (pos < 0) {
            openTabIndices.push(index)
            notifyTabsChanged()
            pos = openTabIndices.length - 1
        }
        currentExamIndex = index
        syncTabBarCurrentIndex()
        editorBackend.update_exam_preview(index)
    }

    function activateTab(examIndex) {
        if (examIndex < 0 || examIndex >= examListModel.count) return
        currentExamIndex = examIndex
        syncTabBarCurrentIndex()
    }

    function closeTabAt(pos) {
        if (pos < 0 || pos >= openTabIndices.length) return
        var closedExam = openTabIndices[pos]
        openTabIndices.splice(pos, 1)
        notifyTabsChanged()

        if (currentExamIndex === closedExam) {
            // Switch to adjacent tab
            var newPos = Math.min(pos, openTabIndices.length - 1)
            currentExamIndex = newPos >= 0 ? openTabIndices[newPos] : -1
        }
        syncTabBarCurrentIndex()
    }

    function removeTabForDeletedExam(deletedIndex) {
        var newTabs = []
        var newActive = currentExamIndex
        for (var i = 0; i < openTabIndices.length; i++) {
            var idx = openTabIndices[i]
            if (idx === deletedIndex) {
                if (currentExamIndex === idx) newActive = -1
                continue
            }
            if (idx > deletedIndex) idx--
            newTabs.push(idx)
        }
        openTabIndices = newTabs

        if (newActive >= examListModel.count) {
            newActive = examListModel.count - 1
        }
        if (newActive < 0 && openTabIndices.length > 0) {
            newActive = openTabIndices[0]
        }
        currentExamIndex = newActive
        syncTabBarCurrentIndex()
    }

    // ── Status helpers ──
    function currentExamStatusText() {
        if (currentExamIndex < 0 || currentExamIndex >= examListModel.count) return ""
        var ex = examListModel.get(currentExamIndex)
        var s = parseDateTime(ex.start)
        var e = parseDateTime(ex.end)
        if (isNaN(s.getTime()) || isNaN(e.getTime())) return "待设置"
        var now = new Date()
        if (now < s) return "未开始"
        if (now >= s && now <= e) return "进行中"
        return "已结束"
    }

    function currentExamStatusColor() {
        var status = currentExamStatusText()
        switch (status) {
            case "进行中": return Theme.success
            case "未开始": return Theme.warning
            case "已结束": return Theme.warning
            case "待设置": return Theme.destructive
            default: return Theme.mutedForeground
        }
    }

    function examStatusText(index) {
        if (index < 0 || index >= examListModel.count) return ""
        var ex = examListModel.get(index)
        var s = parseDateTime(ex.start)
        var e = parseDateTime(ex.end)
        if (isNaN(s.getTime()) || isNaN(e.getTime())) return "待设置"
        var now = new Date()
        if (now < s) return "未开始"
        if (now >= s && now <= e) return "进行中"
        return "已结束"
    }

    function examStatusColor(index) {
        var status = examStatusText(index)
        switch (status) {
            case "进行中": return Theme.success
            case "未开始": return Theme.warning
            case "已结束": return Theme.warning
            case "待设置": return Theme.destructive
            default: return Theme.mutedForeground
        }
    }

    function formatShortDateTime(str) {
        var parts = str.match(/(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})/)
        if (!parts) return "--"
        return parts[2] + "/" + parts[3] + " " + parts[4] + ":" + parts[5]
    }

    function formatShortTimeRange(startStr, endStr) {
        var s = formatShortDateTime(startStr)
        var e = formatShortDateTime(endStr)
        return s + " - " + e
    }

    function validateConfigWithDetails(json) {
        editorBackend.validateConfigWithDetails(json)
    }

    function buildConfigJson() {
        var exams = []
        for (var i = 0; i < examListModel.count; i++) {
            var ex = examListModel.get(i)
            exams.push({
                name: ex.name || "",
                start: ex.start || "",
                end: ex.end || "",
                alertTime: ex.alertTime !== undefined ? ex.alertTime : 5,
                materials: parseMaterials(ex.materials)
            })
        }
        var config = {
            examName: configNameField.text,
            message: configMessageField.text,
            examInfos: exams
        }
        return JSON.stringify(config)
    }

    function syncFromBackendJson() {
        var json = editorBackend.configJson
        if (!json || json.length === 0) return
        try {
            _syncing = true
            var config = JSON.parse(json)
            configNameField.text = config.examName || ""
            configMessageField.text = config.message || ""
            examListModel.clear()
            var infos = config.examInfos || []
            for (var i = 0; i < infos.length; i++) {
                examListModel.append({
                    name: infos[i].name || "",
                    start: infos[i].start || "",
                    end: infos[i].end || "",
                    alertTime: infos[i].alertTime !== undefined ? infos[i].alertTime : 5,
                    materials: stringifyMaterials(infos[i].materials)
                })
            }
            openTabIndices = []
            currentExamIndex = infos.length > 0 ? 0 : -1
            if (currentExamIndex >= 0) {
                openTabIndices.push(currentExamIndex)
            }
            notifyTabsChanged()
            syncTabBarCurrentIndex()
            undoStack = []
            redoStack = []
            updateUndoRedoState()
            _syncing = false
            editorBackend.validateConfigWithDetails(buildConfigJson())
        } catch (e) {
            _syncing = false
            console.error("syncFromBackendJson failed: " + e)
        }
    }

    function onFieldEdited() {
        if (_syncing) return
        debounceTimer.restart()
    }

    // QML ListModel converts JS arrays into ListModel objects, which break
    // JSON.stringify. Store materials as a JSON string instead and parse it
    // back when needed.
    function parseMaterials(value) {
        if (value === undefined || value === null) return []
        if (typeof value === "string") {
            try { return JSON.parse(value) } catch (e) { return [] }
        }
        if (Array.isArray(value)) return value
        return []
    }

    function stringifyMaterials(arr) {
        return JSON.stringify(arr || [])
    }

    function serializeExams() {
        var list = []
        for (var i = 0; i < examListModel.count; i++) {
            var ex = examListModel.get(i)
            list.push({
                name: ex.name,
                start: ex.start,
                end: ex.end,
                alertTime: ex.alertTime,
                materials: parseMaterials(ex.materials)
            })
        }
        return list
    }

    function pushSnapshot(tag) {
        var snapshot = {
            tag: tag || "操作",
            examName: configNameField.text,
            message: configMessageField.text,
            examList: serializeExams()
        }
        undoStack.push(snapshot)
        if (undoStack.length > maxUndoSteps) {
            undoStack.shift()
        }
        redoStack = []
        updateUndoRedoState()
    }

    function restoreSnapshot(snapshot) {
        _syncing = true
        configNameField.text = snapshot.examName
        configMessageField.text = snapshot.message
        examListModel.clear()
        for (var i = 0; i < snapshot.examList.length; i++) {
            var ex = snapshot.examList[i]
            examListModel.append({
                name: ex.name,
                start: ex.start,
                end: ex.end,
                alertTime: ex.alertTime,
                materials: stringifyMaterials(ex.materials)
            })
        }
        if (currentExamIndex >= examListModel.count) {
            currentExamIndex = Math.max(-1, examListModel.count - 1)
        }
        if (currentExamIndex >= 0 && tabPositionForExam(currentExamIndex) < 0) {
            openTabIndices = [currentExamIndex]
        } else if (currentExamIndex < 0) {
            openTabIndices = []
        }
        notifyTabsChanged()
        syncTabBarCurrentIndex()
        _syncing = false
        editorBackend.validateConfigWithDetails(buildConfigJson())
    }

    function undo() {
        if (undoStack.length === 0) return
        var current = {
            tag: "撤销前",
            examName: configNameField.text,
            message: configMessageField.text,
            examList: serializeExams()
        }
        redoStack.push(current)
        var prev = undoStack.pop()
        restoreSnapshot(prev)
        editorBackend.markUnsaved()
        updateUndoRedoState()
    }

    function redo() {
        if (redoStack.length === 0) return
        var current = {
            tag: "重做前",
            examName: configNameField.text,
            message: configMessageField.text,
            examList: serializeExams()
        }
        undoStack.push(current)
        var next = redoStack.pop()
        restoreSnapshot(next)
        editorBackend.markUnsaved()
        updateUndoRedoState()
    }

    function updateUndoRedoState() {
        undoAction.enabled = undoStack.length > 0
        redoAction.enabled = redoStack.length > 0
    }

    function promptUnsaved(action) {
        pendingAction = action
        unsavedDialog.open()
    }

    function executePendingAction() {
        var action = pendingAction
        pendingAction = ""
        if (action === "close") {
            editorBackend.markSaved()
            editorWindow.close()
        } else if (action === "new") {
            doNewConfig()
        } else if (action === "open") {
            openFileDialog.open()
        } else if (action === "start") {
            doStartPresentation()
        }
    }

    function newConfigWithCheck() {
        if (editorBackend.unsaved) {
            promptUnsaved("new")
        } else {
            doNewConfig()
        }
    }

    function doNewConfig() {
        editorBackend.newConfig()
        syncFromBackendJson()
    }

    function openWithCheck() {
        if (editorBackend.unsaved) {
            promptUnsaved("open")
        } else {
            openFileDialog.open()
        }
    }

    function saveFile() {
        if (editorBackend.currentFilePath.length > 0) {
            performSave()
        } else {
            saveAsDialog.open()
        }
    }

    function performSave() {
        var path = editorBackend.currentFilePath
        if (!path) {
            saveAsDialog.open()
            return false
        }
        var ok = editorBackend.saveToFile(path, buildConfigJson())
        if (ok) {
            editorBackend.addRecentFile(path)
        }
        return ok
    }

    function performSaveAs(url) {
        var ok = editorBackend.saveToFile(url, buildConfigJson())
        if (ok) {
            editorBackend.addRecentFile(url)
        }
        return ok
    }

    function parseDateTime(str) {
        var parts = str.match(/(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})/)
        if (!parts) return new Date(NaN)
        return new Date(
            parseInt(parts[1], 10),
            parseInt(parts[2], 10) - 1,
            parseInt(parts[3], 10),
            parseInt(parts[4], 10),
            parseInt(parts[5], 10),
            parseInt(parts[6], 10)
        )
    }

    function formatDateTime(d) {
        var pad = function(n) { return n < 10 ? "0" + n : n }
        return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate()) + " " +
               pad(d.getHours()) + ":" + pad(d.getMinutes()) + ":" + pad(d.getSeconds())
    }

    function addMinutes(d, minutes) {
        return new Date(d.getTime() + minutes * 60000)
    }

    function generateDefaultExamName() {
        var base = "未命名考试"
        var used = {}
        for (var i = 0; i < examListModel.count; i++) {
            used[examListModel.get(i).name] = true
        }
        var candidate = base
        var index = 1
        while (used[candidate]) {
            candidate = base + " " + index
            index++
        }
        return candidate
    }

    function findLatestEndTime() {
        var latest = new Date(NaN)
        for (var i = 0; i < examListModel.count; i++) {
            var end = parseDateTime(examListModel.get(i).end)
            if (!isNaN(end.getTime())) {
                if (isNaN(latest.getTime()) || end > latest) {
                    latest = end
                }
            }
        }
        return latest
    }

    function defaultNewExamStart() {
        var latest = findLatestEndTime()
        if (!isNaN(latest.getTime())) {
            return addMinutes(latest, 10)
        }
        var now = new Date()
        now.setMinutes(0, 0, 0)
        return addMinutes(now, 60)
    }

    function addExam() {
        _syncing = true
        pushSnapshot("添加考试")
        var start = defaultNewExamStart()
        var end = addMinutes(start, 60)
        examListModel.append({
            name: generateDefaultExamName(),
            start: formatDateTime(start),
            end: formatDateTime(end),
            alertTime: 5,
            materials: stringifyMaterials([])
        })
        var newIndex = examListModel.count - 1
        openTabIndices.push(newIndex)
        notifyTabsChanged()
        currentExamIndex = newIndex
        syncTabBarCurrentIndex()
        _syncing = false
        editorBackend.markUnsaved()
        editorBackend.validateConfigWithDetails(buildConfigJson())
    }

    function removeExam(index) {
        var idx = (index === undefined) ? editorWindow.currentExamIndex : index
        if (idx < 0 || idx >= examListModel.count) return
        currentExamIndex = idx
        confirmDeleteDialog.open()
    }

    function doRemoveExam() {
        var idx = editorWindow.currentExamIndex
        if (idx < 0 || idx >= examListModel.count) return
        _syncing = true
        pushSnapshot("删除考试")
        examListModel.remove(idx)
        removeTabForDeletedExam(idx)
        if (currentExamIndex >= examListModel.count) {
            currentExamIndex = Math.max(-1, examListModel.count - 1)
        }
        _syncing = false
        editorBackend.markUnsaved()
        editorBackend.validateConfigWithDetails(buildConfigJson())
    }

    function duplicateExam(index) {
        var idx = (index === undefined) ? editorWindow.currentExamIndex : index
        if (idx < 0 || idx >= examListModel.count) return
        var src = examListModel.get(idx)
        _syncing = true
        pushSnapshot("复制考试")

        var start = defaultNewExamStart()
        var duration = 60
        var srcStart = parseDateTime(src.start)
        var srcEnd = parseDateTime(src.end)
        if (!isNaN(srcStart.getTime()) && !isNaN(srcEnd.getTime()) && srcEnd > srcStart) {
            duration = Math.round((srcEnd.getTime() - srcStart.getTime()) / 60000)
        }
        var end = addMinutes(start, duration)

        var copy = {
            name: (src.name || "未命名考试") + "（副本）",
            start: formatDateTime(start),
            end: formatDateTime(end),
            alertTime: src.alertTime !== undefined ? src.alertTime : 5,
            materials: stringifyMaterials(parseMaterials(src.materials))
        }
        examListModel.append(copy)
        var newIndex = examListModel.count - 1
        openTabIndices.push(newIndex)
        notifyTabsChanged()
        currentExamIndex = newIndex
        syncTabBarCurrentIndex()
        _syncing = false
        editorBackend.markUnsaved()
        editorBackend.validateConfigWithDetails(buildConfigJson())
    }

    function moveExamUp(index) {
        var idx = (index === undefined) ? editorWindow.currentExamIndex : index
        if (idx <= 0) return
        _syncing = true
        pushSnapshot("上移考试")
        swapExams(idx, idx - 1)
        currentExamIndex = idx - 1
        syncTabBarCurrentIndex()
        _syncing = false
        editorBackend.markUnsaved()
        editorBackend.validateConfigWithDetails(buildConfigJson())
    }

    function moveExamDown(index) {
        var idx = (index === undefined) ? editorWindow.currentExamIndex : index
        if (idx < 0 || idx >= examListModel.count - 1) return
        _syncing = true
        pushSnapshot("下移考试")
        swapExams(idx, idx + 1)
        currentExamIndex = idx + 1
        syncTabBarCurrentIndex()
        _syncing = false
        editorBackend.markUnsaved()
        editorBackend.validateConfigWithDetails(buildConfigJson())
    }

    function swapExams(i, j) {
        if (i < 0 || j < 0 || i >= examListModel.count || j >= examListModel.count) return
        var a = examListModel.get(i)
        var b = examListModel.get(j)
        examListModel.set(i, {
            name: b.name,
            start: b.start,
            end: b.end,
            alertTime: b.alertTime,
            materials: stringifyMaterials(parseMaterials(b.materials))
        })
        examListModel.set(j, {
            name: a.name,
            start: a.start,
            end: a.end,
            alertTime: a.alertTime,
            materials: stringifyMaterials(parseMaterials(a.materials))
        })
    }

    function startPresentation() {
        if (editorBackend.unsaved) {
            promptUnsaved("start")
        } else {
            doStartPresentation()
        }
    }

    function doStartPresentation() {
        var configStr = buildConfigJson()
        var comp = Qt.createComponent("PlayerWindow.qml")
        if (comp.status === Component.Ready) {
            var win = comp.createObject(editorWindow)
            win.loadExamData(configStr)
            win.showFullScreen()
        } else if (comp.status === Component.Error) {
            console.error("Failed to load PlayerWindow: " + comp.errorString())
        } else {
            comp.statusChanged.connect(function() {
                if (comp.status === Component.Ready) {
                    var win = comp.createObject(editorWindow)
                    win.loadExamData(configStr)
                    win.showFullScreen()
                }
            })
        }
    }
}
