import QtQuick 2.15
import "."
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

// =====================================================================
// ConfirmDialog — Reusable Pinguo-styled confirmation dialog
// =====================================================================
// Provides a modal dialog shell with:
//   • materialOverlay background + hairline border + radiusLarge corners
//   • Pinguo enter/exit opacity transitions (motionMedium / motionShort)
//   • Standard title + message content layout (360px implicit width)
//
// Callers set `titleText` / `messageText` and provide a `footer` with the
// action buttons. This eliminates duplicated dialog boilerplate.
//
// Usage:
//   ConfirmDialog {
//       id: confirmDialog
//       titleText: "删除考试"
//       messageText: "确定要删除当前考试吗？此操作不可撤销。"
//       footer: RowLayout { ... PinguoButton { ... } ... }
//   }
// =====================================================================

Dialog {
    id: root

    modal: true
    anchors.centerIn: parent
    closePolicy: Popup.CloseOnEscape
    standardButtons: Dialog.NoButton

    property string titleText: ""
    property string messageText: ""

    background: Rectangle {
        color: Theme.materialOverlay
        radius: Theme.radiusLarge
        border.color: Theme.hairline
        border.width: 1
    }

    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: Theme.motionMedium; easing.type: Theme.motionDecelerate }
    }
    exit: Transition {
        NumberAnimation { property: "opacity"; from: 1.0; to: 0.0; duration: Theme.motionShort; easing.type: Theme.motionAccelerate }
    }

    contentItem: ColumnLayout {
        spacing: Theme.spacing16
        implicitWidth: 360

        Text {
            visible: root.titleText !== ""
            text: root.titleText
            font.pixelSize: Theme.typeHeadline
            font.weight: Theme.weightBold
            color: Theme.foreground
            font.family: Theme.fontSans
        }

        Text {
            visible: root.messageText !== ""
            text: root.messageText
            color: Theme.mutedForeground
            font.family: Theme.fontSans
            font.pixelSize: Theme.typeBody
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
    }
}
