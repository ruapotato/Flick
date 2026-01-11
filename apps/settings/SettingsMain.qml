import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../shared"

Page {
    id: settingsMain

    signal pageRequested(var page)

    background: Rectangle {
        color: "#0a0a0f"
    }

    // Large hero header with ambient glow
    Rectangle {
        id: headerArea
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 220
        color: "transparent"

        // Ambient glow effect
        Rectangle {
            anchors.centerIn: parent
            width: 300
            height: 200
            radius: 150
            color: Theme.accentColor
            opacity: 0.08

            NumberAnimation on opacity {
                from: 0.05
                to: 0.12
                duration: 3000
                loops: Animation.Infinite
                easing.type: Easing.InOutSine
            }
        }

        Column {
            anchors.centerIn: parent
            spacing: 12

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Settings"
                font.pixelSize: 22
                font.weight: Font.ExtraLight
                font.letterSpacing: 8
                color: "#ffffff"
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "FLICK PHOSH"
                font.pixelSize: 14
                font.weight: Font.Medium
                font.letterSpacing: 4
                color: "#555566"
            }
        }

        // Bottom fade line
        Rectangle {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 0.2; color: Theme.accentColor }
                GradientStop { position: 0.8; color: Theme.accentColor }
                GradientStop { position: 1.0; color: "transparent" }
            }
            opacity: 0.3
        }
    }

    // Settings grid - scrollable tiles
    GridView {
        id: settingsGrid
        anchors.top: headerArea.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 16
        anchors.bottomMargin: 100

        cellWidth: width / 2
        cellHeight: 140
        clip: true
        interactive: true
        flickableDirection: Flickable.VerticalFlick

        model: ListModel {
            ListElement {
                title: "Effects"
                icon: "✨"
                gradStart: "#4a1a4a"
                gradEnd: "#250d25"
                pageName: "EffectsPage"
            }
            ListElement {
                title: "Apps"
                icon: "📱"
                gradStart: "#1a4a2a"
                gradEnd: "#0d2515"
                pageName: "IconManagerPage"
            }
        }

        delegate: Item {
            width: settingsGrid.cellWidth
            height: settingsGrid.cellHeight

            Rectangle {
                id: tile
                anchors.fill: parent
                anchors.margins: 8
                radius: 24

                gradient: Gradient {
                    GradientStop { position: 0.0; color: model.gradStart }
                    GradientStop { position: 1.0; color: model.gradEnd }
                }

                // Subtle border
                Rectangle {
                    anchors.fill: parent
                    radius: 24
                    color: "transparent"
                    border.color: "#ffffff"
                    border.width: 1
                    opacity: tileMouse.pressed ? 0.2 : 0.05
                }

                // Inner glow on press
                Rectangle {
                    anchors.fill: parent
                    radius: 24
                    color: "#ffffff"
                    opacity: tileMouse.pressed ? 0.1 : 0
                    Behavior on opacity { NumberAnimation { duration: 100 } }
                }

                Column {
                    anchors.centerIn: parent
                    spacing: 16

                    // Large icon
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: model.icon
                        font.pixelSize: 38
                        opacity: 0.9
                    }

                    // Title
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: model.title
                        font.pixelSize: 22
                        font.weight: Font.Medium
                        font.letterSpacing: 2
                        color: "#ffffff"
                    }
                }

                // Entrance animation
                opacity: 0
                scale: 0.9
                Component.onCompleted: entranceAnim.start()

                ParallelAnimation {
                    id: entranceAnim
                    PauseAnimation { duration: index * 60 }
                    NumberAnimation {
                        target: tile
                        property: "opacity"
                        to: 1
                        duration: 300
                        easing.type: Easing.OutCubic
                    }
                    NumberAnimation {
                        target: tile
                        property: "scale"
                        to: 1
                        duration: 300
                        easing.type: Easing.OutBack
                        easing.overshoot: 1.2
                    }
                }

                MouseArea {
                    id: tileMouse
                    anchors.fill: parent
                    onClicked: {
                        var component = Qt.createComponent("pages/" + model.pageName + ".qml")
                        if (component.status === Component.Ready) {
                            settingsMain.pageRequested(component)
                        }
                    }
                }
            }
        }
    }

    // Back button - prominent floating action button
    Rectangle {
        id: backButton
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 24
        anchors.bottomMargin: 120
        width: 48
        height: 48
        radius: 36
        color: backButtonMouse.pressed ? Qt.darker(Theme.accentColor, 1.2) : Theme.accentColor

        Behavior on color { ColorAnimation { duration: 150 } }

        Text {
            anchors.centerIn: parent
            text: "←"
            font.pixelSize: 22
            font.weight: Font.Medium
            color: "#ffffff"
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
        width: 120
        height: 4
        radius: 2
        color: "#333344"
    }
}
