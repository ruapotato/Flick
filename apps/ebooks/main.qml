import QtQuick 2.15
import QtQuick.Window 2.15
import QtQuick.Controls 2.15
import Qt.labs.folderlistmodel 2.15
import "../shared"

Window {
    id: root
    visible: true
    visibility: Window.FullScreen
    width: 1080
    height: 2400
    title: "Ebooks"
    color: "#0a0a0f"

    property real textScale: 1.0
    property var booksList: []
    property string currentView: "library" // "library", "reader"
    property var currentBook: null
    property int currentPage: 0
    property string bookContent: ""
    property var bookPages: []
    property real readerFontSize: 20

    // Reading positions storage
    property var readingPositions: ({})
    property string positionsFile: "/home/droidian/.local/state/flick/ebook_positions.json"

    // Library paths to scan
    property var libraryPaths: [
        "/home/droidian/Books",
        "/home/droidian/Documents",
        "/home/droidian/Downloads"
    ]

    Component.onCompleted: {
        loadTextScale()
        loadReadingPositions()
        scanBooks()
    }

    function loadTextScale() {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file:///home/droidian/.local/state/flick/display_config.json")
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200 || xhr.status === 0) {
                    try {
                        var config = JSON.parse(xhr.responseText)
                        textScale = config.text_scale || 1.0
                        readerFontSize = 20 * textScale
                    } catch (e) {
                        console.log("Failed to parse display config:", e)
                    }
                }
            }
        }
        xhr.send()
    }

    function loadReadingPositions() {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file://" + positionsFile)
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200 || xhr.status === 0) {
                    try {
                        readingPositions = JSON.parse(xhr.responseText)
                    } catch (e) {
                        readingPositions = {}
                    }
                }
            }
        }
        xhr.send()
    }

    function saveReadingPosition() {
        if (!currentBook) return

        readingPositions[currentBook.path] = {
            page: currentPage,
            fontSize: readerFontSize,
            timestamp: Date.now()
        }

        var xhr = new XMLHttpRequest()
        xhr.open("PUT", "file://" + positionsFile)
        xhr.send(JSON.stringify(readingPositions, null, 2))
    }

    function scanBooks() {
        booksList = []
        for (var i = 0; i < libraryPaths.length; i++) {
            scanFolder(libraryPaths[i])
        }
        booksListModel.sync()
    }

    function scanFolder(folderPath) {
        var scanModel = Qt.createQmlObject('
            import QtQuick 2.15
            import Qt.labs.folderlistmodel 2.15
            FolderListModel {
                showDirs: false
                showFiles: true
                nameFilters: ["*.txt", "*.epub", "*.TXT", "*.EPUB"]
            }
        ', root)

        scanModel.folder = "file://" + folderPath

        var checkTimer = Qt.createQmlObject('import QtQuick 2.15; Timer { interval: 100; repeat: true }', root)
        var checkCount = 0

        checkTimer.triggered.connect(function() {
            checkCount++
            if (scanModel.status === 2 || checkCount > 10) {
                checkTimer.stop()

                for (var i = 0; i < scanModel.count; i++) {
                    var fileName = scanModel.get(i, "fileName")
                    var filePath = scanModel.get(i, "filePath")
                    if (fileName) {
                        // Remove file extension for display
                        var displayName = fileName.replace(/\.(txt|epub|TXT|EPUB)$/, "")
                        booksList.push({
                            title: displayName,
                            path: filePath,
                            fileName: fileName
                        })
                    }
                }

                scanModel.destroy()
                checkTimer.destroy()
                booksListModel.sync()
            }
        })
        checkTimer.start()
    }

    ListModel {
        id: booksListModel

        function sync() {
            clear()
            // Sort books alphabetically
            booksList.sort(function(a, b) {
                return a.title.localeCompare(b.title)
            })
            for (var i = 0; i < booksList.length; i++) {
                append(booksList[i])
            }
        }
    }

    function openBook(book) {
        currentBook = book
        currentPage = 0

        // Load saved position
        if (readingPositions[book.path]) {
            currentPage = readingPositions[book.path].page || 0
            if (readingPositions[book.path].fontSize) {
                readerFontSize = readingPositions[book.path].fontSize
            }
        }

        loadBookContent(book.path)
    }

    function loadBookContent(filePath) {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file://" + filePath)
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200 || xhr.status === 0) {
                    bookContent = xhr.responseText
                    paginateBook()
                    currentView = "reader"
                } else {
                    console.log("Failed to load book:", xhr.status)
                }
            }
        }
        xhr.send()
    }

    function paginateBook() {
        // Simple pagination: split by paragraphs and fit to screen
        // This is a simplified version - a real implementation would be more sophisticated
        var paragraphs = bookContent.split(/\n\n+/)
        var pages = []
        var currentPageText = ""
        var linesPerPage = Math.floor((root.height - 300) / (readerFontSize * 1.5)) // Approximate lines per page
        var currentLines = 0

        for (var i = 0; i < paragraphs.length; i++) {
            var para = paragraphs[i].trim()
            if (!para) continue

            // Estimate lines in this paragraph (rough approximation)
            var charsPerLine = Math.floor((root.width - 64) / (readerFontSize * 0.6))
            var paraLines = Math.ceil(para.length / charsPerLine)

            if (currentLines + paraLines > linesPerPage && currentPageText) {
                // Start new page
                pages.push(currentPageText)
                currentPageText = para + "\n\n"
                currentLines = paraLines
            } else {
                currentPageText += para + "\n\n"
                currentLines += paraLines
            }
        }

        // Add last page
        if (currentPageText) {
            pages.push(currentPageText)
        }

        bookPages = pages

        // Ensure current page is valid
        if (currentPage >= pages.length) {
            currentPage = Math.max(0, pages.length - 1)
        }
    }

    function nextPage() {
        if (currentPage < bookPages.length - 1) {
            currentPage++
            saveReadingPosition()
            Haptic.tap()
        }
    }

    function prevPage() {
        if (currentPage > 0) {
            currentPage--
            saveReadingPosition()
            Haptic.tap()
        }
    }

    function increaseFontSize() {
        readerFontSize = Math.min(readerFontSize + 2, 40)
        paginateBook()
        saveReadingPosition()
    }

    function decreaseFontSize() {
        readerFontSize = Math.max(readerFontSize - 2, 14)
        paginateBook()
        saveReadingPosition()
    }

    // Library View
    Item {
        anchors.fill: parent
        visible: currentView === "library"

        // Header
        Rectangle {
            id: libraryHeader
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 220
            color: "transparent"

            // Ambient glow
            Rectangle {
                anchors.centerIn: parent
                width: 300
                height: 200
                radius: 150
                color: "#e94560"
                opacity: 0.08

                NumberAnimation on opacity {
                    from: 0.05
                    to: 0.12
                    duration: 3000
                    loops: Animation.Infinite
                    easing.type: Easing.InOutSine
                }
            }

            Column {
                anchors.centerIn: parent
                spacing: 12

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Ebooks"
                    font.pixelSize: 52 * textScale
                    font.weight: Font.ExtraLight
                    font.letterSpacing: 8
                    color: "#ffffff"
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "YOUR LIBRARY"
                    font.pixelSize: 14 * textScale
                    font.weight: Font.Medium
                    font.letterSpacing: 4
                    color: "#555566"
                }
            }

            Rectangle {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                height: 1
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.2; color: "#e94560" }
                    GradientStop { position: 0.8; color: "#e94560" }
                    GradientStop { position: 1.0; color: "transparent" }
                }
                opacity: 0.3
            }
        }

        // Books list
        ListView {
            id: booksListView
            anchors.top: libraryHeader.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 16
            anchors.bottomMargin: 100
            spacing: 16
            clip: true

            model: booksListModel

            delegate: Rectangle {
                width: booksListView.width
                height: 120
                radius: 16
                color: "#151520"
                border.color: bookMouse.pressed ? "#e94560" : "#333344"
                border.width: 2

                Behavior on border.color { ColorAnimation { duration: 150 } }

                Row {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 16

                    // Book icon
                    Rectangle {
                        width: 88
                        height: 88
                        radius: 12
                        color: "#e94560"
                        opacity: 0.3

                        Text {
                            anchors.centerIn: parent
                            text: "📖"
                            font.pixelSize: 48
                        }
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8
                        width: parent.width - 104 - 32

                        Text {
                            text: model.title
                            font.pixelSize: 24 * textScale
                            font.weight: Font.Medium
                            color: "#ffffff"
                            elide: Text.ElideRight
                            width: parent.width
                        }

                        Text {
                            text: model.fileName
                            font.pixelSize: 14 * textScale
                            color: "#888899"
                            elide: Text.ElideRight
                            width: parent.width
                        }

                        // Reading progress indicator
                        Row {
                            spacing: 8
                            visible: readingPositions[model.path] !== undefined

                            Rectangle {
                                width: 4
                                height: 4
                                radius: 2
                                color: "#e94560"
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Text {
                                text: {
                                    if (readingPositions[model.path]) {
                                        return "Page " + (readingPositions[model.path].page + 1)
                                    }
                                    return ""
                                }
                                font.pixelSize: 14 * textScale
                                color: "#e94560"
                            }
                        }
                    }
                }

                MouseArea {
                    id: bookMouse
                    anchors.fill: parent
                    onClicked: {
                        Haptic.tap()
                        openBook(booksList[index])
                    }
                }
            }
        }

        // Empty state
        Column {
            anchors.centerIn: parent
            spacing: 24
            visible: booksListModel.count === 0

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "📚"
                font.pixelSize: 96
                opacity: 0.3
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "No ebooks found"
                font.pixelSize: 24 * textScale
                color: "#555566"
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Place .txt or .epub files in:\n~/Books\n~/Documents\n~/Downloads"
                font.pixelSize: 16 * textScale
                color: "#888899"
                horizontalAlignment: Text.AlignHCenter
                lineHeight: 1.5
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
            color: libraryBackMouse.pressed ? "#c23a50" : "#e94560"

            Behavior on color { ColorAnimation { duration: 150 } }

            Text {
                anchors.centerIn: parent
                text: "←"
                font.pixelSize: 32
                font.weight: Font.Medium
                color: "#ffffff"
            }

            MouseArea {
                id: libraryBackMouse
                anchors.fill: parent
                onClicked: {
                    Haptic.tap()
                    Qt.quit()
                }
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

    // Reader View
    Item {
        anchors.fill: parent
        visible: currentView === "reader"

        // Header with book title
        Rectangle {
            id: readerHeader
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 100
            color: "#0a0a0f"
            z: 10

            Column {
                anchors.centerIn: parent
                spacing: 4

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: currentBook ? currentBook.title : ""
                    font.pixelSize: 20 * textScale
                    font.weight: Font.Medium
                    color: "#ffffff"
                    elide: Text.ElideRight
                    width: root.width - 32
                    horizontalAlignment: Text.AlignHCenter
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Page " + (currentPage + 1) + " of " + bookPages.length
                    font.pixelSize: 14 * textScale
                    color: "#888899"
                }
            }

            Rectangle {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                height: 1
                color: "#333344"
                opacity: 0.5
            }
        }

        // Reading area with touch zones
        Item {
            anchors.top: readerHeader.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: readerFooter.top
            clip: true

            // Book content
            Flickable {
                id: contentFlickable
                anchors.fill: parent
                anchors.margins: 32
                contentHeight: contentText.height
                clip: true

                Text {
                    id: contentText
                    width: parent.width
                    text: bookPages[currentPage] || ""
                    font.pixelSize: readerFontSize
                    color: "#e8e8f0"
                    wrapMode: Text.WordWrap
                    lineHeight: 1.5
                }
            }

            // Left tap zone (previous page)
            MouseArea {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: parent.width / 3
                onClicked: prevPage()
            }

            // Right tap zone (next page)
            MouseArea {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: parent.width / 3
                onClicked: nextPage()
            }

            // Swipe gestures
            property real swipeStartX: 0

            MouseArea {
                anchors.centerIn: parent
                width: parent.width / 3
                height: parent.height

                onPressed: {
                    parent.swipeStartX = mouseX
                }

                onReleased: {
                    var swipeDelta = mouseX - parent.swipeStartX
                    if (Math.abs(swipeDelta) > 100) {
                        if (swipeDelta > 0) {
                            prevPage()
                        } else {
                            nextPage()
                        }
                    }
                }
            }
        }

        // Footer with controls
        Rectangle {
            id: readerFooter
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 100
            height: 120
            color: "#151520"

            Row {
                anchors.centerIn: parent
                spacing: 24

                // Decrease font
                Rectangle {
                    width: 56
                    height: 56
                    radius: 28
                    color: fontMinusMouse.pressed ? "#333344" : "#252530"

                    Text {
                        anchors.centerIn: parent
                        text: "A-"
                        font.pixelSize: 18 * textScale
                        font.weight: Font.Bold
                        color: "#ffffff"
                    }

                    MouseArea {
                        id: fontMinusMouse
                        anchors.fill: parent
                        onClicked: {
                            Haptic.tap()
                            decreaseFontSize()
                        }
                    }
                }

                // Font size display
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Math.round(readerFontSize) + "pt"
                    font.pixelSize: 16 * textScale
                    color: "#888899"
                }

                // Increase font
                Rectangle {
                    width: 56
                    height: 56
                    radius: 28
                    color: fontPlusMouse.pressed ? "#333344" : "#252530"

                    Text {
                        anchors.centerIn: parent
                        text: "A+"
                        font.pixelSize: 18 * textScale
                        font.weight: Font.Bold
                        color: "#ffffff"
                    }

                    MouseArea {
                        id: fontPlusMouse
                        anchors.fill: parent
                        onClicked: {
                            Haptic.tap()
                            increaseFontSize()
                        }
                    }
                }

                // Separator
                Rectangle {
                    width: 1
                    height: 40
                    color: "#333344"
                    anchors.verticalCenter: parent.verticalCenter
                }

                // Previous page
                Rectangle {
                    width: 56
                    height: 56
                    radius: 28
                    color: prevPageMouse.pressed ? "#333344" : "#252530"
                    opacity: currentPage > 0 ? 1.0 : 0.3

                    Text {
                        anchors.centerIn: parent
                        text: "◀"
                        font.pixelSize: 24
                        color: "#ffffff"
                    }

                    MouseArea {
                        id: prevPageMouse
                        anchors.fill: parent
                        enabled: currentPage > 0
                        onClicked: prevPage()
                    }
                }

                // Next page
                Rectangle {
                    width: 56
                    height: 56
                    radius: 28
                    color: nextPageMouse.pressed ? "#333344" : "#252530"
                    opacity: currentPage < bookPages.length - 1 ? 1.0 : 0.3

                    Text {
                        anchors.centerIn: parent
                        text: "▶"
                        font.pixelSize: 24
                        color: "#ffffff"
                    }

                    MouseArea {
                        id: nextPageMouse
                        anchors.fill: parent
                        enabled: currentPage < bookPages.length - 1
                        onClicked: nextPage()
                    }
                }
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
            color: readerBackMouse.pressed ? "#c23a50" : "#e94560"
            z: 10

            Behavior on color { ColorAnimation { duration: 150 } }

            Text {
                anchors.centerIn: parent
                text: "←"
                font.pixelSize: 32
                font.weight: Font.Medium
                color: "#ffffff"
            }

            MouseArea {
                id: readerBackMouse
                anchors.fill: parent
                onClicked: {
                    Haptic.tap()
                    saveReadingPosition()
                    currentView = "library"
                }
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
}
