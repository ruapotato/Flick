import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Page {
    id: bluetoothPage

    property bool btEnabled: true

    background: Rectangle {
        color: "#0a0a0f"
    }

    // Hero section with large toggle
    Rectangle {
        id: heroSection
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 280
        color: "transparent"

        // Ambient glow when enabled
        Rectangle {
            anchors.centerIn: parent
            width: 350
            height: 250
            radius: 175
            color: btEnabled ? "#2a2a5c" : "#1a1a28"
            opacity: btEnabled ? 0.3 : 0.1

            Behavior on color { ColorAnimation { duration: 300 } }
            Behavior on opacity { NumberAnimation { duration: 300 } }
        }

        Column {
            anchors.centerIn: parent
            spacing: 24

            // Large Bluetooth icon as toggle
            Rectangle {
                id: btToggle
                anchors.horizontalCenter: parent.horizontalCenter
                width: 120
                height: 120
                radius: 60
                color: btEnabled ? "#2a2a5c" : "#1a1a28"
                border.color: btEnabled ? "#6a6abf" : "#2a2a3e"
                border.width: 3

                Behavior on color { ColorAnimation { duration: 200 } }
                Behavior on border.color { ColorAnimation { duration: 200 } }

                Text {
                    anchors.centerIn: parent
                    text: "🔷"
                    font.pixelSize: 52
                    opacity: btEnabled ? 1 : 0.4

                    Behavior on opacity { NumberAnimation { duration: 200 } }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: btEnabled = !btEnabled
                }

                // Pulse animation when enabled
                Rectangle {
                    anchors.fill: parent
                    radius: 60
                    color: "transparent"
                    border.color: "#6a6abf"
                    border.width: 2
                    opacity: 0
                    scale: 1

                    SequentialAnimation on opacity {
                        running: btEnabled
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.5; duration: 1000 }
                        NumberAnimation { to: 0; duration: 1000 }
                    }

                    SequentialAnimation on scale {
                        running: btEnabled
                        loops: Animation.Infinite
                        NumberAnimation { to: 1.3; duration: 2000 }
                        NumberAnimation { to: 1; duration: 0 }
                    }
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Bluetooth"
                font.pixelSize: 42
                font.weight: Font.ExtraLight
                font.letterSpacing: 6
                color: "#ffffff"
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: btEnabled ? "TAP TO DISABLE" : "TAP TO ENABLE"
                font.pixelSize: 12
                font.letterSpacing: 2
                color: "#555566"
            }
        }
    }

    // Devices list
    Flickable {
        id: deviceList
        anchors.top: heroSection.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 16
        anchors.bottomMargin: 100
        contentHeight: devicesColumn.height
        clip: true
        visible: btEnabled

        Column {
            id: devicesColumn
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 12

            // Paired devices section
            Text {
                text: "PAIRED DEVICES"
                font.pixelSize: 12
                font.letterSpacing: 2
                color: "#555566"
                leftPadding: 8
            }

            // Connected device - highlighted card
            Rectangle {
                width: devicesColumn.width
                height: 120
                radius: 24

                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#1a4a3a" }
                    GradientStop { position: 1.0; color: "#0d251d" }
                }

                Rectangle {
                    anchors.fill: parent
                    radius: 24
                    color: "transparent"
                    border.color: "#4ade80"
                    border.width: 2
                    opacity: 0.5
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 16

                    Rectangle {
                        Layout.preferredWidth: 64
                        Layout.preferredHeight: 64
                        radius: 16
                        color: "#1a5a4a"

                        Text {
                            anchors.centerIn: parent
                            text: "🎧"
                            font.pixelSize: 32
                        }
                    }

                    Column {
                        Layout.fillWidth: true
                        spacing: 6

                        Text {
                            text: "AirPods Pro"
                            font.pixelSize: 22
                            font.weight: Font.Medium
                            color: "#ffffff"
                        }

                        Row {
                            spacing: 8

                            Rectangle {
                                width: 8
                                height: 8
                                radius: 4
                                color: "#4ade80"
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Text {
                                text: "Connected  •  85%"
                                font.pixelSize: 14
                                color: "#4ade80"
                            }
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: console.log("Manage AirPods")
                }
            }

            // Other paired device
            Rectangle {
                width: devicesColumn.width
                height: 90
                radius: 20
                color: deviceMouse.pressed ? "#1e1e2e" : "#14141e"
                border.color: "#1a1a2e"
                border.width: 1

                Behavior on color { ColorAnimation { duration: 100 } }

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
                            text: "🔊"
                            font.pixelSize: 26
                        }
                    }

                    Column {
                        Layout.fillWidth: true
                        spacing: 4

                        Text {
                            text: "Car Stereo"
                            font.pixelSize: 20
                            color: "#ffffff"
                        }

                        Text {
                            text: "Not Connected"
                            font.pixelSize: 13
                            color: "#666677"
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: 8
                        Layout.preferredHeight: 8
                        radius: 4
                        color: "#444455"
                    }
                }

                MouseArea {
                    id: deviceMouse
                    anchors.fill: parent
                    onClicked: console.log("Connect to Car Stereo")
                }
            }

            Item { height: 16 }

            // Scanning section
            Text {
                text: "AVAILABLE DEVICES"
                font.pixelSize: 12
                font.letterSpacing: 2
                color: "#555566"
                leftPadding: 8
            }

            Rectangle {
                width: devicesColumn.width
                height: 80
                radius: 20
                color: "#14141e"
                border.color: "#1a1a2e"
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 16

                    // Animated scanning indicator
                    Item {
                        Layout.preferredWidth: 40
                        Layout.preferredHeight: 40

                        Repeater {
                            model: 3
                            Rectangle {
                                anchors.centerIn: parent
                                width: 12 + index * 10
                                height: width
                                radius: width / 2
                                color: "transparent"
                                border.color: "#e94560"
                                border.width: 2
                                opacity: 0

                                SequentialAnimation on opacity {
                                    running: true
                                    loops: Animation.Infinite
                                    PauseAnimation { duration: index * 300 }
                                    NumberAnimation { to: 0.6; duration: 300 }
                                    NumberAnimation { to: 0; duration: 700 }
                                    PauseAnimation { duration: (2 - index) * 300 }
                                }

                                SequentialAnimation on scale {
                                    running: true
                                    loops: Animation.Infinite
                                    PauseAnimation { duration: index * 300 }
                                    NumberAnimation { from: 0.8; to: 1.5; duration: 1000 }
                                    PauseAnimation { duration: (2 - index) * 300 }
                                }
                            }
                        }

                        Rectangle {
                            anchors.centerIn: parent
                            width: 8
                            height: 8
                            radius: 4
                            color: "#e94560"
                        }
                    }

                    Text {
                        text: "Scanning for devices..."
                        font.pixelSize: 18
                        color: "#888899"
                        Layout.fillWidth: true
                    }
                }
            }
        }
    }

    // Disabled state
    Rectangle {
        anchors.top: heroSection.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 100
        color: "transparent"
        visible: !btEnabled

        Column {
            anchors.centerIn: parent
            spacing: 16

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "📵"
                font.pixelSize: 64
                opacity: 0.3
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Bluetooth is disabled"
                font.pixelSize: 20
                color: "#444455"
            }
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
