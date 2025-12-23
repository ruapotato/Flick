import QtQuick 2.15
import QtQuick.Window 2.15
import QtQuick.Controls 2.15
import Qt.labs.folderlistmodel 2.15

Window {
    id: root
    visible: true
    width: 1080
    height: 2400
    title: "Flick Files"
    color: "#0a0a0f"

    // Files uses fixed scaling
    property real textScale: 1.0
    property string currentPath: "/home/droidian"
    property color accentColor: "#e94560"

    Component.onCompleted: {
        loadConfig()
    }

    function loadConfig() {
        // Files uses fixed scaling - no config needed
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
            height: 70 * textScale
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

                // Icon
                Rectangle {
                    width: 40 * textScale
                    height: parent.height
                    color: "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: model.fileIsDir ? "\u{1F4C1}" : "\u{1F4C4}"
                        font.pixelSize: 24 * textScale
                    }
                }

                // Name and details
                Column {
                    width: parent.width - 52 * textScale
                    height: parent.height
                    spacing: 4 * textScale
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        width: parent.width
                        text: model.fileName
                        color: "#ffffff"
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
            }

            MouseArea {
                id: mouseArea
                anchors.fill: parent
                onClicked: {
                    if (model.fileIsDir) {
                        navigateTo(model.filePath)
                    } else {
                        openFile(model.filePath)
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
        anchors.bottom: homeIndicator.top
        anchors.rightMargin: 16 * textScale
        anchors.bottomMargin: 16 * textScale
        width: 72 * textScale
        height: 72 * textScale
        radius: 36 * textScale
        color: accentColor
        z: 3

        Text {
            anchors.centerIn: parent
            text: "\u{2190}"
            color: "#ffffff"
            font.pixelSize: 32 * textScale
            font.weight: Font.Bold
        }

        MouseArea {
            anchors.fill: parent
            onClicked: goUp()
        }

        // Shadow effect
        layer.enabled: true
        layer.effect: ShaderEffect {
            property color shadowColor: "#40000000"
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
}
