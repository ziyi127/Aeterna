import QtQuick 2.15
import "."
import QtQuick.Layouts 1.15

// =====================================================================
// ResizableSplitter — draggable splitter for VS Code-style layouts
// =====================================================================
// Supports both vertical (left/right panels) and horizontal (top/bottom
// panels) orientations. The splitter exposes a `value` property that the
// adjacent panel binds to (e.g. Layout.preferredWidth / preferredHeight).
//
// Visual: 1 px Theme.hairline base; on hover the active track grows and
// tints with accent color at 30 % opacity.
// =====================================================================

Item {
    id: root

    property int orientation: Qt.Vertical
    property int minValue: 0
    property int maxValue: 9999
    property int value: 200

    property bool hovered: mouseArea.containsMouse || mouseArea.pressed

    

    // Layout geometry: 1 px base line, hit target extends 6 px for easier
    // grabbing without consuming extra layout space.
    Layout.preferredWidth: orientation === Qt.Vertical ? 1 : -1
    Layout.preferredHeight: orientation === Qt.Horizontal ? 1 : -1
    Layout.fillWidth: orientation === Qt.Horizontal
    Layout.fillHeight: orientation === Qt.Vertical

    // Internal drag state
    property real _pressValue: 0
    property real _pressGlobalPos: 0

    // Visible 1 px hairline
    Rectangle {
        id: baseLine
        anchors.centerIn: parent
        width: orientation === Qt.Vertical ? 1 : parent.width
        height: orientation === Qt.Horizontal ? 1 : parent.height
        color: Theme.hairline
    }

    // Hover / pressed feedback: slightly wider accent track
    Rectangle {
        id: activeTrack
        anchors.centerIn: parent
        width: orientation === Qt.Vertical
               ? (root.hovered ? 4 : 1)
               : parent.width
        height: orientation === Qt.Horizontal
                ? (root.hovered ? 4 : 1)
                : parent.height
        color: Qt.alpha(Theme.primary, 0.3)
        opacity: root.hovered ? 1 : 0
        radius: orientation === Qt.Vertical ? 2 : 0

        Behavior on opacity {
            NumberAnimation { duration: Theme.motionShort; easing.type: Theme.motionStandard }
        }
    }

    // Extended hit area so the 1 px line is still easy to grab.
    MouseArea {
        id: mouseArea
        x: orientation === Qt.Vertical ? -3 : 0
        y: orientation === Qt.Horizontal ? -3 : 0
        width: orientation === Qt.Vertical ? parent.width + 6 : parent.width
        height: orientation === Qt.Horizontal ? parent.height + 6 : parent.height
        hoverEnabled: true
        cursorShape: orientation === Qt.Vertical
                     ? Qt.SplitHCursor
                     : Qt.SplitVCursor

        onPressed: {
            root._pressValue = root.value
            var g = mouseArea.mapToGlobal(mouse.x, mouse.y)
            root._pressGlobalPos = orientation === Qt.Vertical ? g.x : g.y
        }

        onPositionChanged: {
            if (!pressed) return
            var g = mouseArea.mapToGlobal(mouse.x, mouse.y)
            var pos = orientation === Qt.Vertical ? g.x : g.y
            var delta = pos - root._pressGlobalPos
            var newValue = root._pressValue + delta
            root.value = Math.max(root.minValue, Math.min(root.maxValue, newValue))
        }
    }
}
