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
    readonly property bool requiresAcknowledgement: kind === "end" || kind === "error"
    readonly property bool canDismiss: !requiresAcknowledgement
    readonly property bool solidSurface: Theme.highContrast || Theme.reduceTransparency
    readonly property color semanticColor: {
        switch (root.kind) {
        case "start": return Theme.success
        case "end":
        case "error": return Theme.destructive
        default: return Theme.warning
        }
    }
    readonly property color contentColor: solidSurface
        ? ((kind === "start" || kind === "end" || kind === "error")
           ? (kind === "start" ? Theme.successForeground : Theme.destructiveForeground)
           : Theme.foreground)
        : Theme.foreground

    activeFocusOnTab: visible
    Accessible.role: Accessible.AlertMessage
    Accessible.name: root.title
    Accessible.description: root.message

    color: solidSurface ? semanticColor : Qt.alpha(semanticColor, 0.3)

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
        enabled: root.visible && root.opacity > 0 && root.canDismiss
        onClicked: root.hide()
    }

    ColumnLayout {
        anchors.centerIn: parent
        spacing: Theme.spacing16

        Icon {
            size: 24
            tier: root.kind === "start" ? Icon.Success :
                  (root.kind === "end" || root.kind === "error") ? Icon.Danger : Icon.Warning
            name: root.kind === "start" ? "checkmark.circle" :
                  (root.kind === "end" || root.kind === "error") ? "xmark" : "exclamationmark.triangle"
            overrideColor: root.contentColor
            accessibleName: root.title
            Layout.alignment: Qt.AlignHCenter
        }

        Text {
            text: root.title
            color: root.contentColor
            font.pixelSize: Theme.typeLargeTitle
            font.weight: Theme.weightBold
            font.family: Theme.fontSans
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            Layout.maximumWidth: Math.min(root.width - Theme.spacing48, 640)
            Layout.alignment: Qt.AlignHCenter
        }

        Text {
            text: root.message
            color: root.contentColor
            font.pixelSize: Theme.typeTitle3
            font.family: Theme.fontSans
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            Layout.maximumWidth: Math.min(root.width - Theme.spacing48, 640)
            Layout.alignment: Qt.AlignHCenter
        }

        PinguoButton {
            id: acknowledgeButton
            visible: root.requiresAcknowledgement
            text: "确认"
            variant: PinguoButton.Secondary
            accessibleDescription: "确认并关闭此重要提示"
            Layout.alignment: Qt.AlignHCenter
            onClicked: root.hide()
        }
    }

    Timer {
        id: autoHideTimer
        interval: 5000
        repeat: false
        onTriggered: {
            if (root.canDismiss)
                root.hide()
        }
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

    Keys.onPressed: function(event) {
        if (root.visible && root.canDismiss && (event.key === Qt.Key_Escape || event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space)) {
            root.hide()
            event.accepted = true
        }
    }

    function show(kind, title, message) {
        root.__alertId++
        root.kind = kind
        root.title = title !== undefined ? title : ""
        root.message = message !== undefined ? message : ""
        root.visible = true
        root.opacity = 1.0
        if (root.requiresAcknowledgement)
            acknowledgeButton.forceActiveFocus()
        else
            root.forceActiveFocus()
        if (root.canDismiss)
            autoHideTimer.restart()
        else
            autoHideTimer.stop()
    }

    function hide() {
        root.__alertId++
        root.__hideId++
        root.opacity = 0.0
        hideTimer.targetId = root.__hideId
        hideTimer.restart()
    }
}
