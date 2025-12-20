import QtQuick 2.15
import QtQuick.Controls 2.15

Item {
    id: pinEntry

    // Scale based on parent width - use most of the screen
    width: parent ? Math.min(parent.width * 0.95, 800) : 500
    height: parent ? parent.height * 0.85 : 800

    property string correctPin: "1234"
    property string enteredPin: ""
    property int maxDigits: 4

    // Calculate button size based on available width - larger for mobile
    property real buttonSize: Math.min((width - 40) / 3, 160)
    property real buttonSpacing: buttonSize * 0.15

    signal pinCorrect()
    signal pinIncorrect()
    signal cancelled()

    // Title
    Text {
        id: title
        anchors.top: parent.top
        anchors.topMargin: 30
        anchors.horizontalCenter: parent.horizontalCenter
        text: "Enter PIN"
        font.pixelSize: Math.max(40, parent.width * 0.1)
        font.weight: Font.Light
        color: "#ffffff"
    }

    // PIN dots
    Row {
        id: pinDots
        anchors.top: title.bottom
        anchors.topMargin: 50
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: buttonSize * 0.35

        Repeater {
            model: maxDigits
            Rectangle {
                width: buttonSize * 0.3
                height: width
                radius: width / 2
                color: index < enteredPin.length ? "#e94560" : "transparent"
                border.color: index < enteredPin.length ? "#e94560" : "#444455"
                border.width: 4

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
        anchors.topMargin: 60
        anchors.horizontalCenter: parent.horizontalCenter
        columns: 3
        spacing: buttonSpacing

        Repeater {
            model: ["1", "2", "3", "4", "5", "6", "7", "8", "9", "", "0", "⌫"]

            Rectangle {
                width: buttonSize
                height: buttonSize
                radius: buttonSize / 2
                color: buttonMouse.pressed ? "#333344" : (modelData === "" ? "transparent" : "#1a1a2e")
                border.color: modelData === "" ? "transparent" : "#444455"
                border.width: 3
                visible: modelData !== ""

                Text {
                    anchors.centerIn: parent
                    text: modelData
                    font.pixelSize: modelData === "⌫" ? buttonSize * 0.4 : buttonSize * 0.5
                    font.weight: Font.Normal
                    color: "#ffffff"
                }

                MouseArea {
                    id: buttonMouse
                    anchors.fill: parent
                    enabled: modelData !== ""

                    onClicked: {
                        console.log("Button pressed:", modelData, "current PIN:", enteredPin)
                        if (modelData === "⌫") {
                            // Backspace
                            if (enteredPin.length > 0) {
                                enteredPin = enteredPin.substring(0, enteredPin.length - 1)
                            }
                        } else {
                            // Number
                            if (enteredPin.length < maxDigits) {
                                enteredPin += modelData
                                console.log("PIN now:", enteredPin, "length:", enteredPin.length)

                                // Check PIN when complete
                                if (enteredPin.length === maxDigits) {
                                    console.log("PIN complete, checking:", enteredPin, "vs", correctPin)
                                    checkTimer.start()
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Cancel button
    Text {
        anchors.top: numPad.bottom
        anchors.topMargin: 50
        anchors.horizontalCenter: parent.horizontalCenter
        text: "Cancel"
        font.pixelSize: buttonSize * 0.3
        color: "#888899"

        MouseArea {
            anchors.fill: parent
            anchors.margins: -30
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
            console.log("Checking PIN:", enteredPin, "===", correctPin, "result:", enteredPin === correctPin)
            if (enteredPin === correctPin) {
                console.log("PIN CORRECT!")
                pinCorrect()
            } else {
                console.log("PIN INCORRECT!")
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
