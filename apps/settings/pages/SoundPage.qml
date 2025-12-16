import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Page {
    id: soundPage

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
                text: "Sound"
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

        // Media volume
        Rectangle {
            Layout.fillWidth: true
            height: 100
            color: "#12121a"
            radius: 10

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 12

                Text {
                    text: "Media Volume"
                    font.pixelSize: 18
                    color: "#ffffff"
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    Text {
                        text: "🔈"
                        font.pixelSize: 20
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
                            height: 6
                            radius: 3
                            color: "#333344"

                            Rectangle {
                                width: mediaSlider.visualPosition * parent.width
                                height: parent.height
                                radius: 3
                                color: "#e94560"
                            }
                        }

                        handle: Rectangle {
                            x: mediaSlider.leftPadding + mediaSlider.visualPosition * (mediaSlider.availableWidth - width)
                            y: mediaSlider.topPadding + mediaSlider.availableHeight / 2 - height / 2
                            width: 24
                            height: 24
                            radius: 12
                            color: "#ffffff"
                        }
                    }

                    Text {
                        text: "🔊"
                        font.pixelSize: 20
                    }
                }
            }
        }

        // Ring volume
        Rectangle {
            Layout.fillWidth: true
            height: 100
            color: "#12121a"
            radius: 10

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 12

                Text {
                    text: "Ring Volume"
                    font.pixelSize: 18
                    color: "#ffffff"
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    Text {
                        text: "🔔"
                        font.pixelSize: 20
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
                            height: 6
                            radius: 3
                            color: "#333344"

                            Rectangle {
                                width: ringSlider.visualPosition * parent.width
                                height: parent.height
                                radius: 3
                                color: "#e94560"
                            }
                        }

                        handle: Rectangle {
                            x: ringSlider.leftPadding + ringSlider.visualPosition * (ringSlider.availableWidth - width)
                            y: ringSlider.topPadding + ringSlider.availableHeight / 2 - height / 2
                            width: 24
                            height: 24
                            radius: 12
                            color: "#ffffff"
                        }
                    }

                    Text {
                        text: "🔔"
                        font.pixelSize: 20
                    }
                }
            }
        }

        // Vibration toggle
        Rectangle {
            Layout.fillWidth: true
            height: 60
            color: "#12121a"
            radius: 10

            RowLayout {
                anchors.fill: parent
                anchors.margins: 16

                Text {
                    text: "Vibration"
                    font.pixelSize: 18
                    color: "#ffffff"
                    Layout.fillWidth: true
                }

                Switch {
                    id: vibrationSwitch
                    checked: true

                    indicator: Rectangle {
                        implicitWidth: 50
                        implicitHeight: 28
                        radius: 14
                        color: vibrationSwitch.checked ? "#e94560" : "#333344"

                        Rectangle {
                            x: vibrationSwitch.checked ? parent.width - width - 4 : 4
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

        // Silent mode
        Rectangle {
            Layout.fillWidth: true
            height: 60
            color: "#12121a"
            radius: 10

            RowLayout {
                anchors.fill: parent
                anchors.margins: 16

                Text {
                    text: "Silent Mode"
                    font.pixelSize: 18
                    color: "#ffffff"
                    Layout.fillWidth: true
                }

                Switch {
                    id: silentSwitch
                    checked: false

                    indicator: Rectangle {
                        implicitWidth: 50
                        implicitHeight: 28
                        radius: 14
                        color: silentSwitch.checked ? "#e94560" : "#333344"

                        Rectangle {
                            x: silentSwitch.checked ? parent.width - width - 4 : 4
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

        Item { Layout.fillHeight: true }
    }
}
