import QtQuick 2.15
import QtQuick.Window 2.15
import QtQuick.Controls 2.15
import Qt.labs.folderlistmodel 2.15
import "../shared"

Window {
    id: root
    visible: true
    width: 720
    height: 1600
    title: "Photos"
    color: "#0a0a0f"

    // Photos uses fixed scaling
    property real textScale: 1.0
    property color accentColor: Theme.accentColor
    property color accentPressed: Qt.darker(accentColor, 1.2)
    property int baseFontSize: 8

    function loadConfig() {
        // Photos uses fixed scaling - no config needed
    }

    // Combined photo model from all scanned directories
    ListModel {
        id: photoModel
    }

    // Track total photos found
    property int totalPhotos: 0

    // Base directories to scan for photos
    property var baseDirs: [
        Theme.homeDir + "/Pictures",
        Theme.homeDir + "/DCIM"
    ]

    // Discovered directories (including subfolders)
    property var allDirs: []

    // Active folder models
    property var folderModels: []

    Component.onCompleted: {
        loadConfig()
        scanDirectories()
    }

    // Scan for subdirectories
    function scanDirectories() {
        allDirs = []
        for (var i = 0; i < baseDirs.length; i++) {
            scanDirRecursive(baseDirs[i])
        }
        // Start scanning after a short delay
        scanTimer.start()
    }

    // Use folder model to find subdirectories
    FolderListModel {
        id: dirScanner
        showDirs: true
        showFiles: false
        showDotAndDotDot: false
    }

    function scanDirRecursive(path) {
        // Add this directory
        allDirs.push(path)
        console.log("Will scan: " + path)
    }

    Timer {
        id: scanTimer
        interval: 100
        onTriggered: {
            // Create folder models for each directory and scan for subdirs
            createFolderModels()
        }
    }

    function createFolderModels() {
        // Clear existing
        photoModel.clear()

        // Scan each base directory for subdirs, then scan for photos
        for (var i = 0; i < baseDirs.length; i++) {
            scanDirForPhotosAndSubdirs(baseDirs[i], 0)
        }

        // Rebuild after a delay to let all scans complete
        rebuildTimer.start()
    }

    Timer {
        id: rebuildTimer
        interval: 1000
        onTriggered: {
            totalPhotos = photoModel.count
            console.log("Total photos found: " + totalPhotos)
        }
    }

    function scanDirForPhotosAndSubdirs(dirPath, depth) {
        if (depth > 5) return  // Limit recursion depth

        // Create a model to scan this directory for photos
        var photoScanModel = Qt.createQmlObject('
            import QtQuick 2.15
            import Qt.labs.folderlistmodel 2.15
            FolderListModel {
                showDirs: false
                showFiles: true
                nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.gif", "*.bmp", "*.JPG", "*.JPEG", "*.PNG", "*.GIF", "*.BMP", "*.webp", "*.WEBP"]
            }
        ', root)

        photoScanModel.folder = "file://" + dirPath

        // Create a model to find subdirectories
        var dirScanModel = Qt.createQmlObject('
            import QtQuick 2.15
            import Qt.labs.folderlistmodel 2.15
            FolderListModel {
                showDirs: true
                showFiles: false
                showDotAndDotDot: false
            }
        ', root)

        dirScanModel.folder = "file://" + dirPath

        // Timer to wait for models to load
        var checkTimer = Qt.createQmlObject('import QtQuick 2.15; Timer { interval: 100; repeat: true }', root)
        var checkCount = 0

        checkTimer.triggered.connect(function() {
            checkCount++
            var photoReady = (photoScanModel.status === 2 || checkCount > 20)
            var dirReady = (dirScanModel.status === 2 || checkCount > 20)

            if (photoReady && dirReady) {
                checkTimer.stop()

                // Add photos from this directory
                for (var i = 0; i < photoScanModel.count; i++) {
                    var fileUrl = photoScanModel.get(i, "fileURL")
                    if (fileUrl) {
                        photoModel.append({
                            "fileURL": fileUrl.toString(),
                            "fileName": photoScanModel.get(i, "fileName"),
                            "filePath": photoScanModel.get(i, "filePath")
                        })
                    }
                }

                // Recursively scan subdirectories
                for (var j = 0; j < dirScanModel.count; j++) {
                    var subDirPath = dirScanModel.get(j, "filePath")
                    var subDirName = dirScanModel.get(j, "fileName")
                    if (subDirPath && subDirName && subDirName !== "." && subDirName !== "..") {
                        console.log("Found subdir: " + subDirPath)
                        scanDirForPhotosAndSubdirs(subDirPath, depth + 1)
                    }
                }

                // Update count
                totalPhotos = photoModel.count

                photoScanModel.destroy()
                dirScanModel.destroy()
                checkTimer.destroy()
            }
        })
        checkTimer.start()
    }

    // Legacy compatibility alias
    property alias folderModel: photoModel

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
                    text: totalPhotos + " photos"
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
                                    palette.dark: accentColor
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                Haptic.tap()
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
                        color: accentColor
                        radius: width / 2
                        opacity: 0.8
                    }
                }
            }

            // Empty state
            Item {
                anchors.centerIn: parent
                visible: totalPhotos === 0

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
                width: 48
                height: 48
                radius: 36
                color: closeBtnMouse.pressed ? accentPressed : accentColor
                z: 100

                Text {
                    anchors.centerIn: parent
                    text: "X"
                    color: "#ffffff"
                    font.pixelSize: 20
                    font.weight: Font.Bold
                }

                MouseArea {
                    id: closeBtnMouse
                    anchors.fill: parent
                    onClicked: {
                        Haptic.tap()
                        Qt.quit()
                    }
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
                            initialScale = photoFlickable.photoScale
                        }

                        onPinchUpdated: {
                            var newScale = initialScale * pinch.scale
                            photoFlickable.photoScale = Math.max(1.0, Math.min(newScale, 4.0))
                        }

                        onPinchFinished: {
                            photoFlickable.returnToBounds()
                        }

                        Flickable {
                            id: photoFlickable
                            anchors.fill: parent
                            contentWidth: width
                            contentHeight: height
                            boundsBehavior: Flickable.StopAtBounds
                            clip: true

                            property real photoScale: 1.0

                            Image {
                                id: photoImage
                                source: model.fileURL
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                                cache: true

                                // Calculate size to fit screen, then apply zoom scale
                                property real fitWidth: {
                                    if (implicitWidth > 0 && implicitHeight > 0) {
                                        var imgRatio = implicitWidth / implicitHeight
                                        var viewRatio = photoFlickable.width / photoFlickable.height
                                        return imgRatio > viewRatio ? photoFlickable.width : photoFlickable.height * imgRatio
                                    }
                                    return photoFlickable.width
                                }

                                property real fitHeight: {
                                    if (implicitWidth > 0 && implicitHeight > 0) {
                                        var imgRatio = implicitWidth / implicitHeight
                                        var viewRatio = photoFlickable.width / photoFlickable.height
                                        return imgRatio > viewRatio ? photoFlickable.width / imgRatio : photoFlickable.height
                                    }
                                    return photoFlickable.height
                                }

                                width: fitWidth * photoFlickable.photoScale
                                height: fitHeight * photoFlickable.photoScale

                                // Center in flickable when at 1x, top-left when zoomed
                                x: width > photoFlickable.width ? 0 : (photoFlickable.width - width) / 2
                                y: height > photoFlickable.height ? 0 : (photoFlickable.height - height) / 2

                                onWidthChanged: {
                                    photoFlickable.contentWidth = Math.max(width, photoFlickable.width)
                                }
                                onHeightChanged: {
                                    photoFlickable.contentHeight = Math.max(height, photoFlickable.height)
                                }

                                Rectangle {
                                    anchors.fill: parent
                                    color: "#0a0a0f"
                                    visible: photoImage.status === Image.Loading
                                    z: -1

                                    BusyIndicator {
                                        anchors.centerIn: parent
                                        running: photoImage.status === Image.Loading
                                        palette.dark: accentColor
                                    }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                onDoubleClicked: {
                                    if (photoFlickable.photoScale > 1.0) {
                                        // Reset zoom
                                        photoFlickable.photoScale = 1.0
                                    } else {
                                        // Zoom to 2x
                                        photoFlickable.photoScale = 2.0
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
                    text: (photoList.currentIndex + 1) + " / " + totalPhotos
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
                width: 48
                height: 48
                radius: 36
                color: backBtnMouse.pressed ? accentPressed : accentColor
                z: 100

                Text {
                    anchors.centerIn: parent
                    text: "<"
                    color: "#ffffff"
                    font.pixelSize: 24
                    font.weight: Font.Bold
                }

                MouseArea {
                    id: backBtnMouse
                    anchors.fill: parent
                    onClicked: {
                        Haptic.tap()
                        stackView.pop()
                    }
                }
            }
        }
    }
}
