import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Page {
    id: bluetoothPage

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
            text: "Bluetooth"
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
            spacing: 12

            // Bluetooth toggle
            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 8
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
                        Layout.preferredWidth: 52
                        Layout.preferredHeight: 52
                        radius: 12
                        color: btSwitch.checked ? "#2a2a5c" : "#1a1a28"

                        Text {
                            anchors.centerIn: parent
                            text: "🔵"
                            font.pixelSize: 24
                        }
                    }

                    Text {
                        text: "Bluetooth"
                        font.pixelSize: 22
                        font.weight: Font.Medium
                        color: "#ffffff"
                        Layout.fillWidth: true
                        Layout.leftMargin: 16
                    }

                    Switch {
                        id: btSwitch
                        checked: true

                        indicator: Rectangle {
                            implicitWidth: 64
                            implicitHeight: 36
                            radius: 18
                            color: btSwitch.checked ? "#e94560" : "#333344"

                            Behavior on color { ColorAnimation { duration: 150 } }

                            Rectangle {
                                x: btSwitch.checked ? parent.width - width - 4 : 4
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

            // Paired devices section
            Text {
                text: "PAIRED DEVICES"
                font.pixelSize: 14
                font.weight: Font.Medium
                font.letterSpacing: 2
                color: "#666677"
                Layout.leftMargin: 8
                Layout.topMargin: 20
                visible: btSwitch.checked
            }

            Repeater {
                model: btSwitch.checked ? pairedModel : []

                Rectangle {
                    Layout.fillWidth: true
                    height: 80
                    radius: 16
                    color: deviceMouse.pressed ? "#1e1e2e" : "#14141e"
                    border.color: model.connected ? "#4ade80" : "#1a1a2e"
                    border.width: model.connected ? 2 : 1

                    Behavior on color { ColorAnimation { duration: 100 } }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 20
                        anchors.rightMargin: 20
                        spacing: 16

                        Rectangle {
                            Layout.preferredWidth: 48
                            Layout.preferredHeight: 48
                            radius: 12
                            color: model.connected ? "#1a3a2a" : "#1a1a28"

                            Text {
                                anchors.centerIn: parent
                                text: model.type === "headphones" ? "🎧" : "🔊"
                                font.pixelSize: 22
                            }
                        }

                        Column {
                            Layout.fillWidth: true
                            spacing: 4

                            Text {
                                text: model.name
                                font.pixelSize: 18
                                color: "#ffffff"
                            }
                            Text {
                                text: model.connected ? "Connected" : "Not Connected"
                                font.pixelSize: 13
                                color: model.connected ? "#4ade80" : "#666677"
                            }
                        }

                        Rectangle {
                            Layout.preferredWidth: 8
                            Layout.preferredHeight: 8
                            radius: 4
                            color: model.connected ? "#4ade80" : "#444455"
                        }
                    }

                    MouseArea {
                        id: deviceMouse
                        anchors.fill: parent
                        onClicked: console.log("Toggle connection: " + model.name)
                    }
                }
            }

            ListModel {
                id: pairedModel
                ListElement { name: "AirPods Pro"; type: "headphones"; connected: true }
                ListElement { name: "Car Stereo"; type: "speaker"; connected: false }
            }

            // Available devices section
            Text {
                text: "AVAILABLE DEVICES"
                font.pixelSize: 14
                font.weight: Font.Medium
                font.letterSpacing: 2
                color: "#666677"
                Layout.leftMargin: 8
                Layout.topMargin: 20
                visible: btSwitch.checked
            }

            Rectangle {
                Layout.fillWidth: true
                height: 70
                radius: 16
                color: "#14141e"
                border.color: "#1a1a2e"
                border.width: 1
                visible: btSwitch.checked

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 20
                    anchors.rightMargin: 20
                    spacing: 16

                    BusyIndicator {
                        Layout.preferredWidth: 32
                        Layout.preferredHeight: 32
                        running: true

                        contentItem: Item {
                            Rectangle {
                                anchors.centerIn: parent
                                width: 24
                                height: 24
                                radius: 12
                                color: "transparent"
                                border.color: "#e94560"
                                border.width: 2
                                opacity: 0.3

                                Rectangle {
                                    width: 8
                                    height: 8
                                    radius: 4
                                    color: "#e94560"
                                    anchors.top: parent.top
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.topMargin: -2
                                }

                                RotationAnimation on rotation {
                                    from: 0
                                    to: 360
                                    duration: 1000
                                    loops: Animation.Infinite
                                }
                            }
                        }
                    }

                    Text {
                        text: "Scanning for devices..."
                        font.pixelSize: 16
                        color: "#888899"
                        Layout.fillWidth: true
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
