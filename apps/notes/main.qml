import QtQuick 2.15
import QtQuick.Window 2.15
import QtQuick.Controls 2.15
import Qt.labs.folderlistmodel 2.15

Window {
    id: root
    visible: true
    width: 1080
    height: 2400
    visibility: Window.FullScreen
    title: "Notes"
    color: "#0a0a0f"

    property string notesDir: standardPaths.homePath + "/.local/state/flick/notes"
    property string displayConfigPath: standardPaths.homePath + "/.local/state/flick/display_config.json"
    // Notes uses fixed scaling
    property real textScale: 1.0
    property bool editMode: false
    property string currentNoteFile: ""

    QtObject {
        id: standardPaths
        property string homePath: {
            var home = Qt.getenv("HOME");
            return home ? home : "/home/droidian";
        }
    }

    Component.onCompleted: {
        loadDisplayConfig()
        ensureNotesDir()
        notesModel.refresh()
    }

    function loadDisplayConfig() {
        // Notes uses fixed scaling - no config needed
    }

    function ensureNotesDir() {
        // Log to shell for directory creation
        console.log("NOTES_INIT:" + notesDir)
    }

    function saveNote(filename, content) {
        console.log("SAVE_NOTE:" + filename + ":" + content)
    }

    function deleteNote(filename) {
        console.log("DELETE_NOTE:" + filename)
        notesModel.refresh()
    }

    function createNewNote() {
        var timestamp = Date.now()
        var filename = "note_" + timestamp + ".txt"
        currentNoteFile = filename
        noteEditor.text = ""
        editMode = true
    }

    function openNote(filename) {
        currentNoteFile = filename
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file://" + notesDir + "/" + filename, true)
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200 || xhr.status === 0) {
                    noteEditor.text = xhr.responseText
                    editMode = true
                }
            }
        }
        xhr.send()
    }

    function getNoteTitle(content) {
        if (!content) return "New Note"
        var lines = content.split('\n')
        var title = lines[0].trim()
        return title ? title : "Untitled"
    }

    function getNotePreview(content) {
        if (!content) return ""
        var lines = content.split('\n')
        if (lines.length > 1) {
            return lines.slice(1).join(' ').trim().substring(0, 100)
        }
        return ""
    }

    ListModel {
        id: notesModel

        function refresh() {
            clear()
            folderModel.folder = "file://" + notesDir
        }
    }

    FolderListModel {
        id: folderModel
        folder: "file://" + notesDir
        nameFilters: ["*.txt"]
        showDirs: false
        sortField: FolderListModel.Time
        sortReversed: true

        onCountChanged: {
            notesModel.clear()
            for (var i = 0; i < count; i++) {
                var filepath = get(i, "fileURL").toString().replace("file://", "")
                var filename = get(i, "fileName")

                // Load file content to get title and preview
                var xhr = new XMLHttpRequest()
                xhr.open("GET", get(i, "fileURL"), false)
                xhr.send()

                var content = xhr.responseText
                var title = getNoteTitle(content)
                var preview = getNotePreview(content)

                notesModel.append({
                    filename: filename,
                    title: title,
                    preview: preview,
                    filepath: filepath
                })
            }
        }
    }

    // Notes List View
    Rectangle {
        id: listView
        anchors.fill: parent
        color: "#0a0a0f"
        visible: !editMode

        // Header
        Rectangle {
            id: headerArea
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 200
            color: "transparent"

            // Ambient glow effect
            Rectangle {
                anchors.centerIn: parent
                width: 280
                height: 180
                radius: 140
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
                    text: "Notes"
                    font.pixelSize: 48
                    font.weight: Font.ExtraLight
                    font.letterSpacing: 6
                    color: "#ffffff"
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: notesModel.count + " NOTES"
                    font.pixelSize: 13
                    font.weight: Font.Medium
                    font.letterSpacing: 3
                    color: "#555566"
                }
            }

            // Bottom fade line
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

        // Notes List
        ListView {
            id: notesList
            anchors.top: headerArea.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 16
            anchors.bottomMargin: 160
            spacing: 12
            clip: true

            model: notesModel

            delegate: Rectangle {
                width: notesList.width
                height: 120
                color: "#15151f"
                radius: 12
                border.color: "#e94560"
                border.width: 0

                Rectangle {
                    anchors.fill: parent
                    color: "#e94560"
                    opacity: mouseArea.pressed ? 0.15 : 0.05
                    radius: parent.radius
                }

                Column {
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 8

                    Text {
                        width: parent.width
                        text: model.title
                        font.pixelSize: 20
                        font.weight: Font.Medium
                        color: "#ffffff"
                        elide: Text.ElideRight
                    }

                    Text {
                        width: parent.width
                        text: model.preview
                        font.pixelSize: 15
                        color: "#888899"
                        elide: Text.ElideRight
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                    }
                }

                MouseArea {
                    id: mouseArea
                    anchors.fill: parent
                    onClicked: openNote(model.filename)
                    onPressAndHold: {
                        deleteConfirmDialog.noteToDelete = model.filename
                        deleteConfirmDialog.visible = true
                    }
                }

                // Swipe to delete
                property real swipeThreshold: 200
                property real startX: 0

                MouseArea {
                    id: swipeArea
                    anchors.fill: parent
                    propagateComposedEvents: true

                    property real swipeDistance: 0

                    onPressed: {
                        startX = mouse.x
                        swipeDistance = 0
                    }

                    onPositionChanged: {
                        swipeDistance = mouse.x - startX
                        if (Math.abs(swipeDistance) > 10) {
                            parent.x = swipeDistance
                        }
                    }

                    onReleased: {
                        if (Math.abs(swipeDistance) > swipeThreshold) {
                            deleteConfirmDialog.noteToDelete = model.filename
                            deleteConfirmDialog.visible = true
                        }
                        parent.x = 0
                    }
                }
            }

            Text {
                anchors.centerIn: parent
                text: "No notes yet\n\nTap + to create your first note"
                font.pixelSize: 18
                color: "#555566"
                horizontalAlignment: Text.AlignHCenter
                lineHeight: 1.5
                visible: notesModel.count === 0
            }
        }

        // Floating + button
        Rectangle {
            id: addButton
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.rightMargin: 32
            anchors.bottomMargin: 160
            width: 80
            height: 80
            radius: 40
            color: "#e94560"

            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: "#ffffff"
                opacity: addButtonArea.pressed ? 0.3 : 0
            }

            Text {
                anchors.centerIn: parent
                text: "+"
                font.pixelSize: 48
                font.weight: Font.Light
                color: "#ffffff"
            }

            MouseArea {
                id: addButtonArea
                anchors.fill: parent
                onClicked: createNewNote()
            }

            layer.enabled: true
            layer.effect: Component {
                Item {
                    Rectangle {
                        anchors.fill: parent
                        radius: 40
                        color: "#e94560"
                        opacity: 0.3
                    }
                }
            }
        }

        // Back button
        Rectangle {
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            anchors.margins: 32
            anchors.bottomMargin: 60
            width: 72
            height: 72
            radius: 36
            color: "#e94560"

            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: "#ffffff"
                opacity: backButtonArea.pressed ? 0.3 : 0
            }

            Text {
                anchors.centerIn: parent
                text: "←"
                font.pixelSize: 32
                color: "#ffffff"
            }

            MouseArea {
                id: backButtonArea
                anchors.fill: parent
                onClicked: Qt.quit()
            }
        }

        // Home indicator bar
        Rectangle {
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottomMargin: 8
            width: 200
            height: 4
            radius: 2
            color: "#ffffff"
            opacity: 0.3
        }
    }

    // Note Editor View
    Rectangle {
        id: editorView
        anchors.fill: parent
        color: "#0a0a0f"
        visible: editMode

        // Header with title
        Rectangle {
            id: editorHeader
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 100
            color: "#15151f"

            Row {
                anchors.centerIn: parent
                spacing: 20

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: currentNoteFile ? "Edit Note" : "New Note"
                    font.pixelSize: 24
                    font.weight: Font.Medium
                    color: "#ffffff"
                }
            }

            Rectangle {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                height: 1
                color: "#e94560"
                opacity: 0.3
            }
        }

        // Text editor - using ScrollView for better touch handling
        ScrollView {
            id: editorScrollView
            anchors.top: editorHeader.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 24
            anchors.bottomMargin: 160
            clip: true

            TextArea {
                id: noteEditor
                width: editorScrollView.width
                wrapMode: TextArea.Wrap
                font.pixelSize: 18
                color: "#ffffff"
                background: Rectangle {
                    color: "transparent"
                }
                placeholderText: "Title\n\nStart typing your note here..."
                placeholderTextColor: "#555566"

                // Focus on click for touch
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        noteEditor.forceActiveFocus()
                        // Position cursor at click location
                        var pos = noteEditor.positionAt(mouse.x, mouse.y)
                        noteEditor.cursorPosition = pos
                    }
                    propagateComposedEvents: true
                }

                onTextChanged: {
                    if (currentNoteFile) {
                        saveNote(currentNoteFile, text)
                    }
                }
            }

            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
                width: 8
                contentItem: Rectangle {
                    radius: 4
                    color: "#e94560"
                    opacity: 0.5
                }
            }
        }

        // Done button
        Rectangle {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.rightMargin: 32
            anchors.bottomMargin: 160
            width: 80
            height: 80
            radius: 40
            color: "#e94560"

            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: "#ffffff"
                opacity: doneButtonArea.pressed ? 0.3 : 0
            }

            Text {
                anchors.centerIn: parent
                text: "✓"
                font.pixelSize: 40
                color: "#ffffff"
            }

            MouseArea {
                id: doneButtonArea
                anchors.fill: parent
                onClicked: {
                    if (noteEditor.text.trim() !== "") {
                        if (!currentNoteFile) {
                            var timestamp = Date.now()
                            currentNoteFile = "note_" + timestamp + ".txt"
                        }
                        saveNote(currentNoteFile, noteEditor.text)
                    }
                    editMode = false
                    currentNoteFile = ""
                    notesModel.refresh()
                }
            }
        }

        // Back button
        Rectangle {
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            anchors.margins: 32
            anchors.bottomMargin: 60
            width: 72
            height: 72
            radius: 36
            color: "#e94560"

            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: "#ffffff"
                opacity: editorBackButtonArea.pressed ? 0.3 : 0
            }

            Text {
                anchors.centerIn: parent
                text: "←"
                font.pixelSize: 32
                color: "#ffffff"
            }

            MouseArea {
                id: editorBackButtonArea
                anchors.fill: parent
                onClicked: {
                    if (noteEditor.text.trim() !== "") {
                        if (!currentNoteFile) {
                            var timestamp = Date.now()
                            currentNoteFile = "note_" + timestamp + ".txt"
                        }
                        saveNote(currentNoteFile, noteEditor.text)
                    }
                    editMode = false
                    currentNoteFile = ""
                    notesModel.refresh()
                }
            }
        }

        // Home indicator bar
        Rectangle {
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottomMargin: 8
            width: 200
            height: 4
            radius: 2
            color: "#ffffff"
            opacity: 0.3
        }
    }

    // Delete Confirmation Dialog
    Rectangle {
        id: deleteConfirmDialog
        anchors.fill: parent
        color: "#000000"
        opacity: 0.95
        visible: false
        z: 1000

        property string noteToDelete: ""

        MouseArea {
            anchors.fill: parent
            onClicked: parent.visible = false
        }

        Rectangle {
            anchors.centerIn: parent
            width: 600
            height: 400
            radius: 20
            color: "#15151f"
            border.color: "#e94560"
            border.width: 2

            Column {
                anchors.centerIn: parent
                spacing: 40

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Delete Note?"
                    font.pixelSize: 28
                    font.weight: Font.Medium
                    color: "#ffffff"
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "This action cannot be undone"
                    font.pixelSize: 16
                    color: "#888899"
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 30

                    // Cancel button
                    Rectangle {
                        width: 200
                        height: 70
                        radius: 12
                        color: "#2a2a3a"

                        Rectangle {
                            anchors.fill: parent
                            radius: parent.radius
                            color: "#ffffff"
                            opacity: cancelArea.pressed ? 0.2 : 0
                        }

                        Text {
                            anchors.centerIn: parent
                            text: "Cancel"
                            font.pixelSize: 18
                            font.weight: Font.Medium
                            color: "#ffffff"
                        }

                        MouseArea {
                            id: cancelArea
                            anchors.fill: parent
                            onClicked: deleteConfirmDialog.visible = false
                        }
                    }

                    // Delete button
                    Rectangle {
                        width: 200
                        height: 70
                        radius: 12
                        color: "#e94560"

                        Rectangle {
                            anchors.fill: parent
                            radius: parent.radius
                            color: "#ffffff"
                            opacity: deleteArea.pressed ? 0.3 : 0
                        }

                        Text {
                            anchors.centerIn: parent
                            text: "Delete"
                            font.pixelSize: 18
                            font.weight: Font.Medium
                            color: "#ffffff"
                        }

                        MouseArea {
                            id: deleteArea
                            anchors.fill: parent
                            onClicked: {
                                deleteNote(deleteConfirmDialog.noteToDelete)
                                deleteConfirmDialog.visible = false
                            }
                        }
                    }
                }
            }
        }
    }
}
