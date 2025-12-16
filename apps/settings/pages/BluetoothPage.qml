import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Page {
    id: bluetoothPage

    background: Rectangle {
        color: "#0a0a0f"
    }

    header: Rectangle {
        height: 80
        color: "#12121a"

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 16

            Text {
                text: "‹"
                font.pixelSize: 32
                color: "#e94560"
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -10
                    onClicked: stackView.pop()
                }
            }

            Text {
                text: "Bluetooth"
                font.pixelSize: 28
                font.weight: Font.Light
                color: "#ffffff"
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
            }

            Item { width: 32 }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 20

        // Bluetooth toggle
        Rectangle {
            Layout.fillWidth: true
            height: 60
            color: "#12121a"
            radius: 10

            RowLayout {
                anchors.fill: parent
                anchors.margins: 16

                Text {
                    text: "Bluetooth"
                    font.pixelSize: 18
                    color: "#ffffff"
                    Layout.fillWidth: true
                }

                Switch {
                    id: btSwitch
                    checked: true

                    indicator: Rectangle {
                        implicitWidth: 50
                        implicitHeight: 28
                        radius: 14
                        color: btSwitch.checked ? "#e94560" : "#333344"

                        Rectangle {
                            x: btSwitch.checked ? parent.width - width - 4 : 4
                            anchors.verticalCenter: parent.verticalCenter
                            width: 20
                            height: 20
                            radius: 10
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
            font.pixelSize: 14
            color: "#666677"
            Layout.topMargin: 10
        }

        ListView {
            Layout.fillWidth: true
            Layout.preferredHeight: 130
            clip: true
            spacing: 2

            model: ListModel {
                ListElement { name: "AirPods Pro"; type: "headphones"; connected: true }
                ListElement { name: "Car Stereo"; type: "speaker"; connected: false }
            }

            delegate: Rectangle {
                width: parent.width
                height: 60
                color: mouseArea.pressed ? "#1a1a2e" : "#12121a"
                radius: 10

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 12

                    Text {
                        text: model.type === "headphones" ? "🎧" : "🔊"
                        font.pixelSize: 24
                    }

                    Column {
                        Layout.fillWidth: true
                        spacing: 2

                        Text {
                            text: model.name
                            font.pixelSize: 16
                            color: "#ffffff"
                        }
                        Text {
                            text: model.connected ? "Connected" : "Not Connected"
                            font.pixelSize: 12
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
            font.pixelSize: 14
            color: "#666677"
            Layout.topMargin: 10
        }

        Rectangle {
            Layout.fillWidth: true
            height: 60
            color: "#12121a"
            radius: 10

            RowLayout {
                anchors.fill: parent
                anchors.margins: 16

                BusyIndicator {
                    running: true
                    implicitWidth: 24
                    implicitHeight: 24
                }

                Text {
                    text: "Scanning..."
                    font.pixelSize: 16
                    color: "#666677"
                    Layout.fillWidth: true
                }
            }
        }

        Item { Layout.fillHeight: true }
    }
}
