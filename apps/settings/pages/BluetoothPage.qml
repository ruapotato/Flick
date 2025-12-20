import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Page {
    id: bluetoothPage

    background: Rectangle {
        color: "#0a0a0f"
    }

    header: Rectangle {
        height: 100
        color: "#12121a"

        Text {
            anchors.centerIn: parent
            text: "Bluetooth"
            font.pixelSize: 36
            font.weight: Font.Light
            color: "#ffffff"
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        anchors.bottomMargin: 100
        spacing: 24

        // Bluetooth toggle
        Rectangle {
            Layout.fillWidth: true
            height: 80
            color: "#12121a"
            radius: 12

            RowLayout {
                anchors.fill: parent
                anchors.margins: 20

                Text {
                    text: "Bluetooth"
                    font.pixelSize: 24
                    color: "#ffffff"
                    Layout.fillWidth: true
                }

                Switch {
                    id: btSwitch
                    checked: true

                    indicator: Rectangle {
                        implicitWidth: 60
                        implicitHeight: 34
                        radius: 17
                        color: btSwitch.checked ? "#e94560" : "#333344"

                        Rectangle {
                            x: btSwitch.checked ? parent.width - width - 4 : 4
                            anchors.verticalCenter: parent.verticalCenter
                            width: 26
                            height: 26
                            radius: 13
                            color: "#ffffff"

                            Behavior on x {
                                NumberAnimation { duration: 150 }
                            }
                        }
                    }
                }
            }
        }

        // Paired devices
        Text {
            text: "Paired Devices"
            font.pixelSize: 18
            color: "#666677"
            Layout.topMargin: 12
        }

        ListView {
            Layout.fillWidth: true
            Layout.preferredHeight: 180
            clip: true
            spacing: 4

            model: ListModel {
                ListElement { name: "AirPods Pro"; type: "headphones"; connected: true }
                ListElement { name: "Car Stereo"; type: "speaker"; connected: false }
            }

            delegate: Rectangle {
                width: parent.width
                height: 80
                color: mouseArea.pressed ? "#1a1a2e" : "#12121a"
                radius: 12

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 16

                    Text {
                        text: model.type === "headphones" ? "🎧" : "🔊"
                        font.pixelSize: 32
                    }

                    Column {
                        Layout.fillWidth: true
                        spacing: 4

                        Text {
                            text: model.name
                            font.pixelSize: 22
                            color: "#ffffff"
                        }
                        Text {
                            text: model.connected ? "Connected" : "Not Connected"
                            font.pixelSize: 16
                            color: model.connected ? "#4ade80" : "#666677"
                        }
                    }
                }

                MouseArea {
                    id: mouseArea
                    anchors.fill: parent
                }
            }
        }

        // Available devices
        Text {
            text: "Available Devices"
            font.pixelSize: 18
            color: "#666677"
            Layout.topMargin: 12
        }

        Rectangle {
            Layout.fillWidth: true
            height: 80
            color: "#12121a"
            radius: 12

            RowLayout {
                anchors.fill: parent
                anchors.margins: 20

                BusyIndicator {
                    running: true
                    implicitWidth: 32
                    implicitHeight: 32
                }

                Text {
                    text: "Scanning..."
                    font.pixelSize: 20
                    color: "#666677"
                    Layout.fillWidth: true
                }
            }
        }

        Item { Layout.fillHeight: true }
    }

    // Back button - bottom right (Flick design spec)
    Rectangle {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 24
        anchors.bottomMargin: 24
        width: 64
        height: 64
        radius: 32
        color: backButtonMouse.pressed ? "#333344" : "#1a1a2e"
        border.color: "#444455"
        border.width: 2

        Text {
            anchors.centerIn: parent
            text: "←"
            font.pixelSize: 28
            color: "#ffffff"
        }

        MouseArea {
            id: backButtonMouse
            anchors.fill: parent
            onClicked: stackView.pop()
        }
    }
}
