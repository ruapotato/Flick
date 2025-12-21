import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtQml 2.15

Page {
    id: securityPage

    property int selectedMethod: 1  // 0=PIN, 1=Password, 2=Pattern, 3=None (default to password)
    property string configPath: "/home/droidian/.local/state/flick/lock_config.json"

    // Load current config on startup
    Component.onCompleted: {
        loadConfig()
    }

    function loadConfig() {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file://" + configPath, false)
        try {
            xhr.send()
            if (xhr.status === 200) {
                var config = JSON.parse(xhr.responseText)
                if (config.method === "pin") selectedMethod = 0
                else if (config.method === "password") selectedMethod = 1
                else if (config.method === "pattern") selectedMethod = 2
                else if (config.method === "none") selectedMethod = 3
            }
        } catch (e) {
            console.log("Could not load config: " + e)
            selectedMethod = 1  // Default to password
        }
    }

    function saveConfig(method) {
        var methodStr = "password"
        if (method === 0) methodStr = "pin"
        else if (method === 1) methodStr = "password"
        else if (method === 2) methodStr = "pattern"
        else if (method === 3) methodStr = "none"

        var config = { "method": methodStr }
        var configStr = JSON.stringify(config)

        // Use a helper process to write the file
        var proc = Qt.createQmlObject('import QtQuick 2.15; import Qt.labs.platform 1.1; FileDialog {}', securityPage)
        // Since we can't write files directly from QML, we'll use a shell command
        var writeCmd = "mkdir -p $(dirname " + configPath + ") && echo '" + configStr + "' > " + configPath
        console.log("Saving lock config: " + configStr)

        // Execute via Process (requires Qt.labs.platform or similar)
        // For now, we'll spawn a helper
        Qt.openUrlExternally("file:///usr/bin/sh -c \"" + writeCmd + "\"")
    }

    function applyMethod(method) {
        if (method === 0) {
            // PIN - show PIN setup dialog
            pinSetupDialog.open()
        } else if (method === 2) {
            // Pattern - show pattern setup dialog
            patternSetupDialog.open()
        } else {
            // Password or None - just save directly
            selectedMethod = method
            saveConfigDirect(method)
        }
    }

    function saveConfigDirect(method, patternNodes) {
        var methodStr = "password"
        if (method === 0) methodStr = "pin"
        else if (method === 1) methodStr = "password"
        else if (method === 2) methodStr = "pattern"
        else if (method === 3) methodStr = "none"

        console.log("Saving lock method: " + methodStr)

        // Use Qt.callLater to ensure we're not blocking
        Qt.callLater(function() {
            var helperPath = "/home/droidian/Flick/apps/settings/flick-settings-ctl"

            if (method === 2 && patternNodes && patternNodes.length >= 4) {
                // Pattern mode - use set-pattern command with the pattern
                var patternStr = patternNodes.join(",")
                console.log("Saving pattern: " + patternStr)

                // Write pattern to temp file for helper to read
                var xhr = new XMLHttpRequest()
                xhr.open("PUT", "file:///tmp/flick-pattern-pending", false)
                try {
                    xhr.send(patternStr)
                    console.log("Pattern written to temp file: " + patternStr)
                } catch (e) {
                    console.log("Could not write pattern: " + e)
                }
            } else {
                // Non-pattern mode - write method marker
                var xhr = new XMLHttpRequest()
                xhr.open("PUT", "file:///tmp/flick-lock-config-pending", false)
                try {
                    xhr.send(methodStr)
                } catch (e) {
                    console.log("Could not write marker: " + e)
                }
            }
        })
    }

    background: Rectangle {
        color: "#0a0a0f"
    }

    // PIN Setup Dialog
    Popup {
        id: pinSetupDialog
        anchors.centerIn: parent
        width: parent.width * 0.9
        height: 500
        modal: true
        closePolicy: Popup.CloseOnEscape

        property string enteredPin: ""
        property string confirmPin: ""
        property bool confirming: false

        background: Rectangle {
            color: "#1a1a24"
            radius: 24
            border.color: "#e94560"
            border.width: 2
        }

        contentItem: Column {
            spacing: 20
            padding: 24

            Text {
                text: pinSetupDialog.confirming ? "Confirm PIN" : "Enter New PIN"
                font.pixelSize: 24
                font.weight: Font.Medium
                color: "#ffffff"
                anchors.horizontalCenter: parent.horizontalCenter
            }

            Text {
                text: pinSetupDialog.confirming ? "Enter the same PIN again" : "Enter a 4-6 digit PIN"
                font.pixelSize: 14
                color: "#888899"
                anchors.horizontalCenter: parent.horizontalCenter
            }

            // PIN dots
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 16

                Repeater {
                    model: 6
                    Rectangle {
                        width: 16
                        height: 16
                        radius: 8
                        color: index < (pinSetupDialog.confirming ? pinSetupDialog.confirmPin.length : pinSetupDialog.enteredPin.length) ? "#e94560" : "transparent"
                        border.width: 2
                        border.color: "#666677"
                    }
                }
            }

            // Number pad
            Grid {
                columns: 3
                spacing: 12
                anchors.horizontalCenter: parent.horizontalCenter

                Repeater {
                    model: ["1", "2", "3", "4", "5", "6", "7", "8", "9", "", "0", "⌫"]

                    Rectangle {
                        width: 70
                        height: 70
                        radius: 35
                        color: modelData === "" ? "transparent" : (pinKeyMouse.pressed ? "#3a3a4e" : "#2a2a3e")
                        visible: modelData !== ""

                        Text {
                            anchors.centerIn: parent
                            text: modelData
                            font.pixelSize: modelData === "⌫" ? 24 : 28
                            color: "#ffffff"
                        }

                        MouseArea {
                            id: pinKeyMouse
                            anchors.fill: parent
                            enabled: modelData !== ""
                            onClicked: {
                                if (modelData === "⌫") {
                                    if (pinSetupDialog.confirming) {
                                        pinSetupDialog.confirmPin = pinSetupDialog.confirmPin.slice(0, -1)
                                    } else {
                                        pinSetupDialog.enteredPin = pinSetupDialog.enteredPin.slice(0, -1)
                                    }
                                } else {
                                    if (pinSetupDialog.confirming) {
                                        if (pinSetupDialog.confirmPin.length < 6) {
                                            pinSetupDialog.confirmPin += modelData
                                        }
                                    } else {
                                        if (pinSetupDialog.enteredPin.length < 6) {
                                            pinSetupDialog.enteredPin += modelData
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 16

                Rectangle {
                    width: 100
                    height: 44
                    radius: 22
                    color: cancelPinMouse.pressed ? "#3a3a4e" : "#2a2a3e"

                    Text {
                        anchors.centerIn: parent
                        text: "Cancel"
                        color: "#ffffff"
                        font.pixelSize: 16
                    }

                    MouseArea {
                        id: cancelPinMouse
                        anchors.fill: parent
                        onClicked: {
                            pinSetupDialog.enteredPin = ""
                            pinSetupDialog.confirmPin = ""
                            pinSetupDialog.confirming = false
                            pinSetupDialog.close()
                        }
                    }
                }

                Rectangle {
                    width: 100
                    height: 44
                    radius: 22
                    color: confirmPinMouse.pressed ? "#c23a50" : "#e94560"
                    opacity: (pinSetupDialog.confirming ? pinSetupDialog.confirmPin.length : pinSetupDialog.enteredPin.length) >= 4 ? 1.0 : 0.5

                    Text {
                        anchors.centerIn: parent
                        text: pinSetupDialog.confirming ? "Save" : "Next"
                        color: "#ffffff"
                        font.pixelSize: 16
                        font.weight: Font.Medium
                    }

                    MouseArea {
                        id: confirmPinMouse
                        anchors.fill: parent
                        enabled: (pinSetupDialog.confirming ? pinSetupDialog.confirmPin.length : pinSetupDialog.enteredPin.length) >= 4
                        onClicked: {
                            if (!pinSetupDialog.confirming) {
                                pinSetupDialog.confirming = true
                            } else {
                                if (pinSetupDialog.enteredPin === pinSetupDialog.confirmPin) {
                                    // PINs match - save config
                                    selectedMethod = 0
                                    saveConfigDirect(0)
                                    pinSetupDialog.enteredPin = ""
                                    pinSetupDialog.confirmPin = ""
                                    pinSetupDialog.confirming = false
                                    pinSetupDialog.close()
                                } else {
                                    // PINs don't match - reset
                                    pinSetupDialog.confirmPin = ""
                                    pinSetupDialog.confirming = false
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Pattern Setup Dialog
    Popup {
        id: patternSetupDialog
        anchors.centerIn: parent
        width: parent.width * 0.95
        height: parent.height * 0.85
        modal: true
        closePolicy: Popup.CloseOnEscape

        property var enteredPattern: []
        property var confirmPattern: []
        property bool confirming: false
        property int patternCount: 0  // Force UI updates

        function addToPattern(idx) {
            var pattern = confirming ? confirmPattern.slice() : enteredPattern.slice()
            if (pattern.indexOf(idx) < 0 && pattern.length < 9) {
                pattern.push(idx)
                if (confirming) {
                    confirmPattern = pattern
                } else {
                    enteredPattern = pattern
                }
                patternCount = pattern.length  // Trigger UI update
            }
        }

        function isSelected(idx) {
            var pattern = confirming ? confirmPattern : enteredPattern
            return pattern.indexOf(idx) >= 0
        }

        function currentLength() {
            return confirming ? confirmPattern.length : enteredPattern.length
        }

        background: Rectangle {
            color: "#1a1a24"
            radius: 24
            border.color: "#e94560"
            border.width: 2
        }

        contentItem: Column {
            spacing: 32
            padding: 32

            Text {
                text: patternSetupDialog.confirming ? "Confirm Pattern" : "Draw New Pattern"
                font.pixelSize: 28
                font.weight: Font.Medium
                color: "#ffffff"
                anchors.horizontalCenter: parent.horizontalCenter
            }

            Text {
                text: patternSetupDialog.confirming ? "Tap the same dots again" : "Tap at least 4 dots"
                font.pixelSize: 16
                color: "#888899"
                anchors.horizontalCenter: parent.horizontalCenter
            }

            // Pattern grid - much larger with drag support
            Item {
                id: patternGridContainer
                width: 320
                height: 320
                anchors.horizontalCenter: parent.horizontalCenter

                // Store dot positions for hit testing during drag
                property var dotCenters: []
                property real dotSize: 80
                property real gridSpacing: 24
                property real gridStartX: (width - (3 * dotSize + 2 * gridSpacing)) / 2
                property real gridStartY: (height - (3 * dotSize + 2 * gridSpacing)) / 2

                Component.onCompleted: {
                    // Calculate dot centers for hit testing
                    var centers = []
                    for (var row = 0; row < 3; row++) {
                        for (var col = 0; col < 3; col++) {
                            var cx = gridStartX + col * (dotSize + gridSpacing) + dotSize / 2
                            var cy = gridStartY + row * (dotSize + gridSpacing) + dotSize / 2
                            centers.push({x: cx, y: cy, index: row * 3 + col})
                        }
                    }
                    dotCenters = centers
                }

                // Check if a point is inside a dot (with tolerance)
                function hitTest(px, py) {
                    var hitRadius = dotSize / 2 + 10  // Extra tolerance
                    for (var i = 0; i < dotCenters.length; i++) {
                        var dot = dotCenters[i]
                        var dx = px - dot.x
                        var dy = py - dot.y
                        if (dx * dx + dy * dy <= hitRadius * hitRadius) {
                            return dot.index
                        }
                    }
                    return -1
                }

                Grid {
                    id: patternGrid
                    anchors.centerIn: parent
                    columns: 3
                    spacing: 24

                    Repeater {
                        model: 9

                        Rectangle {
                            id: patternDot
                            width: 80
                            height: 80
                            radius: 40
                            color: patternSetupDialog.isSelected(index) ? "#e94560" : "#3a3a4e"
                            border.width: 4
                            border.color: patternSetupDialog.isSelected(index) ? "#ff6b8a" : "#555566"

                            // Dot number indicator
                            Text {
                                anchors.centerIn: parent
                                text: {
                                    var pattern = patternSetupDialog.confirming ? patternSetupDialog.confirmPattern : patternSetupDialog.enteredPattern
                                    var pos = pattern.indexOf(index)
                                    return pos >= 0 ? (pos + 1).toString() : ""
                                }
                                font.pixelSize: 24
                                font.weight: Font.Bold
                                color: "#ffffff"
                            }

                            // Visual feedback on selection
                            Behavior on color { ColorAnimation { duration: 100 } }
                            Behavior on border.color { ColorAnimation { duration: 100 } }
                        }
                    }
                }

                // Drag-enabled MouseArea covering the entire grid
                MouseArea {
                    anchors.fill: parent

                    onPressed: {
                        var hitIdx = patternGridContainer.hitTest(mouse.x, mouse.y)
                        if (hitIdx >= 0) {
                            patternSetupDialog.addToPattern(hitIdx)
                        }
                    }

                    onPositionChanged: {
                        var hitIdx = patternGridContainer.hitTest(mouse.x, mouse.y)
                        if (hitIdx >= 0) {
                            patternSetupDialog.addToPattern(hitIdx)
                        }
                    }
                }
            }

            Text {
                text: "Dots selected: " + patternSetupDialog.currentLength() + " / 9"
                font.pixelSize: 18
                color: patternSetupDialog.currentLength() >= 4 ? "#4ade80" : "#888899"
                anchors.horizontalCenter: parent.horizontalCenter
            }

            // Buttons row
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 20

                Rectangle {
                    width: 90
                    height: 50
                    radius: 25
                    color: clearPatternMouse.pressed ? "#3a3a4e" : "#2a2a3e"

                    Text {
                        anchors.centerIn: parent
                        text: "Clear"
                        color: "#ffffff"
                        font.pixelSize: 16
                    }

                    MouseArea {
                        id: clearPatternMouse
                        anchors.fill: parent
                        onClicked: {
                            if (patternSetupDialog.confirming) {
                                patternSetupDialog.confirmPattern = []
                            } else {
                                patternSetupDialog.enteredPattern = []
                            }
                            patternSetupDialog.patternCount = 0
                        }
                    }
                }

                Rectangle {
                    width: 90
                    height: 50
                    radius: 25
                    color: cancelPatternMouse.pressed ? "#3a3a4e" : "#2a2a3e"

                    Text {
                        anchors.centerIn: parent
                        text: "Cancel"
                        color: "#ffffff"
                        font.pixelSize: 16
                    }

                    MouseArea {
                        id: cancelPatternMouse
                        anchors.fill: parent
                        onClicked: {
                            patternSetupDialog.enteredPattern = []
                            patternSetupDialog.confirmPattern = []
                            patternSetupDialog.confirming = false
                            patternSetupDialog.patternCount = 0
                            patternSetupDialog.close()
                        }
                    }
                }

                Rectangle {
                    width: 90
                    height: 50
                    radius: 25
                    color: confirmPatternMouse.pressed ? "#c23a50" : "#e94560"
                    opacity: patternSetupDialog.currentLength() >= 4 ? 1.0 : 0.4

                    Text {
                        anchors.centerIn: parent
                        text: patternSetupDialog.confirming ? "Save" : "Next"
                        color: "#ffffff"
                        font.pixelSize: 16
                        font.weight: Font.Medium
                    }

                    MouseArea {
                        id: confirmPatternMouse
                        anchors.fill: parent
                        enabled: patternSetupDialog.currentLength() >= 4
                        onClicked: {
                            if (!patternSetupDialog.confirming) {
                                patternSetupDialog.confirming = true
                                patternSetupDialog.patternCount = 0
                            } else {
                                if (JSON.stringify(patternSetupDialog.enteredPattern) === JSON.stringify(patternSetupDialog.confirmPattern)) {
                                    // Patterns match - save config with pattern nodes
                                    selectedMethod = 2
                                    saveConfigDirect(2, patternSetupDialog.enteredPattern)
                                    patternSetupDialog.enteredPattern = []
                                    patternSetupDialog.confirmPattern = []
                                    patternSetupDialog.confirming = false
                                    patternSetupDialog.patternCount = 0
                                    patternSetupDialog.close()
                                } else {
                                    // Patterns don't match - show error and reset confirm
                                    patternSetupDialog.confirmPattern = []
                                    patternSetupDialog.confirming = false
                                    patternSetupDialog.patternCount = 0
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Hero section - compact
    Rectangle {
        id: heroSection
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 180
        color: "transparent"

        // Ambient glow
        Rectangle {
            anchors.centerIn: parent
            width: 280
            height: 180
            radius: 140
            color: "#4a1a3a"
            opacity: 0.2
        }

        Column {
            anchors.centerIn: parent
            spacing: 12

            // Shield icon - smaller
            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 80
                height: 80

                // Shield glow
                Rectangle {
                    anchors.centerIn: parent
                    width: 100
                    height: 100
                    radius: 50
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
                    width: 70
                    height: 70
                    radius: 35
                    color: "#4a1a3a"
                    border.color: "#e94560"
                    border.width: 2

                    Text {
                        anchors.centerIn: parent
                        text: selectedMethod === 3 ? "🔓" : "🔐"
                        font.pixelSize: 32
                    }
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Security"
                font.pixelSize: 36
                font.weight: Font.ExtraLight
                font.letterSpacing: 4
                color: "#ffffff"
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: selectedMethod === 3 ? "DEVICE UNLOCKED" : "DEVICE PROTECTED"
                font.pixelSize: 11
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
            spacing: 10

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
                height: 76
                radius: 20
                color: pinMouse.pressed ? "#1e1e2e" : "#14141e"
                border.color: selectedMethod === 0 ? "#e94560" : "#1a1a2e"
                border.width: selectedMethod === 0 ? 2 : 1

                Behavior on border.color { ColorAnimation { duration: 150 } }

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 12

                    Rectangle {
                        Layout.preferredWidth: 48
                        Layout.preferredHeight: 48
                        radius: 12
                        color: selectedMethod === 0 ? "#3a1a2a" : "#1a1a28"

                        Text {
                            anchors.centerIn: parent
                            text: "🔢"
                            font.pixelSize: 24
                        }
                    }

                    Column {
                        Layout.fillWidth: true
                        spacing: 4

                        Text {
                            text: "PIN"
                            font.pixelSize: 18
                            font.weight: Font.Medium
                            color: "#ffffff"
                        }

                        Text {
                            text: "4-6 digit numeric code"
                            font.pixelSize: 12
                            color: "#666677"
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: 24
                        Layout.preferredHeight: 24
                        radius: 12
                        color: "transparent"
                        border.color: selectedMethod === 0 ? "#e94560" : "#3a3a4e"
                        border.width: 2

                        Rectangle {
                            anchors.centerIn: parent
                            width: selectedMethod === 0 ? 12 : 0
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
                    onClicked: applyMethod(0)
                }
            }

            // Password option
            Rectangle {
                width: methodsColumn.width
                height: 76
                radius: 20
                color: passwordMouse.pressed ? "#1e1e2e" : "#14141e"
                border.color: selectedMethod === 1 ? "#e94560" : "#1a1a2e"
                border.width: selectedMethod === 1 ? 2 : 1

                Behavior on border.color { ColorAnimation { duration: 150 } }

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 12

                    Rectangle {
                        Layout.preferredWidth: 48
                        Layout.preferredHeight: 48
                        radius: 12
                        color: selectedMethod === 1 ? "#3a1a2a" : "#1a1a28"

                        Text {
                            anchors.centerIn: parent
                            text: "🔤"
                            font.pixelSize: 24
                        }
                    }

                    Column {
                        Layout.fillWidth: true
                        spacing: 4

                        Text {
                            text: "Password"
                            font.pixelSize: 18
                            font.weight: Font.Medium
                            color: "#ffffff"
                        }

                        Text {
                            text: "System password for unlock"
                            font.pixelSize: 12
                            color: "#666677"
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: 24
                        Layout.preferredHeight: 24
                        radius: 12
                        color: "transparent"
                        border.color: selectedMethod === 1 ? "#e94560" : "#3a3a4e"
                        border.width: 2

                        Rectangle {
                            anchors.centerIn: parent
                            width: selectedMethod === 1 ? 12 : 0
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
                    onClicked: applyMethod(1)
                }
            }

            // Pattern option
            Rectangle {
                width: methodsColumn.width
                height: 76
                radius: 20
                color: patternMouse.pressed ? "#1e1e2e" : "#14141e"
                border.color: selectedMethod === 2 ? "#e94560" : "#1a1a2e"
                border.width: selectedMethod === 2 ? 2 : 1

                Behavior on border.color { ColorAnimation { duration: 150 } }

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 12

                    Rectangle {
                        Layout.preferredWidth: 48
                        Layout.preferredHeight: 48
                        radius: 12
                        color: selectedMethod === 2 ? "#3a1a2a" : "#1a1a28"

                        // Pattern grid preview
                        Grid {
                            anchors.centerIn: parent
                            columns: 3
                            spacing: 5

                            Repeater {
                                model: 9
                                Rectangle {
                                    width: 8
                                    height: 8
                                    radius: 4
                                    color: (index === 0 || index === 4 || index === 8) ? "#e94560" : "#444455"
                                }
                            }
                        }
                    }

                    Column {
                        Layout.fillWidth: true
                        spacing: 4

                        Text {
                            text: "Pattern"
                            font.pixelSize: 18
                            font.weight: Font.Medium
                            color: "#ffffff"
                        }

                        Text {
                            text: "Draw a pattern to unlock"
                            font.pixelSize: 12
                            color: "#666677"
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: 24
                        Layout.preferredHeight: 24
                        radius: 12
                        color: "transparent"
                        border.color: selectedMethod === 2 ? "#e94560" : "#3a3a4e"
                        border.width: 2

                        Rectangle {
                            anchors.centerIn: parent
                            width: selectedMethod === 2 ? 12 : 0
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
                    onClicked: applyMethod(2)
                }
            }

            // None option
            Rectangle {
                width: methodsColumn.width
                height: 76
                radius: 20
                color: noneMouse.pressed ? "#1e1e2e" : "#14141e"
                border.color: selectedMethod === 3 ? "#cc8844" : "#1a1a2e"
                border.width: selectedMethod === 3 ? 2 : 1

                Behavior on border.color { ColorAnimation { duration: 150 } }

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 12

                    Rectangle {
                        Layout.preferredWidth: 48
                        Layout.preferredHeight: 48
                        radius: 12
                        color: selectedMethod === 3 ? "#3a2a1a" : "#1a1a28"

                        Text {
                            anchors.centerIn: parent
                            text: "🔓"
                            font.pixelSize: 24
                        }
                    }

                    Column {
                        Layout.fillWidth: true
                        spacing: 4

                        Text {
                            text: "None"
                            font.pixelSize: 18
                            font.weight: Font.Medium
                            color: "#ffffff"
                        }

                        Text {
                            text: "Swipe to unlock (not secure)"
                            font.pixelSize: 12
                            color: "#cc8844"
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: 24
                        Layout.preferredHeight: 24
                        radius: 12
                        color: "transparent"
                        border.color: selectedMethod === 3 ? "#cc8844" : "#3a3a4e"
                        border.width: 2

                        Rectangle {
                            anchors.centerIn: parent
                            width: selectedMethod === 3 ? 12 : 0
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
                    onClicked: applyMethod(3)
                }
            }

            Item { height: 12 }

            // Info card - more compact
            Rectangle {
                width: methodsColumn.width
                height: 56
                radius: 16
                color: "#1a1a1a"
                border.color: "#2a2a2e"
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 10

                    Text {
                        text: "ℹ️"
                        font.pixelSize: 18
                    }

                    Text {
                        text: "Changes take effect on next lock"
                        font.pixelSize: 13
                        color: "#777788"
                        Layout.fillWidth: true
                    }
                }
            }

            Item { height: 16 }
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
