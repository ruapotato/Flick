import QtQuick 2.15
import QtQuick.Window 2.15

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

    // Display
    Rectangle {
        id: displayArea
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 280
        color: "#0f0f14"

        Text {
            anchors.fill: parent
            anchors.margins: 32
            text: display
            color: "#ffffff"
            font.pixelSize: 72
            font.weight: Font.Bold
            horizontalAlignment: Text.AlignRight
            verticalAlignment: Text.AlignVCenter
            fontSizeMode: Text.Fit
            minimumPixelSize: 32
        }
    }

    // Button grid
    Grid {
        id: buttonGrid
        anchors.top: displayArea.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 16
        anchors.bottomMargin: 200

        columns: 4
        rowSpacing: 12
        columnSpacing: 12

        property real btnW: (width - columnSpacing * 3) / 4
        property real btnH: (height - rowSpacing * 4) / 5

        // Row 1
        Rectangle {
            width: buttonGrid.btnW; height: buttonGrid.btnH; radius: 16
            color: r1c.pressed ? "#555577" : "#3a3a4e"
            Text { anchors.centerIn: parent; text: "C"; color: "#fff"; font.pixelSize: 36; font.bold: true }
            MouseArea { id: r1c; anchors.fill: parent; onClicked: clear() }
        }
        Rectangle {
            width: buttonGrid.btnW; height: buttonGrid.btnH; radius: 16
            color: r1pm.pressed ? "#555577" : "#3a3a4e"
            Text { anchors.centerIn: parent; text: "+/-"; color: "#fff"; font.pixelSize: 32; font.bold: true }
            MouseArea { id: r1pm; anchors.fill: parent; onClicked: toggleSign() }
        }
        Rectangle {
            width: buttonGrid.btnW; height: buttonGrid.btnH; radius: 16
            color: r1d.pressed ? "#555577" : "#3a3a4e"
            Text { anchors.centerIn: parent; text: "/"; color: "#fff"; font.pixelSize: 40; font.bold: true }
            MouseArea { id: r1d; anchors.fill: parent; onClicked: setOperation("/") }
        }
        Rectangle {
            width: buttonGrid.btnW; height: buttonGrid.btnH; radius: 16
            color: r1m.pressed ? "#555577" : "#3a3a4e"
            Text { anchors.centerIn: parent; text: "*"; color: "#fff"; font.pixelSize: 40; font.bold: true }
            MouseArea { id: r1m; anchors.fill: parent; onClicked: setOperation("*") }
        }

        // Row 2
        Rectangle {
            width: buttonGrid.btnW; height: buttonGrid.btnH; radius: 16
            color: r27.pressed ? "#2a2a3e" : "#1a1a2e"
            Text { anchors.centerIn: parent; text: "7"; color: "#fff"; font.pixelSize: 40; font.bold: true }
            MouseArea { id: r27; anchors.fill: parent; onClicked: appendDigit("7") }
        }
        Rectangle {
            width: buttonGrid.btnW; height: buttonGrid.btnH; radius: 16
            color: r28.pressed ? "#2a2a3e" : "#1a1a2e"
            Text { anchors.centerIn: parent; text: "8"; color: "#fff"; font.pixelSize: 40; font.bold: true }
            MouseArea { id: r28; anchors.fill: parent; onClicked: appendDigit("8") }
        }
        Rectangle {
            width: buttonGrid.btnW; height: buttonGrid.btnH; radius: 16
            color: r29.pressed ? "#2a2a3e" : "#1a1a2e"
            Text { anchors.centerIn: parent; text: "9"; color: "#fff"; font.pixelSize: 40; font.bold: true }
            MouseArea { id: r29; anchors.fill: parent; onClicked: appendDigit("9") }
        }
        Rectangle {
            width: buttonGrid.btnW; height: buttonGrid.btnH; radius: 16
            color: r2s.pressed ? "#555577" : "#3a3a4e"
            Text { anchors.centerIn: parent; text: "-"; color: "#fff"; font.pixelSize: 48; font.bold: true }
            MouseArea { id: r2s; anchors.fill: parent; onClicked: setOperation("-") }
        }

        // Row 3
        Rectangle {
            width: buttonGrid.btnW; height: buttonGrid.btnH; radius: 16
            color: r34.pressed ? "#2a2a3e" : "#1a1a2e"
            Text { anchors.centerIn: parent; text: "4"; color: "#fff"; font.pixelSize: 40; font.bold: true }
            MouseArea { id: r34; anchors.fill: parent; onClicked: appendDigit("4") }
        }
        Rectangle {
            width: buttonGrid.btnW; height: buttonGrid.btnH; radius: 16
            color: r35.pressed ? "#2a2a3e" : "#1a1a2e"
            Text { anchors.centerIn: parent; text: "5"; color: "#fff"; font.pixelSize: 40; font.bold: true }
            MouseArea { id: r35; anchors.fill: parent; onClicked: appendDigit("5") }
        }
        Rectangle {
            width: buttonGrid.btnW; height: buttonGrid.btnH; radius: 16
            color: r36.pressed ? "#2a2a3e" : "#1a1a2e"
            Text { anchors.centerIn: parent; text: "6"; color: "#fff"; font.pixelSize: 40; font.bold: true }
            MouseArea { id: r36; anchors.fill: parent; onClicked: appendDigit("6") }
        }
        Rectangle {
            width: buttonGrid.btnW; height: buttonGrid.btnH; radius: 16
            color: r3p.pressed ? "#555577" : "#3a3a4e"
            Text { anchors.centerIn: parent; text: "+"; color: "#fff"; font.pixelSize: 44; font.bold: true }
            MouseArea { id: r3p; anchors.fill: parent; onClicked: setOperation("+") }
        }

        // Row 4
        Rectangle {
            width: buttonGrid.btnW; height: buttonGrid.btnH; radius: 16
            color: r41.pressed ? "#2a2a3e" : "#1a1a2e"
            Text { anchors.centerIn: parent; text: "1"; color: "#fff"; font.pixelSize: 40; font.bold: true }
            MouseArea { id: r41; anchors.fill: parent; onClicked: appendDigit("1") }
        }
        Rectangle {
            width: buttonGrid.btnW; height: buttonGrid.btnH; radius: 16
            color: r42.pressed ? "#2a2a3e" : "#1a1a2e"
            Text { anchors.centerIn: parent; text: "2"; color: "#fff"; font.pixelSize: 40; font.bold: true }
            MouseArea { id: r42; anchors.fill: parent; onClicked: appendDigit("2") }
        }
        Rectangle {
            width: buttonGrid.btnW; height: buttonGrid.btnH; radius: 16
            color: r43.pressed ? "#2a2a3e" : "#1a1a2e"
            Text { anchors.centerIn: parent; text: "3"; color: "#fff"; font.pixelSize: 40; font.bold: true }
            MouseArea { id: r43; anchors.fill: parent; onClicked: appendDigit("3") }
        }
        Rectangle {
            width: buttonGrid.btnW; height: buttonGrid.btnH * 2 + buttonGrid.rowSpacing; radius: 16
            color: r4eq.pressed ? "#c23a50" : "#e94560"
            Text { anchors.centerIn: parent; text: "="; color: "#fff"; font.pixelSize: 48; font.bold: true }
            MouseArea { id: r4eq; anchors.fill: parent; onClicked: calculate() }
        }

        // Row 5
        Rectangle {
            width: buttonGrid.btnW * 2 + buttonGrid.columnSpacing; height: buttonGrid.btnH; radius: 16
            color: r50.pressed ? "#2a2a3e" : "#1a1a2e"
            Text { anchors.centerIn: parent; text: "0"; color: "#fff"; font.pixelSize: 40; font.bold: true }
            MouseArea { id: r50; anchors.fill: parent; onClicked: appendDigit("0") }
        }
        Rectangle {
            width: buttonGrid.btnW; height: buttonGrid.btnH; radius: 16
            color: r5dot.pressed ? "#2a2a3e" : "#1a1a2e"
            Text { anchors.centerIn: parent; text: "."; color: "#fff"; font.pixelSize: 48; font.bold: true }
            MouseArea { id: r5dot; anchors.fill: parent; onClicked: appendDecimal() }
        }
    }

    // Back button
    Rectangle {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 24
        anchors.bottomMargin: 120
        width: 72
        height: 72
        radius: 36
        color: backMouse.pressed ? "#c23a50" : "#e94560"
        z: 10

        Text {
            anchors.centerIn: parent
            text: "X"
            font.pixelSize: 28
            font.weight: Font.Bold
            color: "#ffffff"
        }

        MouseArea {
            id: backMouse
            anchors.fill: parent
            onClicked: Qt.quit()
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
