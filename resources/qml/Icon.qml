import QtQuick 2.15
import "."

// =====================================================================
// Aeterna Icon — SF Symbol style icon component
// =====================================================================
// Loads PNG icons from the qrc:/icons/ resource path and applies the
// current theme tint color. Sizes follow 16/20/24 px scale.
//
// Usage:
//   Icon { name: "house"; size: 20; tier: Icon.Primary }
//   Icon { name: "magnifyingglass"; size: 16; tier: Icon.Secondary }
//
// `tier` controls the tint color from theme tokens:
//   Primary   → Theme.foreground
//   Secondary → Theme.mutedForeground
//   Tertiary  → Theme.tertiaryLabel
//   Accent    → Theme.primary
//   Success   → Theme.success
//   Warning   → Theme.warning
//   Danger    → Theme.destructive
//
// Qt 6 requires a precompiled QSB shader for portable ShaderEffect
// rendering; the asset is generated from resources/shaders/icon_tint.frag.
// =====================================================================

Item {
    id: iconRoot

    enum Tier { Primary, Secondary, Tertiary, Accent, Success, Warning, Danger }

    property string name: "circle.fill"
    property int size: 20
    property int tier: Icon.Primary
    property color overrideColor: "transparent"
    property string accessibleName: name

    Accessible.name: accessibleName

    // Only 16/20/24 px assets are provided; snap requested size to the
    // nearest available raster so icons never load a missing resource.
    readonly property int effectiveSize: {
        if (size <= 16) return 16;
        if (size <= 20) return 20;
        return 24;
    }

    width: effectiveSize
    height: effectiveSize

    readonly property color tintColor: {
        if (iconRoot.overrideColor !== "transparent") return iconRoot.overrideColor;
        switch (iconRoot.tier) {
            case 0: return Theme.foreground
            case 1: return Theme.mutedForeground
            case 2: return Theme.tertiaryLabel
            case 3: return Theme.primary
            case 4: return Theme.success
            case 5: return Theme.warning
            case 6: return Theme.destructive
            default: return Theme.foreground
        }
    }

    // Backing source: the black silhouette loaded from qrc resources.
    Image {
        id: sourceImg
        source: {
            if (!iconRoot.name || iconRoot.name === "") return ""
            return "qrc:/icons/" + iconRoot.name + "_" + iconRoot.effectiveSize + ".png"
        }
        sourceSize.width: iconRoot.effectiveSize
        sourceSize.height: iconRoot.effectiveSize
        smooth: true
        mipmap: true
        asynchronous: true
        fillMode: Image.PreserveAspectFit
        visible: false
        anchors.fill: parent
    }

    // Pure-QML color overlay: multiplies source alpha by target color.
    ShaderEffect {
        anchors.fill: sourceImg
        property variant src: sourceImg
        property color tint: iconRoot.tintColor

        fragmentShader: "qrc:/shaders/icon_tint.frag.qsb"

        Behavior on tint {
            ColorAnimation { duration: Theme.motionShort; easing.type: Theme.motionStandard }
        }
    }
}
