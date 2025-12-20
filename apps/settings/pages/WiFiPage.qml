import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Page {
    id: wifiPage

    background: Rectangle {
        color: "#0a0a0f"
    }

    header: Rectangle {
        height: 140
        color: "#12121a"

        Text {
            anchors.centerIn: parent
            text: "WiFi"
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

        // WiFi toggle
        Rectangle {
            Layout.fillWidth: true
            height: 120
            color: "#12121a"
            radius: 16

            RowLayout {
                anchors.fill: parent
                anchors.margins: 28

                Text {
                    text: "WiFi"
                    font.pixelSize: 32
                    color: "#ffffff"
                    Layout.fillWidth: true
                }

                Switch {
                    id: wifiSwitch
                    checked: true

                    indicator: Rectangle {
                        implicitWidth: 80
                        implicitHeight: 44
                        radius: 22
                        color: wifiSwitch.checked ? "#e94560" : "#333344"

                        Rectangle {
                            x: wifiSwitch.checked ? parent.width - width - 4 : 4
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

        // Networks section
        Text {
            text: "Available Networks"
            font.pixelSize: 24
            color: "#666677"
            Layout.topMargin: 16
        }

        // Network list
        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 8

            model: ListModel {
                ListElement { name: "Home WiFi"; signal: 4; secured: true; connected: true }
                ListElement { name: "Neighbor's Network"; signal: 3; secured: true; connected: false }
                ListElement { name: "Coffee Shop"; signal: 2; secured: false; connected: false }
                ListElement { name: "Guest Network"; signal: 1; secured: true; connected: false }
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

                    // Signal strength
                    Text {
                        text: "📶"
                        font.pixelSize: 40
                        opacity: model.signal / 4
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
                            text: model.connected ? "Connected" : (model.secured ? "Secured" : "Open")
                            font.pixelSize: 20
                            color: model.connected ? "#4ade80" : "#666677"
                        }
                    }

                    Text {
                        text: model.secured ? "🔒" : ""
                        font.pixelSize: 28
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
