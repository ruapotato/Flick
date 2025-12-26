import QtQuick 2.15
import QtQuick.Controls 2.15

Item {
    id: lockScreen

    property string lockMethod: "pin"  // "pin", "pattern", "password", "none"
    property string correctPin: "1234"
    property var correctPattern: [0, 1, 2, 5, 8]
    property string stateDir: ""
    property bool showingUnlock: false
    property real swipeProgress: 0  // 0-1 for swipe animation

    signal unlocked()

    // Beautiful gradient background
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#0f0f1a" }
            GradientStop { position: 0.4; color: "#1a1a2e" }
            GradientStop { position: 1.0; color: "#16213e" }
        }
    }

    // Subtle animated particles/stars effect
    Repeater {
        model: 20
        Rectangle {
            property real baseX: Math.random() * lockScreen.width
            property real baseY: Math.random() * lockScreen.height * 0.7
            property real animOffset: Math.random() * 2 * Math.PI

            x: baseX + Math.sin(starAnim.elapsed * 0.001 + animOffset) * 3
            y: baseY + Math.cos(starAnim.elapsed * 0.0008 + animOffset) * 2
            width: 2 + Math.random() * 2
            height: width
            radius: width / 2
            color: "#ffffff"
            opacity: 0.1 + Math.random() * 0.15

            NumberAnimation on opacity {
                from: 0.05
                to: 0.25
                duration: 2000 + Math.random() * 3000
                loops: Animation.Infinite
                easing.type: Easing.InOutSine
            }
        }
    }

    Timer {
        id: starAnim
        property real elapsed: 0
        interval: 50
        running: true
        repeat: true
        onTriggered: elapsed += interval
    }

    // Main clock display
    Item {
        id: clockContainer
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -parent.height * 0.12
        width: parent.width
        height: timeText.height + dateText.height + 24
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
    }

    // Media controls on clock screen (z: 10 to be above swipeArea)
    MediaControls {
        id: clockMediaControls
        z: 10
        anchors.top: clockContainer.bottom
        anchors.topMargin: 40
        anchors.horizontalCenter: parent.horizontalCenter
        opacity: showingUnlock ? 0 : (1 - swipeProgress * 1.5)
        visible: opacity > 0 && hasMedia
        stateDir: lockScreen.stateDir

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
                    width: notificationList.width - 48
                    height: notifContent.height + 24
                    radius: 16
                    color: "#1a1a2e"
                    border.width: 1
                    border.color: modelData.urgency === "critical" ? "#e94560" :
                                  modelData.urgency === "low" ? "#4a6fa5" : "#2a2a4e"

                    // Urgency accent bar
                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: 4
                        radius: 2
                        color: modelData.urgency === "critical" ? "#e94560" :
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
            font.pixelSize: 32
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

    // Swipe gesture handler
    MouseArea {
        id: swipeArea
        anchors.fill: parent
        enabled: !showingUnlock
        property real startY: 0
        property bool isDragging: false

        onPressed: {
            startY = mouse.y
            isDragging = true
        }

        onPositionChanged: {
            if (isDragging) {
                var dragDist = startY - mouse.y
                swipeProgress = Math.max(0, Math.min(1, dragDist / (lockScreen.height * 0.3)))

                if (swipeProgress > 0.7) {
                    isDragging = false
                    showingUnlock = true
                    swipeProgress = 0
                }
            }
        }

        onReleased: {
            isDragging = false
            if (!showingUnlock) {
                swipeProgress = 0
            }
        }
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
