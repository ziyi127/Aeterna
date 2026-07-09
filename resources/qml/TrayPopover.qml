import QtQuick 2.15
import "."
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Aeterna 1.0

ApplicationWindow {
    id: popover
    width: 280
    height: 360
    flags: Qt.Popup | Qt.FramelessWindowHint
    color: Theme.materialOverlay

    

    property var mainWindow: null

    // HIG popover border + corner radius (radius applied to background rectangle)
    background: Rectangle {
        color: Theme.materialOverlay
        radius: Theme.radiusLarge
        border.color: Theme.hairline
        border.width: 1
    }

    AppInfo { id: appInfo }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacing12
        spacing: Theme.spacing12

        // Header
        Text {
            text: "Aeterna"
            font.pixelSize: Theme.typeHeadline
            font.weight: Theme.weightSemibold
            font.family: Theme.fontSans
            color: Theme.primary
            Layout.fillWidth: true
            Layout.topMargin: Theme.spacing8
            horizontalAlignment: Text.AlignHCenter
        }

        Text {
            text: "版本 " + appInfo.version
            font.pixelSize: Theme.typeCaption1
            font.family: Theme.fontSans
            color: Theme.mutedForeground
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: Theme.spacing12
            height: 1
            color: Theme.hairline
        }

        // Recent files section
        Text {
            text: "最近文件"
            font.pixelSize: Theme.typeSubhead
            font.weight: Theme.weightSemibold
            font.family: Theme.fontSans
            color: Theme.foreground
            Layout.topMargin: Theme.spacing12
        }

        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: 120
            model: ListModel {
                ListElement { name: "暂无最近文件" }
            }
            spacing: Theme.spacing4

            delegate: Rectangle {
                id: recentItem
                width: parent.width
                height: 32
                radius: Theme.radiusSmall
                color: "transparent"

                Behavior on color {
                    ColorAnimation { duration: Theme.motionShort; easing.type: Theme.motionStandard }
                }

                Text {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.spacing12
                    verticalAlignment: Text.AlignVCenter
                    text: name
                    color: recentItemMouse.containsMouse ? Theme.foreground : Theme.mutedForeground
                    font.pixelSize: Theme.typeSubhead
                    font.family: Theme.fontSans
                }

                MouseArea {
                    id: recentItemMouse
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true
                    onEntered: recentItem.color = Qt.alpha(Theme.primary, 0.18)
                    onExited: recentItem.color = "transparent"
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: Theme.hairline
        }

        // Quick actions
        Text {
            text: "快捷操作"
            font.pixelSize: Theme.typeSubhead
            font.weight: Theme.weightSemibold
            font.family: Theme.fontSans
            color: Theme.foreground
            Layout.topMargin: Theme.spacing12
        }

        PinguoButton {
            id: showMainButton
            text: "显示主窗口"
            icon: "window"
            variant: PinguoButton.Text
            Layout.fillWidth: true
            Layout.preferredHeight: 36
            onClicked: {
                if (popover.mainWindow) {
                    popover.mainWindow.show()
                    popover.mainWindow.raise()
                    popover.mainWindow.requestActivate()
                }
                popover.close()
            }
        }

        PinguoButton {
            id: openEditorButton
            text: "打开编辑器"
            icon: "doc"
            variant: PinguoButton.Text
            Layout.fillWidth: true
            Layout.preferredHeight: 36
            onClicked: {
                if (popover.mainWindow) {
                    popover.mainWindow.show()
                    popover.mainWindow.raise()
                    popover.mainWindow.requestActivate()
                }
                popover.close()
                // Open editor via the main window's editor loader
                if (popover.mainWindow && popover.mainWindow.editorLoader) {
                    popover.mainWindow.editorLoader.openEditor()
                }
            }
        }

        // ── Quit button with danger styling ──
        Rectangle {
            id: quitButtonBg
            Layout.fillWidth: true
            Layout.preferredHeight: 36
            radius: Theme.radiusMedium
            color: quitMouse.containsMouse
                   ? Qt.alpha(Theme.destructive, 0.12)
                   : "transparent"

            Behavior on color {
                ColorAnimation { duration: Theme.motionShort; easing.type: Theme.motionStandard }
            }

            RowLayout {
                anchors.centerIn: parent
                spacing: Theme.spacing12

                Icon {
                    name: "power"
                    size: 16
                    tier: Icon.Danger
                }
                Text {
                    text: "退出应用"
                    color: Theme.destructive
                    font.pixelSize: Theme.typeSubhead
                    font.weight: Theme.weightSemibold
                    font.family: Theme.fontSans
                }
            }

            MouseArea {
                id: quitMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    popover.close()
                    Qt.quit()
                }
            }
        }
    }
}
