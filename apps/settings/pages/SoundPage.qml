import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Page {
    id: soundPage

    property real mediaVolume: 0.7
    property real ringVolume: 0.8

    background: Rectangle {
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#0a0a0f" }
            GradientStop { position: 1.0; color: "#0f0f18" }
        }
    }

    header: Rectangle {
        height: 120
        color: "transparent"

        Rectangle {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 0.3; color: "#e94560" }
                GradientStop { position: 0.7; color: "#e94560" }
                GradientStop { position: 1.0; color: "transparent" }
            }
            opacity: 0.4
        }

        Text {
            anchors.centerIn: parent
            text: "Sound"
            font.pixelSize: 38
            font.weight: Font.Light
            font.letterSpacing: 4
            color: "#ffffff"
        }
    }

    Flickable {
        anchors.fill: parent
        anchors.bottomMargin: 100
        contentHeight: content.height + 40
        clip: true

        ColumnLayout {
            id: content
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 16
            spacing: 16

            // Volume section
            Text {
                text: "VOLUME"
                font.pixelSize: 14
                font.weight: Font.Medium
                font.letterSpacing: 2
                color: "#666677"
                Layout.leftMargin: 8
                Layout.topMargin: 16
            }

            // Media volume
            Rectangle {
                Layout.fillWidth: true
                height: 100
                radius: 16
                color: "#14141e"
                border.color: "#1a1a2e"
                border.width: 1

                Column {
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 12

                    RowLayout {
                        width: parent.width

                        Text {
                            text: "🎵  Media"
                            font.pixelSize: 18
                            color: "#ffffff"
                            Layout.fillWidth: true
                        }

                        Text {
                            text: Math.round(mediaVolume * 100) + "%"
                            font.pixelSize: 14
                            color: "#888899"
                        }
                    }

                    // Slider
                    Item {
                        width: parent.width
                        height: 32

                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            height: 6
                            radius: 3
                            color: "#2a2a3e"

                            Rectangle {
                                width: parent.width * mediaVolume
                                height: parent.height
                                radius: 3
                                color: "#e94560"
                            }
                        }

                        Rectangle {
                            x: (parent.width - 28) * mediaVolume
                            anchors.verticalCenter: parent.verticalCenter
                            width: 28
                            height: 28
                            radius: 14
                            color: "#ffffff"
                        }

                        MouseArea {
                            anchors.fill: parent
                            onPressed: mediaVolume = Math.max(0, Math.min(1, mouse.x / parent.width))
                            onPositionChanged: if (pressed) mediaVolume = Math.max(0, Math.min(1, mouse.x / parent.width))
                        }
                    }
                }
            }

            // Ring volume
            Rectangle {
                Layout.fillWidth: true
                height: 100
                radius: 16
                color: "#14141e"
                border.color: "#1a1a2e"
                border.width: 1

                Column {
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 12

                    RowLayout {
                        width: parent.width

                        Text {
                            text: "🔔  Ringtone"
                            font.pixelSize: 18
                            color: "#ffffff"
                            Layout.fillWidth: true
                        }

                        Text {
                            text: Math.round(ringVolume * 100) + "%"
                            font.pixelSize: 14
                            color: "#888899"
                        }
                    }

                    Item {
                        width: parent.width
                        height: 32

                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            height: 6
                            radius: 3
                            color: "#2a2a3e"

                            Rectangle {
                                width: parent.width * ringVolume
                                height: parent.height
                                radius: 3
                                color: "#e94560"
                            }
                        }

                        Rectangle {
                            x: (parent.width - 28) * ringVolume
                            anchors.verticalCenter: parent.verticalCenter
                            width: 28
                            height: 28
                            radius: 14
                            color: "#ffffff"
                        }

                        MouseArea {
                            anchors.fill: parent
                            onPressed: ringVolume = Math.max(0, Math.min(1, mouse.x / parent.width))
                            onPositionChanged: if (pressed) ringVolume = Math.max(0, Math.min(1, mouse.x / parent.width))
                        }
                    }
                }
            }

            // Sound modes section
            Text {
                text: "SOUND MODE"
                font.pixelSize: 14
                font.weight: Font.Medium
                font.letterSpacing: 2
                color: "#666677"
                Layout.leftMargin: 8
                Layout.topMargin: 20
            }

            // Vibration toggle
            Rectangle {
                Layout.fillWidth: true
                height: 80
                radius: 16
                color: "#14141e"
                border.color: "#1a1a2e"
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 20
                    anchors.rightMargin: 20

                    Rectangle {
                        Layout.preferredWidth: 48
                        Layout.preferredHeight: 48
                        radius: 12
                        color: vibrationSwitch.checked ? "#2a3c3a" : "#1a1a28"

                        Text {
                            anchors.centerIn: parent
                            text: "📳"
                            font.pixelSize: 22
                        }
                    }

                    Column {
                        Layout.fillWidth: true
                        Layout.leftMargin: 16
                        spacing: 4

                        Text {
                            text: "Vibration"
                            font.pixelSize: 18
                            color: "#ffffff"
                        }
                        Text {
                            text: "Vibrate for calls and notifications"
                            font.pixelSize: 13
                            color: "#666677"
                        }
                    }

                    Switch {
                        id: vibrationSwitch
                        checked: true

                        indicator: Rectangle {
                            implicitWidth: 64
                            implicitHeight: 36
                            radius: 18
                            color: vibrationSwitch.checked ? "#e94560" : "#333344"

                            Behavior on color { ColorAnimation { duration: 150 } }

                            Rectangle {
                                x: vibrationSwitch.checked ? parent.width - width - 4 : 4
                                anchors.verticalCenter: parent.verticalCenter
                                width: 28
                                height: 28
                                radius: 14
                                color: "#ffffff"

                                Behavior on x { NumberAnimation { duration: 150 } }
                            }
                        }
                    }
                }
            }

            // Silent mode toggle
            Rectangle {
                Layout.fillWidth: true
                height: 80
                radius: 16
                color: "#14141e"
                border.color: silentSwitch.checked ? "#e94560" : "#1a1a2e"
                border.width: silentSwitch.checked ? 2 : 1

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 20
                    anchors.rightMargin: 20

                    Rectangle {
                        Layout.preferredWidth: 48
                        Layout.preferredHeight: 48
                        radius: 12
                        color: silentSwitch.checked ? "#3c2a3a" : "#1a1a28"

                        Text {
                            anchors.centerIn: parent
                            text: "🔕"
                            font.pixelSize: 22
                        }
                    }

                    Column {
                        Layout.fillWidth: true
                        Layout.leftMargin: 16
                        spacing: 4

                        Text {
                            text: "Silent Mode"
                            font.pixelSize: 18
                            color: "#ffffff"
                        }
                        Text {
                            text: "Mute all sounds"
                            font.pixelSize: 13
                            color: "#666677"
                        }
                    }

                    Switch {
                        id: silentSwitch
                        checked: false

                        indicator: Rectangle {
                            implicitWidth: 64
                            implicitHeight: 36
                            radius: 18
                            color: silentSwitch.checked ? "#e94560" : "#333344"

                            Behavior on color { ColorAnimation { duration: 150 } }

                            Rectangle {
                                x: silentSwitch.checked ? parent.width - width - 4 : 4
                                anchors.verticalCenter: parent.verticalCenter
                                width: 28
                                height: 28
                                radius: 14
                                color: "#ffffff"

                                Behavior on x { NumberAnimation { duration: 150 } }
                            }
                        }
                    }
                }
            }

            Item { height: 40 }
        }
    }

    // Back button
    Rectangle {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 24
        anchors.bottomMargin: 24
        width: 72
        height: 72
        radius: 36
        color: backButtonMouse.pressed ? "#2a2a3e" : "#1a1a28"
        border.color: backButtonMouse.pressed ? "#e94560" : "#2a2a3e"
        border.width: 2

        Behavior on color { ColorAnimation { duration: 100 } }
        Behavior on border.color { ColorAnimation { duration: 100 } }

        Rectangle {
            anchors.fill: parent
            anchors.margins: 2
            radius: 34
            color: "transparent"
            border.color: "#ffffff"
            border.width: 1
            opacity: 0.05
        }

        Text {
            anchors.centerIn: parent
            text: "←"
            font.pixelSize: 28
            font.weight: Font.Light
            color: backButtonMouse.pressed ? "#e94560" : "#ffffff"

            Behavior on color { ColorAnimation { duration: 100 } }
        }

        MouseArea {
            id: backButtonMouse
            anchors.fill: parent
            onClicked: stackView.pop()
        }
    }

    // Home indicator
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 8
        width: 100
        height: 4
        radius: 2
        color: "#333344"
        opacity: 0.5
    }
}
