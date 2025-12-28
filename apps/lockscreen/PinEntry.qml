import QtQuick 2.15
import QtQuick.Controls 2.15

Item {
    id: pinEntry

    // Fill available space elegantly
    width: parent ? Math.min(parent.width * 0.92, 600) : 500
    height: parent ? parent.height * 0.88 : 800

    property string correctPin: "1234"
    property string enteredPin: ""
    property int maxDigits: 4
    property color accentColor: "#e94560"  // Can be set from parent

    // Dynamic sizing based on available space
    property real buttonSize: Math.min((width - 60) / 3, height / 6.5, 140)
    property real buttonSpacing: buttonSize * 0.18

    signal pinCorrect()
    signal pinIncorrect()
    signal cancelled()

    // Subtle glow effect behind title
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 20
        width: 200
        height: 60
        radius: 30
        color: accentColor
        opacity: 0.08

        NumberAnimation on opacity {
            from: 0.05
            to: 0.12
            duration: 2000
            loops: Animation.Infinite
            easing.type: Easing.InOutSine
        }
    }

    // Title
    Text {
        id: title
        anchors.top: parent.top
        anchors.topMargin: 30
        anchors.horizontalCenter: parent.horizontalCenter
        text: "Enter PIN"
        font.pixelSize: Math.min(42, parent.width * 0.1)
        font.weight: Font.Light
        font.letterSpacing: 3
        color: "#ffffff"
    }

    // PIN dots - elegant hollow circles that fill
    Row {
        id: pinDots
        anchors.top: title.bottom
        anchors.topMargin: 50
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: buttonSize * 0.4

        Repeater {
            model: maxDigits

            Item {
                width: buttonSize * 0.32
                height: width

                // Outer ring
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: "transparent"
                    border.color: index < enteredPin.length ? accentColor : "#3a3a4e"
                    border.width: 3

                    Behavior on border.color {
                        ColorAnimation { duration: 200 }
                    }
                }

                // Inner fill
                Rectangle {
                    anchors.centerIn: parent
                    width: index < enteredPin.length ? parent.width * 0.6 : 0
                    height: width
                    radius: width / 2
                    color: accentColor

                    Behavior on width {
                        NumberAnimation {
                            duration: 200
                            easing.type: Easing.OutBack
                            easing.overshoot: 1.5
                        }
                    }
                }
            }
        }
    }

    // Number pad - elegant glassmorphism style
    Grid {
        id: numPad
        anchors.top: pinDots.bottom
        anchors.topMargin: 50
        anchors.horizontalCenter: parent.horizontalCenter
        columns: 3
        spacing: buttonSpacing

        Repeater {
            model: ["1", "2", "3", "4", "5", "6", "7", "8", "9", "", "0", "⌫"]

            Item {
                width: buttonSize
                height: buttonSize
                visible: modelData !== ""

                // Button background with subtle glass effect
                Rectangle {
                    id: btnBg
                    anchors.fill: parent
                    radius: width / 2
                    color: buttonMouse.pressed ? "#2a2a3e" : "#1a1a28"
                    border.color: buttonMouse.pressed ? accentColor : "#2a2a3e"
                    border.width: 2

                    Behavior on color {
                        ColorAnimation { duration: 100 }
                    }
                    Behavior on border.color {
                        ColorAnimation { duration: 100 }
                    }
                }

                // Subtle inner highlight
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 3
                    radius: width / 2
                    color: "transparent"
                    border.color: "#ffffff"
                    border.width: 1
                    opacity: 0.05
                }

                // Button label
                Text {
                    anchors.centerIn: parent
                    text: modelData
                    font.pixelSize: modelData === "⌫" ? buttonSize * 0.35 : buttonSize * 0.42
                    font.weight: Font.Light
                    color: buttonMouse.pressed ? accentColor : "#ffffff"

                    Behavior on color {
                        ColorAnimation { duration: 100 }
                    }
                }

                // Touch feedback ripple
                Rectangle {
                    id: ripple
                    anchors.centerIn: parent
                    width: 0
                    height: width
                    radius: width / 2
                    color: accentColor
                    opacity: 0

                    SequentialAnimation {
                        id: rippleAnim
                        PropertyAnimation { target: ripple; properties: "width,height"; to: buttonSize * 1.2; duration: 200 }
                        PropertyAnimation { target: ripple; property: "opacity"; to: 0; duration: 150 }
                        PropertyAction { target: ripple; property: "width"; value: 0 }
                        PropertyAction { target: ripple; property: "height"; value: 0 }
                    }
                }

                MouseArea {
                    id: buttonMouse
                    anchors.fill: parent
                    enabled: modelData !== ""

                    onPressed: {
                        ripple.opacity = 0.3
                        rippleAnim.start()
                    }

                    onClicked: {
                        if (modelData === "⌫") {
                            if (enteredPin.length > 0) {
                                enteredPin = enteredPin.substring(0, enteredPin.length - 1)
                            }
                        } else {
                            if (enteredPin.length < maxDigits) {
                                enteredPin += modelData

                                if (enteredPin.length === maxDigits) {
                                    checkTimer.start()
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Cancel button - subtle text link
    Item {
        anchors.top: numPad.bottom
        anchors.topMargin: 40
        anchors.horizontalCenter: parent.horizontalCenter
        width: cancelText.width + 40
        height: cancelText.height + 20

        Text {
            id: cancelText
            anchors.centerIn: parent
            text: "Cancel"
            font.pixelSize: Math.min(22, buttonSize * 0.22)
            font.weight: Font.Light
            font.letterSpacing: 2
            color: cancelMouse.pressed ? accentColor : "#666677"

            Behavior on color {
                ColorAnimation { duration: 100 }
            }
        }

        MouseArea {
            id: cancelMouse
            anchors.fill: parent
            onClicked: {
                enteredPin = ""
                cancelled()
            }
        }
    }

    // Check PIN timer
    Timer {
        id: checkTimer
        interval: 350
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
        interval: 600
        onTriggered: {
            enteredPin = ""
        }
    }
}
