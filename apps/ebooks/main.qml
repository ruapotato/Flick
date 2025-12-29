import QtQuick 2.15
import QtQuick.Window 2.15
import QtQuick.Controls 2.15
import Qt.labs.folderlistmodel 2.15
import QtWebEngine 1.10
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
    property color accentColor: Theme.accentColor
    property color accentPressed: Qt.darker(accentColor, 1.2)
    property var booksList: []
    property string currentView: "library" // "library", "reader", "chapters"
    property var currentBook: null
    property int currentChapter: 0
    property var epubData: null
    property bool isEpub: false

    // For txt files
    property string bookContent: ""
    property var bookPages: []
    property int currentPage: 0
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

    // Auto-refresh library every 3 seconds to pick up new books
    Timer {
        interval: 3000
        running: currentView === "library"
        repeat: true
        onTriggered: scanBooks()
    }

    function loadTextScale() {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file:///home/droidian/.local/state/flick/display_config.json", false)
        try {
            xhr.send()
            if (xhr.status === 200 || xhr.status === 0) {
                var config = JSON.parse(xhr.responseText)
                textScale = config.text_scale || 1.0
                readerFontSize = 20 * textScale
            }
        } catch (e) {}
    }

    function loadReadingPositions() {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file://" + positionsFile, false)
        try {
            xhr.send()
            if (xhr.status === 200 || xhr.status === 0) {
                readingPositions = JSON.parse(xhr.responseText)
            }
        } catch (e) {
            readingPositions = {}
        }
    }

    function saveReadingPosition() {
        if (!currentBook) return

        if (isEpub) {
            readingPositions[currentBook.path] = {
                chapter: currentChapter,
                timestamp: Date.now()
            }
        } else {
            readingPositions[currentBook.path] = {
                page: currentPage,
                fontSize: readerFontSize,
                timestamp: Date.now()
            }
        }

        var xhr = new XMLHttpRequest()
        xhr.open("PUT", "file://" + positionsFile, false)
        try {
            xhr.send(JSON.stringify(readingPositions, null, 2))
        } catch (e) {}
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
                        var isEpubFile = fileName.toLowerCase().endsWith(".epub")
                        var displayName = fileName.replace(/\.(txt|epub|TXT|EPUB)$/, "").replace(/_/g, " ")
                        booksList.push({
                            title: displayName,
                            path: filePath,
                            fileName: fileName,
                            isEpub: isEpubFile
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
        isEpub = book.isEpub

        if (isEpub) {
            openEpub(book.path)
        } else {
            currentPage = 0
            if (readingPositions[book.path]) {
                currentPage = readingPositions[book.path].page || 0
                if (readingPositions[book.path].fontSize) {
                    readerFontSize = readingPositions[book.path].fontSize
                }
            }
            loadTxtContent(book.path)
        }
    }

    function openEpub(filePath) {
        // Read pre-extracted JSON (extracted by run script on launch)
        var bookHash = Qt.md5(filePath)
        var jsonFile = "/tmp/flick_epub_" + bookHash + ".json"

        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file://" + jsonFile, false)
        try {
            xhr.send()
            if (xhr.status === 200 || xhr.status === 0) {
                epubData = JSON.parse(xhr.responseText)
                if (epubData.chapters && epubData.chapters.length > 0) {
                    currentChapter = 0
                    if (readingPositions[currentBook.path]) {
                        currentChapter = readingPositions[currentBook.path].chapter || 0
                    }
                    if (currentChapter >= epubData.chapters.length) {
                        currentChapter = 0
                    }
                    loadEpubChapter(currentChapter)
                    currentView = "reader"
                } else {
                    console.log("No chapters found in epub")
                }
            } else {
                console.log("Failed to load epub JSON:", xhr.status)
            }
        } catch (e) {
            console.log("Failed to open epub:", e)
        }
    }

    function loadEpubChapter(index) {
        if (!epubData || !epubData.chapters || index >= epubData.chapters.length) return
        currentChapter = index
        var chapter = epubData.chapters[index]
        epubWebView.url = "file://" + chapter.path
        saveReadingPosition()
    }

    function nextChapter() {
        if (epubData && currentChapter < epubData.chapters.length - 1) {
            loadEpubChapter(currentChapter + 1)
            Haptic.tap()
        }
    }

    function prevChapter() {
        if (currentChapter > 0) {
            loadEpubChapter(currentChapter - 1)
            Haptic.tap()
        }
    }

    function loadTxtContent(filePath) {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file://" + filePath, false)
        try {
            xhr.send()
            if (xhr.status === 200 || xhr.status === 0) {
                bookContent = xhr.responseText
                paginateBook()
                currentView = "reader"
            }
        } catch (e) {
            console.log("Failed to load book:", e)
        }
    }

    function paginateBook() {
        var paragraphs = bookContent.split(/\n\n+/)
        var pages = []
        var currentPageText = ""
        var linesPerPage = Math.floor((root.height - 300) / (readerFontSize * 1.5))
        var currentLines = 0

        for (var i = 0; i < paragraphs.length; i++) {
            var para = paragraphs[i].trim()
            if (!para) continue

            var charsPerLine = Math.floor((root.width - 64) / (readerFontSize * 0.6))
            var paraLines = Math.ceil(para.length / charsPerLine)

            if (currentLines + paraLines > linesPerPage && currentPageText) {
                pages.push(currentPageText)
                currentPageText = para + "\n\n"
                currentLines = paraLines
            } else {
                currentPageText += para + "\n\n"
                currentLines += paraLines
            }
        }

        if (currentPageText) {
            pages.push(currentPageText)
        }

        bookPages = pages
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

    // Custom CSS for epub display
    property string epubCss: "
        body {
            background-color: #0a0a0f !important;
            color: #e8e8f0 !important;
            font-family: serif !important;
            font-size: " + readerFontSize + "px !important;
            line-height: 1.6 !important;
            padding: 20px !important;
            margin: 0 !important;
        }
        * {
            background-color: transparent !important;
            color: inherit !important;
        }
        a { color: " + accentColor + " !important; }
        img { max-width: 100% !important; height: auto !important; }
        h1, h2, h3, h4, h5, h6 {
            color: #ffffff !important;
            margin-top: 1em !important;
        }
    "

    // Library View
    Item {
        anchors.fill: parent
        visible: currentView === "library"

        Rectangle {
            id: libraryHeader
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 220
            color: "transparent"

            Rectangle {
                anchors.centerIn: parent
                width: 300
                height: 200
                radius: 150
                color: accentColor
                opacity: 0.08
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
                    text: booksList.length + " BOOKS"
                    font.pixelSize: 14 * textScale
                    font.weight: Font.Medium
                    font.letterSpacing: 4
                    color: "#555566"
                }
            }

            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.2; color: accentColor }
                    GradientStop { position: 0.8; color: accentColor }
                    GradientStop { position: 1.0; color: "transparent" }
                }
                opacity: 0.3
            }
        }

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
                border.color: bookMouse.pressed ? accentColor : "#333344"
                border.width: 2

                Row {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 16

                    Rectangle {
                        width: 88
                        height: 88
                        radius: 12
                        color: model.isEpub ? "#4a9eff" : accentColor
                        opacity: 0.3

                        Text {
                            anchors.centerIn: parent
                            text: model.isEpub ? "📚" : "📄"
                            font.pixelSize: 48
                        }
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8
                        width: parent.width - 120

                        Text {
                            text: model.title
                            font.pixelSize: 22 * textScale
                            font.weight: Font.Medium
                            color: "#ffffff"
                            elide: Text.ElideRight
                            width: parent.width
                        }

                        Text {
                            text: model.isEpub ? "EPUB" : "TXT"
                            font.pixelSize: 14 * textScale
                            color: model.isEpub ? "#4a9eff" : "#888899"
                            font.weight: Font.Medium
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
                text: "Place .epub or .txt files in:\n~/Books\n~/Documents\n~/Downloads"
                font.pixelSize: 16 * textScale
                color: "#888899"
                horizontalAlignment: Text.AlignHCenter
            }
        }

        Rectangle {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.rightMargin: 24
            anchors.bottomMargin: 120
            width: 72
            height: 72
            radius: 36
            color: libraryBackMouse.pressed ? accentPressed : accentColor

            Text {
                anchors.centerIn: parent
                text: "←"
                font.pixelSize: 32
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
    }

    // EPUB Reader View
    Item {
        anchors.fill: parent
        visible: currentView === "reader" && isEpub

        Rectangle {
            id: epubHeader
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 100
            color: "#0a0a0f"
            z: 10

            Row {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 16

                Rectangle {
                    width: 56
                    height: 56
                    radius: 28
                    color: tocMouse.pressed ? "#333344" : "#222233"
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        anchors.centerIn: parent
                        text: "≡"
                        font.pixelSize: 28
                        color: "#ffffff"
                    }

                    MouseArea {
                        id: tocMouse
                        anchors.fill: parent
                        onClicked: {
                            Haptic.tap()
                            currentView = "chapters"
                        }
                    }
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 150

                    Text {
                        text: currentBook ? currentBook.title : ""
                        font.pixelSize: 18 * textScale
                        font.weight: Font.Medium
                        color: "#ffffff"
                        elide: Text.ElideRight
                        width: parent.width
                    }

                    Text {
                        text: epubData && epubData.chapters ? "Chapter " + (currentChapter + 1) + " of " + epubData.chapters.length : ""
                        font.pixelSize: 14 * textScale
                        color: "#888899"
                    }
                }
            }

            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1
                color: "#333344"
                opacity: 0.5
            }
        }

        WebEngineView {
            id: epubWebView
            anchors.top: epubHeader.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: epubFooter.top
            backgroundColor: "#0a0a0f"

            onLoadingChanged: function(loadRequest) {
                if (loadRequest.status === WebEngineLoadRequest.LoadSucceededStatus) {
                    // Inject custom CSS for dark mode
                    runJavaScript("
                        var style = document.createElement('style');
                        style.textContent = `" + epubCss + "`;
                        document.head.appendChild(style);
                    ")
                }
            }

            settings.javascriptEnabled: true
            settings.localContentCanAccessFileUrls: true
            settings.localContentCanAccessRemoteUrls: false
        }

        // Touch zones for page navigation
        MouseArea {
            anchors.left: parent.left
            anchors.top: epubHeader.bottom
            anchors.bottom: epubFooter.top
            width: parent.width / 4
            onClicked: prevChapter()
        }

        MouseArea {
            anchors.right: parent.right
            anchors.top: epubHeader.bottom
            anchors.bottom: epubFooter.top
            width: parent.width / 4
            onClicked: nextChapter()
        }

        Rectangle {
            id: epubFooter
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 40
            height: 80
            color: "#151520"

            Row {
                anchors.centerIn: parent
                spacing: 32

                Rectangle {
                    width: 56
                    height: 56
                    radius: 28
                    color: prevChMouse.pressed ? "#333344" : "#252530"
                    opacity: currentChapter > 0 ? 1.0 : 0.3

                    Text {
                        anchors.centerIn: parent
                        text: "◀"
                        font.pixelSize: 24
                        color: "#ffffff"
                    }

                    MouseArea {
                        id: prevChMouse
                        anchors.fill: parent
                        enabled: currentChapter > 0
                        onClicked: prevChapter()
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: epubData && epubData.chapters ? (currentChapter + 1) + " / " + epubData.chapters.length : ""
                    font.pixelSize: 18 * textScale
                    color: "#888899"
                }

                Rectangle {
                    width: 56
                    height: 56
                    radius: 28
                    color: nextChMouse.pressed ? "#333344" : "#252530"
                    opacity: epubData && currentChapter < epubData.chapters.length - 1 ? 1.0 : 0.3

                    Text {
                        anchors.centerIn: parent
                        text: "▶"
                        font.pixelSize: 24
                        color: "#ffffff"
                    }

                    MouseArea {
                        id: nextChMouse
                        anchors.fill: parent
                        enabled: epubData && currentChapter < epubData.chapters.length - 1
                        onClicked: nextChapter()
                    }
                }
            }
        }

        Rectangle {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.rightMargin: 24
            anchors.bottomMargin: 140
            width: 72
            height: 72
            radius: 36
            color: epubBackMouse.pressed ? accentPressed : accentColor
            z: 10

            Text {
                anchors.centerIn: parent
                text: "←"
                font.pixelSize: 32
                color: "#ffffff"
            }

            MouseArea {
                id: epubBackMouse
                anchors.fill: parent
                onClicked: {
                    Haptic.tap()
                    saveReadingPosition()
                    currentView = "library"
                }
            }
        }
    }

    // Chapter List View
    Item {
        anchors.fill: parent
        visible: currentView === "chapters"

        Rectangle {
            anchors.fill: parent
            color: "#0a0a0f"
        }

        Rectangle {
            id: chaptersHeader
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 100
            color: "#0a0a0f"

            Row {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 16

                Rectangle {
                    width: 56
                    height: 56
                    radius: 28
                    color: chapBackMouse.pressed ? "#333344" : "#222233"
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        anchors.centerIn: parent
                        text: "←"
                        font.pixelSize: 28
                        color: "#ffffff"
                    }

                    MouseArea {
                        id: chapBackMouse
                        anchors.fill: parent
                        onClicked: {
                            Haptic.tap()
                            currentView = "reader"
                        }
                    }
                }

                Text {
                    text: "Chapters"
                    font.pixelSize: 24 * textScale
                    font.weight: Font.Medium
                    color: "#ffffff"
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }

        ListView {
            anchors.top: chaptersHeader.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 16
            spacing: 8
            clip: true

            model: epubData ? epubData.chapters : []

            delegate: Rectangle {
                width: parent ? parent.width : 0
                height: 72
                radius: 12
                color: index === currentChapter ? accentColor : (chapterMouse.pressed ? "#252530" : "#151520")
                opacity: index === currentChapter ? 0.3 : 1.0
                border.color: index === currentChapter ? accentColor : "transparent"
                border.width: 2

                Text {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: 20
                    text: (index + 1) + ". " + modelData.title
                    font.pixelSize: 18 * textScale
                    color: "#ffffff"
                    elide: Text.ElideRight
                }

                MouseArea {
                    id: chapterMouse
                    anchors.fill: parent
                    onClicked: {
                        Haptic.tap()
                        loadEpubChapter(index)
                        currentView = "reader"
                    }
                }
            }
        }
    }

    // TXT Reader View (unchanged from before)
    Item {
        anchors.fill: parent
        visible: currentView === "reader" && !isEpub

        Rectangle {
            id: txtHeader
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
        }

        Item {
            anchors.top: txtHeader.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: txtFooter.top
            clip: true

            Flickable {
                anchors.fill: parent
                anchors.margins: 32
                contentHeight: txtContent.height
                clip: true

                Text {
                    id: txtContent
                    width: parent.width
                    text: bookPages[currentPage] || ""
                    font.pixelSize: readerFontSize
                    color: "#e8e8f0"
                    wrapMode: Text.WordWrap
                    lineHeight: 1.5
                }
            }

            MouseArea {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: parent.width / 3
                onClicked: prevPage()
            }

            MouseArea {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: parent.width / 3
                onClicked: nextPage()
            }
        }

        Rectangle {
            id: txtFooter
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 40
            height: 80
            color: "#151520"

            Row {
                anchors.centerIn: parent
                spacing: 24

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

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: (currentPage + 1) + " / " + bookPages.length
                    font.pixelSize: 18 * textScale
                    color: "#888899"
                }

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

        Rectangle {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.rightMargin: 24
            anchors.bottomMargin: 140
            width: 72
            height: 72
            radius: 36
            color: txtBackMouse.pressed ? accentPressed : accentColor
            z: 10

            Text {
                anchors.centerIn: parent
                text: "←"
                font.pixelSize: 32
                color: "#ffffff"
            }

            MouseArea {
                id: txtBackMouse
                anchors.fill: parent
                onClicked: {
                    Haptic.tap()
                    saveReadingPosition()
                    currentView = "library"
                }
            }
        }
    }
}
