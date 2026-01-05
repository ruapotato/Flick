import QtQuick 2.15
import QtQuick.Controls 2.15
import "shared"

Item {
    id: lockScreen

    property string lockMethod: "pin"  // "pin", "pattern", "password", "none"
    property string correctPin: "1234"
    property var correctPattern: [0, 1, 2, 5, 8]
    property string stateDir: ""
    property bool showingUnlock: false
    property real swipeProgress: 0  // 0-1 for swipe animation
    property bool hasWallpaper: false
    property color accentColor: "#e94560"  // Default accent color

    // Battery status
    property int batteryPercent: 0
    property bool batteryCharging: false
    property string batteryStatus: ""

    signal unlocked()

    // Load accent color from config
    Component.onCompleted: {
        loadAccentColor()
        loadBatteryStatus()
    }

    // Battery status polling
    Timer {
        interval: 10000  // Update every 10 seconds
        running: true
        repeat: true
        onTriggered: loadBatteryStatus()
    }

    function loadBatteryStatus() {
        // Read battery capacity
        var xhrCap = new XMLHttpRequest()
        xhrCap.open("GET", "file:///sys/class/power_supply/battery/capacity", false)
        try {
            xhrCap.send()
            if (xhrCap.status === 200 || xhrCap.status === 0) {
                batteryPercent = parseInt(xhrCap.responseText.trim()) || 0
            }
        } catch (e) {}

        // Read battery status (Charging/Discharging/Full)
        var xhrStatus = new XMLHttpRequest()
        xhrStatus.open("GET", "file:///sys/class/power_supply/battery/status", false)
        try {
            xhrStatus.send()
            if (xhrStatus.status === 200 || xhrStatus.status === 0) {
                batteryStatus = xhrStatus.responseText.trim()
                batteryCharging = (batteryStatus === "Charging" || batteryStatus === "Full")
            }
        } catch (e) {}
    }

    function loadAccentColor() {
        var xhr = new XMLHttpRequest()
        var configPath = stateDir !== "" ? stateDir : Theme.stateDir + ""
        xhr.open("GET", "file://" + configPath + "/display_config.json", false)
        try {
            xhr.send()
            if (xhr.status === 200 || xhr.status === 0) {
                var config = JSON.parse(xhr.responseText)
                if (config.accent_color && config.accent_color !== "") {
                    accentColor = config.accent_color
                }
            }
        } catch (e) {
            console.log("Could not load accent color config")
        }
    }

    // Beautiful gradient background (hidden when wallpaper is set)
    Rectangle {
        anchors.fill: parent
        visible: !hasWallpaper
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#0f0f1a" }
            GradientStop { position: 0.4; color: "#1a1a2e" }
            GradientStop { position: 1.0; color: "#16213e" }
        }
    }

    // Main clock display
    Item {
        id: clockContainer
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -parent.height * 0.12
        width: parent.width
        height: timeText.height + dateText.height + batteryRow.height + 48
        opacity: 1 - swipeProgress * 1.5
        scale: 1 - swipeProgress * 0.1

        Behavior on opacity { NumberAnimation { duration: 150 } }
        Behavior on scale { NumberAnimation { duration: 150 } }

        // Time - large, elegant, thin
        Text {
            id: timeText
            anchors.horizontalCenter: parent.horizontalCenter
            font.pixelSize: Math.min(lockScreen.width * 0.28, 180)
            font.weight: Font.Thin
            font.letterSpacing: -4
            color: "#ffffff"
            text: Qt.formatTime(new Date(), "hh:mm")

            Timer {
                interval: 1000
                running: true
                repeat: true
                onTriggered: timeText.text = Qt.formatTime(new Date(), "hh:mm")
            }
        }

        // Date - elegant subtitle
        Text {
            id: dateText
            anchors.top: timeText.bottom
            anchors.topMargin: 8
            anchors.horizontalCenter: parent.horizontalCenter
            font.pixelSize: Math.min(lockScreen.width * 0.055, 32)
            font.weight: Font.Light
            font.letterSpacing: 2
            color: "#8888aa"
            text: Qt.formatDate(new Date(), "dddd, MMMM d").toUpperCase()

            Timer {
                interval: 60000
                running: true
                repeat: true
                onTriggered: dateText.text = Qt.formatDate(new Date(), "dddd, MMMM d").toUpperCase()
            }
        }

        // Battery indicator
        Row {
            id: batteryRow
            anchors.top: dateText.bottom
            anchors.topMargin: 16
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 8

            // Battery icon with fill level
            Item {
                width: 32
                height: 16
                anchors.verticalCenter: parent.verticalCenter

                // Battery outline
                Rectangle {
                    anchors.left: parent.left
                    width: 28
                    height: 14
                    radius: 3
                    color: "transparent"
                    border.color: batteryPercent <= 20 ? "#ff4444" : "#8888aa"
                    border.width: 1.5

                    // Battery fill
                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.margins: 2
                        width: Math.max(0, (parent.width - 4) * batteryPercent / 100)
                        radius: 1.5
                        color: batteryCharging ? "#4ade80" : (batteryPercent <= 20 ? "#ff4444" : "#8888aa")
                    }
                }

                // Battery tip
                Rectangle {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 3
                    height: 6
                    radius: 1
                    color: batteryPercent <= 20 ? "#ff4444" : "#8888aa"
                }
            }

            // Battery percentage and status
            Text {
                anchors.verticalCenter: parent.verticalCenter
                font.pixelSize: 18
                font.weight: Font.Light
                color: batteryCharging ? "#4ade80" : (batteryPercent <= 20 ? "#ff4444" : "#8888aa")
                text: batteryPercent + "%" + (batteryCharging ? " ⚡" : "")
            }
        }
    }

    // Media controls on clock screen (z: 10 to be above swipeArea)
    MediaControls {
        id: clockMediaControls
        z: 10
        anchors.top: clockContainer.bottom
        anchors.topMargin: 40
        anchors.horizontalCenter: parent.horizontalCenter
        opacity: showingUnlock ? 0 : (1 - swipeProgress * 1.5)
        visible: opacity > 0 && clockMediaControls.hasMedia
        stateDir: lockScreen.stateDir
        accentColor: lockScreen.accentColor

        Behavior on opacity { NumberAnimation { duration: 150 } }
    }

    // Notification display area
    property var notifications: []
    property int notificationCount: 0

    Timer {
        id: notificationRefreshTimer
        interval: 2000  // Refresh every 2 seconds
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: loadNotifications()
    }

    function loadNotifications() {
        var xhr = new XMLHttpRequest()
        var url = "file://" + stateDir + "/notifications_display.json"
        xhr.open("GET", url)
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200 || xhr.status === 0) {
                    try {
                        var data = JSON.parse(xhr.responseText)
                        notifications = data.notifications || []
                        notificationCount = data.count || 0
                    } catch (e) {
                        // File not ready or empty
                    }
                }
            }
        }
        xhr.send()
    }

    // Notifications container (between media controls and swipe hint)
    // No mouse handling here - main swipeArea handles all gestures
    Item {
        id: notificationsContainer
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: clockMediaControls.visible ? clockMediaControls.bottom : clockContainer.bottom
        anchors.topMargin: clockMediaControls.visible ? 24 : 60
        anchors.bottom: swipeHint.top
        anchors.bottomMargin: 16
        opacity: showingUnlock ? 0 : (1 - swipeProgress * 1.5)
        visible: opacity > 0 && notificationCount > 0

        Behavior on opacity { NumberAnimation { duration: 150 } }

        // Notification count badge
        Text {
            id: notifHeader
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            font.pixelSize: 14
            font.weight: Font.Light
            font.letterSpacing: 1
            color: "#666688"
            text: notificationCount + " NOTIFICATION" + (notificationCount !== 1 ? "S" : "")
        }

        // Notification list (no interaction - handled by main gesture area)
        Column {
            id: notificationList
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: notifHeader.bottom
            anchors.topMargin: 12
            anchors.leftMargin: 24
            anchors.rightMargin: 24
            spacing: 12

            Repeater {
                model: notifications

                Rectangle {
                    id: notifCard
                    property int notifIndex: index
                    property real swipeOffset: notifSwipeOffsets[index] || 0
                    x: swipeOffset
                    width: notificationList.width - 48
                    height: notifContent.height + 24
                    radius: 16
                    color: "#1a1a2e"
                    border.width: 1
                    border.color: modelData.urgency === "critical" ? accentColor :
                                  modelData.urgency === "low" ? "#4a6fa5" : "#2a2a4e"
                    opacity: 1 - Math.abs(swipeOffset) / (lockScreen.width * 0.5)

                    Behavior on x { NumberAnimation { duration: 100 } }
                    Behavior on opacity { NumberAnimation { duration: 100 } }

                    // Urgency accent bar
                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: 4
                        radius: 2
                        color: modelData.urgency === "critical" ? accentColor :
                               modelData.urgency === "low" ? "#4a9a5a" : "#4a6fa5"
                    }

                    Column {
                        id: notifContent
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.leftMargin: 16
                        anchors.rightMargin: 12
                        anchors.topMargin: 12
                        spacing: 4

                        // App name and time row
                        Item {
                            width: parent.width
                            height: 16

                            Text {
                                anchors.left: parent.left
                                font.pixelSize: 12
                                font.weight: Font.Medium
                                font.letterSpacing: 0.5
                                color: "#8888aa"
                                text: modelData.app_name.toUpperCase()
                            }

                            Text {
                                anchors.right: parent.right
                                font.pixelSize: 11
                                font.weight: Font.Light
                                color: "#666688"
                                text: modelData.time_ago
                            }
                        }

                        // Summary (title)
                        Text {
                            width: parent.width
                            font.pixelSize: 15
                            font.weight: Font.Medium
                            color: "#ffffff"
                            text: modelData.summary
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }

                        // Body
                        Text {
                            width: parent.width
                            font.pixelSize: 13
                            font.weight: Font.Light
                            color: "#aaaacc"
                            text: modelData.body
                            elide: Text.ElideRight
                            maximumLineCount: 2
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }
        }
    }

    // Swipe up hint with animated chevron
    Column {
        id: swipeHint
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 80
        spacing: 16
        opacity: (1 - swipeProgress * 2) * 0.8

        Behavior on opacity { NumberAnimation { duration: 200 } }

        // Animated chevron
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "^"
            font.pixelSize: 22
            font.weight: Font.Light
            color: "#666688"

            SequentialAnimation on y {
                loops: Animation.Infinite
                NumberAnimation { from: 0; to: -8; duration: 800; easing.type: Easing.InOutSine }
                NumberAnimation { from: -8; to: 0; duration: 800; easing.type: Easing.InOutSine }
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Swipe up to unlock"
            font.pixelSize: Math.min(lockScreen.width * 0.045, 22)
            font.weight: Font.Light
            font.letterSpacing: 1
            color: "#555566"
        }
    }

    // Swipe gesture handler - handles both unlock (vertical) and dismiss (horizontal)
    MouseArea {
        id: swipeArea
        anchors.fill: parent
        enabled: !showingUnlock
        property real startX: 0
        property real startY: 0
        property bool isDragging: false
        property bool isHorizontal: false
        property bool gestureDecided: false
        property int touchedNotifIndex: -1

        onPressed: {
            startX = mouse.x
            startY = mouse.y
            isDragging = true
            isHorizontal = false
            gestureDecided = false
            touchedNotifIndex = findNotificationAt(mouse.x, mouse.y)
        }

        onPositionChanged: {
            if (!isDragging) return

            var dx = mouse.x - startX
            var dy = startY - mouse.y  // Positive = up

            // Decide gesture direction after some movement
            if (!gestureDecided && (Math.abs(dx) > 20 || Math.abs(dy) > 20)) {
                gestureDecided = true
                // Only allow horizontal if touching a notification
                isHorizontal = touchedNotifIndex >= 0 && Math.abs(dx) > Math.abs(dy)
            }

            if (gestureDecided) {
                if (isHorizontal && touchedNotifIndex >= 0) {
                    // Horizontal swipe on notification - update notification position
                    updateNotificationSwipe(touchedNotifIndex, dx)
                } else {
                    // Vertical swipe - unlock gesture
                    swipeProgress = Math.max(0, Math.min(1, dy / (lockScreen.height * 0.3)))

                    if (swipeProgress > 0.7) {
                        isDragging = false
                        showingUnlock = true
                        swipeProgress = 0
                    }
                }
            }
        }

        onReleased: {
            var dx = mouse.x - startX
            var dy = startY - mouse.y

            if (isHorizontal && touchedNotifIndex >= 0) {
                // Check if should dismiss
                finishNotificationSwipe(touchedNotifIndex)
            } else if (!gestureDecided && touchedNotifIndex >= 0 && Math.abs(dx) < 20 && Math.abs(dy) < 20) {
                // Tap on notification (no significant movement) - open app after unlock
                openNotificationApp(touchedNotifIndex)
            }

            isDragging = false
            gestureDecided = false
            isHorizontal = false
            touchedNotifIndex = -1

            if (!showingUnlock) {
                swipeProgress = 0
            }
        }
    }

    // Open app associated with notification and trigger unlock
    function openNotificationApp(notifIndex) {
        if (notifIndex < 0 || notifIndex >= notifications.length) return

        var notif = notifications[notifIndex]
        console.log("Notification tapped:", notif.app_name, notif.summary)

        // Determine app command based on notification app_name
        var appCmd = ""
        if (notif.app_name === "Messages") {
            // Open messages app to the specific conversation if we have phone number
            var phone = notif.summary || ""
            appCmd = stateDir + "/../../../Flick/apps/messages/run_messages.sh"
            // Also write conversation hint for messages app
            writeConversationHint(phone)
        } else if (notif.app_name === "Phone") {
            appCmd = stateDir + "/../../../Flick/apps/phone/run_phone.sh"
        } else if (notif.app_name === "Email") {
            appCmd = stateDir + "/../../../Flick/apps/email/run_email.sh"
        }

        if (appCmd !== "") {
            // Write the app to open after unlock
            writeUnlockOpenApp(appCmd)
        }

        // Show unlock screen (same as swipe up)
        showingUnlock = true
        swipeProgress = 0
    }

    // Write unlock_open_app.json for shell to read after unlock
    function writeUnlockOpenApp(appCmd) {
        var data = { app: appCmd }
        var xhr = new XMLHttpRequest()
        var url = "file://" + stateDir + "/unlock_open_app.json"
        xhr.open("PUT", url)
        xhr.send(JSON.stringify(data, null, 2))
        console.log("Wrote unlock open app:", appCmd)
    }

    // Write conversation hint for messages app
    function writeConversationHint(phoneNumber) {
        var data = { open_conversation: phoneNumber }
        var xhr = new XMLHttpRequest()
        var url = "file://" + stateDir + "/messages_open_hint.json"
        xhr.open("PUT", url)
        xhr.send(JSON.stringify(data, null, 2))
        console.log("Wrote messages hint for:", phoneNumber)
    }

    // Find which notification index was touched (if any)
    function findNotificationAt(x, y) {
        if (!notificationsContainer.visible || notifications.length === 0) return -1

        // Calculate notification area bounds
        var listTop = notificationsContainer.y + notifHeader.height + 12
        var cardHeight = 90  // Approximate height
        var spacing = 12

        for (var i = 0; i < notifications.length; i++) {
            var cardTop = listTop + i * (cardHeight + spacing)
            var cardBottom = cardTop + cardHeight

            if (y >= cardTop && y <= cardBottom && x >= 24 && x <= lockScreen.width - 24) {
                return i
            }
        }
        return -1
    }

    // Track notification swipe offsets
    property var notifSwipeOffsets: []

    function updateNotificationSwipe(index, dx) {
        // Ensure array is big enough
        while (notifSwipeOffsets.length <= index) {
            notifSwipeOffsets.push(0)
        }
        notifSwipeOffsets[index] = dx
        notifSwipeOffsetsChanged()
    }

    function finishNotificationSwipe(index) {
        if (index < 0 || index >= notifSwipeOffsets.length) return

        var offset = notifSwipeOffsets[index]
        if (Math.abs(offset) > lockScreen.width * 0.3) {
            // Dismiss this notification
            dismissNotification(notifications[index].id)
        }
        // Reset offset
        notifSwipeOffsets[index] = 0
        notifSwipeOffsetsChanged()
    }

    function dismissNotification(notifId) {
        console.log("Dismissing notification:", notifId)
        // Write dismiss request to file
        var xhr = new XMLHttpRequest()
        var url = "file://" + stateDir + "/dismiss_notification"
        xhr.open("PUT", url)
        xhr.send(notifId.toString())
        // Reload notifications after a brief delay
        Qt.callLater(loadNotifications)
    }

    // Unlock overlay - slides up from bottom
    Rectangle {
        id: unlockOverlay
        anchors.fill: parent
        color: "transparent"
        opacity: showingUnlock ? 1 : 0
        visible: opacity > 0

        Behavior on opacity {
            NumberAnimation { duration: 350; easing.type: Easing.OutCubic }
        }

        // Semi-transparent background
        Rectangle {
            anchors.fill: parent
            color: "#0a0a0f"
            opacity: 0.92
        }

        // PIN Entry (shown when lockMethod is "pin")
        PinEntry {
            id: pinEntry
            visible: lockMethod === "pin"
            anchors.centerIn: parent
            anchors.verticalCenterOffset: showingUnlock ? -80 : 200
            correctPin: lockScreen.correctPin
            accentColor: lockScreen.accentColor

            Behavior on anchors.verticalCenterOffset {
                NumberAnimation { duration: 400; easing.type: Easing.OutBack }
            }

            onPinCorrect: {
                successAnim.start()
            }

            onPinIncorrect: {
                shakeAnimation.start()
            }

            onCancelled: {
                showingUnlock = false
            }
        }

        // Pattern Entry (shown when lockMethod is "pattern")
        PatternEntry {
            id: patternEntry
            visible: lockMethod === "pattern"
            anchors.centerIn: parent
            anchors.verticalCenterOffset: showingUnlock ? -40 : 200
            accentColor: lockScreen.accentColor

            Behavior on anchors.verticalCenterOffset {
                NumberAnimation { duration: 400; easing.type: Easing.OutBack }
            }

            onPatternComplete: {
                console.log("Pattern entered:", JSON.stringify(pattern))
                // Send pattern for verification via shell script
                var patternStr = pattern.join(",")
                console.warn("VERIFY_PATTERN:" + patternStr)
                // Start polling for verification result
                verifyTimer.start()
            }
        }

        // Timer to poll for verification result
        Timer {
            id: verifyTimer
            property int pollCount: 0
            interval: 100
            repeat: true
            onTriggered: {
                pollCount++
                // Timeout after 3 seconds
                if (pollCount > 30) {
                    verifyTimer.stop()
                    pollCount = 0
                    patternEntry.showError("Verification timeout")
                    return
                }

                var xhr = new XMLHttpRequest()
                xhr.open("GET", "file://" + stateDir + "/verify_result", false)
                try {
                    xhr.send()
                    if (xhr.status === 200 && xhr.responseText.trim() !== "") {
                        verifyTimer.stop()
                        pollCount = 0
                        var result = xhr.responseText.trim()
                        console.log("Verification result:", result)
                        if (result === "OK") {
                            successAnim.start()
                        } else {
                            patternEntry.showError("Wrong pattern")
                        }
                    }
                } catch (e) {
                    // File not ready yet, keep polling
                }
            }
        }

        // Cancel button for pattern mode
        Text {
            visible: lockMethod === "pattern"
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 100
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Cancel"
            font.pixelSize: 18
            color: "#888899"

            MouseArea {
                anchors.fill: parent
                anchors.margins: -20
                onClicked: showingUnlock = false
            }
        }

        // Shake animation for wrong PIN
        SequentialAnimation {
            id: shakeAnimation
            PropertyAnimation { target: pinEntry; property: "x"; to: pinEntry.x - 25; duration: 40 }
            PropertyAnimation { target: pinEntry; property: "x"; to: pinEntry.x + 25; duration: 40 }
            PropertyAnimation { target: pinEntry; property: "x"; to: pinEntry.x - 20; duration: 40 }
            PropertyAnimation { target: pinEntry; property: "x"; to: pinEntry.x + 20; duration: 40 }
            PropertyAnimation { target: pinEntry; property: "x"; to: pinEntry.x; duration: 40 }
        }

        // Success animation
        SequentialAnimation {
            id: successAnim
            PropertyAnimation { target: unlockOverlay; property: "scale"; to: 1.05; duration: 150 }
            PropertyAnimation { target: unlockOverlay; property: "opacity"; to: 0; duration: 300 }
            ScriptAction {
                script: {
                    writeUnlockSignal()
                    lockScreen.unlocked()
                }
            }
        }
    }

    // Helper function to compare arrays
    function arraysEqual(a, b) {
        if (a.length !== b.length) return false
        for (var i = 0; i < a.length; i++) {
            if (a[i] !== b[i]) return false
        }
        return true
    }

    // Home indicator at bottom
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 12
        width: 134
        height: 5
        radius: 2.5
        color: "#444455"
        opacity: 0.6
    }

    // Write unlock signal file
    function writeUnlockSignal() {
        var signalPath = stateDir + "/unlock_signal"
        console.log("FLICK_UNLOCK_SIGNAL:" + signalPath)
    }
}
