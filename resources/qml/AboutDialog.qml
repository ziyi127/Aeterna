import QtQuick 2.15
import "."
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Aeterna 1.0

// =====================================================================
// AboutDialog — App info, credits, and license
// =====================================================================

Dialog {
    id: root

    title: "关于 Aeterna"
    width: 420
    height: 360
    modal: true
    anchors.centerIn: parent
    padding: Theme.spacing32
    closePolicy: Popup.CloseOnEscape
    standardButtons: Dialog.NoButton

    AppInfo { id: appInfo }

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
        anchors.fill: parent
        spacing: 0

        // ── App icon + name ──
        Item {
            Layout.preferredHeight: 80
            Layout.fillWidth: true

            ColumnLayout {
                anchors.centerIn: parent
                spacing: Theme.spacing8

                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    width: 48
                    height: 48
                    radius: Theme.radiusMedium
                    color: Theme.brand500

                    Text {
                        anchors.centerIn: parent
                        text: "A"
                        font.pixelSize: 24
                        font.weight: Theme.weightBold
                        font.family: Theme.fontSans
                        color: "white"
                    }
                }

                Text {
                    text: "Aeterna"
                    font.pixelSize: Theme.typeTitle2
                    font.weight: Theme.weightBold
                    color: Theme.foreground
                    font.family: Theme.fontSans
                    Layout.alignment: Qt.AlignHCenter
                }
            }
        }

        // ── Version info ──
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing4

            Text {
                text: "版本 " + appInfo.version
                color: Theme.mutedForeground
                font.family: Theme.fontSans
                font.pixelSize: Theme.typeSubhead
                Layout.alignment: Qt.AlignHCenter
            }

            Text {
                text: "基于 Rust + Qt6 构建"
                color: Qt.alpha(Theme.mutedForeground, 0.72)
                font.family: Theme.fontSans
                font.pixelSize: Theme.typeCaption1
                Layout.alignment: Qt.AlignHCenter
            }
        }

        // ── Divider ──
        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: Theme.spacing24
            Layout.bottomMargin: Theme.spacing24
            height: 1
            color: Theme.hairline
        }

        // ── Author ──
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing4

            Text {
                text: "开发者"
                color: Theme.mutedForeground
                font.family: Theme.fontSans
                font.pixelSize: Theme.typeCaption2
                Layout.alignment: Qt.AlignHCenter
            }

            Text {
                text: '<a href="https://github.com/ziyi127" style="color: ' + Theme.brand500 + '; text-decoration: none;">ziyi127</a>'
                textFormat: Text.RichText
                color: Theme.brand500
                font.family: Theme.fontSans
                font.pixelSize: Theme.typeSubhead
                font.weight: Theme.weightMedium
                Layout.alignment: Qt.AlignHCenter
                cursorShape: Qt.PointingHandCursor
                onLinkActivated: Qt.openUrlExternally(link)
                hoverEnabled: true
            }
        }

        // ── Copyright ──
        Text {
            Layout.topMargin: Theme.spacing16
            Layout.alignment: Qt.AlignHCenter
            text: "© 2026 ziyi127"
            color: Qt.alpha(Theme.mutedForeground, 0.6)
            font.family: Theme.fontSans
            font.pixelSize: Theme.typeCaption2
        }

        // ── License ──
        Text {
            text: "GPL-3.0 License"
            font.pixelSize: Theme.typeCaption2
            font.family: Theme.fontSans
            color: Qt.alpha(Theme.mutedForeground, 0.6)
            Layout.alignment: Qt.AlignHCenter
        }

        Item { Layout.fillHeight: true }

        // ── Close button ──
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing12

            Item { Layout.fillWidth: true }

            PinguoButton {
                text: "关闭"
                variant: PinguoButton.Primary
                onClicked: root.close()
            }
        }
    }
}
