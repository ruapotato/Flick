import QtQuick 2.15
import QtQuick.Controls 2.15

Item {
    id: mediaControls
    width: parent ? parent.width - 48 : 400
    height: hasMedia ? 140 : 0
    visible: hasMedia

    Component.onCompleted: {
        console.log("MediaControls: initialized, stateDir=" + stateDir)
    }

    onHasMediaChanged: {
        console.log("MediaControls: hasMedia changed to " + hasMedia)
    }

    property bool hasMedia: false
    property bool isPlaying: false
    property string title: ""
    property string artist: ""
    property string app: ""
    property int position: 0
    property int duration: 0
    property string stateDir: "/home/droidian/.local/state/flick"
    property color accentColor: "#e94560"  // Can be set from parent

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
        var url = "file://" + stateDir + "/media_status.json"
        xhr.open("GET", url)
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                console.log("MediaControls: loaded status, status=" + xhr.status + " response=" + xhr.responseText.substring(0, 100))
                if (xhr.status === 200 || xhr.status === 0) {
                    try {
                        var status = JSON.parse(xhr.responseText)
                        // Check if status is recent (within last 10 seconds) AND playing
                        var now = Date.now()
                        var age = now - status.timestamp
                        console.log("MediaControls: timestamp age=" + age + "ms, playing=" + status.playing)
                        if (status.timestamp && age < 10000 && status.playing) {
                            hasMedia = true
                            isPlaying = status.playing || false
                            title = status.title || ""
                            artist = status.artist || ""
                            app = status.app || ""
                            position = status.position || 0
                            duration = status.duration || 0
                            console.log("MediaControls: hasMedia=true, title=" + title)
                        } else {
                            hasMedia = false
                            console.log("MediaControls: status too old, age=" + age)
                        }
                    } catch (e) {
                        hasMedia = false
                        console.log("MediaControls: parse error: " + e)
                    }
                } else {
                    hasMedia = false
                    console.log("MediaControls: request failed, status=" + xhr.status)
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
            color: app === "audiobooks" ? accentColor : "#4a9eff"
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
                spacing: 20

                // Skip back (30s for audiobooks, prev track for music)
                Rectangle {
                    width: 44
                    height: 44
                    radius: 22
                    color: skipBackMouse.pressed ? "#333344" : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: app === "music" ? "⏮" : "⏪"
                        font.pixelSize: 22
                        color: "#aaaacc"
                    }

                    MouseArea {
                        id: skipBackMouse
                        anchors.fill: parent
                        anchors.margins: -25
                        onClicked: sendCommand(app === "music" ? "prev" : "seek:-30000")
                    }
                }

                // Play/Pause
                Rectangle {
                    width: 56
                    height: 56
                    radius: 28
                    color: playPauseMouse.pressed ? Qt.darker(accentColor, 1.2) : accentColor

                    Text {
                        anchors.centerIn: parent
                        text: isPlaying ? "⏸" : "▶"
                        font.pixelSize: 24
                        color: "#ffffff"
                    }

                    MouseArea {
                        id: playPauseMouse
                        anchors.fill: parent
                        anchors.margins: -25
                        onClicked: sendCommand(isPlaying ? "pause" : "play")
                    }
                }

                // Skip forward (30s for audiobooks, next track for music)
                Rectangle {
                    width: 44
                    height: 44
                    radius: 22
                    color: skipFwdMouse.pressed ? "#333344" : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: app === "music" ? "⏭" : "⏩"
                        font.pixelSize: 22
                        color: "#aaaacc"
                    }

                    MouseArea {
                        id: skipFwdMouse
                        anchors.fill: parent
                        anchors.margins: -25
                        onClicked: sendCommand(app === "music" ? "next" : "seek:30000")
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
