import QtQuick 2.15
import QtQuick.Window 2.15
import QtQuick.Controls 2.15
import Qt.labs.folderlistmodel 2.15
import "../shared"

Window {
    id: root
    visible: true
    width: 1080
    height: 2400
    title: "Flick Recorder"
    color: "#0a0a0f"

    // Settings from Flick config
    property real textScale: 2.0

    // Recorder state
    property bool isRecording: false
    property string recordingTime: "00:00"
    property int recordingSeconds: 0
    property string currentRecordingFile: ""
    property string recordingsDir: "/home/droidian/Recordings"
    property int audioLevel: 0

    // Playback state
    property bool isPlaying: false
    property string playingFile: ""
    property int playbackPosition: 0
    property int playbackDuration: 0

    Component.onCompleted: {
        loadConfig()
        loadRecordings()
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

    ListModel {
        id: recordingsModel
    }

    function loadRecordings() {
        recordingsModel.clear()
        // Request scan from shell
        var xhr = new XMLHttpRequest()
        xhr.open("PUT", "file:///tmp/flick_recorder_scan_request", false)
        try {
            xhr.send(recordingsDir)
        } catch (e) {}

        loadRecordingsTimer.start()
    }

    Timer {
        id: loadRecordingsTimer
        interval: 500
        repeat: true
        onTriggered: {
            var xhr = new XMLHttpRequest()
            xhr.open("GET", "file:///tmp/flick_recorder_files", false)
            try {
                xhr.send()
                if (xhr.status === 200 || xhr.status === 0) {
                    var content = xhr.responseText.trim()
                    if (content.length > 0 && content !== "scanned") {
                        var files = content.split("\n")
                        recordingsModel.clear()
                        for (var i = 0; i < files.length; i++) {
                            var file = files[i].trim()
                            if (file !== "" && (file.endsWith(".wav") || file.endsWith(".opus"))) {
                                var displayName = file.replace(/\.(wav|opus)$/, "")
                                recordingsModel.append({
                                    fileName: file,
                                    displayName: displayName,
                                    filePath: recordingsDir + "/" + file
                                })
                            }
                        }
                        // Mark as processed
                        var clearXhr = new XMLHttpRequest()
                        clearXhr.open("PUT", "file:///tmp/flick_recorder_files", false)
                        try {
                            clearXhr.send("scanned")
                        } catch (e) {}
                    }
                }
            } catch (e) {}
        }
    }

    function startRecording() {
        Haptic.click()
        var timestamp = new Date().toISOString().replace(/[:.]/g, "-").replace("T", "_").substring(0, 19)
        currentRecordingFile = "recording_" + timestamp + ".wav"
        recordingSeconds = 0
        recordingTime = "00:00"
        isRecording = true

        // Signal to shell to start recording
        console.log("START_RECORDING:" + recordingsDir + "/" + currentRecordingFile)

        recordingTimer.start()
    }

    function stopRecording() {
        Haptic.click()
        isRecording = false
        recordingTimer.stop()

        // Signal to shell to stop recording
        console.log("STOP_RECORDING")

        // Reload recordings list
        setTimeout(function() {
            loadRecordings()
        }, 500)
    }

    function setTimeout(callback, delay) {
        var timer = Qt.createQmlObject("import QtQuick 2.15; Timer {}", root)
        timer.interval = delay
        timer.repeat = false
        timer.triggered.connect(callback)
        timer.start()
    }

    function playRecording(filePath) {
        Haptic.tap()
        if (isPlaying && playingFile === filePath) {
            // Stop playback
            console.log("STOP_PLAYBACK")
            isPlaying = false
            playingFile = ""
        } else {
            // Start playback
            console.log("PLAY_RECORDING:" + filePath)
            isPlaying = true
            playingFile = filePath
        }
    }

    function deleteRecording(fileName) {
        Haptic.heavy()
        console.log("DELETE_RECORDING:" + recordingsDir + "/" + fileName)
        setTimeout(function() {
            loadRecordings()
        }, 200)
    }

    function formatTime(seconds) {
        var mins = Math.floor(seconds / 60)
        var secs = seconds % 60
        return (mins < 10 ? "0" : "") + mins + ":" + (secs < 10 ? "0" : "") + secs
    }

    Timer {
        id: recordingTimer
        interval: 1000
        running: false
        repeat: true
        onTriggered: {
            recordingSeconds++
            recordingTime = formatTime(recordingSeconds)

            // Update audio level (simulate waveform)
            audioLevel = Math.floor(Math.random() * 60) + 20
        }
    }

    // Check playback status
    Timer {
        interval: 500
        running: isPlaying
        repeat: true
        onTriggered: {
            var xhr = new XMLHttpRequest()
            xhr.open("GET", "file:///tmp/flick_recorder_playback_status", false)
            try {
                xhr.send()
                if (xhr.status === 200 || xhr.status === 0) {
                    var status = xhr.responseText.trim()
                    if (status === "stopped") {
                        isPlaying = false
                        playingFile = ""
                    }
                }
            } catch (e) {}
        }
    }

    // Large hero header
    Rectangle {
        id: headerArea
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 180
        color: "transparent"
        z: 1

        // Ambient glow effect
        Rectangle {
            anchors.centerIn: parent
            width: 300
            height: 200
            radius: 150
            color: "#e94560"
            opacity: isRecording ? 0.15 : 0.08

            Behavior on opacity { NumberAnimation { duration: 500 } }

            NumberAnimation on opacity {
                from: isRecording ? 0.10 : 0.05
                to: isRecording ? 0.20 : 0.12
                duration: 1500
                loops: Animation.Infinite
                easing.type: Easing.InOutSine
                running: isRecording
            }
        }

        Column {
            anchors.centerIn: parent
            spacing: 8

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Recorder"
                font.pixelSize: 48 * textScale
                font.weight: Font.ExtraLight
                font.letterSpacing: 6
                color: "#ffffff"
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: isRecording ? "RECORDING" : (recordingsModel.count + " RECORDINGS")
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
                    loadRecordings()
                }
            }
        }
    }

    // Recording control area
    Rectangle {
        id: recordingArea
        anchors.top: headerArea.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: 400
        color: "transparent"

        Column {
            anchors.centerIn: parent
            spacing: 32

            // Recording visualization
            Rectangle {
                id: visualizerArea
                anchors.horizontalCenter: parent.horizontalCenter
                width: 300
                height: 120
                radius: 16
                color: "#1a1a2e"
                border.color: isRecording ? "#e94560" : "#333344"
                border.width: 2

                Behavior on border.color { ColorAnimation { duration: 300 } }

                // Simple waveform visualization
                Row {
                    anchors.centerIn: parent
                    spacing: 4

                    Repeater {
                        model: 20
                        Rectangle {
                            width: 8
                            height: isRecording ? (20 + Math.random() * audioLevel) : 20
                            radius: 4
                            color: "#e94560"
                            opacity: isRecording ? 0.3 + Math.random() * 0.4 : 0.2

                            Behavior on height {
                                NumberAnimation { duration: 150 }
                            }
                        }
                    }
                }

                // Recording icon when not recording
                Text {
                    anchors.centerIn: parent
                    text: "🎙"
                    font.pixelSize: 60
                    opacity: isRecording ? 0 : 0.3
                    visible: !isRecording
                }
            }

            // Recording time
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: recordingTime
                font.pixelSize: 64
                font.weight: Font.Bold
                font.family: "monospace"
                color: isRecording ? "#e94560" : "#666677"

                Behavior on color { ColorAnimation { duration: 300 } }
            }

            // Recording filename
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: isRecording ? currentRecordingFile : "Ready to record"
                font.pixelSize: 14 * textScale
                color: "#888899"
                width: 400
                elide: Text.ElideMiddle
                horizontalAlignment: Text.AlignHCenter
            }

            // Record button
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 100
                height: 100
                radius: 50
                color: recordMouse.pressed ? (isRecording ? "#c23a50" : "#c23a50") : (isRecording ? "#e94560" : "#e94560")
                border.color: "#ffffff"
                border.width: 4

                Rectangle {
                    anchors.centerIn: parent
                    width: isRecording ? 40 : 0
                    height: isRecording ? 40 : 0
                    radius: isRecording ? 4 : 30
                    color: "#ffffff"

                    Behavior on width { NumberAnimation { duration: 200 } }
                    Behavior on height { NumberAnimation { duration: 200 } }
                    Behavior on radius { NumberAnimation { duration: 200 } }
                }

                // Record dot when not recording
                Rectangle {
                    anchors.centerIn: parent
                    width: isRecording ? 0 : 60
                    height: isRecording ? 0 : 60
                    radius: 30
                    color: "#ffffff"

                    Behavior on width { NumberAnimation { duration: 200 } }
                    Behavior on height { NumberAnimation { duration: 200 } }
                }

                MouseArea {
                    id: recordMouse
                    anchors.fill: parent
                    onClicked: {
                        if (isRecording) {
                            stopRecording()
                        } else {
                            startRecording()
                        }
                    }
                }
            }
        }
    }

    // Recordings list
    Rectangle {
        id: listHeader
        anchors.top: recordingArea.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: 60
        color: "transparent"

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 24
            anchors.verticalCenter: parent.verticalCenter
            text: "Previous Recordings"
            font.pixelSize: 20 * textScale
            font.weight: Font.Medium
            color: "#ffffff"
        }
    }

    ListView {
        id: recordingsList
        anchors.top: listHeader.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 16
        anchors.bottomMargin: 120
        spacing: 8
        clip: true

        model: recordingsModel

        delegate: Rectangle {
            width: recordingsList.width
            height: 80
            radius: 12
            color: itemMouse.pressed ? "#1a1a2e" : "#15151f"
            border.color: (isPlaying && playingFile === model.filePath) ? "#e94560" : "#222233"
            border.width: (isPlaying && playingFile === model.filePath) ? 2 : 1

            Behavior on color { ColorAnimation { duration: 150 } }

            Row {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 12

                // Play icon
                Rectangle {
                    width: 56
                    height: 56
                    radius: 28
                    color: "#1a1a2e"
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        anchors.centerIn: parent
                        text: (isPlaying && playingFile === model.filePath) ? "⏸" : "▶"
                        font.pixelSize: 24
                        color: "#e94560"
                    }
                }

                // Recording info
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 140
                    spacing: 4

                    Text {
                        text: model.displayName
                        font.pixelSize: 16 * textScale
                        font.weight: Font.Medium
                        color: "#ffffff"
                        elide: Text.ElideRight
                        width: parent.width
                    }

                    Text {
                        text: model.fileName
                        font.pixelSize: 12 * textScale
                        color: "#888899"
                        elide: Text.ElideRight
                        width: parent.width
                    }
                }

                // Delete button
                Rectangle {
                    width: 48
                    height: 48
                    radius: 24
                    color: deleteMouse.pressed ? "#c23a50" : "#3a3a4e"
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        anchors.centerIn: parent
                        text: "✕"
                        font.pixelSize: 20
                        color: "#ffffff"
                    }

                    MouseArea {
                        id: deleteMouse
                        anchors.fill: parent
                        onClicked: {
                            deleteDialog.recordingToDelete = model.fileName
                            deleteDialog.visible = true
                        }
                    }
                }
            }

            MouseArea {
                id: itemMouse
                anchors.fill: parent
                anchors.rightMargin: 60
                onClicked: playRecording(model.filePath)
            }
        }

        // Empty state
        Text {
            anchors.centerIn: parent
            text: "No recordings yet\n\nTap the record button to start"
            font.pixelSize: 18
            color: "#555566"
            horizontalAlignment: Text.AlignHCenter
            visible: recordingsModel.count === 0
        }

        ScrollBar.vertical: ScrollBar {
            active: true
            policy: ScrollBar.AsNeeded
        }
    }

    // Delete dialog
    Rectangle {
        id: deleteDialog
        anchors.fill: parent
        color: "#c0000000"
        visible: false
        z: 100

        property string recordingToDelete: ""

        MouseArea {
            anchors.fill: parent
            onClicked: deleteDialog.visible = false
        }

        Rectangle {
            anchors.centerIn: parent
            width: 320
            height: 200
            radius: 20
            color: "#1a1a2e"

            Column {
                anchors.centerIn: parent
                spacing: 24

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Delete recording?"
                    font.pixelSize: 20
                    color: "#ffffff"
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 20

                    Rectangle {
                        width: 120
                        height: 48
                        radius: 24
                        color: cancelMouse.pressed ? "#333344" : "#252538"

                        Text {
                            anchors.centerIn: parent
                            text: "Cancel"
                            font.pixelSize: 16
                            color: "#ffffff"
                        }

                        MouseArea {
                            id: cancelMouse
                            anchors.fill: parent
                            onClicked: { Haptic.tap(); deleteDialog.visible = false }
                        }
                    }

                    Rectangle {
                        width: 120
                        height: 48
                        radius: 24
                        color: confirmDeleteMouse.pressed ? "#c23a50" : "#e94560"

                        Text {
                            anchors.centerIn: parent
                            text: "Delete"
                            font.pixelSize: 16
                            color: "#ffffff"
                        }

                        MouseArea {
                            id: confirmDeleteMouse
                            anchors.fill: parent
                            onClicked: {
                                deleteRecording(deleteDialog.recordingToDelete)
                                deleteDialog.visible = false
                            }
                        }
                    }
                }
            }
        }
    }

    // Back button
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
            onClicked: { Haptic.tap(); Qt.quit() }
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
