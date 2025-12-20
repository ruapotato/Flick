import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Page {
    id: displayPage

    property real brightness: 0.75

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
            text: "Display"
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
            spacing: 16

            // Brightness section
            Text {
                text: "BRIGHTNESS"
                font.pixelSize: 14
                font.weight: Font.Medium
                font.letterSpacing: 2
                color: "#666677"
                Layout.leftMargin: 8
                Layout.topMargin: 16
            }

            Rectangle {
                Layout.fillWidth: true
                height: 120
                radius: 16
                color: "#14141e"
                border.color: "#1a1a2e"
                border.width: 1

                Column {
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 16

                    RowLayout {
                        width: parent.width

                        Text {
                            text: "Screen Brightness"
                            font.pixelSize: 18
                            color: "#ffffff"
                            Layout.fillWidth: true
                        }

                        Text {
                            text: Math.round(brightness * 100) + "%"
                            font.pixelSize: 16
                            color: "#e94560"
                        }
                    }

                    // Custom slider
                    Item {
                        width: parent.width
                        height: 40

                        RowLayout {
                            anchors.fill: parent
                            spacing: 16

                            Text {
                                text: "🔅"
                                font.pixelSize: 20
                            }

                            // Slider track
                            Item {
                                Layout.fillWidth: true
                                height: 40

                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    height: 8
                                    radius: 4
                                    color: "#2a2a3e"

                                    Rectangle {
                                        width: parent.width * brightness
                                        height: parent.height
                                        radius: 4
                                        gradient: Gradient {
                                            orientation: Gradient.Horizontal
                                            GradientStop { position: 0.0; color: "#e94560" }
                                            GradientStop { position: 1.0; color: "#ff6b8a" }
                                        }
                                    }
                                }

                                // Handle
                                Rectangle {
                                    x: (parent.width - 32) * brightness
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 32
                                    height: 32
                                    radius: 16
                                    color: "#ffffff"

                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: 12
                                        height: 12
                                        radius: 6
                                        color: "#e94560"
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onPressed: updateBrightness(mouse)
                                    onPositionChanged: if (pressed) updateBrightness(mouse)

                                    function updateBrightness(mouse) {
                                        brightness = Math.max(0.05, Math.min(1, mouse.x / parent.width))
                                    }
                                }
                            }

                            Text {
                                text: "🔆"
                                font.pixelSize: 20
                            }
                        }
                    }
                }
            }

            // Auto brightness toggle
            Rectangle {
                Layout.fillWidth: true
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
                        color: autoBrightnessSwitch.checked ? "#3c3a2a" : "#1a1a28"

                        Text {
                            anchors.centerIn: parent
                            text: "✨"
                            font.pixelSize: 24
                        }
                    }

                    Column {
                        Layout.fillWidth: true
                        Layout.leftMargin: 16
                        spacing: 4

                        Text {
                            text: "Auto Brightness"
                            font.pixelSize: 18
                            color: "#ffffff"
                        }
                        Text {
                            text: "Adjust based on ambient light"
                            font.pixelSize: 13
                            color: "#666677"
                        }
                    }

                    Switch {
                        id: autoBrightnessSwitch
                        checked: false

                        indicator: Rectangle {
                            implicitWidth: 64
                            implicitHeight: 36
                            radius: 18
                            color: autoBrightnessSwitch.checked ? "#e94560" : "#333344"

                            Behavior on color { ColorAnimation { duration: 150 } }

                            Rectangle {
                                x: autoBrightnessSwitch.checked ? parent.width - width - 4 : 4
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

            // Screen timeout section
            Text {
                text: "SCREEN TIMEOUT"
                font.pixelSize: 14
                font.weight: Font.Medium
                font.letterSpacing: 2
                color: "#666677"
                Layout.leftMargin: 8
                Layout.topMargin: 20
            }

            Repeater {
                model: ListModel {
                    ListElement { label: "15 seconds"; value: 15; selected: false }
                    ListElement { label: "30 seconds"; value: 30; selected: true }
                    ListElement { label: "1 minute"; value: 60; selected: false }
                    ListElement { label: "2 minutes"; value: 120; selected: false }
                    ListElement { label: "Never"; value: 0; selected: false }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 60
                    radius: 16
                    color: timeoutMouse.pressed ? "#1e1e2e" : "#14141e"
                    border.color: model.selected ? "#e94560" : "#1a1a2e"
                    border.width: model.selected ? 2 : 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 20
                        anchors.rightMargin: 20

                        Text {
                            text: model.label
                            font.pixelSize: 18
                            color: "#ffffff"
                            Layout.fillWidth: true
                        }

                        Rectangle {
                            Layout.preferredWidth: 24
                            Layout.preferredHeight: 24
                            radius: 12
                            color: "transparent"
                            border.color: model.selected ? "#e94560" : "#3a3a4e"
                            border.width: 2

                            Rectangle {
                                anchors.centerIn: parent
                                width: model.selected ? 12 : 0
                                height: width
                                radius: width / 2
                                color: "#e94560"

                                Behavior on width {
                                    NumberAnimation { duration: 150; easing.type: Easing.OutBack }
                                }
                            }
                        }
                    }

                    MouseArea {
                        id: timeoutMouse
                        anchors.fill: parent
                        onClicked: {
                            // Update selection
                            for (var i = 0; i < 5; i++) {
                                timeoutModel.setProperty(i, "selected", i === index)
                            }
                        }
                    }
                }
            }

            Item { height: 40 }
        }

        // Need to define model separately for property modification
        ListModel {
            id: timeoutModel
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
