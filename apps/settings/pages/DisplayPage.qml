import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Qt.labs.folderlistmodel 2.15

Page {
    id: displayPage

    property real brightness: 0.75
    property bool autoBrightness: false
    property bool autoSupported: false
    property int selectedTimeout: 1  // Index into timeout list (default 30s)
    property var timeoutValues: [15, 30, 60, 300, 0]  // Seconds for each option
    property real textScale: 2.0  // Text scale factor (0.5 to 3.0, default 2.0)
    property string wallpaperPath: ""  // Path to wallpaper image
    property string scaleConfigPath: "/home/droidian/.local/state/flick/display_config.json"
    property bool showImagePicker: false
    property string pickerCurrentPath: "/home/droidian/Pictures"

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
        console.warn("WALLPAPER_SAVE:" + wallpaperPath)
    }

    function isImageFile(fileName) {
        var lower = fileName.toLowerCase()
        return lower.endsWith(".png") || lower.endsWith(".jpg") ||
               lower.endsWith(".jpeg") || lower.endsWith(".webp") ||
               lower.endsWith(".bmp") || lower.endsWith(".gif")
    }

    function openImagePicker() {
        pickerCurrentPath = "/home/droidian/Pictures"
        showImagePicker = true
    }

    function selectImage(path) {
        wallpaperPath = path
        saveWallpaperConfig()
        showImagePicker = false
    }

    function pickerGoUp() {
        if (pickerCurrentPath === "/") return
        var parts = pickerCurrentPath.split("/")
        parts.pop()
        var newPath = parts.join("/")
        if (newPath === "") newPath = "/"
        pickerCurrentPath = newPath
    }

    // Folder model for image picker
    FolderListModel {
        id: pickerFolderModel
        folder: "file://" + pickerCurrentPath
        showDirs: true
        showDotAndDotDot: false
        showHidden: false
        sortField: FolderListModel.Name
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

    // Image picker overlay
    Rectangle {
        id: imagePickerOverlay
        anchors.fill: parent
        color: "#0a0a0f"
        visible: showImagePicker
        z: 100

        // Header
        Rectangle {
            id: pickerHeader
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 80
            color: "#1a1a2e"

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 20
                anchors.verticalCenter: parent.verticalCenter
                text: "Select Image"
                font.pixelSize: 24
                font.weight: Font.Medium
                color: "#ffffff"
            }

            // Close button
            Rectangle {
                anchors.right: parent.right
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                width: 48
                height: 48
                radius: 24
                color: closeMouse.pressed ? "#333344" : "transparent"

                Text {
                    anchors.centerIn: parent
                    text: "✕"
                    font.pixelSize: 24
                    color: "#888899"
                }

                MouseArea {
                    id: closeMouse
                    anchors.fill: parent
                    onClicked: showImagePicker = false
                }
            }
        }

        // Current path
        Rectangle {
            id: pathBar
            anchors.top: pickerHeader.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: 50
            color: "#14141e"

            Row {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                spacing: 12

                // Up button
                Rectangle {
                    width: 40
                    height: 40
                    anchors.verticalCenter: parent.verticalCenter
                    radius: 8
                    color: upMouse.pressed ? "#333344" : "#1a1a2e"
                    visible: pickerCurrentPath !== "/"

                    Text {
                        anchors.centerIn: parent
                        text: "↑"
                        font.pixelSize: 20
                        color: "#ffffff"
                    }

                    MouseArea {
                        id: upMouse
                        anchors.fill: parent
                        onClicked: pickerGoUp()
                    }
                }

                Text {
                    width: parent.width - 60
                    anchors.verticalCenter: parent.verticalCenter
                    text: pickerCurrentPath
                    font.pixelSize: 13
                    color: "#888899"
                    elide: Text.ElideMiddle
                }
            }
        }

        // Image grid
        GridView {
            id: imageGrid
            anchors.top: pathBar.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 8
            anchors.bottomMargin: 40
            cellWidth: (width - 16) / 3
            cellHeight: cellWidth
            clip: true

            model: pickerFolderModel

            delegate: Item {
                width: imageGrid.cellWidth
                height: imageGrid.cellHeight
                visible: model.fileIsDir || isImageFile(model.fileName)

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 4
                    radius: 12
                    color: itemMouse.pressed ? "#333344" : "#1a1a2e"
                    clip: true

                    // Folder icon or image preview
                    Image {
                        anchors.fill: parent
                        anchors.margins: model.fileIsDir ? 30 : 0
                        source: model.fileIsDir ? "" : "file://" + model.filePath
                        fillMode: Image.PreserveAspectCrop
                        visible: !model.fileIsDir && isImageFile(model.fileName)
                        asynchronous: true

                        // Loading placeholder
                        Rectangle {
                            anchors.fill: parent
                            color: "#1a1a2e"
                            visible: parent.status === Image.Loading
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: model.fileIsDir ? "📁" : ""
                        font.pixelSize: 48
                        visible: model.fileIsDir
                    }

                    // File name label
                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: 32
                        color: "#cc000000"
                        visible: !model.fileIsDir

                        Text {
                            anchors.fill: parent
                            anchors.margins: 4
                            text: model.fileName
                            font.pixelSize: 10
                            color: "#ffffff"
                            elide: Text.ElideMiddle
                            verticalAlignment: Text.AlignVCenter
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }

                    // Folder name
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 8
                        width: parent.width - 8
                        text: model.fileIsDir ? model.fileName : ""
                        font.pixelSize: 11
                        color: "#aaaacc"
                        elide: Text.ElideMiddle
                        horizontalAlignment: Text.AlignHCenter
                        visible: model.fileIsDir
                    }

                    MouseArea {
                        id: itemMouse
                        anchors.fill: parent
                        onClicked: {
                            if (model.fileIsDir) {
                                pickerCurrentPath = model.filePath
                            } else if (isImageFile(model.fileName)) {
                                selectImage(model.filePath)
                            }
                        }
                    }
                }
            }
        }

        // Empty state
        Text {
            anchors.centerIn: imageGrid
            visible: pickerFolderModel.count === 0
            text: "No images found"
            color: "#666677"
            font.pixelSize: 16
        }
    }
}
