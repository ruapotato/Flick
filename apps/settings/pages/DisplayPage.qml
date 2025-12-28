import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Page {
    id: displayPage

    property real brightness: 0.75
    property bool autoBrightness: false
    property bool autoSupported: false
    property int selectedTimeout: 1  // Index into timeout list (default 30s)
    property var timeoutValues: [15, 30, 60, 300, 0]  // Seconds for each option
    property real textScale: 2.0  // Text scale factor (0.5 to 3.0, default 2.0)
    property string wallpaperPath: ""  // Path to wallpaper image
    property string accentColor: "#e94560"  // Accent color for buttons
    property var accentColors: ["#e94560", "#4a90d9", "#50c878", "#ffa500", "#9b59b6", "#1abc9c", "#e74c3c", "#f39c12"]
    property var accentColorNames: ["Pink", "Blue", "Green", "Orange", "Purple", "Teal", "Red", "Gold"]
    property string scaleConfigPath: "/home/droidian/.local/state/flick/display_config.json"
    property string pickerResultFile: "/tmp/flick_wallpaper_pick.txt"
    property bool waitingForPicker: false

    Component.onCompleted: {
        loadConfig()
        loadBrightness()
    }

    function loadBrightness() {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file:///tmp/flick-brightness.json", false)
        try {
            xhr.send()
            if (xhr.status === 200) {
                var data = JSON.parse(xhr.responseText)
                if (data.brightness !== undefined) {
                    brightness = data.brightness / 100.0
                }
                autoSupported = (data.auto_supported === true)
                if (data.auto_enabled !== undefined) {
                    autoBrightness = data.auto_enabled
                }
            }
        } catch (e) {
            console.log("Could not read brightness")
        }
    }

    function saveBrightness() {
        var percent = Math.round(brightness * 100)
        console.warn("BRIGHTNESS_CMD:set:" + percent)
    }

    function toggleAutoBrightness() {
        autoBrightness = !autoBrightness
        console.warn("BRIGHTNESS_CMD:auto:" + (autoBrightness ? "on" : "off"))
    }

    function loadConfig() {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file://" + scaleConfigPath, false)
        try {
            xhr.send()
            if (xhr.status === 200) {
                var config = JSON.parse(xhr.responseText)
                if (config.text_scale !== undefined) {
                    textScale = config.text_scale
                }
                if (config.screen_timeout !== undefined) {
                    // Find index for this timeout value
                    var timeout = config.screen_timeout
                    for (var i = 0; i < timeoutValues.length; i++) {
                        if (timeoutValues[i] === timeout) {
                            selectedTimeout = i
                            break
                        }
                    }
                }
                if (config.wallpaper !== undefined) {
                    wallpaperPath = config.wallpaper
                }
                if (config.accent_color !== undefined && config.accent_color !== "") {
                    accentColor = config.accent_color
                }
            }
        } catch (e) {
            console.log("Using default config")
        }
    }

    function saveScaleConfig() {
        // Print to stderr which won't be filtered
        console.warn("SCALE_SAVE:" + textScale.toFixed(2))
    }

    function saveTimeoutConfig() {
        var timeoutSecs = timeoutValues[selectedTimeout]
        console.warn("TIMEOUT_SAVE:" + timeoutSecs)
    }

    function saveWallpaperConfig() {
        // Use "CLEAR" as special marker to explicitly clear wallpaper
        var pathToSave = wallpaperPath === "" ? "CLEAR" : wallpaperPath
        console.warn("WALLPAPER_SAVE:" + pathToSave)
    }

    function saveAccentColor() {
        console.warn("ACCENT_SAVE:" + accentColor)
    }

    // Analyze wallpaper to find a good accent color (SailfishOS style)
    function analyzeWallpaper() {
        if (wallpaperPath === "") return
        colorAnalyzer.source = "file://" + wallpaperPath
    }

    // Hidden image for color analysis
    Image {
        id: colorAnalyzer
        visible: false
        asynchronous: true
        sourceSize.width: 100  // Sample at low res for speed
        sourceSize.height: 100

        onStatusChanged: {
            if (status === Image.Ready) {
                extractColor()
            }
        }

        function extractColor() {
            // Use Canvas to sample pixels
            colorCanvas.requestPaint()
        }
    }

    Canvas {
        id: colorCanvas
        visible: false
        width: 100
        height: 100

        onPaint: {
            var ctx = getContext("2d")
            ctx.drawImage(colorAnalyzer, 0, 0, 100, 100)

            // Sample pixels and find vibrant colors
            var imageData = ctx.getImageData(0, 0, 100, 100)
            var pixels = imageData.data
            var colorCounts = {}
            var vibrantColors = []

            // Sample every 4th pixel for speed
            for (var i = 0; i < pixels.length; i += 16) {
                var r = pixels[i]
                var g = pixels[i + 1]
                var b = pixels[i + 2]

                // Calculate saturation and value
                var max = Math.max(r, g, b)
                var min = Math.min(r, g, b)
                var saturation = max === 0 ? 0 : (max - min) / max
                var value = max / 255

                // Only consider vibrant colors (good saturation and not too dark/light)
                if (saturation > 0.3 && value > 0.3 && value < 0.9) {
                    // Quantize to reduce color space
                    var qr = Math.floor(r / 32) * 32
                    var qg = Math.floor(g / 32) * 32
                    var qb = Math.floor(b / 32) * 32
                    var key = qr + "," + qg + "," + qb

                    if (!colorCounts[key]) {
                        colorCounts[key] = { count: 0, r: qr + 16, g: qg + 16, b: qb + 16 }
                    }
                    colorCounts[key].count++
                }
            }

            // Find the most common vibrant color
            var bestColor = null
            var bestCount = 0
            for (var key in colorCounts) {
                if (colorCounts[key].count > bestCount) {
                    bestCount = colorCounts[key].count
                    bestColor = colorCounts[key]
                }
            }

            if (bestColor) {
                // Boost saturation slightly for better accent
                var hex = "#" +
                    ("0" + Math.min(255, Math.floor(bestColor.r * 1.1)).toString(16)).slice(-2) +
                    ("0" + Math.min(255, Math.floor(bestColor.g * 1.1)).toString(16)).slice(-2) +
                    ("0" + Math.min(255, Math.floor(bestColor.b * 1.1)).toString(16)).slice(-2)
                accentColor = hex.toUpperCase()
                hexInput.text = accentColor.slice(1)
                saveAccentColor()
            }
        }
    }

    function openImagePicker() {
        // Clear any previous result file
        console.warn("PICKER_CLEAR:" + pickerResultFile)
        waitingForPicker = true
        // Launch file app in picker mode
        console.warn("PICKER_LAUNCH:images:/home/droidian/Pictures:" + pickerResultFile)
        // Start polling for result
        pickerPollTimer.start()
    }

    function checkPickerResult() {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file://" + pickerResultFile, false)
        try {
            xhr.send()
            if (xhr.status === 200 && xhr.responseText.trim().length > 0) {
                var path = xhr.responseText.trim()
                console.log("Picker returned: " + path)
                wallpaperPath = path
                saveWallpaperConfig()
                waitingForPicker = false
                pickerPollTimer.stop()
            }
        } catch (e) {
            // File doesn't exist yet, keep polling
        }
    }

    Timer {
        id: pickerPollTimer
        interval: 500
        repeat: true
        onTriggered: checkPickerResult()
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
                    onReleased: saveBrightness()

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
                    onClicked: toggleAutoBrightness()
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
                        onClicked: {
                            selectedTimeout = index
                            saveTimeoutConfig()
                        }
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

            Item { height: 24 }

            Text {
                text: "WALLPAPER"
                font.pixelSize: 12
                font.letterSpacing: 2
                color: "#555566"
                leftPadding: 8
            }

            // Wallpaper selection card
            Rectangle {
                width: settingsColumn.width
                height: 180
                radius: 24
                color: "#14141e"
                border.color: wallpaperPath !== "" ? "#e94560" : "#1a1a2e"
                border.width: wallpaperPath !== "" ? 2 : 1

                Behavior on border.color { ColorAnimation { duration: 200 } }

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 16

                    // Wallpaper preview
                    Rectangle {
                        Layout.preferredWidth: 120
                        Layout.preferredHeight: 148
                        radius: 16
                        color: "#1a1a28"
                        clip: true

                        Image {
                            id: wallpaperPreview
                            anchors.fill: parent
                            source: wallpaperPath !== "" ? "file://" + wallpaperPath : ""
                            fillMode: Image.PreserveAspectCrop
                            visible: wallpaperPath !== ""
                        }

                        Text {
                            anchors.centerIn: parent
                            text: "🖼"
                            font.pixelSize: 48
                            visible: wallpaperPath === ""
                            opacity: 0.3
                        }
                    }

                    Column {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 8

                        Text {
                            text: wallpaperPath !== "" ? "Custom Wallpaper" : "No Wallpaper"
                            font.pixelSize: 20
                            color: "#ffffff"
                        }

                        Text {
                            text: wallpaperPath !== "" ? wallpaperPath.split("/").pop() : "Tap to select an image"
                            font.pixelSize: 13
                            color: "#666677"
                            elide: Text.ElideMiddle
                            width: parent.width
                        }

                        Item { height: 8 }

                        Row {
                            spacing: 12

                            // Select button
                            Rectangle {
                                width: 100
                                height: 44
                                radius: 12
                                color: selectMouse.pressed ? "#c23a50" : "#e94560"

                                Behavior on color { ColorAnimation { duration: 100 } }

                                Text {
                                    anchors.centerIn: parent
                                    text: "Select"
                                    font.pixelSize: 15
                                    font.weight: Font.Medium
                                    color: "#ffffff"
                                }

                                MouseArea {
                                    id: selectMouse
                                    anchors.fill: parent
                                    onClicked: openImagePicker()
                                }
                            }

                            // Clear button (only show if wallpaper is set)
                            Rectangle {
                                width: 80
                                height: 44
                                radius: 12
                                color: clearMouse.pressed ? "#2a2a3e" : "#1a1a28"
                                visible: wallpaperPath !== ""

                                Behavior on color { ColorAnimation { duration: 100 } }

                                Text {
                                    anchors.centerIn: parent
                                    text: "Clear"
                                    font.pixelSize: 15
                                    color: "#888899"
                                }

                                MouseArea {
                                    id: clearMouse
                                    anchors.fill: parent
                                    onClicked: {
                                        wallpaperPath = ""
                                        saveWallpaperConfig()
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Text {
                text: "Select an image to use as your home screen wallpaper."
                font.pixelSize: 13
                color: "#666677"
                leftPadding: 8
            }

            Item { height: 24 }

            Text {
                text: "ACCENT COLOR"
                font.pixelSize: 12
                font.letterSpacing: 2
                color: "#555566"
                leftPadding: 8
            }

            // Accent color selection
            Rectangle {
                width: settingsColumn.width
                height: 340
                radius: 24
                color: "#14141e"
                border.color: "#1a1a2e"
                border.width: 1

                Column {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 12

                    // Header with current color preview
                    Row {
                        spacing: 16

                        Rectangle {
                            width: 48
                            height: 48
                            radius: 24
                            color: accentColor
                            border.color: "#ffffff"
                            border.width: 2
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 4

                            Text {
                                text: "Accent Color"
                                font.pixelSize: 18
                                color: "#ffffff"
                            }

                            Text {
                                text: accentColor.toString().toUpperCase()
                                font.pixelSize: 14
                                font.family: "monospace"
                                color: "#888899"
                            }
                        }
                    }

                    // Preset colors grid
                    Grid {
                        columns: 8
                        spacing: 10
                        anchors.horizontalCenter: parent.horizontalCenter

                        Repeater {
                            model: accentColors.length

                            Rectangle {
                                width: 44
                                height: 44
                                radius: 22
                                color: accentColors[index]
                                border.color: accentColor === accentColors[index] ? "#ffffff" : "transparent"
                                border.width: 2

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        accentColor = accentColors[index]
                                        hexInput.text = accentColor.toString().toUpperCase().slice(1)
                                        saveAccentColor()
                                    }
                                }

                                Text {
                                    anchors.centerIn: parent
                                    text: accentColor === accentColors[index] ? "✓" : ""
                                    font.pixelSize: 20
                                    font.weight: Font.Bold
                                    color: "#ffffff"
                                }
                            }
                        }
                    }

                    // Custom color input
                    Row {
                        spacing: 12
                        anchors.horizontalCenter: parent.horizontalCenter

                        Text {
                            text: "#"
                            font.pixelSize: 24
                            font.family: "monospace"
                            color: "#888899"
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Rectangle {
                            width: 180
                            height: 48
                            radius: 12
                            color: "#1a1a28"
                            border.color: hexInput.activeFocus ? accentColor : "#333344"
                            border.width: 1

                            TextInput {
                                id: hexInput
                                anchors.fill: parent
                                anchors.margins: 12
                                font.pixelSize: 20
                                font.family: "monospace"
                                font.capitalization: Font.AllUppercase
                                color: "#ffffff"
                                maximumLength: 6
                                text: accentColor.toString().toUpperCase().slice(1)
                                inputMethodHints: Qt.ImhNoPredictiveText

                                onTextChanged: {
                                    if (text.length === 6 && /^[0-9A-Fa-f]{6}$/.test(text)) {
                                        accentColor = "#" + text
                                    }
                                }

                                onEditingFinished: {
                                    if (text.length === 6 && /^[0-9A-Fa-f]{6}$/.test(text)) {
                                        accentColor = "#" + text
                                        saveAccentColor()
                                    }
                                }
                            }
                        }

                        Rectangle {
                            width: 48
                            height: 48
                            radius: 12
                            color: applyMouse.pressed ? Qt.darker(accentColor, 1.2) : accentColor

                            Text {
                                anchors.centerIn: parent
                                text: "✓"
                                font.pixelSize: 24
                                color: "#ffffff"
                            }

                            MouseArea {
                                id: applyMouse
                                anchors.fill: parent
                                onClicked: {
                                    if (hexInput.text.length === 6) {
                                        accentColor = "#" + hexInput.text
                                        saveAccentColor()
                                    }
                                }
                            }
                        }
                    }

                    // Auto from wallpaper button
                    Rectangle {
                        width: parent.width - 32
                        height: 52
                        radius: 14
                        color: autoColorMouse.pressed ? "#2a2a3e" : "#1a1a28"
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: wallpaperPath !== ""

                        Row {
                            anchors.centerIn: parent
                            spacing: 12

                            Text {
                                text: "✨"
                                font.pixelSize: 20
                            }

                            Text {
                                text: "Auto from Wallpaper"
                                font.pixelSize: 16
                                color: "#ffffff"
                            }
                        }

                        MouseArea {
                            id: autoColorMouse
                            anchors.fill: parent
                            onClicked: analyzeWallpaper()
                        }
                    }
                }
            }

            Text {
                text: "Changes the color of buttons and accents in all apps."
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
        color: backMouse.pressed ? Qt.darker(accentColor, 1.2) : accentColor

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
