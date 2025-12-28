import QtQuick 2.15
import QtQuick.Window 2.15
import QtQuick.Controls 2.15
import "../shared"

Window {
    id: root
    visible: true
    width: 1080
    height: 2400
    title: "Flick Maps"
    color: "#0a0a0f"

    property real textScale: 2.0

    Component.onCompleted: loadConfig()

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

    // Main content
    Column {
        anchors.centerIn: parent
        spacing: 48
        width: parent.width - 80

        // Map icon
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "\ud83d\uddfa\ufe0f"
            font.pixelSize: 120
        }

        // Title
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Maps"
            font.pixelSize: 36 * textScale
            font.weight: Font.Medium
            color: "#ffffff"
        }

        // Description
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width
            text: "Maps functionality coming soon.\n\nFor now, you can use the web browser to access online maps."
            font.pixelSize: 18 * textScale
            color: "#888899"
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            lineHeight: 1.4
        }

        // Spacer
        Item { width: 1; height: 40 }

        // Quick links
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Quick Links"
            font.pixelSize: 20 * textScale
            font.weight: Font.Medium
            color: "#ffffff"
        }

        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 16

            // OpenStreetMap button
            Rectangle {
                width: 400
                height: 72
                radius: 16
                color: osmMouse.pressed ? "#333344" : "#1a1a2e"
                anchors.horizontalCenter: parent.horizontalCenter

                Row {
                    anchors.centerIn: parent
                    spacing: 16

                    Text {
                        text: "\ud83c\udf0d"
                        font.pixelSize: 28
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: "OpenStreetMap"
                        font.pixelSize: 18 * textScale
                        color: "#ffffff"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                MouseArea {
                    id: osmMouse
                    anchors.fill: parent
                    onClicked: {
                        Haptic.tap()
                        Qt.openUrlExternally("https://www.openstreetmap.org")
                    }
                }
            }

            // Google Maps button
            Rectangle {
                width: 400
                height: 72
                radius: 16
                color: gmapsMouse.pressed ? "#333344" : "#1a1a2e"
                anchors.horizontalCenter: parent.horizontalCenter

                Row {
                    anchors.centerIn: parent
                    spacing: 16

                    Text {
                        text: "\ud83d\udccd"
                        font.pixelSize: 28
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: "Google Maps"
                        font.pixelSize: 18 * textScale
                        color: "#ffffff"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                MouseArea {
                    id: gmapsMouse
                    anchors.fill: parent
                    onClicked: {
                        Haptic.tap()
                        Qt.openUrlExternally("https://maps.google.com")
                    }
                }
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
        z: 10

        Text {
            anchors.centerIn: parent
            text: "\u2190"
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
    }
}
