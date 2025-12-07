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
        anchors.fill: parent

        // When swiping up, start from bottom and follow finger
        transform: Translate {
            y: {
                if (activeEdge === "bottom") {
                    // Swipe up - home slides up from bottom
                    return root.height * (1 - gestureProgress)
                }
                return 0
            }

            Behavior on y {
                enabled: activeEdge === "" || gestureCompleted
                NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
            }
        }

        // Status bar
        Rectangle {
            id: statusBar
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 52
            color: "#16213e"

            Text {
                anchors.centerIn: parent
                text: Qt.formatTime(new Date(), "hh:mm")
                color: "white"
                font.pixelSize: 20
                font.weight: Font.Medium
            }

            Timer {
                interval: 1000
                running: true
                repeat: true
                onTriggered: parent.children[0].text = Qt.formatTime(new Date(), "hh:mm")
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
                width: appGrid.cellWidth
                height: appGrid.cellHeight

                Rectangle {
                    id: appTile
                    anchors.centerIn: parent
                    width: parent.width - 12
                    height: parent.height - 12
                    radius: 20
                    color: appMouse.pressed ? Qt.lighter(modelData.color, 1.3) : modelData.color
                    scale: appMouse.pressed ? 0.95 : 1.0

                    Behavior on color { ColorAnimation { duration: 100 } }
                    Behavior on scale { NumberAnimation { duration: 100 } }

                    Column {
                        anchors.centerIn: parent
                        spacing: 10

                        // Icon (simple shape for now)
                        Rectangle {
                            width: 56
                            height: 56
                            radius: 14
                            color: Qt.rgba(1, 1, 1, 0.2)
                            anchors.horizontalCenter: parent.horizontalCenter

                            Text {
                                anchors.centerIn: parent
                                text: modelData.name.charAt(0)
                                color: "white"
                                font.pixelSize: 26
                                font.weight: Font.Bold
                            }
                        }

                        Text {
                            text: modelData.name
                            color: "white"
                            font.pixelSize: 13
                            font.weight: Font.Medium
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                    }

                    MouseArea {
                        id: appMouse
                        anchors.fill: parent
                        onClicked: {
                            console.log("Launching:", modelData.exec)
                            appLauncher.launch(modelData.exec)
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

            model: windowManager.windows

            delegate: Item {
                width: root.width * 0.7
                height: windowList.height - 40

                Rectangle {
                    id: windowCard
                    anchors.fill: parent
                    radius: 28
                    color: "#1a1a2e"
                    scale: cardMouse.pressed ? 0.97 : 1.0

                    Behavior on scale { NumberAnimation { duration: 100 } }

                    // Preview area
                    Rectangle {
                        anchors.fill: parent
                        anchors.bottomMargin: 90
                        radius: 28
                        color: "#16213e"

                        // Bottom corners square
                        Rectangle {
                            anchors.bottom: parent.bottom
                            width: parent.width
                            height: 28
                            color: parent.color
                        }

                        // App icon/letter
                        Text {
                            anchors.centerIn: parent
                            text: modelData.appClass ? modelData.appClass.charAt(0).toUpperCase() : "?"
                            color: "#e94560"
                            font.pixelSize: 96
                            font.weight: Font.Bold
                            opacity: 0.8
                        }
                    }

                    // Title bar
                    Item {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: 90

                        Text {
                            anchors.centerIn: parent
                            text: modelData.title || modelData.appClass || "Unknown"
                            color: "white"
                            font.pixelSize: 18
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                            width: parent.width - 40
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }

                    MouseArea {
                        id: cardMouse
                        anchors.fill: parent
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
            Text {
                anchors.centerIn: parent
                text: "No apps running"
                color: "#555"
                font.pixelSize: 24
                font.weight: Font.Light
                visible: windowList.count === 0
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

        Rectangle {
            anchors.fill: parent
            color: "#000000"
            opacity: gestureProgress * 0.7
        }

        // Close indicator that follows finger
        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            y: -100 + (gestureProgress * (parent.height * 0.4))

            Rectangle {
                anchors.centerIn: parent
                width: 80 + (gestureProgress * 40)
                height: 80 + (gestureProgress * 40)
                radius: width / 2
                color: gestureProgress > 0.5 ? "#e94560" : "#333"
                scale: gestureProgress > 0.8 ? 1.1 : 1.0

                Behavior on color { ColorAnimation { duration: 150 } }
                Behavior on scale { NumberAnimation { duration: 150 } }

                Text {
                    anchors.centerIn: parent
                    text: "✕"
                    color: "white"
                    font.pixelSize: 32 + (gestureProgress * 16)
                    opacity: 0.5 + (gestureProgress * 0.5)
                }
            }
        }

        // Text hint
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height * 0.55
            text: gestureProgress > 0.5 ? "Release to close" : "Pull down to close"
            color: "white"
            font.pixelSize: 18
            opacity: gestureProgress
        }
    }

    // ===== BACK GESTURE INDICATOR =====
    // Shows when swiping right from left edge
    Rectangle {
        id: backIndicator
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: activeEdge === "left" ? Math.max(20, gestureProgress * 120) : 0
        color: "transparent"
        visible: width > 0

        Behavior on width {
            enabled: activeEdge === ""
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }

        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.25 * gestureProgress) }
                GradientStop { position: 1.0; color: "transparent" }
            }
        }

        // Arrow
        Text {
            anchors.verticalCenter: parent.verticalCenter
            x: 10 + (gestureProgress * 20)
            text: "‹"
            color: Qt.rgba(1, 1, 1, gestureProgress)
            font.pixelSize: 48
            font.weight: Font.Light
        }
    }
}
