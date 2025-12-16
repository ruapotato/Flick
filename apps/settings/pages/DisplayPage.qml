import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Page {
    id: displayPage

    background: Rectangle {
        color: "#0a0a0f"
    }

    header: Rectangle {
        height: 80
        color: "#12121a"

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 16

            Text {
                text: "‹"
                font.pixelSize: 32
                color: "#e94560"
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -10
                    onClicked: stackView.pop()
                }
            }

            Text {
                text: "Display"
                font.pixelSize: 28
                font.weight: Font.Light
                color: "#ffffff"
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
            }

            Item { width: 32 }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 20

        // Brightness section
        Rectangle {
            Layout.fillWidth: true
            height: 120
            color: "#12121a"
            radius: 10

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 16

                RowLayout {
                    Layout.fillWidth: true

                    Text {
                        text: "Brightness"
                        font.pixelSize: 18
                        color: "#ffffff"
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        text: Math.round(brightnessSlider.value) + "%"
                        font.pixelSize: 16
                        color: "#666677"
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    Text {
                        text: "🔅"
                        font.pixelSize: 20
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
                            height: 6
                            radius: 3
                            color: "#333344"

                            Rectangle {
                                width: brightnessSlider.visualPosition * parent.width
                                height: parent.height
                                radius: 3
                                color: "#e94560"
                            }
                        }

                        handle: Rectangle {
                            x: brightnessSlider.leftPadding + brightnessSlider.visualPosition * (brightnessSlider.availableWidth - width)
                            y: brightnessSlider.topPadding + brightnessSlider.availableHeight / 2 - height / 2
                            width: 24
                            height: 24
                            radius: 12
                            color: "#ffffff"
                        }
                    }

                    Text {
                        text: "🔆"
                        font.pixelSize: 20
                    }
                }
            }
        }

        // Auto brightness
        Rectangle {
            Layout.fillWidth: true
            height: 60
            color: "#12121a"
            radius: 10

            RowLayout {
                anchors.fill: parent
                anchors.margins: 16

                Text {
                    text: "Auto Brightness"
                    font.pixelSize: 18
                    color: "#ffffff"
                    Layout.fillWidth: true
                }

                Switch {
                    id: autoBrightnessSwitch
                    checked: false

                    indicator: Rectangle {
                        implicitWidth: 50
                        implicitHeight: 28
                        radius: 14
                        color: autoBrightnessSwitch.checked ? "#e94560" : "#333344"

                        Rectangle {
                            x: autoBrightnessSwitch.checked ? parent.width - width - 4 : 4
                            anchors.verticalCenter: parent.verticalCenter
                            width: 20
                            height: 20
                            radius: 10
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
            height: 60
            color: "#12121a"
            radius: 10

            RowLayout {
                anchors.fill: parent
                anchors.margins: 16

                Text {
                    text: "Screen Timeout"
                    font.pixelSize: 18
                    color: "#ffffff"
                    Layout.fillWidth: true
                }

                Text {
                    text: "30 seconds"
                    font.pixelSize: 16
                    color: "#666677"
                }

                Text {
                    text: "›"
                    font.pixelSize: 20
                    color: "#444455"
                }
            }
        }

        Item { Layout.fillHeight: true }
    }
}
