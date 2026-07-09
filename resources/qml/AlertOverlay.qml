import QtQuick 2.15
import "."
import QtQuick.Layouts 1.15

// =====================================================================
// AlertOverlay — Full-screen colored overlay for playback alerts
// =====================================================================
// Displays a large centered title/message over a translucent semantic
// background. Supports explicit show()/hide() and auto-dismiss after 5s.
//
// Public API:
//   property bool visible
//   property string kind   // "start" | "alert" | "end"
//   property string title
//   property string message
//   function show(kind, title, message)
//   function hide()
// =====================================================================

Rectangle {
    id: root

    anchors.fill: parent
    visible: false
    opacity: 0.0
    z: 1000

    property string kind: "alert"
    property string title: ""
    property string message: ""

    

    color: {
        switch (root.kind) {
        case "start": return Qt.alpha(Theme.success, 0.3)
        case "alert": return Qt.alpha(Theme.warning, 0.3)
        case "end":   return Qt.alpha(Theme.destructive, 0.3)
        default:      return Qt.alpha(Theme.mutedForeground, 0.3)
        }
    }

    Behavior on opacity {
        NumberAnimation {
            duration: Theme.motionMedium
            easing.type: Theme.motionDecelerate
        }
    }

    Behavior on color {
        ColorAnimation {
            duration: Theme.motionShort
            easing.type: Theme.motionStandard
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.visible && root.opacity > 0
        onClicked: root.hide()
    }

    ColumnLayout {
        anchors.centerIn: parent
        spacing: Theme.spacing16

        Icon {
            size: 24
            tier: root.kind === "start" ? Icon.Success :
                  root.kind === "end"   ? Icon.Danger : Icon.Warning
            name: root.kind === "start" ? "checkmark.circle" :
                  root.kind === "end"   ? "xmark" : "exclamationmark.triangle"
            accessibleName: root.title
            Layout.alignment: Qt.AlignHCenter
        }

        Text {
            text: root.title
            color: Theme.foreground
            font.pixelSize: Theme.typeLargeTitle
            font.weight: Theme.weightBold
            font.family: Theme.fontSans
            horizontalAlignment: Text.AlignHCenter
            Layout.alignment: Qt.AlignHCenter
        }

        Text {
            text: root.message
            color: Theme.foreground
            font.pixelSize: Theme.typeTitle3
            font.family: Theme.fontSans
            horizontalAlignment: Text.AlignHCenter
            Layout.alignment: Qt.AlignHCenter
        }
    }

    Timer {
        id: autoHideTimer
        interval: 5000
        repeat: false
        onTriggered: root.hide()
    }

    Timer {
        id: hideTimer
        interval: Theme.motionLong
        repeat: false
        property int targetId: 0
        onTriggered: {
            if (targetId === root.__hideId) {
                root.visible = false
            }
        }
    }

    property int __alertId: 0
    property int __hideId: 0

    function show(kind, title, message) {
        root.__alertId++
        root.kind = kind
        root.title = title !== undefined ? title : ""
        root.message = message !== undefined ? message : ""
        root.visible = true
        root.opacity = 1.0
        autoHideTimer.restart()
    }

    function hide() {
        root.__alertId++
        root.__hideId++
        root.opacity = 0.0
        hideTimer.targetId = root.__hideId
        hideTimer.restart()
    }
}
