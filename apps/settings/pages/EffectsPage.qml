import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Page {
    id: effectsPage

    // Touch effect settings
    property bool touchEffectsEnabled: true
    property int touchEffectStyle: 0     // 0=water, 1=fire, 2=invert, 3=snow
    property real fisheyeSize: 0.16
    property real fisheyeStrength: 0.13
    property real rippleSize: 0.30
    property real rippleStrength: 0.07
    property real rippleDuration: 0.5

    // System event effects
    property bool volumeRippleEnabled: true      // Edge ripple on volume change
    property bool notificationRippleEnabled: true // Edge ripple on notification
    property bool edgeGlowEnabled: true          // Glow when swiping from edges

    // Lock screen effects
    property bool starryNightEnabled: false      // Animated stars on lock screen
    property bool rainEffectEnabled: false       // Rain that increases before lock
    property real rainIntensity: 0.5             // How much rain

    // Animation settings
    property real transitionSpeed: 1.0

    property string configPath: "/home/droidian/.local/state/flick/effects_config.json"

    Component.onCompleted: loadConfig()

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
                // System effects
                if (config.volume_ripple_enabled !== undefined) volumeRippleEnabled = config.volume_ripple_enabled
                if (config.notification_ripple_enabled !== undefined) notificationRippleEnabled = config.notification_ripple_enabled
                if (config.edge_glow_enabled !== undefined) edgeGlowEnabled = config.edge_glow_enabled
                // Lock screen
                if (config.starry_night_enabled !== undefined) starryNightEnabled = config.starry_night_enabled
                if (config.rain_effect_enabled !== undefined) rainEffectEnabled = config.rain_effect_enabled
                if (config.rain_intensity !== undefined) rainIntensity = config.rain_intensity
                // Animation
                if (config.transition_speed !== undefined) transitionSpeed = config.transition_speed
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
            // System effects
            volume_ripple_enabled: volumeRippleEnabled,
            notification_ripple_enabled: notificationRippleEnabled,
            edge_glow_enabled: edgeGlowEnabled,
            // Lock screen
            starry_night_enabled: starryNightEnabled,
            rain_effect_enabled: rainEffectEnabled,
            rain_intensity: rainIntensity,
            // Animation
            transition_speed: transitionSpeed
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
            color: "#e94560"
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
                icon: ["💧", "🔥", "🔄", "❄️", "💨"][touchEffectStyle] || "💧"
                checked: touchEffectsEnabled
                accentColor: ["#4a9eff", "#ff6b35", "#9966ff", "#88ddff", "#7aab4a"][touchEffectStyle] || "#4a9eff"
                onToggled: {
                    touchEffectsEnabled = !touchEffectsEnabled
                    saveConfig()
                }
            }

            // Effect style selector
            Rectangle {
                width: settingsColumn.width
                height: 100
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

                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 8

                        Repeater {
                            model: [
                                { icon: "💧", label: "Water", color: "#4a9eff" },
                                { icon: "🔥", label: "Fire", color: "#ff6b35" },
                                { icon: "🔄", label: "Invert", color: "#9966ff" },
                                { icon: "❄️", label: "Snow", color: "#88ddff" },
                                { icon: "💨", label: "Fart", color: "#7aab4a" }
                            ]

                            Rectangle {
                                width: 58
                                height: 52
                                radius: 14
                                color: touchEffectStyle === index ? Qt.darker(modelData.color, 2) : "#1a1a28"
                                border.color: touchEffectStyle === index ? modelData.color : "#2a2a3e"
                                border.width: touchEffectStyle === index ? 2 : 1

                                Column {
                                    anchors.centerIn: parent
                                    spacing: 2

                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: modelData.icon
                                        font.pixelSize: 18
                                    }

                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: modelData.label
                                        font.pixelSize: 9
                                        color: touchEffectStyle === index ? "#ffffff" : "#666677"
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        touchEffectStyle = index
                                        saveConfig()
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Fisheye settings
            EffectSliderCard {
                width: settingsColumn.width
                visible: touchEffectsEnabled
                title: "Fisheye Lens"
                icon: "🔍"

                sliders: [
                    { label: "Size", value: fisheyeSize, min: 0.05, max: 0.30, color: "#e94560",
                      onChanged: function(v) { fisheyeSize = v } },
                    { label: "Strength", value: fisheyeStrength, min: 0, max: 0.5, color: "#e94560",
                      onChanged: function(v) { fisheyeStrength = v } }
                ]
                onSave: saveConfig()
            }

            // Ripple settings
            EffectSliderCard {
                width: settingsColumn.width
                visible: touchEffectsEnabled
                title: "Water Ripple"
                icon: "🌊"

                sliders: [
                    { label: "Size", value: rippleSize, min: 0.1, max: 0.5, color: "#4a9eff",
                      onChanged: function(v) { rippleSize = v } },
                    { label: "Strength", value: rippleStrength, min: 0, max: 0.3, color: "#4a9eff",
                      onChanged: function(v) { rippleStrength = v } },
                    { label: "Duration", value: rippleDuration, min: 0.2, max: 1.0, color: "#4a9eff", suffix: "s",
                      onChanged: function(v) { rippleDuration = v } }
                ]
                onSave: saveConfig()
            }

            // Test buttons for each effect
            Rectangle {
                width: settingsColumn.width
                height: 90
                radius: 20
                color: "#14141e"
                border.color: "#1a1a2e"
                visible: touchEffectsEnabled

                Column {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 8

                    Text {
                        text: "Test Effects"
                        font.pixelSize: 14
                        color: "#888899"
                    }

                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 8

                        Repeater {
                            model: [
                                { icon: "💧", label: "Water", style: 0, color: "#4a9eff" },
                                { icon: "🔥", label: "Fire", style: 1, color: "#ff6b35" },
                                { icon: "🔄", label: "Invert", style: 2, color: "#9966ff" },
                                { icon: "❄️", label: "Snow", style: 3, color: "#88ddff" },
                                { icon: "💨", label: "Fart", style: 4, color: "#7aab4a" }
                            ]

                            Rectangle {
                                width: 54
                                height: 42
                                radius: 10
                                color: testArea.pressed ? Qt.darker(modelData.color, 1.5) : "#1a1a28"
                                border.color: modelData.color
                                border.width: 1

                                Column {
                                    anchors.centerIn: parent
                                    spacing: 1

                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: modelData.icon
                                        font.pixelSize: 16
                                    }

                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: modelData.label
                                        font.pixelSize: 8
                                        color: "#888899"
                                    }
                                }

                                MouseArea {
                                    id: testArea
                                    anchors.fill: parent
                                    onClicked: {
                                        // Temporarily switch to this style and trigger a test
                                        var oldStyle = touchEffectStyle
                                        touchEffectStyle = modelData.style
                                        saveConfig()
                                        // Flash feedback
                                        parent.color = modelData.color
                                        flashTimer.start()
                                    }
                                }

                                Timer {
                                    id: flashTimer
                                    interval: 200
                                    onTriggered: parent.color = "#1a1a28"
                                }
                            }
                        }
                    }
                }
            }

            Item { height: 16 }

            // ===== SYSTEM EFFECTS =====
            Text {
                text: "SYSTEM EFFECTS"
                font.pixelSize: 11
                font.letterSpacing: 2
                color: "#555566"
                leftPadding: 8
            }

            EffectToggle {
                width: settingsColumn.width
                title: "Volume Edge Ripple"
                subtitle: "Ripple inward when adjusting volume"
                icon: "🔊"
                checked: volumeRippleEnabled
                accentColor: "#9966ff"
                onToggled: {
                    volumeRippleEnabled = !volumeRippleEnabled
                    saveConfig()
                }
            }

            EffectToggle {
                width: settingsColumn.width
                title: "Notification Ripple"
                subtitle: "Edge glow when notifications arrive"
                icon: "🔔"
                checked: notificationRippleEnabled
                accentColor: "#9966ff"
                onToggled: {
                    notificationRippleEnabled = !notificationRippleEnabled
                    saveConfig()
                }
            }

            EffectToggle {
                width: settingsColumn.width
                title: "Edge Swipe Glow"
                subtitle: "Light trail when swiping from edges"
                icon: "✋"
                checked: edgeGlowEnabled
                accentColor: "#9966ff"
                onToggled: {
                    edgeGlowEnabled = !edgeGlowEnabled
                    saveConfig()
                }
            }

            Item { height: 16 }

            // ===== LOCK SCREEN EFFECTS =====
            Text {
                text: "LOCK SCREEN"
                font.pixelSize: 11
                font.letterSpacing: 2
                color: "#555566"
                leftPadding: 8
            }

            EffectToggle {
                width: settingsColumn.width
                title: "Starry Night"
                subtitle: "Animated twinkling stars"
                icon: "⭐"
                checked: starryNightEnabled
                accentColor: "#ffaa00"
                onToggled: {
                    starryNightEnabled = !starryNightEnabled
                    saveConfig()
                }
            }

            EffectToggle {
                width: settingsColumn.width
                title: "Rain Effect"
                subtitle: "Rain increases before screen locks"
                icon: "🌧️"
                checked: rainEffectEnabled
                accentColor: "#4a9eff"
                onToggled: {
                    rainEffectEnabled = !rainEffectEnabled
                    saveConfig()
                }
            }

            // Rain intensity slider
            EffectSliderCard {
                width: settingsColumn.width
                visible: rainEffectEnabled
                title: "Rain Settings"
                icon: "💦"

                sliders: [
                    { label: "Intensity", value: rainIntensity, min: 0.1, max: 1.0, color: "#4a9eff",
                      onChanged: function(v) { rainIntensity = v } }
                ]
                onSave: saveConfig()
            }

            Item { height: 16 }

            // ===== ANIMATION SPEED =====
            Text {
                text: "ANIMATION SPEED"
                font.pixelSize: 11
                font.letterSpacing: 2
                color: "#555566"
                leftPadding: 8
            }

            Rectangle {
                width: settingsColumn.width
                height: 140
                radius: 20
                color: "#14141e"
                border.color: "#1a1a2e"

                Column {
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 16

                    Row {
                        width: parent.width
                        Text {
                            text: "Global Speed"
                            font.pixelSize: 15
                            color: "#ffffff"
                        }
                        Item { width: parent.width - 140; height: 1 }
                        Text {
                            text: transitionSpeed.toFixed(1) + "x"
                            font.pixelSize: 16
                            font.weight: Font.Bold
                            color: "#9966ff"
                        }
                    }

                    // Slider
                    Item {
                        width: parent.width
                        height: 36

                        Rectangle {
                            anchors.centerIn: parent
                            width: parent.width
                            height: 6
                            radius: 3
                            color: "#1a1a28"

                            Rectangle {
                                width: parent.width * ((transitionSpeed - 0.5) / 1.5)
                                height: parent.height
                                radius: 3
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0.0; color: "#663399" }
                                    GradientStop { position: 1.0; color: "#9966ff" }
                                }
                            }
                        }

                        Rectangle {
                            x: (parent.width - 28) * ((transitionSpeed - 0.5) / 1.5)
                            anchors.verticalCenter: parent.verticalCenter
                            width: 28
                            height: 28
                            radius: 14
                            color: "#ffffff"
                            border.color: "#9966ff"
                            border.width: 2
                        }

                        MouseArea {
                            anchors.fill: parent
                            onPressed: update(mouse)
                            onPositionChanged: if (pressed) update(mouse)
                            onReleased: saveConfig()
                            function update(mouse) {
                                var r = Math.max(0, Math.min(1, mouse.x / parent.width))
                                transitionSpeed = 0.5 + r * 1.5
                            }
                        }
                    }

                    // Presets
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 8

                        Repeater {
                            model: [
                                { label: "Slow", value: 0.5 },
                                { label: "Normal", value: 1.0 },
                                { label: "Fast", value: 1.5 },
                                { label: "Instant", value: 2.0 }
                            ]

                            Rectangle {
                                width: 70
                                height: 32
                                radius: 16
                                color: Math.abs(transitionSpeed - modelData.value) < 0.1 ? "#9966ff" : "#1a1a28"

                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.label
                                    font.pixelSize: 11
                                    color: Math.abs(transitionSpeed - modelData.value) < 0.1 ? "#ffffff" : "#666677"
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        transitionSpeed = modelData.value
                                        saveConfig()
                                    }
                                }
                            }
                        }
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
        color: backMouse.pressed ? "#c23a50" : "#e94560"

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
        property color accentColor: "#e94560"
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

    // Reusable slider card component
    component EffectSliderCard: Rectangle {
        property string title
        property string icon
        property var sliders: []
        signal save()

        height: sliderColumn.height + 32
        radius: 20
        color: "#14141e"
        border.color: "#1a1a2e"

        Column {
            id: sliderColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 16
            spacing: 16

            Row {
                spacing: 10
                Text {
                    text: icon
                    font.pixelSize: 20
                }
                Text {
                    text: title
                    font.pixelSize: 16
                    font.weight: Font.Medium
                    color: "#ffffff"
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Repeater {
                model: sliders

                Column {
                    width: sliderColumn.width - 32
                    spacing: 6

                    Row {
                        width: parent.width
                        Text {
                            text: modelData.label
                            font.pixelSize: 13
                            color: "#888899"
                        }
                        Item { width: parent.width - 80; height: 1 }
                        Text {
                            text: (modelData.suffix === "s" ? modelData.value.toFixed(1) : (modelData.value * 100).toFixed(0)) + (modelData.suffix || "%")
                            font.pixelSize: 13
                            font.weight: Font.Bold
                            color: modelData.color
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
                                width: parent.width * ((modelData.value - modelData.min) / (modelData.max - modelData.min))
                                height: parent.height
                                radius: 3
                                color: modelData.color
                            }
                        }

                        Rectangle {
                            x: (parent.width - 24) * ((modelData.value - modelData.min) / (modelData.max - modelData.min))
                            anchors.verticalCenter: parent.verticalCenter
                            width: 24
                            height: 24
                            radius: 12
                            color: "#ffffff"
                            border.color: modelData.color
                            border.width: 2
                        }

                        MouseArea {
                            anchors.fill: parent
                            onPressed: update(mouse)
                            onPositionChanged: if (pressed) update(mouse)
                            onReleased: save()
                            function update(mouse) {
                                var r = Math.max(0, Math.min(1, mouse.x / parent.width))
                                var v = modelData.min + r * (modelData.max - modelData.min)
                                modelData.onChanged(v)
                            }
                        }
                    }
                }
            }
        }
    }
}
