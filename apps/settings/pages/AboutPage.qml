import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Page {
    id: aboutPage

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
            text: "About"
            font.pixelSize: 38
            font.weight: Font.Light
            font.letterSpacing: 4
            color: "#ffffff"
        }
    }

    Flickable {
        anchors.fill: parent
        anchors.bottomMargin: 100
        contentHeight: content.height + 60
        clip: true

        ColumnLayout {
            id: content
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 16
            spacing: 20

            // Logo and branding
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 200
                Layout.topMargin: 20

                Column {
                    anchors.centerIn: parent
                    spacing: 16

                    // App icon with glow
                    Item {
                        width: 100
                        height: 100
                        anchors.horizontalCenter: parent.horizontalCenter

                        // Glow effect
                        Rectangle {
                            anchors.centerIn: parent
                            width: 120
                            height: 120
                            radius: 60
                            color: "#e94560"
                            opacity: 0.15

                            NumberAnimation on opacity {
                                from: 0.1
                                to: 0.2
                                duration: 2000
                                loops: Animation.Infinite
                                easing.type: Easing.InOutSine
                            }
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: 24
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: "#e94560" }
                                GradientStop { position: 1.0; color: "#c23a50" }
                            }

                            Text {
                                anchors.centerIn: parent
                                text: "⚡"
                                font.pixelSize: 48
                            }
                        }
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Flick"
                        font.pixelSize: 42
                        font.weight: Font.Medium
                        font.letterSpacing: 2
                        color: "#ffffff"
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Mobile Shell for Linux"
                        font.pixelSize: 18
                        font.weight: Font.Light
                        font.letterSpacing: 1
                        color: "#888899"
                    }
                }
            }

            // Version info card
            Rectangle {
                Layout.fillWidth: true
                height: infoColumn.height + 32
                radius: 16
                color: "#14141e"
                border.color: "#1a1a2e"
                border.width: 1

                Column {
                    id: infoColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 16
                    spacing: 0

                    Repeater {
                        model: ListModel {
                            ListElement { label: "Version"; value: "0.1.0" }
                            ListElement { label: "Build"; value: "2024.12.20" }
                            ListElement { label: "Compositor"; value: "Smithay" }
                            ListElement { label: "UI Framework"; value: "Slint + Qt5" }
                            ListElement { label: "License"; value: "GPL-3.0" }
                        }

                        Item {
                            width: infoColumn.width
                            height: 52

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8

                                Text {
                                    text: model.label
                                    font.pixelSize: 16
                                    color: "#666677"
                                    Layout.fillWidth: true
                                }

                                Text {
                                    text: model.value
                                    font.pixelSize: 16
                                    font.weight: Font.Medium
                                    color: "#ffffff"
                                }
                            }

                            Rectangle {
                                anchors.bottom: parent.bottom
                                anchors.left: parent.left
                                anchors.right: parent.right
                                height: 1
                                color: "#1a1a2e"
                                visible: index < 4
                            }
                        }
                    }
                }
            }

            // Credits section
            Rectangle {
                Layout.fillWidth: true
                height: creditsColumn.height + 32
                radius: 16
                color: "#14141e"
                border.color: "#1a1a2e"
                border.width: 1

                Column {
                    id: creditsColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 16
                    spacing: 16

                    Text {
                        text: "CREDITS"
                        font.pixelSize: 14
                        font.weight: Font.Medium
                        font.letterSpacing: 2
                        color: "#666677"
                    }

                    Text {
                        text: "Created by David Hamner"
                        font.pixelSize: 18
                        color: "#ffffff"
                    }

                    // GitHub link
                    Rectangle {
                        width: parent.width
                        height: 50
                        radius: 12
                        color: githubMouse.pressed ? "#2a2a3e" : "#1a1a28"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 16
                            anchors.rightMargin: 16

                            Text {
                                text: "🔗"
                                font.pixelSize: 18
                            }

                            Text {
                                text: "github.com/ruapotato/Flick"
                                font.pixelSize: 16
                                color: "#e94560"
                                Layout.fillWidth: true
                            }

                            Text {
                                text: "→"
                                font.pixelSize: 20
                                color: "#444455"
                            }
                        }

                        MouseArea {
                            id: githubMouse
                            anchors.fill: parent
                            onClicked: Qt.openUrlExternally("https://github.com/ruapotato/Flick")
                        }
                    }
                }
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
