import QtQuick 2.15
import QtQuick.Window 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../shared"

Window {
    id: root
    visible: true
    visibility: Window.FullScreen
    color: "#1a1a2e"
    title: "Welcome to Flick"

    property int currentPage: 0
    property int totalPages: 7
    property string configPath: "file://" + Theme.stateDir + "/welcome_config.json"

    // Tutorial pages data
    property var pages: [
        {
            title: "Welcome to Flick",
            subtitle: "A gesture-driven mobile shell",
            description: "Flick is designed from the ground up for touch. Everything is controlled by intuitive swipe gestures.",
            icon: "wave",
            animation: "fade"
        },
        {
            title: "Swipe from Right Edge",
            subtitle: "App Switcher",
            description: "Swipe from the right edge to see all your open apps. Tap any app to switch to it.",
            icon: "layers",
            animation: "swipe-right"
        },
        {
            title: "Swipe from Left Edge",
            subtitle: "Quick Settings",
            description: "Swipe from the left edge to open Quick Settings. Control WiFi, Bluetooth, brightness, and more.",
            icon: "settings",
            animation: "swipe-left"
        },
        {
            title: "Swipe Up from Bottom",
            subtitle: "Keyboard or Home",
            description: "A small swipe up opens the on-screen keyboard. A longer swipe returns to the app grid.",
            icon: "keyboard",
            animation: "swipe-up"
        },
        {
            title: "Swipe Down from Top",
            subtitle: "Close App",
            description: "Swipe down from the top edge to close the current app and return home.",
            icon: "x",
            animation: "swipe-down"
        },
        {
            title: "Long Press Icons",
            subtitle: "Customize Your Grid",
            description: "Long press any app icon to enter edit mode. Drag icons to rearrange them on your home screen.",
            icon: "edit",
            animation: "fade"
        },
        {
            title: "You're Ready!",
            subtitle: "Enjoy Flick",
            description: "That's all you need to know. Flick is still in development - expect bugs and missing features!",
            icon: "check",
            animation: "fade",
            showToggle: true
        }
    ]

    // Gesture indicator animations
    Item {
        id: gestureDemo
        anchors.fill: parent
        z: 0

        // Swipe up indicator
        Rectangle {
            id: swipeUpIndicator
            width: 60
            height: 60
            radius: 30
            color: "#4fc3f7"
            opacity: 0
            x: parent.width / 2 - 30
            y: parent.height - 100

            SequentialAnimation on y {
                id: swipeUpAnim
                running: pages[currentPage].animation === "swipe-up"
                loops: Animation.Infinite
                PropertyAnimation { to: root.height - 100; duration: 0 }
                PropertyAnimation { to: root.height / 2; duration: 800; easing.type: Easing.OutQuad }
                PauseAnimation { duration: 500 }
            }
            SequentialAnimation on opacity {
                running: pages[currentPage].animation === "swipe-up"
                loops: Animation.Infinite
                PropertyAnimation { to: 0.8; duration: 200 }
                PauseAnimation { duration: 600 }
                PropertyAnimation { to: 0; duration: 300 }
                PauseAnimation { duration: 200 }
            }
        }

        // Swipe down indicator
        Rectangle {
            id: swipeDownIndicator
            width: 60
            height: 60
            radius: 30
            color: "#f44336"
            opacity: 0
            x: parent.width / 2 - 30
            y: 50

            SequentialAnimation on y {
                running: pages[currentPage].animation === "swipe-down"
                loops: Animation.Infinite
                PropertyAnimation { to: 50; duration: 0 }
                PropertyAnimation { to: root.height / 2; duration: 800; easing.type: Easing.OutQuad }
                PauseAnimation { duration: 500 }
            }
            SequentialAnimation on opacity {
                running: pages[currentPage].animation === "swipe-down"
                loops: Animation.Infinite
                PropertyAnimation { to: 0.8; duration: 200 }
                PauseAnimation { duration: 600 }
                PropertyAnimation { to: 0; duration: 300 }
                PauseAnimation { duration: 200 }
            }
        }

        // Swipe from left indicator
        Rectangle {
            id: swipeLeftIndicator
            width: 60
            height: 60
            radius: 30
            color: "#66bb6a"
            opacity: 0
            x: 20
            y: parent.height / 2 - 30

            SequentialAnimation on x {
                running: pages[currentPage].animation === "swipe-left"
                loops: Animation.Infinite
                PropertyAnimation { to: 20; duration: 0 }
                PropertyAnimation { to: root.width / 2 - 30; duration: 800; easing.type: Easing.OutQuad }
                PauseAnimation { duration: 500 }
            }
            SequentialAnimation on opacity {
                running: pages[currentPage].animation === "swipe-left"
                loops: Animation.Infinite
                PropertyAnimation { to: 0.8; duration: 200 }
                PauseAnimation { duration: 600 }
                PropertyAnimation { to: 0; duration: 300 }
                PauseAnimation { duration: 200 }
            }
        }

        // Swipe from right indicator
        Rectangle {
            id: swipeRightIndicator
            width: 60
            height: 60
            radius: 30
            color: "#ffb74d"
            opacity: 0
            x: parent.width - 80
            y: parent.height / 2 - 30

            SequentialAnimation on x {
                running: pages[currentPage].animation === "swipe-right"
                loops: Animation.Infinite
                PropertyAnimation { to: root.width - 80; duration: 0 }
                PropertyAnimation { to: root.width / 2 - 30; duration: 800; easing.type: Easing.OutQuad }
                PauseAnimation { duration: 500 }
            }
            SequentialAnimation on opacity {
                running: pages[currentPage].animation === "swipe-right"
                loops: Animation.Infinite
                PropertyAnimation { to: 0.8; duration: 200 }
                PauseAnimation { duration: 600 }
                PropertyAnimation { to: 0; duration: 300 }
                PauseAnimation { duration: 200 }
            }
        }
    }

    // Main content (no swipe - use buttons)
    Item {
        anchors.fill: parent

        ColumnLayout {
            anchors.centerIn: parent
            width: parent.width * 0.85
            spacing: 30

            // Icon circle
            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                width: 120
                height: 120
                radius: 60
                color: "#2d2d4a"
                border.color: "#4fc3f7"
                border.width: 3

                Text {
                    anchors.centerIn: parent
                    text: {
                        switch(pages[currentPage].icon) {
                            case "home": return "\u2302"  // Home
                            case "x": return "\u2715"      // X
                            case "settings": return "\u2699" // Gear
                            case "layers": return "\u25A3"  // Layers
                            case "check": return "\u2713"   // Check
                            case "wave": return "\u263A"    // Smiley
                            case "keyboard": return "\u2328" // Keyboard
                            case "edit": return "\u270E"    // Pencil/Edit
                            default: return "\u2192"        // Arrow
                        }
                    }
                    font.pixelSize: 48
                    color: "#4fc3f7"
                }
            }

            // Title
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: pages[currentPage].title
                font.pixelSize: 36
                font.bold: true
                color: "white"
            }

            // Subtitle
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: pages[currentPage].subtitle
                font.pixelSize: 24
                color: "#4fc3f7"
            }

            // Description
            Text {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: parent.width
                text: pages[currentPage].description
                font.pixelSize: 18
                color: "#cccccc"
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                lineHeight: 1.4
            }

            // Don't show again toggle (only on last page)
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 30
                visible: pages[currentPage].showToggle === true
                spacing: 15

                Text {
                    text: "Don't show on startup"
                    font.pixelSize: 18
                    color: "#aaaaaa"
                }

                Rectangle {
                    id: toggleBg
                    width: 60
                    height: 32
                    radius: 16
                    color: dontShowToggle.checked ? "#4fc3f7" : "#444466"

                    Rectangle {
                        id: toggleKnob
                        width: 26
                        height: 26
                        radius: 13
                        color: "white"
                        x: dontShowToggle.checked ? parent.width - width - 3 : 3
                        y: 3

                        Behavior on x { NumberAnimation { duration: 150 } }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: dontShowToggle.checked = !dontShowToggle.checked
                    }

                    CheckBox {
                        id: dontShowToggle
                        visible: false
                        checked: false
                    }
                }
            }

            // Get Started button (only on last page)
            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 20
                visible: pages[currentPage].showToggle === true
                width: 200
                height: 56
                radius: 28
                color: "#4fc3f7"

                Text {
                    anchors.centerIn: parent
                    text: "Get Started"
                    font.pixelSize: 20
                    font.bold: true
                    color: "#1a1a2e"
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        saveConfig(dontShowToggle.checked)
                        Qt.quit()
                    }
                }
            }
        }
    }

    // Navigation buttons at bottom
    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 40
        spacing: 40

        // Back button
        Rectangle {
            width: 100
            height: 50
            radius: 25
            color: currentPage > 0 ? "#4fc3f7" : "#333355"
            opacity: currentPage > 0 ? 1.0 : 0.5

            Row {
                anchors.centerIn: parent
                spacing: 8

                Text {
                    text: "\u2190"  // Left arrow
                    font.pixelSize: 20
                    font.bold: true
                    color: currentPage > 0 ? "#1a1a2e" : "#666688"
                }

                Text {
                    text: "Back"
                    font.pixelSize: 16
                    font.bold: true
                    color: currentPage > 0 ? "#1a1a2e" : "#666688"
                }
            }

            MouseArea {
                anchors.fill: parent
                enabled: currentPage > 0
                onClicked: currentPage--
            }
        }

        // Page indicator dots
        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            Repeater {
                model: totalPages

                Rectangle {
                    width: currentPage === index ? 20 : 8
                    height: 8
                    radius: 4
                    color: currentPage === index ? "#4fc3f7" : "#444466"

                    Behavior on width { NumberAnimation { duration: 150 } }
                }
            }
        }

        // Next button
        Rectangle {
            width: 100
            height: 50
            radius: 25
            color: currentPage < totalPages - 1 ? "#4fc3f7" : "#333355"
            opacity: currentPage < totalPages - 1 ? 1.0 : 0.5

            Row {
                anchors.centerIn: parent
                spacing: 8

                Text {
                    text: "Next"
                    font.pixelSize: 16
                    font.bold: true
                    color: currentPage < totalPages - 1 ? "#1a1a2e" : "#666688"
                }

                Text {
                    text: "\u2192"  // Right arrow
                    font.pixelSize: 20
                    font.bold: true
                    color: currentPage < totalPages - 1 ? "#1a1a2e" : "#666688"
                }
            }

            MouseArea {
                anchors.fill: parent
                enabled: currentPage < totalPages - 1
                onClicked: currentPage++
            }
        }
    }

    // Skip button
    Text {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 30
        text: "Skip"
        font.pixelSize: 18
        color: "#888888"
        visible: currentPage < totalPages - 1

        MouseArea {
            anchors.fill: parent
            anchors.margins: -10
            onClicked: currentPage = totalPages - 1
        }
    }

    // Save configuration
    function saveConfig(dontShow) {
        var config = { "showOnStartup": !dontShow }
        var xhr = new XMLHttpRequest()
        var path = configPath.toString().replace("file://", "")

        // We can't write directly from QML, so we'll use a different approach
        // Write to stdout which can be captured by the shell
        console.log("WELCOME_CONFIG:" + JSON.stringify(config))
    }

    Component.onCompleted: {
        console.log("Welcome app started")
    }
}
