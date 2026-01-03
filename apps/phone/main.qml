import QtQuick 2.15
import QtQuick.Window 2.15
import QtQuick.Controls 2.15
import "../shared"

Window {
    id: root
    visible: true
    width: 720
    height: 1600
    title: "Phone"
    color: "#0a0a0f"

    // Don't use shell textScale - phone dialpad has fixed dimensions
    property real textScale: 1.0  // Fixed, don't load from config
    property color accentColor: "#e94560"
    property color accentPressed: Qt.darker(accentColor, 1.2)
    property string phoneNumber: ""
    property bool inCall: false
    property string callState: "idle"  // idle, dialing, incoming, active
    property string callerNumber: ""
    property int callDuration: 0
    property int currentTab: 0  // 0 = dialpad, 1 = history
    property bool speakerOn: false
    property bool muteOn: false

    // Call history model
    ListModel {
        id: historyModel
    }

    Component.onCompleted: {
        loadConfig()
        loadHistory()
    }

    function loadConfig() {
        // Phone app uses fixed scaling - don't load textScale from shell config
        // But load accent color
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file://" + Theme.stateDir + "/display_config.json", false)
        try {
            xhr.send()
            if (xhr.status === 200 || xhr.status === 0) {
                var config = JSON.parse(xhr.responseText)
                if (config.accent_color && config.accent_color !== "") {
                    accentColor = config.accent_color
                }
            }
        } catch (e) {}
    }

    function loadHistory() {
        var historyPath = Theme.stateDir + "/call_history.json"
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file://" + historyPath, false)
        try {
            xhr.send()
            if (xhr.status === 200 || xhr.status === 0) {
                var history = JSON.parse(xhr.responseText)
                historyModel.clear()
                for (var i = 0; i < history.length && i < 100; i++) {
                    historyModel.append(history[i])
                }
            }
        } catch (e) {
            console.log("No call history found")
        }
    }

    function loadStatus() {
        var statusPath = "/tmp/flick_phone_status"
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file://" + statusPath, false)
        try {
            xhr.send()
            if (xhr.status === 200 || xhr.status === 0) {
                var status = JSON.parse(xhr.responseText)
                var newState = status.state || "idle"

                // Handle state transitions - sync with daemon state
                if (newState === "incoming") {
                    // Always sync incoming state
                    if (!inCall || callState !== "incoming") {
                        inCall = true
                        callState = "incoming"
                        callerNumber = status.number || "Unknown"
                        callDuration = 0
                    }
                } else if (newState === "active") {
                    // Always show in-call UI for active calls
                    if (!inCall) {
                        callerNumber = status.number || "Unknown"
                    }
                    inCall = true
                    callState = "active"
                    callDuration = status.duration || 0
                } else if (newState === "idle" && inCall) {
                    // Call ended - add to history
                    if (callerNumber !== "") {
                        historyModel.insert(0, {
                            "number": callerNumber,
                            "direction": callState === "incoming" ? "incoming" : "outgoing",
                            "duration": callDuration,
                            "timestamp": new Date().toISOString()
                        })
                    }
                    inCall = false
                    callState = "idle"
                    callerNumber = ""
                    callDuration = 0
                    loadHistory()  // Reload to get daemon's history updates
                } else if (newState === "dialing" || newState === "alerting") {
                    callState = "dialing"
                    callerNumber = status.number || phoneNumber
                }
            }
        } catch (e) {
            // Status file may not exist yet
        }
    }

    function writeCommand(action, data) {
        // Write command to file for daemon to process
        // Using a workaround: create a temp file via console output captured by wrapper
        var cmd = JSON.stringify({action: action, number: data || ""})
        console.log("CMD:" + cmd)
    }

    function appendDigit(digit) {
        if (phoneNumber.length < 20) {
            phoneNumber += digit
        }
    }

    function deleteDigit() {
        if (phoneNumber.length > 0) {
            phoneNumber = phoneNumber.substring(0, phoneNumber.length - 1)
        }
    }

    function clearNumber() {
        phoneNumber = ""
    }

    function dial() {
        if (phoneNumber.length > 0) {
            Haptic.click()
            callState = "dialing"
            callerNumber = phoneNumber
            inCall = true
            callDuration = 0
            writeCommand("dial", phoneNumber)
        }
    }

    function hangup() {
        Haptic.click()
        writeCommand("hangup", "")
        inCall = false
        callState = "idle"
        speakerOn = false
        muteOn = false
    }

    function answer() {
        Haptic.click()
        writeCommand("answer", "")
        callState = "active"
    }

    function toggleSpeaker() {
        speakerOn = !speakerOn
        if (speakerOn) {
            muteOn = false  // Speaker enables unmutes for compatibility
        }
        var cmd = JSON.stringify({action: "speaker", enabled: speakerOn})
        console.log("CMD:" + cmd)
    }

    function toggleMute() {
        muteOn = !muteOn
        if (muteOn) {
            speakerOn = false  // Mute disables speaker for compatibility
        }
        var cmd = JSON.stringify({action: "mute", enabled: muteOn})
        console.log("CMD:" + cmd)
    }

    function formatDuration(seconds) {
        var mins = Math.floor(seconds / 60)
        var secs = seconds % 60
        return mins + ":" + (secs < 10 ? "0" : "") + secs
    }

    function formatTimestamp(isoString) {
        try {
            var date = new Date(isoString)
            var now = new Date()
            var isToday = date.toDateString() === now.toDateString()

            if (isToday) {
                return date.toLocaleTimeString([], {hour: '2-digit', minute:'2-digit'})
            } else {
                return date.toLocaleDateString([], {month: 'short', day: 'numeric'})
            }
        } catch (e) {
            return ""
        }
    }

    // Phone app doesn't need config reload - fixed layout

    // Status poll timer
    Timer {
        interval: 500
        running: true
        repeat: true
        onTriggered: loadStatus()
    }

    // Main content area
    Item {
        anchors.fill: parent
        anchors.bottomMargin: 80 * textScale
        visible: !inCall

        // Tab bar
        Row {
            id: tabBar
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.topMargin: 40 * textScale
            spacing: 20 * textScale

            Repeater {
                model: ["Dialpad", "History"]

                Rectangle {
                    width: 200 * textScale
                    height: 40 * textScale
                    radius: 30 * textScale
                    color: currentTab === index ? accentColor : "#1a1a2e"
                    border.color: "#2a2a4e"
                    border.width: 2

                    Text {
                        anchors.centerIn: parent
                        text: modelData
                        color: "white"
                        font.pixelSize: 24 * textScale
                        font.weight: currentTab === index ? Font.Bold : Font.Normal
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            currentTab = index
                            if (index === 1) loadHistory()
                        }
                    }
                }
            }
        }

        // Dialpad view
        Item {
            anchors.top: tabBar.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.topMargin: 30 * textScale
            visible: currentTab === 0

            // Number display
            Rectangle {
                id: numberDisplay
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 30 * textScale
                height: 120 * textScale
                color: "#0f0f14"
                radius: 16 * textScale
                border.color: "#2a2a4e"
                border.width: 2

                Text {
                    anchors.centerIn: parent
                    text: phoneNumber.length > 0 ? phoneNumber : "Enter number"
                    color: phoneNumber.length > 0 ? "#ffffff" : "#666688"
                    font.pixelSize: 26 * textScale
                    font.weight: Font.Bold
                    font.letterSpacing: 4
                }

                // Clear button
                Rectangle {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.rightMargin: 20 * textScale
                    width: 40 * textScale
                    height: 40 * textScale
                    radius: 30 * textScale
                    color: clearArea.pressed ? "#3a3a4e" : "#2a2a3e"
                    visible: phoneNumber.length > 0

                    Text {
                        anchors.centerIn: parent
                        text: "X"
                        color: accentColor
                        font.pixelSize: 24 * textScale
                        font.weight: Font.Bold
                    }

                    MouseArea {
                        id: clearArea
                        anchors.fill: parent
                        onClicked: clearNumber()
                    }
                }
            }

            // Dialpad grid
            Grid {
                id: dialpad
                anchors.top: numberDisplay.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.topMargin: 40 * textScale
                columns: 3
                rowSpacing: 20 * textScale
                columnSpacing: 30 * textScale

                property real btnSize: 110 * textScale

                Repeater {
                    model: ["1", "2", "3", "4", "5", "6", "7", "8", "9", "*", "0", "#"]

                    Rectangle {
                        width: dialpad.btnSize
                        height: dialpad.btnSize
                        radius: dialpad.btnSize / 2
                        color: dialBtnArea.pressed ? "#2a2a4e" : "#1a1a2e"
                        border.color: "#3a3a5e"
                        border.width: 2

                        Column {
                            anchors.centerIn: parent
                            spacing: 2

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: modelData
                                color: "white"
                                font.pixelSize: 26 * textScale
                                font.weight: Font.Bold
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: {
                                    var letters = ["", "ABC", "DEF", "GHI", "JKL", "MNO", "PQRS", "TUV", "WXYZ", "", "+", ""]
                                    var idx = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "*", "0", "#"].indexOf(modelData)
                                    return letters[idx]
                                }
                                color: "#666688"
                                font.pixelSize: 12 * textScale
                                visible: text !== ""
                            }
                        }

                        MouseArea {
                            id: dialBtnArea
                            anchors.fill: parent
                            onClicked: appendDigit(modelData)
                            onPressAndHold: {
                                if (modelData === "0") {
                                    appendDigit("+")
                                }
                            }
                        }
                    }
                }
            }

            // Action row: backspace and call
            Row {
                anchors.top: dialpad.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.topMargin: 40 * textScale
                spacing: 26 * textScale

                // Backspace
                Rectangle {
                    width: 54 * textScale
                    height: 54 * textScale
                    radius: 40 * textScale
                    color: backspaceArea.pressed ? "#3a3a4e" : "#2a2a3e"

                    Text {
                        anchors.centerIn: parent
                        text: "<"
                        color: phoneNumber.length > 0 ? "white" : "#444"
                        font.pixelSize: 22 * textScale
                        font.weight: Font.Bold
                    }

                    MouseArea {
                        id: backspaceArea
                        anchors.fill: parent
                        enabled: phoneNumber.length > 0
                        onClicked: deleteDigit()
                        onPressAndHold: clearNumber()
                    }
                }

                // Call button
                Rectangle {
                    width: 120 * textScale
                    height: 120 * textScale
                    radius: 60 * textScale
                    color: callBtnArea.pressed ? "#2ecc50" : (phoneNumber.length > 0 ? "#27ae60" : "#1a5a30")

                    Text {
                        anchors.centerIn: parent
                        text: "Call"
                        color: phoneNumber.length > 0 ? "white" : "#555"
                        font.pixelSize: 20 * textScale
                        font.weight: Font.Bold
                    }

                    MouseArea {
                        id: callBtnArea
                        anchors.fill: parent
                        enabled: phoneNumber.length > 0
                        onClicked: dial()
                    }
                }

                // Placeholder for symmetry
                Item {
                    width: 54 * textScale
                    height: 54 * textScale
                }
            }
        }

        // History view
        Item {
            anchors.top: tabBar.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.topMargin: 30 * textScale
            anchors.margins: 20 * textScale
            visible: currentTab === 1

            ListView {
                id: historyList
                anchors.fill: parent
                anchors.leftMargin: 20 * textScale
                anchors.rightMargin: 20 * textScale
                model: historyModel
                clip: true
                spacing: 10 * textScale

                delegate: Rectangle {
                    width: historyList.width
                    height: 100 * textScale
                    color: historyItemArea.pressed ? "#2a2a4e" : "#1a1a2e"
                    radius: 12 * textScale

                    Row {
                        anchors.fill: parent
                        anchors.margins: 20 * textScale
                        spacing: 20 * textScale

                        // Direction icon
                        Rectangle {
                            width: 50 * textScale
                            height: 50 * textScale
                            radius: 25 * textScale
                            anchors.verticalCenter: parent.verticalCenter
                            color: {
                                if (model.direction === "missed") return "#e74c3c"
                                if (model.direction === "incoming") return "#3498db"
                                return "#27ae60"
                            }

                            Text {
                                anchors.centerIn: parent
                                text: {
                                    if (model.direction === "missed") return "!"
                                    if (model.direction === "incoming") return "<"
                                    return ">"
                                }
                                color: "white"
                                font.pixelSize: 24 * textScale
                                font.weight: Font.Bold
                            }
                        }

                        // Number and time
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 5 * textScale

                            Text {
                                text: model.number
                                color: "white"
                                font.pixelSize: 24 * textScale
                                font.weight: Font.Bold
                            }

                            Text {
                                text: formatTimestamp(model.timestamp) +
                                      (model.duration > 0 ? " - " + formatDuration(model.duration) : "")
                                color: "#888899"
                                font.pixelSize: 18 * textScale
                            }
                        }
                    }

                    MouseArea {
                        id: historyItemArea
                        anchors.fill: parent
                        onClicked: {
                            phoneNumber = model.number
                            currentTab = 0
                        }
                    }
                }

                // Empty state
                Text {
                    anchors.centerIn: parent
                    text: "No call history"
                    color: "#666688"
                    font.pixelSize: 24 * textScale
                    visible: historyModel.count === 0
                }
            }
        }
    }

    // In-call screen
    Rectangle {
        anchors.fill: parent
        color: "#0a0a0f"
        visible: inCall

        Column {
            anchors.centerIn: parent
            spacing: 20 * textScale

            // Status
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: {
                    if (callState === "dialing") return "Calling..."
                    if (callState === "incoming") return "Incoming Call"
                    return "Connected"
                }
                color: "#888899"
                font.pixelSize: 20 * textScale
            }

            // Caller number
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: callerNumber
                color: "white"
                font.pixelSize: 22 * textScale
                font.weight: Font.Bold
                font.letterSpacing: 4
            }

            // Duration
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: formatDuration(callDuration)
                color: accentColor
                font.pixelSize: 24 * textScale
                font.weight: Font.Medium
                visible: callState === "active"
            }

            // Spacer
            Item { width: 1; height: 100 * textScale }

            // Call actions
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 26 * textScale

                // Answer (for incoming)
                Rectangle {
                    width: 40 * textScale
                    height: 40 * textScale
                    radius: 45 * textScale
                    color: answerArea.pressed ? "#2ecc50" : "#27ae60"
                    visible: callState === "incoming"

                    Text {
                        anchors.centerIn: parent
                        text: "Yes"
                        color: "white"
                        font.pixelSize: 22 * textScale
                        font.weight: Font.Bold
                    }

                    MouseArea {
                        id: answerArea
                        anchors.fill: parent
                        onClicked: answer()
                    }
                }

                // Mute toggle (visible during active call)
                Rectangle {
                    width: 54 * textScale
                    height: 54 * textScale
                    radius: 40 * textScale
                    color: muteOn ? "#e94560" : (muteArea.pressed ? "#3a3a4e" : "#2a2a3e")
                    visible: callState === "active" || callState === "dialing"

                    Column {
                        anchors.centerIn: parent
                        spacing: 4

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: muteOn ? "🔇" : "🎤"
                            font.pixelSize: 24
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: muteOn ? "Muted" : "Mute"
                            color: muteOn ? "white" : "#888"
                            font.pixelSize: 10 * textScale
                            font.weight: Font.Bold
                        }
                    }

                    MouseArea {
                        id: muteArea
                        anchors.fill: parent
                        onClicked: toggleMute()
                    }
                }

                // Speaker toggle (visible during active call)
                Rectangle {
                    width: 54 * textScale
                    height: 54 * textScale
                    radius: 40 * textScale
                    color: speakerOn ? "#3498db" : (speakerArea.pressed ? "#3a3a4e" : "#2a2a3e")
                    visible: callState === "active" || callState === "dialing"

                    Column {
                        anchors.centerIn: parent
                        spacing: 4

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "🔊"
                            font.pixelSize: 24
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: speakerOn ? "ON" : "OFF"
                            color: speakerOn ? "white" : "#888"
                            font.pixelSize: 10 * textScale
                            font.weight: Font.Bold
                        }
                    }

                    MouseArea {
                        id: speakerArea
                        anchors.fill: parent
                        onClicked: toggleSpeaker()
                    }
                }

                // Hangup
                Rectangle {
                    width: 40 * textScale
                    height: 40 * textScale
                    radius: 45 * textScale
                    color: hangupArea.pressed ? "#c0392b" : "#e74c3c"

                    Text {
                        anchors.centerIn: parent
                        text: "End"
                        color: "white"
                        font.pixelSize: 22 * textScale
                        font.weight: Font.Bold
                    }

                    MouseArea {
                        id: hangupArea
                        anchors.fill: parent
                        onClicked: hangup()
                    }
                }
            }
        }
    }

    // Back button
    Rectangle {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 30 * textScale
        anchors.bottomMargin: 100 * textScale
        width: 48 * textScale
        height: 48 * textScale
        radius: 36 * textScale
        color: backBtnArea.pressed ? "#d93550" : accentColor
        visible: !inCall
        z: 100

        Text {
            anchors.centerIn: parent
            text: "<"
            color: "white"
            font.pixelSize: 22 * textScale
            font.weight: Font.Bold
        }

        MouseArea {
            id: backBtnArea
            anchors.fill: parent
            onClicked: Qt.quit()
        }
    }

    // Home indicator
    Rectangle {
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottomMargin: 10 * textScale
        width: 200 * textScale
        height: 8 * textScale
        radius: 4 * textScale
        color: "#333344"
    }
}
