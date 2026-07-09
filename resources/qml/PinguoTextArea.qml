import QtQuick 2.15
import "."
import QtQuick.Controls 2.15

// =====================================================================
// PinguoTextArea — multi-line text input
// =====================================================================
// Inherits the same border/focus treatment as PinguoTextField,
// with comfortable padding and a minimum 80px height.
// =====================================================================

Item {
    id: root

    property alias text: input.text
    property alias placeholderText: input.placeholderText
    property alias inputItem: input

    

    implicitWidth: 240
    implicitHeight: Math.max(80, input.implicitHeight + Theme.spacing24)

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
        border.color: input.activeFocus ? Theme.ring : Theme.input
        opacity: root.enabled ? 1.0 : 0.55

        Behavior on border.color {
            ColorAnimation { duration: Theme.motionShort; easing.type: Theme.motionStandard }
        }

        TextArea {
            id: input
            anchors.fill: parent
            anchors.margins: Theme.spacing12
            color: Theme.foreground
            font.pixelSize: Theme.typeBody
            font.weight: Theme.weightRegular
            font.family: Theme.fontSans
            placeholderTextColor: Theme.mutedForeground
            wrapMode: TextArea.Wrap
            background: Item {}
            enabled: root.enabled
        }
    }
}