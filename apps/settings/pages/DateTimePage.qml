import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Page {
    id: dateTimePage

    property string currentTime: "12:00"
    property string currentDate: "2024-12-21"
    property string currentDay: "Saturday"
    property string timezone: "UTC"
    property bool ntpEnabled: true

    Component.onCompleted: loadDateTimeInfo()

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: loadDateTimeInfo()
    }

    function loadDateTimeInfo() {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file:///tmp/flick-datetime.json", false)
        try {
            xhr.send()
            if (xhr.status === 200) {
                var data = JSON.parse(xhr.responseText)
                currentTime = data.time || "00:00"
                currentDate = data.date || "2024-01-01"
                currentDay = data.day || "Monday"
                timezone = data.timezone || "UTC"
                ntpEnabled = data.ntp_enabled || false
            }
        } catch (e) {
            // Use JavaScript date as fallback
            var now = new Date()
            currentTime = now.toTimeString().substring(0, 5)
            currentDate = now.toISOString().substring(0, 10)
            currentDay = now.toLocaleDateString('en-US', { weekday: 'long' })
        }
    }

    function toggleNtp() {
        ntpEnabled = !ntpEnabled
        console.warn("DATETIME_CMD:ntp:" + (ntpEnabled ? "on" : "off"))
    }

    background: Rectangle {
        color: "#0a0a0f"
    }

    // Hero section with large clock
    Rectangle {
        id: heroSection
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 320
        color: "transparent"

        // Ambient glow
        Rectangle {
            anchors.centerIn: parent
            width: 350
            height: 280
            radius: 175
            color: "#6366f1"
            opacity: 0.1
        }

        Column {
            anchors.centerIn: parent
            spacing: 12

            // Large time display
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: currentTime
                font.pixelSize: 80
                font.weight: Font.Light
                font.letterSpacing: 4
                color: "#ffffff"

                // Colon blink animation
                Timer {
                    property bool colonVisible: true
                    interval: 500
                    running: true
                    repeat: true
                    onTriggered: colonVisible = !colonVisible
                }
            }

            // Date display
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: currentDay
                font.pixelSize: 28
                font.weight: Font.Medium
                color: "#6366f1"
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: currentDate
                font.pixelSize: 18
                color: "#666677"
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

            Text {
                text: "TIME SETTINGS"
                font.pixelSize: 12
                font.letterSpacing: 2
                color: "#555566"
                leftPadding: 8
            }

            // Auto time sync toggle
            Rectangle {
                width: settingsColumn.width
                height: 90
                radius: 24
                color: ntpMouse.pressed ? "#1e1e2e" : "#14141e"
                border.color: ntpEnabled ? "#6366f1" : "#1a1a2e"
                border.width: ntpEnabled ? 2 : 1

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 16

                    Rectangle {
                        Layout.preferredWidth: 52
                        Layout.preferredHeight: 52
                        radius: 14
                        color: ntpEnabled ? "#1a1a3a" : "#1a1a28"

                        Text {
                            anchors.centerIn: parent
                            text: "🌐"
                            font.pixelSize: 26
                        }
                    }

                    Column {
                        Layout.fillWidth: true
                        spacing: 4

                        Text {
                            text: "Automatic date & time"
                            font.pixelSize: 20
                            color: "#ffffff"
                        }

                        Text {
                            text: "Use network time (NTP)"
                            font.pixelSize: 13
                            color: "#666677"
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: 64
                        Layout.preferredHeight: 36
                        radius: 18
                        color: ntpEnabled ? "#6366f1" : "#2a2a3e"

                        Behavior on color { ColorAnimation { duration: 200 } }

                        Rectangle {
                            x: ntpEnabled ? parent.width - width - 4 : 4
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
                    id: ntpMouse
                    anchors.fill: parent
                    onClicked: toggleNtp()
                }
            }

            // Timezone
            Rectangle {
                width: settingsColumn.width
                height: 90
                radius: 24
                color: "#14141e"
                border.color: "#1a1a2e"
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 16

                    Rectangle {
                        Layout.preferredWidth: 52
                        Layout.preferredHeight: 52
                        radius: 14
                        color: "#1a1a28"

                        Text {
                            anchors.centerIn: parent
                            text: "🌍"
                            font.pixelSize: 26
                        }
                    }

                    Column {
                        Layout.fillWidth: true
                        spacing: 4

                        Text {
                            text: "Time Zone"
                            font.pixelSize: 20
                            color: "#ffffff"
                        }

                        Text {
                            text: timezone
                            font.pixelSize: 13
                            color: "#6366f1"
                        }
                    }

                    Text {
                        text: "→"
                        font.pixelSize: 24
                        color: "#444455"
                    }
                }
            }

            Item { height: 8 }

            Text {
                text: "FORMAT"
                font.pixelSize: 12
                font.letterSpacing: 2
                color: "#555566"
                leftPadding: 8
            }

            // 24-hour time
            Rectangle {
                width: settingsColumn.width
                height: 80
                radius: 24
                color: "#14141e"
                border.color: "#1a1a2e"
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 16

                    Text {
                        text: "⏰"
                        font.pixelSize: 24
                    }

                    Text {
                        text: "24-hour format"
                        font.pixelSize: 18
                        color: "#ffffff"
                        Layout.fillWidth: true
                    }

                    Rectangle {
                        Layout.preferredWidth: 64
                        Layout.preferredHeight: 36
                        radius: 18
                        color: "#6366f1"

                        Rectangle {
                            x: parent.width - width - 4
                            anchors.verticalCenter: parent.verticalCenter
                            width: 28
                            height: 28
                            radius: 14
                            color: "#ffffff"
                        }
                    }
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
