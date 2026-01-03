import QtQuick 2.15
import QtQuick.Window 2.15

Window {
    visible: true
    visibility: Window.FullScreen
    title: "Test"
    color: "#ff0000"  // Bright red background

    Rectangle {
        anchors.centerIn: parent
        width: 400
        height: 200
        color: "#00ff00"  // Green rectangle in center

        Text {
            anchors.centerIn: parent
            text: "TEST"
            font.pixelSize: 22
            color: "#0000ff"  // Blue text
        }
    }
}
