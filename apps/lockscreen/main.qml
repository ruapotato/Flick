import QtQuick 2.15
import QtQuick.Window 2.15

Window {
    id: root
    visible: true
    visibility: Window.FullScreen
    title: "Flick Lock Screen"
    color: wallpaperPath !== "" ? "transparent" : "#0a0a0f"

    // Config - loaded from JSON
    property string lockMethod: "pin"  // "pin", "pattern", "password", "none"
    property string correctPin: "1234"
    property var correctPattern: [0, 1, 2, 5, 8]  // Default pattern
    // State dir - use droidian home on phone, wrapper script sets this path
    property string stateDir: "/home/droidian/.local/state/flick"
    property string wallpaperPath: ""

    // Incoming call state
    property bool hasIncomingCall: false
    property string incomingCaller: ""

    Component.onCompleted: {
        console.log("Lock screen started")
        console.log("stateDir:", stateDir)
        loadConfig()
        loadDisplayConfig()
    }

    // Poll for incoming calls
    Timer {
        interval: 500
        running: true
        repeat: true
        onTriggered: checkPhoneStatus()
    }

    function checkPhoneStatus() {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file:///tmp/flick_phone_status", false)
        try {
            xhr.send()
            if (xhr.status === 200 || xhr.status === 0) {
                var status = JSON.parse(xhr.responseText)
                if (status.state === "incoming") {
                    if (!hasIncomingCall) {
                        console.log("Incoming call from:", status.number)
                        triggerHaptic()
                    }
                    hasIncomingCall = true
                    incomingCaller = status.number || "Unknown"
                } else {
                    hasIncomingCall = false
                    incomingCaller = ""
                }
            }
        } catch (e) {
            // No status file or parse error
        }
    }

    function answerCall() {
        console.log("Answering call")
        triggerHaptic()
        var xhr = new XMLHttpRequest()
        xhr.open("PUT", "file:///tmp/flick_phone_cmd")
        xhr.send(JSON.stringify({action: "answer"}))
    }

    function rejectCall() {
        console.log("Rejecting call")
        triggerHaptic()
        var xhr = new XMLHttpRequest()
        xhr.open("PUT", "file:///tmp/flick_phone_cmd")
        xhr.send(JSON.stringify({action: "hangup"}))
    }

    function triggerHaptic() {
        var xhr = new XMLHttpRequest()
        xhr.open("PUT", "file:///tmp/flick_haptic")
        xhr.send("click")
    }

    function loadDisplayConfig() {
        var xhr = new XMLHttpRequest()
        var url = "file://" + stateDir + "/display_config.json"
        xhr.open("GET", url, false)
        try {
            xhr.send()
            if (xhr.status === 200 || xhr.status === 0) {
                var config = JSON.parse(xhr.responseText)
                if (config.wallpaper) {
                    wallpaperPath = config.wallpaper
                    console.log("Loaded wallpaper:", wallpaperPath)
                }
            }
        } catch (e) {
            console.log("Could not load display config")
        }
    }

    function loadConfig() {
        var xhr = new XMLHttpRequest()
        var url = "file://" + stateDir + "/lock_config.json"
        console.log("Loading lock config from:", url)
        xhr.open("GET", url)
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200 || xhr.status === 0) {
                    try {
                        var config = JSON.parse(xhr.responseText)
                        console.log("Loaded lock config:", JSON.stringify(config))
                        lockMethod = config.method || "pin"
                        // For now, we use hardcoded credentials
                        // TODO: Implement proper IPC verification with compositor
                        console.log("Lock method:", lockMethod)
                    } catch (e) {
                        console.log("Failed to parse lock config:", e)
                    }
                } else {
                    console.log("Failed to load lock config, using defaults")
                }
            }
        }
        xhr.send()
    }

    // Wallpaper background
    Image {
        anchors.fill: parent
        source: wallpaperPath !== "" ? "file://" + wallpaperPath : ""
        fillMode: Image.PreserveAspectCrop
        visible: wallpaperPath !== ""
    }

    // Dark overlay for readability when wallpaper is set
    Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: wallpaperPath !== "" ? 0.4 : 0
    }

    LockScreen {
        anchors.fill: parent
        lockMethod: root.lockMethod
        correctPin: root.correctPin
        correctPattern: root.correctPattern
        stateDir: root.stateDir
        hasWallpaper: wallpaperPath !== ""

        onUnlocked: {
            console.log("Unlocked! Quitting...")
            Qt.quit()
        }
    }

    // Incoming call overlay
    Rectangle {
        id: callOverlay
        anchors.fill: parent
        color: "#ee1a1a2e"
        visible: hasIncomingCall
        z: 1000

        Column {
            anchors.centerIn: parent
            spacing: 30

            // Phone icon
            Text {
                text: "📞"
                font.pixelSize: 72
                anchors.horizontalCenter: parent.horizontalCenter
            }

            // "Incoming call" label
            Text {
                text: "Incoming Call"
                font.pixelSize: 24
                color: "#888888"
                anchors.horizontalCenter: parent.horizontalCenter
            }

            // Caller number
            Text {
                text: incomingCaller
                font.pixelSize: 32
                font.bold: true
                color: "#ffffff"
                anchors.horizontalCenter: parent.horizontalCenter
            }

            // Spacer
            Item { width: 1; height: 60 }

            // Answer/Reject buttons
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 80

                // Reject button (red)
                Rectangle {
                    width: 80
                    height: 80
                    radius: 40
                    color: rejectMouse.pressed ? "#cc3333" : "#e94560"

                    Text {
                        text: "✕"
                        font.pixelSize: 36
                        color: "white"
                        anchors.centerIn: parent
                    }

                    MouseArea {
                        id: rejectMouse
                        anchors.fill: parent
                        onClicked: rejectCall()
                    }
                }

                // Answer button (green)
                Rectangle {
                    width: 80
                    height: 80
                    radius: 40
                    color: answerMouse.pressed ? "#33cc33" : "#4ade80"

                    Text {
                        text: "✓"
                        font.pixelSize: 36
                        color: "white"
                        anchors.centerIn: parent
                    }

                    MouseArea {
                        id: answerMouse
                        anchors.fill: parent
                        onClicked: answerCall()
                    }
                }
            }
        }
    }
}
