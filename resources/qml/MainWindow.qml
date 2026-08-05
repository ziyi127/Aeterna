import QtQuick 2.15
import "."
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtQuick.Window 2.15
import Qt.labs.platform 1.1 as Platform
// import QtGraphicalEffects 1.15  // removed — all effects use native ShaderEffect now
import Aeterna 1.0

ApplicationWindow {
    id: mainWindow
    width: 720
    height: 480
    minimumWidth: 640
    minimumHeight: 400
    title: "Aeterna"
    visible: true
    color: Theme.materialBase

    

    // ── Navigation state ──
    property int currentPage: 0

    // ── Config state ──
    property bool configValid: false
    property int examCount: 0
    property var loadedConfig: null
    property var activePlayerWindow: null
    property var activeSettingsWindow: null
    property bool settingsCreationPending: false
    property string pendingSettingsCategory: "basic"

    // ── Discover state ──
    property var discoveredDevices: []
    property bool scanning: false
    property bool showShareStatus: true
    property string appliedSharedConfig: ""

    // ── Responsive layout helpers ──
    property bool compactWidth: width < 900
    property bool wideWidth: width >= 1440
    property bool shortHeight: height < 500
    readonly property int contentMargin: compactWidth ? Theme.spacing16 : (wideWidth ? Theme.spacing48 : Theme.spacing32)
    readonly property int contentSpacing: compactWidth ? Theme.spacing12 : (wideWidth ? Theme.spacing32 : Theme.spacing24)
    readonly property int sidebarWidth: compactWidth ? Theme.sidebarMin : (wideWidth ? Theme.sidebarMin + Theme.spacing64 : Theme.sidebarMin)

    function handleDeepLink(link) {
        if (typeof link === "string") {
            try {
                link = JSON.parse(link)
            } catch (error) {
                console.warn("Invalid deep link payload:", error)
                return
            }
        }
        if (!link || !link.action) return
        switch (link.action) {
        case "open":
            if (link.file) {
                loadConfigFromUrl(link.file)
                enterPlayerPage()
            }
            break
        case "player":
            enterPlayerPage()
            break
        case "settings":
            settingsLoader.openSettings(link.category || "basic")
            break
        case "editor":
            editorLoader.openEditor()
            break
        case "cast":
            currentPage = 1
            break
        default:
            console.warn("Unsupported deep link action:", link.action)
        }
    }

    function loadConfigFromJson(jsonStr) {
        try {
            var config = JSON.parse(jsonStr)
            if (config && config.examInfos) {
                loadedConfig = config
                configValid = true
                examCount = config.examInfos.length
                configManager.config_json = jsonStr
                if (mainWindow.activePlayerWindow && mainWindow.activePlayerWindow.loadExamData) {
                    mainWindow.activePlayerWindow.loadExamData(loadedConfig)
                }
                if (jsonStr !== mainWindow.appliedSharedConfig) {
                    shareManager.set_local_config(jsonStr)
                }
                mainWindow.appliedSharedConfig = ""
            } else {
                configValid = false
                examCount = 0
            }
        } catch (e) {
            configValid = false
            examCount = 0
        }
    }

    function ensureFileUrl(path) {
        if (!path) return ""
        if (path.indexOf("://") >= 0) return path
        if (path.indexOf("/") === 0) return "file://" + path
        return "file://" + path
    }

    function loadConfigFromUrl(url) {
        var fileUrl = ensureFileUrl(url)
        if (!fileUrl) return
        var xhr = new XMLHttpRequest()
        xhr.open("GET", fileUrl, false)
        xhr.send()
        mainWindow.loadConfigFromJson(xhr.responseText)
    }

    function enterPlayerPage() {
        mainWindow.currentPage = 2
        if (!mainWindow.configValid) {
            playerConfigDialog.refreshRecentFile()
            playerConfigDialog.open()
        }
    }

    function refreshDiscover() {
        scanning = true
        discoveredDevices = []
        discoverManager.start_scan()
        deviceRefreshTimer.start()
        scanTimer.restart()
    }

    onClosing: function(close) {
        if (settingsWindowPreference.minimizeToTray && trayIcon.available) {
            close.accepted = false
            mainWindow.hide()
        }
    }

    property var settingsWindowPreference: ({ minimizeToTray: false })

    function syncTrayPreference() {
        try {
            settingsWindowPreference.minimizeToTray = JSON.parse(settingsBackend.settings_json).basic.minimize_to_tray === true
        } catch (e) {
            settingsWindowPreference.minimizeToTray = false
        }
    }

    // Rust-backed types (engine init only)
    ConfigManager { id: configManager }
    AppInfo { id: appInfo }
    DiscoverManager { id: discoverManager }
    ShareManager { id: shareManager }
    RecentFilesModel { id: recentFilesModel }
    ThemeDetector { id: themeDetector }
    SettingsBackend { id: settingsBackend }

    Platform.SystemTrayIcon {
        id: trayIcon
        visible: available
        icon.source: "qrc:/icons/icon.png"
        tooltip: "Aeterna"

        menu: Platform.Menu {
            Platform.MenuItem {
                text: "显示 Aeterna"
                onTriggered: {
                    mainWindow.show()
                    mainWindow.raise()
                    mainWindow.requestActivate()
                }
            }
            Platform.MenuItem {
                text: "打开编辑器"
                onTriggered: editorLoader.openEditor()
            }
            Platform.MenuItem {
                text: "打开设置"
                onTriggered: settingsLoader.openSettings()
            }
            Platform.MenuSeparator {}
            Platform.MenuItem {
                text: "退出"
                onTriggered: Qt.quit()
            }
        }

        onActivated: function(reason) {
            if (reason === Platform.SystemTrayIcon.Trigger || reason === Platform.SystemTrayIcon.DoubleClick) {
                mainWindow.show()
                mainWindow.raise()
                mainWindow.requestActivate()
            }
        }
    }

    // ── Theme initialization ──
    function applyAccessibilityAppearance() {
        try {
            var appearance = JSON.parse(settingsBackend.settings_json).appearance
            Theme.reduceTransparency = appearance.reduce_transparency === true
            Theme.highContrast = appearance.high_contrast === true
            Theme.reducedMotion = appearance.reduced_motion === true
        } catch (e) {
            Theme.reduceTransparency = false
            Theme.highContrast = false
            Theme.reducedMotion = false
        }
    }

    Component.onCompleted: {
        settingsBackend.load()
        syncTrayPreference()
        applyAccessibilityAppearance()
        shareManager.refresh()
        if (shareManager.active_config_json !== "") {
            mainWindow.appliedSharedConfig = shareManager.active_config_json
            mainWindow.loadConfigFromJson(shareManager.active_config_json)
        }
        var systemDark = themeDetector.detect()
        // Apply theme mode from settings
        if (settingsBackend.theme_mode === "auto") {
            Theme.setDarkMode(systemDark === true)
        } else if (settingsBackend.theme_mode === "dark") {
            Theme.setDarkMode(true)
        } else {
            Theme.setDarkMode(false)
        }
        // Apply custom primary color
        if (settingsBackend.custom_primary_color !== "") {
            Theme.setCustomPrimaryColor(settingsBackend.custom_primary_color)
        }
    }

    // ── System theme polling (auto mode) ──
    Timer {
        id: themePollTimer
        interval: 3000
        running: settingsBackend.theme_mode === "auto"
        repeat: true
        onTriggered: {
            var systemDark = themeDetector.detect()
            Theme.setDarkMode(systemDark === true)
        }
    }

    Connections {
        target: settingsBackend
        function onSettings_jsonChanged() {
            mainWindow.applyAccessibilityAppearance()
            mainWindow.syncTrayPreference()
        }
    }

    // ── Watch for theme_mode changes from SettingsWindow ──
    Connections {
        target: settingsBackend
        function onTheme_modeChanged() {
            if (settingsBackend.theme_mode === "auto") {
                var systemDark = themeDetector.detect()
                Theme.setDarkMode(systemDark === true)
                themePollTimer.running = true
            } else if (settingsBackend.theme_mode === "dark") {
                Theme.setDarkMode(true)
                themePollTimer.running = false
            } else {
                Theme.setDarkMode(false)
                themePollTimer.running = false
            }
        }
    }

    // ── Watch for custom_primary_color changes from SettingsWindow ──
    Connections {
        target: settingsBackend
        function onCustom_primary_colorChanged() {
            Theme.setCustomPrimaryColor(settingsBackend.custom_primary_color)
        }
    }

    Timer {
        id: deviceRefreshTimer
        interval: 500
        running: false
        repeat: true
        onTriggered: {
            discoverManager.refresh_devices()
            var jsonStr = discoverManager.devices_json
            try {
                discoveredDevices = JSON.parse(jsonStr)
            } catch(e) {
                discoveredDevices = []
            }
            if (!discoverManager.scanning) {
                deviceRefreshTimer.stop()
                scanning = false
            }
        }
    }

    Timer {
        id: scanTimer
        interval: 2000
        repeat: false
        onTriggered: {
            if (discoverManager.scanning) {
                discoverManager.refresh_devices()
                discoverManager.stop_scan()
            }
        }
    }

    Connections {
        target: shareManager
        function onActive_config_jsonChanged() {
            if (shareManager.active_config_json !== "" && shareManager.active_config_json !== mainWindow.loadedConfig) {
                mainWindow.appliedSharedConfig = shareManager.active_config_json
                mainWindow.loadConfigFromJson(shareManager.active_config_json)
            }
        }
    }

    Timer {
        id: shareRefreshTimer
        interval: 500
        running: true
        repeat: true
        onTriggered: {
            shareManager.refresh()
            var pending = []
            try { pending = JSON.parse(shareManager.pending_shares_json) } catch (e) {}
            if (pending.length > 0 && !incomingShareDialog.visible) {
                incomingShareDialog.share = pending[0]
                incomingShareDialog.open()
            }
        }
    }

    Dialog {
        id: incomingShareDialog
        property var share: null
        title: "收到远程配置"
        modal: true
        anchors.centerIn: parent
        closePolicy: Popup.NoAutoClose
        standardButtons: Dialog.NoButton
        padding: Theme.spacing24
        background: Rectangle {
            color: Theme.materialOverlay
            radius: Theme.radiusLarge
            border.color: Theme.hairline
            border.width: 1
        }
        contentItem: ColumnLayout {
            spacing: Theme.spacing12
            Text { text: incomingShareDialog.share ? ("设备：" + incomingShareDialog.share.sender_name) : ""; color: Theme.foreground; font.family: Theme.fontSans }
            Text { text: incomingShareDialog.share ? ("配置：" + incomingShareDialog.share.exam_name + "（" + incomingShareDialog.share.exam_count + " 场考试）") : ""; color: Theme.mutedForeground; font.family: Theme.fontSans; wrapMode: Text.WordWrap }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                PinguoButton {
                    text: "拒绝"
                    variant: PinguoButton.Secondary
                    onClicked: {
                        if (incomingShareDialog.share) shareManager.reject_share(incomingShareDialog.share.share_id)
                        incomingShareDialog.close()
                    }
                }
                PinguoButton {
                    text: "接受"
                    variant: PinguoButton.Hero
                    onClicked: {
                        if (incomingShareDialog.share) {
                            var json = shareManager.approve_share(incomingShareDialog.share.share_id)
                            if (json !== "") {
                                mainWindow.appliedSharedConfig = json
                                mainWindow.loadConfigFromJson(json)
                            }
                        }
                        incomingShareDialog.close()
                    }
                }
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // Page transition: short fade between pages (HIG motionShort)
    // ═══════════════════════════════════════════════════════════════
    Behavior on opacity {
        NumberAnimation { duration: Theme.motionShort; easing.type: Theme.motionStandard }
    }

    // ═══════════════════════════════════════════════════════════════
    // Main layout: Sidebar (HIG 160-180pt) + Content
    // ═══════════════════════════════════════════════════════════════
    RowLayout {
        anchors.fill: parent
        spacing: 0 // sidebar and content are edge-to-edge; 0 is intentional

        // Left sidebar — strongest continuous glass navigation layer
        GlassSurface {
            Layout.preferredWidth: mainWindow.sidebarWidth
            Layout.fillHeight: true
            variant: GlassSurface.Navigation
            radius: 0
            bordered: true

            // 1px hairline on right edge of sidebar
            Rectangle {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 1
                color: Theme.hairline
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.topMargin: Theme.spacing24
                anchors.bottomMargin: Theme.spacing24
                anchors.leftMargin: Theme.spacing16
                anchors.rightMargin: Theme.spacing16
                spacing: Theme.spacing12

                Text {
                    Layout.fillWidth: true
                    text: "Aeterna"
                    color: Theme.primary
                    font.pixelSize: Theme.typeTitle3
                    font.weight: Theme.weightBold
                    font.family: Theme.fontSans
                    horizontalAlignment: Text.AlignHCenter
                    Layout.bottomMargin: Theme.spacing24
                }

                ListView {
                    id: navList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    model: navModel
                    currentIndex: mainWindow.currentPage
                    spacing: Theme.spacing4
                    clip: true

                    delegate: NavItem {
                        text: name
                        icon: icon
                        selected: index === navList.currentIndex
                        onClicked: {
                            var action = navModel.get(index).action
                            if (action === "player") {
                                mainWindow.enterPlayerPage()
                            } else {
                                mainWindow.currentPage = index
                                if (action === "discover") {
                                    mainWindow.refreshDiscover()
                                }
                            }
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: "v" + appInfo.version
                    color: Theme.mutedForeground
                    font.pixelSize: Theme.typeCaption2
                    font.family: Theme.fontSans
                    horizontalAlignment: Text.AlignHCenter
                    Layout.topMargin: Theme.spacing12
                    elide: Text.ElideRight
                }
            }
        }

        // Right content area — Material.Base
        StackLayout {
            id: contentStack
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: mainWindow.currentPage

            // ── Page 0: Home ─────────────────────────────────────
            Rectangle {
                color: Theme.background

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: Theme.spacing12

                    Text {
                        text: "Aeterna"
                        font.pixelSize: Theme.typeLargeTitle
                        font.weight: Theme.weightBold
                        font.family: Theme.fontSans
                        color: Theme.foreground
                        horizontalAlignment: Text.AlignHCenter
                        Layout.alignment: Qt.AlignHCenter
                    }
                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: Theme.spacing8
                        visible: mainWindow.configValid
                        Icon {
                            name: "checkmark.circle"
                            size: 16
                            tier: Icon.Success
                        }
                        Text {
                            text: "已加载 " + mainWindow.examCount + " 场考试"
                            font.pixelSize: Theme.typeFootnote
                            font.family: Theme.fontSans
                            color: Theme.success
                            horizontalAlignment: Text.AlignHCenter
                            Layout.alignment: Qt.AlignHCenter
                        }
                    }

                    // ── Grid container (Material.Elevated) ──
                    Material {
                        id: gridContainer
                        Layout.preferredWidth: Math.min(Theme.spacing128 * 5, Math.max(Theme.spacing128 * 4, contentStack.width - mainWindow.contentMargin * 2))
                        Layout.preferredHeight: Math.min(300, mainWindow.height - mainWindow.contentMargin * 2)
                        tier: Material.Elevated
                        radius: Theme.radiusXlarge
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: mainWindow.contentSpacing
                        clip: true

                        // Left arrow
                        Rectangle {
                            id: leftArrow
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.spacing12
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.verticalCenterOffset: -14
                            width: Theme.minHitTarget; height: Theme.minHitTarget
                            radius: Theme.radiusPill
                            color: Theme.secondaryFill
                            opacity: mainWindow.homePageIndex > 0 ? 0.9 : 0.3
                            visible: mainWindow.homeTotalPages > 1

                            Icon {
                                anchors.centerIn: parent
                                name: "arrow.left"
                                size: 16
                                tier: mainWindow.homePageIndex > 0 ? Icon.Primary : Icon.Tertiary
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: mainWindow.homePageIndex > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
                                enabled: mainWindow.homePageIndex > 0
                                onClicked: mainWindow.homePageIndex--
                            }
                        }

                        // Right arrow
                        Rectangle {
                            id: rightArrow
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.spacing12
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.verticalCenterOffset: -14
                            width: Theme.minHitTarget; height: Theme.minHitTarget
                            radius: Theme.radiusPill
                            color: Theme.secondaryFill
                            opacity: mainWindow.homePageIndex < mainWindow.homeTotalPages - 1 ? 0.9 : 0.3
                            visible: mainWindow.homeTotalPages > 1

                            Icon {
                                anchors.centerIn: parent
                                name: "arrow.right"
                                size: 16
                                tier: mainWindow.homePageIndex < mainWindow.homeTotalPages - 1 ? Icon.Primary : Icon.Tertiary
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: mainWindow.homePageIndex < mainWindow.homeTotalPages - 1 ? Qt.PointingHandCursor : Qt.ArrowCursor
                                enabled: mainWindow.homePageIndex < mainWindow.homeTotalPages - 1
                                onClicked: mainWindow.homePageIndex++
                            }
                        }

                        // Button grid
                        Grid {
                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: -10
                            columns: 4
                            columnSpacing: Theme.spacing12
                            rowSpacing: Theme.spacing12

                            Repeater {
                                model: 8
                                delegate: Rectangle {
                                    id: btnCard
                                    property int btnIndex: mainWindow.homePageIndex * 8 + index
                                    property bool hasBtn: btnIndex < homeButtonsModel.count
                                    visible: hasBtn
                                    width: 96
                                    height: 110
                                    color: btnHover ? Qt.alpha(Theme.primary, 0.10) : Theme.accent
                                    radius: Theme.radiusLarge
                                    border.color: Theme.hairlineOnAccent
                                    border.width: 1
                                    scale: btnPressed ? 0.96 : (btnHover ? 1.03 : 1.0)
                                    Behavior on color  { ColorAnimation  { duration: Theme.motionShort; easing.type: Theme.motionStandard } }
                                    Behavior on scale  { NumberAnimation { duration: Theme.motionShort; easing.type: Theme.motionStandard } }

                                    property bool btnHover: false
                                    property bool btnPressed: false
                                    property var btnData: hasBtn ? homeButtonsModel.get(btnIndex) : null

                                    ColumnLayout {
                                        anchors.centerIn: parent
                                        spacing: Theme.spacing8

                                        Icon {
                                            name: btnData ? btnData.iconName : "circle.fill"
                                            size: 24
                                            tier: Icon.Accent
                                            Layout.alignment: Qt.AlignHCenter
                                        }
                                        Text {
                                            text: btnData ? btnData.label : ""
                                            font.pixelSize: Theme.typeFootnote
                                            font.family: Theme.fontSans
                                            color: Theme.foreground
                                            horizontalAlignment: Text.AlignHCenter
                                            Layout.alignment: Qt.AlignHCenter
                                            Layout.maximumWidth: btnCard.width - Theme.spacing16
                                            elide: Text.ElideRight
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        hoverEnabled: true
                                        onEntered: btnCard.btnHover = true
                                        onExited:  btnCard.btnHover = false
                                        onPressed: btnCard.btnPressed = true
                                        onReleased: btnCard.btnPressed = false
                                        onClicked: {
                                            if (!btnData) return
                                            var action = btnData.action
                                            console.log("Home button clicked:", action)
                                            if (action === "openEditor") {
                                                editorLoader.openEditor()
                                            } else if (action === "player") {
                                                mainWindow.enterPlayerPage()
                                            } else if (action === "urlPlayer") {
                                                urlPlayerDialog.open()
                                            } else if (action === "openSettings") {
                                                settingsLoader.openSettings()
                                            } else if (action === "openPlugins") {
                                                pluginLoader.openPlugins()
                                            } else if (action === "openAbout") {
                                                aboutDialog.open()
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Pagination dots — HIG "Page indicator" style
                        Row {
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: Theme.spacing16
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: Theme.spacing12
                            visible: mainWindow.homeTotalPages > 1

                            Repeater {
                                model: mainWindow.homeTotalPages
                                delegate: Rectangle {
                                    width: 8; height: 8
                                    radius: Theme.radiusPill
                                    color: index === mainWindow.homePageIndex ? Theme.primary : "transparent"
                                    border.color: index === mainWindow.homePageIndex ? Theme.primary : Theme.tertiaryFill
                                    border.width: 1
                                    Behavior on color {
                                        ColorAnimation { duration: Theme.motionShort; easing.type: Theme.motionStandard }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        anchors.margins: -4
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: mainWindow.homePageIndex = index
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ── Page 1: Discover ──────────────────────────────────
            Rectangle {
                color: Theme.background
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: mainWindow.contentMargin
                    spacing: mainWindow.contentSpacing

                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: "设备发现"
                            font.pixelSize: Theme.typeTitle2
                            font.weight: Theme.weightBold
                            font.family: Theme.fontSans
                            color: Theme.foreground
                        }
                        Item { Layout.fillWidth: true }
                        PinguoButton {
                            text: scanning ? "扫描中..." : "刷新扫描"
                            variant: PinguoButton.Hero
                            enabled: !scanning
                            onClicked: mainWindow.refreshDiscover()
                        }
                    }

                    // Card: device list (Material.Elevated)
                    Material {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        tier: Material.Elevated
                        radius: Theme.radiusLarge

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: Theme.spacing24
                            spacing: Theme.spacing12

                            Text {
                                text: "局域网设备列表"
                                font.pixelSize: Theme.typeHeadline
                                font.weight: Theme.weightSemibold
                                font.family: Theme.fontSans
                                color: Theme.foreground
                            }
                            Rectangle {
                                Layout.fillWidth: true
                                height: 1
                                color: Theme.hairline
                            }

                            ListView {
                                id: deviceList
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                model: mainWindow.discoveredDevices
                                spacing: Theme.spacing8
                                clip: true

                                delegate: Rectangle {
                                    width: ListView.view.width
                                    height: Theme.sizeListItemLarge
                                    color: "transparent"
                                    radius: Theme.radiusMedium

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: Theme.spacing16
                                        anchors.rightMargin: Theme.spacing16
                                        spacing: Theme.spacing12

                                        Icon {
                                            size: 16
                                            tier: modelData.share_supported ? Icon.Success : Icon.Secondary
                                            name: modelData.share_supported ? "checkmark.circle" : "xmark"
                                            accessibleName: modelData.status
                                            Layout.alignment: Qt.AlignVCenter
                                        }
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: Theme.spacing4
                                            Text {
                                                text: modelData.name
                                                color: Theme.foreground
                                                font.pixelSize: Theme.typeSubhead
                                                font.family: Theme.fontSans
                                            }
                                            Text {
                                                text: modelData.endpoint + (modelData.share_supported ? " · 已验证分享能力" : " · 未开放受认证分享")
                                                color: Theme.mutedForeground
                                                font.pixelSize: Theme.typeCaption1
                                                font.family: Theme.fontSans
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                        }
                                        PinguoButton {
                                            text: "发送配置"
                                            variant: PinguoButton.Secondary
                                            enabled: mainWindow.configValid && modelData.share_supported
                                            onClicked: shareManager.share_current_config_to(modelData.id)
                                        }
                                        Text {
                                            text: modelData.status
                                            color: modelData.share_supported ? Theme.success : Theme.mutedForeground
                                            font.pixelSize: Theme.typeFootnote
                                            font.family: Theme.fontSans
                                            Layout.alignment: Qt.AlignVCenter
                                        }
                                    }
                                }
                            }

                            Text {
                                text: scanning ? "正在扫描局域网设备..." : "未发现设备，点击「刷新扫描」开始搜索"
                                color: Theme.mutedForeground
                                font.pixelSize: Theme.typeFootnote
                                font.family: Theme.fontSans
                                horizontalAlignment: Text.AlignHCenter
                                Layout.fillWidth: true
                                visible: mainWindow.discoveredDevices.length === 0
                                Layout.fillHeight: true
                                verticalAlignment: Text.AlignVCenter
                            }
                        }
                    }

                    Text {
                        text: "Aeterna 使用 mDNS 协议在局域网内自动发现设备，支持跨平台互联。"
                        color: Theme.mutedForeground
                        font.pixelSize: Theme.typeCaption1
                        font.family: Theme.fontSans
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                }
            }

            // ── Page 2: Player Home ───────────────────────────────
            Rectangle {
                color: Theme.background
                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: mainWindow.contentSpacing
                    Text {
                        text: "播放器主页"
                        font.pixelSize: Theme.typeTitle2
                        font.family: Theme.fontSans
                        color: Theme.foreground
                        Layout.alignment: Qt.AlignHCenter
                    }
                    Text {
                        text: mainWindow.configValid ? "已加载 " + mainWindow.examCount + " 场考试" : "未加载考试配置"
                        font.pixelSize: Theme.typeSubhead
                        font.family: Theme.fontSans
                        color: Theme.mutedForeground
                        Layout.alignment: Qt.AlignHCenter
                    }
                    PinguoButton {
                        text: "重新选择配置"
                        variant: PinguoButton.Secondary
                        onClicked: {
                            playerConfigDialog.refreshRecentFile()
                            playerConfigDialog.open()
                        }
                        Layout.alignment: Qt.AlignHCenter
                    }
                    PinguoButton {
                        text: "启动全屏播放器"
                        variant: PinguoButton.Hero
                        enabled: mainWindow.configValid
                        onClicked: playerLoader.openPlayer()
                        Layout.alignment: Qt.AlignHCenter
                    }
                }
            }

        }
    }

    // ── File dialog ───────────────────────────────────────────
    Platform.FileDialog {
        id: fileDialog
        title: "打开考试配置"
        nameFilters: ["Aeterna 配置文件 (*.aeterna *.json)", "所有文件 (*)"]
        onAccepted: {
            mainWindow.loadConfigFromUrl(fileDialog.file)
        }
    }

    // ── Player config prompt dialog ───────────────────────────
    Dialog {
        id: playerConfigDialog
        title: "未加载考试配置"
        modal: true
        anchors.centerIn: parent
        padding: Theme.spacing24
        closePolicy: Popup.CloseOnEscape
        standardButtons: Dialog.NoButton

        property string recentFilePath: ""
        property bool hasRecentFile: recentFilePath.length > 0

        background: Rectangle {
            color: Theme.materialOverlay
            radius: Theme.radiusLarge
            border.color: Theme.hairline
            border.width: 1
        }

        enter: Transition {
            NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: Theme.motionMedium; easing.type: Theme.motionDecelerate }
        }
        exit: Transition {
            NumberAnimation { property: "opacity"; from: 1.0; to: 0.0; duration: Theme.motionShort; easing.type: Theme.motionAccelerate }
        }

        function refreshRecentFile() {
            try {
                var list = JSON.parse(recentFilesModel.recent_files_json)
                if (Array.isArray(list) && list.length > 0 && list[0]) {
                    recentFilePath = list[0]
                } else {
                    recentFilePath = ""
                }
            } catch (e) {
                recentFilePath = ""
            }
        }

        ColumnLayout {
            spacing: Theme.spacing12
            implicitWidth: 360

            Text {
                text: "未加载考试配置"
                font.pixelSize: Theme.typeHeadline
                font.weight: Theme.weightBold
                font.family: Theme.fontSans
                color: Theme.foreground
            }

            Text {
                text: "当前没有加载考试配置，无法启动放映器。请选择操作："
                color: Theme.mutedForeground
                font.pixelSize: Theme.typeBody
                font.family: Theme.fontSans
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            Text {
                text: "编辑器最近配置："
                color: Theme.mutedForeground
                font.pixelSize: Theme.typeCaption1
                font.family: Theme.fontSans
                visible: playerConfigDialog.hasRecentFile
            }

            Text {
                text: playerConfigDialog.recentFilePath
                color: Theme.mutedForeground
                font.pixelSize: Theme.typeCaption1
                font.family: Theme.fontSans
                wrapMode: Text.WrapAnywhere
                Layout.fillWidth: true
                visible: playerConfigDialog.hasRecentFile
            }

            Text {
                text: "没有编辑器最近打开的配置文件"
                color: Theme.mutedForeground
                font.pixelSize: Theme.typeCaption1
                font.family: Theme.fontSans
                visible: !playerConfigDialog.hasRecentFile
            }
        }

        footer: RowLayout {
            spacing: Theme.spacing12
            Layout.margins: Theme.spacing16

            Item { Layout.fillWidth: true }

            PinguoButton {
                text: "取消"
                variant: PinguoButton.Text
                onClicked: playerConfigDialog.close()
            }
            PinguoButton {
                text: "选择配置文件"
                variant: PinguoButton.Secondary
                onClicked: {
                    playerConfigDialog.close()
                    fileDialog.open()
                }
            }
            PinguoButton {
                text: "使用编辑器最近配置"
                variant: PinguoButton.Primary
                enabled: playerConfigDialog.hasRecentFile
                onClicked: {
                    playerConfigDialog.close()
                    mainWindow.loadConfigFromUrl(playerConfigDialog.recentFilePath)
                }
            }
        }
    }

    // ── About dialog ──
    AboutDialog {
        id: aboutDialog
    }

    Dialog {
        id: pluginsComingSoonDialog
        title: "插件功能即将上线"
        modal: true
        anchors.centerIn: parent
        width: 360
        padding: Theme.spacing24
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        standardButtons: Dialog.NoButton
        background: Rectangle {
            color: Theme.materialOverlay
            radius: Theme.radiusLarge
            border.width: 1
            border.color: Theme.hairline
        }
        contentItem: ColumnLayout {
            spacing: Theme.spacing16
            Icon {
                name: "puzzle"
                size: 28
                tier: Icon.Tertiary
                Layout.alignment: Qt.AlignHCenter
            }
            Text {
                Layout.fillWidth: true
                text: "插件服务仍在完善中，暂不支持安装、卸载或从商店下载插件。"
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                color: Theme.foreground
                font.pixelSize: Theme.typeSubhead
                font.family: Theme.fontSans
            }
            PinguoButton {
                text: "知道了"
                variant: PinguoButton.Primary
                Layout.alignment: Qt.AlignHCenter
                onClicked: pluginsComingSoonDialog.close()
            }
        }
    }

    // ── Hint tooltip ──────────────────────────────────────────
    ToolTip {
        id: hintToolTip
        delay: 0
        timeout: 2000
        visible: false
        padding: Theme.spacing12
        contentItem: Text {
            text: hintToolTip.text
            color: Theme.foreground
            font.pixelSize: Theme.typeCaption1
            font.family: Theme.fontSans
        }
        background: Rectangle {
            color: Theme.materialOverlay
            radius: Theme.radiusSmall
            border.color: Theme.hairline
            border.width: 1
        }
    }

    // ── URL Player dialog ────────────────────────────────────
    Dialog {
        id: urlPlayerDialog
        title: "从 URL 放映"
        modal: true
        anchors.centerIn: parent
        padding: Theme.spacing24
        closePolicy: Popup.CloseOnEscape
        standardButtons: Dialog.NoButton

        background: Rectangle {
            color: Theme.materialOverlay
            radius: Theme.radiusLarge
            border.color: Theme.hairline
            border.width: 1
        }

        enter: Transition {
            NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: Theme.motionMedium; easing.type: Theme.motionDecelerate }
        }
        exit: Transition {
            NumberAnimation { property: "opacity"; from: 1.0; to: 0.0; duration: Theme.motionShort; easing.type: Theme.motionAccelerate }
        }

        ColumnLayout {
            spacing: Theme.spacing12
            implicitWidth: 400

            Text {
                text: "从 URL 加载考试配置"
                font.pixelSize: Theme.typeHeadline
                font.weight: Theme.weightBold
                font.family: Theme.fontSans
                color: Theme.foreground
            }

            Text {
                text: "输入考试配置文件的 URL 地址，支持 HTTP/HTTPS 或本地文件路径。"
                color: Theme.mutedForeground
                font.pixelSize: Theme.typeBody
                font.family: Theme.fontSans
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            PinguoTextField {
                id: urlInputField
                Layout.fillWidth: true
                placeholderText: "https://example.com/exam.aeterna"
                inputItem.selectByMouse: true
            }

            Text {
                id: urlErrorText
                visible: false
                text: ""
                color: Theme.destructive
                font.pixelSize: Theme.typeCaption1
                font.family: Theme.fontSans
            }
        }

        footer: RowLayout {
            spacing: Theme.spacing12
            Layout.margins: Theme.spacing16

            Item { Layout.fillWidth: true }

            PinguoButton {
                text: "取消"
                variant: PinguoButton.Text
                onClicked: urlPlayerDialog.close()
            }
            PinguoButton {
                text: "加载"
                variant: PinguoButton.Primary
                onClicked: {
                    var url = urlInputField.text.trim()
                    if (url.length === 0) {
                        urlErrorText.text = "请输入有效的 URL 或文件路径"
                        urlErrorText.visible = true
                        return
                    }
                    urlErrorText.visible = false
                    urlPlayerDialog.close()
                    mainWindow.loadConfigFromUrl(url)
                    mainWindow.enterPlayerPage()
                }
            }
        }
    }

    // ── Home buttons model (grid pagination) ──────────────────
    property int homePageIndex: 0
    readonly property int homeTotalPages: Math.max(1, Math.ceil(homeButtonsModel.count / 8))
    ListModel {
        id: homeButtonsModel
        ListElement { label: "编辑器";     iconName: "doc";          action: "openEditor";     hint: "" }
        ListElement { label: "放映器";     iconName: "play";         action: "player";         hint: "" }
        ListElement { label: "从URL放映";  iconName: "link";         action: "urlPlayer";      hint: "" }
        ListElement { label: "设置";       iconName: "gear";         action: "openSettings";   hint: "" }
        ListElement { label: "插件服务";   iconName: "puzzle";       action: "openPlugins";     hint: "本地清单" }
        ListElement { label: "帮助";       iconName: "questionmark"; action: "openAbout";      hint: "" }
        ListElement { label: "关于";       iconName: "info";         action: "openAbout";      hint: "" }
    }

    // ── Navigation model (sidebar items) ──────────────────────
    ListModel {
        id: navModel
        ListElement { name: "主页";     icon: "house";         action: "home" }
        ListElement { name: "发现";     icon: "magnifyingglass"; action: "discover" }
        ListElement { name: "放映器";   icon: "film";          action: "player" }
    }

    // ── Window loaders ───────────────────────────────────────
    Loader {
        id: editorLoader
        function openEditor() {
            var comp = Qt.createComponent("qrc:/qml/EditorWindow.qml")
            function doCreate() {
                if (comp.status !== Component.Ready) {
                    console.error("EditorWindow not ready: " + comp.errorString())
                    return
                }
                var win = comp.createObject(mainWindow)
                if (!win) {
                    console.error("Failed to create EditorWindow instance")
                    return
                }
                win.show()
            }
            if (comp.status === Component.Ready) {
                doCreate()
            } else if (comp.status === Component.Error) {
                console.error("Failed to load EditorWindow: " + comp.errorString())
            } else {
                comp.statusChanged.connect(doCreate)
            }
        }
    }

    Loader {
        id: playerLoader
        function openPlayer() {
            var comp = Qt.createComponent("qrc:/qml/PlayerWindow.qml")
            function doCreate() {
                if (comp.status !== Component.Ready) {
                    console.error("PlayerWindow not ready: " + comp.errorString())
                    return
                }
                var win = comp.createObject(mainWindow)
                if (!win) {
                    console.error("Failed to create PlayerWindow instance")
                    return
                }
                mainWindow.activePlayerWindow = win
                win.destroyed.connect(function() {
                    if (mainWindow.activePlayerWindow === win) mainWindow.activePlayerWindow = null
                })
                win.showFullScreen()
                if (mainWindow.loadedConfig && win.loadExamData) {
                    win.loadExamData(mainWindow.loadedConfig)
                }
            }
            if (comp.status === Component.Ready) {
                doCreate()
            } else if (comp.status === Component.Error) {
                console.error("Failed to load PlayerWindow: " + comp.errorString())
            } else {
                comp.statusChanged.connect(doCreate)
            }
        }
    }

    Loader {
        id: pluginLoader
        function openPlugins() {
            var comp = Qt.createComponent("qrc:/qml/PluginStoreWindow.qml")
            function doCreate() {
                if (comp.status !== Component.Ready) {
                    console.error("PluginStoreWindow not ready: " + comp.errorString())
                    return
                }
                var win = comp.createObject(mainWindow)
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

    Loader {
        id: settingsLoader

        function normalizeCategory(category) {
            return typeof category === "string" && category !== "" ? category : "basic"
        }

        function activateSettingsWindow(win, category) {
            if (win.selectCategory) win.selectCategory(category)
            win.show()
            win.raise()
            win.requestActivate()
        }

        function openSettings(category) {
            var requestedCategory = normalizeCategory(category)
            if (mainWindow.activeSettingsWindow) {
                activateSettingsWindow(mainWindow.activeSettingsWindow, requestedCategory)
                return
            }

            mainWindow.pendingSettingsCategory = requestedCategory
            if (mainWindow.settingsCreationPending) return

            mainWindow.settingsCreationPending = true
            var comp = Qt.createComponent("qrc:/qml/SettingsWindow.qml")
            var finished = false
            function finishCreation() {
                if (finished) return
                if (comp.status === Component.Error) {
                    finished = true
                    mainWindow.settingsCreationPending = false
                    console.error("Failed to load SettingsWindow: " + comp.errorString())
                    return
                }
                if (comp.status !== Component.Ready) return

                finished = true
                var win = comp.createObject(mainWindow, {
                    "settingsBackend": settingsBackend,
                    "trayIconAvailable": trayIcon.available,
                    "initialCategory": mainWindow.pendingSettingsCategory
                })
                mainWindow.settingsCreationPending = false
                if (!win) {
                    console.error("Failed to create SettingsWindow instance")
                    return
                }

                mainWindow.activeSettingsWindow = win
                win.destroyed.connect(function() {
                    if (mainWindow.activeSettingsWindow === win) {
                        mainWindow.activeSettingsWindow = null
                    }
                })
                activateSettingsWindow(win, mainWindow.pendingSettingsCategory)
            }

            if (comp.status === Component.Ready || comp.status === Component.Error) {
                finishCreation()
            } else {
                comp.statusChanged.connect(finishCreation)
            }
        }
    }

}
