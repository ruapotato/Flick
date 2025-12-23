import QtQuick 2.15
import QtQuick.Window 2.15
import QtQuick.Controls 2.15
import QtMultimedia 5.15
import Qt.labs.folderlistmodel 2.15

Window {
    id: root
    visible: true
    visibility: Window.FullScreen
    width: 1080
    height: 2400
    title: "Audiobooks"
    color: "#0a0a0f"

    property real textScale: 1.0
    property var booksList: []
    property var progressData: ({})
    property string currentView: "library" // "library", "chapters", "player"
    property var currentBook: null
    property int currentChapterIndex: 0

    // Audio player
    Audio {
        id: audioPlayer
        autoPlay: false

        onPositionChanged: {
            if (currentBook && currentBook.chapters && currentBook.chapters[currentChapterIndex]) {
                saveProgress()
            }
        }

        onStopped: {
            // Auto-advance to next chapter if at end
            if (position >= duration - 1000 && currentChapterIndex < currentBook.chapters.length - 1) {
                currentChapterIndex++
                loadChapter(currentChapterIndex)
                audioPlayer.play()
            }
        }
    }

    Component.onCompleted: {
        loadTextScale()
        loadProgress()
        scanAudiobooks()
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
                    } catch (e) {
                        console.log("Failed to parse display config:", e)
                    }
                }
            }
        }
        xhr.send()
    }

    function loadProgress() {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file:///home/droidian/.local/state/flick/audiobook_progress.json")
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200 || xhr.status === 0) {
                    try {
                        progressData = JSON.parse(xhr.responseText)
                    } catch (e) {
                        progressData = {}
                    }
                }
            }
        }
        xhr.send()
    }

    function saveProgress() {
        if (!currentBook || !currentBook.chapters || !currentBook.chapters[currentChapterIndex]) return

        var bookId = currentBook.path
        progressData[bookId] = {
            chapter: currentChapterIndex,
            position: audioPlayer.position,
            timestamp: Date.now()
        }

        var xhr = new XMLHttpRequest()
        xhr.open("PUT", "file:///home/droidian/.local/state/flick/audiobook_progress.json")
        xhr.send(JSON.stringify(progressData, null, 2))
    }

    function scanAudiobooks() {
        booksList = []
        var paths = [
            "/home/droidian/Audiobooks",
            Qt.resolvedUrl("~/Audiobooks").toString().replace("file://", "")
        ]

        for (var i = 0; i < paths.length; i++) {
            scanDirectory(paths[i])
        }
    }

    function scanDirectory(path) {
        // Use FolderListModel to scan directories
        var component = Qt.createQmlObject('
            import QtQuick 2.15
            import Qt.labs.folderlistmodel 2.15
            FolderListModel {
                showDirs: true
                showFiles: false
            }
        ', root)

        component.folder = "file://" + path

        // Wait for folder to load
        Qt.callLater(function() {
            for (var i = 0; i < component.count; i++) {
                var folderName = component.get(i, "fileName")
                var folderPath = component.get(i, "filePath")
                if (folderName && folderName !== "." && folderName !== "..") {
                    var chapters = scanBookFolder(folderPath)
                    if (chapters.length > 0) {
                        booksList.push({
                            title: folderName,
                            path: folderPath,
                            chapters: chapters
                        })
                    }
                }
            }
            booksListModel.sync()
        })
    }

    function scanBookFolder(folderPath) {
        var chapters = []
        var component = Qt.createQmlObject('
            import QtQuick 2.15
            import Qt.labs.folderlistmodel 2.15
            FolderListModel {
                showDirs: false
                showFiles: true
                nameFilters: ["*.mp3", "*.m4a", "*.m4b", "*.ogg", "*.flac", "*.wav", "*.aac"]
            }
        ', root)

        component.folder = folderPath

        for (var i = 0; i < component.count; i++) {
            var fileName = component.get(i, "fileName")
            var filePath = component.get(i, "filePath")
            if (fileName) {
                chapters.push({
                    title: fileName,
                    path: filePath
                })
            }
        }

        // Sort chapters alphabetically
        chapters.sort(function(a, b) {
            return a.title.localeCompare(b.title)
        })

        return chapters
    }

    ListModel {
        id: booksListModel

        function sync() {
            clear()
            for (var i = 0; i < booksList.length; i++) {
                append(booksList[i])
            }
        }
    }

    function openBook(book) {
        currentBook = book
        currentChapterIndex = 0

        // Load saved progress
        if (progressData[book.path]) {
            currentChapterIndex = progressData[book.path].chapter || 0
        }

        currentView = "chapters"
    }

    function playChapter(index) {
        currentChapterIndex = index
        loadChapter(index)
        currentView = "player"
        audioPlayer.play()
    }

    function loadChapter(index) {
        if (!currentBook || !currentBook.chapters || index < 0 || index >= currentBook.chapters.length) return

        var chapter = currentBook.chapters[index]
        audioPlayer.source = chapter.path

        // Restore position if available
        if (progressData[currentBook.path] && progressData[currentBook.path].chapter === index) {
            audioPlayer.seek(progressData[currentBook.path].position || 0)
        }
    }

    function formatTime(ms) {
        var seconds = Math.floor(ms / 1000)
        var hours = Math.floor(seconds / 3600)
        var minutes = Math.floor((seconds % 3600) / 60)
        seconds = seconds % 60

        if (hours > 0) {
            return hours + ":" + (minutes < 10 ? "0" : "") + minutes + ":" + (seconds < 10 ? "0" : "") + seconds
        } else {
            return minutes + ":" + (seconds < 10 ? "0" : "") + seconds
        }
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
                    text: "Audiobooks"
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
            id: booksList
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
                width: booksList.width
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
                            text: "📚"
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
                            text: model.chapters ? model.chapters.length + " chapters" : "0 chapters"
                            font.pixelSize: 16 * textScale
                            color: "#888899"
                        }

                        // Progress indicator
                        Row {
                            spacing: 8
                            visible: progressData[model.path] !== undefined

                            Rectangle {
                                width: 4
                                height: 4
                                radius: 2
                                color: "#e94560"
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Text {
                                text: "In progress"
                                font.pixelSize: 14 * textScale
                                color: "#e94560"
                            }
                        }
                    }
                }

                MouseArea {
                    id: bookMouse
                    anchors.fill: parent
                    onClicked: openBook(model)
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
                text: "No audiobooks found"
                font.pixelSize: 24 * textScale
                color: "#555566"
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Add audiobooks to:\n~/Audiobooks or\n/home/droidian/Audiobooks"
                font.pixelSize: 16 * textScale
                color: "#444455"
                horizontalAlignment: Text.AlignHCenter
            }
        }

        // Back button
        Rectangle {
            id: libraryBackButton
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
                onClicked: Qt.quit()
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

    // Chapters View
    Item {
        anchors.fill: parent
        visible: currentView === "chapters"

        // Header
        Rectangle {
            id: chaptersHeader
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 180
            color: "transparent"

            Column {
                anchors.centerIn: parent
                spacing: 12

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: currentBook ? currentBook.title : ""
                    font.pixelSize: 32 * textScale
                    font.weight: Font.Medium
                    color: "#ffffff"
                    elide: Text.ElideRight
                    width: root.width - 32
                    horizontalAlignment: Text.AlignHCenter
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: currentBook && currentBook.chapters ? currentBook.chapters.length + " CHAPTERS" : ""
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
                color: "#333344"
                opacity: 0.5
            }
        }

        // Chapters list
        ListView {
            id: chaptersList
            anchors.top: chaptersHeader.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 16
            anchors.bottomMargin: 100
            spacing: 12
            clip: true

            model: currentBook ? currentBook.chapters : []

            delegate: Rectangle {
                width: chaptersList.width
                height: 80
                radius: 12
                color: "#151520"
                border.color: chapterMouse.pressed ? "#e94560" : (index === currentChapterIndex && progressData[currentBook.path] ? "#e94560" : "#333344")
                border.width: 1

                Behavior on border.color { ColorAnimation { duration: 150 } }

                Row {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 16

                    // Chapter number
                    Rectangle {
                        width: 48
                        height: 48
                        radius: 24
                        color: index === currentChapterIndex && progressData[currentBook.path] ? "#e94560" : "#333344"
                        anchors.verticalCenter: parent.verticalCenter

                        Behavior on color { ColorAnimation { duration: 150 } }

                        Text {
                            anchors.centerIn: parent
                            text: index + 1
                            font.pixelSize: 20 * textScale
                            font.weight: Font.Bold
                            color: "#ffffff"
                        }
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4
                        width: parent.width - 64 - 32

                        Text {
                            text: modelData.title
                            font.pixelSize: 18 * textScale
                            color: "#ffffff"
                            elide: Text.ElideRight
                            width: parent.width
                        }

                        Text {
                            text: index === currentChapterIndex && progressData[currentBook.path] ? "Currently playing" : "Tap to play"
                            font.pixelSize: 14 * textScale
                            color: index === currentChapterIndex && progressData[currentBook.path] ? "#e94560" : "#888899"
                        }
                    }
                }

                MouseArea {
                    id: chapterMouse
                    anchors.fill: parent
                    onClicked: playChapter(index)
                }
            }
        }

        // Back button
        Rectangle {
            id: chaptersBackButton
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.rightMargin: 24
            anchors.bottomMargin: 120
            width: 72
            height: 72
            radius: 36
            color: chaptersBackMouse.pressed ? "#c23a50" : "#e94560"

            Behavior on color { ColorAnimation { duration: 150 } }

            Text {
                anchors.centerIn: parent
                text: "←"
                font.pixelSize: 32
                font.weight: Font.Medium
                color: "#ffffff"
            }

            MouseArea {
                id: chaptersBackMouse
                anchors.fill: parent
                onClicked: currentView = "library"
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

    // Player View
    Item {
        anchors.fill: parent
        visible: currentView === "player"

        Column {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -100
            spacing: 48
            width: parent.width - 64

            // Book cover placeholder
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 320
                height: 320
                radius: 24
                color: "#e94560"
                opacity: 0.3

                Text {
                    anchors.centerIn: parent
                    text: "📚"
                    font.pixelSize: 128
                }
            }

            // Book title
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: currentBook ? currentBook.title : ""
                font.pixelSize: 28 * textScale
                font.weight: Font.Bold
                color: "#ffffff"
                elide: Text.ElideRight
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
            }

            // Chapter title
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: currentBook && currentBook.chapters && currentBook.chapters[currentChapterIndex] ? currentBook.chapters[currentChapterIndex].title : ""
                font.pixelSize: 18 * textScale
                color: "#888899"
                elide: Text.ElideRight
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
            }

            // Progress bar
            Column {
                width: parent.width
                spacing: 12

                Slider {
                    id: progressSlider
                    width: parent.width
                    from: 0
                    to: audioPlayer.duration
                    value: audioPlayer.position

                    onMoved: {
                        audioPlayer.seek(value)
                    }

                    background: Rectangle {
                        x: progressSlider.leftPadding
                        y: progressSlider.topPadding + progressSlider.availableHeight / 2 - height / 2
                        width: progressSlider.availableWidth
                        height: 4
                        radius: 2
                        color: "#333344"

                        Rectangle {
                            width: progressSlider.visualPosition * parent.width
                            height: parent.height
                            radius: 2
                            color: "#e94560"
                        }
                    }

                    handle: Rectangle {
                        x: progressSlider.leftPadding + progressSlider.visualPosition * (progressSlider.availableWidth - width)
                        y: progressSlider.topPadding + progressSlider.availableHeight / 2 - height / 2
                        width: 20
                        height: 20
                        radius: 10
                        color: "#e94560"
                    }
                }

                Row {
                    width: parent.width

                    Text {
                        text: formatTime(audioPlayer.position)
                        font.pixelSize: 16 * textScale
                        color: "#888899"
                    }

                    Item { width: parent.width - 200; height: 1 }

                    Text {
                        text: formatTime(audioPlayer.duration)
                        font.pixelSize: 16 * textScale
                        color: "#888899"
                    }
                }
            }

            // Playback controls
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 48

                // Skip back 30s
                Rectangle {
                    width: 64
                    height: 64
                    radius: 32
                    color: skipBackMouse.pressed ? "#333344" : "#252530"

                    Text {
                        anchors.centerIn: parent
                        text: "⏪"
                        font.pixelSize: 28
                        color: "#ffffff"
                    }

                    Text {
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: 16
                        text: "30"
                        font.pixelSize: 12 * textScale
                        color: "#888899"
                    }

                    MouseArea {
                        id: skipBackMouse
                        anchors.fill: parent
                        onClicked: audioPlayer.seek(Math.max(0, audioPlayer.position - 30000))
                    }
                }

                // Play/Pause
                Rectangle {
                    width: 96
                    height: 96
                    radius: 48
                    color: playPauseMouse.pressed ? "#c23a50" : "#e94560"

                    Behavior on color { ColorAnimation { duration: 150 } }

                    Text {
                        anchors.centerIn: parent
                        text: audioPlayer.playbackState === Audio.PlayingState ? "⏸" : "▶"
                        font.pixelSize: 40
                        color: "#ffffff"
                    }

                    MouseArea {
                        id: playPauseMouse
                        anchors.fill: parent
                        onClicked: {
                            if (audioPlayer.playbackState === Audio.PlayingState) {
                                audioPlayer.pause()
                            } else {
                                audioPlayer.play()
                            }
                        }
                    }
                }

                // Skip forward 30s
                Rectangle {
                    width: 64
                    height: 64
                    radius: 32
                    color: skipForwardMouse.pressed ? "#333344" : "#252530"

                    Text {
                        anchors.centerIn: parent
                        text: "⏩"
                        font.pixelSize: 28
                        color: "#ffffff"
                    }

                    Text {
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: 16
                        text: "30"
                        font.pixelSize: 12 * textScale
                        color: "#888899"
                    }

                    MouseArea {
                        id: skipForwardMouse
                        anchors.fill: parent
                        onClicked: audioPlayer.seek(Math.min(audioPlayer.duration, audioPlayer.position + 30000))
                    }
                }
            }

            // Playback speed control
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 16

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Speed:"
                    font.pixelSize: 16 * textScale
                    color: "#888899"
                }

                Repeater {
                    model: [0.75, 1.0, 1.25, 1.5, 2.0]

                    Rectangle {
                        width: 64
                        height: 40
                        radius: 8
                        color: audioPlayer.playbackRate === modelData ? "#e94560" : "#252530"
                        border.color: "#333344"
                        border.width: 1

                        Behavior on color { ColorAnimation { duration: 150 } }

                        Text {
                            anchors.centerIn: parent
                            text: modelData + "x"
                            font.pixelSize: 16 * textScale
                            color: "#ffffff"
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: audioPlayer.playbackRate = modelData
                        }
                    }
                }
            }
        }

        // Back button
        Rectangle {
            id: playerBackButton
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.rightMargin: 24
            anchors.bottomMargin: 120
            width: 72
            height: 72
            radius: 36
            color: playerBackMouse.pressed ? "#c23a50" : "#e94560"

            Behavior on color { ColorAnimation { duration: 150 } }

            Text {
                anchors.centerIn: parent
                text: "←"
                font.pixelSize: 32
                font.weight: Font.Medium
                color: "#ffffff"
            }

            MouseArea {
                id: playerBackMouse
                anchors.fill: parent
                onClicked: currentView = "chapters"
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
