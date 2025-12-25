import QtQuick 2.15
import QtQuick.Controls 2.15

Item {
    id: mediaControls
    width: parent ? parent.width - 48 : 400
    height: visible && hasMedia ? 140 : 0
    visible: hasMedia

    property bool hasMedia: false
    property bool isPlaying: false
    property string title: ""
    property string artist: ""
    property string app: ""
    property int position: 0
    property int duration: 0
    property string stateDir: "/home/droidian/.local/state/flick"

    Behavior on height { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }

    // Poll for media status
    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: loadMediaStatus()
    }

    function loadMediaStatus() {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file://" + stateDir + "/media_status.json")
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200 || xhr.status === 0) {
                    try {
                        var status = JSON.parse(xhr.responseText)
                        // Check if status is recent (within last 5 seconds)
                        var now = Date.now()
                        if (status.timestamp && (now - status.timestamp) < 10000) {
                            hasMedia = true
                            isPlaying = status.playing || false
                            title = status.title || ""
                            artist = status.artist || ""
                            app = status.app || ""
                            position = status.position || 0
                            duration = status.duration || 0
                        } else {
                            hasMedia = false
                        }
                    } catch (e) {
                        hasMedia = false
                    }
                } else {
                    hasMedia = false
                }
            }
        }
        xhr.send()
    }

    function sendCommand(cmd) {
        console.log("MEDIA_COMMAND:" + cmd)
        // Write command to file for players to read
        var xhr = new XMLHttpRequest()
        xhr.open("PUT", "file://" + stateDir + "/media_command")
        xhr.send(cmd + ":" + Date.now())
    }

    function formatTime(ms) {
        var seconds = Math.floor(ms / 1000)
        var minutes = Math.floor(seconds / 60)
        seconds = seconds % 60
        return minutes + ":" + (seconds < 10 ? "0" : "") + seconds
    }

    // Background with blur effect
    Rectangle {
        anchors.fill: parent
        radius: 20
        color: "#1a1a28"
        opacity: 0.9
        border.color: "#333344"
        border.width: 1
    }

    Row {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 16

        // Album art / App icon placeholder
        Rectangle {
            width: 80
            height: 80
            radius: 12
            color: app === "audiobooks" ? "#e94560" : "#4a9eff"
            opacity: 0.3
            anchors.verticalCenter: parent.verticalCenter

            Text {
                anchors.centerIn: parent
                text: app === "audiobooks" ? "📚" : "🎵"
                font.pixelSize: 40
            }
        }

        // Track info and controls
        Column {
            width: parent.width - 96 - 16
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            // Title
            Text {
                width: parent.width
                text: title
                font.pixelSize: 18
                font.weight: Font.Medium
                color: "#ffffff"
                elide: Text.ElideRight
            }

            // Artist / Book
            Text {
                width: parent.width
                text: artist
                font.pixelSize: 14
                color: "#888899"
                elide: Text.ElideRight
            }

            // Controls row
            Row {
                width: parent.width
                spacing: 24

                // Skip back 30s
                Rectangle {
                    width: 44
                    height: 44
                    radius: 22
                    color: skipBackMouse.pressed ? "#333344" : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "⏪"
                        font.pixelSize: 22
                        color: "#aaaacc"
                    }

                    MouseArea {
                        id: skipBackMouse
                        anchors.fill: parent
                        onClicked: sendCommand("seek:-30000")
                    }
                }

                // Play/Pause
                Rectangle {
                    width: 56
                    height: 56
                    radius: 28
                    color: playPauseMouse.pressed ? "#c23a50" : "#e94560"

                    Text {
                        anchors.centerIn: parent
                        text: isPlaying ? "⏸" : "▶"
                        font.pixelSize: 24
                        color: "#ffffff"
                    }

                    MouseArea {
                        id: playPauseMouse
                        anchors.fill: parent
                        onClicked: sendCommand(isPlaying ? "pause" : "play")
                    }
                }

                // Skip forward 30s
                Rectangle {
                    width: 44
                    height: 44
                    radius: 22
                    color: skipFwdMouse.pressed ? "#333344" : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "⏩"
                        font.pixelSize: 22
                        color: "#aaaacc"
                    }

                    MouseArea {
                        id: skipFwdMouse
                        anchors.fill: parent
                        onClicked: sendCommand("seek:30000")
                    }
                }

                // Time display
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: formatTime(position) + " / " + formatTime(duration)
                    font.pixelSize: 12
                    color: "#666677"
                }
            }
        }
    }
}
