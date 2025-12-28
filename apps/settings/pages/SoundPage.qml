import "../../shared"
import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Page {
    id: soundPage

    property real mediaVolume: 0.7
    property real micVolume: 0.7
    property bool muted: false
    property bool micMuted: false
    property bool silentMode: false

    Component.onCompleted: loadSoundSettings()

    // Periodic refresh
    Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: loadSoundSettings()
    }

    function loadSoundSettings() {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file:///tmp/flick-sound.json", false)
        try {
            xhr.send()
            if (xhr.status === 200) {
                var data = JSON.parse(xhr.responseText)
                if (data.volume !== undefined) {
                    mediaVolume = data.volume / 100.0
                }
                if (data.muted !== undefined) {
                    muted = data.muted
                    silentMode = data.muted
                }
                if (data.mic_volume !== undefined) {
                    micVolume = data.mic_volume / 100.0
                }
                if (data.mic_muted !== undefined) {
                    micMuted = data.mic_muted
                }
            }
        } catch (e) {
            console.log("Could not read sound settings")
        }
    }

    function saveMediaVolume() {
        var percent = Math.round(mediaVolume * 100)
        console.warn("SOUND_CMD:set-volume:" + percent)
    }

    function saveMicVolume() {
        var percent = Math.round(micVolume * 100)
        console.warn("SOUND_CMD:set-mic-volume:" + percent)
    }

    function toggleMute() {
        silentMode = !silentMode
        if (silentMode) {
            console.warn("SOUND_CMD:mute")
        } else {
            console.warn("SOUND_CMD:unmute")
        }
    }

    function toggleMicMute() {
        micMuted = !micMuted
        if (micMuted) {
            console.warn("SOUND_CMD:mic-mute")
        } else {
            console.warn("SOUND_CMD:mic-unmute")
        }
    }

    background: Rectangle {
        color: "#0a0a0f"
    }

    // Hero section with volume visualization
    Rectangle {
        id: heroSection
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 260
        color: "transparent"

        // Ambient glow
        Rectangle {
            anchors.centerIn: parent
            width: 350
            height: 250
            radius: 175
            color: silentMode ? "#4a1a1a" : "#1a4a3a"
            opacity: 0.2

            Behavior on color { ColorAnimation { duration: 300 } }
        }

        Column {
            anchors.centerIn: parent
            spacing: 20

            // Sound wave visualization
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 8
                height: 80

                Repeater {
                    model: 7
                    Rectangle {
                        width: 8
                        height: silentMode ? 8 : (20 + Math.random() * 60 * mediaVolume)
                        radius: 4
                        color: silentMode ? "#4a4a5a" : "#4ade80"
                        anchors.verticalCenter: parent.verticalCenter

                        Behavior on height { NumberAnimation { duration: 150 } }
                        Behavior on color { ColorAnimation { duration: 300 } }

                        // Animate bars when not silent
                        SequentialAnimation on height {
                            running: !silentMode
                            loops: Animation.Infinite
                            NumberAnimation {
                                to: 20 + Math.random() * 60 * mediaVolume
                                duration: 200 + Math.random() * 300
                            }
                            NumberAnimation {
                                to: 30 + Math.random() * 50 * mediaVolume
                                duration: 200 + Math.random() * 300
                            }
                        }
                    }
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Sound"
                font.pixelSize: 42
                font.weight: Font.ExtraLight
                font.letterSpacing: 6
                color: "#ffffff"
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: silentMode ? "MUTED" : "VOLUME " + Math.round(mediaVolume * 100) + "%"
                font.pixelSize: 12
                font.letterSpacing: 2
                color: silentMode ? Theme.accentColor : "#555566"

                Behavior on color { ColorAnimation { duration: 300 } }
            }
        }
    }

    // Volume controls and settings
    Flickable {
        anchors.top: heroSection.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 16
        anchors.bottomMargin: 100
        contentHeight: controlsColumn.height
        clip: true

        Column {
            id: controlsColumn
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 16

            // Media volume slider
            Rectangle {
                width: controlsColumn.width
                height: 120
                radius: 24
                color: "#14141e"
                border.color: "#1a1a2e"
                border.width: 1
                opacity: silentMode ? 0.5 : 1

                Column {
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 16

                    RowLayout {
                        width: parent.width

                        Text {
                            text: "🔊"
                            font.pixelSize: 24
                        }

                        Text {
                            text: "Volume"
                            font.pixelSize: 20
                            color: "#ffffff"
                            Layout.fillWidth: true
                            Layout.leftMargin: 12
                        }

                        Text {
                            text: Math.round(mediaVolume * 100) + "%"
                            font.pixelSize: 18
                            font.weight: Font.Medium
                            color: Theme.accentColor
                        }
                    }

                    // Slider
                    Item {
                        width: parent.width
                        height: 44

                        Rectangle {
                            anchors.centerIn: parent
                            width: parent.width
                            height: 8
                            radius: 4
                            color: "#2a2a3e"

                            Rectangle {
                                width: parent.width * mediaVolume
                                height: parent.height
                                radius: 4
                                color: Theme.accentColor

                                Behavior on width { NumberAnimation { duration: 50 } }
                            }
                        }

                        Rectangle {
                            x: (parent.width - 40) * mediaVolume
                            anchors.verticalCenter: parent.verticalCenter
                            width: 40
                            height: 40
                            radius: 20
                            color: "#ffffff"
                            border.color: Theme.accentColor
                            border.width: 3

                            Behavior on x { NumberAnimation { duration: 50 } }
                        }

                        MouseArea {
                            anchors.fill: parent
                            enabled: !silentMode
                            onPressed: mediaVolume = Math.max(0, Math.min(1, mouse.x / parent.width))
                            onPositionChanged: if (pressed) mediaVolume = Math.max(0, Math.min(1, mouse.x / parent.width))
                            onReleased: saveMediaVolume()
                        }
                    }
                }
            }

            // Microphone volume slider
            Rectangle {
                width: controlsColumn.width
                height: 120
                radius: 24
                color: "#14141e"
                border.color: micMuted ? Theme.accentColor : "#1a1a2e"
                border.width: micMuted ? 2 : 1
                opacity: micMuted ? 0.5 : 1

                Column {
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 16

                    RowLayout {
                        width: parent.width

                        Text {
                            text: micMuted ? "🎙️" : "🎤"
                            font.pixelSize: 24
                        }

                        Text {
                            text: "Microphone"
                            font.pixelSize: 20
                            color: "#ffffff"
                            Layout.fillWidth: true
                            Layout.leftMargin: 12
                        }

                        Text {
                            text: micMuted ? "Muted" : Math.round(micVolume * 100) + "%"
                            font.pixelSize: 18
                            font.weight: Font.Medium
                            color: micMuted ? Theme.accentColor : "#4a8abf"
                        }
                    }

                    // Slider
                    Item {
                        width: parent.width
                        height: 44

                        Rectangle {
                            anchors.centerIn: parent
                            width: parent.width
                            height: 8
                            radius: 4
                            color: "#2a2a3e"

                            Rectangle {
                                width: parent.width * micVolume
                                height: parent.height
                                radius: 4
                                color: "#4a8abf"

                                Behavior on width { NumberAnimation { duration: 50 } }
                            }
                        }

                        Rectangle {
                            x: (parent.width - 40) * micVolume
                            anchors.verticalCenter: parent.verticalCenter
                            width: 40
                            height: 40
                            radius: 20
                            color: "#ffffff"
                            border.color: "#4a8abf"
                            border.width: 3

                            Behavior on x { NumberAnimation { duration: 50 } }
                        }

                        MouseArea {
                            anchors.fill: parent
                            enabled: !micMuted
                            onPressed: micVolume = Math.max(0, Math.min(1, mouse.x / parent.width))
                            onPositionChanged: if (pressed) micVolume = Math.max(0, Math.min(1, mouse.x / parent.width))
                            onReleased: saveMicVolume()
                        }
                    }
                }

                // Mic mute button overlay
                Rectangle {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 12
                    width: 36
                    height: 36
                    radius: 18
                    color: micMuteMouse.pressed ? "#5a2a2a" : (micMuted ? "#3a1a1a" : "#1a3a2a")

                    Text {
                        anchors.centerIn: parent
                        text: micMuted ? "🔇" : "🔈"
                        font.pixelSize: 16
                    }

                    MouseArea {
                        id: micMuteMouse
                        anchors.fill: parent
                        onClicked: toggleMicMute()
                    }
                }
            }

            Item { height: 8 }

            Text {
                text: "SOUND MODE"
                font.pixelSize: 12
                font.letterSpacing: 2
                color: "#555566"
                leftPadding: 8
            }

            // Mute toggle (replaces silent mode)
            Rectangle {
                width: controlsColumn.width
                height: 90
                radius: 24
                color: muteMouse.pressed ? "#1e1e2e" : "#14141e"
                border.color: silentMode ? Theme.accentColor : "#1a1a2e"
                border.width: silentMode ? 2 : 1

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 16

                    Rectangle {
                        Layout.preferredWidth: 52
                        Layout.preferredHeight: 52
                        radius: 14
                        color: silentMode ? "#3a1a1a" : "#1a1a28"

                        Text {
                            anchors.centerIn: parent
                            text: silentMode ? "🔇" : "🔊"
                            font.pixelSize: 26
                        }
                    }

                    Column {
                        Layout.fillWidth: true
                        spacing: 4

                        Text {
                            text: "Mute All"
                            font.pixelSize: 20
                            color: "#ffffff"
                        }

                        Text {
                            text: silentMode ? "Audio is muted" : "Audio is on"
                            font.pixelSize: 13
                            color: silentMode ? Theme.accentColor : "#666677"
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: 64
                        Layout.preferredHeight: 36
                        radius: 18
                        color: silentMode ? Theme.accentColor : "#2a2a3e"

                        Behavior on color { ColorAnimation { duration: 200 } }

                        Rectangle {
                            x: silentMode ? parent.width - width - 4 : 4
                            anchors.verticalCenter: parent.verticalCenter
                            width: 28
                            height: 28
                            radius: 14
                            color: "#ffffff"

                            Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                        }
                    }
                }

                MouseArea {
                    id: muteMouse
                    anchors.fill: parent
                    onClicked: toggleMute()
                }
            }

            Item { height: 20 }
        }
    }

    // Back button - prominent floating action button
    Rectangle {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 24
        anchors.bottomMargin: 120
        width: 72
        height: 72
        radius: 36
        color: backMouse.pressed ? Qt.darker(Theme.accentColor, 1.2) : Theme.accentColor

        Behavior on color { ColorAnimation { duration: 150 } }

        Text {
            anchors.centerIn: parent
            text: "←"
            font.pixelSize: 32
            font.weight: Font.Medium
            color: "#ffffff"
        }

        MouseArea {
            id: backMouse
            anchors.fill: parent
            onClicked: stackView.pop()
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
    }
}
