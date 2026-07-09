pragma Singleton
import QtQuick 2.15

// =====================================================================
// T — condensed text styling for Pinguo Design System
// =====================================================================
// Eliminates repetitive `font.family: Theme.fontSans` / `font.weight`
// / `color: Theme.foreground` across hundreds of Text items.
// Usage: T { text: "Hello"; type: "headline" }
// =====================================================================

QtObject {
    // ── Factory functions that return property bags ──
    // Use as: font: T.sans("body")
    function sans(style, extra) {
        var s = extra || {}
        switch (style) {
            case "display":     return Object.assign({family: Theme.fontSans, pixelSize: Theme.typeDisplay,    weight: Theme.weightBold,     letterSpacing: Theme.trackingTight * 72}, s)
            case "largeTitle":  return Object.assign({family: Theme.fontSans, pixelSize: Theme.typeLargeTitle, weight: Theme.weightBold}, s)
            case "title1":      return Object.assign({family: Theme.fontSans, pixelSize: Theme.typeTitle1,     weight: Theme.weightBold}, s)
            case "title2":      return Object.assign({family: Theme.fontSans, pixelSize: Theme.typeTitle2,     weight: Theme.weightBold}, s)
            case "title3":      return Object.assign({family: Theme.fontSans, pixelSize: Theme.typeTitle3,     weight: Theme.weightSemibold}, s)
            case "headline":    return Object.assign({family: Theme.fontSans, pixelSize: Theme.typeHeadline,   weight: Theme.weightSemibold}, s)
            case "body":        return Object.assign({family: Theme.fontSans, pixelSize: Theme.typeBody,       weight: Theme.weightRegular}, s)
            case "subhead":     return Object.assign({family: Theme.fontSans, pixelSize: Theme.typeSubhead,    weight: Theme.weightRegular}, s)
            case "footnote":    return Object.assign({family: Theme.fontSans, pixelSize: Theme.typeFootnote,   weight: Theme.weightRegular}, s)
            case "caption1":    return Object.assign({family: Theme.fontSans, pixelSize: Theme.typeCaption1,   weight: Theme.weightRegular}, s)
            case "caption2":    return Object.assign({family: Theme.fontSans, pixelSize: Theme.typeCaption2,   weight: Theme.weightRegular}, s)
            default:            return Object.assign({family: Theme.fontSans, pixelSize: Theme.typeBody,       weight: Theme.weightRegular}, s)
        }
    }

    function mono(style, extra) {
        var s = extra || {}
        return Object.assign({family: Theme.fontMono, pixelSize: s.pixelSize || Theme.typeSubhead, weight: Theme.weightRegular}, s)
    }
}
