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
    property color accentColor: Theme.accentColor
    property var booksList: []
    property string currentView: "library"
    property var currentBook: null
    property string bookContent: ""
    property var bookPages: []
    property int currentPage: 0
    property real fontSize: 20
    property var positions: ({})
    property string positionsFile: "/home/droidian/.local/state/flick/ebook_positions.json"

    Component.onCompleted: {
        loadConfig()
        loadPositions()
        scanBooks()
    }

    function loadConfig() {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file:///home/droidian/.local/state/flick/display_config.json", false)
        try {
            xhr.send()
            if (xhr.status === 200 || xhr.status === 0) {
                var c = JSON.parse(xhr.responseText)
                textScale = c.text_scale || 1.0
                fontSize = 20 * textScale
            }
        } catch (e) {}
    }

    function loadPositions() {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file://" + positionsFile, false)
        try {
            xhr.send()
            if (xhr.status === 200 || xhr.status === 0) {
                positions = JSON.parse(xhr.responseText)
            }
        } catch (e) { positions = {} }
    }

    function savePosition() {
        if (!currentBook) return
        positions[currentBook.path] = { page: currentPage, fontSize: fontSize }
        var xhr = new XMLHttpRequest()
        xhr.open("PUT", "file://" + positionsFile, false)
        try { xhr.send(JSON.stringify(positions)) } catch (e) {}
    }

    function scanBooks() {
        booksList = []
        scanFolder("/home/droidian/Books")
        scanFolder("/home/droidian/Documents")
        scanFolder("/home/droidian/Downloads")
    }

    function scanFolder(path) {
        var model = Qt.createQmlObject('
            import QtQuick 2.15
            import Qt.labs.folderlistmodel 2.15
            FolderListModel { showDirs: false; nameFilters: ["*.txt"] }
        ', root)
        model.folder = "file://" + path

        var timer = Qt.createQmlObject('import QtQuick 2.15; Timer { interval: 100; repeat: true }', root)
        var count = 0
        timer.triggered.connect(function() {
            count++
            if (model.status === 2 || count > 10) {
                timer.stop()
                for (var i = 0; i < model.count; i++) {
                    var name = model.get(i, "fileName")
                    var fpath = model.get(i, "filePath")
                    if (name) {
                        booksList.push({
                            title: name.replace(/\.txt$/i, "").replace(/_/g, " "),
                            path: fpath,
                            fileName: name
                        })
                    }
                }
                model.destroy()
                timer.destroy()
                booksModel.sync()
            }
        })
        timer.start()
    }

    ListModel {
        id: booksModel
        function sync() {
            clear()
            booksList.sort(function(a,b) { return a.title.localeCompare(b.title) })
            for (var i = 0; i < booksList.length; i++) append(booksList[i])
        }
    }

    function openBook(book) {
        currentBook = book
        currentPage = 0
        if (positions[book.path]) {
            currentPage = positions[book.path].page || 0
            fontSize = positions[book.path].fontSize || fontSize
        }

        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file://" + book.path, false)
        try {
            xhr.send()
            if (xhr.status === 200 || xhr.status === 0) {
                bookContent = xhr.responseText
                paginate()
                currentView = "reader"
            }
        } catch (e) {}
    }

    function paginate() {
        var paras = bookContent.split(/\n\n+/)
        var pages = []
        var page = ""
        var lines = 0
        var maxLines = Math.floor((root.height - 280) / (fontSize * 1.6))

        for (var i = 0; i < paras.length; i++) {
            var p = paras[i].trim()
            if (!p) continue
            var pLines = Math.ceil(p.length / Math.floor((root.width - 64) / (fontSize * 0.55)))
            if (lines + pLines > maxLines && page) {
                pages.push(page)
                page = p + "\n\n"
                lines = pLines
            } else {
                page += p + "\n\n"
                lines += pLines
            }
        }
        if (page) pages.push(page)
        bookPages = pages
        if (currentPage >= pages.length) currentPage = Math.max(0, pages.length - 1)
    }

    function nextPage() {
        if (currentPage < bookPages.length - 1) {
            currentPage++
            savePosition()
            Haptic.tap()
        }
    }

    function prevPage() {
        if (currentPage > 0) {
            currentPage--
            savePosition()
            Haptic.tap()
        }
    }

    // Library
    Item {
        anchors.fill: parent
        visible: currentView === "library"

        Column {
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.topMargin: 60
            spacing: 8

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Ebooks"
                font.pixelSize: 48 * textScale
                font.weight: Font.Light
                color: "#ffffff"
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: booksModel.count + " books"
                font.pixelSize: 16 * textScale
                color: "#666677"
            }
        }

        ListView {
            anchors.fill: parent
            anchors.topMargin: 180
            anchors.bottomMargin: 100
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            spacing: 12
            clip: true
            model: booksModel

            delegate: Rectangle {
                width: parent ? parent.width : 0
                height: 100
                radius: 16
                color: ma.pressed ? "#252530" : "#151520"

                Row {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 16

                    Rectangle {
                        width: 68
                        height: 68
                        radius: 12
                        color: accentColor
                        opacity: 0.2

                        Text {
                            anchors.centerIn: parent
                            text: "📖"
                            font.pixelSize: 32
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 100
                        text: model.title
                        font.pixelSize: 20 * textScale
                        color: "#ffffff"
                        elide: Text.ElideRight
                    }
                }

                MouseArea {
                    id: ma
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
            spacing: 16
            visible: booksModel.count === 0

            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "📚"; font.pixelSize: 72; opacity: 0.3 }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "No ebooks found"; font.pixelSize: 20 * textScale; color: "#666677" }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Add .epub or .txt to ~/Books"; font.pixelSize: 16 * textScale; color: "#555566" }
        }

        // Back
        Rectangle {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 24
            anchors.bottomMargin: 100
            width: 64; height: 64; radius: 32
            color: backMa.pressed ? Qt.darker(accentColor, 1.2) : accentColor

            Text { anchors.centerIn: parent; text: "←"; font.pixelSize: 28; color: "#fff" }
            MouseArea { id: backMa; anchors.fill: parent; onClicked: { Haptic.tap(); Qt.quit() } }
        }
    }

    // Reader
    Item {
        anchors.fill: parent
        visible: currentView === "reader"

        // Header
        Rectangle {
            id: readerHeader
            anchors.top: parent.top
            width: parent.width
            height: 80
            color: "#0a0a0f"
            z: 10

            Text {
                anchors.centerIn: parent
                text: currentBook ? currentBook.title : ""
                font.pixelSize: 18 * textScale
                color: "#ffffff"
                elide: Text.ElideRight
                width: parent.width - 32
                horizontalAlignment: Text.AlignHCenter
            }

            Text {
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 8
                anchors.horizontalCenter: parent.horizontalCenter
                text: (currentPage + 1) + " / " + bookPages.length
                font.pixelSize: 14 * textScale
                color: "#666677"
            }
        }

        // Content
        Flickable {
            anchors.top: readerHeader.bottom
            anchors.bottom: readerFooter.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 24
            contentHeight: pageText.height
            clip: true

            Text {
                id: pageText
                width: parent.width
                text: bookPages[currentPage] || ""
                font.pixelSize: fontSize
                color: "#e8e8f0"
                wrapMode: Text.WordWrap
                lineHeight: 1.6
            }
        }

        // Tap zones
        MouseArea {
            anchors.left: parent.left
            anchors.top: readerHeader.bottom
            anchors.bottom: readerFooter.top
            width: parent.width / 3
            onClicked: prevPage()
        }

        MouseArea {
            anchors.right: parent.right
            anchors.top: readerHeader.bottom
            anchors.bottom: readerFooter.top
            width: parent.width / 3
            onClicked: nextPage()
        }

        // Footer
        Rectangle {
            id: readerFooter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 40
            width: parent.width
            height: 70
            color: "#151520"

            Row {
                anchors.centerIn: parent
                spacing: 24

                Rectangle {
                    width: 48; height: 48; radius: 24
                    color: fontDownMa.pressed ? "#333344" : "#252530"
                    Text { anchors.centerIn: parent; text: "A-"; font.pixelSize: 16; font.bold: true; color: "#fff" }
                    MouseArea {
                        id: fontDownMa
                        anchors.fill: parent
                        onClicked: {
                            Haptic.tap()
                            fontSize = Math.max(14, fontSize - 2)
                            paginate()
                            savePosition()
                        }
                    }
                }

                Rectangle {
                    width: 48; height: 48; radius: 24
                    color: prevMa.pressed ? "#333344" : "#252530"
                    opacity: currentPage > 0 ? 1 : 0.3
                    Text { anchors.centerIn: parent; text: "◀"; font.pixelSize: 20; color: "#fff" }
                    MouseArea { id: prevMa; anchors.fill: parent; enabled: currentPage > 0; onClicked: prevPage() }
                }

                Rectangle {
                    width: 48; height: 48; radius: 24
                    color: nextMa.pressed ? "#333344" : "#252530"
                    opacity: currentPage < bookPages.length - 1 ? 1 : 0.3
                    Text { anchors.centerIn: parent; text: "▶"; font.pixelSize: 20; color: "#fff" }
                    MouseArea { id: nextMa; anchors.fill: parent; enabled: currentPage < bookPages.length - 1; onClicked: nextPage() }
                }

                Rectangle {
                    width: 48; height: 48; radius: 24
                    color: fontUpMa.pressed ? "#333344" : "#252530"
                    Text { anchors.centerIn: parent; text: "A+"; font.pixelSize: 16; font.bold: true; color: "#fff" }
                    MouseArea {
                        id: fontUpMa
                        anchors.fill: parent
                        onClicked: {
                            Haptic.tap()
                            fontSize = Math.min(40, fontSize + 2)
                            paginate()
                            savePosition()
                        }
                    }
                }
            }
        }

        // Back button
        Rectangle {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 24
            anchors.bottomMargin: 130
            width: 64; height: 64; radius: 32
            color: readerBackMa.pressed ? Qt.darker(accentColor, 1.2) : accentColor
            z: 10

            Text { anchors.centerIn: parent; text: "←"; font.pixelSize: 28; color: "#fff" }
            MouseArea {
                id: readerBackMa
                anchors.fill: parent
                onClicked: {
                    Haptic.tap()
                    savePosition()
                    currentView = "library"
                }
            }
        }
    }
}
