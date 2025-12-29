import QtQuick 2.15
import QtQuick.Window 2.15
import QtMultimedia 5.15

Window {
    visible: true
    width: 400
    height: 400
    title: "Audio Test"

    Audio {
        id: testAudio
        source: "sounds/beep_400_0.wav"
        volume: 0.7
    }

    Rectangle {
        anchors.fill: parent
        color: "#1a1a2e"

        Text {
            anchors.centerIn: parent
            text: "Click to test beep\n(400 Hz sine wave)"
            color: "white"
            font.pixelSize: 20
            horizontalAlignment: Text.AlignHCenter
        }

        MouseArea {
            anchors.fill: parent
            onClicked: {
                console.log("Playing beep...")
                testAudio.play()
            }
        }
    }

    Component.onCompleted: {
        console.log("Audio test ready. Click to play sound.")
        console.log("Audio source:", testAudio.source)
        console.log("Audio status:", testAudio.status)
    }
}
