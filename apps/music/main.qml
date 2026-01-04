import QtQuick 2.15
import QtQuick.Window 2.15
import QtQuick.Controls 2.15
import QtMultimedia 5.15
import "../shared"

Window {
    id: root
    visible: true
    width: 720
    height: 1600
    title: "Flick Music"
    color: "#0a0a0f"

    // Settings from Flick config
    property real textScale: Theme.textScale
    property color accentColor: Theme.accentColor
    property color accentPressed: Qt.darker(accentColor, 1.2)

    // Music player state
    property int currentTrackIndex: -1
    property var musicFiles: []
    property bool isPlaying: false
    property bool isScanning: false

    // Music folders to scan
    property var musicPaths: [Theme.homeDir + "/Music"]
    property string cacheFile: Theme.stateDir + "/music_cache.json"

    Component.onCompleted: {
        loadConfig()
        loadCache()
        scanMusicFolders()
    }

    function loadConfig() {
        var configPath = Theme.stateDir + "/display_config.json"
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file://" + configPath, false)
        try {
            xhr.send()
            if (xhr.status === 200 || xhr.status === 0) {
                var config = JSON.parse(xhr.responseText)
                if (config.text_scale !== undefined) {
                    textScale = config.text_scale
                }
            }
        } catch (e) {
            console.log("Using default text scale")
        }
    }

    // Reload config periodically
    Timer {
        interval: 3000
        running: true
        repeat: true
        onTriggered: loadConfig()
    }

    function loadCache() {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file://" + cacheFile, false)
        try {
            xhr.send()
            if (xhr.status === 200 || xhr.status === 0) {
                var cached = JSON.parse(xhr.responseText)
                if (cached.tracks && cached.tracks.length > 0) {
                    musicFiles = cached.tracks
                    updateListModel()
                    console.log("Loaded " + musicFiles.length + " tracks from cache")
                }
            }
        } catch (e) {
            console.log("No cache found, will scan")
        }
    }

    function saveCache() {
        var xhr = new XMLHttpRequest()
        xhr.open("PUT", "file://" + cacheFile, false)
        try {
            var data = JSON.stringify({ tracks: musicFiles })
            xhr.send(data)
            console.log("Saved " + musicFiles.length + " tracks to cache")
        } catch (e) {
            console.log("Failed to save cache: " + e)
        }
    }

    function scanMusicFolders() {
        isScanning = true
        console.log("Scanning music folders...")

        var foundTracks = []
        var extensions = [".mp3", ".flac", ".ogg", ".m4a", ".wav", ".opus"]

        for (var p = 0; p < musicPaths.length; p++) {
            var basePath = musicPaths[p]
            console.log("Scanning: " + basePath)

            // Read directory listing using XMLHttpRequest
            var files = listDirectory(basePath)

            for (var i = 0; i < files.length; i++) {
                var file = files[i]
                var lowerFile = file.toLowerCase()

                // Check if it's an audio file
                for (var e = 0; e < extensions.length; e++) {
                    if (lowerFile.endsWith(extensions[e])) {
                        var title = file
                        // Remove extension for display
                        for (var ee = 0; ee < extensions.length; ee++) {
                            if (lowerFile.endsWith(extensions[ee])) {
                                title = file.substring(0, file.length - extensions[ee].length)
                                break
                            }
                        }

                        foundTracks.push({
                            title: title,
                            artist: "Unknown Artist",
                            path: basePath + "/" + file,
                            albumArt: ""
                        })
                        break
                    }
                }
            }
        }

        // Sort by title
        foundTracks.sort(function(a, b) {
            return a.title.localeCompare(b.title)
        })

        if (foundTracks.length > 0) {
            musicFiles = foundTracks
            saveCache()
        } else if (musicFiles.length === 0) {
            // No cached data and no files found
            musicFiles = [{
                title: "No music found",
                artist: "Add music to ~/Music",
                path: "",
                albumArt: ""
            }]
        }

        updateListModel()
        isScanning = false
        console.log("Found " + foundTracks.length + " tracks")
    }

    function listDirectory(path) {
        var files = []
        var xhr = new XMLHttpRequest()

        // Try to read the directory by fetching a listing
        // This is a workaround - we'll use the file:// protocol to read files
        // First, let's create a listing file
        var listFile = "/tmp/flick_music_list_" + Date.now() + ".txt"

        // Execute find command via a temp script approach
        var cmdXhr = new XMLHttpRequest()
        cmdXhr.open("PUT", "file:///tmp/flick_music_scan.sh", false)
        try {
            var script = '#!/bin/bash\nls -1 "' + path + '" 2>/dev/null > "' + listFile + '"'
            cmdXhr.send(script)
        } catch (e) {
            console.log("Failed to write scan script")
            return files
        }

        // Execute the script
        var execXhr = new XMLHttpRequest()
        execXhr.open("PUT", "file:///tmp/flick_music_exec", false)
        try {
            execXhr.send("exec")
        } catch (e) {}

        // Small delay for command to execute (use a synchronous approach)
        var startTime = Date.now()
        while (Date.now() - startTime < 100) {
            // Busy wait
        }

        // Actually, let's just try to enumerate common filenames or use a different approach
        // QML XMLHttpRequest can't execute commands, so let's scan by trying to access files directly

        // Alternative: Try reading common files or use a pre-generated listing
        // For now, let's try a direct file enumeration approach using Qt.resolvedUrl

        // Try reading file listing from a generated temp file approach
        // We'll rely on the shell creating a listing for us periodically

        // Simpler approach: scan by reading /tmp/flick_music_files if it exists
        var listingXhr = new XMLHttpRequest()
        listingXhr.open("GET", "file:///tmp/flick_music_files", false)
        try {
            listingXhr.send()
            if (listingXhr.status === 200 || listingXhr.status === 0) {
                var listing = listingXhr.responseText.trim()
                if (listing.length > 0) {
                    files = listing.split("\n")
                }
            }
        } catch (e) {}

        // If no listing file, try to generate one
        if (files.length === 0) {
            // Request scan from shell by writing a trigger file
            var triggerXhr = new XMLHttpRequest()
            triggerXhr.open("PUT", "file:///tmp/flick_music_scan_request", false)
            try {
                triggerXhr.send(path)
            } catch (e) {}

            // Wait a bit and try again
            var waitStart = Date.now()
            while (Date.now() - waitStart < 500) {}

            // Try reading the listing again
            var retryXhr = new XMLHttpRequest()
            retryXhr.open("GET", "file:///tmp/flick_music_files", false)
            try {
                retryXhr.send()
                if (retryXhr.status === 200 || retryXhr.status === 0) {
                    var retryListing = retryXhr.responseText.trim()
                    if (retryListing.length > 0) {
                        files = retryListing.split("\n")
                    }
                }
            } catch (e) {}
        }

        return files
    }

    function updateListModel() {
        musicListModel.clear()
        for (var j = 0; j < musicFiles.length; j++) {
            musicListModel.append(musicFiles[j])
        }
    }

    // Rescan timer - check for scan requests from shell
    Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: {
            // Check if shell has updated the file listing
            var xhr = new XMLHttpRequest()
            xhr.open("GET", "file:///tmp/flick_music_files", false)
            try {
                xhr.send()
                if (xhr.status === 200 || xhr.status === 0) {
                    var content = xhr.responseText.trim()
                    if (content.length > 0 && content !== "scanned") {
                        var files = content.split("\n")
                        if (files.length > 0 && files[0] !== "") {
                            processScannedFiles(files)
                        }
                    }
                }
            } catch (e) {}
        }
    }

    function processScannedFiles(files) {
        var foundTracks = []
        var extensions = [".mp3", ".flac", ".ogg", ".m4a", ".wav", ".opus"]
        var basePath = musicPaths[0]

        for (var i = 0; i < files.length; i++) {
            var file = files[i].trim()
            if (file === "") continue

            var lowerFile = file.toLowerCase()

            for (var e = 0; e < extensions.length; e++) {
                if (lowerFile.endsWith(extensions[e])) {
                    var title = file
                    for (var ee = 0; ee < extensions.length; ee++) {
                        if (lowerFile.endsWith(extensions[ee])) {
                            title = file.substring(0, file.length - extensions[ee].length)
                            break
                        }
                    }

                    foundTracks.push({
                        title: title,
                        artist: "Unknown Artist",
                        path: basePath + "/" + file,
                        albumArt: ""
                    })
                    break
                }
            }
        }

        if (foundTracks.length > 0) {
            foundTracks.sort(function(a, b) {
                return a.title.localeCompare(b.title)
            })
            musicFiles = foundTracks
            updateListModel()
            saveCache()
            console.log("Updated with " + foundTracks.length + " tracks from scan")

            // Clear the scan file
            var clearXhr = new XMLHttpRequest()
            clearXhr.open("PUT", "file:///tmp/flick_music_files", false)
            try {
                clearXhr.send("scanned")
            } catch (e) {}
        }
    }

    ListModel {
        id: musicListModel
    }

    // Audio player
    Audio {
        id: audioPlayer
        autoPlay: false

        onStatusChanged: {
            console.log("Music: Audio status changed to: " + status)
            if (status === Audio.EndOfMedia) {
                console.log("Music: End of media detected, queuing next track")
                nextTrackTimer.start()
            }
        }

        onPlaybackStateChanged: {
            isPlaying = (playbackState === Audio.PlayingState)
            console.log("Music: Playback state changed, isPlaying=" + isPlaying)
        }

        onPositionChanged: {
            if (duration > 0) {
                progressBar.value = position / duration
            }
        }
    }

    // Timer to play next track (avoids issues with immediate source change)
    Timer {
        id: nextTrackTimer
        interval: 100
        repeat: false
        onTriggered: {
            console.log("Music: Playing next track automatically")
            playNextTrackAuto()
        }
    }

    // Auto-advance without haptic feedback
    function playNextTrackAuto() {
        if (musicFiles.length > 0 && musicFiles[0].path !== "") {
            var nextIndex = (currentTrackIndex + 1) % musicFiles.length
            currentTrackIndex = nextIndex
            audioPlayer.source = "file://" + musicFiles[nextIndex].path
            audioPlayer.play()
            console.log("Music: Now playing track " + nextIndex + ": " + musicFiles[nextIndex].title)
        }
    }

    function playTrack(index) {
        if (index >= 0 && index < musicFiles.length && musicFiles[index].path !== "") {
            Haptic.tap()
            currentTrackIndex = index
            audioPlayer.source = "file://" + musicFiles[index].path
            audioPlayer.play()
        }
    }

    function togglePlayPause() {
        Haptic.tap()
        if (currentTrackIndex < 0 && musicFiles.length > 0 && musicFiles[0].path !== "") {
            playTrack(0)
        } else if (isPlaying) {
            audioPlayer.pause()
        } else {
            audioPlayer.play()
        }
    }

    function nextTrack() {
        Haptic.tap()
        if (musicFiles.length > 0 && musicFiles[0].path !== "") {
            var nextIndex = (currentTrackIndex + 1) % musicFiles.length
            playTrack(nextIndex)
        }
    }

    function prevTrack() {
        Haptic.tap()
        if (musicFiles.length > 0 && musicFiles[0].path !== "") {
            var prevIndex = currentTrackIndex - 1
            if (prevIndex < 0) prevIndex = musicFiles.length - 1
            playTrack(prevIndex)
        }
    }

    function seekToPosition(position) {
        if (audioPlayer.seekable && audioPlayer.duration > 0) {
            Haptic.tap()
            audioPlayer.seek(position * audioPlayer.duration)
        }
    }

    // Write media status for lock screen controls
    function writeMediaStatus() {
        if (currentTrackIndex < 0 || musicFiles.length === 0) {
            return
        }
        var status = {
            playing: audioPlayer.playbackState === Audio.PlayingState,
            app: "music",
            title: musicFiles[currentTrackIndex].title,
            artist: musicFiles[currentTrackIndex].artist,
            position: audioPlayer.position,
            duration: audioPlayer.duration,
            timestamp: Date.now()
        }
        var xhr = new XMLHttpRequest()
        xhr.open("PUT", "file://" + Theme.stateDir + "/media_status.json")
        xhr.send(JSON.stringify(status))
    }

    // Timer to periodically update media status and check for commands
    Timer {
        id: mediaStatusTimer
        interval: 1000
        running: currentTrackIndex >= 0  // Run whenever we have a track loaded
        repeat: true
        onTriggered: {
            if (audioPlayer.playbackState === Audio.PlayingState) {
                writeMediaStatus()
            }
            checkMediaCommand()
        }
    }

    property string lastCommandTimestamp: ""

    function checkMediaCommand() {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file://" + Theme.stateDir + "/media_command")
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200 || xhr.status === 0) {
                    var cmdLine = xhr.responseText.trim()
                    if (cmdLine && cmdLine !== lastCommandTimestamp) {
                        var parts = cmdLine.split(":")
                        var cmd = parts[0]
                        var timestamp = parts.length > 1 ? parts[parts.length - 1] : ""

                        // Only process if this is a new command
                        if (timestamp !== lastCommandTimestamp) {
                            lastCommandTimestamp = timestamp
                            processMediaCommand(cmd, parts.length > 2 ? parts[1] : "")
                        }
                    }
                }
            }
        }
        xhr.send()
    }

    function processMediaCommand(cmd, arg) {
        console.log("Music: Processing media command: " + cmd + " arg: " + arg)
        if (cmd === "play") {
            if (currentTrackIndex < 0 && musicFiles.length > 0 && musicFiles[0].path !== "") {
                playTrack(0)
            } else {
                audioPlayer.play()
            }
        } else if (cmd === "pause") {
            audioPlayer.pause()
        } else if (cmd === "seek") {
            var delta = parseInt(arg) || 0
            audioPlayer.seek(Math.max(0, Math.min(audioPlayer.duration, audioPlayer.position + delta)))
        } else if (cmd === "next") {
            nextTrack()
        } else if (cmd === "prev") {
            prevTrack()
        }
    }

    // Large hero header with ambient glow
    Rectangle {
        id: headerArea
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 200
        color: "transparent"
        z: 1

        // Ambient glow effect
        Rectangle {
            anchors.centerIn: parent
            width: 300
            height: 200
            radius: 150
            color: accentColor
            opacity: isPlaying ? 0.12 : 0.08

            Behavior on opacity { NumberAnimation { duration: 500 } }

            NumberAnimation on opacity {
                from: isPlaying ? 0.08 : 0.05
                to: isPlaying ? 0.15 : 0.12
                duration: 2000
                loops: Animation.Infinite
                easing.type: Easing.InOutSine
                running: true
            }
        }

        Column {
            anchors.centerIn: parent
            spacing: 8

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Music"
                font.pixelSize: 22 * textScale
                font.weight: Font.ExtraLight
                font.letterSpacing: 6
                color: "#ffffff"
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: isScanning ? "SCANNING..." : (isPlaying ? "NOW PLAYING" : (musicFiles.length + " TRACKS"))
                font.pixelSize: 12 * textScale
                font.weight: Font.Medium
                font.letterSpacing: 3
                color: "#555566"
            }
        }

        // Bottom fade line
        Rectangle {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 0.2; color: accentColor }
                GradientStop { position: 0.8; color: accentColor }
                GradientStop { position: 1.0; color: "transparent" }
            }
            opacity: 0.3
        }

        // Refresh button
        Rectangle {
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.rightMargin: 20
            anchors.topMargin: 60
            width: 48
            height: 48
            radius: 24
            color: refreshMouse.pressed ? "#333344" : "#222233"

            Text {
                anchors.centerIn: parent
                text: "↻"
                font.pixelSize: 24
                color: "#888899"

                RotationAnimation on rotation {
                    from: 0
                    to: 360
                    duration: 1000
                    loops: Animation.Infinite
                    running: isScanning
                }
            }

            MouseArea {
                id: refreshMouse
                anchors.fill: parent
                onClicked: {
                    Haptic.tap()
                    // Request fresh scan from shell
                    var xhr = new XMLHttpRequest()
                    xhr.open("PUT", "file:///tmp/flick_music_scan_request", false)
                    try {
                        xhr.send(musicPaths[0])
                    } catch (e) {}
                    isScanning = true

                    // Clear old listing to force rescan
                    var clearXhr = new XMLHttpRequest()
                    clearXhr.open("PUT", "file:///tmp/flick_music_files", false)
                    try {
                        clearXhr.send("")
                    } catch (e) {}
                }
            }
        }
    }

    // Now playing section with album art
    Rectangle {
        id: nowPlayingArea
        anchors.top: headerArea.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: 320
        color: "transparent"

        // Album art placeholder
        Rectangle {
            id: albumArt
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 20
            width: 220
            height: 220
            radius: 16
            color: "#1a1a2e"
            border.color: accentColor
            border.width: 2

            // Music note icon
            Text {
                anchors.centerIn: parent
                text: "♪"
                font.pixelSize: 100
                color: accentColor
                opacity: 0.3
            }

            // Rotation animation when playing
            RotationAnimation on rotation {
                from: 0
                to: 360
                duration: 10000
                loops: Animation.Infinite
                running: isPlaying
            }
        }

        // Track info
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: albumArt.bottom
            anchors.topMargin: 16
            spacing: 4
            width: parent.width - 40

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: currentTrackIndex >= 0 ? musicFiles[currentTrackIndex].title : "No track selected"
                font.pixelSize: 18 * textScale
                font.weight: Font.Medium
                color: "#ffffff"
                elide: Text.ElideRight
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: currentTrackIndex >= 0 ? musicFiles[currentTrackIndex].artist : "Select a track to play"
                font.pixelSize: 14 * textScale
                color: "#888899"
                elide: Text.ElideRight
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }

    // Player controls
    Rectangle {
        id: controlsArea
        anchors.top: nowPlayingArea.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: 180
        color: "transparent"

        Column {
            anchors.centerIn: parent
            spacing: 20
            width: parent.width - 40

            // Progress bar
            Item {
                width: parent.width
                height: 40

                // Time labels
                Row {
                    anchors.fill: parent
                    anchors.bottomMargin: 20

                    Text {
                        text: formatTime(audioPlayer.position)
                        font.pixelSize: 12 * textScale
                        color: "#666677"
                        width: parent.width / 2
                    }

                    Text {
                        text: formatTime(audioPlayer.duration)
                        font.pixelSize: 12 * textScale
                        color: "#666677"
                        width: parent.width / 2
                        horizontalAlignment: Text.AlignRight
                    }
                }

                // Progress bar background
                Rectangle {
                    id: progressBarBg
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 6
                    radius: 3
                    color: "#222233"

                    // Progress fill
                    Rectangle {
                        id: progressBar
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: parent.width * value
                        radius: 3
                        color: accentColor

                        property real value: 0
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            var pos = mouse.x / width
                            seekToPosition(pos)
                        }
                    }
                }
            }

            // Control buttons
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 32

                // Previous button
                Rectangle {
                    width: 64
                    height: 64
                    radius: 32
                    color: prevMouse.pressed ? "#333344" : "#222233"
                    border.color: "#444455"
                    border.width: 1

                    Behavior on color { ColorAnimation { duration: 150 } }

                    Text {
                        anchors.centerIn: parent
                        text: "⏮"
                        font.pixelSize: 32
                        color: "#ffffff"
                    }

                    MouseArea {
                        id: prevMouse
                        anchors.fill: parent
                        onClicked: prevTrack()
                    }
                }

                // Play/Pause button
                Rectangle {
                    width: 88
                    height: 88
                    radius: 44
                    color: playMouse.pressed ? accentPressed : accentColor

                    Behavior on color { ColorAnimation { duration: 150 } }

                    Text {
                        anchors.centerIn: parent
                        text: isPlaying ? "⏸" : "▶"
                        font.pixelSize: 40
                        color: "#ffffff"
                    }

                    MouseArea {
                        id: playMouse
                        anchors.fill: parent
                        onClicked: togglePlayPause()
                    }
                }

                // Next button
                Rectangle {
                    width: 64
                    height: 64
                    radius: 32
                    color: nextMouse.pressed ? "#333344" : "#222233"
                    border.color: "#444455"
                    border.width: 1

                    Behavior on color { ColorAnimation { duration: 150 } }

                    Text {
                        anchors.centerIn: parent
                        text: "⏭"
                        font.pixelSize: 32
                        color: "#ffffff"
                    }

                    MouseArea {
                        id: nextMouse
                        anchors.fill: parent
                        onClicked: nextTrack()
                    }
                }
            }
        }
    }

    // Music list
    ListView {
        id: musicListView
        anchors.top: controlsArea.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 16
        anchors.bottomMargin: 120
        spacing: 8
        clip: true

        model: musicListModel

        delegate: Rectangle {
            width: musicListView.width
            height: 54
            radius: 12
            color: trackMouse.pressed ? "#1a1a2e" : (currentTrackIndex === index ? "#2a2a3e" : "#15151f")
            border.color: currentTrackIndex === index ? accentColor : "#222233"
            border.width: currentTrackIndex === index ? 2 : 1

            Behavior on color { ColorAnimation { duration: 150 } }

            Row {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 12

                // Mini album art
                Rectangle {
                    width: 56
                    height: 56
                    radius: 8
                    color: "#1a1a2e"
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        anchors.centerIn: parent
                        text: "♪"
                        font.pixelSize: 20
                        color: accentColor
                        opacity: 0.3
                    }
                }

                // Track info
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 68
                    spacing: 4

                    Text {
                        text: model.title
                        font.pixelSize: 16 * textScale
                        font.weight: Font.Medium
                        color: "#ffffff"
                        elide: Text.ElideRight
                        width: parent.width
                    }

                    Text {
                        text: model.artist
                        font.pixelSize: 13 * textScale
                        color: "#888899"
                        elide: Text.ElideRight
                        width: parent.width
                    }
                }
            }

            MouseArea {
                id: trackMouse
                anchors.fill: parent
                onClicked: {
                    if (model.path !== "") {
                        playTrack(index)
                    }
                }
            }
        }

        // Scroll indicator
        ScrollBar.vertical: ScrollBar {
            active: true
            policy: ScrollBar.AsNeeded
        }
    }

    // Helper function to format time
    function formatTime(ms) {
        var seconds = Math.floor(ms / 1000)
        var minutes = Math.floor(seconds / 60)
        seconds = seconds % 60
        return minutes + ":" + (seconds < 10 ? "0" : "") + seconds
    }

    // Back button - floating action button
    Rectangle {
        id: backButton
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 24
        anchors.bottomMargin: 120
        width: 48
        height: 48
        radius: 36
        color: backButtonMouse.pressed ? accentPressed : accentColor
        z: 2

        Behavior on color { ColorAnimation { duration: 150 } }

        Text {
            anchors.centerIn: parent
            text: "←"
            font.pixelSize: 22
            font.weight: Font.Medium
            color: "#ffffff"
        }

        MouseArea {
            id: backButtonMouse
            anchors.fill: parent
            onClicked: Qt.quit()
        }
    }

    // Home indicator bar
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
