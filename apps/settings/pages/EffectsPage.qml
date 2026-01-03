import "../../shared"
import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Page {
    id: effectsPage

    // Touch effect settings
    property bool touchEffectsEnabled: true
    property int touchEffectStyle: 0     // 0=water, 1=snow, 2=CRT, 3=terminal_ripple
    property real fisheyeSize: 0.16
    property real fisheyeStrength: 0.13
    property real rippleSize: 0.30
    property real rippleStrength: 0.07
    property real rippleDuration: 0.5
    property real asciiDensity: 8.0      // ASCII character density (4-16)
    property bool livingPixels: false    // Stars in black, eyes in white
    // Living pixels sub-toggles
    property bool lpStars: true          // Twinkling stars in dark areas
    property bool lpShootingStars: true  // Occasional shooting stars
    property bool rainEffectEnabled: false // Compiz-style rain ripples

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
                // Touch effects
                if (config.touch_effects_enabled !== undefined) touchEffectsEnabled = config.touch_effects_enabled
                if (config.touch_effect_style !== undefined) touchEffectStyle = config.touch_effect_style
                if (config.fisheye_size !== undefined) fisheyeSize = config.fisheye_size
                if (config.fisheye_strength !== undefined) fisheyeStrength = config.fisheye_strength
                if (config.ripple_size !== undefined) rippleSize = config.ripple_size
                if (config.ripple_strength !== undefined) rippleStrength = config.ripple_strength
                if (config.ripple_duration !== undefined) rippleDuration = config.ripple_duration
                if (config.ascii_density !== undefined) asciiDensity = config.ascii_density
                if (config.living_pixels !== undefined) livingPixels = config.living_pixels
                // Living pixels sub-toggles
                if (config.lp_stars !== undefined) lpStars = config.lp_stars
                if (config.lp_shooting_stars !== undefined) lpShootingStars = config.lp_shooting_stars
                if (config.rain_effect_enabled !== undefined) rainEffectEnabled = config.rain_effect_enabled
            }
        } catch (e) {
            console.log("Using default effects config")
        }
    }

    function saveConfig() {
        var config = {
            // Touch effects
            touch_effects_enabled: touchEffectsEnabled,
            touch_effect_style: touchEffectStyle,
            fisheye_size: fisheyeSize,
            fisheye_strength: fisheyeStrength,
            ripple_size: rippleSize,
            ripple_strength: rippleStrength,
            ripple_duration: rippleDuration,
            ascii_density: asciiDensity,
            living_pixels: livingPixels,
            // Living pixels sub-toggles
            lp_stars: lpStars,
            lp_shooting_stars: lpShootingStars,
            rain_effect_enabled: rainEffectEnabled
        }

        var xhr = new XMLHttpRequest()
        xhr.open("PUT", "file://" + configPath, false)
        try {
            xhr.send(JSON.stringify(config, null, 2))
        } catch (e) {
            console.error("Failed to save effects config:", e)
        }
    }

    background: Rectangle {
        color: "#0a0a0f"
    }

    // Hero section with animated preview
    Rectangle {
        id: heroSection
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 220
        color: "transparent"

        // Animated orbs
        Rectangle {
            id: orb1
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: -50
            width: 180
            height: 180
            radius: 90
            color: Theme.accentColor
            opacity: 0.12

            SequentialAnimation on opacity {
                loops: Animation.Infinite
                NumberAnimation { to: 0.20; duration: 2000; easing.type: Easing.InOutSine }
                NumberAnimation { to: 0.12; duration: 2000; easing.type: Easing.InOutSine }
            }
        }

        Rectangle {
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: 50
            anchors.verticalCenterOffset: -20
            width: 120
            height: 120
            radius: 60
            color: "#4a9eff"
            opacity: 0.10

            SequentialAnimation on opacity {
                loops: Animation.Infinite
                NumberAnimation { to: 0.18; duration: 1500; easing.type: Easing.InOutSine }
                NumberAnimation { to: 0.10; duration: 1500; easing.type: Easing.InOutSine }
            }
        }

        // Stars preview (if enabled)
        Repeater {
            model: starryNightEnabled ? 20 : 0
            Rectangle {
                x: Math.random() * heroSection.width
                y: Math.random() * heroSection.height
                width: 2 + Math.random() * 3
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
                text: "✨"
                font.pixelSize: 56
            }

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
                text: "NEXT-GEN VISUALS"
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
            spacing: 12

            // ===== TOUCH EFFECTS =====
            Text {
                text: "TOUCH EFFECTS"
                font.pixelSize: 11
                font.letterSpacing: 2
                color: "#555566"
                leftPadding: 8
            }

            // Master toggle
            EffectToggle {
                width: settingsColumn.width
                title: "Touch Distortion"
                subtitle: "Fisheye lens & ripple effects"
                icon: ["💧", "❄️", "📺", "📟"][touchEffectStyle] || "💧"
                checked: touchEffectsEnabled
                accentColor: ["#4a9eff", "#88ddff", "#ff6600", "#00ff00"][touchEffectStyle] || "#4a9eff"
                onToggled: {
                    touchEffectsEnabled = !touchEffectsEnabled
                    saveConfig()
                }
            }

            // Effect style selector
            Rectangle {
                width: settingsColumn.width
                height: 120
                radius: 20
                color: "#14141e"
                border.color: "#1a1a2e"
                visible: touchEffectsEnabled

                Column {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 12

                    Text {
                        text: "Effect Style"
                        font.pixelSize: 14
                        color: "#888899"
                    }

                    Grid {
                        anchors.horizontalCenter: parent.horizontalCenter
                        columns: 3
                        spacing: 12

                        Repeater {
                            model: [
                                { icon: "💧", label: "Water", color: "#4a9eff", style: 0 },
                                { icon: "📺", label: "CRT", color: "#ff6600", style: 2 },
                                { icon: "📟", label: "Terminal", color: "#00ff00", style: 3 }
                            ]

                            Rectangle {
                                width: 90
                                height: 56
                                radius: 14
                                color: touchEffectStyle === modelData.style ? Qt.darker(modelData.color, 2) : "#1a1a28"
                                border.color: touchEffectStyle === modelData.style ? modelData.color : "#2a2a3e"
                                border.width: touchEffectStyle === modelData.style ? 2 : 1

                                Column {
                                    anchors.centerIn: parent
                                    spacing: 4

                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: modelData.icon
                                        font.pixelSize: 20
                                    }

                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: modelData.label
                                        font.pixelSize: 10
                                        color: touchEffectStyle === modelData.style ? "#ffffff" : "#666677"
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        touchEffectStyle = modelData.style
                                        saveConfig()
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Fisheye settings
            Rectangle {
                width: settingsColumn.width
                height: fisheyeColumn.height + 32
                radius: 20
                color: "#14141e"
                border.color: "#1a1a2e"
                visible: touchEffectsEnabled

                Column {
                    id: fisheyeColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 16
                    spacing: 16

                    Row {
                        spacing: 10
                        Text { text: "🔍"; font.pixelSize: 20 }
                        Text { text: "Fisheye Lens"; font.pixelSize: 16; font.weight: Font.Medium; color: "#ffffff" }
                    }

                    // Size slider
                    EffectSlider {
                        width: parent.width - 32
                        label: "Size"
                        value: fisheyeSize
                        minVal: 0.05
                        maxVal: 0.30
                        accentColor: Theme.accentColor
                        onValueChanged: { fisheyeSize = value; saveConfig() }
                    }

                    // Strength slider
                    EffectSlider {
                        width: parent.width - 32
                        label: "Strength"
                        value: fisheyeStrength
                        minVal: 0.0
                        maxVal: 0.5
                        accentColor: Theme.accentColor
                        onValueChanged: { fisheyeStrength = value; saveConfig() }
                    }
                }
            }

            // Ripple settings
            Rectangle {
                width: settingsColumn.width
                height: rippleColumn.height + 32
                radius: 20
                color: "#14141e"
                border.color: "#1a1a2e"
                visible: touchEffectsEnabled

                Column {
                    id: rippleColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 16
                    spacing: 16

                    Row {
                        spacing: 10
                        Text { text: "🌊"; font.pixelSize: 20 }
                        Text { text: "Water Ripple"; font.pixelSize: 16; font.weight: Font.Medium; color: "#ffffff" }
                    }

                    // Size slider
                    EffectSlider {
                        width: parent.width - 32
                        label: "Size"
                        value: rippleSize
                        minVal: 0.1
                        maxVal: 0.5
                        accentColor: "#4a9eff"
                        onValueChanged: { rippleSize = value; saveConfig() }
                    }

                    // Strength slider
                    EffectSlider {
                        width: parent.width - 32
                        label: "Strength"
                        value: rippleStrength
                        minVal: 0.0
                        maxVal: 0.3
                        accentColor: "#4a9eff"
                        onValueChanged: { rippleStrength = value; saveConfig() }
                    }

                    // Duration slider
                    EffectSlider {
                        width: parent.width - 32
                        label: "Duration"
                        value: rippleDuration
                        minVal: 0.2
                        maxVal: 1.0
                        accentColor: "#4a9eff"
                        suffix: "s"
                        onValueChanged: { rippleDuration = value; saveConfig() }
                    }
                }
            }

            // Living Pixels toggle - Always visible (not tied to touch distortion)
            EffectToggle {
                width: settingsColumn.width
                title: "Living Pixels"
                subtitle: "Stars, sprites, rain ripples on screen"
                icon: "👁️"
                checked: livingPixels
                accentColor: "#ffaa00"
                onToggled: {
                    livingPixels = !livingPixels
                    saveConfig()
                }
            }

            // Living Pixels sub-toggles card
            Rectangle {
                width: settingsColumn.width
                height: lpSubColumn.height + 24
                radius: 20
                color: "#14141e"
                border.color: "#ffaa00"
                border.width: 1
                visible: livingPixels

                Column {
                    id: lpSubColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 12
                    spacing: 0

                    // Header
                    Row {
                        spacing: 8
                        leftPadding: 4
                        bottomPadding: 8
                        Text {
                            text: "✨"
                            font.pixelSize: 14
                        }
                        Text {
                            text: "Effect Types"
                            font.pixelSize: 13
                            color: "#888899"
                        }
                    }

                    // Sub-toggles in a grid
                    Grid {
                        width: parent.width
                        columns: 2
                        spacing: 8

                        // Stars
                        LivingPixelSubToggle {
                            width: (lpSubColumn.width - 8) / 2
                            icon: "⭐"
                            label: "Stars"
                            checked: lpStars
                            onToggled: {
                                lpStars = !lpStars
                                saveConfig()
                            }
                        }

                        // Shooting Stars
                        LivingPixelSubToggle {
                            width: (lpSubColumn.width - 8) / 2
                            icon: "💫"
                            label: "Shooting"
                            checked: lpShootingStars
                            onToggled: {
                                lpShootingStars = !lpShootingStars
                                saveConfig()
                            }
                        }

                        // Rain ripples
                        LivingPixelSubToggle {
                            width: (lpSubColumn.width - 8) / 2
                            icon: "💧"
                            label: "Ripples"
                            checked: rainEffectEnabled
                            onToggled: {
                                rainEffectEnabled = !rainEffectEnabled
                                saveConfig()
                            }
                        }
                    }
                }
            }

            // ASCII density slider (only shown when Terminal Ripple mode is selected)
            Rectangle {
                width: settingsColumn.width
                height: termColumn.height + 32
                radius: 20
                color: "#14141e"
                border.color: "#1a1a2e"
                visible: touchEffectsEnabled && touchEffectStyle === 3

                Column {
                    id: termColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 16
                    spacing: 16

                    Row {
                        spacing: 10
                        Text { text: "📟"; font.pixelSize: 20 }
                        Text { text: "Terminal Settings"; font.pixelSize: 16; font.weight: Font.Medium; color: "#ffffff" }
                    }

                    EffectSlider {
                        width: parent.width - 32
                        label: "Density"
                        value: asciiDensity
                        minVal: 4.0
                        maxVal: 16.0
                        accentColor: "#00ff00"
                        suffix: "x"
                        onValueChanged: { asciiDensity = value; saveConfig() }
                    }
                }
            }

            Item { height: 60 }
        }
    }

    // Back button
    Rectangle {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 24
        anchors.bottomMargin: 120
        width: 64
        height: 64
        radius: 32
        color: backMouse.pressed ? Qt.darker(Theme.accentColor, 1.2) : Theme.accentColor

        Text {
            anchors.centerIn: parent
            text: "←"
            font.pixelSize: 28
            color: "#ffffff"
        }

        MouseArea {
            id: backMouse
            anchors.fill: parent
            onClicked: stackView.pop()
        }
    }

    // Reusable toggle component
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

    // Sub-toggle for living pixels effects
    component LivingPixelSubToggle: Rectangle {
        property string icon
        property string label
        property bool checked
        signal toggled()

        height: 48
        radius: 12
        color: lpSubMouse.pressed ? "#2a2a3e" : (checked ? "#2a2a38" : "#1a1a28")
        border.color: checked ? "#ffaa00" : "#2a2a3e"
        border.width: checked ? 1 : 0

        Behavior on color { ColorAnimation { duration: 150 } }

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

            // Small check indicator
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 18
                height: 18
                radius: 9
                color: checked ? "#ffaa00" : "#2a2a3e"
                visible: checked

                Text {
                    anchors.centerIn: parent
                    text: "✓"
                    font.pixelSize: 11
                    color: "#000000"
                }
            }
        }

        MouseArea {
            id: lpSubMouse
            anchors.fill: parent
            onClicked: toggled()
        }
    }

    // Individual slider with proper binding
    component EffectSlider: Column {
        property string label
        property real value
        property real minVal: 0.0
        property real maxVal: 1.0
        property color accentColor: Theme.accentColor
        property string suffix: "%"

        spacing: 6

        Row {
            width: parent.width
            Text {
                text: label
                font.pixelSize: 13
                color: "#888899"
            }
            Item { width: parent.width - 80; height: 1 }
            Text {
                text: {
                    if (suffix === "s" || suffix === "x") {
                        return value.toFixed(2) + suffix
                    } else {
                        return (value * 100).toFixed(0) + suffix
                    }
                }
                font.pixelSize: 13
                font.weight: Font.Bold
                color: accentColor
            }
        }

        Item {
            width: parent.width
            height: 32

            Rectangle {
                anchors.centerIn: parent
                width: parent.width
                height: 6
                radius: 3
                color: "#1a1a28"

                Rectangle {
                    width: parent.width * ((value - minVal) / (maxVal - minVal))
                    height: parent.height
                    radius: 3
                    color: accentColor
                }
            }

            Rectangle {
                x: (parent.width - 24) * ((value - minVal) / (maxVal - minVal))
                anchors.verticalCenter: parent.verticalCenter
                width: 24
                height: 24
                radius: 12
                color: "#ffffff"
                border.color: accentColor
                border.width: 2
            }

            MouseArea {
                anchors.fill: parent
                onPressed: updateSlider(mouse)
                onPositionChanged: if (pressed) updateSlider(mouse)
                function updateSlider(mouse) {
                    var r = Math.max(0, Math.min(1, mouse.x / parent.width))
                    value = minVal + r * (maxVal - minVal)
                }
            }
        }
    }
}
