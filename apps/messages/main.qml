import QtQuick 2.15
import QtQuick.Window 2.15
import QtQuick.Controls 2.15

Window {
    id: root
    visible: true
    width: 1080
    height: 2400
    title: "Messages"
    color: "#0a0a0f"

    property real textScale: 2.0

    Component.onCompleted: {
        loadConfig()
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

    Timer {
        interval: 3000
        running: true
        repeat: true
        onTriggered: loadConfig()
    }

    // Main content - centered
    Item {
        anchors.fill: parent
        anchors.bottomMargin: 80

        Column {
            anchors.centerIn: parent
            spacing: 20 * textScale

            // Icon
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "💬"
                font.pixelSize: 120 * textScale
            }

            // App name
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Messages"
                color: "#e94560"
                font.pixelSize: 48 * textScale
                font.weight: Font.Bold
            }

            // Coming soon text
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Coming Soon"
                color: "#ffffff"
                font.pixelSize: 24 * textScale
                font.weight: Font.Medium
            }
        }
    }

    // Back button (bottom-right)
    Rectangle {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 20
        anchors.bottomMargin: 100
        width: 72
        height: 72
        radius: 36
        color: "#e94560"
        z: 100

        Text {
            anchors.centerIn: parent
            text: "←"
            color: "#ffffff"
            font.pixelSize: 36
            font.weight: Font.Bold
        }

        MouseArea {
            anchors.fill: parent
            onClicked: Qt.quit()
        }
    }

    // Home indicator bar
    Rectangle {
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottomMargin: 10
        width: 200
        height: 6
        radius: 3
        color: "#444466"
    }
}
