import QtQuick 2.15
import "."

// A single adaptive glass layer for navigation and transient chrome.
// Keep content surfaces opaque; do not nest GlassSurface instances.
Item {
    id: root

    enum Variant { Navigation, Toolbar, Popover, Drawer, Clear }

    property int variant: GlassSurface.Toolbar
    property real radius: Theme.radiusLarge
    property bool bordered: true
    property bool mediaBackdrop: false
    property bool highlighted: !(Theme.highContrast || Theme.reduceTransparency)
    property color effectiveForeground: Theme.foreground

    readonly property bool useClear: variant === GlassSurface.Clear && mediaBackdrop
    readonly property color materialColor: {
        if (Theme.highContrast || Theme.reduceTransparency)
            return variant === GlassSurface.Popover ? Theme.surfaceOverlay : Theme.surfaceRaised
        switch (variant) {
        case GlassSurface.Navigation: return Theme.glassNavigation
        case GlassSurface.Popover: return Theme.glassPopover
        case GlassSurface.Drawer: return Theme.glassDrawer
        case GlassSurface.Clear: return useClear ? Theme.glassClear : Theme.glassToolbar
        default: return Theme.glassToolbar
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: root.materialColor
        opacity: Theme.highContrast || Theme.reduceTransparency ? 1.0 : Theme.glassOpacity
        border.width: root.bordered ? 1 : 0
        border.color: Theme.highContrast || Theme.reduceTransparency ? Theme.hairline : Theme.glassBorder

        Behavior on color {
            ColorAnimation { duration: Theme.motionShort; easing.type: Theme.motionStandard }
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 1
            radius: root.radius
            color: Theme.glassHighlight
            visible: root.highlighted
        }
    }
}
