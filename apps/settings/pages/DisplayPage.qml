import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Page {
    id: displayPage

    background: Rectangle {
        color: "#0a0a0f"
    }

    header: Rectangle {
        height: 100
        color: "#12121a"

        Text {
            anchors.centerIn: parent
            text: "Display"
            font.pixelSize: 36
            font.weight: Font.Light
            color: "#ffffff"
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        anchors.bottomMargin: 100
        spacing: 24

        // Brightness section
        Rectangle {
            Layout.fillWidth: true
            height: 140
            color: "#12121a"
            radius: 12

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 20
                spacing: 20

                RowLayout {
                    Layout.fillWidth: true

                    Text {
                        text: "Brightness"
                        font.pixelSize: 24
                        color: "#ffffff"
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        text: Math.round(brightnessSlider.value) + "%"
                        font.pixelSize: 20
                        color: "#666677"
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 16

                    Text {
                        text: "🔅"
                        font.pixelSize: 28
                    }

                    Slider {
                        id: brightnessSlider
                        Layout.fillWidth: true
                        from: 5
                        to: 100
                        value: 75

                        background: Rectangle {
                            x: brightnessSlider.leftPadding
                            y: brightnessSlider.topPadding + brightnessSlider.availableHeight / 2 - height / 2
                            width: brightnessSlider.availableWidth
                            height: 8
                            radius: 4
                            color: "#333344"

                            Rectangle {
                                width: brightnessSlider.visualPosition * parent.width
                                height: parent.height
                                radius: 4
                                color: "#e94560"
                            }
                        }

                        handle: Rectangle {
                            x: brightnessSlider.leftPadding + brightnessSlider.visualPosition * (brightnessSlider.availableWidth - width)
                            y: brightnessSlider.topPadding + brightnessSlider.availableHeight / 2 - height / 2
                            width: 32
                            height: 32
                            radius: 16
                            color: "#ffffff"
                        }
                    }

                    Text {
                        text: "🔆"
                        font.pixelSize: 28
                    }
                }
            }
        }

        // Auto brightness
        Rectangle {
            Layout.fillWidth: true
            height: 80
            color: "#12121a"
            radius: 12

            RowLayout {
                anchors.fill: parent
                anchors.margins: 20

                Text {
                    text: "Auto Brightness"
                    font.pixelSize: 24
                    color: "#ffffff"
                    Layout.fillWidth: true
                }

                Switch {
                    id: autoBrightnessSwitch
                    checked: false

                    indicator: Rectangle {
                        implicitWidth: 60
                        implicitHeight: 34
                        radius: 17
                        color: autoBrightnessSwitch.checked ? "#e94560" : "#333344"

                        Rectangle {
                            x: autoBrightnessSwitch.checked ? parent.width - width - 4 : 4
                            anchors.verticalCenter: parent.verticalCenter
                            width: 26
                            height: 26
                            radius: 13
                            color: "#ffffff"

                            Behavior on x {
                                NumberAnimation { duration: 150 }
                            }
                        }
                    }
                }
            }
        }

        // Screen timeout
        Rectangle {
            Layout.fillWidth: true
            height: 80
            color: "#12121a"
            radius: 12

            RowLayout {
                anchors.fill: parent
                anchors.margins: 20

                Text {
                    text: "Screen Timeout"
                    font.pixelSize: 24
                    color: "#ffffff"
                    Layout.fillWidth: true
                }

                Text {
                    text: "30 seconds"
                    font.pixelSize: 20
                    color: "#666677"
                }

                Text {
                    text: "›"
                    font.pixelSize: 28
                    color: "#444455"
                }
            }
        }

        Item { Layout.fillHeight: true }
    }

    // Back button - bottom right (Flick design spec)
    Rectangle {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 24
        anchors.bottomMargin: 24
        width: 64
        height: 64
        radius: 32
        color: backButtonMouse.pressed ? "#333344" : "#1a1a2e"
        border.color: "#444455"
        border.width: 2

        Text {
            anchors.centerIn: parent
            text: "←"
            font.pixelSize: 28
            color: "#ffffff"
        }

        MouseArea {
            id: backButtonMouse
            anchors.fill: parent
            onClicked: stackView.pop()
        }
    }
}
