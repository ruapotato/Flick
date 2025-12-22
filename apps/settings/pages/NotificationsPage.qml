import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Page {
    id: notificationsPage

    property bool doNotDisturb: false
    property bool showPreviews: true
    property bool soundEnabled: true
    property bool vibrationEnabled: true
    property bool ledEnabled: true

    Component.onCompleted: loadNotificationSettings()

    function loadNotificationSettings() {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file:///tmp/flick-notifications.json", false)
        try {
            xhr.send()
            if (xhr.status === 200) {
                var data = JSON.parse(xhr.responseText)
                doNotDisturb = data.dnd || false
                showPreviews = data.previews !== false
                soundEnabled = data.sound !== false
                vibrationEnabled = data.vibration !== false
                ledEnabled = data.led !== false
            }
        } catch (e) {
            console.log("Could not read notification settings")
        }
    }

    function toggleDnd() {
        doNotDisturb = !doNotDisturb
        console.warn("NOTIFY_CMD:dnd:" + (doNotDisturb ? "on" : "off"))
    }

    function togglePreviews() {
        showPreviews = !showPreviews
        console.warn("NOTIFY_CMD:previews:" + (showPreviews ? "on" : "off"))
    }

    function toggleSound() {
        soundEnabled = !soundEnabled
        console.warn("NOTIFY_CMD:sound:" + (soundEnabled ? "on" : "off"))
    }

    function toggleVibration() {
        vibrationEnabled = !vibrationEnabled
        console.warn("NOTIFY_CMD:vibration:" + (vibrationEnabled ? "on" : "off"))
    }

    background: Rectangle {
        color: "#0a0a0f"
    }

    // Hero section
    Rectangle {
        id: heroSection
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 280
        color: "transparent"

        // Ambient glow
        Rectangle {
            anchors.centerIn: parent
            width: 350
            height: 250
            radius: 175
            color: doNotDisturb ? "#ef4444" : "#f59e0b"
            opacity: 0.12

            Behavior on color { ColorAnimation { duration: 300 } }
        }

        Column {
            anchors.centerIn: parent
            spacing: 20

            // Large icon
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 120
                height: 120
                radius: 60
                color: doNotDisturb ? "#3a1a1a" : "#3a2a1a"
                border.color: doNotDisturb ? "#ef4444" : "#f59e0b"
                border.width: 3

                Behavior on color { ColorAnimation { duration: 300 } }
                Behavior on border.color { ColorAnimation { duration: 300 } }

                Text {
                    anchors.centerIn: parent
                    text: doNotDisturb ? "🔕" : "🔔"
                    font.pixelSize: 52

                    // Ring animation when not DND
                    SequentialAnimation on rotation {
                        running: !doNotDisturb
                        loops: Animation.Infinite
                        PauseAnimation { duration: 3000 }
                        NumberAnimation { to: 15; duration: 100 }
                        NumberAnimation { to: -15; duration: 100 }
                        NumberAnimation { to: 10; duration: 100 }
                        NumberAnimation { to: -10; duration: 100 }
                        NumberAnimation { to: 0; duration: 100 }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: toggleDnd()
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Notifications"
                font.pixelSize: 42
                font.weight: Font.ExtraLight
                font.letterSpacing: 6
                color: "#ffffff"
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: doNotDisturb ? "DO NOT DISTURB" : "TAP TO MUTE"
                font.pixelSize: 12
                font.letterSpacing: 2
                color: doNotDisturb ? "#ef4444" : "#555566"

                Behavior on color { ColorAnimation { duration: 300 } }
            }
        }
    }

    // Settings
    Flickable {
        anchors.top: heroSection.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 16
        anchors.bottomMargin: 100
        contentHeight: settingsColumn.height
        clip: true

        Column {
            id: settingsColumn
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 12

            // DND toggle card
            Rectangle {
                width: settingsColumn.width
                height: 100
                radius: 24
                color: doNotDisturb ? "#2a1a1a" : "#14141e"
                border.color: doNotDisturb ? "#ef4444" : "#1a1a2e"
                border.width: doNotDisturb ? 2 : 1

                Behavior on color { ColorAnimation { duration: 200 } }
                Behavior on border.color { ColorAnimation { duration: 200 } }

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 16

                    Rectangle {
                        Layout.preferredWidth: 56
                        Layout.preferredHeight: 56
                        radius: 14
                        color: doNotDisturb ? "#4a1a1a" : "#1a1a28"

                        Text {
                            anchors.centerIn: parent
                            text: "🌙"
                            font.pixelSize: 28
                        }
                    }

                    Column {
                        Layout.fillWidth: true
                        spacing: 6

                        Text {
                            text: "Do Not Disturb"
                            font.pixelSize: 20
                            color: "#ffffff"
                        }

                        Text {
                            text: doNotDisturb ? "All notifications silenced" : "Notifications are on"
                            font.pixelSize: 13
                            color: doNotDisturb ? "#ef4444" : "#666677"
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: 64
                        Layout.preferredHeight: 36
                        radius: 18
                        color: doNotDisturb ? "#ef4444" : "#2a2a3e"

                        Behavior on color { ColorAnimation { duration: 200 } }

                        Rectangle {
                            x: doNotDisturb ? parent.width - width - 4 : 4
                            anchors.verticalCenter: parent.verticalCenter
                            width: 28
                            height: 28
                            radius: 14
                            color: "#ffffff"

                            Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: toggleDnd()
                }
            }

            Item { height: 8 }

            Text {
                text: "NOTIFICATION STYLE"
                font.pixelSize: 12
                font.letterSpacing: 2
                color: "#555566"
                leftPadding: 8
            }

            // Show previews
            Rectangle {
                width: settingsColumn.width
                height: 80
                radius: 24
                color: previewMouse.pressed ? "#1e1e2e" : "#14141e"
                border.color: showPreviews ? "#f59e0b" : "#1a1a2e"
                border.width: showPreviews ? 2 : 1
                opacity: doNotDisturb ? 0.5 : 1

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 16

                    Text {
                        text: "👁️"
                        font.pixelSize: 24
                    }

                    Text {
                        text: "Show Previews"
                        font.pixelSize: 18
                        color: "#ffffff"
                        Layout.fillWidth: true
                    }

                    Rectangle {
                        Layout.preferredWidth: 64
                        Layout.preferredHeight: 36
                        radius: 18
                        color: showPreviews ? "#f59e0b" : "#2a2a3e"

                        Rectangle {
                            x: showPreviews ? parent.width - width - 4 : 4
                            anchors.verticalCenter: parent.verticalCenter
                            width: 28
                            height: 28
                            radius: 14
                            color: "#ffffff"

                            Behavior on x { NumberAnimation { duration: 200 } }
                        }
                    }
                }

                MouseArea {
                    id: previewMouse
                    anchors.fill: parent
                    enabled: !doNotDisturb
                    onClicked: togglePreviews()
                }
            }

            // Sound
            Rectangle {
                width: settingsColumn.width
                height: 80
                radius: 24
                color: soundMouse.pressed ? "#1e1e2e" : "#14141e"
                border.color: soundEnabled ? "#4ade80" : "#1a1a2e"
                border.width: soundEnabled ? 2 : 1
                opacity: doNotDisturb ? 0.5 : 1

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 16

                    Text {
                        text: "🔊"
                        font.pixelSize: 24
                    }

                    Text {
                        text: "Sound"
                        font.pixelSize: 18
                        color: "#ffffff"
                        Layout.fillWidth: true
                    }

                    Rectangle {
                        Layout.preferredWidth: 64
                        Layout.preferredHeight: 36
                        radius: 18
                        color: soundEnabled ? "#4ade80" : "#2a2a3e"

                        Rectangle {
                            x: soundEnabled ? parent.width - width - 4 : 4
                            anchors.verticalCenter: parent.verticalCenter
                            width: 28
                            height: 28
                            radius: 14
                            color: "#ffffff"

                            Behavior on x { NumberAnimation { duration: 200 } }
                        }
                    }
                }

                MouseArea {
                    id: soundMouse
                    anchors.fill: parent
                    enabled: !doNotDisturb
                    onClicked: toggleSound()
                }
            }

            // Vibration
            Rectangle {
                width: settingsColumn.width
                height: 80
                radius: 24
                color: vibMouse.pressed ? "#1e1e2e" : "#14141e"
                border.color: vibrationEnabled ? "#8b5cf6" : "#1a1a2e"
                border.width: vibrationEnabled ? 2 : 1
                opacity: doNotDisturb ? 0.5 : 1

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 16

                    Text {
                        text: "📳"
                        font.pixelSize: 24
                    }

                    Text {
                        text: "Vibration"
                        font.pixelSize: 18
                        color: "#ffffff"
                        Layout.fillWidth: true
                    }

                    Rectangle {
                        Layout.preferredWidth: 64
                        Layout.preferredHeight: 36
                        radius: 18
                        color: vibrationEnabled ? "#8b5cf6" : "#2a2a3e"

                        Rectangle {
                            x: vibrationEnabled ? parent.width - width - 4 : 4
                            anchors.verticalCenter: parent.verticalCenter
                            width: 28
                            height: 28
                            radius: 14
                            color: "#ffffff"

                            Behavior on x { NumberAnimation { duration: 200 } }
                        }
                    }
                }

                MouseArea {
                    id: vibMouse
                    anchors.fill: parent
                    enabled: !doNotDisturb
                    onClicked: toggleVibration()
                }
            }

            Item { height: 20 }
        }
    }

    // Back button
    Rectangle {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 24
        anchors.bottomMargin: 120
        width: 72
        height: 72
        radius: 36
        color: backMouse.pressed ? "#c23a50" : "#e94560"

        Behavior on color { ColorAnimation { duration: 150 } }

        Text {
            anchors.centerIn: parent
            text: "←"
            font.pixelSize: 32
            font.weight: Font.Medium
            color: "#ffffff"
        }

        MouseArea {
            id: backMouse
            anchors.fill: parent
            onClicked: stackView.pop()
        }
    }

    // Home indicator
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 8
        width: 120
        height: 4
        radius: 2
        color: "#333344"
    }
}
