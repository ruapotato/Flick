import QtQuick 2.15
import QtQuick.Controls 2.15
import QtGraphicalEffects 1.15

Item {
    id: pinEntry
    width: 320
    height: 500

    property string correctPin: "1234"
    property string enteredPin: ""
    property int maxDigits: 4

    signal pinCorrect()
    signal pinIncorrect()
    signal cancelled()

    // Title
    Text {
        id: title
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        text: "Enter PIN"
        font.pixelSize: 28
        font.weight: Font.Light
        color: "#ffffff"
    }

    // PIN dots
    Row {
        id: pinDots
        anchors.top: title.bottom
        anchors.topMargin: 40
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 20

        Repeater {
            model: maxDigits
            Rectangle {
                width: 16
                height: 16
                radius: 8
                color: index < enteredPin.length ? "#e94560" : "transparent"
                border.color: index < enteredPin.length ? "#e94560" : "#444455"
                border.width: 2

                Behavior on color {
                    ColorAnimation { duration: 150 }
                }

                scale: index < enteredPin.length ? 1.2 : 1.0
                Behavior on scale {
                    NumberAnimation { duration: 150; easing.type: Easing.OutBack }
                }
            }
        }
    }

    // Number pad
    Grid {
        id: numPad
        anchors.top: pinDots.bottom
        anchors.topMargin: 50
        anchors.horizontalCenter: parent.horizontalCenter
        columns: 3
        spacing: 20

        Repeater {
            model: ["1", "2", "3", "4", "5", "6", "7", "8", "9", "", "0", "⌫"]

            Rectangle {
                width: 80
                height: 80
                radius: 40
                color: buttonMouse.pressed ? "#333344" : (modelData === "" ? "transparent" : "#1a1a2e")
                border.color: modelData === "" ? "transparent" : "#333344"
                border.width: 1
                visible: modelData !== ""

                Text {
                    anchors.centerIn: parent
                    text: modelData
                    font.pixelSize: modelData === "⌫" ? 28 : 36
                    font.weight: Font.Light
                    color: "#ffffff"
                }

                MouseArea {
                    id: buttonMouse
                    anchors.fill: parent
                    enabled: modelData !== ""

                    onClicked: {
                        if (modelData === "⌫") {
                            // Backspace
                            if (enteredPin.length > 0) {
                                enteredPin = enteredPin.substring(0, enteredPin.length - 1)
                            }
                        } else {
                            // Number
                            if (enteredPin.length < maxDigits) {
                                enteredPin += modelData

                                // Check PIN when complete
                                if (enteredPin.length === maxDigits) {
                                    checkTimer.start()
                                }
                            }
                        }
                    }
                }

                // Ripple effect
                Rectangle {
                    id: ripple
                    anchors.centerIn: parent
                    width: 0
                    height: width
                    radius: width / 2
                    color: "#ffffff"
                    opacity: 0

                    SequentialAnimation {
                        id: rippleAnim
                        PropertyAnimation {
                            target: ripple
                            properties: "width,height"
                            to: 100
                            duration: 200
                        }
                        PropertyAnimation {
                            target: ripple
                            property: "opacity"
                            to: 0
                            duration: 200
                        }
                        PropertyAnimation {
                            target: ripple
                            properties: "width,height"
                            to: 0
                            duration: 0
                        }
                    }

                    Connections {
                        target: buttonMouse
                        function onPressed() {
                            ripple.opacity = 0.2
                            rippleAnim.start()
                        }
                    }
                }
            }
        }
    }

    // Cancel button
    Text {
        anchors.top: numPad.bottom
        anchors.topMargin: 30
        anchors.horizontalCenter: parent.horizontalCenter
        text: "Cancel"
        font.pixelSize: 18
        color: "#666677"

        MouseArea {
            anchors.fill: parent
            anchors.margins: -10
            onClicked: {
                enteredPin = ""
                cancelled()
            }
        }
    }

    // Delay before checking PIN (for visual feedback)
    Timer {
        id: checkTimer
        interval: 300
        onTriggered: {
            if (enteredPin === correctPin) {
                pinCorrect()
            } else {
                pinIncorrect()
                clearTimer.start()
            }
        }
    }

    // Clear PIN after wrong attempt
    Timer {
        id: clearTimer
        interval: 500
        onTriggered: {
            enteredPin = ""
        }
    }
}
