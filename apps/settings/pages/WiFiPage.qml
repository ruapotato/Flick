import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Page {
    id: wifiPage

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
                text: "WiFi"
                font.pixelSize: 28
                font.weight: Font.Light
                color: "#ffffff"
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
            }

            // Placeholder for symmetry
            Item { width: 32 }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 20

        // WiFi toggle
        Rectangle {
            Layout.fillWidth: true
            height: 60
            color: "#12121a"
            radius: 10

            RowLayout {
                anchors.fill: parent
                anchors.margins: 16

                Text {
                    text: "WiFi"
                    font.pixelSize: 18
                    color: "#ffffff"
                    Layout.fillWidth: true
                }

                Switch {
                    id: wifiSwitch
                    checked: true

                    indicator: Rectangle {
                        implicitWidth: 50
                        implicitHeight: 28
                        radius: 14
                        color: wifiSwitch.checked ? "#e94560" : "#333344"

                        Rectangle {
                            x: wifiSwitch.checked ? parent.width - width - 4 : 4
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

        // Networks section
        Text {
            text: "Available Networks"
            font.pixelSize: 14
            color: "#666677"
            Layout.topMargin: 10
        }

        // Network list
        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 2

            model: ListModel {
                ListElement { name: "Home WiFi"; signal: 4; secured: true; connected: true }
                ListElement { name: "Neighbor's Network"; signal: 3; secured: true; connected: false }
                ListElement { name: "Coffee Shop"; signal: 2; secured: false; connected: false }
                ListElement { name: "Guest Network"; signal: 1; secured: true; connected: false }
            }

            delegate: Rectangle {
                width: parent.width
                height: 60
                color: mouseArea.pressed ? "#1a1a2e" : "#12121a"
                radius: index === 0 ? 10 : (index === 3 ? 10 : 0)

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 12

                    // Signal strength
                    Text {
                        text: {
                            var bars = model.signal
                            return bars >= 4 ? "📶" : bars >= 3 ? "📶" : bars >= 2 ? "📶" : "📶"
                        }
                        font.pixelSize: 20
                        opacity: model.signal / 4
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
                            text: model.connected ? "Connected" : (model.secured ? "Secured" : "Open")
                            font.pixelSize: 12
                            color: model.connected ? "#4ade80" : "#666677"
                        }
                    }

                    Text {
                        text: model.secured ? "🔒" : ""
                        font.pixelSize: 16
                    }
                }

                MouseArea {
                    id: mouseArea
                    anchors.fill: parent
                    onClicked: console.log("Connect to: " + model.name)
                }
            }
        }
    }
}
