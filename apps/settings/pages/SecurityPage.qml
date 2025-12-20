import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Page {
    id: securityPage

    property string currentMethod: "pin"  // pin, password, pattern, none

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
            text: "Security"
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

            // Section header
            Text {
                text: "SCREEN LOCK"
                font.pixelSize: 14
                font.weight: Font.Medium
                font.letterSpacing: 2
                color: "#666677"
                Layout.leftMargin: 8
                Layout.topMargin: 16
            }

            // Lock method options
            Repeater {
                model: ListModel {
                    ListElement {
                        title: "PIN"
                        subtitle: "4-digit numeric code"
                        method: "pin"
                        icon: "🔢"
                    }
                    ListElement {
                        title: "Password"
                        subtitle: "System password authentication"
                        method: "password"
                        icon: "🔐"
                    }
                    ListElement {
                        title: "Pattern"
                        subtitle: "Draw a pattern to unlock"
                        method: "pattern"
                        icon: "⬡"
                    }
                    ListElement {
                        title: "None"
                        subtitle: "No lock screen security"
                        method: "none"
                        icon: "🔓"
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 90
                    radius: 16
                    color: methodMouse.pressed ? "#1e1e2e" : "#14141e"
                    border.color: currentMethod === model.method ? "#e94560" : "#1a1a2e"
                    border.width: currentMethod === model.method ? 2 : 1

                    Behavior on color { ColorAnimation { duration: 100 } }
                    Behavior on border.color { ColorAnimation { duration: 200 } }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 20
                        anchors.rightMargin: 20
                        spacing: 16

                        // Icon
                        Rectangle {
                            Layout.preferredWidth: 52
                            Layout.preferredHeight: 52
                            radius: 12
                            color: currentMethod === model.method ? "#3c2a3a" : "#1a1a28"

                            Text {
                                anchors.centerIn: parent
                                text: model.icon
                                font.pixelSize: 24
                            }
                        }

                        // Text
                        Column {
                            Layout.fillWidth: true
                            spacing: 4

                            Text {
                                text: model.title
                                font.pixelSize: 22
                                font.weight: Font.Medium
                                color: "#ffffff"
                            }
                            Text {
                                text: model.subtitle
                                font.pixelSize: 14
                                color: "#666677"
                            }
                        }

                        // Radio indicator
                        Rectangle {
                            Layout.preferredWidth: 28
                            Layout.preferredHeight: 28
                            radius: 14
                            color: "transparent"
                            border.color: currentMethod === model.method ? "#e94560" : "#3a3a4e"
                            border.width: 2

                            Rectangle {
                                anchors.centerIn: parent
                                width: currentMethod === model.method ? 14 : 0
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
                        id: methodMouse
                        anchors.fill: parent
                        onClicked: {
                            currentMethod = model.method
                            // TODO: Save setting and show appropriate config dialog
                        }
                    }
                }
            }

            // PIN Settings (shown when PIN is selected)
            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 16
                height: pinSettingsColumn.height + 40
                radius: 16
                color: "#14141e"
                border.color: "#1a1a2e"
                border.width: 1
                visible: currentMethod === "pin"

                Column {
                    id: pinSettingsColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 20
                    spacing: 16

                    Text {
                        text: "PIN Settings"
                        font.pixelSize: 18
                        font.weight: Font.Medium
                        color: "#888899"
                    }

                    // Change PIN button
                    Rectangle {
                        width: parent.width
                        height: 60
                        radius: 12
                        color: changePinMouse.pressed ? "#2a2a3e" : "#1a1a28"

                        Text {
                            anchors.centerIn: parent
                            text: "Change PIN"
                            font.pixelSize: 18
                            color: "#e94560"
                        }

                        MouseArea {
                            id: changePinMouse
                            anchors.fill: parent
                            onClicked: {
                                // TODO: Show PIN change dialog
                                console.log("Change PIN clicked")
                            }
                        }
                    }
                }
            }

            // Pattern Settings (shown when pattern is selected)
            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 16
                height: patternSettingsColumn.height + 40
                radius: 16
                color: "#14141e"
                border.color: "#1a1a2e"
                border.width: 1
                visible: currentMethod === "pattern"

                Column {
                    id: patternSettingsColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 20
                    spacing: 16

                    Text {
                        text: "Pattern Settings"
                        font.pixelSize: 18
                        font.weight: Font.Medium
                        color: "#888899"
                    }

                    // Draw new pattern button
                    Rectangle {
                        width: parent.width
                        height: 60
                        radius: 12
                        color: drawPatternMouse.pressed ? "#2a2a3e" : "#1a1a28"

                        Text {
                            anchors.centerIn: parent
                            text: "Draw New Pattern"
                            font.pixelSize: 18
                            color: "#e94560"
                        }

                        MouseArea {
                            id: drawPatternMouse
                            anchors.fill: parent
                            onClicked: {
                                // TODO: Show pattern setup
                                console.log("Draw pattern clicked")
                            }
                        }
                    }

                    // Show pattern toggle
                    Rectangle {
                        width: parent.width
                        height: 60
                        radius: 12
                        color: "#1a1a28"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 16
                            anchors.rightMargin: 16

                            Text {
                                text: "Show pattern while drawing"
                                font.pixelSize: 16
                                color: "#ffffff"
                                Layout.fillWidth: true
                            }

                            Switch {
                                id: showPatternSwitch
                                checked: true

                                indicator: Rectangle {
                                    implicitWidth: 56
                                    implicitHeight: 32
                                    radius: 16
                                    color: showPatternSwitch.checked ? "#e94560" : "#333344"

                                    Rectangle {
                                        x: showPatternSwitch.checked ? parent.width - width - 3 : 3
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
                }
            }

            // Security info
            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 24
                height: infoColumn.height + 32
                radius: 16
                color: "#14141e"
                border.color: "#1a1a2e"
                border.width: 1

                Column {
                    id: infoColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 16
                    spacing: 12

                    Text {
                        text: "ℹ️  Security Information"
                        font.pixelSize: 16
                        font.weight: Font.Medium
                        color: "#888899"
                    }

                    Text {
                        width: parent.width
                        text: "Your device will lock automatically after the screen timeout. You can also lock it manually by pressing the power button."
                        font.pixelSize: 14
                        color: "#555566"
                        wrapMode: Text.WordWrap
                        lineHeight: 1.4
                    }
                }
            }

            Item { height: 40 }
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
