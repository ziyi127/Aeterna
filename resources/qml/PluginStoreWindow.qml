import QtQuick 2.15
import "."
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Aeterna 1.0

ApplicationWindow {
    id: pluginInventoryWindow
    width: 800
    height: 600
    minimumWidth: 680
    minimumHeight: 440
    title: "已安装插件 - Aeterna"
    color: Theme.surfaceBase

    property string searchText: ""
    property bool diagnosticsExpanded: false

    PluginManagerBackend {
        id: pluginBackend
        onPlugins_jsonChanged: pluginInventoryWindow.populatePlugins()
        onDiagnostics_jsonChanged: pluginInventoryWindow.populateDiagnostics()
    }

    ListModel { id: pluginListModel }
    ListModel { id: diagnosticsModel }

    function populatePlugins() {
        try {
            var plugins = JSON.parse(pluginBackend.plugins_json)
            pluginListModel.clear()
            for (var i = 0; i < plugins.length; ++i) {
                var plugin = plugins[i]
                var matches = searchText === ""
                    || plugin.name.toLowerCase().indexOf(searchText) >= 0
                    || plugin.description.toLowerCase().indexOf(searchText) >= 0
                    || plugin.author.toLowerCase().indexOf(searchText) >= 0
                if (matches)
                    pluginListModel.append(plugin)
            }
        } catch (e) {
            pluginListModel.clear()
        }
    }

    function populateDiagnostics() {
        try {
            var diagnostics = JSON.parse(pluginBackend.diagnostics_json)
            diagnosticsModel.clear()
            for (var i = 0; i < diagnostics.length; ++i)
                diagnosticsModel.append({ message: diagnostics[i] })
        } catch (e) {
            diagnosticsModel.clear()
        }
    }

    function refreshInventory() {
        pluginBackend.refresh()
    }

    Component.onCompleted: refreshInventory()

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacing24
        spacing: Theme.spacing16

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing16

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.spacing4

                Text {
                    text: "已安装插件"
                    font.pixelSize: Theme.typeTitle2
                    font.weight: Theme.weightBold
                    font.family: Theme.fontSans
                    color: Theme.foreground
                }
                Text {
                    text: "实验性：仅显示本地插件清单；插件不会被加载或执行。"
                    font.pixelSize: Theme.typeFootnote
                    font.family: Theme.fontSans
                    color: Theme.warning
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
            }

            PinguoTextField {
                id: searchField
                Layout.preferredWidth: 250
                leadingIcon: "magnifyingglass"
                placeholderText: "筛选本地清单"
                onTextChanged: {
                    pluginInventoryWindow.searchText = text.toLowerCase()
                    pluginInventoryWindow.populatePlugins()
                }
            }

            PinguoButton {
                text: "刷新本地清单"
                icon: "arrow.uturn.forward"
                variant: PinguoButton.Secondary
                onClicked: pluginInventoryWindow.refreshInventory()
            }
        }

        Material {
            Layout.fillWidth: true
            Layout.preferredHeight: pluginDirectoryText.implicitHeight + Theme.spacing16 * 2
            tier: Material.Elevated
            radius: Theme.radiusMedium

            Text {
                id: pluginDirectoryText
                anchors.fill: parent
                anchors.margins: Theme.spacing16
                text: "扫描目录：" + pluginBackend.plugin_directory + "\n目录不会由 Aeterna 自动创建。"
                font.pixelSize: Theme.typeFootnote
                font.family: Theme.fontMono
                color: Theme.mutedForeground
                wrapMode: Text.WordWrap
            }
        }

        Material {
            Layout.fillWidth: true
            Layout.fillHeight: true
            tier: Material.Elevated
            radius: Theme.radiusLarge

            ListView {
                id: pluginListView
                anchors.fill: parent
                anchors.margins: Theme.spacing16
                model: pluginListModel
                spacing: Theme.spacing12
                clip: true

                delegate: Material {
                    width: ListView.view.width
                    implicitHeight: cardContent.implicitHeight + Theme.spacing16 * 2
                    tier: Material.Base
                    radius: Theme.radiusMedium

                    RowLayout {
                        id: cardContent
                        anchors.fill: parent
                        anchors.margins: Theme.spacing16
                        spacing: Theme.spacing16

                        Rectangle {
                            Layout.preferredWidth: Theme.sizeButtonLarge
                            Layout.preferredHeight: Theme.sizeButtonLarge
                            radius: Theme.radiusMedium
                            color: Qt.alpha(Theme.primary, 0.18)
                            Icon {
                                anchors.centerIn: parent
                                name: "puzzle"
                                size: 24
                                tier: Icon.Accent
                                Accessible.ignored: true
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacing4
                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    text: name
                                    Layout.fillWidth: true
                                    font.pixelSize: Theme.typeHeadline
                                    font.weight: Theme.weightSemibold
                                    font.family: Theme.fontSans
                                    color: Theme.foreground
                                    elide: Text.ElideRight
                                }
                                Text {
                                    text: "v" + version
                                    font.pixelSize: Theme.typeCaption1
                                    font.family: Theme.fontMono
                                    color: Theme.mutedForeground
                                }
                            }
                            Text {
                                text: description || "未提供描述"
                                Layout.fillWidth: true
                                font.pixelSize: Theme.typeSubhead
                                font.family: Theme.fontSans
                                color: Theme.mutedForeground
                                wrapMode: Text.WordWrap
                            }
                            Text {
                                text: "作者：" + (author || "未提供") + " · 类型：" + type
                                Layout.fillWidth: true
                                font.pixelSize: Theme.typeCaption1
                                font.family: Theme.fontSans
                                color: Theme.mutedForeground
                                elide: Text.ElideMiddle
                            }
                            Text {
                                text: path
                                Layout.fillWidth: true
                                font.pixelSize: Theme.typeCaption2
                                font.family: Theme.fontMono
                                color: Theme.tertiaryLabel
                                elide: Text.ElideMiddle
                            }
                        }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    width: parent.width - Theme.spacing32
                    visible: pluginListModel.count === 0
                    text: searchText === ""
                        ? "未发现本地插件清单\n可将 manifest.json 放入上述目录的插件子目录中；Aeterna 不会自动创建该目录。"
                        : "没有与筛选条件匹配的本地插件清单。"
                    font.pixelSize: Theme.typeSubhead
                    font.family: Theme.fontSans
                    color: Theme.mutedForeground
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: diagnosticsModel.count > 0
            spacing: Theme.spacing8

            PinguoButton {
                text: "发现 " + diagnosticsModel.count + " 个清单问题"
                icon: "exclamationmark.triangle"
                variant: PinguoButton.Text
                showTrailingArrow: true
                onClicked: diagnosticsExpanded = !diagnosticsExpanded
            }

            Material {
                Layout.fillWidth: true
                visible: diagnosticsExpanded
                implicitHeight: diagnosticsColumn.implicitHeight + Theme.spacing12 * 2
                tier: Material.Overlay
                radius: Theme.radiusMedium

                ColumnLayout {
                    id: diagnosticsColumn
                    anchors.fill: parent
                    anchors.margins: Theme.spacing12
                    spacing: Theme.spacing8
                    Repeater {
                        model: diagnosticsModel
                        delegate: Text {
                            Layout.fillWidth: true
                            text: "• " + message
                            font.pixelSize: Theme.typeFootnote
                            font.family: Theme.fontSans
                            color: Theme.warning
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Item { Layout.fillWidth: true }
            PinguoButton {
                text: "关闭"
                variant: PinguoButton.Secondary
                onClicked: pluginInventoryWindow.close()
            }
        }
    }
}
