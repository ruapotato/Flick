import QtQuick 2.15
import QtQuick.Window 2.15
import QtQuick.Controls 2.15
import QtMultimedia 5.15
import Qt.labs.folderlistmodel 2.15
import "../shared"

Window {
    id: root
    visible: true
    width: 1080
    height: 2400
    title: "Flick Video"
    color: "#0a0a0f"

    property real textScale: 2.0
    property bool isPlaying: false
    property bool showControls: true
    property string currentVideo: ""
    property string currentVideoName: ""

    function loadConfig() {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file:///home/droidian/.local/state/flick/display_config.json", false)
        try {
            xhr.send()
            if (xhr.status === 200 || xhr.status === 0) {
                var config = JSON.parse(xhr.responseText)
                if (config.text_scale) textScale = config.text_scale
            }
        } catch (e) {}
    }

    Timer {
        interval: 3000
        running: true
        repeat: true
        onTriggered: loadConfig()
    }

    // Video folders to scan
    property var videoFolders: [
        "/home/droidian/Videos",
        "/home/droidian/Movies",
        "/home/droidian/Downloads",
        "/home/droidian/DCIM"
    ]

    ListModel { id: videoModel }
    property var pendingScans: 0
    property var scannedFolders: []
    property var videoExtensions: ["mp4", "mkv", "avi", "webm", "mov", "m4v", "3gp", "MP4", "MKV", "AVI", "WEBM", "MOV", "M4V", "3GP"]

    Component.onCompleted: {
        loadConfig()
        startScan()
    }

    function startScan() {
        videoModel.clear()
        scannedFolders = []
        pendingScans = 0
        for (var i = 0; i < videoFolders.length; i++) {
            scanFolderRecursive(videoFolders[i])
        }
    }

    function scanFolderRecursive(folderPath) {
        // Avoid rescanning
        if (scannedFolders.indexOf(folderPath) >= 0) return
        scannedFolders.push(folderPath)
        pendingScans++

        // Create a folder model to scan this directory
        var scanner = folderScannerComponent.createObject(root, {
            scanPath: folderPath
        })
    }

    function isVideoFile(fileName) {
        var ext = fileName.split(".").pop().toLowerCase()
        return videoExtensions.indexOf(ext) >= 0 || videoExtensions.indexOf(ext.toUpperCase()) >= 0
    }

    // Component to scan a folder
    Component {
        id: folderScannerComponent
        Item {
            id: scanner
            property string scanPath: ""

            FolderListModel {
                id: folderModel
                folder: "file://" + scanner.scanPath
                showDirs: true
                showDirsFirst: true
                showDotAndDotDot: false
                showOnlyReadable: true

                onStatusChanged: {
                    if (status === FolderListModel.Ready) {
                        processFolder()
                    }
                }
            }

            function processFolder() {
                var baseName = scanPath.split("/").pop()

                for (var i = 0; i < folderModel.count; i++) {
                    var fileName = folderModel.get(i, "fileName")
                    var isDir = folderModel.get(i, "fileIsDir")
                    var filePath = scanPath + "/" + fileName

                    if (isDir) {
                        // Recursively scan subdirectory
                        scanFolderRecursive(filePath)
                    } else if (isVideoFile(fileName)) {
                        // Add video to model
                        videoModel.append({
                            name: folderModel.get(i, "fileBaseName"),
                            fileName: fileName,
                            filePath: filePath,
                            folder: baseName
                        })
                    }
                }

                pendingScans--
                // Clean up after a delay
                destroyTimer.start()
            }

            Timer {
                id: destroyTimer
                interval: 100
                onTriggered: scanner.destroy()
            }
        }
    }

    function playVideo(path, name) {
        Haptic.click()
        currentVideo = path
        currentVideoName = name
        mediaPlayer.source = "file://" + path
        mediaPlayer.play()
        isPlaying = true
        showControls = true
        controlsTimer.restart()
    }

    function togglePlayPause() {
        Haptic.tap()
        if (mediaPlayer.playbackState === MediaPlayer.PlayingState) {
            mediaPlayer.pause()
            isPlaying = false
        } else {
            mediaPlayer.play()
            isPlaying = true
        }
    }

    function stopVideo() {
        Haptic.tap()
        mediaPlayer.stop()
        currentVideo = ""
        isPlaying = false
    }

    function formatTime(ms) {
        var secs = Math.floor(ms / 1000)
        var mins = Math.floor(secs / 60)
        var hours = Math.floor(mins / 60)
        secs = secs % 60
        mins = mins % 60
        if (hours > 0) {
            return hours + ":" + (mins < 10 ? "0" : "") + mins + ":" + (secs < 10 ? "0" : "") + secs
        }
        return mins + ":" + (secs < 10 ? "0" : "") + secs
    }

    Timer {
        id: controlsTimer
        interval: 4000
        onTriggered: if (isPlaying) showControls = false
    }

    // Media player
    MediaPlayer {
        id: mediaPlayer
        onStatusChanged: {
            if (status === MediaPlayer.EndOfMedia) {
                isPlaying = false
                showControls = true
            }
        }
        onError: console.log("Media error: " + errorString)
    }

    VideoOutput {
        id: videoOutput
        anchors.fill: parent
        source: mediaPlayer
        visible: currentVideo !== ""
        fillMode: VideoOutput.PreserveAspectFit

        MouseArea {
            anchors.fill: parent
            onClicked: {
                showControls = !showControls
                if (showControls) controlsTimer.restart()
            }
        }
    }

    // Video controls overlay
    Rectangle {
        anchors.fill: parent
        color: "#80000000"
        visible: currentVideo !== "" && showControls
        opacity: showControls ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 200 } }

        // Top bar with title and close
        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 100
            color: "#c0000000"

            Text {
                anchors.centerIn: parent
                text: currentVideoName
                font.pixelSize: 20 * textScale
                color: "#ffffff"
                width: parent.width - 120
                elide: Text.ElideMiddle
                horizontalAlignment: Text.AlignHCenter
            }

            Rectangle {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.rightMargin: 20
                width: 56
                height: 56
                radius: 28
                color: closeMouse.pressed ? "#e94560" : "#333344"

                Text {
                    anchors.centerIn: parent
                    text: "✕"
                    font.pixelSize: 24
                    color: "#ffffff"
                }

                MouseArea {
                    id: closeMouse
                    anchors.fill: parent
                    onClicked: stopVideo()
                }
            }
        }

        // Center play/pause button
        Rectangle {
            anchors.centerIn: parent
            width: 100
            height: 100
            radius: 50
            color: centerPlayMouse.pressed ? "#c23a50" : "#e94560"

            Text {
                anchors.centerIn: parent
                text: isPlaying ? "⏸" : "▶"
                font.pixelSize: 40
                color: "#ffffff"
            }

            MouseArea {
                id: centerPlayMouse
                anchors.fill: parent
                onClicked: togglePlayPause()
            }
        }

        // Bottom controls
        Rectangle {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: 160
            color: "#c0000000"

            Column {
                anchors.fill: parent
                anchors.margins: 20
                spacing: 16

                // Progress bar
                Rectangle {
                    width: parent.width
                    height: 8
                    radius: 4
                    color: "#333344"

                    Rectangle {
                        width: mediaPlayer.duration > 0 ? parent.width * (mediaPlayer.position / mediaPlayer.duration) : 0
                        height: parent.height
                        radius: 4
                        color: "#e94560"
                    }

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -20
                        onClicked: {
                            var pos = mouse.x / parent.width
                            mediaPlayer.seek(pos * mediaPlayer.duration)
                        }
                    }
                }

                // Time display
                Row {
                    width: parent.width

                    Text {
                        text: formatTime(mediaPlayer.position)
                        font.pixelSize: 14 * textScale
                        color: "#ffffff"
                    }

                    Item { width: parent.width - 200; height: 1 }

                    Text {
                        text: formatTime(mediaPlayer.duration)
                        font.pixelSize: 14 * textScale
                        color: "#888899"
                    }
                }

                // Control buttons
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 40

                    // Rewind 10s
                    Rectangle {
                        width: 56
                        height: 56
                        radius: 28
                        color: rew10Mouse.pressed ? "#333344" : "#222233"

                        Text {
                            anchors.centerIn: parent
                            text: "−10"
                            font.pixelSize: 16
                            color: "#ffffff"
                        }

                        MouseArea {
                            id: rew10Mouse
                            anchors.fill: parent
                            onClicked: {
                                Haptic.tap()
                                mediaPlayer.seek(Math.max(0, mediaPlayer.position - 10000))
                            }
                        }
                    }

                    // Play/Pause
                    Rectangle {
                        width: 72
                        height: 72
                        radius: 36
                        color: playMouse.pressed ? "#c23a50" : "#e94560"

                        Text {
                            anchors.centerIn: parent
                            text: isPlaying ? "⏸" : "▶"
                            font.pixelSize: 28
                            color: "#ffffff"
                        }

                        MouseArea {
                            id: playMouse
                            anchors.fill: parent
                            onClicked: togglePlayPause()
                        }
                    }

                    // Forward 10s
                    Rectangle {
                        width: 56
                        height: 56
                        radius: 28
                        color: fwd10Mouse.pressed ? "#333344" : "#222233"

                        Text {
                            anchors.centerIn: parent
                            text: "+10"
                            font.pixelSize: 16
                            color: "#ffffff"
                        }

                        MouseArea {
                            id: fwd10Mouse
                            anchors.fill: parent
                            onClicked: {
                                Haptic.tap()
                                mediaPlayer.seek(Math.min(mediaPlayer.duration, mediaPlayer.position + 10000))
                            }
                        }
                    }
                }
            }
        }
    }

    // Video library view (when no video playing)
    Rectangle {
        anchors.fill: parent
        color: "#0a0a0f"
        visible: currentVideo === ""

        // Header
        Rectangle {
            id: header
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 160
            color: "transparent"

            Column {
                anchors.centerIn: parent
                spacing: 8

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Videos"
                    font.pixelSize: 48 * textScale
                    font.weight: Font.ExtraLight
                    font.letterSpacing: 6
                    color: "#ffffff"
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: videoModel.count + " VIDEOS"
                    font.pixelSize: 12 * textScale
                    font.weight: Font.Medium
                    font.letterSpacing: 3
                    color: "#555566"
                }
            }

            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
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
                }

                MouseArea {
                    id: refreshMouse
                    anchors.fill: parent
                    onClicked: {
                        Haptic.tap()
                        startScan()
                    }
                }
            }
        }

        ListView {
            anchors.top: header.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 16
            anchors.bottomMargin: 100
            spacing: 12
            clip: true

            model: videoModel

            delegate: Rectangle {
                width: parent.width
                height: 100
                radius: 16
                color: itemMouse.pressed ? "#1a1a2e" : "#15151f"

                Row {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 16

                    // Video icon
                    Rectangle {
                        width: 68
                        height: 68
                        radius: 12
                        color: "#1a1a2e"
                        anchors.verticalCenter: parent.verticalCenter

                        Text {
                            anchors.centerIn: parent
                            text: "🎬"
                            font.pixelSize: 32
                        }
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 100
                        spacing: 4

                        Text {
                            text: model.name
                            font.pixelSize: 18 * textScale
                            font.weight: Font.Medium
                            color: "#ffffff"
                            elide: Text.ElideRight
                            width: parent.width
                        }

                        Text {
                            text: model.folder + " • " + model.fileName.split(".").pop().toUpperCase()
                            font.pixelSize: 12 * textScale
                            color: "#888899"
                        }
                    }
                }

                MouseArea {
                    id: itemMouse
                    anchors.fill: parent
                    onClicked: playVideo(model.filePath, model.name)
                }
            }

            Text {
                anchors.centerIn: parent
                text: "No videos found\n\nAdd videos to ~/Videos or ~/Movies"
                font.pixelSize: 18
                color: "#555566"
                horizontalAlignment: Text.AlignHCenter
                visible: videoModel.count === 0
            }
        }
    }

    // Back button
    Rectangle {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 24
        anchors.bottomMargin: 100
        width: 72
        height: 72
        radius: 36
        color: backMouse.pressed ? "#c23a50" : "#e94560"
        visible: currentVideo === ""
        z: 10

        Text {
            anchors.centerIn: parent
            text: "←"
            font.pixelSize: 32
            color: "#ffffff"
        }

        MouseArea {
            id: backMouse
            anchors.fill: parent
            onClicked: { Haptic.tap(); Qt.quit() }
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
        visible: currentVideo === ""
    }
}
