import "../../shared"
import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Page {
    id: aboutPage

    property string hostname: "flick"
    property string osName: "Linux"
    property string kernelVersion: "6.1.0"
    property string arch: "aarch64"
    property string uptime: "0m"
    property string cpuModel: "Unknown"
    property int cpuCores: 4
    property real ramTotal: 4.0
    property real storageTotal: 64.0
    property real storageUsed: 32.0

    Component.onCompleted: loadSystemInfo()

    function loadSystemInfo() {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file:///tmp/flick-system.json", false)
        try {
            xhr.send()
            if (xhr.status === 200) {
                var data = JSON.parse(xhr.responseText)
                hostname = data.hostname || "unknown"
                osName = data.os || "Linux"
                kernelVersion = data.kernel || "unknown"
                arch = data.arch || "unknown"
                uptime = data.uptime || "0m"
                cpuModel = data.cpu || "Unknown"
                cpuCores = data.cores || 1
            }
        } catch (e) {
            console.log("Could not read system info")
        }

        // Load memory info
        var xhr2 = new XMLHttpRequest()
        xhr2.open("GET", "file:///tmp/flick-memory.json", false)
        try {
            xhr2.send()
            if (xhr2.status === 200) {
                var mem = JSON.parse(xhr2.responseText)
                ramTotal = mem.total_gb || 0
            }
        } catch (e) {}

        // Load storage info
        var xhr3 = new XMLHttpRequest()
        xhr3.open("GET", "file:///tmp/flick-storage.json", false)
        try {
            xhr3.send()
            if (xhr3.status === 200) {
                var stor = JSON.parse(xhr3.responseText)
                storageTotal = stor.total_gb || 0
                storageUsed = stor.used_gb || 0
            }
        } catch (e) {}
    }

    background: Rectangle {
        color: "#0a0a0f"
    }

    // Hero section with animated logo
    Rectangle {
        id: heroSection
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 300
        color: "transparent"

        // Animated background particles
        Repeater {
            model: 20
            Rectangle {
                property real startX: Math.random() * heroSection.width
                property real startY: Math.random() * heroSection.height

                x: startX
                y: startY
                width: 2 + Math.random() * 4
                height: width
                radius: width / 2
                color: Theme.accentColor
                opacity: 0.1 + Math.random() * 0.2

                SequentialAnimation on y {
                    loops: Animation.Infinite
                    NumberAnimation {
                        to: startY - 50 - Math.random() * 100
                        duration: 3000 + Math.random() * 4000
                        easing.type: Easing.InOutSine
                    }
                    NumberAnimation {
                        to: startY
                        duration: 3000 + Math.random() * 4000
                        easing.type: Easing.InOutSine
                    }
                }

                SequentialAnimation on opacity {
                    loops: Animation.Infinite
                    NumberAnimation {
                        to: 0.3 + Math.random() * 0.3
                        duration: 2000 + Math.random() * 2000
                    }
                    NumberAnimation {
                        to: 0.1
                        duration: 2000 + Math.random() * 2000
                    }
                }
            }
        }

        Column {
            anchors.centerIn: parent
            spacing: 16

            // Large logo with pulsing glow
            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 120
                height: 120

                // Outer glow ring
                Rectangle {
                    anchors.centerIn: parent
                    width: 160
                    height: 160
                    radius: 80
                    color: "transparent"
                    border.color: Theme.accentColor
                    border.width: 2
                    opacity: 0

                    SequentialAnimation on opacity {
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.4; duration: 1500 }
                        NumberAnimation { to: 0; duration: 1500 }
                    }

                    SequentialAnimation on scale {
                        loops: Animation.Infinite
                        NumberAnimation { from: 0.8; to: 1.2; duration: 3000 }
                    }
                }

                // Main logo
                Rectangle {
                    anchors.centerIn: parent
                    width: 100
                    height: 100
                    radius: 25

                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Theme.accentColor }
                        GradientStop { position: 1.0; color: Qt.darker(Theme.accentColor, 1.2) }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: "⚡"
                        font.pixelSize: 50
                    }
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Flick"
                font.pixelSize: 48
                font.weight: Font.ExtraLight
                font.letterSpacing: 8
                color: "#ffffff"
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "MOBILE SHELL FOR LINUX"
                font.pixelSize: 12
                font.letterSpacing: 3
                color: "#555566"
            }
        }
    }

    // Info section
    Flickable {
        anchors.top: heroSection.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 16
        anchors.bottomMargin: 100
        contentHeight: infoColumn.height
        clip: true

        Column {
            id: infoColumn
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 16

            // Device info card
            Rectangle {
                width: infoColumn.width
                height: deviceInfoColumn.height + 32
                radius: 24
                color: "#14141e"
                border.color: "#1a1a2e"
                border.width: 1

                Column {
                    id: deviceInfoColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 16
                    spacing: 0

                    Text {
                        text: "DEVICE"
                        font.pixelSize: 12
                        font.letterSpacing: 2
                        color: "#555566"
                        leftPadding: 8
                        bottomPadding: 8
                    }

                    Repeater {
                        model: ListModel {
                            ListElement { label: "Name"; prop: "hostname" }
                            ListElement { label: "OS"; prop: "osName" }
                            ListElement { label: "Kernel"; prop: "kernelVersion" }
                            ListElement { label: "Architecture"; prop: "arch" }
                            ListElement { label: "Uptime"; prop: "uptime" }
                        }

                        Item {
                            width: deviceInfoColumn.width
                            height: 48

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8

                                Text {
                                    text: model.label
                                    font.pixelSize: 16
                                    color: "#666677"
                                    Layout.fillWidth: true
                                }

                                Text {
                                    text: {
                                        if (model.prop === "hostname") return hostname
                                        if (model.prop === "osName") return osName
                                        if (model.prop === "kernelVersion") return kernelVersion
                                        if (model.prop === "arch") return arch
                                        if (model.prop === "uptime") return uptime
                                        return ""
                                    }
                                    font.pixelSize: 16
                                    font.weight: Font.Medium
                                    color: "#ffffff"
                                }
                            }

                            Rectangle {
                                anchors.bottom: parent.bottom
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                height: 1
                                color: "#1a1a2e"
                                visible: index < 4
                            }
                        }
                    }
                }
            }

            // Hardware card
            Rectangle {
                width: infoColumn.width
                height: hardwareColumn.height + 32
                radius: 24
                color: "#14141e"
                border.color: "#1a1a2e"
                border.width: 1

                Column {
                    id: hardwareColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 16
                    spacing: 0

                    Text {
                        text: "HARDWARE"
                        font.pixelSize: 12
                        font.letterSpacing: 2
                        color: "#555566"
                        leftPadding: 8
                        bottomPadding: 8
                    }

                    // CPU
                    Item {
                        width: parent.width
                        height: 48

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8

                            Text {
                                text: "CPU"
                                font.pixelSize: 16
                                color: "#666677"
                                Layout.fillWidth: true
                            }

                            Text {
                                text: cpuCores + " cores"
                                font.pixelSize: 16
                                font.weight: Font.Medium
                                color: "#ffffff"
                            }
                        }

                        Rectangle {
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            height: 1
                            color: "#1a1a2e"
                        }
                    }

                    // RAM
                    Item {
                        width: parent.width
                        height: 48

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8

                            Text {
                                text: "RAM"
                                font.pixelSize: 16
                                color: "#666677"
                                Layout.fillWidth: true
                            }

                            Text {
                                text: ramTotal.toFixed(1) + " GB"
                                font.pixelSize: 16
                                font.weight: Font.Medium
                                color: "#ffffff"
                            }
                        }

                        Rectangle {
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            height: 1
                            color: "#1a1a2e"
                        }
                    }

                    // Storage
                    Item {
                        width: parent.width
                        height: 48

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8

                            Text {
                                text: "Storage"
                                font.pixelSize: 16
                                color: "#666677"
                                Layout.fillWidth: true
                            }

                            Text {
                                text: storageUsed.toFixed(1) + " / " + storageTotal.toFixed(1) + " GB"
                                font.pixelSize: 16
                                font.weight: Font.Medium
                                color: "#ffffff"
                            }
                        }
                    }
                }
            }

            // Software card
            Rectangle {
                width: infoColumn.width
                height: softwareColumn.height + 32
                radius: 24
                color: "#14141e"
                border.color: "#1a1a2e"
                border.width: 1

                Column {
                    id: softwareColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 16
                    spacing: 0

                    Text {
                        text: "SOFTWARE"
                        font.pixelSize: 12
                        font.letterSpacing: 2
                        color: "#555566"
                        leftPadding: 8
                        bottomPadding: 8
                    }

                    Repeater {
                        model: ListModel {
                            ListElement { label: "Flick Version"; value: "0.1.0" }
                            ListElement { label: "Compositor"; value: "Smithay" }
                            ListElement { label: "UI Framework"; value: "Slint + Qt5" }
                            ListElement { label: "License"; value: "GPL-3.0" }
                        }

                        Item {
                            width: softwareColumn.width
                            height: 48

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8

                                Text {
                                    text: model.label
                                    font.pixelSize: 16
                                    color: "#666677"
                                    Layout.fillWidth: true
                                }

                                Text {
                                    text: model.value
                                    font.pixelSize: 16
                                    font.weight: Font.Medium
                                    color: model.label === "Flick Version" ? Theme.accentColor : "#ffffff"
                                }
                            }

                            Rectangle {
                                anchors.bottom: parent.bottom
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                height: 1
                                color: "#1a1a2e"
                                visible: index < 3
                            }
                        }
                    }
                }
            }

            // GitHub link
            Rectangle {
                width: infoColumn.width
                height: 70
                radius: 24
                color: githubMouse.pressed ? "#2a2a3e" : "#14141e"
                border.color: "#1a1a2e"
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 16

                    Text {
                        text: "🔗"
                        font.pixelSize: 24
                    }

                    Column {
                        Layout.fillWidth: true
                        spacing: 4

                        Text {
                            text: "Source Code"
                            font.pixelSize: 17
                            color: "#ffffff"
                        }

                        Text {
                            text: "github.com/ruapotato/Flick"
                            font.pixelSize: 13
                            color: Theme.accentColor
                        }
                    }

                    Text {
                        text: "→"
                        font.pixelSize: 24
                        color: "#444455"
                    }
                }

                MouseArea {
                    id: githubMouse
                    anchors.fill: parent
                    onClicked: Qt.openUrlExternally("https://github.com/ruapotato/Flick")
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
