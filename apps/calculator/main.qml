import QtQuick 2.15
import QtQuick.Window 2.15
import "../shared"

Window {
    id: root
    visible: true
    visibility: Window.FullScreen
    width: 1080
    height: 2400
    title: "Calculator"
    color: "#0a0a0f"

    property string display: "0"
    property real currentValue: 0
    property real storedValue: 0
    property string currentOperation: ""
    property bool newNumber: true
    property int maxDigits: 12
    property color accentColor: Theme.accentColor
    property color accentPressed: Qt.darker(accentColor, 1.2)

    function appendDigit(digit) {
        Haptic.tap()
        if (newNumber) {
            display = digit
            newNumber = false
        } else {
            if (display.length < maxDigits) {
                if (display === "0" && digit !== ".") {
                    display = digit
                } else {
                    display += digit
                }
            }
        }
        currentValue = parseFloat(display)
    }

    function appendDecimal() {
        Haptic.tap()
        if (newNumber) {
            display = "0."
            newNumber = false
        } else {
            if (display.indexOf(".") === -1 && display.length < maxDigits) {
                display += "."
            }
        }
    }

    function toggleSign() {
        Haptic.tap()
        if (display !== "0") {
            if (display.charAt(0) === "-") {
                display = display.substring(1)
            } else {
                display = "-" + display
            }
            currentValue = parseFloat(display)
        }
    }

    function clear() {
        Haptic.click()
        display = "0"
        currentValue = 0
        storedValue = 0
        currentOperation = ""
        newNumber = true
    }

    function setOperation(op) {
        Haptic.tap()
        if (currentOperation !== "" && !newNumber) {
            calculate()
        } else {
            storedValue = currentValue
        }
        currentOperation = op
        newNumber = true
    }

    function calculate() {
        Haptic.click()
        var result = 0
        switch (currentOperation) {
            case "+": result = storedValue + currentValue; break
            case "-": result = storedValue - currentValue; break
            case "*": result = storedValue * currentValue; break
            case "/":
                if (currentValue !== 0) {
                    result = storedValue / currentValue
                } else {
                    display = "Error"
                    currentOperation = ""
                    newNumber = true
                    return
                }
                break
            default: result = currentValue
        }

        var resultStr = result.toString()
        if (resultStr.length > maxDigits) {
            if (Math.abs(result) >= Math.pow(10, maxDigits)) {
                resultStr = result.toExponential(6)
            } else {
                resultStr = result.toPrecision(maxDigits)
            }
        }

        display = resultStr
        currentValue = result
        storedValue = result
        currentOperation = ""
        newNumber = true
    }

    // Display area
    Rectangle {
        id: displayArea
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: parent.height * 0.25
        color: "#0f0f14"

        Column {
            anchors.fill: parent
            anchors.margins: 32

            // Operation indicator
            Text {
                width: parent.width
                height: 40
                text: currentOperation !== "" ? storedValue + " " + currentOperation : ""
                color: "#666677"
                font.pixelSize: 24
                horizontalAlignment: Text.AlignRight
                verticalAlignment: Text.AlignBottom
            }

            // Main display
            Text {
                width: parent.width
                height: parent.height - 40
                text: display
                color: "#ffffff"
                font.pixelSize: 80
                font.weight: Font.Bold
                horizontalAlignment: Text.AlignRight
                verticalAlignment: Text.AlignVCenter
                fontSizeMode: Text.Fit
                minimumPixelSize: 36
            }
        }
    }

    // Button area
    Item {
        id: buttonArea
        anchors.top: displayArea.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 16
        anchors.bottomMargin: 100

        property real btnSpacing: 12
        property real btnW: (width - btnSpacing * 3) / 4
        property real btnH: (height - btnSpacing * 4) / 5

        // Calculator button component
        component CalcButton: Rectangle {
            id: calcBtn
            property string label: ""
            property color btnColor: "#1a1a2e"
            property color pressedColor: "#2a2a3e"
            property int fontSize: 40
            signal clicked()

            radius: 16
            color: btnMouse.pressed ? pressedColor : btnColor

            Behavior on color { ColorAnimation { duration: 100 } }

            Text {
                anchors.centerIn: parent
                text: calcBtn.label
                color: "#ffffff"
                font.pixelSize: calcBtn.fontSize
                font.weight: Font.Bold
            }

            MouseArea {
                id: btnMouse
                anchors.fill: parent
                onClicked: calcBtn.clicked()
            }
        }

        // Row 1: C, +/-, /, *
        Row {
            id: row1
            x: 0
            y: 0
            spacing: buttonArea.btnSpacing

            CalcButton {
                width: buttonArea.btnW; height: buttonArea.btnH
                label: "C"; btnColor: "#3a3a4e"; pressedColor: "#555577"
                onClicked: clear()
            }
            CalcButton {
                width: buttonArea.btnW; height: buttonArea.btnH
                label: "+/-"; btnColor: "#3a3a4e"; pressedColor: "#555577"; fontSize: 32
                onClicked: toggleSign()
            }
            CalcButton {
                width: buttonArea.btnW; height: buttonArea.btnH
                label: "%"; btnColor: "#3a3a4e"; pressedColor: "#555577"
                onClicked: { Haptic.tap(); display = (currentValue / 100).toString(); currentValue = currentValue / 100 }
            }
            CalcButton {
                width: buttonArea.btnW; height: buttonArea.btnH
                label: "÷"; btnColor: accentColor; pressedColor: accentPressed
                onClicked: setOperation("/")
            }
        }

        // Row 2: 7, 8, 9, ×
        Row {
            id: row2
            x: 0
            y: buttonArea.btnH + buttonArea.btnSpacing
            spacing: buttonArea.btnSpacing

            CalcButton {
                width: buttonArea.btnW; height: buttonArea.btnH
                label: "7"
                onClicked: appendDigit("7")
            }
            CalcButton {
                width: buttonArea.btnW; height: buttonArea.btnH
                label: "8"
                onClicked: appendDigit("8")
            }
            CalcButton {
                width: buttonArea.btnW; height: buttonArea.btnH
                label: "9"
                onClicked: appendDigit("9")
            }
            CalcButton {
                width: buttonArea.btnW; height: buttonArea.btnH
                label: "×"; btnColor: accentColor; pressedColor: accentPressed
                onClicked: setOperation("*")
            }
        }

        // Row 3: 4, 5, 6, -
        Row {
            id: row3
            x: 0
            y: (buttonArea.btnH + buttonArea.btnSpacing) * 2
            spacing: buttonArea.btnSpacing

            CalcButton {
                width: buttonArea.btnW; height: buttonArea.btnH
                label: "4"
                onClicked: appendDigit("4")
            }
            CalcButton {
                width: buttonArea.btnW; height: buttonArea.btnH
                label: "5"
                onClicked: appendDigit("5")
            }
            CalcButton {
                width: buttonArea.btnW; height: buttonArea.btnH
                label: "6"
                onClicked: appendDigit("6")
            }
            CalcButton {
                width: buttonArea.btnW; height: buttonArea.btnH
                label: "-"; btnColor: accentColor; pressedColor: accentPressed; fontSize: 48
                onClicked: setOperation("-")
            }
        }

        // Row 4: 1, 2, 3, + (plus spans to row 5)
        Row {
            id: row4
            x: 0
            y: (buttonArea.btnH + buttonArea.btnSpacing) * 3
            spacing: buttonArea.btnSpacing

            CalcButton {
                width: buttonArea.btnW; height: buttonArea.btnH
                label: "1"
                onClicked: appendDigit("1")
            }
            CalcButton {
                width: buttonArea.btnW; height: buttonArea.btnH
                label: "2"
                onClicked: appendDigit("2")
            }
            CalcButton {
                width: buttonArea.btnW; height: buttonArea.btnH
                label: "3"
                onClicked: appendDigit("3")
            }
            CalcButton {
                width: buttonArea.btnW; height: buttonArea.btnH
                label: "+"; btnColor: accentColor; pressedColor: accentPressed; fontSize: 48
                onClicked: setOperation("+")
            }
        }

        // Row 5: 0 (wide), ., =
        Row {
            id: row5
            x: 0
            y: (buttonArea.btnH + buttonArea.btnSpacing) * 4
            spacing: buttonArea.btnSpacing

            CalcButton {
                width: buttonArea.btnW * 2 + buttonArea.btnSpacing; height: buttonArea.btnH
                label: "0"
                onClicked: appendDigit("0")
            }
            CalcButton {
                width: buttonArea.btnW; height: buttonArea.btnH
                label: "."; fontSize: 48
                onClicked: appendDecimal()
            }
            CalcButton {
                width: buttonArea.btnW; height: buttonArea.btnH
                label: "="; btnColor: accentColor; pressedColor: accentPressed; fontSize: 48
                onClicked: calculate()
            }
        }
    }

    // Home indicator
    Rectangle {
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottomMargin: 8
        width: 120
        height: 4
        radius: 2
        color: "#333344"
    }
}
