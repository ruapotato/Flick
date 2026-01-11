pragma Singleton
import QtQuick 2.15

QtObject {
    id: mediaController

    // Media status properties
    property bool hasMedia: false
    property bool isPlaying: false
    property string title: ""
    property string artist: ""
    property string app: ""  // "music", "audiobooks", "podcast", etc.
    property int position: 0  // milliseconds
    property int duration: 0  // milliseconds
    property string albumArt: ""

    // Timestamp of last status update
    property var lastUpdate: 0

    // State directory for file-based IPC
    readonly property string stateDir: {
        var paths = [
            "/home/furios/.local/state/flick",
            "/home/droidian/.local/state/flick"
        ]
        for (var i = 0; i < paths.length; i++) {
            var xhr = new XMLHttpRequest()
            xhr.open("GET", "file://" + paths[i] + "/display_config.json", false)
            try {
                xhr.send()
                if ((xhr.status === 200 || xhr.status === 0) && xhr.responseText) {
                    return paths[i]
                }
            } catch (e) {}
        }
        return "/home/furios/.local/state/flick"
    }

    // Poll timer for media status
    property Timer pollTimer: Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: mediaController.loadStatus()
    }

    // Load media status from file
    function loadStatus() {
        var xhr = new XMLHttpRequest()
        var url = "file://" + stateDir + "/media_status.json"
        xhr.open("GET", url)
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200 || xhr.status === 0) {
                    try {
                        var status = JSON.parse(xhr.responseText)
                        var now = Date.now()
                        var age = now - status.timestamp

                        // Allow longer timeout when paused (60s) vs playing (10s)
                        var maxAge = status.playing ? 10000 : 60000

                        if (status.timestamp && age < maxAge && status.title) {
                            hasMedia = true
                            isPlaying = status.playing || false
                            title = status.title || ""
                            artist = status.artist || ""
                            app = status.app || ""
                            position = status.position || 0
                            duration = status.duration || 0
                            albumArt = status.album_art || ""
                            lastUpdate = status.timestamp
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

    // Send media command
    function sendCommand(cmd) {
        console.log("MEDIA_COMMAND:" + cmd)
        var xhr = new XMLHttpRequest()
        xhr.open("PUT", "file://" + stateDir + "/media_command")
        xhr.send(cmd + ":" + Date.now())
    }

    // Control functions
    function play() {
        sendCommand("play")
    }

    function pause() {
        sendCommand("pause")
    }

    function togglePlayPause() {
        sendCommand(isPlaying ? "pause" : "play")
    }

    function next() {
        sendCommand("next")
    }

    function previous() {
        sendCommand("prev")
    }

    function seekForward(ms) {
        if (typeof ms === 'undefined') ms = 30000
        sendCommand("seek:" + ms)
    }

    function seekBackward(ms) {
        if (typeof ms === 'undefined') ms = 30000
        sendCommand("seek:-" + ms)
    }

    function seekTo(positionMs) {
        sendCommand("seek_to:" + positionMs)
    }

    // Helper to format time as M:SS or H:MM:SS
    function formatTime(ms) {
        var seconds = Math.floor(ms / 1000)
        var hours = Math.floor(seconds / 3600)
        seconds = seconds % 3600
        var minutes = Math.floor(seconds / 60)
        seconds = seconds % 60

        if (hours > 0) {
            return hours + ":" + (minutes < 10 ? "0" : "") + minutes + ":" + (seconds < 10 ? "0" : "") + seconds
        }
        return minutes + ":" + (seconds < 10 ? "0" : "") + seconds
    }

    // Progress as 0.0-1.0
    readonly property real progress: duration > 0 ? position / duration : 0

    // Time strings
    readonly property string positionText: formatTime(position)
    readonly property string durationText: formatTime(duration)
    readonly property string remainingText: formatTime(duration - position)

    // App-specific behavior helpers
    readonly property bool isAudiobook: app === "audiobooks"
    readonly property bool isMusic: app === "music"
    readonly property bool isPodcast: app === "podcast"

    // Skip amount based on app type
    readonly property int skipAmount: isMusic ? 0 : 30000  // 30s for audiobooks/podcasts, track skip for music

    // Write media status (for player apps to report their status)
    function reportStatus(statusObj) {
        var status = {
            title: statusObj.title || "",
            artist: statusObj.artist || "",
            app: statusObj.app || "music",
            playing: statusObj.playing || false,
            position: statusObj.position || 0,
            duration: statusObj.duration || 0,
            album_art: statusObj.albumArt || "",
            timestamp: Date.now()
        }

        var xhr = new XMLHttpRequest()
        xhr.open("PUT", "file://" + stateDir + "/media_status.json")
        xhr.send(JSON.stringify(status))
    }

    // Clear media status (when player stops)
    function clearStatus() {
        hasMedia = false
        var xhr = new XMLHttpRequest()
        xhr.open("PUT", "file://" + stateDir + "/media_status.json")
        xhr.send("{}")
    }

    Component.onCompleted: {
        loadStatus()
    }
}
