import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Page {
    id: settingsMain

    signal pageRequested(var page)

    background: Rectangle {
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#0a0a0f" }
            GradientStop { position: 1.0; color: "#0f0f18" }
        }
    }

    // Elegant header with subtle styling
    header: Rectangle {
        height: 120
        color: "transparent"

        // Subtle bottom accent line
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
            text: "Settings"
            font.pixelSize: 38
            font.weight: Font.Light
            font.letterSpacing: 4
            color: "#ffffff"
        }
    }

    // Settings list with elegant cards
    ListView {
        id: settingsList
        anchors.fill: parent
        anchors.topMargin: 20
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        anchors.bottomMargin: 100
        spacing: 12
        clip: true

        model: ListModel {
            ListElement {
                title: "WiFi"
                subtitle: "Manage wireless networks"
                icon: "📶"
                iconBg: "#1a3a5c"
                pageName: "WiFiPage"
            }
            ListElement {
                title: "Bluetooth"
                subtitle: "Pair and manage devices"
                icon: "🔵"
                iconBg: "#2a2a5c"
                pageName: "BluetoothPage"
            }
            ListElement {
                title: "Display"
                subtitle: "Brightness and screen settings"
                icon: "🔆"
                iconBg: "#3c3a2a"
                pageName: "DisplayPage"
            }
            ListElement {
                title: "Sound"
                subtitle: "Volume and notifications"
                icon: "🔊"
                iconBg: "#2a3c3a"
                pageName: "SoundPage"
            }
            ListElement {
                title: "Security"
                subtitle: "Lock screen and passwords"
                icon: "🔒"
                iconBg: "#3c2a3a"
                pageName: "SecurityPage"
            }
            ListElement {
                title: "About"
                subtitle: "Device information"
                icon: "ℹ️"
                iconBg: "#2a2a3c"
                pageName: "AboutPage"
            }
        }

        delegate: Rectangle {
            id: settingsCard
            width: settingsList.width
            height: 100
            radius: 16
            color: mouseArea.pressed ? "#1e1e2e" : "#14141e"
            border.color: mouseArea.pressed ? "#e94560" : "#1a1a2e"
            border.width: 1

            Behavior on color { ColorAnimation { duration: 100 } }
            Behavior on border.color { ColorAnimation { duration: 100 } }

            // Entrance animation
            opacity: 0
            Component.onCompleted: {
                entranceAnim.start()
            }

            SequentialAnimation {
                id: entranceAnim
                PauseAnimation { duration: index * 50 }
                NumberAnimation {
                    target: settingsCard
                    property: "opacity"
                    to: 1
                    duration: 200
                    easing.type: Easing.OutCubic
                }
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 20
                anchors.rightMargin: 20
                spacing: 20

                // Icon container with colored background
                Rectangle {
                    Layout.preferredWidth: 60
                    Layout.preferredHeight: 60
                    radius: 14
                    color: model.iconBg

                    Text {
                        anchors.centerIn: parent
                        text: model.icon
                        font.pixelSize: 28
                    }
                }

                // Text column
                Column {
                    Layout.fillWidth: true
                    spacing: 6

                    Text {
                        text: model.title
                        font.pixelSize: 24
                        font.weight: Font.Medium
                        color: "#ffffff"
                    }
                    Text {
                        text: model.subtitle
                        font.pixelSize: 16
                        color: "#666677"
                    }
                }

                // Chevron
                Text {
                    text: "›"
                    font.pixelSize: 32
                    font.weight: Font.Light
                    color: "#444455"
                }
            }

            MouseArea {
                id: mouseArea
                anchors.fill: parent
                onClicked: {
                    var component = Qt.createComponent("pages/" + model.pageName + ".qml")
                    if (component.status === Component.Ready) {
                        settingsMain.pageRequested(component)
                    } else {
                        console.log("Could not load page: " + model.pageName)
                    }
                }
            }
        }
    }

    // Elegant back button - bottom right
    Rectangle {
        id: backButton
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

        // Subtle inner glow
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
            onClicked: Qt.quit()
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
