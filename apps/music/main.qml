import QtQuick 2.15
import QtQuick.Window 2.15
import QtQuick.Controls 2.15
import QtMultimedia 5.15

Window {
    id: root
    visible: true
    width: 1080
    height: 2400
    title: "Flick Music"
    color: "#0a0a0f"

    // Settings from Flick config
    property real textScale: 2.0

    // Music player state
    property int currentTrackIndex: -1
    property var musicFiles: []
    property bool isPlaying: false

    Component.onCompleted: {
        loadConfig()
        scanMusicFolders()
    }

    function loadConfig() {
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

    // Reload config periodically
    Timer {
        interval: 3000
        running: true
        repeat: true
        onTriggered: loadConfig()
    }

    function scanMusicFolders() {
        musicFiles = []
        var folders = ["/home/droidian/Music", Qt.resolvedUrl("~/Music").toString().replace("file://", "")]
        var extensions = [".mp3", ".flac", ".ogg", ".m4a"]

        for (var i = 0; i < folders.length; i++) {
            var folder = folders[i]
            var command = "find '" + folder + "' -type f 2>/dev/null | grep -E '\\.(mp3|flac|ogg|m4a)$'"

            // Execute command using QProcess would be better, but for QML we'll use a simpler approach
            // This is a demonstration - in production you'd want to use FolderListModel or C++ backend
            console.log("Would scan: " + folder)
        }

        // For demonstration, add some placeholder entries
        // In a real implementation, you'd use FolderListModel or a C++ backend
        musicFiles = [
            {
                title: "No music files found",
                artist: "Please add music to ~/Music",
                path: "",
                albumArt: ""
            }
        ]

        musicListModel.clear()
        for (var j = 0; j < musicFiles.length; j++) {
            musicListModel.append(musicFiles[j])
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
            if (status === Audio.EndOfMedia) {
                nextTrack()
            }
        }

        onPlaybackStateChanged: {
            isPlaying = (playbackState === Audio.PlayingState)
        }

        onPositionChanged: {
            if (duration > 0) {
                progressBar.value = position / duration
            }
        }
    }

    function playTrack(index) {
        if (index >= 0 && index < musicFiles.length && musicFiles[index].path !== "") {
            currentTrackIndex = index
            audioPlayer.source = "file://" + musicFiles[index].path
            audioPlayer.play()
        }
    }

    function togglePlayPause() {
        if (currentTrackIndex < 0 && musicFiles.length > 0) {
            playTrack(0)
        } else if (isPlaying) {
            audioPlayer.pause()
        } else {
            audioPlayer.play()
        }
    }

    function nextTrack() {
        if (musicFiles.length > 0) {
            var nextIndex = (currentTrackIndex + 1) % musicFiles.length
            playTrack(nextIndex)
        }
    }

    function prevTrack() {
        if (musicFiles.length > 0) {
            var prevIndex = currentTrackIndex - 1
            if (prevIndex < 0) prevIndex = musicFiles.length - 1
            playTrack(prevIndex)
        }
    }

    function seekToPosition(position) {
        if (audioPlayer.seekable && audioPlayer.duration > 0) {
            audioPlayer.seek(position * audioPlayer.duration)
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
            color: "#e94560"
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
                font.pixelSize: 48 * textScale
                font.weight: Font.ExtraLight
                font.letterSpacing: 6
                color: "#ffffff"
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: isPlaying ? "NOW PLAYING" : "FLICK PLAYER"
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
                GradientStop { position: 0.2; color: "#e94560" }
                GradientStop { position: 0.8; color: "#e94560" }
                GradientStop { position: 1.0; color: "transparent" }
            }
            opacity: 0.3
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
            border.color: "#e94560"
            border.width: 2

            // Music note icon
            Text {
                anchors.centerIn: parent
                text: "♪"
                font.pixelSize: 100
                color: "#e94560"
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
                        color: "#e94560"

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
                spacing: 30

                // Previous button
                Rectangle {
                    width: 60
                    height: 60
                    radius: 30
                    color: prevMouse.pressed ? "#333344" : "#222233"
                    border.color: "#444455"
                    border.width: 1

                    Behavior on color { ColorAnimation { duration: 150 } }

                    Text {
                        anchors.centerIn: parent
                        text: "⏮"
                        font.pixelSize: 24
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
                    width: 80
                    height: 80
                    radius: 40
                    color: playMouse.pressed ? "#c23a50" : "#e94560"

                    Behavior on color { ColorAnimation { duration: 150 } }

                    Text {
                        anchors.centerIn: parent
                        text: isPlaying ? "⏸" : "▶"
                        font.pixelSize: 32
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
                    width: 60
                    height: 60
                    radius: 30
                    color: nextMouse.pressed ? "#333344" : "#222233"
                    border.color: "#444455"
                    border.width: 1

                    Behavior on color { ColorAnimation { duration: 150 } }

                    Text {
                        anchors.centerIn: parent
                        text: "⏭"
                        font.pixelSize: 24
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
            height: 80
            radius: 12
            color: trackMouse.pressed ? "#1a1a2e" : (currentTrackIndex === index ? "#2a2a3e" : "#15151f")
            border.color: currentTrackIndex === index ? "#e94560" : "#222233"
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
                        font.pixelSize: 28
                        color: "#e94560"
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
        width: 72
        height: 72
        radius: 36
        color: backButtonMouse.pressed ? "#c23a50" : "#e94560"
        z: 2

        Behavior on color { ColorAnimation { duration: 150 } }

        Text {
            anchors.centerIn: parent
            text: "←"
            font.pixelSize: 32
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
