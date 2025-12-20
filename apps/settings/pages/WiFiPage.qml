import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Page {
    id: wifiPage

    background: Rectangle {
        color: "#0a0a0f"
    }

    header: Rectangle {
        height: 100
        color: "#12121a"

        Text {
            anchors.centerIn: parent
            text: "WiFi"
            font.pixelSize: 36
            font.weight: Font.Light
            color: "#ffffff"
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        anchors.bottomMargin: 100  // Space for back button
        spacing: 24

        // WiFi toggle
        Rectangle {
            Layout.fillWidth: true
            height: 80
            color: "#12121a"
            radius: 12

            RowLayout {
                anchors.fill: parent
                anchors.margins: 20

                Text {
                    text: "WiFi"
                    font.pixelSize: 24
                    color: "#ffffff"
                    Layout.fillWidth: true
                }

                Switch {
                    id: wifiSwitch
                    checked: true

                    indicator: Rectangle {
                        implicitWidth: 60
                        implicitHeight: 34
                        radius: 17
                        color: wifiSwitch.checked ? "#e94560" : "#333344"

                        Rectangle {
                            x: wifiSwitch.checked ? parent.width - width - 4 : 4
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

        // Networks section
        Text {
            text: "Available Networks"
            font.pixelSize: 18
            color: "#666677"
            Layout.topMargin: 12
        }

        // Network list
        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 4

            model: ListModel {
                ListElement { name: "Home WiFi"; signal: 4; secured: true; connected: true }
                ListElement { name: "Neighbor's Network"; signal: 3; secured: true; connected: false }
                ListElement { name: "Coffee Shop"; signal: 2; secured: false; connected: false }
                ListElement { name: "Guest Network"; signal: 1; secured: true; connected: false }
            }

            delegate: Rectangle {
                width: parent.width
                height: 80
                color: mouseArea.pressed ? "#1a1a2e" : "#12121a"
                radius: index === 0 ? 12 : (index === 3 ? 12 : 0)

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 16

                    // Signal strength
                    Text {
                        text: {
                            var bars = model.signal
                            return bars >= 4 ? "📶" : bars >= 3 ? "📶" : bars >= 2 ? "📶" : "📶"
                        }
                        font.pixelSize: 28
                        opacity: model.signal / 4
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
                            text: model.connected ? "Connected" : (model.secured ? "Secured" : "Open")
                            font.pixelSize: 16
                            color: model.connected ? "#4ade80" : "#666677"
                        }
                    }

                    Text {
                        text: model.secured ? "🔒" : ""
                        font.pixelSize: 22
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
