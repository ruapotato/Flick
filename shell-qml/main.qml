import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ApplicationWindow {
    id: root
    visible: true
    visibility: Window.FullScreen
    color: "#1a1a2e"

    // Gesture state from compositor
    property string activeEdge: ""
    property real gestureProgress: 0
    property bool gestureCompleted: false

    // View state
    property bool showingSwitcher: false

    // Gesture handling from compositor
    Connections {
        target: gestureHandler

        function onGestureStarted(edge, progress, velocity) {
            activeEdge = edge
            gestureProgress = 0
            gestureCompleted = false
            console.log("Gesture started:", edge)
        }

        function onGestureUpdated(edge, progress, velocity) {
            if (edge === activeEdge) {
                gestureProgress = Math.min(progress, 1.5)  // Allow slight overscroll
                console.log("Gesture update:", edge, progress)
            }
        }

        function onGestureEnded(edge, completed, velocity) {
            console.log("Gesture ended:", edge, "completed:", completed)
            gestureCompleted = completed

            if (edge === "right" && completed) {
                // Swipe left completed - show app switcher
                showingSwitcher = true
                gestureProgress = 1
            } else if (edge === "right" && !completed) {
                // Cancelled - animate back
                showingSwitcher = false
            } else if (edge === "bottom" && completed) {
                // Swipe up completed - we're home
                gestureProgress = 0
            }

            // Reset after animation
            resetTimer.start()
        }
    }

    Timer {
        id: resetTimer
        interval: 300
        onTriggered: {
            if (!showingSwitcher) {
                activeEdge = ""
                gestureProgress = 0
            }
        }
    }

    // App list
    property var apps: [
        { name: "Terminal", icon: "terminal", exec: "foot", color: "#2d3436" },
        { name: "Firefox", icon: "firefox", exec: "firefox", color: "#e17055" },
        { name: "Chromium", icon: "chrome", exec: "chromium --ozone-platform=wayland", color: "#0984e3" },
        { name: "Files", icon: "folder", exec: "nautilus", color: "#fdcb6e" },
        { name: "XTerm", icon: "terminal", exec: "xterm", color: "#636e72" },
        { name: "Kate", icon: "edit", exec: "kate", color: "#a29bfe" }
    ]

    // ===== HOME SCREEN =====
    // This slides up from bottom when you swipe up
    Item {
        id: homeScreen
        width: parent.width
        height: parent.height
        x: 0

        // Swipe up from bottom
        y: activeEdge === "bottom" ? root.height * (1 - gestureProgress) : 0

        Behavior on y {
            enabled: activeEdge === "" || gestureCompleted
            NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
        }

        // Status bar
        Rectangle {
            id: statusBar
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 48
            color: "#16213e"

            // Center - time
            Text {
                id: timeText
                anchors.centerIn: parent
                text: Qt.formatTime(new Date(), "hh:mm")
                color: "white"
                font.pixelSize: 18
                font.weight: Font.DemiBold
            }

            Timer {
                interval: 1000
                running: true
                repeat: true
                onTriggered: timeText.text = Qt.formatTime(new Date(), "hh:mm")
            }

            // Battery percentage
            Text {
                anchors.right: parent.right
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                text: "85%"
                color: "white"
                font.pixelSize: 13
            }
        }

        // App Grid
        GridView {
            id: appGrid
            anchors.top: statusBar.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: homeIndicator.top
            anchors.margins: 16
            anchors.topMargin: 24

            cellWidth: width / 3
            cellHeight: cellWidth * 1.2

            model: root.apps

            delegate: Item {
                id: appDelegate
                width: appGrid.cellWidth
                height: appGrid.cellHeight

                Rectangle {
                    id: appTile
                    anchors.centerIn: parent
                    width: parent.width - 16
                    height: parent.height - 16
                    radius: 24
                    color: modelData.color
                    scale: appMouse.pressed ? 0.9 : 1.0
                    opacity: appMouse.pressed ? 0.85 : 1.0

                    Behavior on scale {
                        NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                    }
                    Behavior on opacity { NumberAnimation { duration: 100 } }

                    // Highlight overlay when pressed
                    Rectangle {
                        anchors.fill: parent
                        radius: parent.radius
                        color: "white"
                        opacity: appMouse.pressed ? 0.2 : 0

                        Behavior on opacity { NumberAnimation { duration: 100 } }
                    }

                    Column {
                        anchors.centerIn: parent
                        spacing: 12

                        // Icon container with glow
                        Item {
                            width: 64
                            height: 64
                            anchors.horizontalCenter: parent.horizontalCenter

                            // Icon background
                            Rectangle {
                                anchors.fill: parent
                                radius: 16
                                color: Qt.rgba(1, 1, 1, 0.2)

                                // Inner shadow effect
                                Rectangle {
                                    anchors.fill: parent
                                    anchors.margins: 2
                                    radius: 14
                                    color: "transparent"
                                    border.width: 1
                                    border.color: Qt.rgba(1, 1, 1, 0.1)
                                }
                            }

                            Text {
                                anchors.centerIn: parent
                                text: modelData.name.charAt(0)
                                color: "white"
                                font.pixelSize: 28
                                font.weight: Font.Bold
                            }
                        }

                        Text {
                            text: modelData.name
                            color: "white"
                            font.pixelSize: 14
                            font.weight: Font.Medium
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                    }

                    MouseArea {
                        id: appMouse
                        anchors.fill: parent
                        onClicked: {
                            // Launch animation
                            launchAnim.start()
                            console.log("Launching:", modelData.exec)
                            appLauncher.launch(modelData.exec)
                        }
                    }

                    // Launch "ripple" animation
                    SequentialAnimation {
                        id: launchAnim
                        NumberAnimation {
                            target: appTile
                            property: "scale"
                            to: 0.85
                            duration: 80
                            easing.type: Easing.InCubic
                        }
                        NumberAnimation {
                            target: appTile
                            property: "scale"
                            to: 1.0
                            duration: 200
                            easing.type: Easing.OutBack
                        }
                    }
                }
            }
        }

        // Home indicator
        Rectangle {
            id: homeIndicator
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottomMargin: 16
            width: 134
            height: 5
            radius: 3
            color: "#4a4a6a"
        }
    }

    // ===== APP SWITCHER =====
    // Slides in from right when you swipe left from right edge
    Rectangle {
        id: appSwitcher
        anchors.fill: parent
        color: "#000000"

        // Slide in from right based on gesture
        transform: Translate {
            x: {
                if (activeEdge === "right") {
                    return root.width * (1 - gestureProgress)
                } else if (showingSwitcher) {
                    return 0
                }
                return root.width
            }

            Behavior on x {
                enabled: activeEdge === "" || gestureCompleted
                NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
            }
        }

        visible: activeEdge === "right" || showingSwitcher

        // Header
        Rectangle {
            id: switcherHeader
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 80
            color: "transparent"

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 24
                anchors.verticalCenter: parent.verticalCenter
                text: "Open Apps"
                color: "white"
                font.pixelSize: 28
                font.weight: Font.Light
            }

            // Close button
            Rectangle {
                anchors.right: parent.right
                anchors.rightMargin: 20
                anchors.verticalCenter: parent.verticalCenter
                width: 44
                height: 44
                radius: 22
                color: closeMouse.pressed ? "#333" : "transparent"

                Text {
                    anchors.centerIn: parent
                    text: "✕"
                    color: "white"
                    font.pixelSize: 22
                }

                MouseArea {
                    id: closeMouse
                    anchors.fill: parent
                    onClicked: {
                        showingSwitcher = false
                        activeEdge = ""
                        gestureProgress = 0
                    }
                }
            }
        }

        // Window cards - horizontal list
        ListView {
            id: windowList
            anchors.top: switcherHeader.bottom
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottomMargin: 40

            orientation: ListView.Horizontal
            spacing: 24
            leftMargin: 32
            rightMargin: 32
            snapMode: ListView.SnapToItem
            highlightRangeMode: ListView.StrictlyEnforceRange
            preferredHighlightBegin: 32
            preferredHighlightEnd: root.width * 0.7 + 32

            model: windowManager.windows

            delegate: Item {
                id: cardDelegate
                width: root.width * 0.7
                height: windowList.height - 40

                // Entrance animation
                opacity: showingSwitcher ? 1 : 0

                Behavior on opacity {
                    NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                }

                // Shadow behind card
                Rectangle {
                    anchors.fill: windowCard
                    anchors.margins: -6
                    radius: 34
                    color: "#000000"
                    opacity: 0.5
                    z: -1
                }

                Rectangle {
                    id: windowCard
                    anchors.fill: parent
                    radius: 28
                    color: "#1a1a2e"
                    scale: cardMouse.pressed ? 0.95 : 1.0

                    Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }

                    // Preview area with gradient
                    Rectangle {
                        id: previewArea
                        anchors.fill: parent
                        anchors.bottomMargin: 80
                        radius: 28
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: "#1e3a5f" }
                            GradientStop { position: 1.0; color: "#16213e" }
                        }

                        // Bottom corners square
                        Rectangle {
                            anchors.bottom: parent.bottom
                            width: parent.width
                            height: 28
                            color: "#16213e"
                        }

                        // App icon/letter
                        Text {
                            anchors.centerIn: parent
                            text: modelData.appClass ? modelData.appClass.charAt(0).toUpperCase() : "?"
                            color: "#e94560"
                            font.pixelSize: 80
                            font.weight: Font.Bold
                            opacity: 0.9
                        }

                        // App class label
                        Rectangle {
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.margins: 16
                            width: appClassText.width + 16
                            height: appClassText.height + 8
                            radius: 8
                            color: Qt.rgba(0, 0, 0, 0.3)

                            Text {
                                id: appClassText
                                anchors.centerIn: parent
                                text: modelData.appClass || "App"
                                color: "white"
                                font.pixelSize: 12
                                font.weight: Font.Medium
                                opacity: 0.8
                            }
                        }
                    }

                    // Title bar
                    Item {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: 80

                        Text {
                            anchors.centerIn: parent
                            text: modelData.title || modelData.appClass || "Unknown"
                            color: "white"
                            font.pixelSize: 16
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                            width: parent.width - 48
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }

                    // Close button on card
                    Rectangle {
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.margins: 12
                        width: 36
                        height: 36
                        radius: 18
                        color: closeCardMouse.pressed ? "#e94560" : Qt.rgba(0, 0, 0, 0.4)
                        opacity: closeCardMouse.containsMouse ? 1 : 0.7

                        Behavior on color { ColorAnimation { duration: 100 } }
                        Behavior on opacity { NumberAnimation { duration: 100 } }

                        Text {
                            anchors.centerIn: parent
                            text: "✕"
                            color: "white"
                            font.pixelSize: 16
                        }

                        MouseArea {
                            id: closeCardMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                console.log("Close window:", modelData.id)
                                // TODO: Send close request to compositor
                            }
                        }
                    }

                    MouseArea {
                        id: cardMouse
                        anchors.fill: parent
                        anchors.rightMargin: 48  // Avoid close button
                        onClicked: {
                            console.log("Focus window:", modelData.id)
                            windowManager.focusWindow(modelData.id)
                            showingSwitcher = false
                            activeEdge = ""
                        }
                    }
                }
            }

            // Empty state
            Column {
                anchors.centerIn: parent
                spacing: 16
                visible: windowList.count === 0
                opacity: showingSwitcher ? 1 : 0

                Behavior on opacity { NumberAnimation { duration: 300 } }

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 80
                    height: 80
                    radius: 40
                    color: "#222"

                    Text {
                        anchors.centerIn: parent
                        text: "~"
                        color: "#666"
                        font.pixelSize: 36
                    }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "No apps running"
                    color: "#666"
                    font.pixelSize: 22
                    font.weight: Font.Light
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Swipe right or tap outside to go back"
                    color: "#444"
                    font.pixelSize: 14
                }
            }
        }

        // Swipe right to dismiss app switcher
        MouseArea {
            anchors.fill: parent
            z: -1  // Behind the cards
            onClicked: {
                showingSwitcher = false
                activeEdge = ""
                gestureProgress = 0
            }
        }
    }

    // ===== CLOSE GESTURE OVERLAY =====
    // Shows when swiping down from top
    Rectangle {
        id: closeOverlay
        anchors.fill: parent
        color: "transparent"
        visible: activeEdge === "top"

        // Dark vignette from top
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.9 * gestureProgress) }
                GradientStop { position: 0.5; color: Qt.rgba(0, 0, 0, 0.6 * gestureProgress) }
                GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.3 * gestureProgress) }
            }
        }

        // Red danger zone indicator at threshold
        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: parent.height * 0.15
            visible: gestureProgress > 0.4
            opacity: (gestureProgress - 0.4) * 2
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(0.91, 0.27, 0.38, 0.4) }
                GradientStop { position: 1.0; color: "transparent" }
            }
        }

        // Close indicator that follows finger
        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            y: -120 + (gestureProgress * (parent.height * 0.45))

            Rectangle {
                id: closeCircle
                anchors.centerIn: parent
                width: 72 + (gestureProgress * 48)
                height: width
                radius: width / 2
                color: gestureProgress > 0.5 ? "#e94560" : "#2d2d2d"
                border.width: 3
                border.color: gestureProgress > 0.5 ? "#ff6b6b" : "#555"
                scale: gestureProgress > 0.8 ? 1.15 : 1.0

                Behavior on color { ColorAnimation { duration: 150 } }
                Behavior on border.color { ColorAnimation { duration: 150 } }
                Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutBack } }

                // Glow ring when ready to close
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width + 20
                    height: parent.height + 20
                    radius: width / 2
                    color: "transparent"
                    border.width: 4
                    border.color: "#e94560"
                    opacity: gestureProgress > 0.5 ? 0.6 : 0
                    scale: gestureProgress > 0.5 ? 1.2 : 1.0

                    Behavior on opacity { NumberAnimation { duration: 200 } }
                    Behavior on scale { NumberAnimation { duration: 200 } }
                }

                Text {
                    anchors.centerIn: parent
                    text: "✕"
                    color: "white"
                    font.pixelSize: 28 + (gestureProgress * 20)
                    font.weight: Font.Medium
                    opacity: 0.6 + (gestureProgress * 0.4)
                }
            }
        }

        // Text hint
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height * 0.6
            text: gestureProgress > 0.5 ? "Release to close" : "Pull down to close"
            color: "white"
            font.pixelSize: 20
            font.weight: Font.Light
            opacity: Math.min(gestureProgress * 1.5, 1)

            Behavior on text { PropertyAnimation { duration: 0 } }
        }

        // Progress bar at top
        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            width: parent.width * Math.min(gestureProgress * 2, 1)
            height: 4
            color: gestureProgress > 0.5 ? "#e94560" : "#4a4a6a"

            Behavior on color { ColorAnimation { duration: 150 } }
        }
    }

    // ===== BACK GESTURE INDICATOR =====
    // Shows when swiping right from left edge - iOS style curved arrow
    Item {
        id: backIndicator
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 150
        visible: activeEdge === "left"
        opacity: gestureProgress

        Behavior on opacity {
            enabled: activeEdge === ""
            NumberAnimation { duration: 200 }
        }

        // Curved gradient background
        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: Math.min(gestureProgress * 150, 100)
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.15) }
                GradientStop { position: 1.0; color: "transparent" }
            }

            Behavior on width {
                enabled: activeEdge === ""
                NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
            }
        }

        // Arrow chevron that follows finger
        Item {
            id: arrowContainer
            anchors.verticalCenter: parent.verticalCenter
            x: -30 + (gestureProgress * 60)
            width: 50
            height: 50

            Behavior on x {
                enabled: activeEdge === ""
                NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
            }

            // Circle background
            Rectangle {
                anchors.centerIn: parent
                width: 44 + (gestureProgress * 16)
                height: width
                radius: width / 2
                color: gestureProgress > 0.6 ? Qt.rgba(1, 1, 1, 0.25) : Qt.rgba(1, 1, 1, 0.15)
                scale: gestureProgress > 0.6 ? 1.1 : 1.0

                Behavior on color { ColorAnimation { duration: 100 } }
                Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutBack } }
            }

            // Chevron arrow
            Text {
                anchors.centerIn: parent
                anchors.horizontalCenterOffset: -2
                text: "‹"
                color: "white"
                font.pixelSize: 36 + (gestureProgress * 12)
                font.weight: Font.Light
                opacity: 0.7 + (gestureProgress * 0.3)
                rotation: gestureProgress > 0.6 ? -5 : 0

                Behavior on rotation { NumberAnimation { duration: 100 } }
            }
        }

        // "Back" text hint (appears when almost complete)
        Text {
            anchors.verticalCenter: parent.verticalCenter
            x: 60
            text: "Back"
            color: "white"
            font.pixelSize: 16
            font.weight: Font.Medium
            opacity: Math.max(0, (gestureProgress - 0.5) * 2)

            Behavior on opacity { NumberAnimation { duration: 100 } }
        }
    }

    // ===== EDGE HINTS =====
    // Subtle indicators at screen edges showing swipe zones
    Rectangle {
        id: rightEdgeHint
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: 4
        height: 80
        radius: 2
        color: "#4a4a6a"
        opacity: activeEdge === "" && !showingSwitcher ? 0.5 : 0

        Behavior on opacity { NumberAnimation { duration: 300 } }
    }

    Rectangle {
        id: leftEdgeHint
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: 4
        height: 80
        radius: 2
        color: "#4a4a6a"
        opacity: activeEdge === "" && !showingSwitcher ? 0.5 : 0

        Behavior on opacity { NumberAnimation { duration: 300 } }
    }
}
