import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Page {
    id: settingsMain

    signal pageRequested(var page)

    background: Rectangle {
        color: "#0a0a0f"
    }

    // Header
    header: Rectangle {
        height: 140
        color: "#12121a"

        Text {
            anchors.centerIn: parent
            text: "Settings"
            font.pixelSize: 48
            font.weight: Font.Light
            color: "#ffffff"
        }
    }

    // Settings list
    ListView {
        id: settingsList
        anchors.fill: parent
        anchors.topMargin: 24
        anchors.bottomMargin: 80  // Leave space for back button

        model: ListModel {
            ListElement {
                title: "WiFi"
                subtitle: "Manage wireless networks"
                icon: "📶"
                pageName: "WiFiPage"
            }
            ListElement {
                title: "Bluetooth"
                subtitle: "Pair and manage devices"
                icon: "🔵"
                pageName: "BluetoothPage"
            }
            ListElement {
                title: "Display"
                subtitle: "Brightness and screen settings"
                icon: "🔆"
                pageName: "DisplayPage"
            }
            ListElement {
                title: "Sound"
                subtitle: "Volume and notifications"
                icon: "🔊"
                pageName: "SoundPage"
            }
            ListElement {
                title: "About"
                subtitle: "Device information"
                icon: "ℹ️"
                pageName: "AboutPage"
            }
        }

        delegate: Rectangle {
            width: settingsList.width
            height: 160
            color: mouseArea.pressed ? "#1a1a2e" : "transparent"

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 32
                anchors.rightMargin: 32
                spacing: 28

                // Icon
                Text {
                    text: model.icon
                    font.pixelSize: 56
                    Layout.preferredWidth: 70
                }

                // Text
                Column {
                    Layout.fillWidth: true
                    spacing: 10

                    Text {
                        text: model.title
                        font.pixelSize: 32
                        font.weight: Font.Medium
                        color: "#ffffff"
                    }
                    Text {
                        text: model.subtitle
                        font.pixelSize: 22
                        color: "#666677"
                    }
                }

                // Arrow
                Text {
                    text: "›"
                    font.pixelSize: 48
                    color: "#444455"
                }
            }

            // Separator
            Rectangle {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 130
                height: 2
                color: "#1a1a2e"
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

    // Back button - bottom right (Flick design spec for 1st party apps)
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
            onClicked: {
                Qt.quit()
            }
        }
    }
}
