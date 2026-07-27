import QtQuick 2.15
import "."
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

// =====================================================================
// PinguoButton — capsule action button
// =====================================================================
// Variants: primary (40), secondary (48), text (48), hero (56).
// Pill shape, DM Sans, 0.18s transitions.
// 
// Pinguo spec "Secondary Link Button" pattern: set showTrailingArrow
// to true for a text-led secondary action with a trailing chevron mark
// (e.g. "Learn more ›").
// =====================================================================

Item {
    id: root

    enum Variant { Primary, Secondary, Text, Hero }

    property string text: ""
    property string icon: ""
    property int variant: PinguoButton.Primary
    property bool showTrailingArrow: false

    signal clicked()

    

    readonly property bool isPrimary: variant === PinguoButton.Primary || variant === PinguoButton.Hero
    readonly property bool isHero: variant === PinguoButton.Hero
    readonly property bool isText: variant === PinguoButton.Text

    readonly property int buttonHeight: isHero ? Theme.sizeButtonLarge
                                              : (variant === PinguoButton.Secondary || variant === PinguoButton.Text
                                                 ? Theme.sizeButtonMedium
                                                 : Theme.sizeButtonSmall)
    readonly property int hPadding: isHero ? 28 : (variant === PinguoButton.Secondary || variant === PinguoButton.Text ? 24 : 20)
    readonly property int fontSize: isHero ? 16 : 14

    implicitWidth: Math.max(buttonHeight, rowLayout.implicitWidth + hPadding * 2)
    implicitHeight: buttonHeight
    opacity: root.enabled ? 1.0 : 0.42
    activeFocusOnTab: true

    Rectangle {
        id: background
        anchors.fill: parent
        radius: Theme.radiusPill
        color: {
            if (!root.enabled) return root.isPrimary ? Theme.primary : (root.isText ? "transparent" : Theme.secondary);
            if (root.isText) return "transparent";
            if (root.isPrimary) return btnMouse.containsMouse ? Qt.darker(Theme.primary, 1.04) : Theme.primary;
            return btnMouse.containsMouse ? Theme.muted : Theme.secondary;
        }
        border.width: 0

        Behavior on color {
            ColorAnimation { duration: Theme.motionShort; easing.type: Theme.motionStandard }
        }
    }

    Rectangle {
        id: focusRing
        x: -2
        y: -2
        width: parent.width + 4
        height: parent.height + 4
        radius: Theme.radiusPill + 2
        color: "transparent"
        border.width: 2
        border.color: Theme.ring
        visible: root.activeFocus
    }

    RowLayout {
        id: rowLayout
        anchors.centerIn: parent
        spacing: Theme.spacing8

        Icon {
            visible: root.icon !== ""
            name: root.icon
            size: root.fontSize
            tier: Icon.Primary
            // Pinguo spec: icons on filled buttons use the foreground color for contrast
            overrideColor: root.isPrimary ? Theme.primaryForeground : Theme.foreground
        }

        Text {
            visible: root.text !== ""
            text: root.text
            color: root.isPrimary ? Theme.primaryForeground
                                  : (root.isText && btnMouse.containsMouse ? Theme.primary : Theme.foreground)
            font.pixelSize: root.fontSize
            font.weight: Theme.weightSemibold
            font.family: Theme.fontSans
            elide: Text.ElideRight

            Behavior on color {
                ColorAnimation { duration: Theme.motionShort; easing.type: Theme.motionStandard }
            }
        }

        // Pinguo "Secondary Link Button" trailing chevron (per button.json spec)
        Text {
            visible: root.showTrailingArrow && !root.isPrimary
            text: "›"
            color: root.isText && btnMouse.containsMouse ? Theme.primary : Theme.foreground
            font.pixelSize: root.fontSize + 2
            font.family: Theme.fontSans

            Behavior on color {
                ColorAnimation { duration: Theme.motionShort; easing.type: Theme.motionStandard }
            }
        }
    }

    MouseArea {
        id: btnMouse
        anchors.fill: parent
        hoverEnabled: root.enabled
        cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: {
            root.forceActiveFocus()
            if (root.enabled) root.clicked()
        }
    }

    Keys.onPressed: {
        if (root.enabled && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space)) {
            root.clicked()
        }
    }
}
