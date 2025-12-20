import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Page {
    id: displayPage

    background: Rectangle {
        color: "#0a0a0f"
    }

    header: Rectangle {
        height: 140
        color: "#12121a"

        Text {
            anchors.centerIn: parent
            text: "Display"
            font.pixelSize: 48
            font.weight: Font.Light
            color: "#ffffff"
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 32
        anchors.bottomMargin: 120
        spacing: 32

        // Brightness section
        Rectangle {
            Layout.fillWidth: true
            height: 180
            color: "#12121a"
            radius: 16

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 28
                spacing: 24

                RowLayout {
                    Layout.fillWidth: true

                    Text {
                        text: "Brightness"
                        font.pixelSize: 32
                        color: "#ffffff"
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        text: Math.round(brightnessSlider.value) + "%"
                        font.pixelSize: 28
                        color: "#666677"
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 20

                    Text {
                        text: "🔅"
                        font.pixelSize: 36
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
                            height: 12
                            radius: 6
                            color: "#333344"

                            Rectangle {
                                width: brightnessSlider.visualPosition * parent.width
                                height: parent.height
                                radius: 6
                                color: "#e94560"
                            }
                        }

                        handle: Rectangle {
                            x: brightnessSlider.leftPadding + brightnessSlider.visualPosition * (brightnessSlider.availableWidth - width)
                            y: brightnessSlider.topPadding + brightnessSlider.availableHeight / 2 - height / 2
                            width: 44
                            height: 44
                            radius: 22
                            color: "#ffffff"
                        }
                    }

                    Text {
                        text: "🔆"
                        font.pixelSize: 36
                    }
                }
            }
        }

        // Auto brightness
        Rectangle {
            Layout.fillWidth: true
            height: 120
            color: "#12121a"
            radius: 16

            RowLayout {
                anchors.fill: parent
                anchors.margins: 28

                Text {
                    text: "Auto Brightness"
                    font.pixelSize: 32
                    color: "#ffffff"
                    Layout.fillWidth: true
                }

                Switch {
                    id: autoBrightnessSwitch
                    checked: false

                    indicator: Rectangle {
                        implicitWidth: 80
                        implicitHeight: 44
                        radius: 22
                        color: autoBrightnessSwitch.checked ? "#e94560" : "#333344"

                        Rectangle {
                            x: autoBrightnessSwitch.checked ? parent.width - width - 4 : 4
                            anchors.verticalCenter: parent.verticalCenter
                            width: 36
                            height: 36
                            radius: 18
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
            height: 120
            color: "#12121a"
            radius: 16

            RowLayout {
                anchors.fill: parent
                anchors.margins: 28

                Text {
                    text: "Screen Timeout"
                    font.pixelSize: 32
                    color: "#ffffff"
                    Layout.fillWidth: true
                }

                Text {
                    text: "30 seconds"
                    font.pixelSize: 26
                    color: "#666677"
                }

                Text {
                    text: "›"
                    font.pixelSize: 36
                    color: "#444455"
                }
            }
        }

        Item { Layout.fillHeight: true }
    }

    // Back button - bottom right
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
            onClicked: stackView.pop()
        }
    }
}
