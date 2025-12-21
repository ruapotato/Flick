import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Page {
    id: displayPage

    property real brightness: 0.75
    property bool autoBrightness: false
    property int selectedTimeout: 1
    property real textScale: 2.0  // Text scale factor (0.5 to 3.0, default 2.0)
    property string scaleConfigPath: "/home/droidian/.local/state/flick/display_config.json"

    Component.onCompleted: loadScaleConfig()

    function loadScaleConfig() {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file://" + scaleConfigPath, false)
        try {
            xhr.send()
            if (xhr.status === 200) {
                var config = JSON.parse(xhr.responseText)
                if (config.text_scale !== undefined) {
                    textScale = config.text_scale
                }
            }
        } catch (e) {
            console.log("Using default text scale: 2.0")
        }
    }

    function saveScaleConfig() {
        // Log the scale value - shell script will capture and save to config
        console.log("Saving text scale: " + textScale.toFixed(2))
    }

    background: Rectangle {
        color: "#0a0a0f"
    }

    // Hero section with brightness control
    Rectangle {
        id: heroSection
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 320
        color: "transparent"

        // Dynamic ambient glow based on brightness
        Rectangle {
            anchors.centerIn: parent
            width: 400
            height: 300
            radius: 200
            color: "#4a3a1a"
            opacity: brightness * 0.3

            Behavior on opacity { NumberAnimation { duration: 100 } }
        }

        Column {
            anchors.centerIn: parent
            spacing: 20

            // Large sun icon with glow
            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 140
                height: 140

                // Sun rays
                Repeater {
                    model: 8
                    Rectangle {
                        anchors.centerIn: parent
                        width: 4
                        height: 60
                        radius: 2
                        color: "#ffaa44"
                        opacity: brightness * 0.6
                        rotation: index * 45
                        transformOrigin: Item.Center

                        Behavior on opacity { NumberAnimation { duration: 100 } }
                    }
                }

                // Sun body
                Rectangle {
                    anchors.centerIn: parent
                    width: 80
                    height: 80
                    radius: 40
                    color: Qt.lighter("#ffaa44", 1 + brightness * 0.5)

                    Behavior on color { ColorAnimation { duration: 100 } }
                }

                Text {
                    anchors.centerIn: parent
                    text: Math.round(brightness * 100)
                    font.pixelSize: 28
                    font.weight: Font.Bold
                    color: "#0a0a0f"
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Display"
                font.pixelSize: 42
                font.weight: Font.ExtraLight
                font.letterSpacing: 6
                color: "#ffffff"
            }

            // Large slider
            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 300
                height: 60

                // Track background
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width
                    height: 12
                    radius: 6
                    color: "#1a1a28"

                    // Filled portion
                    Rectangle {
                        width: parent.width * brightness
                        height: parent.height
                        radius: 6
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: "#cc6600" }
                            GradientStop { position: 1.0; color: "#ffcc00" }
                        }

                        Behavior on width { NumberAnimation { duration: 50 } }
                    }
                }

                // Handle
                Rectangle {
                    x: (parent.width - 44) * brightness
                    anchors.verticalCenter: parent.verticalCenter
                    width: 44
                    height: 44
                    radius: 22
                    color: "#ffffff"
                    border.color: "#ffcc00"
                    border.width: 3

                    Behavior on x { NumberAnimation { duration: 50 } }

                    Text {
                        anchors.centerIn: parent
                        text: brightness > 0.5 ? "☀" : "🌙"
                        font.pixelSize: 20
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onPressed: updateBrightness(mouse)
                    onPositionChanged: if (pressed) updateBrightness(mouse)

                    function updateBrightness(mouse) {
                        brightness = Math.max(0.05, Math.min(1, mouse.x / parent.width))
                    }
                }
            }
        }
    }

    // Settings below hero
    Flickable {
        anchors.top: heroSection.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 16
        anchors.bottomMargin: 100
        contentHeight: settingsColumn.height
        clip: true

        Column {
            id: settingsColumn
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 12

            // Auto brightness toggle
            Rectangle {
                width: settingsColumn.width
                height: 100
                radius: 24
                color: autoMouse.pressed ? "#1e1e2e" : "#14141e"
                border.color: autoBrightness ? "#ffcc00" : "#1a1a2e"
                border.width: autoBrightness ? 2 : 1

                Behavior on border.color { ColorAnimation { duration: 200 } }

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 16

                    Rectangle {
                        Layout.preferredWidth: 56
                        Layout.preferredHeight: 56
                        radius: 14
                        color: autoBrightness ? "#3c3a1a" : "#1a1a28"

                        Behavior on color { ColorAnimation { duration: 200 } }

                        Text {
                            anchors.centerIn: parent
                            text: "✨"
                            font.pixelSize: 28
                        }
                    }

                    Column {
                        Layout.fillWidth: true
                        spacing: 6

                        Text {
                            text: "Auto Brightness"
                            font.pixelSize: 20
                            color: "#ffffff"
                        }

                        Text {
                            text: "Adjust based on ambient light"
                            font.pixelSize: 13
                            color: "#666677"
                        }
                    }

                    // Custom toggle
                    Rectangle {
                        Layout.preferredWidth: 64
                        Layout.preferredHeight: 36
                        radius: 18
                        color: autoBrightness ? "#e94560" : "#2a2a3e"

                        Behavior on color { ColorAnimation { duration: 200 } }

                        Rectangle {
                            x: autoBrightness ? parent.width - width - 4 : 4
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
                    id: autoMouse
                    anchors.fill: parent
                    onClicked: autoBrightness = !autoBrightness
                }
            }

            Item { height: 8 }

            Text {
                text: "SCREEN TIMEOUT"
                font.pixelSize: 12
                font.letterSpacing: 2
                color: "#555566"
                leftPadding: 8
            }

            // Timeout options as large cards
            Repeater {
                model: ListModel {
                    ListElement { label: "15 seconds"; value: 15 }
                    ListElement { label: "30 seconds"; value: 30 }
                    ListElement { label: "1 minute"; value: 60 }
                    ListElement { label: "5 minutes"; value: 300 }
                    ListElement { label: "Never"; value: 0 }
                }

                Rectangle {
                    width: settingsColumn.width
                    height: 70
                    radius: 20
                    color: timeoutMouse.pressed ? "#1e1e2e" : "#14141e"
                    border.color: selectedTimeout === index ? "#e94560" : "#1a1a2e"
                    border.width: selectedTimeout === index ? 2 : 1

                    Behavior on border.color { ColorAnimation { duration: 150 } }

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 20
                        spacing: 16

                        Text {
                            text: model.label
                            font.pixelSize: 20
                            color: "#ffffff"
                            Layout.fillWidth: true
                        }

                        // Radio indicator
                        Rectangle {
                            Layout.preferredWidth: 28
                            Layout.preferredHeight: 28
                            radius: 14
                            color: "transparent"
                            border.color: selectedTimeout === index ? "#e94560" : "#3a3a4e"
                            border.width: 2

                            Rectangle {
                                anchors.centerIn: parent
                                width: selectedTimeout === index ? 14 : 0
                                height: width
                                radius: width / 2
                                color: "#e94560"

                                Behavior on width {
                                    NumberAnimation { duration: 150; easing.type: Easing.OutBack }
                                }
                            }
                        }
                    }

                    MouseArea {
                        id: timeoutMouse
                        anchors.fill: parent
                        onClicked: selectedTimeout = index
                    }
                }
            }

            Item { height: 16 }

            Text {
                text: "TEXT SIZE"
                font.pixelSize: 12
                font.letterSpacing: 2
                color: "#555566"
                leftPadding: 8
            }

            // Text scale card with slider
            Rectangle {
                width: settingsColumn.width
                height: 200
                radius: 24
                color: "#14141e"
                border.color: "#1a1a2e"
                border.width: 1

                Column {
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 16

                    // Preview text
                    Item {
                        width: parent.width
                        height: 60

                        Text {
                            anchors.centerIn: parent
                            text: "Preview Text"
                            font.pixelSize: 14 * textScale
                            color: "#ffffff"

                            Behavior on font.pixelSize { NumberAnimation { duration: 100 } }
                        }
                    }

                    // Scale value display
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: textScale.toFixed(1) + "x"
                        font.pixelSize: 24
                        font.weight: Font.Bold
                        color: "#e94560"
                    }

                    // Slider
                    Item {
                        width: parent.width
                        height: 50

                        // Track labels
                        Row {
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right

                            Text {
                                width: parent.width / 3
                                text: "0.5x"
                                font.pixelSize: 11
                                color: "#555566"
                                horizontalAlignment: Text.AlignLeft
                            }
                            Text {
                                width: parent.width / 3
                                text: "2.0x"
                                font.pixelSize: 11
                                color: "#555566"
                                horizontalAlignment: Text.AlignHCenter
                            }
                            Text {
                                width: parent.width / 3
                                text: "3.0x"
                                font.pixelSize: 11
                                color: "#555566"
                                horizontalAlignment: Text.AlignRight
                            }
                        }

                        // Track background
                        Rectangle {
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 8
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: parent.width
                            height: 10
                            radius: 5
                            color: "#1a1a28"

                            // Filled portion
                            Rectangle {
                                width: parent.width * ((textScale - 0.5) / 2.5)
                                height: parent.height
                                radius: 5
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0.0; color: "#993366" }
                                    GradientStop { position: 1.0; color: "#e94560" }
                                }

                                Behavior on width { NumberAnimation { duration: 50 } }
                            }
                        }

                        // Handle
                        Rectangle {
                            x: (parent.width - 36) * ((textScale - 0.5) / 2.5)
                            anchors.bottom: parent.bottom
                            width: 36
                            height: 36
                            radius: 18
                            color: "#ffffff"
                            border.color: "#e94560"
                            border.width: 3

                            Behavior on x { NumberAnimation { duration: 50 } }

                            Text {
                                anchors.centerIn: parent
                                text: "Aa"
                                font.pixelSize: 14
                                font.weight: Font.Bold
                                color: "#e94560"
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onPressed: updateScale(mouse)
                            onPositionChanged: if (pressed) updateScale(mouse)
                            onReleased: saveScaleConfig()

                            function updateScale(mouse) {
                                var ratio = Math.max(0, Math.min(1, mouse.x / parent.width))
                                textScale = 0.5 + ratio * 2.5  // 0.5 to 3.0 range
                            }
                        }
                    }
                }
            }

            // Description
            Text {
                text: "Adjusts text size in apps. Default is 2.0x."
                font.pixelSize: 13
                color: "#666677"
                leftPadding: 8
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
