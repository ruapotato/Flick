import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Page {
    id: wifiPage

    property bool wifiEnabled: true

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
            color: wifiEnabled ? "#1a3a5c" : "#1a1a28"
            opacity: wifiEnabled ? 0.3 : 0.1

            Behavior on color { ColorAnimation { duration: 300 } }
            Behavior on opacity { NumberAnimation { duration: 300 } }
        }

        Column {
            anchors.centerIn: parent
            spacing: 24

            // Large WiFi icon as toggle
            Rectangle {
                id: wifiToggle
                anchors.horizontalCenter: parent.horizontalCenter
                width: 120
                height: 120
                radius: 60
                color: wifiEnabled ? "#1a3a5c" : "#1a1a28"
                border.color: wifiEnabled ? "#4a8abf" : "#2a2a3e"
                border.width: 3

                Behavior on color { ColorAnimation { duration: 200 } }
                Behavior on border.color { ColorAnimation { duration: 200 } }

                Text {
                    anchors.centerIn: parent
                    text: "📶"
                    font.pixelSize: 52
                    opacity: wifiEnabled ? 1 : 0.4

                    Behavior on opacity { NumberAnimation { duration: 200 } }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: wifiEnabled = !wifiEnabled
                }

                // Pulse animation when enabled
                Rectangle {
                    anchors.fill: parent
                    radius: 60
                    color: "transparent"
                    border.color: "#4a8abf"
                    border.width: 2
                    opacity: 0
                    scale: 1

                    SequentialAnimation on opacity {
                        running: wifiEnabled
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.5; duration: 1000 }
                        NumberAnimation { to: 0; duration: 1000 }
                    }

                    SequentialAnimation on scale {
                        running: wifiEnabled
                        loops: Animation.Infinite
                        NumberAnimation { to: 1.3; duration: 2000 }
                        NumberAnimation { to: 1; duration: 0 }
                    }
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "WiFi"
                font.pixelSize: 42
                font.weight: Font.ExtraLight
                font.letterSpacing: 6
                color: "#ffffff"
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: wifiEnabled ? "TAP TO DISABLE" : "TAP TO ENABLE"
                font.pixelSize: 12
                font.letterSpacing: 2
                color: "#555566"
            }
        }
    }

    // Connected network - large hero card
    Rectangle {
        id: connectedCard
        anchors.top: heroSection.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 16
        height: 140
        radius: 24
        visible: wifiEnabled
        opacity: wifiEnabled ? 1 : 0

        gradient: Gradient {
            GradientStop { position: 0.0; color: "#1a4a3a" }
            GradientStop { position: 1.0; color: "#0d251d" }
        }

        Behavior on opacity { NumberAnimation { duration: 300 } }

        // Border glow
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
            anchors.margins: 24
            spacing: 20

            Column {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "CONNECTED"
                    font.pixelSize: 12
                    font.letterSpacing: 2
                    color: "#4ade80"
                }

                Text {
                    text: "Home WiFi"
                    font.pixelSize: 28
                    font.weight: Font.Medium
                    color: "#ffffff"
                }

                Text {
                    text: "Excellent signal  •  192.168.1.42"
                    font.pixelSize: 14
                    color: "#88aa99"
                }
            }

            // Signal strength indicator
            Row {
                spacing: 4

                Repeater {
                    model: 4
                    Rectangle {
                        width: 8
                        height: 12 + index * 10
                        radius: 4
                        color: "#4ade80"
                        anchors.bottom: parent.bottom
                    }
                }
            }
        }
    }

    // Available networks
    Flickable {
        id: networkList
        anchors.top: connectedCard.visible ? connectedCard.bottom : heroSection.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 16
        anchors.topMargin: 24
        anchors.bottomMargin: 100
        contentHeight: networksColumn.height
        clip: true
        visible: wifiEnabled

        Column {
            id: networksColumn
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 12

            Text {
                text: "AVAILABLE NETWORKS"
                font.pixelSize: 12
                font.letterSpacing: 2
                color: "#555566"
                leftPadding: 8
            }

            Repeater {
                model: ListModel {
                    ListElement { name: "Neighbor's Network"; signal: 3; secured: true }
                    ListElement { name: "Coffee Shop"; signal: 2; secured: false }
                    ListElement { name: "Guest Network"; signal: 2; secured: true }
                    ListElement { name: "NETGEAR-5G"; signal: 1; secured: true }
                }

                Rectangle {
                    width: networksColumn.width
                    height: 90
                    radius: 20
                    color: networkMouse.pressed ? "#1e1e2e" : "#14141e"
                    border.color: "#1a1a2e"
                    border.width: 1

                    Behavior on color { ColorAnimation { duration: 100 } }

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 20
                        spacing: 16

                        // Signal indicator
                        Column {
                            Layout.preferredWidth: 40
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 2

                            Row {
                                anchors.horizontalCenter: parent.horizontalCenter
                                spacing: 3

                                Repeater {
                                    model: 4
                                    Rectangle {
                                        width: 6
                                        height: 6 + index * 6
                                        radius: 3
                                        color: index < model.signal ? "#e94560" : "#2a2a3e"
                                        anchors.bottom: parent.bottom
                                    }
                                }
                            }
                        }

                        Column {
                            Layout.fillWidth: true
                            spacing: 6

                            Text {
                                text: model.name
                                font.pixelSize: 20
                                color: "#ffffff"
                            }

                            Text {
                                text: model.secured ? "WPA2 Secured" : "Open Network"
                                font.pixelSize: 13
                                color: model.secured ? "#666677" : "#cc8844"
                            }
                        }

                        Text {
                            text: model.secured ? "🔒" : "⚠"
                            font.pixelSize: 20
                            opacity: 0.7
                        }
                    }

                    MouseArea {
                        id: networkMouse
                        anchors.fill: parent
                        onClicked: console.log("Connect to: " + model.name)
                    }
                }
            }
        }
    }

    // Disabled state overlay
    Rectangle {
        anchors.top: heroSection.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 100
        color: "transparent"
        visible: !wifiEnabled

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
                text: "WiFi is disabled"
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
