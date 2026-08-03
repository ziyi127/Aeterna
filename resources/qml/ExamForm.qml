import QtQuick 2.15
import "."
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

// =====================================================================
// ExamForm — single-exam editor
// =====================================================================
// Field order and visual styling:
//   name → start → end → alertTime → materials → validation
// =====================================================================

ColumnLayout {
    id: root
    spacing: Theme.spacing24

    property int currentExamIndex: -1
    property bool endBeforeStart: false
    property bool _syncing: false
    property bool materialsExpanded: true
    property int pendingMaterialIndex: -1
    property bool pendingMaterialClear: false

    // Materials helpers — see MaterialUtils.qml for full implementation.
    function parseMaterials(v)   { return MaterialUtils.parseMaterials(v) }
    function stringifyMaterials(v) { return MaterialUtils.stringifyMaterials(v) }

    // References injected by EditorWindow.qml via Loader.
    property var examListModel: null
    property var editorWindow: null

    // Debounce timer for notifying the editor window of edits.
    Timer {
        id: editTimer
        interval: 300
        repeat: false
        onTriggered: {
            if (!root._syncing && editorWindow) {
                editorWindow.onFieldEdited()
            }
        }
    }

    function notifyEdit() {
        if (_syncing) return
        editTimer.restart()
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

    function updateEndValidation() {
        if (currentExamIndex < 0 || currentExamIndex >= examListModel.count) {
            endBeforeStart = false
            return
        }
        var s = parseDateTime(startTimeEdit.text)
        var e = parseDateTime(endTimeEdit.text)
        var sOk = !isNaN(s.getTime())
        var eOk = !isNaN(e.getTime())
        endBeforeStart = sOk && eOk && e < s
    }

    function loadMaterials() {
        _syncing = true
        materialsModel.clear()
        if (currentExamIndex >= 0 && currentExamIndex < examListModel.count) {
            var arr = parseMaterials(examListModel.get(currentExamIndex).materials)
            for (var i = 0; i < arr.length; i++) {
                materialsModel.append({
                    name: arr[i].name || "",
                    quantity: arr[i].quantity !== undefined ? arr[i].quantity : 1,
                    unit: arr[i].unit || "份"
                })
            }
        }
        _syncing = false
    }

    function syncMaterialsToExam() {
        if (currentExamIndex < 0 || currentExamIndex >= examListModel.count) return
        var arr = []
        for (var i = 0; i < materialsModel.count; i++) {
            var m = materialsModel.get(i)
            arr.push({ name: m.name, quantity: m.quantity, unit: m.unit })
        }
        _syncing = true
        examListModel.setProperty(currentExamIndex, "materials", stringifyMaterials(arr))
        _syncing = false
        notifyEdit()
    }

    function addMaterial() {
        materialsModel.append({ name: "", quantity: 1, unit: "份" })
        syncMaterialsToExam()
    }

    function duplicateMaterial(index) {
        if (index < 0 || index >= materialsModel.count) return
        var m = materialsModel.get(index)
        materialsModel.insert(index + 1, { name: m.name, quantity: m.quantity, unit: m.unit })
        syncMaterialsToExam()
    }

    function removeMaterial(index) {
        if (index < 0 || index >= materialsModel.count) return
        materialsModel.remove(index)
        syncMaterialsToExam()
    }

    function clearAllMaterials() {
        materialsModel.clear()
        syncMaterialsToExam()
    }

    function requestRemoveMaterial(index) {
        if (index < 0 || index >= materialsModel.count) return
        pendingMaterialIndex = index
        pendingMaterialClear = false
        materialDeleteDialog.open()
    }

    function requestClearMaterials() {
        if (materialsModel.count === 0) return
        pendingMaterialIndex = -1
        pendingMaterialClear = true
        materialDeleteDialog.open()
    }

    function confirmMaterialDeletion() {
        if (pendingMaterialClear) {
            clearAllMaterials()
        } else {
            removeMaterial(pendingMaterialIndex)
        }
        pendingMaterialIndex = -1
        pendingMaterialClear = false
    }

    onCurrentExamIndexChanged: {
        _syncing = true
        loadMaterials()
        updateEndValidation()
        _syncing = false
    }

    // ── 考试名称 ──
    ColumnLayout {
        spacing: Theme.spacing8
        Layout.fillWidth: true

        Text {
            text: "* 考试名称"
            color: Theme.foreground
            font.pixelSize: Theme.typeSubhead
            font.weight: Theme.weightMedium
            font.family: Theme.fontSans
            Layout.fillWidth: true
        }

        PinguoTextField {
            id: examNameField
            Layout.fillWidth: true
            placeholderText: "请输入考试名称"
            inputItem.selectByMouse: true
            text: root.currentExamIndex >= 0 && root.currentExamIndex < examListModel.count
                  ? examListModel.get(root.currentExamIndex).name
                  : ""
            onTextChanged: {
                if (_syncing) return
                if (root.currentExamIndex >= 0 && root.currentExamIndex < examListModel.count) {
                    examListModel.setProperty(root.currentExamIndex, "name", text)
                    root.notifyEdit()
                }
            }
        }
    }

    // ── 开始时间 ──
    ColumnLayout {
        spacing: Theme.spacing8
        Layout.fillWidth: true

        Text {
            text: "* 开始时间"
            color: Theme.foreground
            font.pixelSize: Theme.typeSubhead
            font.weight: Theme.weightMedium
            font.family: Theme.fontSans
            Layout.fillWidth: true
        }

        RowLayout {
            spacing: Theme.spacing8
            Layout.fillWidth: true

            PinguoTextField {
                id: startTimeEdit
                placeholderText: "yyyy-MM-dd HH:mm:ss"
                inputItem.inputMask: "0000-00-00 00:00:00"
                inputItem.selectByMouse: true
                Layout.fillWidth: true
                text: root.currentExamIndex >= 0 && root.currentExamIndex < examListModel.count
                      ? examListModel.get(root.currentExamIndex).start
                      : ""
                onTextChanged: {
                    if (_syncing) return
                    if (root.currentExamIndex >= 0 && root.currentExamIndex < examListModel.count) {
                        examListModel.setProperty(root.currentExamIndex, "start", text)
                        root.updateEndValidation()
                        root.notifyEdit()
                    }
                }
            }

            PinguoButton {
                variant: PinguoButton.Primary
                icon: "clock"
                Layout.alignment: Qt.AlignVCenter
                onClicked: startCalendar.open()
            }

            CalendarPicker {
                id: startCalendar
                x: {
                    var target = editorWindow ? editorWindow.contentItem : null
                    if (!target) return 0
                    var pt = startTimeEdit.mapToItem(target, 0, 0)
                    return Math.min(pt.x, target.width - implicitWidth - Theme.spacing16)
                }
                y: {
                    var target = editorWindow ? editorWindow.contentItem : null
                    if (!target) return 0
                    var mappedY = startTimeEdit.mapToItem(target, 0, startTimeEdit.height).y + Theme.spacing8
                    var maxY = target.height - implicitHeight - Theme.spacing16
                    return Math.min(mappedY, Math.max(Theme.spacing8, maxY))
                }
                currentText: startTimeEdit.text
                onDateSelected: function(dateText) { startTimeEdit.text = dateText }
            }
        }
    }

    // ── 结束时间 ──
    ColumnLayout {
        spacing: Theme.spacing8
        Layout.fillWidth: true

        Text {
            text: "* 结束时间"
            color: Theme.foreground
            font.pixelSize: Theme.typeSubhead
            font.weight: Theme.weightMedium
            font.family: Theme.fontSans
            Layout.fillWidth: true
        }

        RowLayout {
            spacing: Theme.spacing8
            Layout.fillWidth: true

            PinguoTextField {
                id: endTimeEdit
                placeholderText: "yyyy-MM-dd HH:mm:ss"
                inputItem.inputMask: "0000-00-00 00:00:00"
                inputItem.selectByMouse: true
                Layout.fillWidth: true
                errorState: root.endBeforeStart
                text: root.currentExamIndex >= 0 && root.currentExamIndex < examListModel.count
                      ? examListModel.get(root.currentExamIndex).end
                      : ""
                onTextChanged: {
                    if (_syncing) return
                    if (root.currentExamIndex >= 0 && root.currentExamIndex < examListModel.count) {
                        examListModel.setProperty(root.currentExamIndex, "end", text)
                        root.updateEndValidation()
                        root.notifyEdit()
                    }
                }
            }

            PinguoButton {
                variant: PinguoButton.Primary
                icon: "clock"
                Layout.alignment: Qt.AlignVCenter
                onClicked: endCalendar.open()
            }

            CalendarPicker {
                id: endCalendar
                x: {
                    var target = editorWindow ? editorWindow.contentItem : null
                    if (!target) return 0
                    var pt = endTimeEdit.mapToItem(target, 0, 0)
                    return Math.min(pt.x, target.width - implicitWidth - Theme.spacing16)
                }
                y: {
                    var target = editorWindow ? editorWindow.contentItem : null
                    if (!target) return 0
                    var mappedY = endTimeEdit.mapToItem(target, 0, endTimeEdit.height).y + Theme.spacing8
                    var maxY = target.height - implicitHeight - Theme.spacing16
                    return Math.min(mappedY, Math.max(Theme.spacing8, maxY))
                }
                currentText: endTimeEdit.text
                onDateSelected: endTimeEdit.text = dateText
            }
        }
    }

    // ── 考试结束提醒时间 ──
    ColumnLayout {
        spacing: Theme.spacing8
        Layout.fillWidth: true

        Text {
            text: "* 考试结束提醒时间"
            color: Theme.foreground
            font.pixelSize: Theme.typeSubhead
            font.weight: Theme.weightMedium
            font.family: Theme.fontSans
            Layout.fillWidth: true
        }

        RowLayout {
            spacing: Theme.spacing8
            Layout.fillWidth: true

            PinguoSpinBox {
                id: alertTimeSpinBox
                Layout.preferredWidth: 140
                value: root.currentExamIndex >= 0 && root.currentExamIndex < examListModel.count
                       ? examListModel.get(root.currentExamIndex).alertTime
                       : 15
                from: 0
                to: 120
                onValueModified: {
                    if (root._syncing) return
                    if (root.currentExamIndex >= 0 && root.currentExamIndex < examListModel.count) {
                        examListModel.setProperty(root.currentExamIndex, "alertTime", value)
                        root.notifyEdit()
                    }
                }
            }

            Text {
                text: "分钟（结束前提醒）"
                color: Theme.mutedForeground
                font.pixelSize: Theme.typeCaption1
                font.family: Theme.fontSans
                Layout.alignment: Qt.AlignVCenter
                Layout.leftMargin: Theme.spacing4
            }

            Item { Layout.fillWidth: true }
        }
    }

    // ── End-time validation hint ──
    RowLayout {
        visible: endBeforeStart
        spacing: Theme.spacing12
        Layout.fillWidth: true

        Icon {
            name: "exclamationmark.triangle"
            size: 16
            tier: Icon.Danger
            Layout.alignment: Qt.AlignVCenter
        }

        Text {
            text: "结束时间不能早于开始时间"
            color: Theme.destructive
            font.pixelSize: Theme.typeCaption1
            font.family: Theme.fontSans
            Layout.alignment: Qt.AlignVCenter
        }
    }

    // ── 考试材料 ──
    ColumnLayout {
        spacing: Theme.spacing12
        Layout.fillWidth: true

        // Collapsible "考试材料" panel
        Material {
            id: materialPanel
            tier: Material.Elevated
            radius: Theme.radiusMedium
            Layout.fillWidth: true
            implicitHeight: panelLayout.implicitHeight + Theme.spacing16 * 2

            ColumnLayout {
                id: panelLayout
                anchors.fill: parent
                anchors.margins: Theme.spacing16
                spacing: Theme.spacing12

                // Panel header
                RowLayout {
                    id: headerRow
                    Layout.fillWidth: true
                    spacing: Theme.spacing12

                    Text {
                        text: "考试材料"
                        color: Theme.foreground
                        font.pixelSize: Theme.typeSubhead
                        font.weight: Theme.weightSemibold
                        font.family: Theme.fontSans
                    }

                    Item { Layout.fillWidth: true }

                    IconButton {
                        Layout.alignment: Qt.AlignVCenter
                        icon: "checkmark.circle"
                        iconSize: 16
                        accessibleName: "验证配置"
                        onClicked: editorWindow.validateConfigWithDetails(editorWindow.buildConfigJson())
                    }

                    IconButton {
                        Layout.alignment: Qt.AlignVCenter
                        icon: "arrow.right"
                        iconSize: 16
                        accessibleName: root.materialsExpanded ? "折叠材料清单" : "展开材料清单"
                        onClicked: root.materialsExpanded = !root.materialsExpanded
                    }

                    IconButton {
                        Layout.alignment: Qt.AlignVCenter
                        icon: "xmark"
                        iconSize: 16
                        danger: true
                        enabled: materialsModel.count > 0
                        accessibleName: "清空全部材料"
                        accessibleDescription: "需要确认后才会删除所有材料"
                        onClicked: root.requestClearMaterials()
                    }
                }

                // Panel content
                ColumnLayout {
                    id: contentLayout
                    Layout.fillWidth: true
                    visible: root.materialsExpanded
                    spacing: Theme.spacing12

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacing12

                        Text {
                            text: "考试中将会用到的材料"
                            color: Theme.mutedForeground
                            font.pixelSize: Theme.typeCaption1
                            font.family: Theme.fontSans
                            Layout.fillWidth: true
                        }

                        PinguoButton {
                            variant: PinguoButton.Secondary
                            text: "添加材料"
                            onClicked: root.addMaterial()
                        }
                    }

                    ListView {
                        id: materialsList
                        Layout.fillWidth: true
                        Layout.preferredHeight: materialsModel.count === 0
                                                   ? 0
                                                   : Math.min(240, materialsModel.count * (Theme.sizeListItemXlarge + Theme.spacing8))
                        visible: materialsModel.count > 0
                        model: ListModel { id: materialsModel }
                        spacing: Theme.spacing8
                        clip: true

                        delegate: Material {
                            tier: Material.Elevated
                            radius: Theme.radiusMedium
                            width: ListView.view.width
                            height: Theme.sizeListItemXlarge

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Theme.spacing12
                                anchors.rightMargin: Theme.spacing8
                                anchors.topMargin: Theme.spacing4
                                anchors.bottomMargin: Theme.spacing4
                                spacing: Theme.spacing8

                                PinguoTextField {
                                    text: name
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 100
                                    small: true
                                    inputItem.selectByMouse: true
                                    placeholderText: "材料名称"
                                    onTextChanged: {
                                        if (root._syncing) return
                                        materialsModel.setProperty(index, "name", text)
                                        root.syncMaterialsToExam()
                                    }
                                }

                                PinguoSpinBox {
                                    value: quantity
                                    from: 0
                                    to: 999
                                    Layout.preferredWidth: 160
                                    Layout.alignment: Qt.AlignVCenter
                                    onValueModified: {
                                        if (root._syncing) return
                                        materialsModel.setProperty(index, "quantity", value)
                                        root.syncMaterialsToExam()
                                    }
                                }

                                PinguoTextField {
                                    text: unit
                                    Layout.preferredWidth: 64
                                    small: true
                                    inputItem.selectByMouse: true
                                    placeholderText: "单位"
                                    onTextChanged: {
                                        if (root._syncing) return
                                        materialsModel.setProperty(index, "unit", text)
                                        root.syncMaterialsToExam()
                                    }
                                }

                                IconButton {
                                    Layout.alignment: Qt.AlignVCenter
                                    icon: "doc"
                                    iconSize: 16
                                    size: Theme.minHitTarget
                                    accessibleName: "复制材料"
                                    onClicked: root.duplicateMaterial(index)
                                }

                                IconButton {
                                    Layout.alignment: Qt.AlignVCenter
                                    icon: "trash"
                                    iconSize: 16
                                    size: Theme.minHitTarget
                                    danger: true
                                    accessibleName: "删除材料"
                                    accessibleDescription: "需要确认后才会删除此材料"
                                    onClicked: root.requestRemoveMaterial(index)
                                }
                            }
                        }
                    }

                    // Empty state
                    ColumnLayout {
                        visible: materialsModel.count === 0
                        Layout.fillWidth: true
                        spacing: Theme.spacing8

                        Icon {
                            name: "tray"
                            size: 24
                            tier: Icon.Tertiary
                            Layout.alignment: Qt.AlignHCenter
                        }

                        Text {
                            text: "暂无材料，点击“添加材料”开始"
                            color: Theme.mutedForeground
                            font.pixelSize: Theme.typeCaption1
                            font.family: Theme.fontSans
                            Layout.alignment: Qt.AlignHCenter
                        }
                    }
                }
            }
        }

        ConfirmDialog {
            id: materialDeleteDialog
            titleText: root.pendingMaterialClear ? "清空全部材料" : "删除材料"
            messageText: root.pendingMaterialClear
                         ? "确定要删除全部考试材料吗？此操作可通过编辑器的撤销功能恢复。"
                         : "确定要删除此材料吗？此操作可通过编辑器的撤销功能恢复。"

            footer: RowLayout {
                spacing: Theme.spacing12
                Layout.margins: Theme.spacing16

                Item { Layout.fillWidth: true }

                PinguoButton {
                    text: "取消"
                    variant: PinguoButton.Text
                    onClicked: materialDeleteDialog.close()
                }
                PinguoButton {
                    text: root.pendingMaterialClear ? "清空全部" : "删除材料"
                    variant: PinguoButton.Destructive
                    onClicked: {
                        root.confirmMaterialDeletion()
                        materialDeleteDialog.close()
                    }
                }
            }
        }

        // 配置验证 row
        Material {
            id: validationPanel
            tier: Material.Elevated
            radius: Theme.radiusMedium
            Layout.fillWidth: true
            implicitHeight: validationRow.implicitHeight + Theme.spacing12 * 2

            RowLayout {
                id: validationRow
                anchors.fill: parent
                anchors.leftMargin: Theme.spacing16
                anchors.rightMargin: Theme.spacing16
                spacing: Theme.spacing12

                Text {
                    text: "配置验证"
                    color: Theme.foreground
                    font.pixelSize: Theme.typeSubhead
                    font.weight: Theme.weightSemibold
                    font.family: Theme.fontSans
                    Layout.alignment: Qt.AlignVCenter
                }

                Item { Layout.fillWidth: true }

                RowLayout {
                    spacing: Theme.spacing8
                    visible: editorWindow.errorCount === 0 && editorWindow.warningCount === 0
                    Layout.alignment: Qt.AlignVCenter

                    Icon {
                        name: "checkmark.circle"
                        size: 16
                        tier: Icon.Success
                    }
                    Text {
                        text: "配置正常"
                        color: Theme.success
                        font.pixelSize: Theme.typeCaption1
                        font.family: Theme.fontSans
                    }
                }

                RowLayout {
                    spacing: Theme.spacing8
                    visible: editorWindow.errorCount > 0
                    Layout.alignment: Qt.AlignVCenter

                    Icon {
                        name: "xmark"
                        size: 16
                        tier: Icon.Danger
                    }
                    Text {
                        text: editorWindow.errorCount + " 个错误"
                        color: Theme.destructive
                        font.pixelSize: Theme.typeCaption1
                        font.family: Theme.fontSans
                    }
                }

                RowLayout {
                    spacing: Theme.spacing8
                    visible: editorWindow.errorCount === 0 && editorWindow.warningCount > 0
                    Layout.alignment: Qt.AlignVCenter

                    Icon {
                        name: "exclamationmark.triangle"
                        size: 16
                        tier: Icon.Warning
                    }
                    Text {
                        text: editorWindow.warningCount + " 个警告"
                        color: Theme.warning
                        font.pixelSize: Theme.typeCaption1
                        font.family: Theme.fontSans
                    }
                }
            }
        }
    }
}
