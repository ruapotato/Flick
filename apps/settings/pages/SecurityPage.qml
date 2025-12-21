import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Page {
    id: securityPage

    property int selectedMethod: 0  // 0=PIN, 1=Password, 2=Pattern, 3=None

    background: Rectangle {
        color: "#0a0a0f"
    }

    // Hero section
    Rectangle {
        id: heroSection
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 260
        color: "transparent"

        // Ambient glow
        Rectangle {
            anchors.centerIn: parent
            width: 350
            height: 250
            radius: 175
            color: "#4a1a3a"
            opacity: 0.2
        }

        Column {
            anchors.centerIn: parent
            spacing: 20

            // Large shield icon
            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 120
                height: 120

                // Shield glow
                Rectangle {
                    anchors.centerIn: parent
                    width: 150
                    height: 150
                    radius: 75
                    color: "#e94560"
                    opacity: 0.1

                    SequentialAnimation on opacity {
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.2; duration: 2000 }
                        NumberAnimation { to: 0.1; duration: 2000 }
                    }
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: 100
                    height: 100
                    radius: 50
                    color: "#4a1a3a"
                    border.color: "#e94560"
                    border.width: 3

                    Text {
                        anchors.centerIn: parent
                        text: selectedMethod === 3 ? "🔓" : "🔐"
                        font.pixelSize: 44
                    }
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Security"
                font.pixelSize: 42
                font.weight: Font.ExtraLight
                font.letterSpacing: 6
                color: "#ffffff"
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: selectedMethod === 3 ? "DEVICE UNLOCKED" : "DEVICE PROTECTED"
                font.pixelSize: 12
                font.letterSpacing: 2
                color: selectedMethod === 3 ? "#cc8844" : "#4ade80"
            }
        }
    }

    // Lock method selection
    Flickable {
        anchors.top: heroSection.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 16
        anchors.bottomMargin: 100
        contentHeight: methodsColumn.height
        clip: true

        Column {
            id: methodsColumn
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 12

            Text {
                text: "SCREEN LOCK METHOD"
                font.pixelSize: 12
                font.letterSpacing: 2
                color: "#555566"
                leftPadding: 8
            }

            // PIN option
            Rectangle {
                width: methodsColumn.width
                height: 100
                radius: 24
                color: pinMouse.pressed ? "#1e1e2e" : "#14141e"
                border.color: selectedMethod === 0 ? "#e94560" : "#1a1a2e"
                border.width: selectedMethod === 0 ? 2 : 1

                Behavior on border.color { ColorAnimation { duration: 150 } }

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 16

                    Rectangle {
                        Layout.preferredWidth: 60
                        Layout.preferredHeight: 60
                        radius: 16
                        color: selectedMethod === 0 ? "#3a1a2a" : "#1a1a28"

                        Text {
                            anchors.centerIn: parent
                            text: "🔢"
                            font.pixelSize: 28
                        }
                    }

                    Column {
                        Layout.fillWidth: true
                        spacing: 6

                        Text {
                            text: "PIN"
                            font.pixelSize: 22
                            font.weight: Font.Medium
                            color: "#ffffff"
                        }

                        Text {
                            text: "4-6 digit numeric code"
                            font.pixelSize: 14
                            color: "#666677"
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: 28
                        Layout.preferredHeight: 28
                        radius: 14
                        color: "transparent"
                        border.color: selectedMethod === 0 ? "#e94560" : "#3a3a4e"
                        border.width: 2

                        Rectangle {
                            anchors.centerIn: parent
                            width: selectedMethod === 0 ? 14 : 0
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
                    id: pinMouse
                    anchors.fill: parent
                    onClicked: selectedMethod = 0
                }
            }

            // Password option
            Rectangle {
                width: methodsColumn.width
                height: 100
                radius: 24
                color: passwordMouse.pressed ? "#1e1e2e" : "#14141e"
                border.color: selectedMethod === 1 ? "#e94560" : "#1a1a2e"
                border.width: selectedMethod === 1 ? 2 : 1

                Behavior on border.color { ColorAnimation { duration: 150 } }

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 16

                    Rectangle {
                        Layout.preferredWidth: 60
                        Layout.preferredHeight: 60
                        radius: 16
                        color: selectedMethod === 1 ? "#3a1a2a" : "#1a1a28"

                        Text {
                            anchors.centerIn: parent
                            text: "🔤"
                            font.pixelSize: 28
                        }
                    }

                    Column {
                        Layout.fillWidth: true
                        spacing: 6

                        Text {
                            text: "Password"
                            font.pixelSize: 22
                            font.weight: Font.Medium
                            color: "#ffffff"
                        }

                        Text {
                            text: "System password for unlock"
                            font.pixelSize: 14
                            color: "#666677"
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: 28
                        Layout.preferredHeight: 28
                        radius: 14
                        color: "transparent"
                        border.color: selectedMethod === 1 ? "#e94560" : "#3a3a4e"
                        border.width: 2

                        Rectangle {
                            anchors.centerIn: parent
                            width: selectedMethod === 1 ? 14 : 0
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
                    id: passwordMouse
                    anchors.fill: parent
                    onClicked: selectedMethod = 1
                }
            }

            // Pattern option
            Rectangle {
                width: methodsColumn.width
                height: 100
                radius: 24
                color: patternMouse.pressed ? "#1e1e2e" : "#14141e"
                border.color: selectedMethod === 2 ? "#e94560" : "#1a1a2e"
                border.width: selectedMethod === 2 ? 2 : 1

                Behavior on border.color { ColorAnimation { duration: 150 } }

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 16

                    Rectangle {
                        Layout.preferredWidth: 60
                        Layout.preferredHeight: 60
                        radius: 16
                        color: selectedMethod === 2 ? "#3a1a2a" : "#1a1a28"

                        // Pattern grid preview
                        Grid {
                            anchors.centerIn: parent
                            columns: 3
                            spacing: 6

                            Repeater {
                                model: 9
                                Rectangle {
                                    width: 10
                                    height: 10
                                    radius: 5
                                    color: (index === 0 || index === 4 || index === 8) ? "#e94560" : "#444455"
                                }
                            }
                        }
                    }

                    Column {
                        Layout.fillWidth: true
                        spacing: 6

                        Text {
                            text: "Pattern"
                            font.pixelSize: 22
                            font.weight: Font.Medium
                            color: "#ffffff"
                        }

                        Text {
                            text: "Draw a pattern to unlock"
                            font.pixelSize: 14
                            color: "#666677"
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: 28
                        Layout.preferredHeight: 28
                        radius: 14
                        color: "transparent"
                        border.color: selectedMethod === 2 ? "#e94560" : "#3a3a4e"
                        border.width: 2

                        Rectangle {
                            anchors.centerIn: parent
                            width: selectedMethod === 2 ? 14 : 0
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
                    id: patternMouse
                    anchors.fill: parent
                    onClicked: selectedMethod = 2
                }
            }

            // None option
            Rectangle {
                width: methodsColumn.width
                height: 100
                radius: 24
                color: noneMouse.pressed ? "#1e1e2e" : "#14141e"
                border.color: selectedMethod === 3 ? "#cc8844" : "#1a1a2e"
                border.width: selectedMethod === 3 ? 2 : 1

                Behavior on border.color { ColorAnimation { duration: 150 } }

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 16

                    Rectangle {
                        Layout.preferredWidth: 60
                        Layout.preferredHeight: 60
                        radius: 16
                        color: selectedMethod === 3 ? "#3a2a1a" : "#1a1a28"

                        Text {
                            anchors.centerIn: parent
                            text: "🔓"
                            font.pixelSize: 28
                        }
                    }

                    Column {
                        Layout.fillWidth: true
                        spacing: 6

                        Text {
                            text: "None"
                            font.pixelSize: 22
                            font.weight: Font.Medium
                            color: "#ffffff"
                        }

                        Text {
                            text: "Swipe to unlock (not secure)"
                            font.pixelSize: 14
                            color: "#cc8844"
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: 28
                        Layout.preferredHeight: 28
                        radius: 14
                        color: "transparent"
                        border.color: selectedMethod === 3 ? "#cc8844" : "#3a3a4e"
                        border.width: 2

                        Rectangle {
                            anchors.centerIn: parent
                            width: selectedMethod === 3 ? 14 : 0
                            height: width
                            radius: width / 2
                            color: "#cc8844"

                            Behavior on width {
                                NumberAnimation { duration: 150; easing.type: Easing.OutBack }
                            }
                        }
                    }
                }

                MouseArea {
                    id: noneMouse
                    anchors.fill: parent
                    onClicked: selectedMethod = 3
                }
            }

            Item { height: 16 }

            // Info card
            Rectangle {
                width: methodsColumn.width
                height: 80
                radius: 20
                color: "#1a1a1a"
                border.color: "#2a2a2e"
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 12

                    Text {
                        text: "ℹ️"
                        font.pixelSize: 24
                    }

                    Text {
                        text: "Changes take effect on next lock"
                        font.pixelSize: 15
                        color: "#777788"
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                    }
                }
            }

            Item { height: 20 }
        }
    }

    // Back button - prominent floating action button
    Rectangle {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 24
        anchors.bottomMargin: 120
        width: 72
        height: 72
        radius: 36
        color: backMouse.pressed ? "#c23a50" : "#e94560"

        Behavior on color { ColorAnimation { duration: 150 } }

        Text {
            anchors.centerIn: parent
            text: "←"
            font.pixelSize: 32
            font.weight: Font.Medium
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
