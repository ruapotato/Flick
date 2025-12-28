import "../../shared"
import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Page {
    id: storagePage

    property real totalGb: 64
    property real usedGb: 32
    property real freeGb: 32
    property int percentUsed: 50
    property real homeGb: 10
    property real memTotalGb: 4
    property real memUsedGb: 2
    property int memPercent: 50

    Component.onCompleted: {
        loadStorageInfo()
        loadMemoryInfo()
    }

    Timer {
        interval: 10000
        running: true
        repeat: true
        onTriggered: {
            loadStorageInfo()
            loadMemoryInfo()
        }
    }

    function loadStorageInfo() {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file:///tmp/flick-storage.json", false)
        try {
            xhr.send()
            if (xhr.status === 200) {
                var data = JSON.parse(xhr.responseText)
                totalGb = data.total_gb || 0
                usedGb = data.used_gb || 0
                freeGb = data.free_gb || 0
                percentUsed = data.percent_used || 0
                homeGb = data.home_gb || 0
            }
        } catch (e) {
            console.log("Could not read storage info")
        }
    }

    function loadMemoryInfo() {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file:///tmp/flick-memory.json", false)
        try {
            xhr.send()
            if (xhr.status === 200) {
                var data = JSON.parse(xhr.responseText)
                memTotalGb = data.total_gb || 0
                memUsedGb = data.used_gb || 0
                memPercent = data.percent_used || 0
            }
        } catch (e) {
            console.log("Could not read memory info")
        }
    }

    function getStorageColor() {
        if (percentUsed >= 90) return "#ef4444"
        if (percentUsed >= 75) return "#f59e0b"
        return "#4a8abf"
    }

    function getMemoryColor() {
        if (memPercent >= 90) return "#ef4444"
        if (memPercent >= 75) return "#f59e0b"
        return "#8b5cf6"
    }

    background: Rectangle {
        color: "#0a0a0f"
    }

    // Hero section with storage visualization
    Rectangle {
        id: heroSection
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 300
        color: "transparent"

        // Ambient glow
        Rectangle {
            anchors.centerIn: parent
            width: 350
            height: 260
            radius: 175
            color: getStorageColor()
            opacity: 0.12
        }

        Column {
            anchors.centerIn: parent
            spacing: 20

            // Circular progress
            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 160
                height: 160

                // Background circle
                Rectangle {
                    anchors.fill: parent
                    radius: 80
                    color: "transparent"
                    border.color: "#2a2a3e"
                    border.width: 12
                }

                // Progress arc (simplified as a thick border)
                Canvas {
                    id: progressCanvas
                    anchors.fill: parent

                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.reset()

                        var centerX = width / 2
                        var centerY = height / 2
                        var radius = width / 2 - 6

                        // Draw progress arc
                        ctx.beginPath()
                        ctx.lineWidth = 12
                        ctx.strokeStyle = getStorageColor()
                        ctx.lineCap = "round"
                        ctx.arc(centerX, centerY, radius, -Math.PI / 2, -Math.PI / 2 + (2 * Math.PI * percentUsed / 100))
                        ctx.stroke()
                    }

                    Connections {
                        target: storagePage
                        function onPercentUsedChanged() {
                            progressCanvas.requestPaint()
                        }
                    }
                }

                // Center text
                Column {
                    anchors.centerIn: parent
                    spacing: 4

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: percentUsed + "%"
                        font.pixelSize: 36
                        font.weight: Font.Bold
                        color: "#ffffff"
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "used"
                        font.pixelSize: 14
                        color: "#666677"
                    }
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Storage"
                font.pixelSize: 42
                font.weight: Font.ExtraLight
                font.letterSpacing: 6
                color: "#ffffff"
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: usedGb.toFixed(1) + " GB of " + totalGb.toFixed(1) + " GB"
                font.pixelSize: 14
                color: "#555566"
            }
        }
    }

    // Storage details
    Flickable {
        anchors.top: heroSection.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 16
        anchors.bottomMargin: 100
        contentHeight: detailsColumn.height
        clip: true

        Column {
            id: detailsColumn
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 16

            // Storage breakdown card
            Rectangle {
                width: detailsColumn.width
                height: 180
                radius: 24
                color: "#14141e"
                border.color: "#1a1a2e"
                border.width: 1

                Column {
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 16

                    Text {
                        text: "STORAGE BREAKDOWN"
                        font.pixelSize: 12
                        font.letterSpacing: 2
                        color: "#555566"
                    }

                    // Used storage bar
                    Column {
                        width: parent.width
                        spacing: 8

                        RowLayout {
                            width: parent.width

                            Text {
                                text: "💾 Used"
                                font.pixelSize: 16
                                color: "#ffffff"
                                Layout.fillWidth: true
                            }

                            Text {
                                text: usedGb.toFixed(1) + " GB"
                                font.pixelSize: 16
                                font.weight: Font.Medium
                                color: getStorageColor()
                            }
                        }

                        Rectangle {
                            width: parent.width
                            height: 8
                            radius: 4
                            color: "#2a2a3e"

                            Rectangle {
                                width: parent.width * (percentUsed / 100)
                                height: parent.height
                                radius: 4
                                color: getStorageColor()

                                Behavior on width { NumberAnimation { duration: 500 } }
                            }
                        }
                    }

                    // Free storage bar
                    Column {
                        width: parent.width
                        spacing: 8

                        RowLayout {
                            width: parent.width

                            Text {
                                text: "📁 Available"
                                font.pixelSize: 16
                                color: "#ffffff"
                                Layout.fillWidth: true
                            }

                            Text {
                                text: freeGb.toFixed(1) + " GB"
                                font.pixelSize: 16
                                font.weight: Font.Medium
                                color: "#4ade80"
                            }
                        }

                        Rectangle {
                            width: parent.width
                            height: 8
                            radius: 4
                            color: "#2a2a3e"

                            Rectangle {
                                width: parent.width * ((100 - percentUsed) / 100)
                                height: parent.height
                                radius: 4
                                color: "#4ade80"

                                Behavior on width { NumberAnimation { duration: 500 } }
                            }
                        }
                    }
                }
            }

            // Memory card
            Rectangle {
                width: detailsColumn.width
                height: 140
                radius: 24
                color: "#14141e"
                border.color: "#1a1a2e"
                border.width: 1

                Column {
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 16

                    RowLayout {
                        width: parent.width

                        Text {
                            text: "🧠 Memory (RAM)"
                            font.pixelSize: 18
                            color: "#ffffff"
                            Layout.fillWidth: true
                        }

                        Text {
                            text: memPercent + "%"
                            font.pixelSize: 18
                            font.weight: Font.Bold
                            color: getMemoryColor()
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 12
                        radius: 6
                        color: "#2a2a3e"

                        Rectangle {
                            width: parent.width * (memPercent / 100)
                            height: parent.height
                            radius: 6
                            color: getMemoryColor()

                            Behavior on width { NumberAnimation { duration: 500 } }
                        }
                    }

                    Text {
                        text: memUsedGb.toFixed(2) + " GB of " + memTotalGb.toFixed(2) + " GB used"
                        font.pixelSize: 14
                        color: "#666677"
                    }
                }
            }

            // Home folder usage
            Rectangle {
                width: detailsColumn.width
                height: 80
                radius: 24
                color: "#14141e"
                border.color: "#1a1a2e"
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 16

                    Rectangle {
                        Layout.preferredWidth: 44
                        Layout.preferredHeight: 44
                        radius: 12
                        color: "#1a2a3a"

                        Text {
                            anchors.centerIn: parent
                            text: "🏠"
                            font.pixelSize: 22
                        }
                    }

                    Column {
                        Layout.fillWidth: true
                        spacing: 4

                        Text {
                            text: "Home Folder"
                            font.pixelSize: 17
                            color: "#ffffff"
                        }

                        Text {
                            text: homeGb.toFixed(2) + " GB"
                            font.pixelSize: 14
                            color: "#666677"
                        }
                    }
                }
            }

            Item { height: 20 }
        }
    }

    // Back button
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
