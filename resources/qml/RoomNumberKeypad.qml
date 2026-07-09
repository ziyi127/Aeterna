import QtQuick 2.15
import "."
import QtQuick.Layouts 1.15

// =====================================================================
// RoomNumberKeypad — Numeric keypad dialog for entering a room number
// =====================================================================
// A 3-column keypad with a 6-digit display, clear/backspace helpers,
// and confirm/cancel action buttons.
//
// Public API:
//   property bool visible
//   property string currentNumber
//   signal confirmed(string number)
//   signal canceled()
// =====================================================================

Item {
    id: root

    width: 320
    height: contentColumn.implicitHeight + Theme.spacing24 * 2
    visible: false

    property string currentNumber: ""
    property string title: "输入考场号"

    signal confirmed(string number)
    signal canceled()

    

    Material {
        anchors.fill: parent
        tier: Material.Overlay
        radius: Theme.radiusLarge
    }

    ColumnLayout {
        id: contentColumn
        anchors.fill: parent
        anchors.margins: Theme.spacing24
        spacing: Theme.spacing16

        Text {
            text: root.title
            color: Theme.foreground
            font.pixelSize: Theme.typeBody
            font.weight: Theme.weightBold
            font.family: Theme.fontSans
            Layout.alignment: Qt.AlignHCenter
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 56
            color: Theme.accent
            radius: Theme.radiusMedium
            border.width: 1
            border.color: Theme.hairline

            Text {
                id: numberDisplay
                anchors.fill: parent
                anchors.margins: Theme.spacing12
                text: root.currentNumber
                color: Theme.foreground
                font.pixelSize: Theme.typeTitle1
                font.family: Theme.fontSans
                font.weight: Theme.weightBold
                font.letterSpacing: Theme.trackingTight * 28
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }

        GridLayout {
            id: digitGrid
            columns: 3
            rowSpacing: Theme.spacing8
            columnSpacing: Theme.spacing8
            Layout.fillWidth: true

            Repeater {
                model: [
                    { label: "1", value: "1" },
                    { label: "2", value: "2" },
                    { label: "3", value: "3" },
                    { label: "4", value: "4" },
                    { label: "5", value: "5" },
                    { label: "6", value: "6" },
                    { label: "7", value: "7" },
                    { label: "8", value: "8" },
                    { label: "9", value: "9" },
                    { label: "清空", value: "clear" },
                    { label: "0", value: "0" },
                    { label: "退格", value: "backspace" }
                ]

                delegate: PinguoButton {
                    Layout.fillWidth: true
                    text: modelData.label
                    variant: PinguoButton.Secondary
                    onClicked: {
                        if (modelData.value === "clear") {
                            root.currentNumber = ""
                        } else if (modelData.value === "backspace") {
                            if (root.currentNumber.length > 0) {
                                root.currentNumber = root.currentNumber.slice(0, -1)
                            }
                        } else {
                            if (root.currentNumber.length < 6) {
                                root.currentNumber += modelData.value
                            }
                        }
                    }
                }
            }
        }

        RowLayout {
            spacing: Theme.spacing8
            Layout.fillWidth: true

            PinguoButton {
                Layout.fillWidth: true
                Layout.preferredHeight: Theme.sizeButtonLarge
                Layout.alignment: Qt.AlignVCenter
                text: "取消"
                variant: PinguoButton.Secondary
                onClicked: {
                    root.canceled()
                    root.visible = false
                }
            }

            PinguoButton {
                Layout.fillWidth: true
                Layout.preferredHeight: Theme.sizeButtonLarge
                Layout.alignment: Qt.AlignVCenter
                text: "确认"
                variant: PinguoButton.Hero
                onClicked: {
                    root.confirmed(root.currentNumber)
                    root.visible = false
                }
            }
        }
    }
}
