import QtQuick 2.15
import "."
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Aeterna 1.0

ApplicationWindow {
    id: playerWindow
    width: Screen.width
    height: Screen.height
    title: "Aeterna 播放器"
    color: Theme.background
    visibility: "FullScreen"
    flags: Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint

    

    PlayerBackend { id: playerBackend }
    AppInfo     { id: appInfo }

    Component.onCompleted: {
        playerBackend.loadPlayerSettings()
        initToolbar()
        applyAutoScale()
        playerBackend.start()
        contentRoot.forceActiveFocus()
    }

    onClosing: {
        playerBackend.stop()
    }

    // ═══════════════════════════════════════════════════════════════
    // State
    // ═══════════════════════════════════════════════════════════════
    property bool autoScaleApplied: true
    property string __currentAlertKey: ""
    property var toolbarCallbacks: []
    property int __exitPasswordAttempts: 0
    property int __exitCooldownSeconds: 0

    // Intermediary values for PlaybackSettingsDrawer — breaks binding loops
    // by serving as a one-way buffer between backend props and drawer.
    property real settingsUiScale: playerBackend.uiScale
    property string settingsDensity: playerBackend.density
    property bool settingsBigClock: playerBackend.bigClock
    property real settingsBigClockFontSize: playerBackend.bigClockFontSize
    property bool settingsLargeInfoFont: playerBackend.largeInfoFont

    readonly property real infoFontScale: playerBackend.largeInfoFont ? 1.3 : 1.0
    readonly property int densitySpacing: {
        if (playerBackend.density === "compact") return Theme.spacing12
        if (playerBackend.density === "cozy") return Theme.spacing16
        return Theme.spacing24
    }

    // Responsive scale driven by the backend uiScale setting.
    // applyAutoScale() sets an initial scale based on screen width;
    // the user can still override it from the playback settings drawer.
    readonly property real contentScale: playerBackend.uiScale

    // ═══════════════════════════════════════════════════════════════
    // Timers
    // ═══════════════════════════════════════════════════════════════
    Timer {
        id: tickTimer
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            playerBackend.refresh()
            syncFromBackend()
        }
    }

    Timer {
        id: exitCooldownTimer
        interval: 1000
        running: __exitCooldownSeconds > 0
        repeat: true
        onTriggered: {
            if (__exitCooldownSeconds > 0) {
                __exitCooldownSeconds--
            }
        }
    }

    Timer {
        id: topmostEnforcer
        interval: 500
        running: playerWindow.visibility === Window.FullScreen
        repeat: true
        onTriggered: {
            playerWindow.raise()
            playerWindow.requestActivate()
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // Backend sync / public API
    // ═══════════════════════════════════════════════════════════════
    function syncFromBackend() {
        try {
            var list = JSON.parse(playerBackend.examListJson)
            examListModel.clear()
            for (var i = 0; i < list.length; i++) {
                examListModel.append({
                    name: list[i].name,
                    timeRange: list[i].timeRange,
                    status: list[i].status,
                    statusText: list[i].statusText,
                    date: list[i].date
                })
            }
        } catch (e) { }
        try {
            var mats = JSON.parse(playerBackend.materialsJson)
            materialsListModel.clear()
            for (var j = 0; j < mats.length; j++) {
                materialsListModel.append({
                    name: mats[j].name,
                    quantity: mats[j].quantity,
                    unit: mats[j].unit
                })
            }
        } catch (e) { }
    }

    function loadExamData(config) {
        var json = (typeof config === "string") ? config : JSON.stringify(config)
        playerBackend.loadConfig(json)
        syncFromBackend()
    }

    function loadConfigFile(fileUrl) {
        var url = fileUrl
        if (url.indexOf("://") < 0) {
            if (url.indexOf("/") === 0) url = "file://" + url
            else url = ""
        }
        if (!url) return
        var xhr = new XMLHttpRequest()
        xhr.open("GET", url, false)
        xhr.send()
        try {
            var config = JSON.parse(xhr.responseText)
            if (config && config.examInfos) {
                loadExamData(config)
            }
        } catch (e) {
            console.error("PlayerWindow: failed to load config file:", e)
        }
    }

    function requestExit() {
        if (__exitCooldownSeconds > 0) {
            alertOverlay.show("warning", "退出冷却中", "请等待 " + __exitCooldownSeconds + " 秒后再试")
            return
        }
        if (playerBackend.exitPasswordEnabled) {
            exitPasswordKeypad.currentNumber = ""
            exitPasswordKeypad.visible = true
        } else {
            exitConfirmDialog.open()
        }
    }

    function applyAutoScale() {
        if (!autoScaleApplied) return
        var s
        if (playerWindow.width >= 1920) s = 1.15
        else if (playerWindow.width >= 1440) s = 1.0
        else if (playerWindow.width >= 1024) s = 0.92
        else s = 0.78
        if (Math.abs(playerBackend.uiScale - s) > 0.001) {
            playerBackend.setUiScale(s)
        }
    }

    onWidthChanged: applyAutoScale()

    function formatRoomNumber(room) {
        var s = String(room || "01")
        if (s.length < 2) return "0" + s
        return s
    }

    // ═══════════════════════════════════════════════════════════════
    // Toolbar registry (kept for plugin compatibility)
    // ═══════════════════════════════════════════════════════════════
    ListModel { id: toolbarItems }

    function initToolbar() {
        toolbarItems.append({ icon: "gear", label: "设置", danger: false, builtIn: true, action: "settings" })
        toolbarItems.append({ icon: "square.grid.2x2", label: "密度", danger: false, builtIn: true, action: "density" })
        toolbarItems.append({ icon: "clock", label: "时钟", danger: false, builtIn: true, action: "clock" })
        toolbarItems.append({ icon: "minus", label: "收起", danger: false, builtIn: true, action: "collapse" })
        toolbarItems.append({ icon: "power", label: "退出", danger: true, builtIn: true, action: "exit" })
        toolbarCallbacks = [null, null, null, null, null]
    }

    function registerToolbarItem(icon, label, danger, callback) {
        toolbarItems.append({ icon: icon, label: label, danger: danger, builtIn: false, action: "" })
        toolbarCallbacks.push(callback)
    }

    function unregisterToolbarItem(index) {
        if (index < 0 || index >= toolbarItems.count) return
        if (toolbarItems.get(index).builtIn) return
        toolbarItems.remove(index)
        toolbarCallbacks.splice(index, 1)
    }

    function handleToolbarAction(action, index) {
        if (action === "settings") {
            settingsDrawer.visible = true
        } else if (action === "density") {
            toggleDensity()
        } else if (action === "clock") {
            playerBackend.setBigClock(!playerBackend.bigClock)
        } else if (action === "collapse") {
            playerWindow.visibility = "Windowed"
            playerWindow.flags = Qt.Window
        } else if (action === "exit") {
            requestExit()
        } else if (typeof toolbarCallbacks[index] === "function") {
            toolbarCallbacks[index]()
        }
    }

    function toggleDensity() {
        var next = "comfortable"
        if (playerBackend.density === "comfortable") next = "cozy"
        else if (playerBackend.density === "cozy") next = "compact"
        playerBackend.setDensity(next)
    }

    // ═══════════════════════════════════════════════════════════════
    // Content root (handles focus and key input)
    // ═══════════════════════════════════════════════════════════════
    Item {
        id: contentRoot
        anchors.fill: parent
        focus: true

        Keys.onPressed: {
            if ((event.modifiers & Qt.ControlModifier)
                && (event.key === Qt.Key_Q || event.key === Qt.Key_W || event.key === Qt.Key_R)) {
                event.accepted = true
                return
            }
            if (event.key === Qt.Key_F11) {
                event.accepted = true
                return
            }
            if (event.key === Qt.Key_Escape) {
                requestExit()
                event.accepted = true
                return
            }
        }

        // ═══════════════════════════════════════════════════════════════
        // Header
        // ═══════════════════════════════════════════════════════════════
        RowLayout {
            id: header
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.topMargin: Theme.spacing24 * contentScale
            anchors.leftMargin: Theme.spacing24 * contentScale
            anchors.rightMargin: Theme.spacing24 * contentScale
            spacing: Theme.spacing16 * contentScale

            ColumnLayout {
                spacing: Theme.spacing4 * contentScale

                Text {
                    text: playerBackend.examEventName || "未命名考试"
                    font.pixelSize: Theme.typeTitle1 * contentScale
                    font.weight: Theme.weightBold
                    font.family: Theme.fontSans
                    color: Theme.foreground
                }
                Text {
                    text: playerBackend.message || "考试信息"
                    font.pixelSize: Theme.typeSubhead * contentScale
                    font.family: Theme.fontSans
                    color: Theme.mutedForeground
                }
            }

            Item { Layout.fillWidth: true }

            Material {
                id: roomPill
                Layout.preferredWidth: roomNumberLabel.width + Theme.spacing24 * 2 * contentScale
                Layout.preferredHeight: roomNumberLabel.height + Theme.spacing16 * 2 * contentScale
                tier: Material.Elevated
                radius: Theme.radiusPill

                Text {
                    id: roomNumberLabel
                    anchors.centerIn: parent
                    text: formatRoomNumber(playerBackend.roomNumberSaved || playerBackend.roomNumber || "01")
                    font.pixelSize: Theme.typeTitle1 * contentScale
                    font.family: Theme.fontSans
                    font.weight: Theme.weightBold
                    color: Theme.foreground
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        roomKeypad.currentNumber = roomNumberLabel.text
                        roomKeypad.visible = true
                    }
                }
            }
        }

        // ═══════════════════════════════════════════════════════════════
        // Footer actions
        // ═══════════════════════════════════════════════════════════════
        RowLayout {
            id: footer
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.leftMargin: Theme.spacing24 * contentScale
            anchors.bottomMargin: Theme.spacing24 * contentScale
            spacing: Theme.spacing16 * contentScale
            z: 50

            Material {
                id: exitActionButton
                Layout.preferredWidth: exitActionRow.implicitWidth + Theme.spacing16 * 2 * contentScale
                Layout.preferredHeight: Math.max(44 * contentScale, exitActionRow.implicitHeight + Theme.spacing12 * 2 * contentScale)
                tier: Material.Elevated
                radius: Theme.radiusMedium

                RowLayout {
                    id: exitActionRow
                    anchors.centerIn: parent
                    spacing: Theme.spacing12 * contentScale

                    Icon {
                        name: "arrow.left"
                        size: 20 * contentScale
                        tier: Icon.Primary
                    }
                    Text {
                        text: "退出播放"
                        font.pixelSize: Theme.typeBody * contentScale
                        font.family: Theme.fontSans
                        color: Theme.foreground
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: requestExit()
                }
            }

            Material {
                id: settingsActionButton
                Layout.preferredWidth: settingsActionRow.implicitWidth + Theme.spacing16 * 2 * contentScale
                Layout.preferredHeight: Math.max(44 * contentScale, settingsActionRow.implicitHeight + Theme.spacing12 * 2 * contentScale)
                tier: Material.Elevated
                radius: Theme.radiusMedium

                RowLayout {
                    id: settingsActionRow
                    anchors.centerIn: parent
                    spacing: Theme.spacing12 * contentScale

                    Icon {
                        name: "gear"
                        size: 20 * contentScale
                        tier: Icon.Primary
                    }
                    Text {
                        text: "播放设置"
                        font.pixelSize: Theme.typeBody * contentScale
                        font.family: Theme.fontSans
                        color: Theme.foreground
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: settingsDrawer.visible = true
                }
            }

            Item { Layout.fillWidth: true }
        }

        // ═══════════════════════════════════════════════════════════════
        // Main content grid
        // ═══════════════════════════════════════════════════════════════
        GridLayout {
            id: mainGrid
            anchors.top: header.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: footer.top
            anchors.topMargin: Theme.spacing24 * contentScale
            anchors.leftMargin: Theme.spacing24 * contentScale
            anchors.rightMargin: Theme.spacing24 * contentScale
            anchors.bottomMargin: Theme.spacing24 * contentScale
            columnSpacing: Theme.spacing24 * contentScale
            rowSpacing: Theme.spacing24 * contentScale
            columns: useWideLayout ? 2 : 1
            flow: GridLayout.LeftToRight

            readonly property bool useWideLayout: width > height * 1.25

            // ── Clock card ──
            Material {
                id: clockCard
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: clockContent.implicitHeight + Theme.spacing24 * 2 * contentScale
                Layout.preferredHeight: 300 * contentScale
                tier: Material.Elevated
                radius: Theme.radiusLarge

                ColumnLayout {
                    id: clockContent
                    anchors.centerIn: parent
                    spacing: Theme.spacing12 * contentScale

                    Text {
                        id: clockDisplay
                        text: playerBackend.currentTime
                        font.pixelSize: playerBackend.bigClock
                            ? Math.min(playerBackend.bigClockFontSize * contentScale, clockCard.width * 0.85)
                            : Math.min(180 * contentScale, Math.max(56, clockCard.width * 0.22))
                        font.family: Theme.fontSans
                        font.weight: Theme.weightBold
                        font.letterSpacing: Theme.trackingTight * 72
                        color: Theme.foreground
                        horizontalAlignment: Text.AlignHCenter
                        Layout.alignment: Qt.AlignHCenter
                    }

                    Text {
                        text: playerBackend.currentDate
                        font.pixelSize: Theme.typeTitle3 * contentScale
                        font.family: Theme.fontSans
                        color: Theme.mutedForeground
                        horizontalAlignment: Text.AlignHCenter
                        Layout.alignment: Qt.AlignHCenter
                    }
                }
            }

            // ── Exam list card ──
            Material {
                id: examListCard
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.rowSpan: mainGrid.useWideLayout ? 2 : 1
                Layout.preferredHeight: 500 * contentScale
                tier: Material.Elevated
                radius: Theme.radiusLarge

                ColumnLayout {
                    id: listContent
                    anchors.fill: parent
                    anchors.margins: densitySpacing * contentScale
                    spacing: Theme.spacing16 * contentScale

                    Text {
                        text: "本次考试信息"
                        font.pixelSize: Theme.typeTitle3 * contentScale
                        font.weight: Theme.weightBold
                        font.family: Theme.fontSans
                        color: Theme.foreground
                    }

                    ListView {
                        id: examList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        model: examListModel
                        spacing: Theme.spacing8 * contentScale
                        clip: true

                        delegate: Rectangle {
                            width: ListView.view.width
                            height: Math.max(40 * contentScale, delegateRow.implicitHeight + Theme.spacing12 * 2 * contentScale)
                            radius: Theme.radiusMedium
                            color: index === playerBackend.currentExamIndex
                                ? Qt.alpha(Theme.primary, 0.14)
                                : "transparent"

                            Behavior on color {
                                ColorAnimation {
                                    duration: Theme.motionShort
                                    easing.type: Theme.motionStandard
                                }
                            }

                            RowLayout {
                                id: delegateRow
                                anchors.fill: parent
                                anchors.margins: Theme.spacing12 * contentScale
                                spacing: Theme.spacing12 * contentScale

                                Text {
                                    text: date
                                    color: Theme.mutedForeground
                                    font.pixelSize: Theme.typeCaption1 * contentScale
                                    font.family: Theme.fontSans
                                    Layout.alignment: Qt.AlignVCenter
                                }

                                Text {
                                    text: name
                                    color: Theme.foreground
                                    font.pixelSize: Theme.typeSubhead * contentScale
                                    font.weight: Theme.weightMedium
                                    font.family: Theme.fontSans
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    Layout.alignment: Qt.AlignVCenter
                                }

                                Text {
                                    text: timeRange
                                    color: Theme.mutedForeground
                                    font.pixelSize: Theme.typeCaption1 * contentScale
                                    font.family: Theme.fontSans
                                    Layout.alignment: Qt.AlignVCenter
                                }

                                Rectangle {
                                    radius: Theme.radiusPill
                                    color: {
                                        if (status === "inProgress") return Qt.alpha(Theme.success, 0.18)
                                        if (status === "completed") return Qt.alpha(Theme.mutedForeground, 0.18)
                                        return Qt.alpha(Theme.warning, 0.18)
                                    }
                                    width: statusPillText.implicitWidth + Theme.spacing12 * 2 * contentScale
                                    height: statusPillText.implicitHeight + Theme.spacing4 * 2 * contentScale
                                    Layout.alignment: Qt.AlignVCenter

                                    Text {
                                        id: statusPillText
                                        anchors.centerIn: parent
                                        text: statusText
                                        color: {
                                            if (status === "inProgress") return Theme.success
                                            if (status === "completed") return Theme.mutedForeground
                                            return Theme.warning
                                        }
                                        font.pixelSize: Theme.typeCaption2 * contentScale
                                        font.weight: Theme.weightSemibold
                                        font.family: Theme.fontSans
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ── Current exam info card ──
            Material {
                id: currentInfoCard
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: currentInfoContent.implicitHeight + Theme.spacing24 * 2 * contentScale
                Layout.preferredHeight: 200 * contentScale
                tier: Material.Elevated
                radius: Theme.radiusLarge

                ColumnLayout {
                    id: currentInfoContent
                    anchors.fill: parent
                    anchors.margins: densitySpacing * contentScale
                    spacing: Theme.spacing16 * contentScale

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacing12 * contentScale

                        Text {
                            text: "当前考试信息"
                            font.pixelSize: Theme.typeTitle3 * contentScale * infoFontScale
                            font.weight: Theme.weightBold
                            font.family: Theme.fontSans
                            color: Theme.foreground
                            Layout.fillWidth: true
                        }

                        Rectangle {
                            width: 32 * contentScale
                            height: 32 * contentScale
                            radius: Theme.radiusMedium
                            color: editMouse.containsMouse
                                ? Qt.alpha(Theme.foreground, 0.08)
                                : Qt.alpha(Theme.foreground, 0)

                            Behavior on color {
                                ColorAnimation {
                                    duration: Theme.motionShort
                                    easing.type: Theme.motionStandard
                                }
                            }

                            Icon {
                                name: "gear"
                                size: 20 * contentScale
                                anchors.centerIn: parent
                                tier: Icon.Secondary
                                accessibleName: "打开播放设置"
                            }

                            MouseArea {
                                id: editMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: settingsDrawer.visible = true
                            }
                        }
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        columnSpacing: Theme.spacing32 * contentScale
                        rowSpacing: Theme.spacing12 * contentScale

                        Text {
                            text: "当前科目"
                            font.pixelSize: Theme.typeCaption1 * contentScale * infoFontScale
                            font.family: Theme.fontSans
                            color: Theme.mutedForeground
                        }
                        Text {
                            text: playerBackend.currentExamName
                            font.pixelSize: Theme.typeSubhead * contentScale * infoFontScale
                            font.weight: Theme.weightSemibold
                            font.family: Theme.fontSans
                            color: Theme.foreground
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }

                        Text {
                            text: "考试时间"
                            font.pixelSize: Theme.typeCaption1 * contentScale * infoFontScale
                            font.family: Theme.fontSans
                            color: Theme.mutedForeground
                        }
                        Text {
                            text: playerBackend.currentExamTimeRange
                            font.pixelSize: Theme.typeSubhead * contentScale * infoFontScale
                            font.weight: Theme.weightSemibold
                            font.family: Theme.fontSans
                            color: Theme.foreground
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }

                    ColumnLayout {
                        spacing: Theme.spacing4 * contentScale

                        Text {
                            text: "剩余时间"
                            font.pixelSize: Theme.typeCaption1 * contentScale * infoFontScale
                            font.family: Theme.fontSans
                            color: Theme.mutedForeground
                        }
                        Text {
                            id: countdownText
                            text: playerBackend.remainingTime
                            font.pixelSize: Math.min(56 * contentScale * infoFontScale, Math.max(28, currentInfoCard.width * 0.08))
                            font.family: Theme.fontSans
                            font.weight: Theme.weightBold
                            font.letterSpacing: Theme.trackingTight * 72
                            color: {
                                var thresholdMs = playerBackend.currentExamAlertTime * 60 * 1000
                                if (thresholdMs > 0 && playerBackend.remainingTimeMs > 0 && playerBackend.remainingTimeMs <= thresholdMs) {
                                    return Theme.destructive
                                }
                                return Theme.foreground
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 6 * contentScale
                        radius: Theme.radiusSmall
                        color: Qt.alpha(Theme.foreground, 0.06)

                        Rectangle {
                            id: progressBar
                            height: parent.height
                            radius: Theme.radiusSmall
                            color: Theme.primary
                            width: parent.width * playerBackend.progress
                        }
                    }
                }
            }
        }

        // ═══════════════════════════════════════════════════════════════
        // Watermark
        // ═══════════════════════════════════════════════════════════════
        RowLayout {
            id: watermark
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.rightMargin: Theme.spacing24 * contentScale
            anchors.bottomMargin: Theme.spacing24 * contentScale
            spacing: Theme.spacing8 * contentScale
            z: 45

            Text {
                id: watermarkLogo
                text: "Aeterna"
                font.pixelSize: Theme.typeTitle2 * contentScale
                font.weight: Theme.weightSemibold
                font.family: Theme.fontSans
                color: Qt.alpha(Theme.mutedForeground, 0.35)
            }
            Text {
                id: watermarkVersion
                text: "v" + appInfo.version
                font.pixelSize: Theme.typeCaption1 * contentScale
                font.family: Theme.fontSans
                color: Qt.alpha(Theme.mutedForeground, 0.35)
                Layout.alignment: Qt.AlignBaseline
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // Overlays — rendered inside a full-window Item layered above content.
    // Each child uses z-ordering rather than direct parent assignment so
    // the QML object tree stays consistent with the visual hierarchy.
    // ═══════════════════════════════════════════════════════════════
    Item {
        id: overlayRoot
        anchors.fill: parent
        z: 100

        AlertOverlay {
            id: alertOverlay
            anchors.fill: parent
        }

        // Backdrop shield for settings drawer
        Rectangle {
            anchors.fill: parent
            color: Qt.alpha(Theme.foreground, 0.2)
            visible: settingsDrawer.visible
            z: 150

            MouseArea {
                anchors.fill: parent
                onClicked: settingsDrawer.visible = false
            }
        }

        PlaybackSettingsDrawer {
            id: settingsDrawer
            width: Math.min(360, playerWindow.width * 0.85)
            height: playerWindow.height
            visible: false
            z: 200
            uiScale: settingsUiScale
            density: settingsDensity
            bigClock: settingsBigClock
            bigClockFontSize: settingsBigClockFontSize
            largeInfoFont: settingsLargeInfoFont

            onUiScaleChanged: {
                if (visible) playerWindow.autoScaleApplied = false
                settingsUiScale = uiScale
                playerBackend.setUiScale(uiScale)
            }
            onDensityChanged: {
                settingsDensity = density
                playerBackend.setDensity(density)
            }
            onBigClockChanged: {
                settingsBigClock = bigClock
                playerBackend.setBigClock(bigClock)
            }
            onBigClockFontSizeChanged: {
                settingsBigClockFontSize = bigClockFontSize
                playerBackend.setBigClockFontSize(bigClockFontSize)
            }
            onLargeInfoFontChanged: {
                settingsLargeInfoFont = largeInfoFont
                playerBackend.setLargeInfoFont(largeInfoFont)
            }
            onClosed: visible = false
        }

        // Backdrop shield for room number keypad
        Rectangle {
            anchors.fill: parent
            color: Qt.alpha(Theme.foreground, 0.2)
            visible: roomKeypad.visible
            z: 199

            MouseArea {
                anchors.fill: parent
                onClicked: roomKeypad.visible = false
            }
        }

        // Backdrop shield for exit password keypad
        Rectangle {
            anchors.fill: parent
            color: Qt.alpha(Theme.foreground, 0.2)
            visible: exitPasswordKeypad.visible
            z: 199

            MouseArea {
                anchors.fill: parent
                onClicked: exitPasswordKeypad.visible = false
            }
        }

        RoomNumberKeypad {
            id: roomKeypad
            anchors.centerIn: parent
            visible: false
            z: 200

            onConfirmed: {
                playerBackend.saveRoomNumber(number)
            }
            onCanceled: visible = false
        }

        RoomNumberKeypad {
            id: exitPasswordKeypad
            anchors.centerIn: parent
            visible: false
            z: 200
            title: "输入退出密码"

            onConfirmed: {
                if (playerBackend.checkExitPassword(number)) {
                    __exitPasswordAttempts = 0
                    exitPasswordKeypad.visible = false
                    playerWindow.close()
                } else {
                    __exitPasswordAttempts++
                    var remaining = 3 - __exitPasswordAttempts
                    if (remaining > 0) {
                        alertOverlay.show("warning", "密码错误", "剩余尝试次数：" + remaining)
                        exitPasswordKeypad.currentNumber = ""
                    } else {
                        __exitCooldownSeconds = 30
                        exitPasswordKeypad.visible = false
                        alertOverlay.show("error", "尝试次数过多", "请等待 30 秒后重试")
                    }
                }
            }
            onCanceled: {
                exitPasswordKeypad.visible = false
                exitPasswordKeypad.currentNumber = ""
            }
        }
    }

    // Connections to player backend for reminder events
    Connections {
        target: playerBackend
        function onReminderEvent(kind, title, message) {
            var key = kind + "|" + title + "|" + message
            if (alertOverlay.visible && playerWindow.__currentAlertKey === key) {
                return
            }
            playerWindow.__currentAlertKey = key
            alertOverlay.show(kind, title, message)
        }
    }

    Dialog {
        id: exitConfirmDialog
        title: "退出播放器"
        standardButtons: Dialog.Yes | Dialog.No
        modal: true
        z: 1000

        // Anchor to overlayRoot's coordinate space directly:
        // "Popup can only be centered within its immediate parent or Overlay.overlay"
        parent: overlayRoot
        anchors.centerIn: parent

        background: Rectangle {
            color: Theme.materialOverlay
            radius: Theme.radiusLarge
            border.color: Theme.hairline
            border.width: 1
        }

        enter: Transition {
            NumberAnimation {
                property: "opacity"
                from: 0.0
                to: 1.0
                duration: Theme.motionMedium
                easing.type: Theme.motionDecelerate
            }
        }

        exit: Transition {
            NumberAnimation {
                property: "opacity"
                from: 1.0
                to: 0.0
                duration: Theme.motionShort
                easing.type: Theme.motionAccelerate
            }
        }

        contentItem: Text {
            text: "确定要退出全屏播放器吗？"
            font.family: Theme.fontSans
            color: Theme.foreground
        }

        onAccepted: playerWindow.close()
    }

    // ═══════════════════════════════════════════════════════════════
    // Models
    // ═══════════════════════════════════════════════════════════════
    ListModel {
        id: examListModel
    }

    ListModel {
        id: materialsListModel
    }
}
