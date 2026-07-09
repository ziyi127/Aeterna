import QtQuick 2.15
import "."
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Aeterna 1.0

ApplicationWindow {
    id: pluginStoreWindow
    width: 800
    height: 600
    minimumWidth: 700
    minimumHeight: 450
    title: "插件商店 - Aeterna"
    color: Theme.materialBase

    

    property string searchText: ""
    property var installedPlugins: []

    AppInfo { id: appInfo }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacing24
        spacing: Theme.spacing16

        // Header
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing16

            Text {
                text: "插件商店"
                font.pixelSize: Theme.typeTitle2
                font.weight: Theme.weightBold
                font.family: Theme.fontSans
                color: Theme.foreground
            }

            Item { Layout.fillWidth: true }

            // Search bar
            PinguoTextField {
                id: searchField
                Layout.preferredWidth: 280
                leadingIcon: "magnifyingglass"
                placeholderText: "搜索插件..."
                onTextChanged: {
                    pluginStoreWindow.searchText = text.toLowerCase()
                }
            }
        }

        // Plugin list
        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ListView {
                id: pluginListView
                anchors.fill: parent
                model: pluginListModel
                spacing: Theme.spacing12

                delegate: Rectangle {
                    id: pluginCard
                    width: ListView.view.width
                    height: pluginCardLayout.implicitHeight + Theme.spacing32
                    color: Theme.materialElevated
                    radius: Theme.radiusLarge
                    border.color: Theme.hairline
                    border.width: 1

                    Behavior on color {
                        ColorAnimation { duration: Theme.motionShort; easing.type: Theme.motionStandard }
                    }

                    RowLayout {
                        id: pluginCardLayout
                        anchors.fill: parent
                        anchors.margins: Theme.spacing24
                        spacing: Theme.spacing24

                        // Plugin icon
                        Rectangle {
                            Layout.preferredWidth: 56
                            Layout.preferredHeight: 56
                            radius: Theme.radiusMedium
                            color: Qt.alpha(Theme.primary, 0.18)

                            Icon {
                                anchors.centerIn: parent
                                name: icon || "puzzle"
                                size: 24
                                tier: Icon.Accent
                            }
                        }

                        // Plugin info
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: Theme.spacing8

                            RowLayout {
                                spacing: Theme.spacing12

                                Text {
                                    text: name
                                    font.pixelSize: Theme.typeBody
                                    font.weight: Theme.weightSemibold
                                    font.family: Theme.fontSans
                                    color: Theme.foreground
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }

                                Rectangle {
                                    Layout.preferredHeight: 20
                                    Layout.minimumWidth: 40
                                    implicitWidth: badgeText.implicitWidth + Theme.spacing16
                                    radius: Theme.radiusPill
                                    color: installed ? Theme.success : Theme.primary

                                    Text {
                                        id: badgeText
                                        anchors.centerIn: parent
                                        text: installed ? "已安装" : "v" + version
                                        font.pixelSize: Theme.typeCaption2
                                        font.family: Theme.fontSans
                                        color: installed ? Theme.successForeground : Theme.primaryForeground
                                    }
                                }
                            }

                            Text {
                                text: description
                                font.pixelSize: Theme.typeSubhead
                                font.family: Theme.fontSans
                                color: Theme.mutedForeground
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                            }

                            RowLayout {
                                spacing: Theme.spacing24
                                Layout.topMargin: Theme.spacing8

                                RowLayout {
                                    spacing: Theme.spacing8
                                    Icon {
                                        name: "star"
                                        size: 16
                                        tier: Icon.Warning
                                        accessibleName: "评分 " + rating.toFixed(1)
                                        Layout.alignment: Qt.AlignVCenter
                                    }
                                    Text {
                                        text: rating.toFixed(1)
                                        font.pixelSize: Theme.typeCaption1
                                        font.family: Theme.fontSans
                                        color: Theme.warning
                                    }
                                }

                                RowLayout {
                                    spacing: Theme.spacing8
                                    Icon {
                                        name: "arrow.down.circle"
                                        size: 16
                                        tier: Icon.Tertiary
                                        accessibleName: "下载量 " + formatDownloads(downloads)
                                        Layout.alignment: Qt.AlignVCenter
                                    }
                                    Text {
                                        text: formatDownloads(downloads)
                                        font.pixelSize: Theme.typeCaption1
                                        font.family: Theme.fontSans
                                        color: Theme.mutedForeground
                                    }
                                }

                                Text {
                                    text: "作者: " + author
                                    font.pixelSize: Theme.typeCaption1
                                    font.family: Theme.fontSans
                                    color: Theme.mutedForeground
                                }
                            }
                        }

                        // Action buttons
                        ColumnLayout {
                            Layout.alignment: Qt.AlignVCenter
                            spacing: Theme.spacing8

                            PinguoButton {
                                id: installButton
                                text: installed ? "卸载" : "安装"
                                variant: installed ? PinguoButton.Secondary : PinguoButton.Primary
                                Layout.preferredWidth: 80
                                onClicked: {
                                    if (installed) {
                                        uninstallPlugin(name)
                                    } else {
                                        installPlugin(name)
                                    }
                                }
                            }

                            PinguoButton {
                                id: detailButton
                                text: "详情"
                                variant: PinguoButton.Secondary
                                Layout.preferredWidth: 80
                                onClicked: {
                                    showPluginDetail(name, description, author, version, rating, downloads, compatibleVersion)
                                }
                            }
                        }
                    }
                }
            }
        }

        // Bottom bar
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Theme.hairline
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing16

            Text {
                text: "共 " + filteredCount + " 个插件"
                font.pixelSize: Theme.typeSubhead
                font.family: Theme.fontSans
                color: Theme.mutedForeground
            }

            Item { Layout.fillWidth: true }

            PinguoButton {
                id: refreshButton
                text: "刷新"
                variant: PinguoButton.Text
                onClicked: refreshStore()
            }

            PinguoButton {
                id: closeButton
                text: "关闭"
                variant: PinguoButton.Primary
                onClicked: pluginStoreWindow.close()
            }
        }
    }

    // Plugin detail dialog (HIG Material.Overlay)
    Dialog {
        id: detailDialog
        title: "插件详情"
        width: 450
        height: 350
        standardButtons: Dialog.Close
        anchors.centerIn: parent
        padding: Theme.spacing24

        background: Rectangle {
            color: Theme.materialOverlay
            radius: Theme.radiusLarge
            border.color: Theme.hairline
            border.width: 1
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: Theme.spacing16

            Text {
                id: detailName
                font.pixelSize: Theme.typeHeadline
                font.weight: Theme.weightBold
                font.family: Theme.fontSans
                color: Theme.foreground
            }

            Text {
                id: detailDescription
                font.pixelSize: Theme.typeSubhead
                font.family: Theme.fontSans
                color: Theme.mutedForeground
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
            }

            RowLayout {
                spacing: Theme.spacing24

                Text {
                    id: detailVersionText
                    font.pixelSize: Theme.typeSubhead
                    font.family: Theme.fontSans
                    color: Theme.mutedForeground
                }

                Text {
                    id: detailAuthorText
                    font.pixelSize: Theme.typeSubhead
                    font.family: Theme.fontSans
                    color: Theme.mutedForeground
                }
            }

            RowLayout {
                spacing: Theme.spacing24

                RowLayout {
                    spacing: Theme.spacing8
                    Icon {
                        name: "star"
                        size: 16
                        tier: Icon.Warning
                        Layout.alignment: Qt.AlignVCenter
                    }
                    Text {
                        id: detailRating
                        font.pixelSize: Theme.typeSubhead
                        font.family: Theme.fontSans
                        color: Theme.warning
                    }
                }

                Text {
                    id: detailDownloads
                    font.pixelSize: Theme.typeSubhead
                    font.family: Theme.fontSans
                    color: Theme.mutedForeground
                }

                Text {
                    id: detailCompatible
                    font.pixelSize: Theme.typeSubhead
                    font.family: Theme.fontSans
                    color: Theme.mutedForeground
                }
            }
        }
    }

    // Data model (populated from remote store API in production)
    ListModel {
        id: pluginListModel
        Component.onCompleted: {
            append({ name: "NTP 时间同步", description: "通过 NTP 协议自动同步系统时间，支持多服务器配置。", author: "Aeterna", version: "1.2.0", rating: 4.8, downloads: 12500, compatibleVersion: "1.0+", installed: false, icon: "clock" })
            append({ name: "投屏增强", description: "增强投屏功能，支持自定义分辨率、帧率和编码格式。", author: "Aeterna", version: "0.9.1", rating: 4.5, downloads: 8300, compatibleVersion: "1.0+", installed: false, icon: "antenna" })
            append({ name: "数据导出", description: "将考试数据导出为 Excel、CSV 或 PDF 格式。", author: "Aeterna", version: "2.0.0", rating: 4.2, downloads: 6100, compatibleVersion: "1.0+", installed: false, icon: "doc" })
            append({ name: "语音播报", description: "在考试开始和结束时自动语音播报提醒。", author: "第三方", version: "1.0.3", rating: 4.6, downloads: 4200, compatibleVersion: "1.0+", installed: false, icon: "speaker" })
            append({ name: "主题扩展包", description: "提供 10+ 种额外主题配色方案，支持自定义颜色。", author: "第三方", version: "3.1.0", rating: 4.9, downloads: 9800, compatibleVersion: "1.0+", installed: false, icon: "paintbrush" })
            append({ name: "远程控制", description: "允许通过局域网远程控制播放器的播放状态。", author: "Aeterna", version: "0.5.0", rating: 3.8, downloads: 2100, compatibleVersion: "1.2+", installed: false, icon: "network" })
        }
    }

    // Filtered count property
    property int filteredCount: {
        var count = 0
        for (var i = 0; i < pluginListModel.count; i++) {
            var item = pluginListModel.get(i)
            if (searchText === "" ||
                item.name.toLowerCase().indexOf(searchText) >= 0 ||
                item.description.toLowerCase().indexOf(searchText) >= 0 ||
                item.author.toLowerCase().indexOf(searchText) >= 0) {
                count++
            }
        }
        return count
    }

    // Functions
    function formatDownloads(count) {
        if (count >= 1000) {
            return (count / 1000).toFixed(1) + "k"
        }
        return count.toString()
    }

    function installPlugin(name) {
        for (var i = 0; i < pluginListModel.count; i++) {
            if (pluginListModel.get(i).name === name) {
                pluginListModel.setProperty(i, "installed", true)
                console.log("Plugin installed: " + name)
                break
            }
        }
    }

    function uninstallPlugin(name) {
        for (var i = 0; i < pluginListModel.count; i++) {
            if (pluginListModel.get(i).name === name) {
                pluginListModel.setProperty(i, "installed", false)
                console.log("Plugin uninstalled: " + name)
                break
            }
        }
    }

    function refreshStore() {
        console.log("Refreshing plugin store...")
        // In production, this would fetch from a remote store API
    }

    function showPluginDetail(name, description, author, version, rating, downloads, compatibleVersion) {
        detailName.text = name
        detailDescription.text = description
        detailAuthorText.text = "作者: " + author
        detailVersionText.text = "版本: " + version
        detailRating.text = rating.toFixed(1)
        detailDownloads.text = "下载量: " + formatDownloads(downloads)
        detailCompatible.text = "兼容版本: " + compatibleVersion
        detailDialog.open()
    }
}
