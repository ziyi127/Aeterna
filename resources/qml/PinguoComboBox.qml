import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "."

// =====================================================================
// PinguoComboBox — Pinguo-styled popup selector
// =====================================================================
// PinguoButton that opens a themed popup menu with options.
// Uses theme tokens for all styling, pill-shaped, DM Sans.
// =====================================================================

Item {
    id: root

    property var model: []
    property string currentText: ""
    property int currentIndex: -1

    activeFocusOnTab: true

    signal activated(string text)

    implicitWidth: Math.max(140, displayLayout.implicitWidth + Theme.spacing32)
    implicitHeight: Theme.sizeButtonMedium

    // ── Display button ──
    Rectangle {
        id: displayBg
        anchors.fill: parent
        radius: Theme.radiusPill
        color: root.enabled && btnMouse.containsMouse ? Theme.muted : Theme.secondary
        border.width: 1
        border.color: root.activeFocus ? Theme.ring : Theme.hairline

        Behavior on color {
            ColorAnimation { duration: Theme.motionShort; easing.type: Theme.motionStandard }
        }
        Behavior on border.color {
            ColorAnimation { duration: Theme.motionShort; easing.type: Theme.motionStandard }
        }
    }

    RowLayout {
        id: displayLayout
        anchors.fill: parent
        anchors.leftMargin: Theme.spacing16
        anchors.rightMargin: Theme.spacing8

        Text {
            Layout.fillWidth: true
            text: root.currentText || "请选择"
            color: root.currentText ? Theme.foreground : Theme.mutedForeground
            font.pixelSize: Theme.typeSubhead
            font.family: Theme.fontSans
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }

        Icon {
            name: "arrow.down.circle"
            size: 12
            tier: Icon.Secondary
            Layout.alignment: Qt.AlignVCenter
        }
    }

    MouseArea {
        id: btnMouse
        anchors.fill: parent
        hoverEnabled: root.enabled
        cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: {
            if (root.enabled) comboPopup.open()
        }
    }

    // ── Popup menu ──
    Popup {
        id: comboPopup
        y: parent.height + Theme.spacing4
        width: Math.max(parent.width, 200)
        padding: Theme.spacing4
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        background: Rectangle {
            color: Theme.materialOverlay
            radius: Theme.radiusLarge
            border.color: Theme.hairline
            border.width: 1
        }

        enter: Transition {
            NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: Theme.motionShort; easing.type: Theme.motionDecelerate }
        }
        exit: Transition {
            NumberAnimation { property: "opacity"; from: 1.0; to: 0.0; duration: Theme.motionShort; easing.type: Theme.motionAccelerate }
        }

        ListView {
            implicitHeight: Math.min(contentHeight, 300)
            model: root.model
            clip: true
            spacing: Theme.spacing4

            delegate: Item {
                width: ListView.view.width
                height: Theme.sizeListItemMedium

                Rectangle {
                    anchors.fill: parent
                    radius: Theme.radiusMedium
                    color: itemMouse.containsMouse ? Qt.alpha(Theme.primary, 0.08) : "transparent"
                    Behavior on color {
                        ColorAnimation { duration: Theme.motionShort; easing.type: Theme.motionStandard }
                    }
                }

                Text {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.spacing12
                    anchors.rightMargin: Theme.spacing12
                    text: modelData
                    color: modelData === root.currentText ? Theme.primary : Theme.foreground
                    font.pixelSize: Theme.typeSubhead
                    font.family: Theme.fontSans
                    font.weight: modelData === root.currentText ? Theme.weightSemibold : Theme.weightRegular
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                }

                MouseArea {
                    id: itemMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.currentText = modelData
                        root.currentIndex = index
                        root.activated(modelData)
                        comboPopup.close()
                    }
                }
            }
        }
    }

    Keys.onPressed: {
        if (root.enabled && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space)) {
            comboPopup.open()
        }
    }
}