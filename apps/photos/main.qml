import QtQuick 2.15
import QtQuick.Window 2.15
import QtQuick.Controls 2.15
import Qt.labs.folderlistmodel 2.15

Window {
    id: root
    visible: true
    width: 1080
    height: 2400
    title: "Photos"
    color: "#0a0a0f"

    // Settings from Flick config
    property real textScale: 2.0
    property int baseFontSize: 8

    Component.onCompleted: {
        loadConfig()
    }

    function loadConfig() {
        // Try to read config from standard location (uses droidian home)
        var configPath = "/home/droidian/.local/state/flick/display_config.json"
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file://" + configPath, false)
        try {
            xhr.send()
            if (xhr.status === 200 || xhr.status === 0) {
                var config = JSON.parse(xhr.responseText)
                if (config.text_scale !== undefined) {
                    textScale = config.text_scale
                    console.log("Loaded text scale: " + textScale)
                }
            }
        } catch (e) {
            console.log("Using default text scale: " + textScale)
        }
    }

    // Reload config periodically to pick up settings changes
    Timer {
        interval: 3000
        running: true
        repeat: true
        onTriggered: loadConfig()
    }

    // Photo model combining both directories
    ListModel {
        id: photoModel

        Component.onCompleted: {
            loadPhotos()
        }

        function loadPhotos() {
            clear()

            // Load from ~/Pictures (using droidian home)
            var dirs = ["/home/droidian/Pictures", Qt.resolvedUrl("~/Pictures")]

            for (var d = 0; d < dirs.length; d++) {
                var dir = dirs[d]
                var xhr = new XMLHttpRequest()
                xhr.open("GET", "file://" + dir, false)
                try {
                    xhr.send()
                    console.log("Scanning directory: " + dir)
                } catch (e) {
                    console.log("Could not access: " + dir)
                }
            }
        }
    }

    // Folder model for loading photos
    FolderListModel {
        id: folderModel
        folder: "file:///home/droidian/Pictures"
        nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.gif", "*.bmp", "*.JPG", "*.JPEG", "*.PNG", "*.GIF", "*.BMP"]
        showDirs: false

        onCountChanged: {
            console.log("Found " + count + " photos in Pictures")
        }
    }

    StackView {
        id: stackView
        anchors.fill: parent
        initialItem: gridViewPage
    }

    // Grid view page
    Component {
        id: gridViewPage

        Item {
            // Title bar
            Rectangle {
                id: titleBar
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 56 * textScale
                color: "#1a1a2e"
                z: 10

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 20
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Photos"
                    color: "#ffffff"
                    font.pixelSize: 20 * textScale
                    font.weight: Font.Bold
                }

                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 20
                    anchors.verticalCenter: parent.verticalCenter
                    text: folderModel.count + " photos"
                    color: "#aaaacc"
                    font.pixelSize: 14 * textScale
                }
            }

            // Photo grid
            GridView {
                id: grid
                anchors.top: titleBar.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 100

                cellWidth: width / 3
                cellHeight: cellWidth

                model: folderModel
                clip: true

                delegate: Item {
                    width: grid.cellWidth
                    height: grid.cellHeight

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 2
                        color: "#1a1a2e"

                        Image {
                            id: thumbnail
                            anchors.fill: parent
                            anchors.margins: 4
                            source: model.fileURL
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: true

                            Rectangle {
                                anchors.fill: parent
                                color: "#0a0a0f"
                                visible: thumbnail.status === Image.Loading

                                BusyIndicator {
                                    anchors.centerIn: parent
                                    running: thumbnail.status === Image.Loading
                                    palette.dark: "#e94560"
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                stackView.push(fullScreenViewPage, {
                                    currentIndex: index
                                })
                            }
                        }
                    }
                }

                ScrollBar.vertical: ScrollBar {
                    width: 8
                    policy: ScrollBar.AsNeeded

                    contentItem: Rectangle {
                        color: "#e94560"
                        radius: width / 2
                        opacity: 0.8
                    }
                }
            }

            // Empty state
            Item {
                anchors.centerIn: parent
                visible: folderModel.count === 0

                Column {
                    anchors.centerIn: parent
                    spacing: 16

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "No Photos"
                        color: "#aaaacc"
                        font.pixelSize: 24 * textScale
                        font.weight: Font.Bold
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Add photos to ~/Pictures"
                        color: "#666677"
                        font.pixelSize: 14 * textScale
                    }
                }
            }

            // Home indicator bar
            Rectangle {
                id: homeIndicator
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottomMargin: 8
                width: 120
                height: 4
                radius: 2
                color: "#333344"
                z: 100
            }

            // Floating back button (close app from grid view)
            Rectangle {
                id: backButton
                anchors.bottom: parent.bottom
                anchors.right: parent.right
                anchors.bottomMargin: 30
                anchors.rightMargin: 30
                width: 72
                height: 72
                radius: 36
                color: "#e94560"
                z: 100

                Text {
                    anchors.centerIn: parent
                    text: "✕"
                    color: "#ffffff"
                    font.pixelSize: 32 * textScale
                    font.weight: Font.Bold
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: Qt.quit()
                }

                // Subtle shadow effect
                layer.enabled: true
                layer.effect: ShaderEffect {
                    property color shadowColor: "#80000000"
                }
            }
        }
    }

    // Full screen view page
    Component {
        id: fullScreenViewPage

        Item {
            id: fullScreenView
            property int currentIndex: 0

            Rectangle {
                anchors.fill: parent
                color: "#000000"
            }

            // Swipeable photo view
            ListView {
                id: photoList
                anchors.fill: parent
                orientation: ListView.Horizontal
                snapMode: ListView.SnapOneItem
                highlightRangeMode: ListView.StrictlyEnforceRange
                currentIndex: fullScreenView.currentIndex

                model: folderModel

                delegate: Item {
                    width: photoList.width
                    height: photoList.height

                    PinchArea {
                        id: pinchArea
                        anchors.fill: parent

                        property real initialScale: 1.0

                        onPinchStarted: {
                            initialScale = photoFlickable.contentWidth / photoImage.implicitWidth
                        }

                        onPinchUpdated: {
                            var newScale = initialScale * pinch.scale
                            newScale = Math.max(1.0, Math.min(newScale, 4.0))

                            photoFlickable.contentWidth = photoImage.implicitWidth * newScale
                            photoFlickable.contentHeight = photoImage.implicitHeight * newScale
                        }

                        onPinchFinished: {
                            photoFlickable.returnToBounds()
                        }

                        Flickable {
                            id: photoFlickable
                            anchors.fill: parent
                            contentWidth: photoImage.implicitWidth
                            contentHeight: photoImage.implicitHeight
                            boundsBehavior: Flickable.StopAtBounds
                            clip: true

                            Image {
                                id: photoImage
                                anchors.centerIn: parent
                                source: model.fileURL
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                                cache: true

                                width: {
                                    if (implicitWidth > 0 && implicitHeight > 0) {
                                        var ratio = implicitWidth / implicitHeight
                                        var viewRatio = photoFlickable.width / photoFlickable.height
                                        return ratio > viewRatio ? photoFlickable.width : photoFlickable.height * ratio
                                    }
                                    return photoFlickable.width
                                }

                                height: {
                                    if (implicitWidth > 0 && implicitHeight > 0) {
                                        var ratio = implicitWidth / implicitHeight
                                        var viewRatio = photoFlickable.width / photoFlickable.height
                                        return ratio > viewRatio ? photoFlickable.width / ratio : photoFlickable.height
                                    }
                                    return photoFlickable.height
                                }

                                Rectangle {
                                    anchors.fill: parent
                                    color: "#0a0a0f"
                                    visible: photoImage.status === Image.Loading

                                    BusyIndicator {
                                        anchors.centerIn: parent
                                        running: photoImage.status === Image.Loading
                                        palette.dark: "#e94560"
                                    }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                onDoubleClicked: {
                                    if (photoFlickable.contentWidth > photoImage.implicitWidth) {
                                        // Reset zoom
                                        photoFlickable.contentWidth = photoImage.implicitWidth
                                        photoFlickable.contentHeight = photoImage.implicitHeight
                                    } else {
                                        // Zoom to 2x
                                        photoFlickable.contentWidth = photoImage.implicitWidth * 2
                                        photoFlickable.contentHeight = photoImage.implicitHeight * 2
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Photo counter
            Rectangle {
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.topMargin: 20
                width: counterText.width + 32
                height: 40
                radius: 20
                color: "#80000000"
                z: 100

                Text {
                    id: counterText
                    anchors.centerIn: parent
                    text: (photoList.currentIndex + 1) + " / " + folderModel.count
                    color: "#ffffff"
                    font.pixelSize: 16 * textScale
                    font.weight: Font.Medium
                }
            }

            // Home indicator bar
            Rectangle {
                id: fullScreenHomeIndicator
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottomMargin: 8
                width: 120
                height: 4
                radius: 2
                color: "#333344"
                z: 100
            }

            // Floating back button (go back to grid)
            Rectangle {
                id: fullScreenBackButton
                anchors.bottom: parent.bottom
                anchors.right: parent.right
                anchors.bottomMargin: 30
                anchors.rightMargin: 30
                width: 72
                height: 72
                radius: 36
                color: "#e94560"
                z: 100

                Text {
                    anchors.centerIn: parent
                    text: "←"
                    color: "#ffffff"
                    font.pixelSize: 32 * textScale
                    font.weight: Font.Bold
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: stackView.pop()
                }

                // Subtle shadow effect
                layer.enabled: true
                layer.effect: ShaderEffect {
                    property color shadowColor: "#80000000"
                }
            }
        }
    }
}
