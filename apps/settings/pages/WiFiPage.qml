import "../../shared"
import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Page {
    id: wifiPage

    property bool wifiEnabled: true
    property bool isConnected: false
    property string connectedSsid: ""
    property string connectedIp: ""
    property int connectedSignal: 0
    property bool isScanning: false
    property bool showPasswordDialog: false
    property string connectingSsid: ""

    // Network list model
    ListModel {
        id: networkModel
    }

    Component.onCompleted: {
        loadWifiStatus()
        loadNetworks()
    }

    // Periodic refresh timer
    Timer {
        interval: 5000
        running: wifiEnabled && !showPasswordDialog
        repeat: true
        onTriggered: {
            loadWifiStatus()
            loadNetworks()
        }
    }

    function loadWifiStatus() {
        // Read WiFi radio status
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file:///tmp/flick-wifi-status.json", false)
        try {
            xhr.send()
            if (xhr.status === 200) {
                var status = JSON.parse(xhr.responseText)
                wifiEnabled = status.enabled
            }
        } catch (e) {
            console.log("Could not read WiFi status")
        }

        // Read connection info
        var xhr2 = new XMLHttpRequest()
        xhr2.open("GET", "file:///tmp/flick-wifi-connected.json", false)
        try {
            xhr2.send()
            if (xhr2.status === 200) {
                var conn = JSON.parse(xhr2.responseText)
                isConnected = conn.connected
                if (conn.connected) {
                    connectedSsid = conn.ssid || ""
                    connectedIp = conn.ip || ""
                    connectedSignal = conn.signal || 0
                }
            }
        } catch (e) {
            isConnected = false
        }
    }

    function loadNetworks() {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file:///tmp/flick-wifi-networks.json", false)
        try {
            xhr.send()
            if (xhr.status === 200) {
                var networks = JSON.parse(xhr.responseText)
                networkModel.clear()
                for (var i = 0; i < networks.length; i++) {
                    var net = networks[i]
                    // Skip the connected network
                    if (net.ssid !== connectedSsid) {
                        networkModel.append({
                            name: net.ssid,
                            signal: Math.ceil(net.signal / 25), // Convert 0-100 to 0-4
                            signalPercent: net.signal,
                            secured: net.secured
                        })
                    }
                }
                isScanning = false
            }
        } catch (e) {
            console.log("Could not read networks")
            isScanning = false
        }
    }

    function toggleWifi() {
        if (wifiEnabled) {
            console.warn("WIFI_CMD:disable")
            wifiEnabled = false
            isConnected = false
        } else {
            console.warn("WIFI_CMD:enable")
            wifiEnabled = true
            isScanning = true
        }
    }

    function refreshNetworks() {
        console.warn("WIFI_CMD:scan")
        isScanning = true
    }

    function connectToNetwork(ssid, password) {
        if (password && password.length > 0) {
            console.warn("WIFI_CMD:connect:" + ssid + ":" + password)
        } else {
            console.warn("WIFI_CMD:connect:" + ssid)
        }
        showPasswordDialog = false
        connectingSsid = ""
        isScanning = true // Show scanning while connecting
    }

    function disconnect() {
        console.warn("WIFI_CMD:disconnect")
        isConnected = false
    }

    function signalStrengthText(signal) {
        if (signal >= 75) return "Excellent signal"
        if (signal >= 50) return "Good signal"
        if (signal >= 25) return "Fair signal"
        return "Weak signal"
    }

    background: Rectangle {
        color: "#0a0a0f"
    }

    // Password dialog overlay
    Rectangle {
        id: passwordOverlay
        anchors.fill: parent
        color: "#000000"
        opacity: showPasswordDialog ? 0.8 : 0
        visible: opacity > 0
        z: 100

        Behavior on opacity { NumberAnimation { duration: 200 } }

        MouseArea {
            anchors.fill: parent
            onClicked: showPasswordDialog = false
        }
    }

    Rectangle {
        id: passwordDialog
        anchors.centerIn: parent
        width: parent.width - 48
        height: 280
        radius: 28
        color: "#1a1a2a"
        border.color: "#4a8abf"
        border.width: 2
        visible: showPasswordDialog
        z: 101

        Column {
            anchors.fill: parent
            anchors.margins: 24
            spacing: 20

            Text {
                text: "Connect to Network"
                font.pixelSize: 24
                font.weight: Font.Medium
                color: "#ffffff"
            }

            Text {
                text: connectingSsid
                font.pixelSize: 18
                color: "#4a8abf"
            }

            Rectangle {
                width: parent.width
                height: 56
                radius: 16
                color: "#0a0a0f"
                border.color: passwordInput.activeFocus ? "#4a8abf" : "#2a2a3e"
                border.width: 2

                TextInput {
                    id: passwordInput
                    anchors.fill: parent
                    anchors.margins: 16
                    font.pixelSize: 18
                    color: "#ffffff"
                    echoMode: TextInput.Password
                    clip: true

                    Text {
                        anchors.fill: parent
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Enter password"
                        font.pixelSize: 18
                        color: "#555566"
                        visible: !passwordInput.text && !passwordInput.activeFocus
                    }
                }
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 16

                Rectangle {
                    width: 120
                    height: 48
                    radius: 24
                    color: cancelMouse.pressed ? "#2a2a3e" : "#1a1a28"
                    border.color: "#3a3a4e"
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "Cancel"
                        font.pixelSize: 16
                        color: "#888899"
                    }

                    MouseArea {
                        id: cancelMouse
                        anchors.fill: parent
                        onClicked: {
                            showPasswordDialog = false
                            passwordInput.text = ""
                        }
                    }
                }

                Rectangle {
                    width: 120
                    height: 48
                    radius: 24
                    color: connectMouse.pressed ? "#3a6a9f" : "#4a8abf"

                    Text {
                        anchors.centerIn: parent
                        text: "Connect"
                        font.pixelSize: 16
                        font.weight: Font.Medium
                        color: "#ffffff"
                    }

                    MouseArea {
                        id: connectMouse
                        anchors.fill: parent
                        onClicked: {
                            connectToNetwork(connectingSsid, passwordInput.text)
                            passwordInput.text = ""
                        }
                    }
                }
            }
        }
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
            color: wifiEnabled ? "#1a3a5c" : "#1a1a28"
            opacity: wifiEnabled ? 0.3 : 0.1

            Behavior on color { ColorAnimation { duration: 300 } }
            Behavior on opacity { NumberAnimation { duration: 300 } }
        }

        Column {
            anchors.centerIn: parent
            spacing: 24

            // Large WiFi icon as toggle
            Rectangle {
                id: wifiToggle
                anchors.horizontalCenter: parent.horizontalCenter
                width: 120
                height: 120
                radius: 60
                color: wifiEnabled ? "#1a3a5c" : "#1a1a28"
                border.color: wifiEnabled ? "#4a8abf" : "#2a2a3e"
                border.width: 3

                Behavior on color { ColorAnimation { duration: 200 } }
                Behavior on border.color { ColorAnimation { duration: 200 } }

                Text {
                    anchors.centerIn: parent
                    text: "📶"
                    font.pixelSize: 22
                    opacity: wifiEnabled ? 1 : 0.4

                    Behavior on opacity { NumberAnimation { duration: 200 } }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: toggleWifi()
                }

                // Pulse animation when enabled
                Rectangle {
                    anchors.fill: parent
                    radius: 60
                    color: "transparent"
                    border.color: "#4a8abf"
                    border.width: 2
                    opacity: 0
                    scale: 1

                    SequentialAnimation on opacity {
                        running: wifiEnabled
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.5; duration: 1000 }
                        NumberAnimation { to: 0; duration: 1000 }
                    }

                    SequentialAnimation on scale {
                        running: wifiEnabled
                        loops: Animation.Infinite
                        NumberAnimation { to: 1.3; duration: 2000 }
                        NumberAnimation { to: 1; duration: 0 }
                    }
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "WiFi"
                font.pixelSize: 20
                font.weight: Font.ExtraLight
                font.letterSpacing: 6
                color: "#ffffff"
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: wifiEnabled ? "TAP TO DISABLE" : "TAP TO ENABLE"
                font.pixelSize: 12
                font.letterSpacing: 2
                color: "#555566"
            }
        }
    }

    // Connected network - large hero card
    Rectangle {
        id: connectedCard
        anchors.top: heroSection.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 16
        height: 140
        radius: 24
        visible: wifiEnabled && isConnected
        opacity: (wifiEnabled && isConnected) ? 1 : 0

        gradient: Gradient {
            GradientStop { position: 0.0; color: "#1a4a3a" }
            GradientStop { position: 1.0; color: "#0d251d" }
        }

        Behavior on opacity { NumberAnimation { duration: 300 } }

        // Border glow
        Rectangle {
            anchors.fill: parent
            radius: 24
            color: "transparent"
            border.color: "#4ade80"
            border.width: 2
            opacity: 0.5
        }

        RowLayout {
            anchors.fill: parent
            anchors.margins: 24
            spacing: 20

            Column {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "CONNECTED"
                    font.pixelSize: 12
                    font.letterSpacing: 2
                    color: "#4ade80"
                }

                Text {
                    text: connectedSsid
                    font.pixelSize: 20
                    font.weight: Font.Medium
                    color: "#ffffff"
                }

                Text {
                    text: signalStrengthText(connectedSignal) + (connectedIp ? "  •  " + connectedIp : "")
                    font.pixelSize: 14
                    color: "#88aa99"
                }
            }

            // Signal strength indicator
            Row {
                spacing: 4

                Repeater {
                    model: 4
                    Rectangle {
                        width: 8
                        height: 12 + index * 10
                        radius: 4
                        color: index < Math.ceil(connectedSignal / 25) ? "#4ade80" : "#2a3a2e"
                        anchors.bottom: parent.bottom
                    }
                }
            }
        }

        // Disconnect button
        Rectangle {
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 12
            width: 36
            height: 36
            radius: 18
            color: disconnectMouse.pressed ? "#5a2a2a" : "#3a1a1a"

            Text {
                anchors.centerIn: parent
                text: "✕"
                font.pixelSize: 18
                color: "#ff6666"
            }

            MouseArea {
                id: disconnectMouse
                anchors.fill: parent
                onClicked: disconnect()
            }
        }
    }

    // Available networks
    Flickable {
        id: networkList
        anchors.top: (wifiEnabled && isConnected) ? connectedCard.bottom : heroSection.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 16
        anchors.topMargin: 24
        anchors.bottomMargin: 100
        contentHeight: networksColumn.height
        clip: true
        visible: wifiEnabled

        Column {
            id: networksColumn
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 12

            Row {
                width: parent.width
                spacing: 12

                Text {
                    text: "AVAILABLE NETWORKS"
                    font.pixelSize: 12
                    font.letterSpacing: 2
                    color: "#555566"
                    leftPadding: 8
                }

                // Scanning indicator
                Text {
                    text: isScanning ? "Scanning..." : ""
                    font.pixelSize: 12
                    color: "#4a8abf"
                    visible: isScanning

                    SequentialAnimation on opacity {
                        running: isScanning
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.3; duration: 500 }
                        NumberAnimation { to: 1; duration: 500 }
                    }
                }

                Item { width: 1; height: 1; Layout.fillWidth: true }

                // Refresh button
                Rectangle {
                    width: 32
                    height: 32
                    radius: 16
                    color: refreshMouse.pressed ? "#2a2a3e" : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "↻"
                        font.pixelSize: 20
                        color: "#4a8abf"
                        rotation: isScanning ? 360 : 0

                        Behavior on rotation {
                            RotationAnimation {
                                duration: 1000
                                loops: isScanning ? Animation.Infinite : 1
                            }
                        }
                    }

                    MouseArea {
                        id: refreshMouse
                        anchors.fill: parent
                        onClicked: refreshNetworks()
                    }
                }
            }

            // Empty state
            Rectangle {
                width: parent.width
                height: 100
                radius: 20
                color: "#14141e"
                visible: networkModel.count === 0 && !isScanning

                Column {
                    anchors.centerIn: parent
                    spacing: 8

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "📡"
                        font.pixelSize: 22
                        opacity: 0.5
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "No networks found"
                        font.pixelSize: 16
                        color: "#555566"
                    }
                }
            }

            Repeater {
                model: networkModel

                Rectangle {
                    width: networksColumn.width
                    height: 40
                    radius: 20
                    color: networkMouse.pressed ? "#1e1e2e" : "#14141e"
                    border.color: "#1a1a2e"
                    border.width: 1

                    Behavior on color { ColorAnimation { duration: 100 } }

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 20
                        spacing: 16

                        // Signal indicator
                        Column {
                            Layout.preferredWidth: 40
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 2

                            Row {
                                anchors.horizontalCenter: parent.horizontalCenter
                                spacing: 3

                                Repeater {
                                    model: 4
                                    Rectangle {
                                        width: 6
                                        height: 6 + index * 6
                                        radius: 3
                                        color: index < signal ? Theme.accentColor : "#2a2a3e"
                                        anchors.bottom: parent.bottom
                                    }
                                }
                            }
                        }

                        Column {
                            Layout.fillWidth: true
                            spacing: 6

                            Text {
                                text: name
                                font.pixelSize: 20
                                color: "#ffffff"
                            }

                            Text {
                                text: secured ? "WPA2 Secured" : "Open Network"
                                font.pixelSize: 13
                                color: secured ? "#666677" : "#cc8844"
                            }
                        }

                        Text {
                            text: secured ? "🔒" : "⚠"
                            font.pixelSize: 20
                            opacity: 0.7
                        }
                    }

                    MouseArea {
                        id: networkMouse
                        anchors.fill: parent
                        onClicked: {
                            if (secured) {
                                connectingSsid = name
                                showPasswordDialog = true
                            } else {
                                connectToNetwork(name, "")
                            }
                        }
                    }
                }
            }
        }
    }

    // Disabled state overlay
    Rectangle {
        anchors.top: heroSection.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 100
        color: "transparent"
        visible: !wifiEnabled

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
                text: "WiFi is disabled"
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
