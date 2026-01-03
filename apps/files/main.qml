import QtQuick 2.15
import QtQuick.Window 2.15
import QtQuick.Controls 2.15
import Qt.labs.folderlistmodel 2.15

Window {
    id: root
    visible: true
    width: 720
    height: 1600
    title: pickerMode ? "Select " + (pickerFilter === "images" ? "Image" : pickerFilter === "vcf" ? "Contact File" : "File") : "Flick Files"
    color: "#0a0a0f"

    // Use shell text scale
    property real textScale: 1.0
    property string currentPath: Theme.homeDir
    property color accentColor: accentColor

    // Picker mode properties (set via environment variables)
    property bool pickerMode: false
    property string pickerFilter: ""  // "images", "audio", "video", or empty for all
    property string pickerResultFile: ""

    // Context menu state
    property var selectedFile: null
    property string clipboardPath: ""
    property string clipboardAction: "" // "copy" or "cut"

    Component.onCompleted: {
        loadConfig()
        loadPickerConfig()
    }

    function loadPickerConfig() {
        // Read picker settings from environment (set by shell script)
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file:///proc/self/environ", false)
        try {
            xhr.send()
            var env = xhr.responseText
            // Parse null-separated environment variables
            var vars = env.split('\0')
            for (var i = 0; i < vars.length; i++) {
                var v = vars[i]
                if (v.indexOf("FLICK_PICKER_MODE=") === 0) {
                    pickerMode = (v.split("=")[1] === "true")
                } else if (v.indexOf("FLICK_PICKER_FILTER=") === 0) {
                    pickerFilter = v.split("=")[1]
                } else if (v.indexOf("FLICK_PICKER_START_DIR=") === 0) {
                    var startDir = v.substring(v.indexOf("=") + 1)
                    if (startDir && startDir.length > 0) {
                        currentPath = startDir
                        folderModel.folder = "file://" + startDir
                    }
                } else if (v.indexOf("FLICK_PICKER_RESULT_FILE=") === 0) {
                    pickerResultFile = v.substring(v.indexOf("=") + 1)
                }
            }
            console.log("Picker mode:", pickerMode, "Filter:", pickerFilter, "Start:", currentPath)
        } catch (e) {
            console.log("Could not read picker config:", e)
        }
    }

    function matchesFilter(fileName) {
        if (!pickerMode || pickerFilter === "") return true
        var lower = fileName.toLowerCase()
        if (pickerFilter === "images") {
            return lower.endsWith(".png") || lower.endsWith(".jpg") ||
                   lower.endsWith(".jpeg") || lower.endsWith(".webp") ||
                   lower.endsWith(".bmp") || lower.endsWith(".gif")
        } else if (pickerFilter === "audio") {
            return lower.endsWith(".mp3") || lower.endsWith(".wav") ||
                   lower.endsWith(".ogg") || lower.endsWith(".flac") ||
                   lower.endsWith(".m4a") || lower.endsWith(".aac")
        } else if (pickerFilter === "video") {
            return lower.endsWith(".mp4") || lower.endsWith(".mkv") ||
                   lower.endsWith(".webm") || lower.endsWith(".avi") ||
                   lower.endsWith(".mov")
        } else if (pickerFilter === "vcf") {
            return lower.endsWith(".vcf") || lower.endsWith(".vcard")
        }
        return true
    }

    function pickFile(filePath) {
        console.log("PICKER_RESULT:" + filePath)
        Qt.quit()
    }

    function loadConfig() {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file://" + Theme.stateDir + "/display_config.json")
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200 || xhr.status === 0) {
                    try {
                        var config = JSON.parse(xhr.responseText)
                        textScale = config.text_scale || 1.0
                    } catch (e) {
                        console.log("Failed to parse display config:", e)
                    }
                }
            }
        }
        xhr.send()
    }

    FolderListModel {
        id: folderModel
        folder: "file://" + currentPath
        showDirs: true
        showDotAndDotDot: false
        showHidden: false
        sortField: FolderListModel.Name
    }

    function navigateTo(path) {
        currentPath = path
        folderModel.folder = "file://" + path
    }

    function goUp() {
        if (currentPath === "/") {
            Qt.quit()
            return
        }
        var parts = currentPath.split("/")
        parts.pop()
        var newPath = parts.join("/")
        if (newPath === "") newPath = "/"
        navigateTo(newPath)
    }

    function formatSize(bytes) {
        if (bytes < 1024) return bytes + " B"
        if (bytes < 1048576) return (bytes / 1024).toFixed(1) + " KB"
        if (bytes < 1073741824) return (bytes / 1048576).toFixed(1) + " MB"
        return (bytes / 1073741824).toFixed(2) + " GB"
    }

    function formatDate(date) {
        var months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        var d = new Date(date)
        return months[d.getMonth()] + " " + d.getDate() + ", " + d.getFullYear()
    }

    function openFile(path) {
        console.log("Opening file: " + path)
        // Use xdg-open to open the file
        var process = Qt.createQmlObject('import QtQuick 2.15; QtObject {}', root)
        var command = "xdg-open \"" + path + "\" &"
        // Log command for shell script to execute
        console.log("FILE_OPEN:" + path)
    }

    function showContextMenu(filePath, fileName, isDir) {
        selectedFile = {
            path: filePath,
            name: fileName,
            isDir: isDir
        }
        contextMenu.visible = true
    }

    function copyFile() {
        if (selectedFile) {
            clipboardPath = selectedFile.path
            clipboardAction = "copy"
            console.log("FILE_COPY:" + selectedFile.path)
        }
        contextMenu.visible = false
    }

    function cutFile() {
        if (selectedFile) {
            clipboardPath = selectedFile.path
            clipboardAction = "cut"
            console.log("FILE_CUT:" + selectedFile.path)
        }
        contextMenu.visible = false
    }

    function pasteFile() {
        if (clipboardPath && clipboardAction) {
            var cmd = clipboardAction === "copy" ? "FILE_PASTE_COPY" : "FILE_PASTE_MOVE"
            console.log(cmd + ":" + clipboardPath + ":" + currentPath)
            if (clipboardAction === "cut") {
                clipboardPath = ""
                clipboardAction = ""
            }
        }
    }

    function deleteFile() {
        if (selectedFile) {
            console.log("FILE_DELETE:" + selectedFile.path)
        }
        contextMenu.visible = false
    }

    function renameFile() {
        if (selectedFile) {
            renameInput.text = selectedFile.name
            renameDialog.visible = true
        }
        contextMenu.visible = false
    }

    function confirmRename() {
        if (selectedFile && renameInput.text.length > 0) {
            var dir = selectedFile.path.substring(0, selectedFile.path.lastIndexOf("/"))
            var newPath = dir + "/" + renameInput.text
            console.log("FILE_RENAME:" + selectedFile.path + ":" + newPath)
        }
        renameDialog.visible = false
    }

    // Title bar with current path
    Rectangle {
        id: titleBar
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 50 * textScale
        color: "#1a1a2e"
        z: 2

        Text {
            anchors.fill: parent
            anchors.leftMargin: 16 * textScale
            anchors.rightMargin: 16 * textScale
            text: currentPath
            color: "#aaaacc"
            font.pixelSize: 12 * textScale
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideMiddle
        }
    }

    // File list
    ListView {
        id: listView
        anchors.top: titleBar.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: homeIndicator.top
        anchors.bottomMargin: 80 * textScale
        clip: true

        model: folderModel
        delegate: Rectangle {
            width: listView.width
            height: (model.fileIsDir || matchesFilter(model.fileName)) ? 70 * textScale : 0
            visible: model.fileIsDir || matchesFilter(model.fileName)
            color: mouseArea.pressed ? "#1a1a2e" : "transparent"

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 1
                color: "#1a1a2e"
            }

            Row {
                anchors.fill: parent
                anchors.leftMargin: 16 * textScale
                anchors.rightMargin: 16 * textScale
                spacing: 12 * textScale

                // Icon or thumbnail
                Rectangle {
                    width: 50 * textScale
                    height: 50 * textScale
                    anchors.verticalCenter: parent.verticalCenter
                    radius: 8
                    color: "#1a1a2e"
                    clip: true

                    // Image thumbnail for image files
                    Image {
                        anchors.fill: parent
                        source: (!model.fileIsDir && pickerFilter === "images" && matchesFilter(model.fileName))
                                ? "file://" + model.filePath : ""
                        fillMode: Image.PreserveAspectCrop
                        visible: !model.fileIsDir && pickerFilter === "images" && matchesFilter(model.fileName)
                        asynchronous: true
                    }

                    Text {
                        anchors.centerIn: parent
                        text: model.fileIsDir ? "📁" : (pickerFilter === "images" ? "" : "📄")
                        font.pixelSize: 24 * textScale
                        visible: model.fileIsDir || pickerFilter !== "images"
                    }
                }

                // Name and details
                Column {
                    width: parent.width - 62 * textScale
                    height: parent.height
                    spacing: 4 * textScale
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        width: parent.width
                        text: model.fileName
                        color: matchesFilter(model.fileName) || model.fileIsDir ? "#ffffff" : "#666677"
                        font.pixelSize: 14 * textScale
                        font.weight: Font.Medium
                        elide: Text.ElideRight
                    }

                    Row {
                        spacing: 12 * textScale

                        Text {
                            text: model.fileIsDir ? "Folder" : formatSize(model.fileSize)
                            color: "#888899"
                            font.pixelSize: 11 * textScale
                        }

                        Text {
                            text: formatDate(model.fileModified)
                            color: "#888899"
                            font.pixelSize: 11 * textScale
                        }
                    }
                }

                // Select indicator in picker mode
                Rectangle {
                    width: 36 * textScale
                    height: 36 * textScale
                    anchors.verticalCenter: parent.verticalCenter
                    radius: 18 * textScale
                    color: accentColor
                    visible: pickerMode && !model.fileIsDir && matchesFilter(model.fileName)

                    Text {
                        anchors.centerIn: parent
                        text: "✓"
                        font.pixelSize: 18 * textScale
                        color: "#ffffff"
                    }
                }
            }

            MouseArea {
                id: mouseArea
                anchors.fill: parent
                pressAndHoldInterval: 500

                onClicked: {
                    if (model.fileIsDir) {
                        navigateTo(model.filePath)
                    } else if (pickerMode) {
                        // In picker mode, select the file and return
                        if (matchesFilter(model.fileName)) {
                            pickFile(model.filePath)
                        }
                    } else {
                        openFile(model.filePath)
                    }
                }

                onPressAndHold: {
                    if (!pickerMode) {
                        showContextMenu(model.filePath, model.fileName, model.fileIsDir)
                    }
                }
            }
        }
    }

    // Empty state
    Text {
        anchors.centerIn: listView
        visible: folderModel.count === 0
        text: "Empty folder"
        color: "#888899"
        font.pixelSize: 14 * textScale
    }

    // Floating back button
    Rectangle {
        id: backButton
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 24
        anchors.bottomMargin: 120
        width: 72
        height: 72
        radius: 36
        color: backMouse.pressed ? accentPressed : accentColor
        z: 10

        Behavior on color { ColorAnimation { duration: 150 } }

        Text {
            anchors.centerIn: parent
            text: currentPath === "/" ? "✕" : "←"
            color: "#ffffff"
            font.pixelSize: 32
            font.weight: Font.Medium
        }

        MouseArea {
            id: backMouse
            anchors.fill: parent
            onClicked: goUp()
        }
    }

    // Home indicator bar
    Rectangle {
        id: homeIndicator
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottomMargin: 8 * textScale
        width: 120 * textScale
        height: 4 * textScale
        radius: 2 * textScale
        color: "#444466"
        z: 2
    }

    // Paste button (visible when clipboard has content)
    Rectangle {
        id: pasteButton
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.leftMargin: 24
        anchors.bottomMargin: 120
        width: 72
        height: 72
        radius: 36
        color: pasteMouse.pressed ? "#2a8a4a" : "#3ca55c"
        visible: clipboardPath !== ""
        z: 10

        Behavior on color { ColorAnimation { duration: 150 } }

        Text {
            anchors.centerIn: parent
            text: "📋"
            font.pixelSize: 28
        }

        MouseArea {
            id: pasteMouse
            anchors.fill: parent
            onClicked: pasteFile()
        }
    }

    // Context menu overlay
    Rectangle {
        id: contextMenu
        anchors.fill: parent
        color: "#80000000"
        visible: false
        z: 100

        MouseArea {
            anchors.fill: parent
            onClicked: contextMenu.visible = false
        }

        Rectangle {
            anchors.centerIn: parent
            width: 320
            height: menuColumn.height + 32
            radius: 20
            color: "#1a1a2e"
            border.color: "#333344"
            border.width: 1

            Column {
                id: menuColumn
                anchors.centerIn: parent
                width: parent.width - 32
                spacing: 4

                // Selected file name
                Text {
                    width: parent.width
                    text: selectedFile ? selectedFile.name : ""
                    color: "#aaaacc"
                    font.pixelSize: 14
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideMiddle
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: "#333344"
                }

                // Copy
                Rectangle {
                    width: parent.width
                    height: 56
                    radius: 12
                    color: copyMouse.pressed ? "#252538" : "transparent"

                    Row {
                        anchors.centerIn: parent
                        spacing: 12

                        Text {
                            text: "📄"
                            font.pixelSize: 20
                        }
                        Text {
                            text: "Copy"
                            color: "#ffffff"
                            font.pixelSize: 18
                        }
                    }

                    MouseArea {
                        id: copyMouse
                        anchors.fill: parent
                        onClicked: copyFile()
                    }
                }

                // Cut (Move)
                Rectangle {
                    width: parent.width
                    height: 56
                    radius: 12
                    color: cutMouse.pressed ? "#252538" : "transparent"

                    Row {
                        anchors.centerIn: parent
                        spacing: 12

                        Text {
                            text: "✂️"
                            font.pixelSize: 20
                        }
                        Text {
                            text: "Cut"
                            color: "#ffffff"
                            font.pixelSize: 18
                        }
                    }

                    MouseArea {
                        id: cutMouse
                        anchors.fill: parent
                        onClicked: cutFile()
                    }
                }

                // Rename
                Rectangle {
                    width: parent.width
                    height: 56
                    radius: 12
                    color: renameMouse.pressed ? "#252538" : "transparent"

                    Row {
                        anchors.centerIn: parent
                        spacing: 12

                        Text {
                            text: "✏️"
                            font.pixelSize: 20
                        }
                        Text {
                            text: "Rename"
                            color: "#ffffff"
                            font.pixelSize: 18
                        }
                    }

                    MouseArea {
                        id: renameMouse
                        anchors.fill: parent
                        onClicked: renameFile()
                    }
                }

                // Delete
                Rectangle {
                    width: parent.width
                    height: 56
                    radius: 12
                    color: deleteMouse.pressed ? "#3a1a1a" : "transparent"

                    Row {
                        anchors.centerIn: parent
                        spacing: 12

                        Text {
                            text: "🗑️"
                            font.pixelSize: 20
                        }
                        Text {
                            text: "Delete"
                            color: accentColor
                            font.pixelSize: 18
                        }
                    }

                    MouseArea {
                        id: deleteMouse
                        anchors.fill: parent
                        onClicked: deleteFile()
                    }
                }
            }
        }
    }

    // Rename dialog
    Rectangle {
        id: renameDialog
        anchors.fill: parent
        color: "#80000000"
        visible: false
        z: 101

        MouseArea {
            anchors.fill: parent
            onClicked: renameDialog.visible = false
        }

        Rectangle {
            anchors.centerIn: parent
            width: 360
            height: renameColumn.height + 32
            radius: 20
            color: "#1a1a2e"
            border.color: "#333344"
            border.width: 1

            Column {
                id: renameColumn
                anchors.centerIn: parent
                width: parent.width - 32
                spacing: 16

                Text {
                    text: "Rename"
                    color: "#ffffff"
                    font.pixelSize: 20
                    font.weight: Font.Medium
                }

                Rectangle {
                    width: parent.width
                    height: 50
                    radius: 12
                    color: "#0a0a0f"
                    border.color: renameInput.activeFocus ? accentColor : "#333344"
                    border.width: renameInput.activeFocus ? 2 : 1

                    TextInput {
                        id: renameInput
                        anchors.fill: parent
                        anchors.margins: 12
                        color: "#ffffff"
                        font.pixelSize: 16
                        verticalAlignment: TextInput.AlignVCenter
                        clip: true
                        selectByMouse: true
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: renameInput.forceActiveFocus()
                    }
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 16

                    Rectangle {
                        width: 120
                        height: 48
                        radius: 24
                        color: cancelMouse.pressed ? "#252538" : "#333344"

                        Text {
                            anchors.centerIn: parent
                            text: "Cancel"
                            color: "#ffffff"
                            font.pixelSize: 16
                        }

                        MouseArea {
                            id: cancelMouse
                            anchors.fill: parent
                            onClicked: renameDialog.visible = false
                        }
                    }

                    Rectangle {
                        width: 120
                        height: 48
                        radius: 24
                        color: confirmMouse.pressed ? accentPressed : accentColor

                        Text {
                            anchors.centerIn: parent
                            text: "Rename"
                            color: "#ffffff"
                            font.pixelSize: 16
                        }

                        MouseArea {
                            id: confirmMouse
                            anchors.fill: parent
                            onClicked: confirmRename()
                        }
                    }
                }
            }
        }
    }
}
