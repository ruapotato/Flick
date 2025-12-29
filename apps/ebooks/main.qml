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
    property real fontSize: 22
    property var positions: ({})
    property string positionsFile: "/home/droidian/.local/state/flick/ebook_positions.json"
    property int pageDirection: 0
    property string theme: "dark"  // "dark", "sepia", "light"
    property bool serifFont: true
    property bool immersiveMode: false
    property int wordCount: 0

    // Preset book cover colors for visual variety
    property var coverColors: [
        ["#e94560", "#ff6b6b"],  // red
        ["#4ecdc4", "#45b7af"],  // teal
        ["#a855f7", "#7c3aed"],  // purple
        ["#3b82f6", "#2563eb"],  // blue
        ["#f59e0b", "#d97706"],  // amber
        ["#10b981", "#059669"],  // emerald
        ["#ec4899", "#db2777"],  // pink
        ["#8b5cf6", "#6d28d9"],  // violet
        ["#06b6d4", "#0891b2"],  // cyan
        ["#f97316", "#ea580c"]   // orange
    ]

    // Theme colors
    property color bgColor: theme === "dark" ? "#0d0d12" : (theme === "sepia" ? "#f4ecd8" : "#fafafa")
    property color textColor: theme === "dark" ? "#e8e8f0" : (theme === "sepia" ? "#5c4b37" : "#2a2a2a")
    property color headerBg: theme === "dark" ? "#0a0a0f" : (theme === "sepia" ? "#e8dcc8" : "#f0f0f0")

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
                fontSize = 22 * textScale
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
        positions[currentBook.path] = {
            page: currentPage,
            fontSize: fontSize,
            theme: theme,
            serifFont: serifFont,
            totalPages: bookPages.length
        }
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

    function getCoverColor(title) {
        var hash = 0
        for (var i = 0; i < title.length; i++) {
            hash = ((hash << 5) - hash) + title.charCodeAt(i)
            hash = hash & hash
        }
        return coverColors[Math.abs(hash) % coverColors.length]
    }

    function getReadingProgress(path) {
        if (positions[path]) {
            var page = positions[path].page || 0
            var total = positions[path].totalPages || 1
            return (page + 1) / total
        }
        return 0
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
        serifFont = true
        if (positions[book.path]) {
            currentPage = positions[book.path].page || 0
            fontSize = positions[book.path].fontSize || fontSize
            theme = positions[book.path].theme || theme
            serifFont = positions[book.path].serifFont !== false
        }

        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file://" + book.path, false)
        try {
            xhr.send()
            if (xhr.status === 200 || xhr.status === 0) {
                bookContent = xhr.responseText
                wordCount = bookContent.split(/\s+/).length
                paginate()
                currentView = "reader"
                immersiveMode = false
            }
        } catch (e) {}
    }

    function paginate() {
        var paras = bookContent.split(/\n\n+/)
        var pages = []
        var page = ""
        var lines = 0
        var maxLines = Math.floor((root.height - 320) / (fontSize * 1.8))

        for (var i = 0; i < paras.length; i++) {
            var p = paras[i].trim()
            if (!p) continue
            var pLines = Math.ceil(p.length / Math.floor((root.width - 80) / (fontSize * 0.55)))
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

    function getReadingTime() {
        var wordsRemaining = Math.round(wordCount * (1 - (currentPage / Math.max(1, bookPages.length))))
        var minutes = Math.ceil(wordsRemaining / 200)  // avg 200 wpm
        if (minutes < 60) return minutes + " min left"
        var hours = Math.floor(minutes / 60)
        var mins = minutes % 60
        return hours + "h " + mins + "m left"
    }

    function nextPage() {
        if (currentPage < bookPages.length - 1) {
            pageDirection = 1
            pageFlipAnim.start()
            currentPage++
            pageContent.contentY = 0
            savePosition()
            Haptic.tap()
        }
    }

    function prevPage() {
        if (currentPage > 0) {
            pageDirection = -1
            pageFlipAnim.start()
            currentPage--
            pageContent.contentY = 0
            savePosition()
            Haptic.tap()
        }
    }

    function cycleTheme() {
        if (theme === "dark") theme = "sepia"
        else if (theme === "sepia") theme = "light"
        else theme = "dark"
        savePosition()
        Haptic.tap()
    }

    // ==================== LIBRARY ====================
    Item {
        anchors.fill: parent
        visible: currentView === "library"

        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#06060a" }
                GradientStop { position: 0.4; color: "#0a0a0f" }
                GradientStop { position: 0.6; color: "#0c0c14" }
                GradientStop { position: 1.0; color: "#08080c" }
            }
        }

        // Subtle background pattern
        Canvas {
            anchors.fill: parent
            opacity: 0.03
            onPaint: {
                var ctx = getContext("2d")
                ctx.strokeStyle = "#ffffff"
                ctx.lineWidth = 0.5
                for (var i = 0; i < width; i += 60) {
                    for (var j = 0; j < height; j += 60) {
                        ctx.beginPath()
                        ctx.moveTo(i, j)
                        ctx.lineTo(i + 30, j + 30)
                        ctx.stroke()
                    }
                }
            }
        }

        // Ambient glow orbs
        Repeater {
            model: 3
            Rectangle {
                property real centerX: (index === 0 ? 0.2 : (index === 1 ? 0.8 : 0.5)) * root.width
                property real centerY: (index === 0 ? 0.15 : (index === 1 ? 0.25 : 0.7)) * root.height
                x: centerX - width/2
                y: centerY - height/2
                width: 300 + index * 100
                height: width
                radius: width / 2
                color: coverColors[index * 3][0]
                opacity: 0.025

                SequentialAnimation on opacity {
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.04; duration: 3000 + index * 1000; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 0.025; duration: 3000 + index * 1000; easing.type: Easing.InOutSine }
                }
            }
        }

        // Header
        Column {
            id: libraryHeader
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.topMargin: 60
            spacing: 16

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Library"
                font.pixelSize: 52 * textScale
                font.weight: Font.Light
                font.letterSpacing: 8
                color: "#ffffff"
            }

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 80
                height: 2
                radius: 1
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.5; color: accentColor }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: booksModel.count + (booksModel.count === 1 ? " book" : " books")
                font.pixelSize: 15 * textScale
                font.letterSpacing: 3
                font.weight: Font.Light
                color: "#666688"
            }
        }

        ListView {
            id: bookListView
            anchors.top: libraryHeader.bottom
            anchors.topMargin: 40
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 110
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 24
            anchors.rightMargin: 24
            spacing: 20
            clip: true
            model: booksModel

            flickDeceleration: 1500
            maximumFlickVelocity: 4000
            boundsBehavior: Flickable.DragAndOvershootBounds

            delegate: Item {
                width: bookListView.width
                height: 120

                Rectangle {
                    id: cardBg
                    anchors.fill: parent
                    radius: 20
                    color: ma.pressed ? "#1a1a28" : "#101018"
                    border.width: 1
                    border.color: ma.pressed ? Qt.rgba(getCoverColor(model.title)[0].substring(1,3)/255, 0, 0, 0.5) : "#1a1a24"

                    Behavior on color { ColorAnimation { duration: 150 } }
                    Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }

                    scale: ma.pressed ? 0.98 : 1.0

                    // Card shine effect
                    Rectangle {
                        anchors.fill: parent
                        radius: parent.radius
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: "#06ffffff" }
                            GradientStop { position: 0.3; color: "transparent" }
                            GradientStop { position: 1.0; color: "#02000000" }
                        }
                    }

                    Row {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 20

                        // Book cover with dynamic colors
                        Rectangle {
                            id: bookCover
                            width: 64
                            height: 88
                            radius: 6
                            anchors.verticalCenter: parent.verticalCenter

                            property var colors: getCoverColor(model.title)
                            property real progress: getReadingProgress(model.path)

                            gradient: Gradient {
                                GradientStop { position: 0.0; color: bookCover.colors[0] }
                                GradientStop { position: 1.0; color: bookCover.colors[1] }
                            }

                            // Spine highlight
                            Rectangle {
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                width: 8
                                radius: 6
                                color: Qt.lighter(bookCover.colors[0], 1.3)
                                opacity: 0.4

                                Rectangle {
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    width: 1
                                    color: "#00000030"
                                }
                            }

                            // Decorative lines
                            Column {
                                anchors.centerIn: parent
                                anchors.horizontalCenterOffset: 4
                                spacing: 6

                                Repeater {
                                    model: 3
                                    Rectangle {
                                        width: 32 - index * 6
                                        height: 2
                                        radius: 1
                                        color: "#ffffff"
                                        opacity: 0.25 - index * 0.05
                                    }
                                }
                            }

                            // Title initial
                            Text {
                                anchors.bottom: parent.bottom
                                anchors.right: parent.right
                                anchors.margins: 6
                                text: model.title.charAt(0).toUpperCase()
                                font.pixelSize: 24
                                font.weight: Font.Bold
                                color: "#ffffff"
                                opacity: 0.9
                                style: Text.Raised
                                styleColor: "#00000040"
                            }

                            // Progress overlay
                            Rectangle {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                height: parent.height * (1 - bookCover.progress)
                                color: "#000000"
                                opacity: 0.3
                                visible: bookCover.progress > 0 && bookCover.progress < 1

                                Rectangle {
                                    anchors.top: parent.top
                                    width: parent.width
                                    height: 2
                                    color: "#ffffff"
                                    opacity: 0.5
                                }
                            }
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 100
                            spacing: 10

                            Text {
                                width: parent.width
                                text: model.title
                                font.pixelSize: 19 * textScale
                                font.weight: Font.Medium
                                font.letterSpacing: 0.5
                                color: "#ffffff"
                                elide: Text.ElideRight
                                maximumLineCount: 2
                                wrapMode: Text.WordWrap
                            }

                            Row {
                                spacing: 12
                                visible: positions[model.path] !== undefined

                                Rectangle {
                                    width: 80
                                    height: 3
                                    radius: 1.5
                                    color: "#202030"
                                    anchors.verticalCenter: parent.verticalCenter

                                    Rectangle {
                                        width: parent.width * getReadingProgress(model.path)
                                        height: parent.height
                                        radius: 1.5
                                        color: getCoverColor(model.title)[0]

                                        Behavior on width { NumberAnimation { duration: 300 } }
                                    }
                                }

                                Text {
                                    text: Math.round(getReadingProgress(model.path) * 100) + "%"
                                    font.pixelSize: 12 * textScale
                                    font.weight: Font.Medium
                                    color: getCoverColor(model.title)[0]
                                }
                            }

                            Text {
                                visible: positions[model.path] === undefined
                                text: "New book"
                                font.pixelSize: 13 * textScale
                                font.weight: Font.Light
                                font.letterSpacing: 1
                                color: "#555570"
                            }
                        }

                        // Arrow indicator
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "›"
                            font.pixelSize: 32
                            font.weight: Font.Light
                            color: "#444455"
                            opacity: ma.pressed ? 1 : 0.6
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
        }

        // Empty state
        Column {
            anchors.centerIn: parent
            spacing: 24
            visible: booksModel.count === 0
            opacity: 0.8

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 120
                height: 160
                radius: 8
                color: "#16161e"
                border.width: 2
                border.color: "#252535"

                // Book spine lines
                Column {
                    anchors.centerIn: parent
                    spacing: 8

                    Repeater {
                        model: 5
                        Rectangle {
                            width: 60 - index * 8
                            height: 3
                            radius: 1.5
                            color: "#303045"
                        }
                    }
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Your library is empty"
                font.pixelSize: 20 * textScale
                font.weight: Font.Light
                font.letterSpacing: 1
                color: "#888899"
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Add .epub or .txt files to ~/Books"
                font.pixelSize: 14 * textScale
                font.weight: Font.Light
                color: "#555566"
            }
        }

        // Exit button
        Rectangle {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 28
            anchors.bottomMargin: 100
            width: 60; height: 60; radius: 30
            color: backMa.pressed ? Qt.darker(accentColor, 1.2) : accentColor

            Behavior on scale { NumberAnimation { duration: 100 } }
            scale: backMa.pressed ? 0.92 : 1.0

            // Outer glow
            Rectangle {
                anchors.centerIn: parent
                width: 80; height: 80; radius: 40
                color: accentColor
                opacity: 0.12
                z: -1
            }

            Text {
                anchors.centerIn: parent
                text: "×"
                font.pixelSize: 32
                font.weight: Font.Light
                color: "#fff"
            }
            MouseArea {
                id: backMa
                anchors.fill: parent
                anchors.margins: -10
                onClicked: { Haptic.tap(); Qt.quit() }
            }
        }
    }

    // ==================== READER ====================
    Item {
        anchors.fill: parent
        visible: currentView === "reader"

        Rectangle {
            anchors.fill: parent
            color: bgColor
            Behavior on color { ColorAnimation { duration: 400; easing.type: Easing.InOutQuad } }
        }

        // Page flip animation with curl effect
        SequentialAnimation {
            id: pageFlipAnim

            ParallelAnimation {
                NumberAnimation {
                    target: pageContent
                    property: "opacity"
                    to: 0
                    duration: 120
                    easing.type: Easing.OutQuad
                }
                NumberAnimation {
                    target: pageContent
                    property: "scale"
                    to: 0.96
                    duration: 120
                    easing.type: Easing.OutQuad
                }
                NumberAnimation {
                    target: pageContent
                    property: "x"
                    to: pageDirection * -40
                    duration: 120
                    easing.type: Easing.OutQuad
                }
            }

            PropertyAction {
                target: pageContent
                property: "x"
                value: pageDirection * 30
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
                    property: "scale"
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

        // Header - animated visibility
        Rectangle {
            id: readerHeader
            anchors.top: parent.top
            width: parent.width
            height: immersiveMode ? 0 : 110
            color: headerBg
            z: 10
            clip: true

            Behavior on height { NumberAnimation { duration: 250; easing.type: Easing.InOutCubic } }
            Behavior on color { ColorAnimation { duration: 400 } }

            // Subtle shadow
            Rectangle {
                anchors.top: parent.bottom
                width: parent.width
                height: 20
                visible: !immersiveMode
                gradient: Gradient {
                    GradientStop { position: 0.0; color: theme === "dark" ? "#20000000" : "#10000000" }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }

            Column {
                anchors.centerIn: parent
                spacing: 10
                opacity: immersiveMode ? 0 : 1
                Behavior on opacity { NumberAnimation { duration: 200 } }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: currentBook ? currentBook.title : ""
                    font.pixelSize: 17 * textScale
                    font.weight: Font.Medium
                    font.letterSpacing: 0.5
                    color: theme === "dark" ? "#ffffff" : "#333333"
                    elide: Text.ElideRight
                    width: root.width - 140
                    horizontalAlignment: Text.AlignHCenter
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 16

                    // Progress bar
                    Rectangle {
                        width: 140
                        height: 3
                        radius: 1.5
                        color: theme === "dark" ? "#252530" : "#00000012"
                        anchors.verticalCenter: parent.verticalCenter

                        Rectangle {
                            width: parent.width * ((currentPage + 1) / Math.max(1, bookPages.length))
                            height: parent.height
                            radius: 1.5
                            color: accentColor

                            Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                        }
                    }

                    Text {
                        text: getReadingTime()
                        font.pixelSize: 12 * textScale
                        font.weight: Font.Light
                        color: theme === "dark" ? "#888899" : "#666666"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            // Theme toggle
            Rectangle {
                anchors.right: parent.right
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                width: 48; height: 48; radius: 24
                color: themeMa.pressed ? (theme === "dark" ? "#333344" : "#00000015") : "transparent"
                visible: !immersiveMode

                Text {
                    anchors.centerIn: parent
                    text: theme === "dark" ? "◐" : (theme === "sepia" ? "◑" : "○")
                    font.pixelSize: 22
                    color: theme === "dark" ? "#888899" : "#666666"
                }

                MouseArea {
                    id: themeMa
                    anchors.fill: parent
                    onClicked: cycleTheme()
                }
            }

            // Font toggle
            Rectangle {
                anchors.left: parent.left
                anchors.leftMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                width: 48; height: 48; radius: 24
                color: fontMa.pressed ? (theme === "dark" ? "#333344" : "#00000015") : "transparent"
                visible: !immersiveMode

                Text {
                    anchors.centerIn: parent
                    text: serifFont ? "Aa" : "Aa"
                    font.pixelSize: 18
                    font.family: serifFont ? "serif" : "sans-serif"
                    font.weight: Font.Medium
                    color: theme === "dark" ? "#888899" : "#666666"
                }

                MouseArea {
                    id: fontMa
                    anchors.fill: parent
                    onClicked: {
                        Haptic.tap()
                        serifFont = !serifFont
                        savePosition()
                    }
                }
            }
        }

        // Content area with swipe detection
        Item {
            id: contentArea
            anchors.top: readerHeader.bottom
            anchors.bottom: readerFooter.top
            anchors.left: parent.left
            anchors.right: parent.right

            // Swipe gesture detection
            property real swipeStartX: 0
            property real swipeStartY: 0
            property bool isHorizontalSwipe: false

            Flickable {
                id: pageContent
                anchors.fill: parent
                anchors.margins: 36
                anchors.topMargin: 20
                anchors.bottomMargin: 12
                contentHeight: pageText.height + 80
                clip: true

                flickDeceleration: 2500
                maximumFlickVelocity: 6000
                boundsBehavior: Flickable.DragAndOvershootBounds

                // Tap to toggle immersive mode
                MouseArea {
                    anchors.fill: parent
                    propagateComposedEvents: true
                    onClicked: {
                        if (mouse.y > parent.height * 0.3 && mouse.y < parent.height * 0.7) {
                            immersiveMode = !immersiveMode
                            Haptic.tap()
                        }
                        mouse.accepted = false
                    }
                    onPressed: mouse.accepted = false
                    onReleased: mouse.accepted = false
                }

                Text {
                    id: pageText
                    width: parent.width
                    text: bookPages[currentPage] || ""
                    font.pixelSize: fontSize
                    font.family: serifFont ? "Georgia, serif" : "Helvetica, sans-serif"
                    color: textColor
                    wrapMode: Text.WordWrap
                    lineHeight: 1.75
                    textFormat: Text.PlainText

                    Behavior on color { ColorAnimation { duration: 400 } }
                    Behavior on font.family { PropertyAnimation { duration: 0 } }
                }
            }

            // Horizontal swipe overlay for page turns
            MouseArea {
                anchors.fill: parent
                propagateComposedEvents: true

                onPressed: {
                    contentArea.swipeStartX = mouse.x
                    contentArea.swipeStartY = mouse.y
                    contentArea.isHorizontalSwipe = false
                    mouse.accepted = false
                }

                onPositionChanged: {
                    var dx = mouse.x - contentArea.swipeStartX
                    var dy = mouse.y - contentArea.swipeStartY

                    if (!contentArea.isHorizontalSwipe && Math.abs(dx) > 30 && Math.abs(dx) > Math.abs(dy) * 2) {
                        contentArea.isHorizontalSwipe = true
                    }
                    mouse.accepted = false
                }

                onReleased: {
                    var dx = mouse.x - contentArea.swipeStartX
                    if (contentArea.isHorizontalSwipe && Math.abs(dx) > 80) {
                        if (dx < 0) nextPage()
                        else prevPage()
                    }
                    mouse.accepted = false
                }
            }
        }

        // Scroll fade at bottom
        Rectangle {
            anchors.bottom: readerFooter.top
            width: parent.width
            height: 50
            visible: pageContent.contentHeight > pageContent.height && !immersiveMode
            gradient: Gradient {
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 1.0; color: bgColor }
            }
            Behavior on visible { NumberAnimation { duration: 200 } }
        }

        // Footer - animated visibility
        Rectangle {
            id: readerFooter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 30
            width: parent.width
            height: immersiveMode ? 0 : 100
            color: headerBg
            clip: true

            Behavior on height { NumberAnimation { duration: 250; easing.type: Easing.InOutCubic } }
            Behavior on color { ColorAnimation { duration: 400 } }

            // Top shadow
            Rectangle {
                anchors.bottom: parent.top
                width: parent.width
                height: 20
                visible: !immersiveMode
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 1.0; color: theme === "dark" ? "#20000000" : "#10000000" }
                }
            }

            Row {
                anchors.centerIn: parent
                spacing: 20
                opacity: immersiveMode ? 0 : 1
                Behavior on opacity { NumberAnimation { duration: 200 } }

                // Font smaller
                Rectangle {
                    width: 48; height: 48; radius: 24
                    color: fontDownMa.pressed ? (theme === "dark" ? "#333344" : "#00000015") : (theme === "dark" ? "#18181f" : "#00000005")
                    border.width: 1
                    border.color: theme === "dark" ? "#2a2a35" : "#00000008"

                    Text {
                        anchors.centerIn: parent
                        text: "A"
                        font.pixelSize: 13
                        font.weight: Font.Medium
                        color: theme === "dark" ? "#888899" : "#666666"
                    }

                    MouseArea {
                        id: fontDownMa
                        anchors.fill: parent
                        onClicked: {
                            Haptic.tap()
                            fontSize = Math.max(16, fontSize - 2)
                            paginate()
                            savePosition()
                        }
                    }
                }

                // Previous page
                Rectangle {
                    width: 60; height: 60; radius: 30
                    color: prevMa.pressed ? accentColor : (theme === "dark" ? "#18181f" : "#00000005")
                    border.width: 2
                    border.color: currentPage > 0 ? accentColor : (theme === "dark" ? "#252530" : "#00000008")
                    opacity: currentPage > 0 ? 1 : 0.35

                    Behavior on color { ColorAnimation { duration: 100 } }

                    Text {
                        anchors.centerIn: parent
                        text: "‹"
                        font.pixelSize: 28
                        font.weight: Font.Light
                        color: prevMa.pressed ? "#ffffff" : (theme === "dark" ? "#ffffff" : "#333333")
                    }

                    MouseArea {
                        id: prevMa
                        anchors.fill: parent
                        enabled: currentPage > 0
                        onClicked: prevPage()
                    }
                }

                // Page counter
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: (currentPage + 1) + " / " + bookPages.length
                        font.pixelSize: 16
                        font.weight: Font.Medium
                        font.letterSpacing: 1
                        color: theme === "dark" ? "#cccccc" : "#444444"
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Math.round(((currentPage + 1) / Math.max(1, bookPages.length)) * 100) + "%"
                        font.pixelSize: 11
                        font.weight: Font.Light
                        color: accentColor
                    }
                }

                // Next page
                Rectangle {
                    width: 60; height: 60; radius: 30
                    color: nextMa.pressed ? accentColor : (theme === "dark" ? "#18181f" : "#00000005")
                    border.width: 2
                    border.color: currentPage < bookPages.length - 1 ? accentColor : (theme === "dark" ? "#252530" : "#00000008")
                    opacity: currentPage < bookPages.length - 1 ? 1 : 0.35

                    Behavior on color { ColorAnimation { duration: 100 } }

                    Text {
                        anchors.centerIn: parent
                        text: "›"
                        font.pixelSize: 28
                        font.weight: Font.Light
                        color: nextMa.pressed ? "#ffffff" : (theme === "dark" ? "#ffffff" : "#333333")
                    }

                    MouseArea {
                        id: nextMa
                        anchors.fill: parent
                        enabled: currentPage < bookPages.length - 1
                        onClicked: nextPage()
                    }
                }

                // Font larger
                Rectangle {
                    width: 48; height: 48; radius: 24
                    color: fontUpMa.pressed ? (theme === "dark" ? "#333344" : "#00000015") : (theme === "dark" ? "#18181f" : "#00000005")
                    border.width: 1
                    border.color: theme === "dark" ? "#2a2a35" : "#00000008"

                    Text {
                        anchors.centerIn: parent
                        text: "A"
                        font.pixelSize: 20
                        font.weight: Font.Medium
                        color: theme === "dark" ? "#ffffff" : "#333333"
                    }

                    MouseArea {
                        id: fontUpMa
                        anchors.fill: parent
                        onClicked: {
                            Haptic.tap()
                            fontSize = Math.min(44, fontSize + 2)
                            paginate()
                            savePosition()
                        }
                    }
                }
            }
        }

        // Back button
        Rectangle {
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.margins: 24
            anchors.bottomMargin: immersiveMode ? 60 : 50
            width: 52; height: 52; radius: 26
            color: readerBackMa.pressed ? Qt.darker(accentColor, 1.2) : accentColor
            z: 20

            Behavior on scale { NumberAnimation { duration: 100 } }
            Behavior on anchors.bottomMargin { NumberAnimation { duration: 250 } }
            scale: readerBackMa.pressed ? 0.92 : 1.0

            // Glow effect
            Rectangle {
                anchors.centerIn: parent
                width: 72; height: 72; radius: 36
                color: accentColor
                opacity: 0.15
                z: -1
            }

            Text {
                anchors.centerIn: parent
                text: "←"
                font.pixelSize: 22
                color: "#fff"
            }

            MouseArea {
                id: readerBackMa
                anchors.fill: parent
                anchors.margins: -10
                onClicked: {
                    Haptic.tap()
                    savePosition()
                    currentView = "library"
                }
            }
        }

        // Immersive mode hint - shows briefly
        Rectangle {
            id: immersiveHint
            anchors.centerIn: parent
            width: 220
            height: 50
            radius: 25
            color: "#80000000"
            opacity: 0
            visible: opacity > 0

            Text {
                anchors.centerIn: parent
                text: immersiveMode ? "Tap center to show" : "Tap center to hide"
                font.pixelSize: 14
                color: "#ffffff"
            }

            SequentialAnimation {
                id: hintAnim
                NumberAnimation { target: immersiveHint; property: "opacity"; to: 1; duration: 200 }
                PauseAnimation { duration: 1500 }
                NumberAnimation { target: immersiveHint; property: "opacity"; to: 0; duration: 300 }
            }
        }

        // Show hint when immersive mode changes
        Connections {
            target: root
            function onImmersiveModeChanged() {
                hintAnim.restart()
            }
        }
    }
}
