import QtQuick 2.15
import "."
import QtQuick.Layouts 1.15

// =====================================================================
// ToolbarButton — Small toolbar control with icon + label
// =====================================================================
// HIG-compliant 64x44 tappable control. Supports normal, checked, and
// danger presentations, plus long-press activation.
//
// Public API:
//   property string icon
//   property string label
//   property bool checked
//   property bool danger
//   signal clicked()
//   signal pressAndHold()
// =====================================================================

Item {
    id: root

    width: Theme.sizeToolbarButtonWidth
    height: Theme.sizeToolbarButtonHeight

    property string icon: ""
    property string label: ""
    property bool checked: false
    property bool danger: false
    activeFocusOnTab: true

    signal clicked()
    signal pressAndHold()

    

    Rectangle {
        id: background
        anchors.fill: parent
        radius: Theme.radiusMedium
        color: {
            if (root.checked) {
                return Qt.alpha(Theme.primary, 0.18)
            }
            if (root.danger) {
                return mouse.containsMouse
                    ? Qt.alpha(Theme.destructive, 0.12)
                    : Qt.alpha(Theme.foreground, 0)
            }
            return mouse.containsMouse
                ? Qt.alpha(Theme.foreground, 0.08)
                : Qt.alpha(Theme.foreground, 0)
        }

        Behavior on color {
            ColorAnimation {
                duration: Theme.motionShort
                easing.type: Theme.motionStandard
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: -2
        radius: Theme.radiusMedium + 2
        color: "transparent"
        border.width: 2
        border.color: Theme.ring
        visible: root.activeFocus
    }

    ColumnLayout {
        anchors.centerIn: parent
        spacing: Theme.spacing4

        Icon {
            name: root.icon
            size: 20
            tier: root.danger
                ? Icon.Danger
                : (root.checked ? Icon.Accent : Icon.Primary)
            Layout.alignment: Qt.AlignHCenter
        }

        Text {
            text: root.label
            color: root.danger
                ? Theme.destructive
                : (root.checked ? Theme.primary : Theme.foreground)
            font.pixelSize: Theme.typeCaption2
            font.family: Theme.fontSans
            Layout.alignment: Qt.AlignHCenter
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            root.forceActiveFocus()
            root.clicked()
        }
        onPressAndHold: root.pressAndHold()
    }

    Keys.onPressed: {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            root.clicked()
            event.accepted = true
        }
    }
}
