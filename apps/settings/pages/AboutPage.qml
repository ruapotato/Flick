import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Page {
    id: aboutPage

    background: Rectangle {
        color: "#0a0a0f"
    }

    // Hero section with animated logo
    Rectangle {
        id: heroSection
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 340
        color: "transparent"

        // Animated background particles
        Repeater {
            model: 20
            Rectangle {
                property real startX: Math.random() * heroSection.width
                property real startY: Math.random() * heroSection.height

                x: startX
                y: startY
                width: 2 + Math.random() * 4
                height: width
                radius: width / 2
                color: "#e94560"
                opacity: 0.1 + Math.random() * 0.2

                SequentialAnimation on y {
                    loops: Animation.Infinite
                    NumberAnimation {
                        to: startY - 50 - Math.random() * 100
                        duration: 3000 + Math.random() * 4000
                        easing.type: Easing.InOutSine
                    }
                    NumberAnimation {
                        to: startY
                        duration: 3000 + Math.random() * 4000
                        easing.type: Easing.InOutSine
                    }
                }

                SequentialAnimation on opacity {
                    loops: Animation.Infinite
                    NumberAnimation {
                        to: 0.3 + Math.random() * 0.3
                        duration: 2000 + Math.random() * 2000
                    }
                    NumberAnimation {
                        to: 0.1
                        duration: 2000 + Math.random() * 2000
                    }
                }
            }
        }

        Column {
            anchors.centerIn: parent
            spacing: 20

            // Large logo with pulsing glow
            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 140
                height: 140

                // Outer glow ring
                Rectangle {
                    anchors.centerIn: parent
                    width: 180
                    height: 180
                    radius: 90
                    color: "transparent"
                    border.color: "#e94560"
                    border.width: 2
                    opacity: 0

                    SequentialAnimation on opacity {
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.4; duration: 1500 }
                        NumberAnimation { to: 0; duration: 1500 }
                    }

                    SequentialAnimation on scale {
                        loops: Animation.Infinite
                        NumberAnimation { from: 0.8; to: 1.2; duration: 3000 }
                    }
                }

                // Second glow ring
                Rectangle {
                    anchors.centerIn: parent
                    width: 160
                    height: 160
                    radius: 80
                    color: "transparent"
                    border.color: "#e94560"
                    border.width: 1
                    opacity: 0.2
                }

                // Main logo
                Rectangle {
                    anchors.centerIn: parent
                    width: 120
                    height: 120
                    radius: 30

                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "#e94560" }
                        GradientStop { position: 1.0; color: "#c23a50" }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: "⚡"
                        font.pixelSize: 60
                    }
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Flick"
                font.pixelSize: 56
                font.weight: Font.ExtraLight
                font.letterSpacing: 8
                color: "#ffffff"
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "MOBILE SHELL FOR LINUX"
                font.pixelSize: 13
                font.letterSpacing: 3
                color: "#555566"
            }
        }
    }

    // Info section
    Flickable {
        anchors.top: heroSection.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 16
        anchors.bottomMargin: 100
        contentHeight: infoColumn.height
        clip: true

        Column {
            id: infoColumn
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 16

            // System info card
            Rectangle {
                width: infoColumn.width
                height: infoListColumn.height + 32
                radius: 24
                color: "#14141e"
                border.color: "#1a1a2e"
                border.width: 1

                Column {
                    id: infoListColumn
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
                            width: infoListColumn.width
                            height: 56

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8

                                Text {
                                    text: model.label
                                    font.pixelSize: 17
                                    color: "#666677"
                                    Layout.fillWidth: true
                                }

                                Text {
                                    text: model.value
                                    font.pixelSize: 17
                                    font.weight: Font.Medium
                                    color: "#ffffff"
                                }
                            }

                            Rectangle {
                                anchors.bottom: parent.bottom
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                height: 1
                                color: "#1a1a2e"
                                visible: index < 4
                            }
                        }
                    }
                }
            }

            // Creator card
            Rectangle {
                width: infoColumn.width
                height: 160
                radius: 24
                color: "#14141e"
                border.color: "#1a1a2e"
                border.width: 1

                Column {
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 16

                    Text {
                        text: "CREATED BY"
                        font.pixelSize: 12
                        font.letterSpacing: 2
                        color: "#555566"
                    }

                    Text {
                        text: "David Hamner"
                        font.pixelSize: 26
                        font.weight: Font.Medium
                        color: "#ffffff"
                    }

                    // GitHub link
                    Rectangle {
                        width: parent.width
                        height: 56
                        radius: 16
                        color: githubMouse.pressed ? "#2a2a3e" : "#1a1a28"

                        Behavior on color { ColorAnimation { duration: 100 } }

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 16
                            spacing: 12

                            Text {
                                text: "🔗"
                                font.pixelSize: 20
                            }

                            Text {
                                text: "github.com/ruapotato/Flick"
                                font.pixelSize: 16
                                color: "#e94560"
                                Layout.fillWidth: true
                            }

                            Text {
                                text: "→"
                                font.pixelSize: 24
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

            Item { height: 20 }
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
        color: backMouse.pressed ? "#e94560" : "#1a1a28"
        border.color: "#2a2a3e"
        border.width: 2

        Behavior on color { ColorAnimation { duration: 150 } }

        Text {
            anchors.centerIn: parent
            text: "←"
            font.pixelSize: 32
            font.weight: Font.Light
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
