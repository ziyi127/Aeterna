import QtQuick 2.15
import "."
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

ColumnLayout {
    id: root
    spacing: Theme.spacing16

    

    property int currentExamIndex: -1
    property bool endBeforeStart: false
    property bool _updating: false

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

    onCurrentExamIndexChanged: {
        _updating = true
        updateEndValidation()
        _updating = false
    }

    // ── 基本信息 ──
    Material {
        tier: Material.Elevated
        radius: Theme.radiusMedium
        Layout.fillWidth: true

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.spacing16
            spacing: Theme.spacing16

            Text {
                text: "基本信息"
                color: Theme.foreground
                font.pixelSize: Theme.typeSubhead
                font.weight: Theme.weightSemibold
                font.family: Theme.fontSans
            }

        GridLayout {
            columns: 2
            rowSpacing: Theme.spacing16
            columnSpacing: Theme.spacing24
            Layout.fillWidth: true

            Text {
                text: "考试名称:"
                color: Theme.mutedForeground
                font.pixelSize: Theme.typeSubhead
                font.weight: Theme.weightMedium
                font.family: Theme.fontSans
                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
            }
            PinguoTextField {
                id: examInfoName
                Layout.fillWidth: true
                placeholderText: "考试科目名称"
                inputItem.selectByMouse: true
                text: root.currentExamIndex >= 0 && root.currentExamIndex < examListModel.count
                      ? examListModel.get(root.currentExamIndex).name
                      : ""
                onTextChanged: {
                    if (_updating) return
                    if (root.currentExamIndex >= 0 && root.currentExamIndex < examListModel.count) {
                        examListModel.setProperty(root.currentExamIndex, "name", text)
                        editorWindow.onFieldEdited()
                    }
                }
            }

            Text {
                text: "开始时间:"
                color: Theme.mutedForeground
                font.pixelSize: Theme.typeSubhead
                font.weight: Theme.weightMedium
                font.family: Theme.fontSans
                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
            }
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
                    if (_updating) return
                    if (root.currentExamIndex >= 0 && root.currentExamIndex < examListModel.count) {
                        examListModel.setProperty(root.currentExamIndex, "start", text)
                        updateEndValidation()
                        editorWindow.onFieldEdited()
                    }
                }
            }

            Text {
                text: "结束时间:"
                color: Theme.mutedForeground
                font.pixelSize: Theme.typeSubhead
                font.weight: Theme.weightMedium
                font.family: Theme.fontSans
                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
            }
            PinguoTextField {
                id: endTimeEdit
                placeholderText: "yyyy-MM-dd HH:mm:ss"
                inputItem.inputMask: "0000-00-00 00:00:00"
                inputItem.selectByMouse: true
                errorState: root.endBeforeStart
                Layout.fillWidth: true
                text: root.currentExamIndex >= 0 && root.currentExamIndex < examListModel.count
                      ? examListModel.get(root.currentExamIndex).end
                      : ""
                onTextChanged: {
                    if (_updating) return
                    if (root.currentExamIndex >= 0 && root.currentExamIndex < examListModel.count) {
                        examListModel.setProperty(root.currentExamIndex, "end", text)
                        updateEndValidation()
                        editorWindow.onFieldEdited()
                    }
                }
            }

            Text {
                text: "提前提醒分钟数:"
                color: Theme.mutedForeground
                font.pixelSize: Theme.typeSubhead
                font.weight: Theme.weightMedium
                font.family: Theme.fontSans
                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
            }
            PinguoSpinBox {
                id: alertTimeSpin
                from: 0
                to: 60
                value: root.currentExamIndex >= 0 && root.currentExamIndex < examListModel.count
                       ? examListModel.get(root.currentExamIndex).alertTime
                       : 5
                Layout.preferredWidth: 140
                onValueChanged: {
                    if (_updating) return
                    if (root.currentExamIndex >= 0 && root.currentExamIndex < examListModel.count) {
                        examListModel.setProperty(root.currentExamIndex, "alertTime", value)
                        editorWindow.onFieldEdited()
                    }
                }
            }
            }
        }
    }

    RowLayout {
        visible: endBeforeStart
        spacing: Theme.spacing12
        Layout.leftMargin: Theme.spacing12

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

    Connections {
        target: root
        function onEndBeforeStartChanged() {
            endTimeEdit.errorState = endBeforeStart
        }
    }
}
