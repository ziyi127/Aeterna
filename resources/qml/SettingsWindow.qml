import QtQuick 2.15
import "."
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Qt.labs.platform 1.1
import Aeterna 1.0

ApplicationWindow {
    id: settingsWindow
    width: 720
    height: 540
    minimumWidth: 660
    minimumHeight: 480
    title: "设置 - Aeterna"
    color: Theme.materialBase

    

    AppInfo { id: appInfo }
    ThemeDetector { id: themeDetector }
    // 内部 SettingsBackend 作为回退；外部可通过属性注入共享实例
    SettingsBackend { id: internalSettingsBackend }
    property QtObject settingsBackend: null

    property string initialCategory: "basic"

    // ── Local settings state (persisted in-memory for the session) ──
    property var settings: ({
        // Basic
        autoStart: false,
        minimizeToTray: true,
        autoLoadLastConfig: true,
        configDir: "~/Documents/Aeterna",
        // Player
        fullscreenByDefault: true,
        disableSystemShortcuts: true,
        showGradientBg: true,
        autoHideControls: false,
        uiAccessEnabled: false,
        clockStyle: "数字时钟",
        // HTTP API
        httpEnabled: true,
        httpPort: 9527,
        httpBind: "0.0.0.0",
        tokenAuth: false,
        apiToken: "••••••••",
        corsEnabled: true,
        // Cast
        mdnsEnabled: true,
        allowDiscovery: true,
        deviceName: "Aeterna-001",
        allowRemoteControl: false,
        autoAcceptCast: false,
        showStatusBar: true,
        // Plugins
        installedPlugins: []
    })

    // ── Responsive layout helpers ──
    property bool compactWidth: width < 900
    property bool wideWidth: width >= 1440
    readonly property int contentMargin: compactWidth ? Theme.spacing16 : (wideWidth ? Theme.spacing48 : Theme.spacing32)
    readonly property int sidebarWidth: compactWidth ? Theme.sidebarMin : (wideWidth ? Theme.sidebarMin + Theme.spacing64 : Theme.sidebarMin)

    // ── Page-transition fade (HIG motionShort) ──
    Behavior on opacity {
        NumberAnimation { duration: Theme.motionShort; easing.type: Theme.motionStandard }
    }

    // ── Folder dialog for config directory ──
    FolderDialog {
        id: folderDialog
        title: "选择默认配置目录"
        onAccepted: {
            var path = folderDialog.folder.toString()
            if (path.indexOf("file://") === 0) path = path.substring(7)
            settingsWindow.settings.configDir = path
            settingsWindow.syncToBackend()
        }
    }

    // ── Persist local settings to backend ──
    function syncToBackend() {
        if (!settingsBackend) return
        var s = settingsWindow.settings
        try {
            var json = JSON.stringify({
            version: "2.0.0",
            basic: {
                auto_start: s.autoStart,
                minimize_to_tray: s.minimizeToTray,
                auto_load_last: s.autoLoadLastConfig,
                config_dir: s.configDir
            },
            appearance: {
                theme: "dark",
                theme_mode: settingsBackend.theme_mode,
                custom_primary_color: settingsBackend.custom_primary_color,
                body_font: "DM Sans",
                number_font: "DM Sans",
                font_size: 14
            },
            player: {
                default_fullscreen: s.fullscreenByDefault,
                disable_shortcuts: s.disableSystemShortcuts,
                show_gradient_bg: s.showGradientBg,
                auto_hide_toolbar: s.autoHideControls,
                clock_style: "digital",
                show_seconds: settingsBackend.show_seconds,
                show_date: settingsBackend.show_date,
                primary_color: "",
                bg_color: "",
                ui_scale: 1.0,
                density: "comfortable",
                big_clock: false,
                large_info_font: false,
                room_number: "",
                ntp_enabled: false,
                ui_access_enabled: settingsBackend.ui_access_enabled,
                exit_password_enabled: settingsBackend.exit_password_enabled,
                exit_password: settingsBackend.exit_password
            },
            editor: {
                recent_files: [],
                auto_save: false,
                default_path: s.configDir
            },
            time: {
                ntp_servers: ["ntp.aliyun.com", "pool.ntp.org"],
                auto_sync: settingsBackend.ntp_auto_sync,
                periodic_sync: settingsBackend.ntp_periodic_sync,
                sync_interval_minutes: settingsBackend.ntp_sync_interval_minutes
            },
            http_api: {
                enabled: s.httpEnabled,
                port: s.httpPort,
                bind_address: s.httpBind,
                token_auth: s.tokenAuth,
                token: s.apiToken,
                allow_cors: s.corsEnabled
            },
            cast: {
                enabled: s.mdnsEnabled,
                allow_discovery: s.allowDiscovery,
                device_name: s.deviceName,
                allow_remote_control: s.allowRemoteControl,
                auto_accept: s.autoAcceptCast,
                show_status_bar: s.showStatusBar
            }
        })
        settingsBackend.update_settings(json)
        } catch (e) {
            console.warn("Settings: failed to serialize settings:", e)
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // Layout: Sidebar (HIG 160pt) + Stack content (HIG Material.Elevated)
    // ═══════════════════════════════════════════════════════════════
    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ── Sidebar ──
        Material {
            Layout.preferredWidth: settingsWindow.sidebarWidth
            Layout.fillHeight: true
            tier: Material.Elevated
            radius: 0
            bordered: false

            Rectangle {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 1
                color: Theme.hairline
            }

            ListView {
                id: categoryList
                anchors.fill: parent
                anchors.margins: Theme.spacing16
                model: categoryModel
                spacing: Theme.spacing4
                clip: true

                delegate: NavItem {
                    text: name
                    icon: iconName
                    selected: index === categoryList.currentIndex
                    onClicked: categoryList.currentIndex = index
                }
            }
        }

        // ── Content stack ──
        StackLayout {
            id: settingsStack
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: categoryList.currentIndex
            clip: true

            // ═══════════════ Page 0: Basic ═══════════════
            Flickable {
                id: basicFlickable
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: width
                contentHeight: basicMaterial.height
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                Material {
                    id: basicMaterial
                    width: basicFlickable.width
                    height: basicPageContent.implicitHeight + 2 * settingsWindow.contentMargin
                    tier: Material.Elevated
                    radius: Theme.radiusLarge

                    ColumnLayout {
                        id: basicPageContent
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.margins: settingsWindow.contentMargin
                        spacing: Theme.spacing16

                        Text {
                            text: "基本设置"
                            font.pixelSize: Theme.typeTitle2
                            font.weight: Theme.weightBold
                            font.family: Theme.fontSans
                            color: Theme.foreground
                        }

                        // ── Startup ──
                        Card {
                            Layout.fillWidth: true
                            title: "启动行为"
                            contentItem: ColumnLayout {
                                spacing: Theme.spacing12
                                PinguoCheckBox {
                                    text: "开机自启动"
                                    checked: settingsWindow.settings.autoStart
                                    onToggled: {
                                        settingsWindow.settings.autoStart = checked
                                        settingsWindow.syncToBackend()
                                    }
                                }
                                PinguoCheckBox {
                                    text: "启动后最小化到系统托盘"
                                    checked: settingsWindow.settings.minimizeToTray
                                    onToggled: {
                                        settingsWindow.settings.minimizeToTray = checked
                                        settingsWindow.syncToBackend()
                                    }
                                }
                                PinguoCheckBox {
                                    text: "启动时自动加载上次配置"
                                    checked: settingsWindow.settings.autoLoadLastConfig
                                    onToggled: {
                                        settingsWindow.settings.autoLoadLastConfig = checked
                                        settingsWindow.syncToBackend()
                                    }
                                }
                            }
                        }

                        // ── File ──
                        Card {
                            Layout.fillWidth: true
                            title: "文件"
                            contentItem: RowLayout {
                                spacing: Theme.spacing12
                                Text {
                                    text: "默认配置目录:"
                                    color: Theme.foreground
                                    font.pixelSize: Theme.typeSubhead
                                    font.family: Theme.fontSans
                                }
                                PinguoTextField {
                                    text: settingsWindow.settings.configDir
                                    Layout.fillWidth: true
                                    onTextChanged: {
                                        settingsWindow.settings.configDir = text
                                        settingsWindow.syncToBackend(); console.log("Settings: configDir =", text)
                                    }
                                }
                                PinguoButton {
                                    text: "浏览…"
                                    variant: PinguoButton.Secondary
                                    onClicked: folderDialog.open()
                                }
                            }
                        }
                    }
                }
            }

            // ═══════════════ Page 1: Appearance ═══════════════
            Flickable {
                id: appearanceFlickable
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: width
                contentHeight: appearanceMaterial.height
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                Material {
                    id: appearanceMaterial
                    width: appearanceFlickable.width
                    height: appearancePageContent.implicitHeight + 2 * settingsWindow.contentMargin
                    tier: Material.Elevated
                    radius: Theme.radiusLarge

                    ColumnLayout {
                        id: appearancePageContent
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.margins: settingsWindow.contentMargin
                        spacing: Theme.spacing16

                        Text {
                            text: "外观设置"
                            font.pixelSize: Theme.typeTitle2
                            font.weight: Theme.weightBold
                            font.family: Theme.fontSans
                            color: Theme.foreground
                        }

                        // ── Theme Mode ──
                        Card {
                            Layout.fillWidth: true
                            title: "主题模式"
                            contentItem: ColumnLayout {
                                spacing: Theme.spacing12
                                // 跟随系统
                                Item {
                                    Layout.fillWidth: true
                                    implicitHeight: 20
                                    RowLayout {
                                        anchors.fill: parent
                                        spacing: Theme.spacing8
                                        Rectangle {
                                            width: 20; height: 20
                                            radius: 10
                                            border.width: 2
                                            border.color: settingsBackend.theme_mode === "auto" ? Theme.primary : Theme.border
                                            color: settingsBackend.theme_mode === "auto" ? Theme.primary : "transparent"
                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: 8; height: 8
                                                radius: 4
                                                color: settingsBackend.theme_mode === "auto" ? Theme.primaryForeground : "transparent"
                                                visible: settingsBackend.theme_mode === "auto"
                                            }
                                        }
                                        Text {
                                            text: "跟随系统"
                                            color: Theme.foreground
                                            font.pixelSize: Theme.typeSubhead
                                            font.family: Theme.fontSans
                                        }
                                        Text {
                                            text: themeDetector.systemPrefersDark ? "（当前: 深色）" : "（当前: 浅色）"
                                            color: Theme.mutedForeground
                                            font.pixelSize: Theme.typeCaption1
                                            font.family: Theme.fontSans
                                            visible: settingsBackend.theme_mode === "auto"
                                        }
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: settingsBackend.theme_mode = "auto"
                                    }
                                }
                                // 深色
                                Item {
                                    Layout.fillWidth: true
                                    implicitHeight: 20
                                    RowLayout {
                                        anchors.fill: parent
                                        spacing: Theme.spacing8
                                        Rectangle {
                                            width: 20; height: 20
                                            radius: 10
                                            border.width: 2
                                            border.color: settingsBackend.theme_mode === "dark" ? Theme.primary : Theme.border
                                            color: settingsBackend.theme_mode === "dark" ? Theme.primary : "transparent"
                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: 8; height: 8
                                                radius: 4
                                                color: settingsBackend.theme_mode === "dark" ? Theme.primaryForeground : "transparent"
                                                visible: settingsBackend.theme_mode === "dark"
                                            }
                                        }
                                        Text {
                                            text: "深色"
                                            color: Theme.foreground
                                            font.pixelSize: Theme.typeSubhead
                                            font.family: Theme.fontSans
                                        }
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: settingsBackend.theme_mode = "dark"
                                    }
                                }
                                // 浅色
                                Item {
                                    Layout.fillWidth: true
                                    implicitHeight: 20
                                    RowLayout {
                                        anchors.fill: parent
                                        spacing: Theme.spacing8
                                        Rectangle {
                                            width: 20; height: 20
                                            radius: 10
                                            border.width: 2
                                            border.color: settingsBackend.theme_mode === "light" ? Theme.primary : Theme.border
                                            color: settingsBackend.theme_mode === "light" ? Theme.primary : "transparent"
                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: 8; height: 8
                                                radius: 4
                                                color: settingsBackend.theme_mode === "light" ? Theme.primaryForeground : "transparent"
                                                visible: settingsBackend.theme_mode === "light"
                                            }
                                        }
                                        Text {
                                            text: "浅色"
                                            color: Theme.foreground
                                            font.pixelSize: Theme.typeSubhead
                                            font.family: Theme.fontSans
                                        }
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: settingsBackend.theme_mode = "light"
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ═══════════════ Page 2: Player ═══════════════
            Flickable {
                id: playerFlickable
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: width
                contentHeight: playerMaterial.height
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                Material {
                    id: playerMaterial
                    width: playerFlickable.width
                    height: playerPageContent.implicitHeight + 2 * settingsWindow.contentMargin
                    tier: Material.Elevated
                    radius: Theme.radiusLarge

                    ColumnLayout {
                        id: playerPageContent
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.margins: settingsWindow.contentMargin
                        spacing: Theme.spacing16

                        Text {
                            text: "播放器设置"
                            font.pixelSize: Theme.typeTitle2
                            font.weight: Theme.weightBold
                            font.family: Theme.fontSans
                            color: Theme.foreground
                        }

                        Card {
                            Layout.fillWidth: true
                            title: "全屏播放器"
                            contentItem: ColumnLayout {
                                spacing: Theme.spacing12
                                PinguoCheckBox { text: "启动时默认全屏"; checked: settingsWindow.settings.fullscreenByDefault; onToggled: { settingsWindow.settings.fullscreenByDefault = checked; settingsWindow.syncToBackend(); console.log("Settings: fullscreenByDefault =", checked) } }
                                PinguoCheckBox { text: "禁用系统快捷键"; checked: settingsWindow.settings.disableSystemShortcuts; onToggled: { settingsWindow.settings.disableSystemShortcuts = checked; settingsWindow.syncToBackend(); console.log("Settings: disableSystemShortcuts =", checked) } }
                                PinguoCheckBox { text: "显示渐变背景"; checked: settingsWindow.settings.showGradientBg; onToggled: { settingsWindow.settings.showGradientBg = checked; settingsWindow.syncToBackend(); console.log("Settings: showGradientBg =", checked) } }
                                PinguoCheckBox { text: "自动隐藏底部操作栏"; checked: settingsWindow.settings.autoHideControls; onToggled: { settingsWindow.settings.autoHideControls = checked; settingsWindow.syncToBackend(); console.log("Settings: autoHideControls =", checked) } }
                                PinguoCheckBox {
                                    text: "启用 UI Access（需要管理员权限，仅 Windows）"
                                    checked: settingsBackend.ui_access_enabled
                                    onToggled: {
                                        settingsBackend.ui_access_enabled = checked
                                        settingsWindow.syncToBackend(); console.log("Settings: uiAccessEnabled =", checked)
                                    }
                                }
                                PinguoCheckBox {
                                    text: "启用退出密码"
                                    checked: settingsBackend.exit_password_enabled
                                    onToggled: {
                                        settingsBackend.exit_password_enabled = checked
                                        settingsWindow.syncToBackend(); console.log("Settings: exitPasswordEnabled =", checked)
                                    }
                                }
                                RowLayout {
                                    visible: settingsBackend.exit_password_enabled
                                    spacing: Theme.spacing12
                                    Text {
                                        text: "退出密码:"
                                        color: Theme.foreground
                                        font.pixelSize: Theme.typeSubhead
                                        font.family: Theme.fontSans
                                    }
                                    PinguoTextField {
                                        text: settingsBackend.exit_password
                                        inputItem.echoMode: TextInput.Password
                                        Layout.fillWidth: true
                                        onTextChanged: {
                                            settingsBackend.exit_password = text
                                            settingsWindow.syncToBackend(); console.log("Settings: exitPassword updated")
                                        }
                                    }
                                }
                            }
                        }

                        Card {
                            Layout.fillWidth: true
                            title: "时钟显示"
                            contentItem: ColumnLayout {
                                spacing: Theme.spacing12
                                RowLayout {
                                    Text { text: "时钟样式:"; color: Theme.foreground; font.pixelSize: Theme.typeSubhead; font.family: Theme.fontSans }
                                    PinguoComboBox {
                                        model: ["数字时钟", "模拟时钟", "双时钟"]
                                        currentText: settingsWindow.settings.clockStyle
                                        onActivated: {
                                            settingsWindow.settings.clockStyle = currentText
                                            settingsWindow.syncToBackend(); console.log("Settings: clockStyle =", currentText)
                                        }
                                    }
                                }
                                PinguoCheckBox { text: "显示秒"; checked: settingsBackend.show_seconds; onToggled: { settingsBackend.show_seconds = checked; settingsWindow.syncToBackend(); console.log("Settings: showSeconds =", checked) } }
                                PinguoCheckBox { text: "显示日期"; checked: settingsBackend.show_date; onToggled: { settingsBackend.show_date = checked; settingsWindow.syncToBackend(); console.log("Settings: showDate =", checked) } }
                            }
                        }

                        Card {
                            Layout.fillWidth: true
                            title: "颜色方案"
                            contentItem: ColumnLayout {
                                spacing: Theme.spacing12

                                // ── 预设色块 ──
                                Text {
                                    text: "主色调"
                                    font.family: Theme.fontSans
                                    font.pixelSize: Theme.typeHeadline
                                    font.weight: Theme.weightSemibold
                                    color: Theme.foreground
                                }
                                RowLayout {
                                    spacing: Theme.spacing8
                                    Repeater {
                                        model: [
                                            { name: "Pinguo Blue", color: Theme.brand500 },
                                            { name: "Sunset Gold", color: Theme.chartOrange },
                                            { name: "Forest Green", color: Theme.stateSuccess },
                                            { name: "System Red", color: Theme.stateError },
                                            { name: "System Purple", color: Theme.systemPurple },
                                            { name: "System Orange", color: Theme.systemOrange }
                                        ]
                                        Rectangle {
                                            width: 32; height: 32
                                            radius: 16
                                            color: modelData.color
                                            border.width: settingsBackend.custom_primary_color === modelData.color ? 3 : 1
                                            border.color: settingsBackend.custom_primary_color === modelData.color ? Theme.foreground : Theme.border
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    settingsBackend.custom_primary_color = modelData.color
                                                    Theme.setCustomPrimaryColor(modelData.color)
                                                }
                                            }
                                        }
                                    }
                                }

                                // ── Hex 输入 ──
                                RowLayout {
                                    spacing: Theme.spacing8
                                    Text {
                                        text: "自定义 Hex:"
                                        color: Theme.mutedForeground
                                        font.family: Theme.fontSans
                                        font.pixelSize: Theme.typeSubhead
                                    }
                                    Rectangle {
                                        width: 120; height: 32
                                        radius: Theme.radiusMedium
                                        border.width: 1
                                        border.color: Theme.input
                                        color: Theme.background
                                        TextInput {
                                            id: hexInput
                                            anchors.fill: parent
                                            anchors.margins: 8
                                            font.family: Theme.fontMono
                                            font.pixelSize: Theme.typeSubhead
                                            color: Theme.foreground
                                            text: settingsBackend.custom_primary_color
                                            onAccepted: {
                                                var hex = text.trim()
                                                if (/^#[0-9a-fA-F]{6}$/.test(hex)) {
                                                    settingsBackend.custom_primary_color = hex
                                                    Theme.setCustomPrimaryColor(hex)
                                                }
                                            }
                                        }
                                    }
                                }

                                // ── 恢复默认 ──
                                PinguoButton {
                                    text: "恢复默认"
                                    variant: PinguoButton.Text
                                    Layout.alignment: Qt.AlignLeft
                                    onClicked: {
                                        settingsBackend.custom_primary_color = ""
                                        Theme.setCustomPrimaryColor("")
                                        hexInput.text = ""
                                    }
                                }

                                // ── 实时预览 ──
                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 56
                                    radius: Theme.radiusMedium
                                    color: Theme.card
                                    border.width: 1
                                    border.color: Theme.border
                                    RowLayout {
                                        anchors.centerIn: parent
                                        spacing: Theme.spacing12
                                        Rectangle {
                                            width: 32; height: 32
                                            radius: 16
                                            color: Theme.primary
                                        }
                                        Text {
                                            text: Theme.primary
                                            font.family: Theme.fontMono
                                            font.pixelSize: Theme.typeSubhead
                                            color: Theme.foreground
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ═══════════════ Page 3: Time / NTP ═══════════════
            Flickable {
                id: timeFlickable
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: width
                contentHeight: timeMaterial.height
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                Material {
                    id: timeMaterial
                    width: timeFlickable.width
                    height: timePageContent.implicitHeight + 2 * settingsWindow.contentMargin
                    tier: Material.Elevated
                    radius: Theme.radiusLarge

                    ColumnLayout {
                        id: timePageContent
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.margins: settingsWindow.contentMargin
                        spacing: Theme.spacing16

                        Text {
                            text: "时间同步设置"
                            font.pixelSize: Theme.typeTitle2
                            font.weight: Theme.weightBold
                            font.family: Theme.fontSans
                            color: Theme.foreground
                        }

                        Card {
                            Layout.fillWidth: true
                            title: "NTP 服务器"
                            contentItem: ColumnLayout {
                                id: ntpServerList
                                spacing: Theme.spacing12

                                Repeater {
                                    model: ntpServerModel
                                    delegate: RowLayout {
                                        Layout.fillWidth: true
                                        spacing: Theme.spacing12
                                        PinguoTextField {
                                            text: server
                                            Layout.fillWidth: true
                                            onTextChanged: {
                                                ntpServerModel.setProperty(index, "server", text)
                                                timePage.saveNtpServers()
                                            }
                                        }
                                        PinguoButton {
                                            text: testing ? "…" : "测试"
                                            variant: PinguoButton.Secondary
                                            enabled: !testing
                                            onClicked: {
                                                var srv = ntpServerModel.get(index).server
                                                if (!srv) return
                                                ntpServerModel.setProperty(index, "testing", true)
                                                ntpServerModel.setProperty(index, "testResult", "测试中…")
                                                settingsBackend.test_ntp_server(srv)
                                            }
                                        }
                                        PinguoButton {
                                            text: "×"
                                            variant: PinguoButton.Text
                                            onClicked: {
                                                settingsBackend.remove_ntp_server(index)
                                                ntpServerModel.remove(index)
                                            }
                                        }
                                    }
                                }

                                // 测试结果行
                                Text {
                                    id: ntpTestResultText
                                    text: ""
                                    color: Theme.mutedForeground
                                    font.pixelSize: Theme.typeCaption1
                                    font.family: Theme.fontSans
                                    visible: text !== ""
                                }

                                PinguoButton {
                                    text: "添加服务器"
                                    variant: PinguoButton.Secondary
                                    onClicked: {
                                        settingsBackend.add_ntp_server()
                                        ntpServerModel.append({ server: "", testing: false, testResult: "" })
                                    }
                                }
                            }
                        }

                        Card {
                            Layout.fillWidth: true
                            title: "同步选项"
                            contentItem: ColumnLayout {
                                spacing: Theme.spacing12
                                PinguoCheckBox {
                                    text: "启动时自动同步"
                                    checked: settingsBackend.ntp_auto_sync
                                    onToggled: {
                                        settingsBackend.ntp_auto_sync = checked
                                    }
                                }
                                PinguoCheckBox {
                                    text: "定时同步（每" + settingsBackend.ntp_sync_interval_minutes + "分钟）"
                                    checked: settingsBackend.ntp_periodic_sync
                                    onToggled: {
                                        settingsBackend.ntp_periodic_sync = checked
                                    }
                                }
                                RowLayout {
                                    spacing: Theme.spacing12
                                    PinguoButton {
                                        text: "立即同步"
                                        variant: PinguoButton.Primary
                                        onClicked: {
                                            ntpTestResultText.text = "正在同步…"
                                            settingsBackend.sync_ntp_all()
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ── NTP 服务器列表模型 ──
                ListModel {
                    id: ntpServerModel
                    Component.onCompleted: {
                        timePage.loadNtpServers()
                    }
                }

                // ── 内部方法 ──
                QtObject {
                    id: timePage
                    function loadNtpServers() {
                        ntpServerModel.clear()
                        var jsonStr = settingsBackend.ntp_servers_json
                        try {
                            var arr = JSON.parse(jsonStr)
                            for (var i = 0; i < arr.length; i++) {
                                ntpServerModel.append({ server: arr[i], testing: false, testResult: "" })
                            }
                        } catch (e) {
                            console.log("Time: failed to parse ntp_servers_json:", e)
                        }
                    }
                    function saveNtpServers() {
                        var arr = []
                        for (var i = 0; i < ntpServerModel.count; i++) {
                            arr.push(ntpServerModel.get(i).server)
                        }
                        var jsonStr = JSON.stringify(arr)
                        // 通过 update_settings 保存
                        var settings = JSON.parse(settingsBackend.settings_json)
                        settings.time.ntp_servers = arr
                        settingsBackend.update_settings(JSON.stringify(settings, null, 2))
                    }
                }

                // 监听 NTP 测试结果
                Connections {
                    target: settingsBackend
                    function onNtp_test_result(index, success, message) {
                        if (index >= 0 && index < ntpServerModel.count) {
                            ntpServerModel.setProperty(index, "testing", false)
                            ntpServerModel.setProperty(index, "testResult", success ? "✓ " + message : "✗ " + message)
                        }
                        ntpTestResultText.text = message
                        ntpTestResultText.color = success ? Theme.success : Theme.stateError
                    }
                }
            }

            // ═══════════════ Page 4: HTTP API ═══════════════
            Flickable {
                id: httpFlickable
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: width
                contentHeight: httpMaterial.height
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                Material {
                    id: httpMaterial
                    width: httpFlickable.width
                    height: httpPageContent.implicitHeight + 2 * settingsWindow.contentMargin
                    tier: Material.Elevated
                    radius: Theme.radiusLarge

                    ColumnLayout {
                        id: httpPageContent
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.margins: settingsWindow.contentMargin
                        spacing: Theme.spacing16

                        Text {
                            text: "HTTP API 设置"
                            font.pixelSize: Theme.typeTitle2
                            font.weight: Theme.weightBold
                            font.family: Theme.fontSans
                            color: Theme.foreground
                        }

                        Card {
                            Layout.fillWidth: true
                            title: "服务器"
                            contentItem: ColumnLayout {
                                spacing: Theme.spacing12
                                PinguoCheckBox { text: "启用 HTTP API 服务"; checked: settingsWindow.settings.httpEnabled; onToggled: { settingsWindow.settings.httpEnabled = checked; settingsWindow.syncToBackend(); console.log("Settings: httpEnabled =", checked) } }
                                RowLayout {
                                    spacing: Theme.spacing12
                                    Text { text: "监听端口:"; color: Theme.foreground; font.pixelSize: Theme.typeSubhead; font.family: Theme.fontSans }
                                    PinguoSpinBox { from: 1024; to: 65535; value: settingsWindow.settings.httpPort; onValueChanged: { settingsWindow.settings.httpPort = value; settingsWindow.syncToBackend(); console.log("Settings: httpPort =", value) } }
                                }
                                RowLayout {
                                    spacing: Theme.spacing12
                                    Text { text: "监听地址:"; color: Theme.foreground; font.pixelSize: Theme.typeSubhead; font.family: Theme.fontSans }
                                    PinguoComboBox {
                                        model: ["0.0.0.0", "127.0.0.1", "localhost"]
                                        currentText: settingsWindow.settings.httpBind
                                        onActivated: {
                                            settingsWindow.settings.httpBind = currentText
                                            settingsWindow.syncToBackend(); console.log("Settings: httpBind =", currentText)
                                        }
                                    }
                                }
                            }
                        }

                        Card {
                            Layout.fillWidth: true
                            title: "认证"
                            contentItem: ColumnLayout {
                                spacing: Theme.spacing12
                                PinguoCheckBox { text: "启用 Token 认证"; checked: settingsWindow.settings.tokenAuth; onToggled: { settingsWindow.settings.tokenAuth = checked; settingsWindow.syncToBackend(); console.log("Settings: tokenAuth =", checked) } }
                                RowLayout {
                                    spacing: Theme.spacing12
                                    Text { text: "Token:"; color: Theme.foreground; font.pixelSize: Theme.typeSubhead; font.family: Theme.fontSans }
                                    PinguoTextField {
                                        text: settingsWindow.settings.apiToken
                                        inputItem.echoMode: TextInput.Password
                                        Layout.fillWidth: true
                                        onTextChanged: {
                                            settingsWindow.settings.apiToken = text
                                            settingsWindow.syncToBackend(); console.log("Settings: apiToken updated")
                                        }
                                    }
                                    PinguoButton {
                                        text: "重新生成"
                                        variant: PinguoButton.Secondary
                                        onClicked: {
                                            var chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
                                            var token = ""
                                            for (var i = 0; i < 32; i++) {
                                                token += chars.charAt(Math.floor(Math.random() * chars.length))
                                            }
                                            settingsWindow.settings.apiToken = token
                                            settingsWindow.syncToBackend(); console.log("Settings: regenerated apiToken")
                                        }
                                    }
                                }
                            }
                        }

                        Card {
                            Layout.fillWidth: true
                            title: "CORS"
                            contentItem: PinguoCheckBox { text: "允许跨域请求"; checked: settingsWindow.settings.corsEnabled; onToggled: { settingsWindow.settings.corsEnabled = checked; settingsWindow.syncToBackend(); console.log("Settings: corsEnabled =", checked) } }
                        }
                    }
                }
            }

            // ═══════════════ Page 5: Cast ═══════════════
            Flickable {
                id: castFlickable
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: width
                contentHeight: castMaterial.height
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                Material {
                    id: castMaterial
                    width: castFlickable.width
                    height: castPageContent.implicitHeight + 2 * settingsWindow.contentMargin
                    tier: Material.Elevated
                    radius: Theme.radiusLarge

                    ColumnLayout {
                        id: castPageContent
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.margins: settingsWindow.contentMargin
                        spacing: Theme.spacing16

                        Text {
                            text: "投屏设置"
                            font.pixelSize: Theme.typeTitle2
                            font.weight: Theme.weightBold
                            font.family: Theme.fontSans
                            color: Theme.foreground
                        }

                        Card {
                            Layout.fillWidth: true
                            title: "设备发现"
                            contentItem: ColumnLayout {
                                spacing: Theme.spacing12
                                PinguoCheckBox { text: "启用 mDNS 设备发现"; checked: settingsWindow.settings.mdnsEnabled; onToggled: { settingsWindow.settings.mdnsEnabled = checked; settingsWindow.syncToBackend(); console.log("Settings: mdnsEnabled =", checked) } }
                                PinguoCheckBox { text: "允许被发现"; checked: settingsWindow.settings.allowDiscovery; onToggled: { settingsWindow.settings.allowDiscovery = checked; settingsWindow.syncToBackend(); console.log("Settings: allowDiscovery =", checked) } }
                                RowLayout {
                                    spacing: Theme.spacing12
                                    Text { text: "设备名称:"; color: Theme.foreground; font.pixelSize: Theme.typeSubhead; font.family: Theme.fontSans }
                                    PinguoTextField { text: settingsWindow.settings.deviceName; Layout.fillWidth: true; onTextChanged: { settingsWindow.settings.deviceName = text; settingsWindow.syncToBackend(); console.log("Settings: deviceName =", text) } }
                                }
                            }
                        }

                        Card {
                            Layout.fillWidth: true
                            title: "投屏选项"
                            contentItem: ColumnLayout {
                                spacing: Theme.spacing12
                                PinguoCheckBox { text: "允许远程控制"; checked: settingsWindow.settings.allowRemoteControl; onToggled: { settingsWindow.settings.allowRemoteControl = checked; settingsWindow.syncToBackend(); console.log("Settings: allowRemoteControl =", checked) } }
                                PinguoCheckBox { text: "自动接受投屏请求"; checked: settingsWindow.settings.autoAcceptCast; onToggled: { settingsWindow.settings.autoAcceptCast = checked; settingsWindow.syncToBackend(); console.log("Settings: autoAcceptCast =", checked) } }
                                PinguoCheckBox { text: "投屏时显示状态栏"; checked: settingsWindow.settings.showStatusBar; onToggled: { settingsWindow.settings.showStatusBar = checked; settingsWindow.syncToBackend(); console.log("Settings: showStatusBar =", checked) } }
                            }
                        }
                    }
                }
            }

            // ═══════════════ Page 6: Plugins ═══════════════
            Flickable {
                id: pluginsFlickable
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: width
                contentHeight: pluginsMaterial.height
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                Material {
                    id: pluginsMaterial
                    width: pluginsFlickable.width
                    height: pluginsPageContent.implicitHeight + 2 * settingsWindow.contentMargin
                    tier: Material.Elevated
                    radius: Theme.radiusLarge

                    ColumnLayout {
                        id: pluginsPageContent
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.margins: settingsWindow.contentMargin
                        spacing: Theme.spacing16

                        Text {
                            text: "插件管理"
                            font.pixelSize: Theme.typeTitle2
                            font.weight: Theme.weightBold
                            font.family: Theme.fontSans
                            color: Theme.foreground
                        }

                        Card {
                            Layout.fillWidth: true
                            title: "已安装插件"
                            contentItem: ColumnLayout {
                                spacing: Theme.spacing8

                                ListView {
                                    id: installedPluginsList
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: Math.min(200, pluginSettingsModel.count * (Theme.sizeListItemLarge + Theme.spacing8))
                                    model: ListModel {
                                        id: pluginSettingsModel
                                        Component.onCompleted: {
                                            if (settingsWindow.settings.installedPlugins.length === 0) {
                                                append({ name: "NTP 时间同步", version: "1.2.0", enabled: true })
                                                append({ name: "投屏增强", version: "0.9.1", enabled: true })
                                                append({ name: "数据导出", version: "2.0.0", enabled: false })
                                            }
                                        }
                                    }
                                    spacing: Theme.spacing8

                                    delegate: RowLayout {
                                        width: ListView.view.width
                                        height: Theme.sizeListItemLarge
                                        spacing: Theme.spacing12
                                        PinguoCheckBox {
                                            checked: enabled
                                            onToggled: {
                                                model.enabled = checked
                                                settingsWindow.syncToBackend(); console.log("Settings: plugin", name, "enabled =", checked)
                                            }
                                        }
                                        Text { text: name; color: Theme.foreground; font.pixelSize: Theme.typeSubhead; font.family: Theme.fontSans }
                                        Text { text: "v" + version; color: Theme.mutedForeground; font.pixelSize: Theme.typeCaption1; font.family: Theme.fontSans }
                                        Item { Layout.fillWidth: true }
                                        PinguoButton {
                                            text: "卸载"
                                            variant: PinguoButton.Secondary
                                            onClicked: {
                                                pluginSettingsModel.remove(index)
                                                settingsWindow.syncToBackend(); console.log("Settings: uninstalled plugin", name)
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        RowLayout {
                            spacing: Theme.spacing12
                            PinguoButton {
                                text: "安装插件…"
                                variant: PinguoButton.Secondary
                                Layout.alignment: Qt.AlignLeft
                                onClicked: {
                                    settingsWindow.syncToBackend(); console.log("Settings: install plugin from file")
                                }
                            }
                            PinguoButton {
                                text: "打开插件商店"
                                variant: PinguoButton.Primary
                                Layout.alignment: Qt.AlignLeft
                                onClicked: {
                                    var comp = Qt.createComponent("qrc:/qml/PluginStoreWindow.qml")
                                    function doCreate() {
                                        if (comp.status !== Component.Ready) {
                                            console.error("PluginStoreWindow not ready: " + comp.errorString())
                                            return
                                        }
                                        var win = comp.createObject(settingsWindow)
                                        if (!win) {
                                            console.error("Failed to create PluginStoreWindow instance")
                                            return
                                        }
                                        win.show()
                                    }
                                    if (comp.status === Component.Ready) {
                                        doCreate()
                                    } else if (comp.status === Component.Error) {
                                        console.error("Failed to load PluginStoreWindow: " + comp.errorString())
                                    } else {
                                        comp.statusChanged.connect(doCreate)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ═══════════════ Page 7: About ═══════════════
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: Theme.spacing16

                    Icon {
                        name: "info"
                        size: 48
                        tier: Icon.Tertiary
                        Layout.alignment: Qt.AlignHCenter
                    }

                    Text {
                        text: "Aeterna"
                        font.pixelSize: Theme.typeTitle1
                        font.weight: Theme.weightBold
                        font.family: Theme.fontSans
                        color: Theme.foreground
                        Layout.alignment: Qt.AlignHCenter
                    }

                    Text {
                        text: "版本 " + appInfo.version
                        font.pixelSize: Theme.typeSubhead
                        font.family: Theme.fontSans
                        color: Theme.mutedForeground
                        Layout.alignment: Qt.AlignHCenter
                    }

                    PinguoButton {
                        text: "查看详细信息"
                        variant: PinguoButton.Secondary
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: Theme.spacing12
                        onClicked: aboutDialog.open()
                    }
                }

                AboutDialog {
                    id: aboutDialog
                }
            }
        }
    }

    // ── Category model (HIG SF Symbol icon names) ──
    ListModel {
        id: categoryModel
        ListElement { key: "basic";      name: "基本";  iconName: "gear" }
        ListElement { key: "appearance"; name: "外观";  iconName: "paintbrush" }
        ListElement { key: "player";     name: "播放器"; iconName: "play" }
        ListElement { key: "time";       name: "时间";  iconName: "clock" }
        ListElement { key: "http";       name: "HTTP API"; iconName: "network" }
        ListElement { key: "cast";       name: "投屏";  iconName: "antenna" }
        ListElement { key: "plugins";    name: "插件";  iconName: "puzzle" }
        ListElement { key: "about";      name: "关于";  iconName: "info" }
    }

    Component.onCompleted: {
        // 初始化系统主题检测
        themeDetector.detect()
        // 若无外部注入，则使用内部实例
        if (!settingsWindow.settingsBackend) {
            settingsWindow.settingsBackend = internalSettingsBackend
        }
        // 加载设置
        settingsBackend.load()
        // 同步自定义颜色到 Hex 输入框
        hexInput.text = settingsBackend.custom_primary_color
        // 导航到初始分类
        for (var i = 0; i < categoryModel.count; i++) {
            if (categoryModel.get(i).key === initialCategory) {
                categoryList.currentIndex = i
                break
            }
        }
    }
}