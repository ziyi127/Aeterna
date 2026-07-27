import QtQuick 2.15
import "."
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Aeterna 1.0

Dialog {
    id: root

    width: parent ? Math.min(440, Math.max(320, parent.width - Theme.spacing32)) : 400
    modal: true
    anchors.centerIn: parent
    padding: 0
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    standardButtons: Dialog.NoButton

    implicitHeight: bodyColumn.implicitHeight + Theme.spacing32 * 2
    height: Math.min(implicitHeight, parent ? parent.height - Theme.spacing48 : implicitHeight)

    AppInfo { id: appInfo }

    background: Rectangle {
        color: Theme.materialOverlay
        radius: Theme.radiusLarge
        border.color: Theme.hairline
        border.width: 1
    }

    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.motionMedium; easing.type: Theme.motionDecelerate }
    }
    exit: Transition {
        NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Theme.motionShort; easing.type: Theme.motionAccelerate }
    }

    contentItem: Flickable {
        id: bodyFlick
        anchors.fill: parent
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        contentWidth: width
        contentHeight: bodyColumn.implicitHeight + Theme.spacing32 * 2

        ScrollBar.vertical: ScrollBar {
            contentItem: Rectangle {
                implicitWidth: 6
                radius: 3
                color: Qt.alpha(Theme.foreground, 0.24)
            }
        }

        ColumnLayout {
            id: bodyColumn
            width: bodyFlick.width
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: Theme.spacing32
            anchors.rightMargin: Theme.spacing32
            anchors.topMargin: Theme.spacing32
            anchors.bottomMargin: Theme.spacing32
            spacing: Theme.spacing16

            // ── Logo ──
            Image {
                Layout.alignment: Qt.AlignHCenter
                width: 64
                height: 64
                source: "qrc:/icons/icon.png"
                fillMode: Image.PreserveAspectFit
                smooth: true
                mipmap: true
                sourceSize.width: 128
                sourceSize.height: 128
            }

            // ── App name ──
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: appInfo.name
                color: Theme.foreground
                font.pixelSize: Theme.typeTitle2
                font.weight: Theme.weightBold
                font.family: Theme.fontSans
            }

            // ── Subtitle ──
            Text {
                Layout.fillWidth: true
                text: "考试日程播放与考场计时系统"
                color: Theme.mutedForeground
                font.pixelSize: Theme.typeSubhead
                font.family: Theme.fontSans
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }

            // ── Version ──
            Text {
                Layout.fillWidth: true
                text: "版本 " + appInfo.version + " · Rust + Qt 6"
                color: Qt.alpha(Theme.mutedForeground, 0.8)
                font.pixelSize: Theme.typeCaption1
                font.family: Theme.fontSans
                horizontalAlignment: Text.AlignHCenter
            }

            // ── Separator ──
            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: Theme.spacing4
                height: 1
                color: Theme.hairline
            }

            // ── Developer label ──
            Text {
                Layout.fillWidth: true
                text: "开发者"
                color: Theme.mutedForeground
                font.pixelSize: Theme.typeCaption1
                font.family: Theme.fontSans
                horizontalAlignment: Text.AlignHCenter
            }

            // ── GitHub link ──
            Text {
                Layout.fillWidth: true
                text: '<a href="https://github.com/ziyi127" style="color: ' + Theme.primary + '; text-decoration: none;">ziyi127</a>'
                textFormat: Text.RichText
                color: Theme.primary
                font.pixelSize: Theme.typeSubhead
                font.weight: Theme.weightMedium
                font.family: Theme.fontSans
                horizontalAlignment: Text.AlignHCenter
                onLinkActivated: Qt.openUrlExternally(link)
            }

            // ── Copyright ──
            Text {
                Layout.fillWidth: true
                text: "© 2026 ziyi127 · GPL-3.0"
                color: Qt.alpha(Theme.mutedForeground, 0.72)
                font.pixelSize: Theme.typeCaption2
                font.family: Theme.fontSans
                horizontalAlignment: Text.AlignHCenter
            }

            // ── Close button ──
            PinguoButton {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: Theme.spacing8
                text: "关闭"
                variant: PinguoButton.Primary
                onClicked: root.close()
            }
        }
    }
}
