import QtQuick 2.15
import "."
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

// =====================================================================
// ValidationPanel — Displays validation errors/warnings from the editor
// =====================================================================
// Parses `reportJson` (EditorBackend.validation_report_json) and renders
// a list of issues. Each item is clickable and emits `jumpTo`.
// =====================================================================

Item {
    id: root

    property string reportJson: ""
    property bool showTitle: true
    signal jumpTo(int examIndex, string field)

    

    readonly property var report: {
        if (!reportJson || reportJson.length === 0) return { errors: [], warnings: [] };
        try {
            return JSON.parse(reportJson);
        } catch (e) {
            return { errors: [], warnings: [] };
        }
    }

    readonly property var issueList: {
        var issues = [];
        var i;
        var list = report.errors || [];
        for (i = 0; i < list.length; ++i) {
            issues.push({
                type: "error",
                examIndex: list[i].examIndex !== undefined ? list[i].examIndex : -1,
                field: list[i].field || "",
                message: list[i].message || ""
            });
        }
        list = report.warnings || [];
        for (i = 0; i < list.length; ++i) {
            issues.push({
                type: "warning",
                examIndex: list[i].examIndex !== undefined ? list[i].examIndex : -1,
                field: list[i].field || "",
                message: list[i].message || ""
            });
        }
        return issues;
    }

    implicitWidth: 280

    Material {
        anchors.fill: parent
        tier: Material.Elevated
        radius: Theme.radiusLarge
    }

    Flickable {
        anchors.fill: parent
        anchors.margins: Theme.spacing24
        contentWidth: contentColumn.width
        contentHeight: contentColumn.implicitHeight
        clip: true
        ScrollBar.vertical: ScrollBar {
        contentItem: Rectangle {
            implicitWidth: 6
            radius: 3
            color: Qt.alpha(Theme.foreground, 0.24)
        }
    }

        ColumnLayout {
            id: contentColumn
            width: parent.width
            spacing: Theme.spacing16

            Text {
                text: "问题"
                visible: root.showTitle
                color: Theme.foreground
                font.family: Theme.fontSans
                font.pixelSize: Theme.typeSubhead
                font.weight: Theme.weightSemibold
            }

            Text {
                visible: issueList.length === 0
                text: "无问题"
                color: Theme.mutedForeground
                font.family: Theme.fontSans
                font.pixelSize: Theme.typeBody
                Layout.fillWidth: true
            }

            ColumnLayout {
                visible: issueList.length > 0
                spacing: Theme.spacing8
                Layout.fillWidth: true

                Repeater {
                    model: issueList

                    Rectangle {
                        Layout.fillWidth: true
                        height: Theme.sizeListItemSmall
                        radius: Theme.radiusMedium
                        color: issueMouse.containsPress
                            ? Qt.alpha(Theme.foreground, 0.12)
                            : (issueMouse.containsMouse ? Qt.alpha(Theme.foreground, 0.06) : Qt.alpha(Theme.foreground, 0))

                        Behavior on color {
                            ColorAnimation { duration: Theme.motionShort; easing.type: Theme.motionStandard }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.spacing12
                            anchors.rightMargin: Theme.spacing12
                            spacing: Theme.spacing12

                            Icon {
                                name: modelData.type === "error" ? "xmark" : "exclamationmark.triangle"
                                size: 20
                                tier: modelData.type === "error" ? Icon.Danger : Icon.Warning
                            }

                            Text {
                                text: modelData.message
                                color: Theme.foreground
                                font.family: Theme.fontSans
                                font.pixelSize: Theme.typeBody
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }

                        MouseArea {
                            id: issueMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.jumpTo(modelData.examIndex, modelData.field)
                        }
                    }
                }
            }
        }
    }
}
