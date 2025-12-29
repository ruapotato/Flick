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
    property int pageDirection: 0  // -1 left, 1 right, 0 none

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
            pageDirection = 1
            pageFlipAnim.start()
            currentPage++
            savePosition()
            Haptic.tap()
        }
    }

    function prevPage() {
        if (currentPage > 0) {
            pageDirection = -1
            pageFlipAnim.start()
            currentPage--
            savePosition()
            Haptic.tap()
        }
    }

    // Library
    Item {
        anchors.fill: parent
        visible: currentView === "library"

        // Animated background gradient
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#0a0a0f" }
                GradientStop { position: 0.5; color: "#0f0f18" }
                GradientStop { position: 1.0; color: "#0a0a0f" }
            }
        }

        // Floating particles
        Repeater {
            model: 8
            Rectangle {
                property real startX: Math.random() * root.width
                property real startY: Math.random() * root.height
                x: startX
                y: startY
                width: 4 + Math.random() * 4
                height: width
                radius: width / 2
                color: accentColor
                opacity: 0.1 + Math.random() * 0.1

                SequentialAnimation on y {
                    loops: Animation.Infinite
                    NumberAnimation { to: startY - 100; duration: 3000 + Math.random() * 2000; easing.type: Easing.InOutSine }
                    NumberAnimation { to: startY; duration: 3000 + Math.random() * 2000; easing.type: Easing.InOutSine }
                }

                SequentialAnimation on opacity {
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.2; duration: 2000; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 0.05; duration: 2000; easing.type: Easing.InOutSine }
                }
            }
        }

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
                font.letterSpacing: 4
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
            id: bookListView
            anchors.fill: parent
            anchors.topMargin: 180
            anchors.bottomMargin: 100
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            spacing: 12
            clip: true
            model: booksModel

            // Smooth scrolling
            flickDeceleration: 1500
            maximumFlickVelocity: 4000

            // Pull indicator
            header: Item {
                width: parent.width
                height: bookListView.contentY < -50 ? 60 : 0
                Behavior on height { NumberAnimation { duration: 150 } }
            }

            delegate: Rectangle {
                width: bookListView.width
                height: 100
                radius: 20
                color: ma.pressed ? "#252535" : "#15151f"
                border.width: 2
                border.color: ma.pressed ? accentColor : "#252530"

                Behavior on color { ColorAnimation { duration: 150 } }
                Behavior on border.color { ColorAnimation { duration: 150 } }
                Behavior on scale { NumberAnimation { duration: 100 } }

                scale: ma.pressed ? 0.98 : 1.0

                Row {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 16

                    // Book icon with glow
                    Item {
                        width: 68
                        height: 68
                        anchors.verticalCenter: parent.verticalCenter

                        Rectangle {
                            anchors.centerIn: parent
                            width: 80
                            height: 80
                            radius: 40
                            color: accentColor
                            opacity: 0.15
                        }

                        Rectangle {
                            anchors.centerIn: parent
                            width: 68
                            height: 68
                            radius: 16
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: Qt.lighter(accentColor, 1.2) }
                                GradientStop { position: 1.0; color: accentColor }
                            }
                            opacity: 0.3
                        }

                        Text {
                            anchors.centerIn: parent
                            text: "📖"
                            font.pixelSize: 32
                        }
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 100
                        spacing: 4

                        Text {
                            width: parent.width
                            text: model.title
                            font.pixelSize: 20 * textScale
                            font.weight: Font.Medium
                            color: "#ffffff"
                            elide: Text.ElideRight
                        }

                        // Progress bar if we have a saved position
                        Rectangle {
                            width: parent.width
                            height: 4
                            radius: 2
                            color: "#252530"
                            visible: positions[model.path] !== undefined

                            Rectangle {
                                width: {
                                    var pos = positions[model.path]
                                    if (pos && pos.page !== undefined) {
                                        return parent.width * 0.1  // Approximate
                                    }
                                    return 0
                                }
                                height: parent.height
                                radius: 2
                                color: accentColor
                            }
                        }
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

            // Scroll indicator
            Rectangle {
                anchors.right: parent.right
                anchors.rightMargin: 2
                y: parent.height * (parent.contentY / parent.contentHeight)
                width: 4
                height: Math.max(40, parent.height * (parent.height / parent.contentHeight))
                radius: 2
                color: accentColor
                opacity: parent.moving ? 0.8 : 0
                Behavior on opacity { NumberAnimation { duration: 300 } }
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

        // Back button with glow
        Rectangle {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 24
            anchors.bottomMargin: 100
            width: 64; height: 64; radius: 32
            color: backMa.pressed ? Qt.darker(accentColor, 1.2) : accentColor

            Rectangle {
                anchors.centerIn: parent
                width: 80
                height: 80
                radius: 40
                color: accentColor
                opacity: 0.2
                z: -1
            }

            Text { anchors.centerIn: parent; text: "←"; font.pixelSize: 28; color: "#fff" }
            MouseArea { id: backMa; anchors.fill: parent; onClicked: { Haptic.tap(); Qt.quit() } }
        }
    }

    // Reader
    Item {
        anchors.fill: parent
        visible: currentView === "reader"

        // Paper texture background
        Rectangle {
            anchors.fill: parent
            color: "#0d0d12"
        }

        // Header
        Rectangle {
            id: readerHeader
            anchors.top: parent.top
            width: parent.width
            height: 90
            color: "#0a0a0f"
            z: 10

            // Subtle bottom glow
            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1
                color: accentColor
                opacity: 0.3
            }

            Column {
                anchors.centerIn: parent
                spacing: 4

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: currentBook ? currentBook.title : ""
                    font.pixelSize: 18 * textScale
                    font.weight: Font.Medium
                    color: "#ffffff"
                    elide: Text.ElideRight
                    width: root.width - 32
                    horizontalAlignment: Text.AlignHCenter
                }

                // Page progress
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 8

                    Text {
                        text: (currentPage + 1) + " / " + bookPages.length
                        font.pixelSize: 14 * textScale
                        color: "#666677"
                    }

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 100
                        height: 3
                        radius: 1.5
                        color: "#252530"

                        Rectangle {
                            width: parent.width * ((currentPage + 1) / Math.max(1, bookPages.length))
                            height: parent.height
                            radius: 1.5
                            color: accentColor

                            Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                        }
                    }
                }
            }
        }

        // Page content with flip animation
        Item {
            id: pageContainer
            anchors.top: readerHeader.bottom
            anchors.bottom: readerFooter.top
            anchors.left: parent.left
            anchors.right: parent.right
            clip: true

            // Page flip animation
            SequentialAnimation {
                id: pageFlipAnim

                NumberAnimation {
                    target: pageContent
                    property: "opacity"
                    to: 0
                    duration: 100
                    easing.type: Easing.OutQuad
                }

                NumberAnimation {
                    target: pageContent
                    property: "x"
                    to: pageDirection * -50
                    duration: 0
                }

                ParallelAnimation {
                    NumberAnimation {
                        target: pageContent
                        property: "opacity"
                        to: 1
                        duration: 200
                        easing.type: Easing.OutCubic
                    }
                    NumberAnimation {
                        target: pageContent
                        property: "x"
                        to: 0
                        duration: 200
                        easing.type: Easing.OutCubic
                    }
                }
            }

            Flickable {
                id: pageContent
                anchors.fill: parent
                anchors.margins: 24
                contentHeight: pageText.height + 40
                clip: true

                flickDeceleration: 2000
                boundsBehavior: Flickable.DragAndOvershootBounds

                Text {
                    id: pageText
                    width: parent.width
                    text: bookPages[currentPage] || ""
                    font.pixelSize: fontSize
                    font.family: "serif"
                    color: "#e8e8f0"
                    wrapMode: Text.WordWrap
                    lineHeight: 1.7
                    textFormat: Text.PlainText
                }

                // Scroll indicator
                Rectangle {
                    anchors.right: parent.right
                    anchors.rightMargin: -20
                    y: pageContent.height * (pageContent.contentY / pageContent.contentHeight)
                    width: 3
                    height: Math.max(30, pageContent.height * (pageContent.height / pageContent.contentHeight))
                    radius: 1.5
                    color: accentColor
                    opacity: pageContent.moving ? 0.6 : 0
                    Behavior on opacity { NumberAnimation { duration: 300 } }
                }
            }

            // Edge shadows for depth
            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 20
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "#20000000" }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }

            Rectangle {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 20
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 1.0; color: "#20000000" }
                }
            }
        }

        // Invisible tap zones
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

        // Swipe detection in middle
        MouseArea {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: readerHeader.bottom
            anchors.bottom: readerFooter.top
            width: parent.width / 3
            property real startX: 0

            onPressed: startX = mouseX
            onReleased: {
                var delta = mouseX - startX
                if (Math.abs(delta) > 80) {
                    if (delta > 0) prevPage()
                    else nextPage()
                }
            }
        }

        // Footer with glassmorphism effect
        Rectangle {
            id: readerFooter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 40
            width: parent.width
            height: 80
            color: "#18181f"

            Rectangle {
                anchors.top: parent.top
                width: parent.width
                height: 1
                color: "#333344"
            }

            Row {
                anchors.centerIn: parent
                spacing: 20

                // Font size down
                Rectangle {
                    width: 52; height: 52; radius: 26
                    color: fontDownMa.pressed ? "#333344" : "#252530"
                    border.width: 1
                    border.color: "#333344"

                    Behavior on color { ColorAnimation { duration: 100 } }

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

                // Previous
                Rectangle {
                    width: 52; height: 52; radius: 26
                    color: prevMa.pressed ? "#333344" : "#252530"
                    border.width: 1
                    border.color: currentPage > 0 ? "#333344" : "#1a1a1a"
                    opacity: currentPage > 0 ? 1 : 0.4

                    Behavior on color { ColorAnimation { duration: 100 } }

                    Text { anchors.centerIn: parent; text: "◀"; font.pixelSize: 18; color: "#fff" }
                    MouseArea { id: prevMa; anchors.fill: parent; enabled: currentPage > 0; onClicked: prevPage() }
                }

                // Page indicator pill
                Rectangle {
                    width: 80
                    height: 36
                    radius: 18
                    color: "#1a1a24"
                    border.width: 1
                    border.color: "#333344"
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        anchors.centerIn: parent
                        text: (currentPage + 1) + "/" + bookPages.length
                        font.pixelSize: 14
                        font.weight: Font.Medium
                        color: "#aaaaaa"
                    }
                }

                // Next
                Rectangle {
                    width: 52; height: 52; radius: 26
                    color: nextMa.pressed ? "#333344" : "#252530"
                    border.width: 1
                    border.color: currentPage < bookPages.length - 1 ? "#333344" : "#1a1a1a"
                    opacity: currentPage < bookPages.length - 1 ? 1 : 0.4

                    Behavior on color { ColorAnimation { duration: 100 } }

                    Text { anchors.centerIn: parent; text: "▶"; font.pixelSize: 18; color: "#fff" }
                    MouseArea { id: nextMa; anchors.fill: parent; enabled: currentPage < bookPages.length - 1; onClicked: nextPage() }
                }

                // Font size up
                Rectangle {
                    width: 52; height: 52; radius: 26
                    color: fontUpMa.pressed ? "#333344" : "#252530"
                    border.width: 1
                    border.color: "#333344"

                    Behavior on color { ColorAnimation { duration: 100 } }

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
            anchors.bottomMargin: 140
            width: 64; height: 64; radius: 32
            color: readerBackMa.pressed ? Qt.darker(accentColor, 1.2) : accentColor
            z: 10

            Behavior on scale { NumberAnimation { duration: 100 } }
            scale: readerBackMa.pressed ? 0.95 : 1.0

            // Glow
            Rectangle {
                anchors.centerIn: parent
                width: 80
                height: 80
                radius: 40
                color: accentColor
                opacity: 0.2
                z: -1
            }

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
