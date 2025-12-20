import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Page {
    id: soundPage

    background: Rectangle {
        color: "#0a0a0f"
    }

    header: Rectangle {
        height: 140
        color: "#12121a"

        Text {
            anchors.centerIn: parent
            text: "Sound"
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

        // Media volume
        Rectangle {
            Layout.fillWidth: true
            height: 160
            color: "#12121a"
            radius: 16

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 28
                spacing: 20

                Text {
                    text: "Media Volume"
                    font.pixelSize: 32
                    color: "#ffffff"
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 20

                    Text {
                        text: "🔈"
                        font.pixelSize: 36
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
                            height: 12
                            radius: 6
                            color: "#333344"

                            Rectangle {
                                width: mediaSlider.visualPosition * parent.width
                                height: parent.height
                                radius: 6
                                color: "#e94560"
                            }
                        }

                        handle: Rectangle {
                            x: mediaSlider.leftPadding + mediaSlider.visualPosition * (mediaSlider.availableWidth - width)
                            y: mediaSlider.topPadding + mediaSlider.availableHeight / 2 - height / 2
                            width: 44
                            height: 44
                            radius: 22
                            color: "#ffffff"
                        }
                    }

                    Text {
                        text: "🔊"
                        font.pixelSize: 36
                    }
                }
            }
        }

        // Ring volume
        Rectangle {
            Layout.fillWidth: true
            height: 160
            color: "#12121a"
            radius: 16

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 28
                spacing: 20

                Text {
                    text: "Ring Volume"
                    font.pixelSize: 32
                    color: "#ffffff"
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 20

                    Text {
                        text: "🔔"
                        font.pixelSize: 36
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
                            height: 12
                            radius: 6
                            color: "#333344"

                            Rectangle {
                                width: ringSlider.visualPosition * parent.width
                                height: parent.height
                                radius: 6
                                color: "#e94560"
                            }
                        }

                        handle: Rectangle {
                            x: ringSlider.leftPadding + ringSlider.visualPosition * (ringSlider.availableWidth - width)
                            y: ringSlider.topPadding + ringSlider.availableHeight / 2 - height / 2
                            width: 44
                            height: 44
                            radius: 22
                            color: "#ffffff"
                        }
                    }

                    Text {
                        text: "🔔"
                        font.pixelSize: 36
                    }
                }
            }
        }

        // Vibration toggle
        Rectangle {
            Layout.fillWidth: true
            height: 120
            color: "#12121a"
            radius: 16

            RowLayout {
                anchors.fill: parent
                anchors.margins: 28

                Text {
                    text: "Vibration"
                    font.pixelSize: 32
                    color: "#ffffff"
                    Layout.fillWidth: true
                }

                Switch {
                    id: vibrationSwitch
                    checked: true

                    indicator: Rectangle {
                        implicitWidth: 80
                        implicitHeight: 44
                        radius: 22
                        color: vibrationSwitch.checked ? "#e94560" : "#333344"

                        Rectangle {
                            x: vibrationSwitch.checked ? parent.width - width - 4 : 4
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

        // Silent mode
        Rectangle {
            Layout.fillWidth: true
            height: 120
            color: "#12121a"
            radius: 16

            RowLayout {
                anchors.fill: parent
                anchors.margins: 28

                Text {
                    text: "Silent Mode"
                    font.pixelSize: 32
                    color: "#ffffff"
                    Layout.fillWidth: true
                }

                Switch {
                    id: silentSwitch
                    checked: false

                    indicator: Rectangle {
                        implicitWidth: 80
                        implicitHeight: 44
                        radius: 22
                        color: silentSwitch.checked ? "#e94560" : "#333344"

                        Rectangle {
                            x: silentSwitch.checked ? parent.width - width - 4 : 4
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
