import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Page {
    id: soundPage

    property real mediaVolume: 0.7
    property real ringVolume: 0.8
    property bool vibration: true
    property bool silentMode: false

    background: Rectangle {
        color: "#0a0a0f"
    }

    // Hero section with volume visualization
    Rectangle {
        id: heroSection
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 260
        color: "transparent"

        // Ambient glow
        Rectangle {
            anchors.centerIn: parent
            width: 350
            height: 250
            radius: 175
            color: silentMode ? "#4a1a1a" : "#1a4a3a"
            opacity: 0.2

            Behavior on color { ColorAnimation { duration: 300 } }
        }

        Column {
            anchors.centerIn: parent
            spacing: 20

            // Sound wave visualization
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 8
                height: 80

                Repeater {
                    model: 7
                    Rectangle {
                        width: 8
                        height: silentMode ? 8 : (20 + Math.random() * 60 * mediaVolume)
                        radius: 4
                        color: silentMode ? "#4a4a5a" : "#4ade80"
                        anchors.verticalCenter: parent.verticalCenter

                        Behavior on height { NumberAnimation { duration: 150 } }
                        Behavior on color { ColorAnimation { duration: 300 } }

                        // Animate bars when not silent
                        SequentialAnimation on height {
                            running: !silentMode
                            loops: Animation.Infinite
                            NumberAnimation {
                                to: 20 + Math.random() * 60 * mediaVolume
                                duration: 200 + Math.random() * 300
                            }
                            NumberAnimation {
                                to: 30 + Math.random() * 50 * mediaVolume
                                duration: 200 + Math.random() * 300
                            }
                        }
                    }
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Sound"
                font.pixelSize: 42
                font.weight: Font.ExtraLight
                font.letterSpacing: 6
                color: "#ffffff"
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: silentMode ? "SILENT MODE ACTIVE" : "VOLUME CONTROL"
                font.pixelSize: 12
                font.letterSpacing: 2
                color: silentMode ? "#e94560" : "#555566"

                Behavior on color { ColorAnimation { duration: 300 } }
            }
        }
    }

    // Volume controls and settings
    Flickable {
        anchors.top: heroSection.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 16
        anchors.bottomMargin: 100
        contentHeight: controlsColumn.height
        clip: true

        Column {
            id: controlsColumn
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 16

            // Media volume slider
            Rectangle {
                width: controlsColumn.width
                height: 120
                radius: 24
                color: "#14141e"
                border.color: "#1a1a2e"
                border.width: 1
                opacity: silentMode ? 0.5 : 1

                Column {
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 16

                    RowLayout {
                        width: parent.width

                        Text {
                            text: "🎵"
                            font.pixelSize: 24
                        }

                        Text {
                            text: "Media"
                            font.pixelSize: 20
                            color: "#ffffff"
                            Layout.fillWidth: true
                            Layout.leftMargin: 12
                        }

                        Text {
                            text: Math.round(mediaVolume * 100) + "%"
                            font.pixelSize: 18
                            font.weight: Font.Medium
                            color: "#e94560"
                        }
                    }

                    // Slider
                    Item {
                        width: parent.width
                        height: 44

                        Rectangle {
                            anchors.centerIn: parent
                            width: parent.width
                            height: 8
                            radius: 4
                            color: "#2a2a3e"

                            Rectangle {
                                width: parent.width * mediaVolume
                                height: parent.height
                                radius: 4
                                color: "#e94560"

                                Behavior on width { NumberAnimation { duration: 50 } }
                            }
                        }

                        Rectangle {
                            x: (parent.width - 40) * mediaVolume
                            anchors.verticalCenter: parent.verticalCenter
                            width: 40
                            height: 40
                            radius: 20
                            color: "#ffffff"
                            border.color: "#e94560"
                            border.width: 3

                            Behavior on x { NumberAnimation { duration: 50 } }
                        }

                        MouseArea {
                            anchors.fill: parent
                            enabled: !silentMode
                            onPressed: mediaVolume = Math.max(0, Math.min(1, mouse.x / parent.width))
                            onPositionChanged: if (pressed) mediaVolume = Math.max(0, Math.min(1, mouse.x / parent.width))
                        }
                    }
                }
            }

            // Ring volume slider
            Rectangle {
                width: controlsColumn.width
                height: 120
                radius: 24
                color: "#14141e"
                border.color: "#1a1a2e"
                border.width: 1
                opacity: silentMode ? 0.5 : 1

                Column {
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 16

                    RowLayout {
                        width: parent.width

                        Text {
                            text: "🔔"
                            font.pixelSize: 24
                        }

                        Text {
                            text: "Ringtone"
                            font.pixelSize: 20
                            color: "#ffffff"
                            Layout.fillWidth: true
                            Layout.leftMargin: 12
                        }

                        Text {
                            text: Math.round(ringVolume * 100) + "%"
                            font.pixelSize: 18
                            font.weight: Font.Medium
                            color: "#e94560"
                        }
                    }

                    // Slider
                    Item {
                        width: parent.width
                        height: 44

                        Rectangle {
                            anchors.centerIn: parent
                            width: parent.width
                            height: 8
                            radius: 4
                            color: "#2a2a3e"

                            Rectangle {
                                width: parent.width * ringVolume
                                height: parent.height
                                radius: 4
                                color: "#e94560"

                                Behavior on width { NumberAnimation { duration: 50 } }
                            }
                        }

                        Rectangle {
                            x: (parent.width - 40) * ringVolume
                            anchors.verticalCenter: parent.verticalCenter
                            width: 40
                            height: 40
                            radius: 20
                            color: "#ffffff"
                            border.color: "#e94560"
                            border.width: 3

                            Behavior on x { NumberAnimation { duration: 50 } }
                        }

                        MouseArea {
                            anchors.fill: parent
                            enabled: !silentMode
                            onPressed: ringVolume = Math.max(0, Math.min(1, mouse.x / parent.width))
                            onPositionChanged: if (pressed) ringVolume = Math.max(0, Math.min(1, mouse.x / parent.width))
                        }
                    }
                }
            }

            Item { height: 8 }

            Text {
                text: "SOUND MODE"
                font.pixelSize: 12
                font.letterSpacing: 2
                color: "#555566"
                leftPadding: 8
            }

            // Vibration toggle
            Rectangle {
                width: controlsColumn.width
                height: 90
                radius: 24
                color: vibMouse.pressed ? "#1e1e2e" : "#14141e"
                border.color: vibration ? "#4ade80" : "#1a1a2e"
                border.width: vibration ? 2 : 1

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 16

                    Rectangle {
                        Layout.preferredWidth: 52
                        Layout.preferredHeight: 52
                        radius: 14
                        color: vibration ? "#1a3a2a" : "#1a1a28"

                        Text {
                            anchors.centerIn: parent
                            text: "📳"
                            font.pixelSize: 26
                        }
                    }

                    Column {
                        Layout.fillWidth: true
                        spacing: 4

                        Text {
                            text: "Vibration"
                            font.pixelSize: 20
                            color: "#ffffff"
                        }

                        Text {
                            text: "Vibrate for calls and notifications"
                            font.pixelSize: 13
                            color: "#666677"
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: 64
                        Layout.preferredHeight: 36
                        radius: 18
                        color: vibration ? "#4ade80" : "#2a2a3e"

                        Behavior on color { ColorAnimation { duration: 200 } }

                        Rectangle {
                            x: vibration ? parent.width - width - 4 : 4
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
                    id: vibMouse
                    anchors.fill: parent
                    onClicked: vibration = !vibration
                }
            }

            // Silent mode toggle
            Rectangle {
                width: controlsColumn.width
                height: 90
                radius: 24
                color: silentMouse.pressed ? "#1e1e2e" : "#14141e"
                border.color: silentMode ? "#e94560" : "#1a1a2e"
                border.width: silentMode ? 2 : 1

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 16

                    Rectangle {
                        Layout.preferredWidth: 52
                        Layout.preferredHeight: 52
                        radius: 14
                        color: silentMode ? "#3a1a1a" : "#1a1a28"

                        Text {
                            anchors.centerIn: parent
                            text: "🔕"
                            font.pixelSize: 26
                        }
                    }

                    Column {
                        Layout.fillWidth: true
                        spacing: 4

                        Text {
                            text: "Silent Mode"
                            font.pixelSize: 20
                            color: "#ffffff"
                        }

                        Text {
                            text: "Mute all sounds"
                            font.pixelSize: 13
                            color: "#666677"
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: 64
                        Layout.preferredHeight: 36
                        radius: 18
                        color: silentMode ? "#e94560" : "#2a2a3e"

                        Behavior on color { ColorAnimation { duration: 200 } }

                        Rectangle {
                            x: silentMode ? parent.width - width - 4 : 4
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
                    id: silentMouse
                    anchors.fill: parent
                    onClicked: silentMode = !silentMode
                }
            }

            Item { height: 20 }
        }
    }

    // Back button - prominent floating action button
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
