import "../../shared"
import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Page {
    id: bluetoothPage

    property bool btEnabled: true
    property bool isScanning: false

    // Device models
    ListModel {
        id: pairedDevicesModel
    }

    ListModel {
        id: availableDevicesModel
    }

    Component.onCompleted: {
        loadBluetoothStatus()
        loadPairedDevices()
        loadAvailableDevices()
    }

    // Periodic refresh timer
    Timer {
        interval: 3000
        running: btEnabled
        repeat: true
        onTriggered: {
            loadBluetoothStatus()
            loadPairedDevices()
            if (isScanning) {
                loadAvailableDevices()
            }
        }
    }

    // Auto-stop scan after 30 seconds
    Timer {
        id: scanTimer
        interval: 30000
        running: isScanning
        onTriggered: {
            isScanning = false
            console.warn("BT_CMD:scan-stop")
        }
    }

    function loadBluetoothStatus() {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file:///tmp/flick-bt-status.json", false)
        try {
            xhr.send()
            if (xhr.status === 200) {
                var status = JSON.parse(xhr.responseText)
                btEnabled = status.enabled
            }
        } catch (e) {
            console.log("Could not read BT status")
        }
    }

    function loadPairedDevices() {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file:///tmp/flick-bt-paired.json", false)
        try {
            xhr.send()
            if (xhr.status === 200) {
                var devices = JSON.parse(xhr.responseText)
                pairedDevicesModel.clear()
                for (var i = 0; i < devices.length; i++) {
                    pairedDevicesModel.append(devices[i])
                }
            }
        } catch (e) {
            console.log("Could not read paired devices")
        }
    }

    function loadAvailableDevices() {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file:///tmp/flick-bt-available.json", false)
        try {
            xhr.send()
            if (xhr.status === 200) {
                var devices = JSON.parse(xhr.responseText)
                availableDevicesModel.clear()
                for (var i = 0; i < devices.length; i++) {
                    availableDevicesModel.append(devices[i])
                }
            }
        } catch (e) {
            console.log("Could not read available devices")
        }
    }

    function toggleBluetooth() {
        if (btEnabled) {
            console.warn("BT_CMD:disable")
            btEnabled = false
            isScanning = false
        } else {
            console.warn("BT_CMD:enable")
            btEnabled = true
        }
    }

    function startScan() {
        console.warn("BT_CMD:scan-start")
        isScanning = true
        scanTimer.restart()
    }

    function connectDevice(mac) {
        console.warn("BT_CMD:connect:" + mac)
    }

    function disconnectDevice(mac) {
        console.warn("BT_CMD:disconnect:" + mac)
    }

    function pairDevice(mac) {
        console.warn("BT_CMD:pair:" + mac)
    }

    function removeDevice(mac) {
        console.warn("BT_CMD:remove:" + mac)
    }

    function getIconEmoji(icon) {
        switch (icon) {
            case "headphones": return "🎧"
            case "speaker": return "🔊"
            case "keyboard": return "⌨"
            case "mouse": return "🖱"
            case "phone": return "📱"
            case "watch": return "⌚"
            case "car": return "🚗"
            case "tv": return "📺"
            case "laptop": return "💻"
            default: return "🔷"
        }
    }

    background: Rectangle {
        color: "#0a0a0f"
    }

    // Hero section with large toggle
    Rectangle {
        id: heroSection
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 280
        color: "transparent"

        // Ambient glow when enabled
        Rectangle {
            anchors.centerIn: parent
            width: 350
            height: 250
            radius: 175
            color: btEnabled ? "#2a2a5c" : "#1a1a28"
            opacity: btEnabled ? 0.3 : 0.1

            Behavior on color { ColorAnimation { duration: 300 } }
            Behavior on opacity { NumberAnimation { duration: 300 } }
        }

        Column {
            anchors.centerIn: parent
            spacing: 24

            // Large Bluetooth icon as toggle
            Rectangle {
                id: btToggle
                anchors.horizontalCenter: parent.horizontalCenter
                width: 120
                height: 120
                radius: 60
                color: btEnabled ? "#2a2a5c" : "#1a1a28"
                border.color: btEnabled ? "#6a6abf" : "#2a2a3e"
                border.width: 3

                Behavior on color { ColorAnimation { duration: 200 } }
                Behavior on border.color { ColorAnimation { duration: 200 } }

                Text {
                    anchors.centerIn: parent
                    text: "🔷"
                    font.pixelSize: 22
                    opacity: btEnabled ? 1 : 0.4

                    Behavior on opacity { NumberAnimation { duration: 200 } }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: toggleBluetooth()
                }

                // Pulse animation when enabled
                Rectangle {
                    anchors.fill: parent
                    radius: 60
                    color: "transparent"
                    border.color: "#6a6abf"
                    border.width: 2
                    opacity: 0
                    scale: 1

                    SequentialAnimation on opacity {
                        running: btEnabled
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.5; duration: 1000 }
                        NumberAnimation { to: 0; duration: 1000 }
                    }

                    SequentialAnimation on scale {
                        running: btEnabled
                        loops: Animation.Infinite
                        NumberAnimation { to: 1.3; duration: 2000 }
                        NumberAnimation { to: 1; duration: 0 }
                    }
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Bluetooth"
                font.pixelSize: 20
                font.weight: Font.ExtraLight
                font.letterSpacing: 6
                color: "#ffffff"
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: btEnabled ? "TAP TO DISABLE" : "TAP TO ENABLE"
                font.pixelSize: 12
                font.letterSpacing: 2
                color: "#555566"
            }
        }
    }

    // Devices list
    Flickable {
        id: deviceList
        anchors.top: heroSection.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 16
        anchors.bottomMargin: 100
        contentHeight: devicesColumn.height
        clip: true
        visible: btEnabled

        Column {
            id: devicesColumn
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 12

            // Paired devices section
            Text {
                text: "PAIRED DEVICES"
                font.pixelSize: 12
                font.letterSpacing: 2
                color: "#555566"
                leftPadding: 8
                visible: pairedDevicesModel.count > 0
            }

            // Paired devices
            Repeater {
                model: pairedDevicesModel

                Rectangle {
                    width: devicesColumn.width
                    height: model.connected ? 120 : 90
                    radius: model.connected ? 24 : 20
                    color: model.connected ? "transparent" : (pairedMouse.pressed ? "#1e1e2e" : "#14141e")
                    border.color: model.connected ? "#4ade80" : "#1a1a2e"
                    border.width: model.connected ? 2 : 1

                    gradient: model.connected ? connectedGradient : null

                    Gradient {
                        id: connectedGradient
                        GradientStop { position: 0.0; color: "#1a4a3a" }
                        GradientStop { position: 1.0; color: "#0d251d" }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 20
                        spacing: 16

                        Rectangle {
                            Layout.preferredWidth: model.connected ? 64 : 52
                            Layout.preferredHeight: model.connected ? 64 : 52
                            radius: model.connected ? 16 : 14
                            color: model.connected ? "#1a5a4a" : "#1a1a28"

                            Text {
                                anchors.centerIn: parent
                                text: getIconEmoji(model.icon)
                                font.pixelSize: model.connected ? 32 : 26
                            }
                        }

                        Column {
                            Layout.fillWidth: true
                            spacing: model.connected ? 6 : 4

                            Text {
                                text: model.name
                                font.pixelSize: model.connected ? 22 : 20
                                font.weight: model.connected ? Font.Medium : Font.Normal
                                color: "#ffffff"
                            }

                            Row {
                                spacing: 8

                                Rectangle {
                                    width: 8
                                    height: 8
                                    radius: 4
                                    color: model.connected ? "#4ade80" : "#444455"
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                Text {
                                    text: {
                                        var status = model.connected ? "Connected" : "Not Connected"
                                        if (model.battery !== undefined && model.battery > 0) {
                                            status += "  •  " + model.battery + "%"
                                        }
                                        return status
                                    }
                                    font.pixelSize: model.connected ? 14 : 13
                                    color: model.connected ? "#4ade80" : "#666677"
                                }
                            }
                        }

                        // Action button
                        Rectangle {
                            Layout.preferredWidth: 36
                            Layout.preferredHeight: 36
                            radius: 18
                            color: actionMouse.pressed ? (model.connected ? "#5a2a2a" : "#2a4a3a") : (model.connected ? "#3a1a1a" : "#1a3a2a")
                            visible: true

                            Text {
                                anchors.centerIn: parent
                                text: model.connected ? "✕" : "→"
                                font.pixelSize: 18
                                color: model.connected ? "#ff6666" : "#4ade80"
                            }

                            MouseArea {
                                id: actionMouse
                                anchors.fill: parent
                                onClicked: {
                                    if (model.connected) {
                                        disconnectDevice(model.mac)
                                    } else {
                                        connectDevice(model.mac)
                                    }
                                }
                            }
                        }
                    }

                    MouseArea {
                        id: pairedMouse
                        anchors.fill: parent
                        z: -1
                        onPressAndHold: {
                            // Long press to remove
                            removeDevice(model.mac)
                        }
                    }
                }
            }

            // Empty paired state
            Rectangle {
                width: devicesColumn.width
                height: 54
                radius: 20
                color: "#14141e"
                visible: pairedDevicesModel.count === 0

                Column {
                    anchors.centerIn: parent
                    spacing: 4

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "No paired devices"
                        font.pixelSize: 16
                        color: "#555566"
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Scan to find devices"
                        font.pixelSize: 13
                        color: "#444455"
                    }
                }
            }

            Item { height: 16 }

            // Available devices section
            Row {
                width: parent.width
                spacing: 12

                Text {
                    text: "AVAILABLE DEVICES"
                    font.pixelSize: 12
                    font.letterSpacing: 2
                    color: "#555566"
                    leftPadding: 8
                }

                // Scanning indicator
                Text {
                    text: isScanning ? "Scanning..." : ""
                    font.pixelSize: 12
                    color: "#6a6abf"
                    visible: isScanning

                    SequentialAnimation on opacity {
                        running: isScanning
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.3; duration: 500 }
                        NumberAnimation { to: 1; duration: 500 }
                    }
                }

                Item { width: 1; height: 1; Layout.fillWidth: true }

                // Scan button
                Rectangle {
                    width: 32
                    height: 32
                    radius: 16
                    color: scanMouse.pressed ? "#2a2a4e" : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "↻"
                        font.pixelSize: 20
                        color: "#6a6abf"
                        rotation: isScanning ? 360 : 0

                        Behavior on rotation {
                            RotationAnimation {
                                duration: 1000
                                loops: isScanning ? Animation.Infinite : 1
                            }
                        }
                    }

                    MouseArea {
                        id: scanMouse
                        anchors.fill: parent
                        onClicked: startScan()
                    }
                }
            }

            // Scanning animation
            Rectangle {
                width: devicesColumn.width
                height: 54
                radius: 20
                color: "#14141e"
                border.color: "#1a1a2e"
                border.width: 1
                visible: isScanning && availableDevicesModel.count === 0

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 16

                    // Animated scanning indicator
                    Item {
                        Layout.preferredWidth: 40
                        Layout.preferredHeight: 40

                        Repeater {
                            model: 3
                            Rectangle {
                                anchors.centerIn: parent
                                width: 12 + index * 10
                                height: width
                                radius: width / 2
                                color: "transparent"
                                border.color: Theme.accentColor
                                border.width: 2
                                opacity: 0

                                SequentialAnimation on opacity {
                                    running: isScanning
                                    loops: Animation.Infinite
                                    PauseAnimation { duration: index * 300 }
                                    NumberAnimation { to: 0.6; duration: 300 }
                                    NumberAnimation { to: 0; duration: 700 }
                                    PauseAnimation { duration: (2 - index) * 300 }
                                }

                                SequentialAnimation on scale {
                                    running: isScanning
                                    loops: Animation.Infinite
                                    PauseAnimation { duration: index * 300 }
                                    NumberAnimation { from: 0.8; to: 1.5; duration: 1000 }
                                    PauseAnimation { duration: (2 - index) * 300 }
                                }
                            }
                        }

                        Rectangle {
                            anchors.centerIn: parent
                            width: 8
                            height: 8
                            radius: 4
                            color: Theme.accentColor
                        }
                    }

                    Text {
                        text: "Scanning for devices..."
                        font.pixelSize: 18
                        color: "#888899"
                        Layout.fillWidth: true
                    }
                }
            }

            // Available devices list
            Repeater {
                model: availableDevicesModel

                Rectangle {
                    width: devicesColumn.width
                    height: 54
                    radius: 20
                    color: availMouse.pressed ? "#1e1e2e" : "#14141e"
                    border.color: "#1a1a2e"
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 20
                        spacing: 16

                        Rectangle {
                            Layout.preferredWidth: 48
                            Layout.preferredHeight: 48
                            radius: 12
                            color: "#1a1a28"

                            Text {
                                anchors.centerIn: parent
                                text: getIconEmoji(model.icon)
                                font.pixelSize: 24
                            }
                        }

                        Column {
                            Layout.fillWidth: true
                            spacing: 4

                            Text {
                                text: model.name
                                font.pixelSize: 18
                                color: "#ffffff"
                            }

                            Text {
                                text: "Tap to pair"
                                font.pixelSize: 12
                                color: "#666677"
                            }
                        }

                        Text {
                            text: "+"
                            font.pixelSize: 24
                            color: "#6a6abf"
                        }
                    }

                    MouseArea {
                        id: availMouse
                        anchors.fill: parent
                        onClicked: pairDevice(model.mac)
                    }
                }
            }

            // No devices found
            Rectangle {
                width: devicesColumn.width
                height: 40
                radius: 16
                color: "#14141e"
                visible: !isScanning && availableDevicesModel.count === 0

                Text {
                    anchors.centerIn: parent
                    text: "Tap ↻ to scan for devices"
                    font.pixelSize: 14
                    color: "#555566"
                }
            }

            Item { height: 20 }
        }
    }

    // Disabled state
    Rectangle {
        anchors.top: heroSection.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 100
        color: "transparent"
        visible: !btEnabled

        Column {
            anchors.centerIn: parent
            spacing: 16

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "📵"
                font.pixelSize: 20
                opacity: 0.3
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Bluetooth is disabled"
                font.pixelSize: 20
                color: "#444455"
            }
        }
    }

    // Back button - prominent floating action button
    Rectangle {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 24
        anchors.bottomMargin: 120
        width: 48
        height: 48
        radius: 36
        color: backMouse.pressed ? Qt.darker(Theme.accentColor, 1.2) : Theme.accentColor

        Behavior on color { ColorAnimation { duration: 150 } }

        Text {
            anchors.centerIn: parent
            text: "←"
            font.pixelSize: 22
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
