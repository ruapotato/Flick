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
        height: 80
        color: "#12121a"

        Text {
            anchors.centerIn: parent
            text: "Settings"
            font.pixelSize: 28
            font.weight: Font.Light
            color: "#ffffff"
        }
    }

    // Settings list
    ListView {
        id: settingsList
        anchors.fill: parent
        anchors.topMargin: 20

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
            height: 80
            color: mouseArea.pressed ? "#1a1a2e" : "transparent"

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 20
                anchors.rightMargin: 20
                spacing: 16

                // Icon
                Text {
                    text: model.icon
                    font.pixelSize: 28
                    Layout.preferredWidth: 40
                }

                // Text
                Column {
                    Layout.fillWidth: true
                    spacing: 4

                    Text {
                        text: model.title
                        font.pixelSize: 18
                        font.weight: Font.Medium
                        color: "#ffffff"
                    }
                    Text {
                        text: model.subtitle
                        font.pixelSize: 14
                        color: "#666677"
                    }
                }

                // Arrow
                Text {
                    text: "›"
                    font.pixelSize: 24
                    color: "#444455"
                }
            }

            // Separator
            Rectangle {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 76
                height: 1
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
}
