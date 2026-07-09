import QtQuick 2.15
import "."
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

ColumnLayout {
    id: root
    spacing: Theme.spacing16

    

    property int currentExamIndex: -1
    property bool _syncing: false
    property var unitOptions: ["张", "份", "本", "卷", "套"]

    // QML ListModel converts JS arrays into ListModel objects, so the exam
    // list stores materials as a JSON string.
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

    function reloadMaterials() {
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

    function syncToExam() {
        if (currentExamIndex < 0 || currentExamIndex >= examListModel.count) return
        var arr = []
        for (var i = 0; i < materialsModel.count; i++) {
            var m = materialsModel.get(i)
            arr.push({
                name: m.name,
                quantity: m.quantity,
                unit: m.unit
            })
        }
        _syncing = true
        examListModel.setProperty(currentExamIndex, "materials", stringifyMaterials(arr))
        _syncing = false
        editorWindow.onFieldEdited()
    }

    function addMaterial() {
        materialsModel.append({name: "", quantity: 1, unit: "份"})
        syncToExam()
    }

    function duplicateMaterial(index) {
        if (index < 0 || index >= materialsModel.count) return
        var m = materialsModel.get(index)
        materialsModel.insert(index + 1, {
            name: m.name,
            quantity: m.quantity,
            unit: m.unit
        })
        syncToExam()
    }

    function promptDeleteMaterial(index) {
        if (index < 0 || index >= materialsModel.count) return
        materialsList.currentIndex = index
        deleteMaterialDialog.open()
    }

    function confirmDeleteMaterial() {
        var idx = materialsList.currentIndex
        if (idx < 0 || idx >= materialsModel.count) return
        materialsModel.remove(idx)
        syncToExam()
    }

    onCurrentExamIndexChanged: reloadMaterials()

    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.spacing12

        Text {
            text: "材料清单"
            color: Theme.foreground
            font.pixelSize: Theme.typeSubhead
            font.weight: Theme.weightSemibold
            font.family: Theme.fontSans
            Layout.fillWidth: true
        }

        Item { Layout.fillWidth: true }

        PinguoButton {
            variant: PinguoButton.Secondary
            text: "添加材料"
            onClicked: addMaterial()
        }

    }

    ListView {
        id: materialsList
        Layout.fillWidth: true
        Layout.fillHeight: true
        model: ListModel { id: materialsModel }
        spacing: Theme.spacing12
        clip: true

        delegate: Material {
            tier: Material.Elevated
            radius: Theme.radiusMedium
            width: ListView.view.width
            height: Theme.sizeListItemXlarge

            RowLayout {
                anchors.fill: parent
                anchors.margins: Theme.spacing12
                spacing: Theme.spacing12

                Text {
                    text: "名称"
                    color: Theme.mutedForeground
                    font.pixelSize: Theme.typeCaption1
                    font.family: Theme.fontSans
                    Layout.alignment: Qt.AlignVCenter
                }
                PinguoTextField {
                    text: name
                    Layout.fillWidth: true
                    Layout.preferredWidth: 160
                    inputItem.selectByMouse: true
                    placeholderText: "材料名称"
                    onTextChanged: {
                        if (root._syncing) return
                        materialsModel.setProperty(index, "name", text)
                        syncToExam()
                    }
                }

                Text {
                    text: "数量"
                    color: Theme.mutedForeground
                    font.pixelSize: Theme.typeCaption1
                    font.family: Theme.fontSans
                    Layout.alignment: Qt.AlignVCenter
                }
                PinguoSpinBox {
                    value: quantity
                    from: 1
                    to: 999
                    Layout.preferredWidth: 140
                    onValueChanged: {
                        if (root._syncing) return
                        materialsModel.setProperty(index, "quantity", value)
                        syncToExam()
                    }
                }

                Text {
                    text: "单位"
                    color: Theme.mutedForeground
                    font.pixelSize: Theme.typeCaption1
                    font.family: Theme.fontSans
                    Layout.alignment: Qt.AlignVCenter
                }
                PinguoComboBox {
                    model: root.unitOptions
                    currentText: unit
                    Layout.preferredWidth: 120
                    onActivated: {
                        if (root._syncing) return
                        materialsModel.setProperty(index, "unit", currentText)
                        syncToExam()
                    }
                }

                Icon {
                    name: "doc"
                    size: 20
                    tier: Icon.Secondary
                    accessibleName: "复制材料"
                    Layout.alignment: Qt.AlignVCenter
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: duplicateMaterial(index)
                    }
                }

                Icon {
                    name: "minus"
                    size: 20
                    tier: Icon.Danger
                    accessibleName: "删除材料"
                    Layout.alignment: Qt.AlignVCenter
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: promptDeleteMaterial(index)
                    }
                }
            }
        }
    }

    Text {
        Layout.fillWidth: true
        text: "材料清单是可选的，用于在播放器上显示需要分发的材料信息。"
        color: Theme.mutedForeground
        font.pixelSize: Theme.typeCaption1
        font.family: Theme.fontSans
        wrapMode: Text.WordWrap
    }

    Dialog {
        id: deleteMaterialDialog
        modal: true
        anchors.centerIn: parent
        closePolicy: Popup.CloseOnEscape
        standardButtons: Dialog.NoButton

        background: Rectangle {
            color: Theme.materialOverlay
            radius: Theme.radiusLarge
            border.color: Theme.hairline
            border.width: 1
        }

        enter: Transition {
            NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: Theme.motionMedium; easing.type: Theme.motionDecelerate }
        }
        exit: Transition {
            NumberAnimation { property: "opacity"; from: 1.0; to: 0.0; duration: Theme.motionShort; easing.type: Theme.motionAccelerate }
        }

        contentItem: ColumnLayout {
            spacing: Theme.spacing16
            Layout.preferredWidth: 300

            Text {
                text: "删除材料"
                font.pixelSize: Theme.typeHeadline
                font.weight: Theme.weightBold
                color: Theme.foreground
                font.family: Theme.fontSans
            }

            Text {
                text: "确定要删除当前材料吗？此操作无法撤销。"
                color: Theme.mutedForeground
                font.pixelSize: Theme.typeBody
                font.family: Theme.fontSans
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
        }

        footer: RowLayout {
            spacing: Theme.spacing12
            Layout.margins: Theme.spacing16

            Item { Layout.fillWidth: true }

            PinguoButton {
                variant: PinguoButton.Secondary
                text: "取消"
                onClicked: deleteMaterialDialog.reject()
            }
            PinguoButton {
                variant: PinguoButton.Primary
                text: "删除"
                onClicked: {
                    confirmDeleteMaterial()
                    deleteMaterialDialog.accept()
                }
            }
        }
    }
}
