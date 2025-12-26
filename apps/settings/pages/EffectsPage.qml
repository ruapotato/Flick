import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Page {
    id: effectsPage

    // Effect settings
    property bool touchEffectsEnabled: true
    property real fisheyeSize: 0.12      // 12% of screen (smaller default)
    property real fisheyeStrength: 0.20  // 20% distortion (subtler)
    property real rippleSize: 0.25       // 25% of screen
    property real rippleStrength: 0.20   // 20% distortion
    property real rippleDuration: 0.5    // 0.5 seconds

    // Window effects
    property bool wobblyWindows: false
    property bool windowAnimations: true
    property int closeAnimation: 0       // 0=fade, 1=shrink, 2=explode
    property int minimizeAnimation: 0    // 0=scale, 1=genie, 2=magic lamp

    // Transition effects
    property real transitionSpeed: 1.0   // Multiplier

    property string configPath: "/home/droidian/.local/state/flick/effects_config.json"

    Component.onCompleted: loadConfig()

    function loadConfig() {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file://" + configPath, false)
        try {
            xhr.send()
            if (xhr.status === 200) {
                var config = JSON.parse(xhr.responseText)
                if (config.touch_effects_enabled !== undefined) touchEffectsEnabled = config.touch_effects_enabled
                if (config.fisheye_size !== undefined) fisheyeSize = config.fisheye_size
                if (config.fisheye_strength !== undefined) fisheyeStrength = config.fisheye_strength
                if (config.ripple_size !== undefined) rippleSize = config.ripple_size
                if (config.ripple_strength !== undefined) rippleStrength = config.ripple_strength
                if (config.ripple_duration !== undefined) rippleDuration = config.ripple_duration
                if (config.wobbly_windows !== undefined) wobblyWindows = config.wobbly_windows
                if (config.window_animations !== undefined) windowAnimations = config.window_animations
                if (config.close_animation !== undefined) closeAnimation = config.close_animation
                if (config.minimize_animation !== undefined) minimizeAnimation = config.minimize_animation
                if (config.transition_speed !== undefined) transitionSpeed = config.transition_speed
            }
        } catch (e) {
            console.log("Using default effects config")
        }
    }

    function saveConfig() {
        var config = {
            touch_effects_enabled: touchEffectsEnabled,
            fisheye_size: fisheyeSize,
            fisheye_strength: fisheyeStrength,
            ripple_size: rippleSize,
            ripple_strength: rippleStrength,
            ripple_duration: rippleDuration,
            wobbly_windows: wobblyWindows,
            window_animations: windowAnimations,
            close_animation: closeAnimation,
            minimize_animation: minimizeAnimation,
            transition_speed: transitionSpeed
        }

        // Write to temp file first, then move to final location
        var xhr = new XMLHttpRequest()
        xhr.open("PUT", "file://" + configPath, false)
        try {
            xhr.send(JSON.stringify(config, null, 2))
            console.log("Effects config saved")
        } catch (e) {
            console.error("Failed to save effects config:", e)
        }
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
        height: 260
        color: "transparent"

        // Animated gradient orbs
        Rectangle {
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: -60
            width: 200
            height: 200
            radius: 100
            color: "#e94560"
            opacity: 0.15

            SequentialAnimation on opacity {
                loops: Animation.Infinite
                NumberAnimation { to: 0.25; duration: 2000; easing.type: Easing.InOutSine }
                NumberAnimation { to: 0.15; duration: 2000; easing.type: Easing.InOutSine }
            }
        }

        Rectangle {
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: 60
            width: 160
            height: 160
            radius: 80
            color: "#4a9eff"
            opacity: 0.12

            SequentialAnimation on opacity {
                loops: Animation.Infinite
                NumberAnimation { to: 0.20; duration: 1500; easing.type: Easing.InOutSine }
                NumberAnimation { to: 0.12; duration: 1500; easing.type: Easing.InOutSine }
            }
        }

        Column {
            anchors.centerIn: parent
            spacing: 12

            // Sparkle icon
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "✨"
                font.pixelSize: 72
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Effects"
                font.pixelSize: 42
                font.weight: Font.ExtraLight
                font.letterSpacing: 6
                color: "#ffffff"
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "COMPIZ-STYLE MAGIC"
                font.pixelSize: 12
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

            // ===== TOUCH EFFECTS SECTION =====
            Text {
                text: "TOUCH EFFECTS"
                font.pixelSize: 12
                font.letterSpacing: 2
                color: "#555566"
                leftPadding: 8
            }

            // Master toggle
            Rectangle {
                width: settingsColumn.width
                height: 100
                radius: 24
                color: touchMasterMouse.pressed ? "#1e1e2e" : "#14141e"
                border.color: touchEffectsEnabled ? "#e94560" : "#1a1a2e"
                border.width: touchEffectsEnabled ? 2 : 1

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 16

                    Rectangle {
                        Layout.preferredWidth: 56
                        Layout.preferredHeight: 56
                        radius: 14
                        color: touchEffectsEnabled ? "#3a1a2a" : "#1a1a28"

                        Text {
                            anchors.centerIn: parent
                            text: "💧"
                            font.pixelSize: 28
                        }
                    }

                    Column {
                        Layout.fillWidth: true
                        spacing: 6

                        Text {
                            text: "Touch Distortion"
                            font.pixelSize: 20
                            color: "#ffffff"
                        }

                        Text {
                            text: "Fisheye lens & water ripple effects"
                            font.pixelSize: 13
                            color: "#666677"
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: 64
                        Layout.preferredHeight: 36
                        radius: 18
                        color: touchEffectsEnabled ? "#e94560" : "#2a2a3e"

                        Behavior on color { ColorAnimation { duration: 200 } }

                        Rectangle {
                            x: touchEffectsEnabled ? parent.width - width - 4 : 4
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
                    id: touchMasterMouse
                    anchors.fill: parent
                    onClicked: {
                        touchEffectsEnabled = !touchEffectsEnabled
                        saveConfig()
                    }
                }
            }

            // Fisheye settings (only shown when enabled)
            Rectangle {
                width: settingsColumn.width
                height: fisheyeColumn.height + 40
                radius: 24
                color: "#14141e"
                border.color: "#1a1a2e"
                visible: touchEffectsEnabled

                Column {
                    id: fisheyeColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 20
                    spacing: 20

                    Row {
                        spacing: 12
                        Text {
                            text: "🔍"
                            font.pixelSize: 24
                        }
                        Text {
                            text: "Fisheye Lens"
                            font.pixelSize: 18
                            font.weight: Font.Medium
                            color: "#ffffff"
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    // Size slider
                    Column {
                        width: parent.width
                        spacing: 8

                        Row {
                            width: parent.width
                            Text {
                                text: "Size"
                                font.pixelSize: 14
                                color: "#888899"
                            }
                            Item { width: parent.width - 100; height: 1 }
                            Text {
                                text: (fisheyeSize * 100).toFixed(0) + "%"
                                font.pixelSize: 14
                                font.weight: Font.Bold
                                color: "#e94560"
                            }
                        }

                        Item {
                            width: parent.width
                            height: 40

                            Rectangle {
                                anchors.centerIn: parent
                                width: parent.width
                                height: 8
                                radius: 4
                                color: "#1a1a28"

                                Rectangle {
                                    width: parent.width * ((fisheyeSize - 0.05) / 0.25)
                                    height: parent.height
                                    radius: 4
                                    gradient: Gradient {
                                        orientation: Gradient.Horizontal
                                        GradientStop { position: 0.0; color: "#993366" }
                                        GradientStop { position: 1.0; color: "#e94560" }
                                    }
                                }
                            }

                            Rectangle {
                                x: (parent.width - 32) * ((fisheyeSize - 0.05) / 0.25)
                                anchors.verticalCenter: parent.verticalCenter
                                width: 32
                                height: 32
                                radius: 16
                                color: "#ffffff"
                                border.color: "#e94560"
                                border.width: 2
                            }

                            MouseArea {
                                anchors.fill: parent
                                onPressed: updateFisheyeSize(mouse)
                                onPositionChanged: if (pressed) updateFisheyeSize(mouse)
                                onReleased: saveConfig()

                                function updateFisheyeSize(mouse) {
                                    var ratio = Math.max(0, Math.min(1, mouse.x / parent.width))
                                    fisheyeSize = 0.05 + ratio * 0.25  // 5% to 30%
                                }
                            }
                        }
                    }

                    // Strength slider
                    Column {
                        width: parent.width
                        spacing: 8

                        Row {
                            width: parent.width
                            Text {
                                text: "Strength"
                                font.pixelSize: 14
                                color: "#888899"
                            }
                            Item { width: parent.width - 100; height: 1 }
                            Text {
                                text: (fisheyeStrength * 100).toFixed(0) + "%"
                                font.pixelSize: 14
                                font.weight: Font.Bold
                                color: "#e94560"
                            }
                        }

                        Item {
                            width: parent.width
                            height: 40

                            Rectangle {
                                anchors.centerIn: parent
                                width: parent.width
                                height: 8
                                radius: 4
                                color: "#1a1a28"

                                Rectangle {
                                    width: parent.width * (fisheyeStrength / 0.5)
                                    height: parent.height
                                    radius: 4
                                    gradient: Gradient {
                                        orientation: Gradient.Horizontal
                                        GradientStop { position: 0.0; color: "#993366" }
                                        GradientStop { position: 1.0; color: "#e94560" }
                                    }
                                }
                            }

                            Rectangle {
                                x: (parent.width - 32) * (fisheyeStrength / 0.5)
                                anchors.verticalCenter: parent.verticalCenter
                                width: 32
                                height: 32
                                radius: 16
                                color: "#ffffff"
                                border.color: "#e94560"
                                border.width: 2
                            }

                            MouseArea {
                                anchors.fill: parent
                                onPressed: updateFisheyeStrength(mouse)
                                onPositionChanged: if (pressed) updateFisheyeStrength(mouse)
                                onReleased: saveConfig()

                                function updateFisheyeStrength(mouse) {
                                    var ratio = Math.max(0, Math.min(1, mouse.x / parent.width))
                                    fisheyeStrength = ratio * 0.5  // 0% to 50%
                                }
                            }
                        }
                    }
                }
            }

            // Ripple settings
            Rectangle {
                width: settingsColumn.width
                height: rippleColumn.height + 40
                radius: 24
                color: "#14141e"
                border.color: "#1a1a2e"
                visible: touchEffectsEnabled

                Column {
                    id: rippleColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 20
                    spacing: 20

                    Row {
                        spacing: 12
                        Text {
                            text: "🌊"
                            font.pixelSize: 24
                        }
                        Text {
                            text: "Water Ripple"
                            font.pixelSize: 18
                            font.weight: Font.Medium
                            color: "#ffffff"
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    // Size slider
                    Column {
                        width: parent.width
                        spacing: 8

                        Row {
                            width: parent.width
                            Text {
                                text: "Size"
                                font.pixelSize: 14
                                color: "#888899"
                            }
                            Item { width: parent.width - 100; height: 1 }
                            Text {
                                text: (rippleSize * 100).toFixed(0) + "%"
                                font.pixelSize: 14
                                font.weight: Font.Bold
                                color: "#4a9eff"
                            }
                        }

                        Item {
                            width: parent.width
                            height: 40

                            Rectangle {
                                anchors.centerIn: parent
                                width: parent.width
                                height: 8
                                radius: 4
                                color: "#1a1a28"

                                Rectangle {
                                    width: parent.width * ((rippleSize - 0.1) / 0.4)
                                    height: parent.height
                                    radius: 4
                                    gradient: Gradient {
                                        orientation: Gradient.Horizontal
                                        GradientStop { position: 0.0; color: "#2a4a6a" }
                                        GradientStop { position: 1.0; color: "#4a9eff" }
                                    }
                                }
                            }

                            Rectangle {
                                x: (parent.width - 32) * ((rippleSize - 0.1) / 0.4)
                                anchors.verticalCenter: parent.verticalCenter
                                width: 32
                                height: 32
                                radius: 16
                                color: "#ffffff"
                                border.color: "#4a9eff"
                                border.width: 2
                            }

                            MouseArea {
                                anchors.fill: parent
                                onPressed: updateRippleSize(mouse)
                                onPositionChanged: if (pressed) updateRippleSize(mouse)
                                onReleased: saveConfig()

                                function updateRippleSize(mouse) {
                                    var ratio = Math.max(0, Math.min(1, mouse.x / parent.width))
                                    rippleSize = 0.1 + ratio * 0.4  // 10% to 50%
                                }
                            }
                        }
                    }

                    // Strength slider
                    Column {
                        width: parent.width
                        spacing: 8

                        Row {
                            width: parent.width
                            Text {
                                text: "Strength"
                                font.pixelSize: 14
                                color: "#888899"
                            }
                            Item { width: parent.width - 100; height: 1 }
                            Text {
                                text: (rippleStrength * 100).toFixed(0) + "%"
                                font.pixelSize: 14
                                font.weight: Font.Bold
                                color: "#4a9eff"
                            }
                        }

                        Item {
                            width: parent.width
                            height: 40

                            Rectangle {
                                anchors.centerIn: parent
                                width: parent.width
                                height: 8
                                radius: 4
                                color: "#1a1a28"

                                Rectangle {
                                    width: parent.width * (rippleStrength / 0.5)
                                    height: parent.height
                                    radius: 4
                                    gradient: Gradient {
                                        orientation: Gradient.Horizontal
                                        GradientStop { position: 0.0; color: "#2a4a6a" }
                                        GradientStop { position: 1.0; color: "#4a9eff" }
                                    }
                                }
                            }

                            Rectangle {
                                x: (parent.width - 32) * (rippleStrength / 0.5)
                                anchors.verticalCenter: parent.verticalCenter
                                width: 32
                                height: 32
                                radius: 16
                                color: "#ffffff"
                                border.color: "#4a9eff"
                                border.width: 2
                            }

                            MouseArea {
                                anchors.fill: parent
                                onPressed: updateRippleStrength(mouse)
                                onPositionChanged: if (pressed) updateRippleStrength(mouse)
                                onReleased: saveConfig()

                                function updateRippleStrength(mouse) {
                                    var ratio = Math.max(0, Math.min(1, mouse.x / parent.width))
                                    rippleStrength = ratio * 0.5  // 0% to 50%
                                }
                            }
                        }
                    }

                    // Duration slider
                    Column {
                        width: parent.width
                        spacing: 8

                        Row {
                            width: parent.width
                            Text {
                                text: "Duration"
                                font.pixelSize: 14
                                color: "#888899"
                            }
                            Item { width: parent.width - 100; height: 1 }
                            Text {
                                text: rippleDuration.toFixed(1) + "s"
                                font.pixelSize: 14
                                font.weight: Font.Bold
                                color: "#4a9eff"
                            }
                        }

                        Item {
                            width: parent.width
                            height: 40

                            Rectangle {
                                anchors.centerIn: parent
                                width: parent.width
                                height: 8
                                radius: 4
                                color: "#1a1a28"

                                Rectangle {
                                    width: parent.width * ((rippleDuration - 0.2) / 0.8)
                                    height: parent.height
                                    radius: 4
                                    gradient: Gradient {
                                        orientation: Gradient.Horizontal
                                        GradientStop { position: 0.0; color: "#2a4a6a" }
                                        GradientStop { position: 1.0; color: "#4a9eff" }
                                    }
                                }
                            }

                            Rectangle {
                                x: (parent.width - 32) * ((rippleDuration - 0.2) / 0.8)
                                anchors.verticalCenter: parent.verticalCenter
                                width: 32
                                height: 32
                                radius: 16
                                color: "#ffffff"
                                border.color: "#4a9eff"
                                border.width: 2
                            }

                            MouseArea {
                                anchors.fill: parent
                                onPressed: updateRippleDuration(mouse)
                                onPositionChanged: if (pressed) updateRippleDuration(mouse)
                                onReleased: saveConfig()

                                function updateRippleDuration(mouse) {
                                    var ratio = Math.max(0, Math.min(1, mouse.x / parent.width))
                                    rippleDuration = 0.2 + ratio * 0.8  // 0.2s to 1.0s
                                }
                            }
                        }
                    }
                }
            }

            Item { height: 24 }

            // ===== WINDOW EFFECTS SECTION =====
            Text {
                text: "WINDOW EFFECTS"
                font.pixelSize: 12
                font.letterSpacing: 2
                color: "#555566"
                leftPadding: 8
            }

            // Wobbly Windows toggle
            Rectangle {
                width: settingsColumn.width
                height: 100
                radius: 24
                color: wobblyMouse.pressed ? "#1e1e2e" : "#14141e"
                border.color: wobblyWindows ? "#4a9eff" : "#1a1a2e"
                border.width: wobblyWindows ? 2 : 1

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 16

                    Rectangle {
                        Layout.preferredWidth: 56
                        Layout.preferredHeight: 56
                        radius: 14
                        color: wobblyWindows ? "#1a2a4a" : "#1a1a28"

                        Text {
                            anchors.centerIn: parent
                            text: "〰️"
                            font.pixelSize: 28
                        }
                    }

                    Column {
                        Layout.fillWidth: true
                        spacing: 6

                        Text {
                            text: "Wobbly Windows"
                            font.pixelSize: 20
                            color: "#ffffff"
                        }

                        Text {
                            text: "Windows wobble when moved (coming soon)"
                            font.pixelSize: 13
                            color: "#666677"
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: 64
                        Layout.preferredHeight: 36
                        radius: 18
                        color: wobblyWindows ? "#4a9eff" : "#2a2a3e"

                        Behavior on color { ColorAnimation { duration: 200 } }

                        Rectangle {
                            x: wobblyWindows ? parent.width - width - 4 : 4
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
                    id: wobblyMouse
                    anchors.fill: parent
                    onClicked: {
                        wobblyWindows = !wobblyWindows
                        saveConfig()
                    }
                }
            }

            // Window animations toggle
            Rectangle {
                width: settingsColumn.width
                height: 100
                radius: 24
                color: animMouse.pressed ? "#1e1e2e" : "#14141e"
                border.color: windowAnimations ? "#4a9eff" : "#1a1a2e"
                border.width: windowAnimations ? 2 : 1

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 16

                    Rectangle {
                        Layout.preferredWidth: 56
                        Layout.preferredHeight: 56
                        radius: 14
                        color: windowAnimations ? "#1a2a4a" : "#1a1a28"

                        Text {
                            anchors.centerIn: parent
                            text: "🎬"
                            font.pixelSize: 28
                        }
                    }

                    Column {
                        Layout.fillWidth: true
                        spacing: 6

                        Text {
                            text: "Window Animations"
                            font.pixelSize: 20
                            color: "#ffffff"
                        }

                        Text {
                            text: "Animate window open/close"
                            font.pixelSize: 13
                            color: "#666677"
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: 64
                        Layout.preferredHeight: 36
                        radius: 18
                        color: windowAnimations ? "#4a9eff" : "#2a2a3e"

                        Behavior on color { ColorAnimation { duration: 200 } }

                        Rectangle {
                            x: windowAnimations ? parent.width - width - 4 : 4
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
                    id: animMouse
                    anchors.fill: parent
                    onClicked: {
                        windowAnimations = !windowAnimations
                        saveConfig()
                    }
                }
            }

            Item { height: 24 }

            // ===== ANIMATION SPEED SECTION =====
            Text {
                text: "ANIMATION SPEED"
                font.pixelSize: 12
                font.letterSpacing: 2
                color: "#555566"
                leftPadding: 8
            }

            Rectangle {
                width: settingsColumn.width
                height: 120
                radius: 24
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
                            font.pixelSize: 16
                            color: "#ffffff"
                        }
                        Item { width: parent.width - 160; height: 1 }
                        Text {
                            text: transitionSpeed.toFixed(1) + "x"
                            font.pixelSize: 18
                            font.weight: Font.Bold
                            color: "#9966ff"
                        }
                    }

                    Item {
                        width: parent.width
                        height: 40

                        Rectangle {
                            anchors.centerIn: parent
                            width: parent.width
                            height: 8
                            radius: 4
                            color: "#1a1a28"

                            Rectangle {
                                width: parent.width * ((transitionSpeed - 0.5) / 1.5)
                                height: parent.height
                                radius: 4
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0.0; color: "#663399" }
                                    GradientStop { position: 1.0; color: "#9966ff" }
                                }
                            }
                        }

                        Rectangle {
                            x: (parent.width - 32) * ((transitionSpeed - 0.5) / 1.5)
                            anchors.verticalCenter: parent.verticalCenter
                            width: 32
                            height: 32
                            radius: 16
                            color: "#ffffff"
                            border.color: "#9966ff"
                            border.width: 2
                        }

                        MouseArea {
                            anchors.fill: parent
                            onPressed: updateSpeed(mouse)
                            onPositionChanged: if (pressed) updateSpeed(mouse)
                            onReleased: saveConfig()

                            function updateSpeed(mouse) {
                                var ratio = Math.max(0, Math.min(1, mouse.x / parent.width))
                                transitionSpeed = 0.5 + ratio * 1.5  // 0.5x to 2.0x
                            }
                        }
                    }
                }
            }

            // Speed presets
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 12

                Repeater {
                    model: [
                        { label: "Slow", value: 0.5 },
                        { label: "Normal", value: 1.0 },
                        { label: "Fast", value: 1.5 },
                        { label: "Instant", value: 2.0 }
                    ]

                    Rectangle {
                        width: 80
                        height: 44
                        radius: 22
                        color: Math.abs(transitionSpeed - modelData.value) < 0.1 ? "#9966ff" : "#1a1a28"
                        border.color: "#2a2a3e"

                        Text {
                            anchors.centerIn: parent
                            text: modelData.label
                            font.pixelSize: 13
                            color: Math.abs(transitionSpeed - modelData.value) < 0.1 ? "#ffffff" : "#888899"
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

            Item { height: 40 }
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
