pragma Singleton
import QtQuick 2.15

// =====================================================================
// Aeterna Design Tokens — Pinguo Design System alignment
// =====================================================================
//  - Colors: Pinguo primitive ramps + semantic roles (light/dark)
//  - Spacing: 0.24rem base → 4px grid scale (4/8/12/16/24/32/48/64/96/128)
//  - Radius: global 1.2rem → 19.2px, with small/medium/large/xlarge/pill
//  - Type:   DM Sans / JetBrains Mono, Pinguo scale + Apple HIG fallbacks
//  - Material: base/elevated/overlay/vibrant mapped to semantic surfaces
//  - Motion:  Pinguo 0.18s short transitions + standard curves
//  Three appearance modes are supported: light / dark / highContrast.
// =====================================================================

QtObject {
    id: theme

    // ── External state (set by Rust backend via MainWindow) ──
    property bool _darkMode: true
    property string _customPrimaryColor: ""

    // ── Appearance modes ──
    readonly property bool darkMode: _darkMode
    property bool highContrast: false

    // ═══════════════════════════════════════════════════════════════
    // PRIMITIVE PALETTE
    // ═══════════════════════════════════════════════════════════════

    // brand — Pinguo Blue #007aff as anchor (per colors_and_type.css)
    readonly property color brand50:  "#e8f2ff"
    readonly property color brand100: "#cfe5ff"
    readonly property color brand200: "#9fcbff"
    readonly property color brand300: "#66abff"
    readonly property color brand400: "#2e8dff"
    readonly property color brand500: "#007aff"
    readonly property color brand600: "#0064d6"
    readonly property color brand700: "#004fad"
    readonly property color brand800: "#003b82"
    readonly property color brand900: "#00275a"

    // Pinguo brand named colors (per README.md)
    readonly property color pinguoBlue:  "#007aff"
    readonly property color spaceBlack:  "#000000"
    readonly property color silverMist:  "#f5f5f7"
    readonly property color inkGray:     "#3a3a3c"
    readonly property color chartOrange: darkMode ? "#ff9f0a" : "#ff9500"

    // background
    readonly property color background50:  "#ffffff"
    readonly property color background100: "#f7f7fa"
    readonly property color background200: "#f2f2f7"
    readonly property color background300: "#e5e5ea"
    readonly property color background400: "#d1d1d6"
    readonly property color background500: "#aeaeb2"
    readonly property color background600: "#8e8e93"
    readonly property color background700: "#3a3a3c"
    readonly property color background800: "#1c1c1e"
    readonly property color background900: "#000000"

    // text
    readonly property color text50:  "#f5f5f7"
    readonly property color text100: "#e3e3e8"
    readonly property color text200: "#c7c7cc"
    readonly property color text300: "#aeaeb2"
    readonly property color text400: "#8e8e93"
    readonly property color text500: "#6e6e73"
    readonly property color text600: "#48484a"
    readonly property color text700: "#3c3c43"
    readonly property color text800: "#1d1d1f"
    readonly property color text900: "#000000"

    // icon
    readonly property color icon50:  "#f5f5f7"
    readonly property color icon100: "#e5e5ea"
    readonly property color icon200: "#d1d1d6"
    readonly property color icon300: "#c7c7cc"
    readonly property color icon400: "#aeaeb2"
    readonly property color icon500: "#8e8e93"
    readonly property color icon600: "#6e6e73"
    readonly property color icon700: "#48484a"
    readonly property color icon800: "#2c2c2e"
    readonly property color icon900: "#1d1d1f"

    // state — Apple System Green #34c759 for success (per Pinguo spec)
    readonly property color stateSuccess:          "#34c759"
    readonly property color stateSuccessDark:      "#30d158"
    readonly property color stateSuccessSurface:   "#e9f9ee"
    readonly property color stateSuccessForeground:"#ffffff"
    readonly property color stateError:            "#ff3b30"
    readonly property color stateErrorDark:        "#ff453a"
    readonly property color stateErrorSurface:     "#ffecea"
    readonly property color stateErrorForeground:  "#ffffff"

    // chart (Pinguo brand aligned, light/dark aware per colors_and_type.css)
    readonly property color chart1: darkMode ? stateSuccessDark : stateSuccess
    readonly property color chart2: darkMode ? brand400 : brand500
    readonly property color chart3: darkMode ? "#ff9f0a" : "#ff9500"
    readonly property color chart4: darkMode ? "#5e5ce6" : "#5856d6"
    readonly property color chart5: darkMode ? "#bf5af2" : "#af52de"

    // ═══════════════════════════════════════════════════════════════
    // SEMANTIC ROLES — light / dark / highContrast
    // ═══════════════════════════════════════════════════════════════

    // Surfaces
    readonly property color background: darkMode ? background900 : background50
    readonly property color foreground: darkMode ? text50 : text800
    readonly property color card:       darkMode ? background800 : background50
    readonly property color cardForeground: darkMode ? text50 : text800
    readonly property color popover:    darkMode ? background700 : background50
    readonly property color popoverForeground: darkMode ? text50 : text900

    // Actions / emphasis
    readonly property color primary: {
        if (_customPrimaryColor !== "") {
            return _customPrimaryColor;
        }
        return darkMode ? brand400 : brand500;
    }
    readonly property color primaryForeground: darkMode ? background900 : background50
    readonly property color secondary:       darkMode ? background800 : background200
    readonly property color secondaryForeground: darkMode ? text50 : text800
    readonly property color muted:           darkMode ? background800 : background200
    readonly property color mutedForeground: darkMode ? text400 : text400
    readonly property color accent:          darkMode ? background700 : background100
    readonly property color accentForeground: darkMode ? text50 : text800

    // Status
    readonly property color destructive:          darkMode ? stateErrorDark : stateError
    readonly property color destructiveForeground: stateErrorForeground
    readonly property color success:              darkMode ? stateSuccessDark : stateSuccess
    readonly property color successForeground:    stateSuccessForeground

    // Edges
    readonly property color border: darkMode ? background700 : background300
    readonly property color input:  darkMode ? background700 : background400
    readonly property color ring:   darkMode ? brand400 : brand500

    // Icon tints
    readonly property color icon:       darkMode ? icon50 : icon900
    readonly property color iconMuted:  darkMode ? icon500 : icon500

    // Sidebar surfaces (Pinguo semantic sidebar roles)
    readonly property color sidebar:              darkMode ? background800 : background200
    readonly property color sidebarForeground:    darkMode ? text50 : text800
    readonly property color sidebarPrimary:       darkMode ? brand400 : brand500
    readonly property color sidebarPrimaryForeground: darkMode ? background900 : background50
    readonly property color sidebarAccent:        darkMode ? background700 : background300
    readonly property color sidebarAccentForeground: darkMode ? text50 : text800
    readonly property color sidebarBorder:        darkMode ? background700 : background300
    readonly property color sidebarRing:          darkMode ? brand400 : brand500

    // Legacy Apple system color aliases (mapped to Pinguo/Apple primitives)
    // — chart-* values are light/dark aware per colors_and_type.css
    readonly property color systemBlue:   brand500
    readonly property color systemGreen:  stateSuccess
    readonly property color systemIndigo: darkMode ? "#5e5ce6" : "#5856d6"
    readonly property color systemOrange: chartOrange
    readonly property color systemPink:   "#ff2d55"
    readonly property color systemPurple: darkMode ? "#bf5af2" : "#af52de"
    readonly property color systemRed:    stateError
    readonly property color systemTeal:   "#5ac8d8"
    readonly property color systemYellow: "#ffcc00"

    readonly property color accentColor: primary

    // Apple HIG-compatible label aliases (mapped to Pinguo semantic foreground)
    readonly property color label:           foreground
    readonly property color secondaryLabel:  mutedForeground
    readonly property color tertiaryLabel:   Qt.alpha(mutedForeground, 0.72)
    readonly property color quaternaryLabel: Qt.alpha(mutedForeground, 0.48)

    // Apple HIG-compatible background aliases
    readonly property color systemBackground:              background
    readonly property color secondarySystemBackground:     secondary
    readonly property color tertiarySystemBackground:      accent
    readonly property color systemGroupedBackground:       background
    readonly property color secondarySystemGroupedBackground: card
    readonly property color tertiarySystemGroupedBackground:  accent

    // Apple HIG-compatible separator / fill aliases
    readonly property color separator:       Qt.alpha(border, 0.60)
    readonly property color opaqueSeparator: border
    readonly property color systemFill:      Qt.alpha(foreground, 0.18)
    readonly property color secondaryFill:   Qt.alpha(foreground, 0.14)
    readonly property color tertiaryFill:    Qt.alpha(foreground, 0.10)
    readonly property color quaternaryFill:  Qt.alpha(foreground, 0.06)

    // Apple HIG-compatible gray scale
    readonly property color systemGray:  text500
    readonly property color systemGray2: text400
    readonly property color systemGray3: text300
    readonly property color systemGray4: text200
    readonly property color systemGray5: text100
    readonly property color systemGray6: text50

    // Status aliases
    readonly property color warning: systemOrange

    // High-contrast overrides (only where it improves legibility)
    readonly property color hcForeground: highContrast ? (darkMode ? "#ffffff" : "#000000") : foreground
    readonly property color hcBackground: highContrast ? (darkMode ? "#000000" : "#ffffff") : background

    // ═══════════════════════════════════════════════════════════════
    // LAYOUT — Pinguo 0.24rem base (≈4px), expanded 10-step scale
    // ═══════════════════════════════════════════════════════════════
    readonly property int spacingBase: 4
    readonly property int spacing4:   4
    readonly property int spacing8:   8
    readonly property int spacing12:  12
    readonly property int spacing16:  16
    readonly property int spacing24:  24
    readonly property int spacing32:  32
    readonly property int spacing48:  48
    readonly property int spacing64:  64
    readonly property int spacing96:  96
    readonly property int spacing128: 128

    // Legacy HIG spacing aliases (mapped to Pinguo scale)
    readonly property int spacingXxs: spacing4
    readonly property int spacingXs:  spacing8
    readonly property int spacingS:   spacing12
    readonly property int spacingM:   spacing16
    readonly property int spacingL:   spacing24
    readonly property int spacingXl:  spacing32
    readonly property int spacingXxl: spacing48

    // ── Layout metrics ──
    readonly property int marginNarrow:   12
    readonly property int marginStandard: 16
    readonly property int marginWide:     24
    readonly property int minHitTarget:   44
    readonly property int sidebarMin:     160
    readonly property int sidebarMax:     280

    // ── Component sizing tokens (Pinguo component scale) ──
    readonly property int sizeButtonSmall:  40   // text / utility
    readonly property int sizeButtonMedium: 48   // secondary
    readonly property int sizeButtonLarge:  56   // primary hero
    readonly property int sizeListItemSmall:   40
    readonly property int sizeListItemMedium:  44
    readonly property int sizeListItemLarge:   48
    readonly property int sizeListItemXlarge:  56
    readonly property int sizeIconButtonSmall:  28
    readonly property int sizeIconButtonMedium: 32
    readonly property int sizeIconButtonLarge:  44
    readonly property int sizeToolbarButtonWidth:  64
    readonly property int sizeToolbarButtonHeight: 44
    readonly property int sizeTabBar: 32

    // ═══════════════════════════════════════════════════════════════
    // RADIUS — global 1.2rem (19.2px) + scale
    // ═══════════════════════════════════════════════════════════════
    readonly property real radius:       19.2
    readonly property real radiusSmall:  6
    readonly property real radiusMedium: 10
    readonly property real radiusLarge:  19.2
    readonly property real radiusXlarge: 24
    readonly property real radiusPill:   9999

    // ═══════════════════════════════════════════════════════════════
    // TYPOGRAPHY — DM Sans + JetBrains Mono
    // ═══════════════════════════════════════════════════════════════
    readonly property string fontSans: "DM Sans, ui-sans-serif, sans-serif, system-ui"
    readonly property string fontMono: "JetBrains Mono, monospace"

    // Tracking
    readonly property real trackingTight:  -0.04
    readonly property real trackingNormal:  0
    readonly property real trackingWide:    0.08
    readonly property real trackingLabel:   0.12

    // Type scale
    readonly property int typeCaption2: 11
    readonly property int typeCaption1: 12
    readonly property int typeFootnote: 13
    readonly property int typeSubhead:  14
    readonly property int typeBody:     15
    readonly property int typeHeadline: 17
    readonly property int typeTitle3:   20
    readonly property int typeTitle2:   22
    readonly property int typeTitle1:   28
    readonly property int typeLargeTitle: 34
    readonly property int typeDisplay:    72

    // Line heights (Pinguo spec)
    readonly property real displayLineHeight: 0.92   // hero display
    readonly property real bodyLineHeight:    1.55   // body copy
    readonly property real headlineLineHeight: 1.15  // card titles

    // Standard font weights
    readonly property int weightRegular:  Font.Normal
    readonly property int weightMedium:   Font.Medium
    readonly property int weightSemibold: Font.DemiBold
    readonly property int weightBold:     Font.Bold

    // ═══════════════════════════════════════════════════════════════
    // MATERIAL — opaque semantic surface tiers (Pinguo)
    // ═══════════════════════════════════════════════════════════════
    //   base     — primary window surface (background)
    //   elevated — raised card / panel (card)
    //   overlay  — popovers, menus, sheets (popover)
    //   vibrant  — sidebars / headers that sit between layers (secondary)
    readonly property color materialBase:     background
    readonly property color materialElevated: card
    readonly property color materialOverlay:  popover
    readonly property color materialVibrant:  secondary

    // Hairline border: structural 1px edge.
    // Pinguo spec: "1px borders to define edges before reaching for shadow."
    // On accent/secondary surfaces where border and background could be identical,
    // this ensures edges remain structurally visible.
    readonly property color hairline: border
    readonly property color hairlineOnAccent: Qt.alpha(foreground, darkMode ? 0.08 : 0.06)

    // ═══════════════════════════════════════════════════════════════
    // SHADOW TOKENS — quiet elevation (colors only; apply via DropShadow)
    // ═══════════════════════════════════════════════════════════════
    // Pinguo composite shadows (per colors_and_type.css):
    //   shadow-sm  (Card)  : 2 layers → 0 1px 2px + 0 1px 3px -1px  @0.05
    //   shadow-md  (Hover) : 2 layers → 0 4px 8px -2px + 0 2px 4px -2px @0.06/0.05
    //   shadow-lg  (Float) : 2 layers → 0 8px 24px -8px + 0 4px 8px -4px @0.08/0.05
    //   shadow-xl  (Overlay): 2 layers → 0 16px 40px -10px + 0 8px 16px -8px @0.10/0.06
    //   shadow-2xl (Modal)  : 1 layer  → 0 24px 64px -12px @0.12
    // QML DropShadow supports one layer; multi-layer shadows require
    // stacking multiple DropShadow items in the component.
    readonly property color shadowColor: darkMode ? "#000000" : "#000000"
    readonly property real  shadowOpacityHairline: darkMode ? 0.30 : 0.04
    readonly property real  shadowOpacitySubtle:   darkMode ? 0.30 : 0.04
    readonly property real  shadowOpacityCard:     darkMode ? 0.36 : 0.05
    readonly property real  shadowOpacityRaised:   darkMode ? 0.40 : 0.06
    readonly property real  shadowOpacityHover:    darkMode ? 0.44 : 0.06
    readonly property real  shadowOpacityFloat:    darkMode ? 0.50 : 0.08
    readonly property real  shadowOpacityOverlay:  darkMode ? 0.55 : 0.10
    readonly property real  shadowOpacityModal:    darkMode ? 0.60 : 0.12

    // Shadow blur radii (Pinguo whisper-light: small at rest, larger on hover)
    readonly property real shadowRadiusDefault: 4.0
    readonly property real shadowRadiusHover:   12.0

    // ═══════════════════════════════════════════════════════════════
    // MOTION — duration + easing tokens (mirrored in Motion.qml)
    // ═══════════════════════════════════════════════════════════════
    // Pinguo timing: 150ms / 250ms / 350ms (per SKILL.md guideline)
    // Easing: cubic-bezier(0.32, 0.72, 0, 1) — Pinguo custom curve
    //   with strong initial velocity and gentle settle.
    //   Qt 6.0+ BezierSpline: control points match Pinguo spec exactly.
    //   Edge: BezierSpline was added in Qt 6.0; on Qt 5.15 the closest
    //   fallback is OutCubic (0.33, 0.00, 0.67, 1.00).
    readonly property int motionShort:   150
    readonly property int motionMedium:  250
    readonly property int motionLong:    350

    readonly property int motionStandard:    Easing.OutCubic
    readonly property int motionDecelerate:  Easing.OutCubic
    readonly property int motionAccelerate:  Easing.InCubic

    // Pinguo custom bezier curve as an array [x1,y1,x2,y2] for use with
    // Qt 6 BezierSpline easing type. Qt6 can consume this directly:
    //   easing.type: Easing.BezierSpline
    //   easing.bezierCurve: Theme.motionPinguoBezier
    // Qt 5.15 falls back to Easing.OutCubic (no BezierSpline).
    readonly property var motionPinguoBezier: [0.32, 0.72, 0, 1]

    // ── Setters called from QML to sync with Rust backend ──
    function setDarkMode(mode) {
        _darkMode = mode;
    }

    function setCustomPrimaryColor(color) {
        _customPrimaryColor = color;
    }
}
