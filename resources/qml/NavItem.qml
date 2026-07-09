import QtQuick 2.15
import "."
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

// =====================================================================
// NavItem — Pinguo sidebar navigation row
// =====================================================================
// A single row with an icon and label, styled for selected/hover states
// using Pinguo sidebar semantic tokens.
// =====================================================================

Item {
    id: root

    property string text: ""
    property string icon: ""
    property bool selected: false
    signal clicked()

    

    height: Theme.minHitTarget
    width: parent ? parent.width : implicitWidth
    implicitWidth: rowLayout.implicitWidth + Theme.marginStandard * 2

    Rectangle {
        id: background
        anchors.fill: parent
        radius: Theme.radiusMedium
        color: root.selected
            ? Theme.sidebarAccent
            : (navMouse.containsMouse ? Qt.alpha(Theme.sidebarForeground, 0.06) : Qt.alpha(Theme.sidebarForeground, 0))
        border.width: 0

        Behavior on color {
            ColorAnimation { duration: Theme.motionShort; easing.type: Theme.motionStandard }
        }
    }

    RowLayout {
        id: rowLayout
        anchors.fill: parent
        anchors.leftMargin: Theme.marginStandard
        anchors.rightMargin: Theme.marginStandard
        spacing: Theme.spacing12

        Icon {
            name: root.icon
            size: 20
            tier: root.selected ? Icon.Accent : Icon.Primary
        }

        Text {
            text: root.text
            color: root.selected ? Theme.sidebarPrimary : Theme.sidebarForeground
            font.pixelSize: Theme.typeBody
            font.weight: root.selected ? Theme.weightSemibold : Theme.weightRegular
            font.family: Theme.fontSans
            elide: Text.ElideRight
            Layout.fillWidth: true
        }
    }

    MouseArea {
        id: navMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
