import "../../shared"
import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Page {
    id: effectsPage

    // Config properties matching Rust effects app
    property bool fireTouchEnabled: true
    property bool livingPixelsEnabled: false
    property bool lpStars: true
    property bool lpShootingStars: true
    property bool lpFireflies: true

    property string configPath: Theme.stateDir + "/effects_config.json"

    Component.onCompleted: {
        loadConfig()
    }

    function loadConfig() {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file://" + configPath, false)
        try {
            xhr.send()
            if (xhr.status === 200) {
                var config = JSON.parse(xhr.responseText)
                if (config.fire_touch_enabled !== undefined) fireTouchEnabled = config.fire_touch_enabled
                if (config.living_pixels_enabled !== undefined) livingPixelsEnabled = config.living_pixels_enabled
                if (config.lp_stars !== undefined) lpStars = config.lp_stars
                if (config.lp_shooting_stars !== undefined) lpShootingStars = config.lp_shooting_stars
                if (config.lp_fireflies !== undefined) lpFireflies = config.lp_fireflies
            }
        } catch (e) {
            console.log("Using default effects config")
        }
    }

    function saveConfig() {
        var config = {
            fire_touch_enabled: fireTouchEnabled,
            living_pixels_enabled: livingPixelsEnabled,
            lp_stars: lpStars,
            lp_shooting_stars: lpShootingStars,
            lp_fireflies: lpFireflies
        }

        // Output to console for shell script to capture and save
        console.log("SAVE_EFFECTS:" + JSON.stringify(config))
    }

    background: Rectangle {
        color: "#0a0a0f"
    }

    // Hero section
    Rectangle {
        id: heroSection
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 200
        color: "transparent"

        // Fire preview
        Rectangle {
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: -40
            width: 100
            height: 100
            radius: 50
            color: "#ff6600"
            opacity: fireTouchEnabled ? 0.3 : 0.1

            SequentialAnimation on opacity {
                loops: Animation.Infinite
                running: fireTouchEnabled
                NumberAnimation { to: 0.5; duration: 300; easing.type: Easing.InOutSine }
                NumberAnimation { to: 0.2; duration: 300; easing.type: Easing.InOutSine }
            }
        }

        // Stars preview
        Repeater {
            model: livingPixelsEnabled ? 15 : 0
            Rectangle {
                x: Math.random() * heroSection.width
                y: Math.random() * heroSection.height * 0.7
                width: 2 + Math.random() * 2
                height: width
                radius: width / 2
                color: "#ffffff"
                opacity: 0.3 + Math.random() * 0.5

                SequentialAnimation on opacity {
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.1; duration: 1000 + Math.random() * 2000 }
                    NumberAnimation { to: 0.8; duration: 1000 + Math.random() * 2000 }
                }
            }
        }

        Column {
            anchors.centerIn: parent
            spacing: 8

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Effects"
                font.pixelSize: 38
                font.weight: Font.ExtraLight
                font.letterSpacing: 4
                color: "#ffffff"
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "VISUAL ENHANCEMENTS"
                font.pixelSize: 11
                font.letterSpacing: 3
                color: "#555566"
            }
        }
    }

    // Settings
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
            spacing: 16

            // ===== TOUCH EFFECTS =====
            Text {
                text: "TOUCH EFFECTS"
                font.pixelSize: 11
                font.letterSpacing: 2
                color: "#555566"
                leftPadding: 8
            }

            // Fire touch toggle
            EffectToggle {
                width: settingsColumn.width
                title: "Fire on Touch"
                subtitle: "Flame particles follow your finger"
                icon: "🔥"
                checked: fireTouchEnabled
                accentColor: "#ff6600"
                onToggled: {
                    fireTouchEnabled = !fireTouchEnabled
                    saveConfig()
                }
            }

            Item { height: 16 }

            // ===== AMBIENT EFFECTS =====
            Text {
                text: "AMBIENT EFFECTS"
                font.pixelSize: 11
                font.letterSpacing: 2
                color: "#555566"
                leftPadding: 8
            }

            // Living pixels master toggle
            EffectToggle {
                width: settingsColumn.width
                title: "Living Pixels"
                subtitle: "Stars, shooting stars, fireflies on screen"
                icon: "✨"
                checked: livingPixelsEnabled
                accentColor: "#ffaa00"
                onToggled: {
                    livingPixelsEnabled = !livingPixelsEnabled
                    saveConfig()
                }
            }

            // Sub-toggles card
            Rectangle {
                width: settingsColumn.width
                height: lpSubColumn.height + 24
                radius: 20
                color: "#14141e"
                border.color: livingPixelsEnabled ? "#ffaa00" : "#1a1a2e"
                border.width: 1
                visible: livingPixelsEnabled
                opacity: livingPixelsEnabled ? 1.0 : 0.5

                Column {
                    id: lpSubColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 12
                    spacing: 8

                    Text {
                        text: "Effect Types"
                        font.pixelSize: 13
                        color: "#888899"
                        leftPadding: 4
                    }

                    Grid {
                        width: parent.width
                        columns: 2
                        spacing: 8

                        SubToggle {
                            width: (lpSubColumn.width - 8) / 2
                            icon: "⭐"
                            label: "Stars"
                            checked: lpStars
                            onToggled: { lpStars = !lpStars; saveConfig() }
                        }

                        SubToggle {
                            width: (lpSubColumn.width - 8) / 2
                            icon: "💫"
                            label: "Shooting Stars"
                            checked: lpShootingStars
                            onToggled: { lpShootingStars = !lpShootingStars; saveConfig() }
                        }

                        SubToggle {
                            width: (lpSubColumn.width - 8) / 2
                            icon: "🌟"
                            label: "Fireflies"
                            checked: lpFireflies
                            onToggled: { lpFireflies = !lpFireflies; saveConfig() }
                        }
                    }
                }
            }

            Item { height: 16 }

            // Info text
            Rectangle {
                width: settingsColumn.width
                height: infoCol.height + 24
                radius: 16
                color: "#14141e"
                border.color: "#1a1a2e"

                Column {
                    id: infoCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 12
                    spacing: 8

                    Row {
                        spacing: 8
                        Text { text: "ℹ️"; font.pixelSize: 16 }
                        Text { text: "Note"; font.pixelSize: 14; color: "#888899"; font.weight: Font.Medium }
                    }

                    Text {
                        width: parent.width
                        text: "Changes apply after restarting flick-effects service. Living pixels may impact battery life."
                        font.pixelSize: 12
                        color: "#666677"
                        wrapMode: Text.WordWrap
                    }
                }
            }

            Item { height: 40 }
        }
    }

    // Back button
    Rectangle {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 24
        anchors.bottomMargin: 120
        width: 44
        height: 44
        radius: 32
        color: backMouse.pressed ? Qt.darker(Theme.accentColor, 1.2) : Theme.accentColor

        Text {
            anchors.centerIn: parent
            text: "←"
            font.pixelSize: 20
            color: "#ffffff"
        }

        MouseArea {
            id: backMouse
            anchors.fill: parent
            onClicked: stackView.pop()
        }
    }

    // Toggle component
    component EffectToggle: Rectangle {
        property string title
        property string subtitle
        property string icon
        property bool checked
        property color accentColor: Theme.accentColor
        signal toggled()

        height: 88
        radius: 20
        color: toggleMouse.pressed ? "#1e1e2e" : "#14141e"
        border.color: checked ? accentColor : "#1a1a2e"
        border.width: checked ? 2 : 1

        RowLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 14

            Rectangle {
                Layout.preferredWidth: 48
                Layout.preferredHeight: 48
                radius: 12
                color: checked ? Qt.darker(accentColor, 2) : "#1a1a28"

                Text {
                    anchors.centerIn: parent
                    text: icon
                    font.pixelSize: 24
                }
            }

            Column {
                Layout.fillWidth: true
                spacing: 4

                Text {
                    text: title
                    font.pixelSize: 17
                    color: "#ffffff"
                }

                Text {
                    text: subtitle
                    font.pixelSize: 12
                    color: "#666677"
                }
            }

            Rectangle {
                Layout.preferredWidth: 56
                Layout.preferredHeight: 32
                radius: 16
                color: checked ? accentColor : "#2a2a3e"

                Behavior on color { ColorAnimation { duration: 200 } }

                Rectangle {
                    x: checked ? parent.width - width - 3 : 3
                    anchors.verticalCenter: parent.verticalCenter
                    width: 26
                    height: 26
                    radius: 13
                    color: "#ffffff"

                    Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                }
            }
        }

        MouseArea {
            id: toggleMouse
            anchors.fill: parent
            onClicked: toggled()
        }
    }

    // Sub-toggle component
    component SubToggle: Rectangle {
        property string icon
        property string label
        property bool checked
        signal toggled()

        height: 48
        radius: 12
        color: subMouse.pressed ? "#2a2a3e" : (checked ? "#2a2a38" : "#1a1a28")
        border.color: checked ? "#ffaa00" : "#2a2a3e"
        border.width: checked ? 1 : 0

        Row {
            anchors.centerIn: parent
            spacing: 8

            Text {
                text: icon
                font.pixelSize: 18
                opacity: checked ? 1.0 : 0.5
            }

            Text {
                text: label
                font.pixelSize: 13
                color: checked ? "#ffffff" : "#666677"
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 16
                height: 16
                radius: 8
                color: checked ? "#ffaa00" : "transparent"
                visible: checked

                Text {
                    anchors.centerIn: parent
                    text: "✓"
                    font.pixelSize: 10
                    color: "#000000"
                }
            }
        }

        MouseArea {
            id: subMouse
            anchors.fill: parent
            onClicked: toggled()
        }
    }
}
