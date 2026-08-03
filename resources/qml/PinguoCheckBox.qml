import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "."

// =====================================================================
// PinguoCheckBox — Pinguo-styled toggle checkbox
// =====================================================================
// Pill-shaped toggle with checkmark icon, DM Sans, 0.18s transitions.
// Uses theme tokens for all colors, no bare hex values.
// =====================================================================

Item {
    id: root

    property string text: ""
    property string accessibleName: text
    property string accessibleDescription: ""
    property bool checked: false

    signal toggled()

    activeFocusOnTab: true
    Accessible.role: Accessible.CheckBox
    Accessible.name: root.accessibleName
    Accessible.description: root.accessibleDescription
    Accessible.checked: root.checked
    Accessible.onToggleAction: {
        if (root.enabled) {
            root.checked = !root.checked
            root.toggled()
        }
    }

    implicitWidth: rowLayout.implicitWidth
    implicitHeight: Theme.sizeButtonSmall
    opacity: root.enabled ? 1.0 : 0.42

    RowLayout {
        id: rowLayout
        anchors.fill: parent
        spacing: Theme.spacing8

        // ── Toggle pill ──
        Rectangle {
            id: togglePill
            Layout.alignment: Qt.AlignVCenter
            width: 36
            height: 20
            radius: Theme.radiusPill
            color: root.checked ? Theme.primary : Qt.alpha(Theme.foreground, 0.24)
            border.width: 0

            Behavior on color {
                ColorAnimation { duration: Theme.motionShort; easing.type: Theme.motionStandard }
            }

            Rectangle {
                id: toggleKnob
                width: 16
                height: 16
                radius: 8
                color: root.enabled ? Theme.background : Theme.mutedForeground
                anchors.verticalCenter: parent.verticalCenter
                x: root.checked ? parent.width - width - 2 : 2

                Behavior on x {
                    NumberAnimation { duration: Theme.motionShort; easing.type: Theme.motionStandard }
                }
                Behavior on color {
                    ColorAnimation { duration: Theme.motionShort; easing.type: Theme.motionStandard }
                }
            }
        }

        // ── Label ──
        Text {
            id: textLabel
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            text: root.text
            color: Theme.foreground
            font.pixelSize: Theme.typeSubhead
            font.family: Theme.fontSans
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
    }

    // ── Focus ring ──
    Rectangle {
        anchors.fill: parent
        anchors.margins: -2
        radius: Theme.radiusPill + 2
        color: "transparent"
        border.width: 2
        border.color: Theme.ring
        visible: root.activeFocus
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: root.enabled
        cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: {
            if (root.enabled) {
                root.checked = !root.checked
                root.toggled()
            }
        }
    }

    Keys.onPressed: {
        if (root.enabled && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space)) {
            root.checked = !root.checked
            root.toggled()
        }
    }
}
