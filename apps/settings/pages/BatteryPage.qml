import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Page {
    id: batteryPage

    property int batteryLevel: 75
    property string batteryStatus: "Discharging"
    property bool isCharging: false
    property string batteryHealth: "Good"
    property real batteryVoltage: 4.2
    property real batteryTemp: 25.0
    property bool noBattery: false

    Component.onCompleted: loadBatteryInfo()

    Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: loadBatteryInfo()
    }

    function loadBatteryInfo() {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file:///tmp/flick-battery.json", false)
        try {
            xhr.send()
            if (xhr.status === 200) {
                var data = JSON.parse(xhr.responseText)
                batteryLevel = data.level || 0
                batteryStatus = data.status || "Unknown"
                isCharging = data.charging || false
                batteryHealth = data.health || "Unknown"
                batteryVoltage = data.voltage || 0
                batteryTemp = data.temperature || 0
                noBattery = data.no_battery || false
            }
        } catch (e) {
            console.log("Could not read battery info")
        }
    }

    function getBatteryColor() {
        if (isCharging) return "#4ade80"
        if (batteryLevel <= 15) return "#ef4444"
        if (batteryLevel <= 30) return "#f59e0b"
        return "#4ade80"
    }

    function getBatteryIcon() {
        if (isCharging) return "⚡"
        if (batteryLevel <= 15) return "🪫"
        return "🔋"
    }

    background: Rectangle {
        color: "#0a0a0f"
    }

    // Hero section with battery visualization
    Rectangle {
        id: heroSection
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 320
        color: "transparent"

        // Ambient glow
        Rectangle {
            anchors.centerIn: parent
            width: 350
            height: 280
            radius: 175
            color: getBatteryColor()
            opacity: 0.15

            Behavior on color { ColorAnimation { duration: 500 } }
        }

        Column {
            anchors.centerIn: parent
            spacing: 16

            // Large battery visualization
            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 120
                height: 180

                // Battery body
                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 100
                    height: 160
                    radius: 16
                    color: "#1a1a28"
                    border.color: getBatteryColor()
                    border.width: 3

                    // Battery fill
                    Rectangle {
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.margins: 8
                        height: (parent.height - 16) * (batteryLevel / 100)
                        radius: 10
                        color: getBatteryColor()
                        opacity: 0.8

                        Behavior on height { NumberAnimation { duration: 500 } }
                        Behavior on color { ColorAnimation { duration: 500 } }

                        // Charging animation
                        SequentialAnimation on opacity {
                            running: isCharging
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.4; duration: 800 }
                            NumberAnimation { to: 0.8; duration: 800 }
                        }
                    }

                    // Percentage text
                    Text {
                        anchors.centerIn: parent
                        text: batteryLevel + "%"
                        font.pixelSize: 32
                        font.weight: Font.Bold
                        color: "#ffffff"
                    }
                }

                // Battery cap
                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 160
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 40
                    height: 12
                    radius: 6
                    color: getBatteryColor()
                }

                // Charging bolt overlay
                Text {
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: 20
                    text: isCharging ? "⚡" : ""
                    font.pixelSize: 48
                    opacity: 0.9
                    visible: isCharging

                    SequentialAnimation on scale {
                        running: isCharging
                        loops: Animation.Infinite
                        NumberAnimation { to: 1.2; duration: 500 }
                        NumberAnimation { to: 1.0; duration: 500 }
                    }
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: noBattery ? "AC Power" : (isCharging ? "Charging" : batteryStatus)
                font.pixelSize: 24
                font.weight: Font.Medium
                color: getBatteryColor()
            }
        }
    }

    // Battery details
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
            spacing: 12

            Text {
                text: "BATTERY DETAILS"
                font.pixelSize: 12
                font.letterSpacing: 2
                color: "#555566"
                leftPadding: 8
            }

            // Details card
            Rectangle {
                width: detailsColumn.width
                height: detailsListColumn.height + 32
                radius: 24
                color: "#14141e"
                border.color: "#1a1a2e"
                border.width: 1

                Column {
                    id: detailsListColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 16
                    spacing: 0

                    // Health
                    Item {
                        width: parent.width
                        height: 56

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 8

                            Text {
                                text: "💚"
                                font.pixelSize: 20
                            }

                            Text {
                                text: "Health"
                                font.pixelSize: 17
                                color: "#666677"
                                Layout.fillWidth: true
                                Layout.leftMargin: 12
                            }

                            Text {
                                text: batteryHealth
                                font.pixelSize: 17
                                font.weight: Font.Medium
                                color: batteryHealth === "Good" ? "#4ade80" : "#f59e0b"
                            }
                        }

                        Rectangle {
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left
                            anchors.right: parent.right
                            height: 1
                            color: "#1a1a2e"
                        }
                    }

                    // Voltage
                    Item {
                        width: parent.width
                        height: 56
                        visible: !noBattery

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 8

                            Text {
                                text: "⚡"
                                font.pixelSize: 20
                            }

                            Text {
                                text: "Voltage"
                                font.pixelSize: 17
                                color: "#666677"
                                Layout.fillWidth: true
                                Layout.leftMargin: 12
                            }

                            Text {
                                text: batteryVoltage.toFixed(2) + " V"
                                font.pixelSize: 17
                                font.weight: Font.Medium
                                color: "#ffffff"
                            }
                        }

                        Rectangle {
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left
                            anchors.right: parent.right
                            height: 1
                            color: "#1a1a2e"
                        }
                    }

                    // Temperature
                    Item {
                        width: parent.width
                        height: 56
                        visible: !noBattery && batteryTemp > 0

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 8

                            Text {
                                text: "🌡️"
                                font.pixelSize: 20
                            }

                            Text {
                                text: "Temperature"
                                font.pixelSize: 17
                                color: "#666677"
                                Layout.fillWidth: true
                                Layout.leftMargin: 12
                            }

                            Text {
                                text: batteryTemp.toFixed(1) + "°C"
                                font.pixelSize: 17
                                font.weight: Font.Medium
                                color: batteryTemp > 40 ? "#ef4444" : "#ffffff"
                            }
                        }

                        Rectangle {
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left
                            anchors.right: parent.right
                            height: 1
                            color: "#1a1a2e"
                        }
                    }

                    // Status
                    Item {
                        width: parent.width
                        height: 56

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 8

                            Text {
                                text: "📊"
                                font.pixelSize: 20
                            }

                            Text {
                                text: "Status"
                                font.pixelSize: 17
                                color: "#666677"
                                Layout.fillWidth: true
                                Layout.leftMargin: 12
                            }

                            Text {
                                text: batteryStatus
                                font.pixelSize: 17
                                font.weight: Font.Medium
                                color: "#ffffff"
                            }
                        }
                    }
                }
            }

            Item { height: 16 }

            // Battery saver option
            Text {
                text: "POWER OPTIONS"
                font.pixelSize: 12
                font.letterSpacing: 2
                color: "#555566"
                leftPadding: 8
                visible: !noBattery
            }

            Rectangle {
                width: detailsColumn.width
                height: 90
                radius: 24
                color: "#14141e"
                border.color: "#1a1a2e"
                border.width: 1
                visible: !noBattery

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 16

                    Rectangle {
                        Layout.preferredWidth: 52
                        Layout.preferredHeight: 52
                        radius: 14
                        color: "#1a2a1a"

                        Text {
                            anchors.centerIn: parent
                            text: "🔋"
                            font.pixelSize: 26
                        }
                    }

                    Column {
                        Layout.fillWidth: true
                        spacing: 4

                        Text {
                            text: "Battery Saver"
                            font.pixelSize: 20
                            color: "#ffffff"
                        }

                        Text {
                            text: "Reduces performance to save power"
                            font.pixelSize: 13
                            color: "#666677"
                        }
                    }

                    Text {
                        text: "→"
                        font.pixelSize: 24
                        color: "#444455"
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
        color: backMouse.pressed ? "#c23a50" : "#e94560"

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
