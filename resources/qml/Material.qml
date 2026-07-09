import QtQuick 2.15
import "."
import QtQuick.Controls 2.15

// =====================================================================
// Aeterna Material — Pinguo Design System surface tiers
// =====================================================================
// Creates a Rectangle styled according to one of the four Pinguo surface
// tiers. Each tier encapsulates a semantic background color and a
// structural 1px border, pulled from Theme.qml tokens.
//
// Pinguo surface principles applied here:
//  • Surfaces are opaque and semantic — prefer background/card/popover
//    over decorative tints.
//  • Use the THINNEST surface that achieves hierarchy; Elevated/Overlay
//    sit above Base; Vibrant separates navigation/header regions.
//  • Borders are structural, 1px, and use Theme.hairline.
//
// Tiers:
//   Base     — primary window surface (Theme.background)
//   Elevated — raised card / panel above the window (Theme.card)
//   Overlay  — popover / menu / sheet (Theme.popover)
//   Vibrant  — sidebar / header surface (Theme.secondary)
//
// Usage:
//   Material { anchors.fill: parent; tier: Material.Elevated }
//   Material { tier: Material.Overlay; radius: Theme.radiusLarge }
// =====================================================================

Item {
    id: root

    enum Tier { Base, Elevated, Overlay, Vibrant }

    property int tier: Material.Elevated
    property real radius: Theme.radiusLarge
    property bool bordered: true

    // Aliases for parent layout convenience
    property alias color: rect.color
    property alias border: rect.border

    Rectangle {
        id: rect
        anchors.fill: parent
        radius: root.radius
        border.width: root.bordered ? 1 : 0
        color: {
            switch (root.tier) {
                case 0: return Theme.materialBase
                case 1: return Theme.materialElevated
                case 2: return Theme.materialOverlay
                case 3: return Theme.materialVibrant
                default: return Theme.materialBase
            }
        }
        border.color: Theme.hairline

        Behavior on color {
            ColorAnimation { duration: Theme.motionShort; easing.type: Theme.motionStandard }
        }
    }
}
