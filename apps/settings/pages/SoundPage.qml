import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Page {
    id: soundPage

    background: Rectangle {
        color: "#0a0a0f"
    }

    header: Rectangle {
        height: 100
        color: "#12121a"

        Text {
            anchors.centerIn: parent
            text: "Sound"
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

        // Media volume
        Rectangle {
            Layout.fillWidth: true
            height: 120
            color: "#12121a"
            radius: 12

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 20
                spacing: 16

                Text {
                    text: "Media Volume"
                    font.pixelSize: 24
                    color: "#ffffff"
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 16

                    Text {
                        text: "🔈"
                        font.pixelSize: 28
                    }

                    Slider {
                        id: mediaSlider
                        Layout.fillWidth: true
                        from: 0
                        to: 100
                        value: 70

                        background: Rectangle {
                            x: mediaSlider.leftPadding
                            y: mediaSlider.topPadding + mediaSlider.availableHeight / 2 - height / 2
                            width: mediaSlider.availableWidth
                            height: 8
                            radius: 4
                            color: "#333344"

                            Rectangle {
                                width: mediaSlider.visualPosition * parent.width
                                height: parent.height
                                radius: 4
                                color: "#e94560"
                            }
                        }

                        handle: Rectangle {
                            x: mediaSlider.leftPadding + mediaSlider.visualPosition * (mediaSlider.availableWidth - width)
                            y: mediaSlider.topPadding + mediaSlider.availableHeight / 2 - height / 2
                            width: 32
                            height: 32
                            radius: 16
                            color: "#ffffff"
                        }
                    }

                    Text {
                        text: "🔊"
                        font.pixelSize: 28
                    }
                }
            }
        }

        // Ring volume
        Rectangle {
            Layout.fillWidth: true
            height: 120
            color: "#12121a"
            radius: 12

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 20
                spacing: 16

                Text {
                    text: "Ring Volume"
                    font.pixelSize: 24
                    color: "#ffffff"
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 16

                    Text {
                        text: "🔔"
                        font.pixelSize: 28
                    }

                    Slider {
                        id: ringSlider
                        Layout.fillWidth: true
                        from: 0
                        to: 100
                        value: 80

                        background: Rectangle {
                            x: ringSlider.leftPadding
                            y: ringSlider.topPadding + ringSlider.availableHeight / 2 - height / 2
                            width: ringSlider.availableWidth
                            height: 8
                            radius: 4
                            color: "#333344"

                            Rectangle {
                                width: ringSlider.visualPosition * parent.width
                                height: parent.height
                                radius: 4
                                color: "#e94560"
                            }
                        }

                        handle: Rectangle {
                            x: ringSlider.leftPadding + ringSlider.visualPosition * (ringSlider.availableWidth - width)
                            y: ringSlider.topPadding + ringSlider.availableHeight / 2 - height / 2
                            width: 32
                            height: 32
                            radius: 16
                            color: "#ffffff"
                        }
                    }

                    Text {
                        text: "🔔"
                        font.pixelSize: 28
                    }
                }
            }
        }

        // Vibration toggle
        Rectangle {
            Layout.fillWidth: true
            height: 80
            color: "#12121a"
            radius: 12

            RowLayout {
                anchors.fill: parent
                anchors.margins: 20

                Text {
                    text: "Vibration"
                    font.pixelSize: 24
                    color: "#ffffff"
                    Layout.fillWidth: true
                }

                Switch {
                    id: vibrationSwitch
                    checked: true

                    indicator: Rectangle {
                        implicitWidth: 60
                        implicitHeight: 34
                        radius: 17
                        color: vibrationSwitch.checked ? "#e94560" : "#333344"

                        Rectangle {
                            x: vibrationSwitch.checked ? parent.width - width - 4 : 4
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

        // Silent mode
        Rectangle {
            Layout.fillWidth: true
            height: 80
            color: "#12121a"
            radius: 12

            RowLayout {
                anchors.fill: parent
                anchors.margins: 20

                Text {
                    text: "Silent Mode"
                    font.pixelSize: 24
                    color: "#ffffff"
                    Layout.fillWidth: true
                }

                Switch {
                    id: silentSwitch
                    checked: false

                    indicator: Rectangle {
                        implicitWidth: 60
                        implicitHeight: 34
                        radius: 17
                        color: silentSwitch.checked ? "#e94560" : "#333344"

                        Rectangle {
                            x: silentSwitch.checked ? parent.width - width - 4 : 4
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
