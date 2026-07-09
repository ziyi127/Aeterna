import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "."

// =====================================================================
// PinguoSpinBox — Pinguo-styled numeric input with stepper
// =====================================================================
// PinguoTextField with decrement/increment PinguoButtons on the sides.
// Uses theme tokens, pill-shaped, DM Sans, 0.18s transitions.
// =====================================================================

Item {
    id: root

    property int value: 0
    property int from: 0
    property int to: 100
    property int stepSize: 1
    property bool small: false

    // Emitted only on user interaction (button clicks / typed text),
    // not on programmatic value assignments — mirrors QtQuick.Controls SpinBox.
    signal valueModified()

    activeFocusOnTab: true

    implicitWidth: 140
    implicitHeight: root.small ? Theme.sizeButtonSmall : Theme.sizeButtonMedium

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ── Decrement button ──
        PinguoButton {
            id: decBtn
            text: "−"
            variant: PinguoButton.Text
            enabled: root.enabled && root.value > root.from
            implicitWidth: 36
            implicitHeight: root.height
            onClicked: {
                root.value = Math.max(root.from, root.value - root.stepSize)
                root.valueModified()
            }
        }

        // ── Value display/input ──
        PinguoTextField {
            id: valueField
            Layout.fillWidth: true
            Layout.preferredHeight: root.height
            small: root.small
            text: root.value.toString()
            enabled: root.enabled
            inputItem.validator: IntValidator { bottom: root.from; top: root.to }
            inputItem.horizontalAlignment: TextInput.AlignHCenter
            inputItem.selectByMouse: true
            onTextChanged: {
                var num = parseInt(text)
                if (!isNaN(num) && num >= root.from && num <= root.to) {
                    if (root.value !== num) {
                        root.value = num
                        root.valueModified()
                    }
                }
            }
        }

        // ── Increment button ──
        PinguoButton {
            id: incBtn
            text: "+"
            variant: PinguoButton.Text
            enabled: root.enabled && root.value < root.to
            implicitWidth: 36
            implicitHeight: root.height
            onClicked: {
                root.value = Math.min(root.to, root.value + root.stepSize)
                root.valueModified()
            }
        }
    }
}
