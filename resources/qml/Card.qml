import QtQuick 2.15
import "."
import QtQuick.Layouts 1.15

// =====================================================================
// Card — Pinguo elevated container with optional title
// =====================================================================
// Wraps content in a Material.Elevated surface using Pinguo spacing
// (1.2rem radius, 24px internal padding) and quiet hierarchy.
//
// Hover: card lifts 2px with enhanced shadow (180ms ease).
// Disabled: opacity 0.5, hover lift disabled.
//
// No dependency on Qt5Compat.GraphicalEffects — the shadow is
// rendered via a simple ShaderEffect so the component works
// without the compat module being installed in the system Qt.
// =====================================================================

Item {
    id: root

    property string title: ""
    property Item contentItem: null
    property bool hoverEnabled: true

    property bool _hovered: false

    implicitWidth: 240
    implicitHeight: contentLayout.implicitHeight + Theme.spacing24 * 2

    // ── Card surface container with lift and disabled states ──
    Item {
        id: cardContainer
        anchors.fill: parent

        // Lift on hover: shift up 2px
        y: (root._hovered && root.enabled && root.hoverEnabled) ? -2 : 0
        Behavior on y {
            NumberAnimation { duration: Theme.motionShort; easing.type: Theme.motionStandard }
        }

        // Disabled state: reduce opacity
        opacity: root.enabled ? 1.0 : 0.5
        Behavior on opacity {
            NumberAnimation { duration: Theme.motionShort; easing.type: Theme.motionStandard }
        }

        // Qt 6 ShaderEffect requires precompiled .qsb assets for portable
        // deployment. Until the project has a shader build pipeline, use the
        // structural border from Material as elevation rather than a broken
        // runtime GLSL shadow.

        Material {
            id: cardBackground
            anchors.fill: parent
            tier: Material.Elevated
            radius: Theme.radiusLarge
            visible: true
        }

        // ── Content ──
        ColumnLayout {
            id: contentLayout
            anchors.fill: parent
            anchors.margins: Theme.spacing24
            spacing: Theme.spacing16

            Text {
                visible: root.title !== ""
                text: root.title
                color: Theme.foreground
                font.pixelSize: Theme.typeSubhead
                font.weight: Theme.weightSemibold
                font.family: Theme.fontSans
            }

            Item {
                id: contentContainer
                Layout.fillWidth: true
                Layout.fillHeight: true
                implicitHeight: root.contentItem ? root.contentItem.implicitHeight : 0
                children: root.contentItem ? [root.contentItem] : []

                // Anchor the reparented contentItem to fill the container
                Component.onCompleted: {
                    if (root.contentItem) {
                        root.contentItem.anchors.fill = contentContainer
                    }
                }
            }
        }
    }

    // ── Hover detection ──
    MouseArea {
        id: hoverArea
        anchors.fill: parent
        hoverEnabled: root.hoverEnabled
        acceptedButtons: Qt.NoButton
        cursorShape: root.hoverEnabled && root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor

        onEntered: { if (root.enabled) root._hovered = true }
        onExited: { root._hovered = false }
    }
}
