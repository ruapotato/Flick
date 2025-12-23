import QtQuick 2.15
import QtQuick.Window 2.15
import QtQuick.Controls 2.15

Window {
    id: root
    visible: true
    width: 1080
    height: 2400
    title: "Calculator"
    color: "#0a0a0f"

    // Settings from Flick config
    property real textScale: 2.0

    // Calculator state
    property string display: "0"
    property real currentValue: 0
    property real storedValue: 0
    property string currentOperation: ""
    property bool newNumber: true
    property int maxDigits: 12

    Component.onCompleted: {
        loadConfig()
    }

    function loadConfig() {
        // Try to read config from standard location (uses droidian home)
        var configPath = "/home/droidian/.local/state/flick/display_config.json"
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file://" + configPath, false)
        try {
            xhr.send()
            if (xhr.status === 200 || xhr.status === 0) {
                var config = JSON.parse(xhr.responseText)
                if (config.text_scale !== undefined) {
                    textScale = config.text_scale
                    console.log("Loaded text scale: " + textScale)
                }
            }
        } catch (e) {
            console.log("Using default text scale: " + textScale)
        }
    }

    // Reload config periodically to pick up settings changes
    Timer {
        interval: 3000
        running: true
        repeat: true
        onTriggered: loadConfig()
    }

    // Calculator logic
    function appendDigit(digit) {
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
        display = "0"
        currentValue = 0
        storedValue = 0
        currentOperation = ""
        newNumber = true
    }

    function setOperation(op) {
        if (currentOperation !== "" && !newNumber) {
            calculate()
        } else {
            storedValue = currentValue
        }
        currentOperation = op
        newNumber = true
    }

    function calculate() {
        var result = 0

        switch (currentOperation) {
            case "+":
                result = storedValue + currentValue
                break
            case "-":
                result = storedValue - currentValue
                break
            case "*":
                result = storedValue * currentValue
                break
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
            default:
                result = currentValue
        }

        // Format the result
        var resultStr = result.toString()
        if (resultStr.length > maxDigits) {
            // Try scientific notation or truncate
            if (Math.abs(result) >= Math.pow(10, maxDigits) ||
                (Math.abs(result) < 1 && Math.abs(result) > 0 && resultStr.length > maxDigits)) {
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

    // Main display
    Rectangle {
        id: displayArea
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 320 * textScale
        color: "#0f0f14"
        border.color: "#1a1a2e"
        border.width: 2

        Text {
            id: displayText
            anchors.fill: parent
            anchors.margins: 40 * textScale
            text: display
            color: "#ffffff"
            font.pixelSize: 60 * textScale
            font.weight: Font.Bold
            horizontalAlignment: Text.AlignRight
            verticalAlignment: Text.AlignVCenter
            fontSizeMode: Text.Fit
            minimumPixelSize: 30 * textScale
            elide: Text.ElideLeft
        }
    }

    // Button grid
    Grid {
        id: buttonGrid
        anchors.top: displayArea.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: homeIndicator.top
        anchors.margins: 20 * textScale
        anchors.topMargin: 30 * textScale
        anchors.bottomMargin: 120 * textScale

        columns: 4
        rowSpacing: 15 * textScale
        columnSpacing: 15 * textScale

        property real buttonWidth: (width - columnSpacing * (columns - 1)) / columns
        property real buttonHeight: (height - rowSpacing * 4) / 5

        // Row 1: C, +/-, /, *
        CalcButton {
            width: buttonGrid.buttonWidth
            height: buttonGrid.buttonHeight
            text: "C"
            textScale: root.textScale
            isOperation: true
            onClicked: clear()
        }
        CalcButton {
            width: buttonGrid.buttonWidth
            height: buttonGrid.buttonHeight
            text: "+/-"
            textScale: root.textScale
            isOperation: true
            onClicked: toggleSign()
        }
        CalcButton {
            width: buttonGrid.buttonWidth
            height: buttonGrid.buttonHeight
            text: "/"
            textScale: root.textScale
            isOperation: true
            onClicked: setOperation("/")
        }
        CalcButton {
            width: buttonGrid.buttonWidth
            height: buttonGrid.buttonHeight
            text: "*"
            textScale: root.textScale
            isOperation: true
            onClicked: setOperation("*")
        }

        // Row 2: 7, 8, 9, -
        CalcButton {
            width: buttonGrid.buttonWidth
            height: buttonGrid.buttonHeight
            text: "7"
            textScale: root.textScale
            onClicked: appendDigit("7")
        }
        CalcButton {
            width: buttonGrid.buttonWidth
            height: buttonGrid.buttonHeight
            text: "8"
            textScale: root.textScale
            onClicked: appendDigit("8")
        }
        CalcButton {
            width: buttonGrid.buttonWidth
            height: buttonGrid.buttonHeight
            text: "9"
            textScale: root.textScale
            onClicked: appendDigit("9")
        }
        CalcButton {
            width: buttonGrid.buttonWidth
            height: buttonGrid.buttonHeight
            text: "-"
            textScale: root.textScale
            isOperation: true
            onClicked: setOperation("-")
        }

        // Row 3: 4, 5, 6, +
        CalcButton {
            width: buttonGrid.buttonWidth
            height: buttonGrid.buttonHeight
            text: "4"
            textScale: root.textScale
            onClicked: appendDigit("4")
        }
        CalcButton {
            width: buttonGrid.buttonWidth
            height: buttonGrid.buttonHeight
            text: "5"
            textScale: root.textScale
            onClicked: appendDigit("5")
        }
        CalcButton {
            width: buttonGrid.buttonWidth
            height: buttonGrid.buttonHeight
            text: "6"
            textScale: root.textScale
            onClicked: appendDigit("6")
        }
        CalcButton {
            width: buttonGrid.buttonWidth
            height: buttonGrid.buttonHeight
            text: "+"
            textScale: root.textScale
            isOperation: true
            onClicked: setOperation("+")
        }

        // Row 4: 1, 2, 3, (blank for layout)
        CalcButton {
            width: buttonGrid.buttonWidth
            height: buttonGrid.buttonHeight
            text: "1"
            textScale: root.textScale
            onClicked: appendDigit("1")
        }
        CalcButton {
            width: buttonGrid.buttonWidth
            height: buttonGrid.buttonHeight
            text: "2"
            textScale: root.textScale
            onClicked: appendDigit("2")
        }
        CalcButton {
            width: buttonGrid.buttonWidth
            height: buttonGrid.buttonHeight
            text: "3"
            textScale: root.textScale
            onClicked: appendDigit("3")
        }

        // Equals button (spans 2 rows visually)
        CalcButton {
            width: buttonGrid.buttonWidth
            height: buttonGrid.buttonHeight * 2 + buttonGrid.rowSpacing
            text: "="
            textScale: root.textScale
            isOperation: true
            isEquals: true
            onClicked: calculate()
        }

        // Row 5: 0 (2 cols), .
        CalcButton {
            width: buttonGrid.buttonWidth * 2 + buttonGrid.columnSpacing
            height: buttonGrid.buttonHeight
            text: "0"
            textScale: root.textScale
            onClicked: appendDigit("0")
        }
        CalcButton {
            width: buttonGrid.buttonWidth
            height: buttonGrid.buttonHeight
            text: "."
            textScale: root.textScale
            onClicked: appendDecimal()
        }
    }

    // Floating back button
    Rectangle {
        id: backButton
        anchors.right: parent.right
        anchors.bottom: homeIndicator.top
        anchors.margins: 30 * textScale
        width: 72 * textScale
        height: 72 * textScale
        radius: 36 * textScale
        color: backButtonArea.pressed ? "#d93550" : "#e94560"

        Text {
            anchors.centerIn: parent
            text: "<"
            font.pixelSize: 32 * textScale
            font.weight: Font.Bold
            color: "white"
        }

        MouseArea {
            id: backButtonArea
            anchors.fill: parent
            onClicked: Qt.quit()
        }
    }

    // Home indicator bar
    Rectangle {
        id: homeIndicator
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottomMargin: 10 * textScale
        width: 200 * textScale
        height: 8 * textScale
        radius: 4 * textScale
        color: "#333344"
    }
}

// Calculator button component
component CalcButton: Rectangle {
    id: button
    required property string text
    required property real textScale
    property bool isOperation: false
    property bool isEquals: false
    signal clicked()

    color: {
        if (buttonArea.pressed) {
            return isEquals ? "#d93550" : (isOperation ? "#555577" : "#2a2a3e")
        }
        return isEquals ? "#e94560" : (isOperation ? "#3a3a4e" : "#1a1a2e")
    }
    radius: 12 * textScale
    border.color: "#2a2a4e"
    border.width: 2

    Text {
        anchors.centerIn: parent
        text: button.text
        color: "white"
        font.pixelSize: 36 * textScale
        font.weight: Font.Bold
    }

    MouseArea {
        id: buttonArea
        anchors.fill: parent
        onClicked: button.clicked()
    }
}
