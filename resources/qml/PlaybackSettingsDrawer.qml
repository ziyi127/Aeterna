import QtQuick 2.15
import "."
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15

// =====================================================================
// PlaybackSettingsDrawer — Right-side settings drawer for the player
// =====================================================================
// Slides in from the right and exposes UI scale, density, big-clock mode,
// big-clock font size, and large-info-font toggle.
//
// Public API:
//   property bool visible
//   property real uiScale
//   property string density        // "comfortable" | "cozy" | "compact"
//   property bool bigClock
//   property bool largeInfoFont
//   signal closed()
//
// Note: uiScale/density/bigClock/largeInfoFont also emit the standard
// QML changed signals (uiScaleChanged, densityChanged, etc.).
// =====================================================================

Item {
    id: root

    width: 320
    height: parent ? parent.height : implicitHeight
    x: visible ? parent.width - width : parent.width
    visible: false
    z: 200

    property real uiScale: 1.0
    property string density: "comfortable"
    property bool bigClock: false
    property bool largeInfoFont: false
    property bool bigClockEnabled: false
    property real bigClockFontSize: 96

    signal closed()



    activeFocusOnTab: visible
    Accessible.role: Accessible.Dialog
    Accessible.name: "播放设置"

    function close() {
        if (visible)
            visible = false
    }

    Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape && root.visible) {
            root.close()
            event.accepted = true
        }
    }

    Behavior on x {
        NumberAnimation {
            duration: Theme.motionMedium
            easing.type: Theme.motionDecelerate
        }
    }

    GlassSurface {
        anchors.fill: parent
        variant: GlassSurface.Drawer
        radius: 0 // drawer is edge-to-edge on the right; 0 is intentional
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacing24
        spacing: Theme.spacing24

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing12

            Text {
                text: "播放设置"
                color: Theme.foreground
                font.pixelSize: Theme.typeHeadline
                font.weight: Theme.weightBold
                font.family: Theme.fontSans
                Layout.fillWidth: true
            }

            Rectangle {
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                radius: Theme.radiusMedium
                color: closeMouse.containsMouse
                    ? Qt.alpha(Theme.foreground, 0.08)
                    : Qt.alpha(Theme.foreground, 0)

                Behavior on color {
                    ColorAnimation {
                        duration: Theme.motionShort
                        easing.type: Theme.motionStandard
                    }
                }

                Icon {
                    name: "xmark"
                    size: 20
                    anchors.centerIn: parent
                    tier: Icon.Primary
                }

                MouseArea {
                    id: closeMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.close()
                }
            }
        }

        ColumnLayout {
            spacing: Theme.spacing12
            Layout.fillWidth: true

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacing12

                Text {
                    text: "界面缩放"
                    color: Theme.foreground
                    font.pixelSize: Theme.typeSubhead
                    font.family: Theme.fontSans
                    Layout.fillWidth: true
                }

                Text {
                    text: Math.round(root.uiScale * 100) + "%"
                    color: Theme.mutedForeground
                    font.pixelSize: Theme.typeCaption1
                    font.family: Theme.fontSans
                }
            }

            Slider {
                id: uiScaleSlider
                from: 0.5
                to: 2.0
                stepSize: 0.05
                value: root.uiScale
                Layout.fillWidth: true
                // onMoved only fires on user drag — one-way update, no loop.
                onMoved: root.uiScale = value
                background: Rectangle {
                    x: uiScaleSlider.leftPadding
                    y: uiScaleSlider.topPadding + uiScaleSlider.availableHeight / 2 - height / 2
                    implicitWidth: 200
                    implicitHeight: 4
                    width: uiScaleSlider.availableWidth
                    height: implicitHeight
                    radius: 2
                    color: Theme.muted
                    Rectangle {
                        width: uiScaleSlider.visualPosition * parent.width
                        height: parent.height
                        color: Theme.primary
                        radius: 2
                    }
                }
                handle: Rectangle {
                    x: uiScaleSlider.leftPadding + uiScaleSlider.visualPosition * (uiScaleSlider.availableWidth - width)
                    y: uiScaleSlider.topPadding + uiScaleSlider.availableHeight / 2 - height / 2
                    implicitWidth: 16
                    implicitHeight: 16
                    radius: 8
                    color: Theme.background
                    border.color: Theme.primary
                    border.width: 2
                }
            }
        }

        ColumnLayout {
            spacing: Theme.spacing12
            Layout.fillWidth: true

            Text {
                text: "界面密度"
                color: Theme.foreground
                font.pixelSize: Theme.typeSubhead
                font.family: Theme.fontSans
            }

            RowLayout {
                spacing: Theme.spacing8
                Layout.fillWidth: true

                Repeater {
                    model: [
                        { label: "舒适", value: "comfortable" },
                        { label: "适中", value: "cozy" },
                        { label: "紧凑", value: "compact" }
                    ]

                    delegate: PinguoButton {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Theme.sizeButtonMedium
                        Layout.alignment: Qt.AlignVCenter
                        text: modelData.label
                        variant: root.density === modelData.value
                            ? PinguoButton.Primary
                            : PinguoButton.Secondary
                        onClicked: root.density = modelData.value
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing12

            Text {
                text: "大时钟模式"
                color: Theme.foreground
                font.pixelSize: Theme.typeSubhead
                font.family: Theme.fontSans
                Layout.fillWidth: true
            }

            PinguoCheckBox {
                checked: root.bigClock
                onToggled: root.bigClock = checked
            }
        }

        ColumnLayout {
            spacing: Theme.spacing12
            Layout.fillWidth: true
            enabled: root.bigClock
            opacity: root.bigClock ? 1.0 : 0.4

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacing12

                Text {
                    text: "大时钟字号"
                    color: Theme.foreground
                    font.pixelSize: Theme.typeSubhead
                    font.family: Theme.fontSans
                    Layout.fillWidth: true
                }

                Text {
                    text: root.bigClockFontSize + "px"
                    color: Theme.mutedForeground
                    font.pixelSize: Theme.typeCaption1
                    font.family: Theme.fontSans
                }
            }

            Slider {
                id: clockFontSlider
                from: 48
                to: 240
                stepSize: 4
                value: root.bigClockFontSize
                Layout.fillWidth: true
                enabled: root.bigClock
                // onMoved only fires on user drag — one-way update, no loop.
                onMoved: root.bigClockFontSize = value
                background: Rectangle {
                    x: clockFontSlider.leftPadding
                    y: clockFontSlider.topPadding + clockFontSlider.availableHeight / 2 - height / 2
                    implicitWidth: 200
                    implicitHeight: 4
                    width: clockFontSlider.availableWidth
                    height: implicitHeight
                    radius: 2
                    color: Theme.muted
                    Rectangle {
                        width: clockFontSlider.visualPosition * parent.width
                        height: parent.height
                        color: Theme.primary
                        radius: 2
                    }
                }
                handle: Rectangle {
                    x: clockFontSlider.leftPadding + clockFontSlider.visualPosition * (clockFontSlider.availableWidth - width)
                    y: clockFontSlider.topPadding + clockFontSlider.availableHeight / 2 - height / 2
                    implicitWidth: 16
                    implicitHeight: 16
                    radius: 8
                    color: Theme.background
                    border.color: Theme.primary
                    border.width: 2
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing12

            Text {
                text: "本场信息大字体"
                color: Theme.foreground
                font.pixelSize: Theme.typeSubhead
                font.family: Theme.fontSans
                Layout.fillWidth: true
            }

            PinguoCheckBox {
                checked: root.largeInfoFont
                onToggled: root.largeInfoFont = checked
            }
        }

        Item { Layout.fillHeight: true }
    }

    property bool __wasVisible: false

    onVisibleChanged: {
        if (visible) {
            closeTimer.stop()
            root.__wasVisible = true
            forceActiveFocus()
        } else if (root.__wasVisible) {
            root.__wasVisible = false
            closeTimer.restart()
        }
    }

    Timer {
        id: closeTimer
        interval: Theme.motionMedium
        repeat: false
        onTriggered: root.closed()
    }
}
