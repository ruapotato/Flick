import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ApplicationWindow {
    id: root
    visible: true
    visibility: Window.FullScreen
    color: "#1a1a2e"

    // Track current view
    property string currentView: "home"  // home, switcher
    property real gestureProgress: 0
    property string activeGesture: ""

    // App list - will be replaced with .desktop file scanning
    property var apps: [
        { name: "Terminal", icon: "utilities-terminal", exec: "foot" },
        { name: "Firefox", icon: "firefox", exec: "firefox" },
        { name: "Chromium", icon: "chromium", exec: "chromium --ozone-platform=wayland" },
        { name: "Files", icon: "system-file-manager", exec: "nautilus" },
        { name: "Settings", icon: "preferences-system", exec: "gnome-control-center" },
        { name: "Calculator", icon: "accessories-calculator", exec: "gnome-calculator" }
    ]

    // Gesture handling
    Connections {
        target: gestureHandler

        function onGestureStarted(edge, progress, velocity) {
            activeGesture = edge
            gestureProgress = progress

            if (edge === "right") {
                // Swipe from right edge - show app switcher
                currentView = "switcher"
            }
        }

        function onGestureUpdated(edge, progress, velocity) {
            if (edge === activeGesture) {
                gestureProgress = progress
            }
        }

        function onGestureEnded(edge, completed, velocity) {
            if (edge === "right") {
                if (!completed) {
                    // Cancelled - go back to home
                    currentView = "home"
                }
            } else if (edge === "bottom" && completed) {
                // Swipe up completed - we're now visible (compositor brought us up)
                currentView = "home"
            }

            gestureProgress = 0
            activeGesture = ""
        }
    }

    // Main content
    StackView {
        id: stackView
        anchors.fill: parent
        initialItem: homeView

        pushEnter: Transition {
            PropertyAnimation { property: "x"; from: root.width; to: 0; duration: 250; easing.type: Easing.OutCubic }
        }
        pushExit: Transition {
            PropertyAnimation { property: "x"; from: 0; to: -root.width * 0.3; duration: 250; easing.type: Easing.OutCubic }
        }
        popEnter: Transition {
            PropertyAnimation { property: "x"; from: -root.width * 0.3; to: 0; duration: 250; easing.type: Easing.OutCubic }
        }
        popExit: Transition {
            PropertyAnimation { property: "x"; from: 0; to: root.width; duration: 250; easing.type: Easing.OutCubic }
        }
    }

    // Home view with app grid
    Component {
        id: homeView

        Item {
            // Status bar
            Rectangle {
                id: statusBar
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 48
                color: "#16213e"

                Text {
                    anchors.centerIn: parent
                    text: Qt.formatTime(new Date(), "hh:mm")
                    color: "white"
                    font.pixelSize: 18
                    font.weight: Font.Medium
                }

                // Update time every second
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
                anchors.margins: 20

                cellWidth: width / 4
                cellHeight: cellWidth * 1.3

                model: root.apps

                delegate: Item {
                    width: appGrid.cellWidth
                    height: appGrid.cellHeight

                    Rectangle {
                        id: appButton
                        anchors.centerIn: parent
                        width: parent.width - 16
                        height: parent.height - 16
                        radius: 16
                        color: mouseArea.pressed ? "#3d5a80" : "transparent"

                        Behavior on color {
                            ColorAnimation { duration: 100 }
                        }

                        Column {
                            anchors.centerIn: parent
                            spacing: 12

                            // Icon placeholder (circle with first letter)
                            Rectangle {
                                width: 64
                                height: 64
                                radius: 16
                                color: "#0f3460"
                                anchors.horizontalCenter: parent.horizontalCenter

                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.name.charAt(0)
                                    color: "#e94560"
                                    font.pixelSize: 28
                                    font.weight: Font.Bold
                                }
                            }

                            Text {
                                text: modelData.name
                                color: "white"
                                font.pixelSize: 14
                                anchors.horizontalCenter: parent.horizontalCenter
                                elide: Text.ElideRight
                                width: appButton.width - 8
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }

                        MouseArea {
                            id: mouseArea
                            anchors.fill: parent
                            onClicked: appLauncher.launch(modelData.exec)
                        }
                    }
                }
            }

            // Home indicator bar
            Rectangle {
                id: homeIndicator
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottomMargin: 12
                width: 134
                height: 5
                radius: 3
                color: "#4a4a6a"
            }
        }
    }

    // App Switcher overlay
    Rectangle {
        id: appSwitcher
        anchors.fill: parent
        color: "#000000"
        opacity: currentView === "switcher" ? 0.95 : 0
        visible: opacity > 0

        Behavior on opacity {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }

        Column {
            anchors.fill: parent
            anchors.topMargin: 60

            // Header
            RowLayout {
                width: parent.width
                height: 60

                Text {
                    text: "Recent Apps"
                    color: "white"
                    font.pixelSize: 24
                    font.weight: Font.Medium
                    Layout.leftMargin: 24
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    width: 48
                    height: 48
                    radius: 24
                    color: closeButton.pressed ? "#333" : "transparent"
                    Layout.rightMargin: 16

                    Text {
                        anchors.centerIn: parent
                        text: "✕"
                        color: "white"
                        font.pixelSize: 24
                    }

                    MouseArea {
                        id: closeButton
                        anchors.fill: parent
                        onClicked: currentView = "home"
                    }
                }
            }

            // Window cards
            ListView {
                id: windowList
                width: parent.width
                height: parent.height - 120
                orientation: ListView.Horizontal
                spacing: 20
                leftMargin: 40
                rightMargin: 40

                model: windowManager.windows

                delegate: Rectangle {
                    width: windowList.width * 0.75
                    height: windowList.height - 80
                    radius: 24
                    color: "#1a1a2e"

                    Column {
                        anchors.fill: parent
                        spacing: 0

                        // Preview area
                        Rectangle {
                            width: parent.width
                            height: parent.height - 80
                            radius: 24
                            color: "#16213e"

                            // Round only top corners
                            Rectangle {
                                anchors.bottom: parent.bottom
                                width: parent.width
                                height: parent.radius
                                color: parent.color
                            }

                            Text {
                                anchors.centerIn: parent
                                text: modelData.appClass.charAt(0).toUpperCase()
                                color: "#e94560"
                                font.pixelSize: 72
                                font.weight: Font.Bold
                            }
                        }

                        // Title
                        Rectangle {
                            width: parent.width
                            height: 80
                            color: "transparent"

                            Text {
                                anchors.centerIn: parent
                                text: modelData.title || modelData.appClass
                                color: "white"
                                font.pixelSize: 20
                                font.weight: Font.Medium
                                elide: Text.ElideRight
                                width: parent.width - 32
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            windowManager.focusWindow(modelData.id)
                            currentView = "home"
                        }
                    }
                }

                // Empty state
                Text {
                    anchors.centerIn: parent
                    text: "No running apps"
                    color: "#666"
                    font.pixelSize: 20
                    visible: windowList.count === 0
                }
            }
        }
    }

    // Back gesture indicator (left edge swipe)
    Rectangle {
        id: backIndicator
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: activeGesture === "left" ? 20 + (gestureProgress * 60) : 0
        color: "transparent"
        visible: width > 0

        Behavior on width {
            NumberAnimation { duration: 50 }
        }

        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.3 * gestureProgress) }
                GradientStop { position: 1.0; color: "transparent" }
            }
        }

        Text {
            anchors.centerIn: parent
            text: "‹"
            color: Qt.rgba(1, 1, 1, gestureProgress)
            font.pixelSize: 32
            font.weight: Font.Light
        }
    }
}
