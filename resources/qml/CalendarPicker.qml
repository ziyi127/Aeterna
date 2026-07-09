import QtQuick 2.15
import "."
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

// =====================================================================
// CalendarPicker — compact date picker popup for datetime fields
// =====================================================================
// Opens below its parent and lets the user pick a date. The existing
// time portion of the bound value is preserved.
// =====================================================================

Popup {
    id: root

    property string currentText: ""

    signal dateSelected(string dateText)

    padding: Theme.spacing12
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    background: Rectangle {
        color: Theme.materialOverlay
        radius: Theme.radiusLarge
        border.color: Theme.hairline
        border.width: 1
    }

    

    readonly property var months: ["1月", "2月", "3月", "4月", "5月", "6月",
                                     "7月", "8月", "9月", "10月", "11月", "12月"]

    function parseDate(str) {
        var parts = str.match(/(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})/)
        if (!parts) return new Date()
        return new Date(parseInt(parts[1], 10),
                        parseInt(parts[2], 10) - 1,
                        parseInt(parts[3], 10),
                        parseInt(parts[4], 10),
                        parseInt(parts[5], 10),
                        parseInt(parts[6], 10))
    }

    function formatDateTime(d, originalText) {
        var pad = function(n) { return n < 10 ? "0" + n : n }
        var timePart = "00:00:00"
        var t = originalText.match(/(\d{2}):(\d{2}):(\d{2})/)
        if (t) {
            timePart = t[1] + ":" + t[2] + ":" + t[3]
        }
        return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate()) + " " + timePart
    }

    onOpened: {
        var d = parseDate(currentText)
        calendarModel.year = d.getFullYear()
        calendarModel.month = d.getMonth()
    }

    ColumnLayout {
        spacing: Theme.spacing12

        // Header: month/year navigation
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing8

            PinguoButton {
                variant: PinguoButton.Text
                text: "<"
                onClicked: calendarModel.prevMonth()
            }

            Text {
                text: calendarModel.year + "年" + root.months[calendarModel.month]
                color: Theme.foreground
                font.pixelSize: Theme.typeSubhead
                font.weight: Theme.weightSemibold
                font.family: Theme.fontSans
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
            }

            PinguoButton {
                variant: PinguoButton.Text
                text: ">"
                onClicked: calendarModel.nextMonth()
            }
        }

        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: Theme.hairline
        }

        // Day of week header
        RowLayout {
            Layout.fillWidth: true
            spacing: 0
            Repeater {
                model: ["日", "一", "二", "三", "四", "五", "六"]
                delegate: Text {
                    text: modelData
                    color: Theme.mutedForeground
                    font.pixelSize: Theme.typeCaption1
                    font.weight: Theme.weightMedium
                    font.family: Theme.fontSans
                    Layout.preferredWidth: 28
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }

        // Day grid
        GridLayout {
            id: dayGrid
            columns: 7
            rowSpacing: Theme.spacing8
            columnSpacing: Theme.spacing8

            Repeater {
                model: cellsModel
                delegate: Rectangle {
                    Layout.preferredWidth: 28
                    Layout.preferredHeight: 28
                    radius: Theme.radiusSmall
                    color: model.isCurrentMonth
                           ? (model.selected
                              ? Qt.alpha(Theme.primary, 0.18)
                              : (dayMouse.containsMouse
                                 ? Qt.alpha(Theme.primary, 0.08)
                                 : "transparent"))
                           : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: model.day
                        color: model.isCurrentMonth ? Theme.foreground : Theme.mutedForeground
                        font.pixelSize: Theme.typeCaption1
                        font.weight: model.selected ? Theme.weightSemibold : Theme.weightRegular
                        font.family: Theme.fontSans
                    }

                    MouseArea {
                        id: dayMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            var d = new Date(calendarModel.year, calendarModel.month, model.day)
                            root.dateSelected(root.formatDateTime(d, root.currentText))
                            root.close()
                        }
                    }
                }
            }
        }
    }

    // CalendarModel builds 42 cells for the current month view
    QtObject {
        id: calendarModel
        property int year: new Date().getFullYear()
        property int month: new Date().getMonth()
        property int count: 42

        function prevMonth() {
            if (month === 0) {
                month = 11
                year--
            } else {
                month--
            }
        }

        function nextMonth() {
            if (month === 11) {
                month = 0
                year++
            } else {
                month++
            }
        }
    }

    // Build 42 cells covering the month view.
    // Since we cannot subclass QAbstractListModel easily, we use a Repeater with
    // a small ListModel that is rebuilt whenever year/month changes.
    ListModel {
        id: cellsModel
    }

    function rebuildCells() {
        cellsModel.clear()
        var firstDay = new Date(calendarModel.year, calendarModel.month, 1)
        var startOffset = firstDay.getDay()
        var startDate = new Date(calendarModel.year, calendarModel.month, 1 - startOffset)
        var current = parseDate(root.currentText)
        for (var i = 0; i < 42; i++) {
            var cellDate = new Date(startDate.getTime() + i * 86400000)
            var inMonth = cellDate.getMonth() === calendarModel.month
            var selected = inMonth &&
                           cellDate.getFullYear() === current.getFullYear() &&
                           cellDate.getMonth() === current.getMonth() &&
                           cellDate.getDate() === current.getDate()
            cellsModel.append({
                day: cellDate.getDate(),
                isCurrentMonth: inMonth,
                selected: selected
            })
        }
    }

    Connections {
        target: calendarModel
        function onYearChanged() { rebuildCells() }
        function onMonthChanged() { rebuildCells() }
    }

    onCurrentTextChanged: rebuildCells()
    Component.onCompleted: rebuildCells()
}
