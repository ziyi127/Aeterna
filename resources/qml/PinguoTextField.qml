import QtQuick 2.15
import "."
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

// =====================================================================
// PinguoTextField — single-line text input
// =====================================================================
// 44px height (small: 40px), 10px radius, 1px border using Theme.input.
// Focus ring switches to Theme.ring. DM Sans 13/14px.
// =====================================================================

Item {
    id: root

    property alias text: input.text
    property alias placeholderText: input.placeholderText
    property alias inputItem: input
    property bool small: false
    property bool errorState: false
    property string leadingIcon: ""
    property string trailingIcon: ""

    signal trailingClicked()



    implicitWidth: 240
    implicitHeight: root.small ? 40 : 44

    // Focus ring glow — rendered behind the main background
    Rectangle {
        anchors.fill: parent
        anchors.margins: -1
        radius: Theme.radiusMedium + 1
        color: "transparent"
        border.width: 1
        border.color: Theme.ring
        opacity: input.activeFocus ? 1.0 : 0.0

        Behavior on opacity {
            NumberAnimation { duration: Theme.motionShort; easing.type: Theme.motionStandard }
        }
    }

    // Main background
    Rectangle {
        id: bg
        anchors.fill: parent
        radius: Theme.radiusMedium
        color: Theme.background
        border.width: 1
        border.color: root.errorState ? Theme.destructive
                                      : (input.activeFocus ? Theme.ring : Theme.input)
        opacity: root.enabled ? 1.0 : 0.55

        Behavior on border.color {
            ColorAnimation { duration: Theme.motionShort; easing.type: Theme.motionStandard }
        }

        RowLayout {
            id: rowLayout
            anchors.fill: parent
            anchors.leftMargin: Theme.spacing12
            anchors.rightMargin: Theme.spacing12
            spacing: Theme.spacing8

            Icon {
                visible: root.leadingIcon !== ""
                name: root.leadingIcon
                size: 16
                tier: Icon.Secondary
            }

            TextField {
                id: input
                Layout.fillWidth: true
                Layout.fillHeight: true
                verticalAlignment: TextInput.AlignVCenter
                color: Theme.foreground
                font.pixelSize: root.small ? Theme.typeFootnote : Theme.typeSubhead
                font.weight: Theme.weightRegular
                font.family: Theme.fontSans
                placeholderTextColor: Theme.mutedForeground
                background: Item {}
                enabled: root.enabled
            }

            Icon {
                id: trailingIconItem
                visible: root.trailingIcon !== ""
                name: root.trailingIcon
                size: 16
                tier: Icon.Secondary

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.trailingClicked()
                }
            }
        }
    }
}