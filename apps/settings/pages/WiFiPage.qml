import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Page {
    id: wifiPage

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
            text: "WiFi"
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

            // WiFi toggle card
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
                        color: wifiSwitch.checked ? "#1a3a5c" : "#1a1a28"

                        Text {
                            anchors.centerIn: parent
                            text: "📶"
                            font.pixelSize: 24
                        }
                    }

                    Text {
                        text: "WiFi"
                        font.pixelSize: 22
                        font.weight: Font.Medium
                        color: "#ffffff"
                        Layout.fillWidth: true
                        Layout.leftMargin: 16
                    }

                    Switch {
                        id: wifiSwitch
                        checked: true

                        indicator: Rectangle {
                            implicitWidth: 64
                            implicitHeight: 36
                            radius: 18
                            color: wifiSwitch.checked ? "#e94560" : "#333344"

                            Behavior on color { ColorAnimation { duration: 150 } }

                            Rectangle {
                                x: wifiSwitch.checked ? parent.width - width - 4 : 4
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

            // Current network section
            Text {
                text: "CONNECTED"
                font.pixelSize: 14
                font.weight: Font.Medium
                font.letterSpacing: 2
                color: "#4ade80"
                Layout.leftMargin: 8
                Layout.topMargin: 20
                visible: wifiSwitch.checked
            }

            Rectangle {
                Layout.fillWidth: true
                height: 90
                radius: 16
                color: "#14141e"
                border.color: "#4ade80"
                border.width: 1
                visible: wifiSwitch.checked

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 20
                    anchors.rightMargin: 20
                    spacing: 16

                    Rectangle {
                        Layout.preferredWidth: 52
                        Layout.preferredHeight: 52
                        radius: 12
                        color: "#1a3a5c"

                        Text {
                            anchors.centerIn: parent
                            text: "📶"
                            font.pixelSize: 24
                        }
                    }

                    Column {
                        Layout.fillWidth: true
                        spacing: 4

                        Text {
                            text: "Home WiFi"
                            font.pixelSize: 20
                            font.weight: Font.Medium
                            color: "#ffffff"
                        }
                        Text {
                            text: "Connected • Excellent signal"
                            font.pixelSize: 14
                            color: "#4ade80"
                        }
                    }

                    Text {
                        text: "🔒"
                        font.pixelSize: 18
                    }
                }
            }

            // Available networks section
            Text {
                text: "AVAILABLE NETWORKS"
                font.pixelSize: 14
                font.weight: Font.Medium
                font.letterSpacing: 2
                color: "#666677"
                Layout.leftMargin: 8
                Layout.topMargin: 20
                visible: wifiSwitch.checked
            }

            // Network list
            Repeater {
                model: wifiSwitch.checked ? networkModel : []

                Rectangle {
                    Layout.fillWidth: true
                    height: 80
                    radius: 16
                    color: networkMouse.pressed ? "#1e1e2e" : "#14141e"
                    border.color: "#1a1a2e"
                    border.width: 1

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
                            color: "#1a1a28"

                            Text {
                                anchors.centerIn: parent
                                text: "📶"
                                font.pixelSize: 20
                                opacity: model.signal / 4
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
                                text: model.secured ? "Secured" : "Open"
                                font.pixelSize: 13
                                color: "#666677"
                            }
                        }

                        Text {
                            text: model.secured ? "🔒" : ""
                            font.pixelSize: 16
                            visible: model.secured
                        }
                    }

                    MouseArea {
                        id: networkMouse
                        anchors.fill: parent
                        onClicked: console.log("Connect to: " + model.name)
                    }
                }
            }

            ListModel {
                id: networkModel
                ListElement { name: "Neighbor's Network"; signal: 3; secured: true }
                ListElement { name: "Coffee Shop"; signal: 2; secured: false }
                ListElement { name: "Guest Network"; signal: 2; secured: true }
                ListElement { name: "NETGEAR-5G"; signal: 1; secured: true }
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
