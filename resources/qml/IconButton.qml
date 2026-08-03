import QtQuick 2.15
import "."

// Accessible icon-only action with a predictable hit target and focus treatment.
Item {
    id: root

    property string icon: ""
    property string accessibleName: icon
    property string accessibleDescription: ""
    property int size: Theme.minHitTarget
    property int iconSize: size >= Theme.minHitTarget ? 20 : 16
    property bool danger: false
    property bool checked: false

    signal clicked()

    implicitWidth: size
    implicitHeight: size
    width: implicitWidth
    height: implicitHeight
    activeFocusOnTab: true
    opacity: enabled ? 1.0 : 0.42

    Accessible.role: Accessible.Button
    Accessible.name: root.accessibleName
    Accessible.description: root.accessibleDescription
    Accessible.onPressAction: {
        if (root.enabled)
            root.clicked()
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusMedium
        color: {
            if (root.checked)
                return Theme.iconButtonChecked
            if (mouse.containsMouse)
                return root.danger ? Theme.iconButtonDangerHover : Theme.iconButtonHover
            return "transparent"
        }

        Behavior on color {
            ColorAnimation { duration: Theme.motionShort; easing.type: Theme.motionStandard }
        }
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: -2
        radius: Theme.radiusMedium + 2
        color: "transparent"
        border.width: 2
        border.color: Theme.focusRing
        visible: root.activeFocus
    }

    Icon {
        anchors.centerIn: parent
        name: root.icon
        size: root.iconSize
        tier: root.danger ? Icon.Danger : (root.checked ? Icon.Accent : Icon.Primary)
        Accessible.ignored: true
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: root.enabled
        cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: {
            root.forceActiveFocus()
            if (root.enabled)
                root.clicked()
        }
    }

    Keys.onPressed: {
        if (root.enabled && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space)) {
            root.clicked()
            event.accepted = true
        }
    }
}
