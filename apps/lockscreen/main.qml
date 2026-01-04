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
    property string stateDir: Theme.stateDir + ""
    property string wallpaperPath: ""

    // Call state
    property bool hasIncomingCall: false
    property bool hasActiveCall: false
    property string callNumber: ""
    property int callDuration: 0
    property bool isMuted: false
    property bool isSpeaker: false
    // Media playback state
    property bool hasMedia: false
    property bool mediaPlaying: false
    property string mediaTitle: ""
    property string mediaArtist: ""
    property string mediaApp: ""

    // Poll for media status
    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: checkMediaStatus()
    }

    function checkMediaStatus() {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file://" + stateDir + "/media_status.json", false)
        try {
            xhr.send()
            if (xhr.status === 200 || xhr.status === 0) {
                var status = JSON.parse(xhr.responseText)
                // Only show if status is recent (within last 30 seconds)
                var age = Date.now() - (status.timestamp || 0)
                if (age < 30000) {
                    hasMedia = true
                    mediaPlaying = status.playing || false
                    mediaTitle = status.title || "Unknown"
                    mediaArtist = status.artist || ""
                    mediaApp = status.app || ""
                } else {
                    hasMedia = false
                }
            }
        } catch (e) {
            hasMedia = false
        }
    }

    function sendMediaCommand(cmd, arg) {
        triggerHaptic()
        var cmdStr = cmd + (arg ? ":" + arg : "") + ":" + Date.now()
        var xhr = new XMLHttpRequest()
        xhr.open("PUT", "file://" + stateDir + "/media_command")
        xhr.send(cmdStr)
    }


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
                callNumber = status.number || "Unknown"
                callDuration = status.duration || 0

                if (status.state === "incoming") {
                    if (!hasIncomingCall) {
                        console.log("Incoming call from:", status.number)
                        triggerHaptic()
                    }
                    hasIncomingCall = true
                    hasActiveCall = false
                } else if (status.state === "active") {
                    hasIncomingCall = false
                    hasActiveCall = true
                } else {
                    hasIncomingCall = false
                    hasActiveCall = false
                    callNumber = ""
                    callDuration = 0
                }
            }
        } catch (e) {
            // No status file or parse error
        }
    }

    function formatDuration(seconds) {
        var mins = Math.floor(seconds / 60)
        var secs = seconds % 60
        return mins + ":" + (secs < 10 ? "0" : "") + secs
    }

    function hangupCall() {
        console.log("Hanging up call")
        triggerHaptic()
        var xhr = new XMLHttpRequest()
        xhr.open("PUT", "file:///tmp/flick_phone_cmd")
        xhr.send(JSON.stringify({action: "hangup"}))
    }

    function toggleSpeaker() {
        isSpeaker = !isSpeaker
        if (isSpeaker) {
            isMuted = false  // Speaker enables unmutes for compatibility
        }
        console.log("Toggling speaker:", isSpeaker)
        triggerHaptic()
        var xhr = new XMLHttpRequest()
        xhr.open("PUT", "file:///tmp/flick_phone_cmd")
        xhr.send(JSON.stringify({action: "speaker", enabled: isSpeaker}))
    }

    function toggleMute() {
        isMuted = !isMuted
        if (isMuted) {
            isSpeaker = false  // Mute disables speaker for compatibility
        }
        console.log("Toggling mute:", isMuted)
        triggerHaptic()
        var xhr = new XMLHttpRequest()
        xhr.open("PUT", "file:///tmp/flick_phone_cmd")
        xhr.send(JSON.stringify({action: "mute", enabled: isMuted}))
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

    // Media controls widget (bottom of lock screen)
    Rectangle {
        id: mediaWidget
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 16
        anchors.bottomMargin: 32
        height: 100
        radius: 20
        color: "#cc1a1a2e"
        visible: hasMedia && !hasIncomingCall && !hasActiveCall
        z: 500

        Row {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 12

            // Album art placeholder
            Rectangle {
                width: 76
                height: 76
                radius: 12
                color: "#333355"

                Text {
                    anchors.centerIn: parent
                    text: mediaApp === "audiobooks" ? "📚" : "🎵"
                    font.pixelSize: 32
                }
            }

            // Title and artist
            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 200
                spacing: 4

                Text {
                    text: mediaTitle
                    font.pixelSize: 16
                    font.bold: true
                    color: "#ffffff"
                    elide: Text.ElideRight
                    width: parent.width
                }

                Text {
                    text: mediaArtist
                    font.pixelSize: 14
                    color: "#888899"
                    elide: Text.ElideRight
                    width: parent.width
                }
            }

            // Play controls
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                // Rewind 10s
                Rectangle {
                    width: 40
                    height: 40
                    radius: 20
                    color: rwMouse.pressed ? "#444466" : "#333355"

                    Text {
                        anchors.centerIn: parent
                        text: "⏪"
                        font.pixelSize: 18
                    }

                    MouseArea {
                        id: rwMouse
                        anchors.fill: parent
                        onClicked: sendMediaCommand("seek", "-10000")
                    }
                }

                // Play/Pause
                Rectangle {
                    width: 48
                    height: 48
                    radius: 24
                    color: playMouse.pressed ? "#e94560" : "#333355"

                    Text {
                        anchors.centerIn: parent
                        text: mediaPlaying ? "⏸" : "▶"
                        font.pixelSize: 22
                    }

                    MouseArea {
                        id: playMouse
                        anchors.fill: parent
                        onClicked: sendMediaCommand(mediaPlaying ? "pause" : "play")
                    }
                }

                // Forward 10s
                Rectangle {
                    width: 40
                    height: 40
                    radius: 20
                    color: ffMouse.pressed ? "#444466" : "#333355"

                    Text {
                        anchors.centerIn: parent
                        text: "⏩"
                        font.pixelSize: 18
                    }

                    MouseArea {
                        id: ffMouse
                        anchors.fill: parent
                        onClicked: sendMediaCommand("seek", "10000")
                    }
                }
            }
        }
    }

    Rectangle {
        id: incomingCallOverlay
        anchors.fill: parent
        color: "#ee1a1a2e"
        visible: hasIncomingCall
        z: 1000

        Column {
            anchors.centerIn: parent
            spacing: 20

            // Phone icon
            Text {
                text: "📞"
                font.pixelSize: 22
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
                text: callNumber
                font.pixelSize: 22
                font.bold: true
                color: "#ffffff"
                anchors.horizontalCenter: parent.horizontalCenter
            }

            // Spacer
            Item { width: 1; height: 40 }

            // Answer/Reject buttons
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 32

                // Reject button (red)
                Rectangle {
                    width: 54
                    height: 54
                    radius: 40
                    color: rejectMouse.pressed ? "#cc3333" : "#e94560"

                    Text {
                        text: "✕"
                        font.pixelSize: 24
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
                    width: 54
                    height: 54
                    radius: 40
                    color: answerMouse.pressed ? "#33cc33" : "#4ade80"

                    Text {
                        text: "✓"
                        font.pixelSize: 24
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

    // Active call overlay (in-call UI)
    Rectangle {
        id: activeCallOverlay
        anchors.fill: parent
        color: "#ee1a1a2e"
        visible: hasActiveCall
        z: 1000

        Column {
            anchors.centerIn: parent
            spacing: 20

            // Phone icon (green for active)
            Text {
                text: "📱"
                font.pixelSize: 20
                anchors.horizontalCenter: parent.horizontalCenter
            }

            // "On call" label
            Text {
                text: "On Call"
                font.pixelSize: 20
                color: "#4ade80"
                anchors.horizontalCenter: parent.horizontalCenter
            }

            // Caller number
            Text {
                text: callNumber
                font.pixelSize: 20
                font.bold: true
                color: "#ffffff"
                anchors.horizontalCenter: parent.horizontalCenter
            }

            // Call duration
            Text {
                text: formatDuration(callDuration)
                font.pixelSize: 22
                font.bold: true
                color: "#ffffff"
                anchors.horizontalCenter: parent.horizontalCenter
            }

            // Spacer
            Item { width: 1; height: 40 }

            // Mute, Speaker and Hang up buttons
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 26

                // Mute button
                Column {
                    spacing: 8

                    Rectangle {
                        width: 44
                        height: 44
                        radius: 32
                        color: isMuted ? "#e94560" : (muteMouse.pressed ? "#444466" : "#333355")

                        Text {
                            text: isMuted ? "🔇" : "🎤"
                            font.pixelSize: 24
                            anchors.centerIn: parent
                        }

                        MouseArea {
                            id: muteMouse
                            anchors.fill: parent
                            onClicked: toggleMute()
                        }
                    }

                    Text {
                        text: isMuted ? "Unmute" : "Mute"
                        font.pixelSize: 12
                        color: "#888888"
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }

                // Speaker button
                Column {
                    spacing: 8

                    Rectangle {
                        width: 44
                        height: 44
                        radius: 32
                        color: isSpeaker ? "#4ade80" : (speakerMouse.pressed ? "#444466" : "#333355")

                        Text {
                            text: "🔊"
                            font.pixelSize: 24
                            anchors.centerIn: parent
                        }

                        MouseArea {
                            id: speakerMouse
                            anchors.fill: parent
                            onClicked: toggleSpeaker()
                        }
                    }

                    Text {
                        text: isSpeaker ? "Earpiece" : "Speaker"
                        font.pixelSize: 12
                        color: "#888888"
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }

                // Hang up button
                Column {
                    spacing: 8

                    Rectangle {
                        width: 44
                        height: 44
                        radius: 32
                        color: hangupMouse.pressed ? "#cc3333" : "#e94560"

                        Text {
                            text: "✕"
                            font.pixelSize: 20
                            color: "white"
                            anchors.centerIn: parent
                        }

                        MouseArea {
                            id: hangupMouse
                            anchors.fill: parent
                            onClicked: hangupCall()
                        }
                    }

                    Text {
                        text: "End"
                        font.pixelSize: 12
                        color: "#888888"
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }
            }
        }
    }
}
