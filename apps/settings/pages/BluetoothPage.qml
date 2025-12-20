import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Page {
    id: bluetoothPage

    background: Rectangle {
        color: "#0a0a0f"
    }

    header: Rectangle {
        height: 140
        color: "#12121a"

        Text {
            anchors.centerIn: parent
            text: "Bluetooth"
            font.pixelSize: 48
            font.weight: Font.Light
            color: "#ffffff"
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 32
        anchors.bottomMargin: 120
        spacing: 32

        // Bluetooth toggle
        Rectangle {
            Layout.fillWidth: true
            height: 120
            color: "#12121a"
            radius: 16

            RowLayout {
                anchors.fill: parent
                anchors.margins: 28

                Text {
                    text: "Bluetooth"
                    font.pixelSize: 32
                    color: "#ffffff"
                    Layout.fillWidth: true
                }

                Switch {
                    id: btSwitch
                    checked: true

                    indicator: Rectangle {
                        implicitWidth: 80
                        implicitHeight: 44
                        radius: 22
                        color: btSwitch.checked ? "#e94560" : "#333344"

                        Rectangle {
                            x: btSwitch.checked ? parent.width - width - 4 : 4
                            anchors.verticalCenter: parent.verticalCenter
                            width: 36
                            height: 36
                            radius: 18
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
            font.pixelSize: 24
            color: "#666677"
            Layout.topMargin: 16
        }

        ListView {
            Layout.fillWidth: true
            Layout.preferredHeight: 260
            clip: true
            spacing: 8

            model: ListModel {
                ListElement { name: "AirPods Pro"; type: "headphones"; connected: true }
                ListElement { name: "Car Stereo"; type: "speaker"; connected: false }
            }

            delegate: Rectangle {
                width: parent.width
                height: 120
                color: mouseArea.pressed ? "#1a1a2e" : "#12121a"
                radius: 16

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 28
                    spacing: 24

                    Text {
                        text: model.type === "headphones" ? "🎧" : "🔊"
                        font.pixelSize: 44
                    }

                    Column {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            text: model.name
                            font.pixelSize: 28
                            color: "#ffffff"
                        }
                        Text {
                            text: model.connected ? "Connected" : "Not Connected"
                            font.pixelSize: 20
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
            font.pixelSize: 24
            color: "#666677"
            Layout.topMargin: 16
        }

        Rectangle {
            Layout.fillWidth: true
            height: 120
            color: "#12121a"
            radius: 16

            RowLayout {
                anchors.fill: parent
                anchors.margins: 28

                BusyIndicator {
                    running: true
                    implicitWidth: 44
                    implicitHeight: 44
                }

                Text {
                    text: "Scanning..."
                    font.pixelSize: 28
                    color: "#666677"
                    Layout.fillWidth: true
                }
            }
        }

        Item { Layout.fillHeight: true }
    }

    // Back button - bottom right
    Rectangle {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 32
        anchors.bottomMargin: 32
        width: 80
        height: 80
        radius: 40
        color: backButtonMouse.pressed ? "#333344" : "#1a1a2e"
        border.color: "#444455"
        border.width: 3

        Text {
            anchors.centerIn: parent
            text: "←"
            font.pixelSize: 36
            color: "#ffffff"
        }

        MouseArea {
            id: backButtonMouse
            anchors.fill: parent
            onClicked: stackView.pop()
        }
    }
}
