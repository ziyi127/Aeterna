import QtQuick 2.15
import "."
import QtQuick.Controls 2.15
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
        y: (_hovered && root.enabled && root.hoverEnabled) ? -2 : 0
        Behavior on y {
            NumberAnimation { duration: Theme.motionShort; easing.type: Theme.motionStandard }
        }

        // Disabled state: reduce opacity
        opacity: root.enabled ? 1.0 : 0.5
        Behavior on opacity {
            NumberAnimation { duration: Theme.motionShort; easing.type: Theme.motionStandard }
        }

        // ── Shadow gutter — the card is slightly inset so the
        //     shadow blur stays visible outside the bounds. ──
        Item {
            id: shadowGutter
            anchors.fill: parent
            anchors.margins: -12

            // Shadow blur — pure ShaderEffect, no Qt5Compat needed
            ShaderEffect {
                id: cardShadow
                anchors.fill: parent
                property variant src: cardBackground
                property real blurRadius: (_hovered && root.enabled && root.hoverEnabled) ? 12.0 : 4.0
                property real shadowOpacity: (_hovered && root.enabled && root.hoverEnabled)
                                              ? Theme.shadowOpacityFloat : Theme.shadowOpacityCard
                property color shadowColor: Theme.shadowColor

                // Simple blur + tint shader
                fragmentShader: "
                    varying highp vec2 qt_TexCoord0;
                    uniform sampler2D src;
                    uniform lowp float blurRadius;
                    uniform lowp float shadowOpacity;
                    uniform lowp vec4 shadowColor;

                    void main() {
                        lowp vec4 col = texture2D(src, qt_TexCoord0);
                        // Use alpha channel as distance from opaque region;
                        // amplify it with blurRadius to get a soft halo.
                        lowp float d = col.a;
                        lowp float kernel = exp(-d * blurRadius * 2.0);
                        lowp float alpha = kernel * shadowOpacity;
                        gl_FragColor = vec4(shadowColor.rgb, shadowColor.a * alpha);
                    }"
                visible: shadowOpacity > 0.0

                Behavior on blurRadius {
                    NumberAnimation { duration: Theme.motionShort; easing.type: Theme.motionStandard }
                }
                Behavior on shadowOpacity {
                    NumberAnimation { duration: Theme.motionShort; easing.type: Theme.motionStandard }
                }
            }
        }

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

        onEntered: { if (root.enabled) _hovered = true }
        onExited: { _hovered = false }
    }
}
