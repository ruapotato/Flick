import QtQuick 2.15
import QtQuick.Window 2.15
import QtQuick.Controls 2.15
import Qt.labs.folderlistmodel 2.15
import "../shared"

Window {
    id: root
    visible: true
    width: 1080
    height: 2400
    visibility: Window.FullScreen
    title: "Notes"
    color: "#0a0a0f"

    property string notesDir: "/home/droidian/.local/state/flick/notes"
    property bool editMode: false
    property string currentNoteFile: ""
    property string currentNoteContent: ""
    property string searchQuery: ""
    property color accentColor: Theme.accentColor
    property color accentPressed: Qt.darker(accentColor, 1.2)

    Component.onCompleted: {
        console.log("NOTES_INIT:" + notesDir)
        loadNotes()
    }

    // Notes model for search/filtering
    ListModel { id: notesModel }

    function loadNotes() {
        notesModel.clear()
        // Request shell to scan notes
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file://" + notesDir, false)
        xhr.send()

        // Load each note from folder model after it updates
        loadNotesTimer.start()
    }

    Timer {
        id: loadNotesTimer
        interval: 100
        onTriggered: {
            notesModel.clear()
            for (var i = 0; i < folderModel.count; i++) {
                var fileUrl = folderModel.get(i, "fileURL")
                var fileName = folderModel.get(i, "fileName")
                var xhr = new XMLHttpRequest()
                xhr.open("GET", fileUrl, false)
                xhr.send()
                var content = xhr.responseText
                notesModel.append({
                    fileName: fileName,
                    fileURL: fileUrl,
                    content: content,
                    title: getNoteTitle(content),
                    preview: getNotePreview(content)
                })
            }
        }
    }

    function matchesSearch(content, title) {
        if (searchQuery === "") return true
        var query = searchQuery.toLowerCase()
        return content.toLowerCase().indexOf(query) !== -1 ||
               title.toLowerCase().indexOf(query) !== -1
    }

    function saveNote(filename, content) {
        // Base64 encode to handle newlines in content
        var encoded = Qt.btoa(content)
        console.log("SAVE_NOTE:" + filename + ":" + encoded)
    }

    function deleteNote(filename) {
        console.log("DELETE_NOTE:" + filename)
    }

    function createNewNote() {
        Haptic.tap()
        var timestamp = Date.now()
        currentNoteFile = "note_" + timestamp + ".txt"
        currentNoteContent = ""
        editMode = true
    }

    function openNote(filename, content) {
        Haptic.tap()
        currentNoteFile = filename
        currentNoteContent = content
        editMode = true
    }

    function getNoteTitle(content) {
        if (!content) return "New Note"
        var lines = content.split('\n')
        var title = lines[0].trim()
        return title ? title.substring(0, 50) : "Untitled"
    }

    function getNotePreview(content) {
        if (!content) return ""
        var lines = content.split('\n')
        if (lines.length > 1) {
            return lines.slice(1).join(' ').trim().substring(0, 100)
        }
        return ""
    }

    FolderListModel {
        id: folderModel
        folder: "file://" + notesDir
        nameFilters: ["*.txt"]
        showDirs: false
        sortField: FolderListModel.Time
        sortReversed: true
    }

    // Notes List View
    Item {
        anchors.fill: parent
        visible: !editMode

        // Header
        Rectangle {
            id: headerArea
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 200
            color: "#1a1a2e"

            Column {
                anchors.fill: parent
                anchors.margins: 16
                anchors.topMargin: 24
                spacing: 16

                // Title row
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 12

                    Text {
                        text: "Notes"
                        font.pixelSize: 36
                        font.weight: Font.Medium
                        color: "#ffffff"
                    }

                    Text {
                        anchors.baseline: parent.children[0].baseline
                        text: "(" + notesModel.count + ")"
                        font.pixelSize: 18
                        color: "#888899"
                    }
                }

                // Search bar
                Rectangle {
                    width: parent.width
                    height: 56
                    radius: 28
                    color: "#15151f"
                    border.color: searchInput.activeFocus ? accentColor : "#333344"
                    border.width: 1

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 20
                        anchors.rightMargin: 20
                        spacing: 12

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "🔍"
                            font.pixelSize: 20
                            opacity: 0.6
                        }

                        TextInput {
                            id: searchInput
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 80
                            text: searchQuery
                            font.pixelSize: 18
                            color: "#ffffff"
                            clip: true

                            onTextChanged: searchQuery = text

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Search notes..."
                                font.pixelSize: 18
                                color: "#555566"
                                visible: parent.text === "" && !parent.activeFocus
                            }
                        }

                        // Clear button
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "✕"
                            font.pixelSize: 18
                            color: "#888899"
                            visible: searchQuery !== ""

                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -10
                                onClicked: {
                                    Haptic.tap()
                                    searchQuery = ""
                                    searchInput.text = ""
                                }
                            }
                        }
                    }
                }
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
            anchors.bottomMargin: 180
            spacing: 12
            clip: true

            model: notesModel

            delegate: Rectangle {
                id: noteItem
                width: notesList.width
                height: matchesSearch(model.content, model.title) ? 100 : 0
                visible: matchesSearch(model.content, model.title)
                color: noteMouse.pressed ? "#252538" : "#15151f"
                radius: 12
                clip: true

                Behavior on height { NumberAnimation { duration: 150 } }

                Column {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 6

                    Text {
                        width: parent.width
                        text: model.title
                        font.pixelSize: 18
                        font.weight: Font.Medium
                        color: "#ffffff"
                        elide: Text.ElideRight
                    }

                    Text {
                        width: parent.width
                        text: model.preview
                        font.pixelSize: 14
                        color: "#888899"
                        elide: Text.ElideRight
                        maximumLineCount: 2
                        wrapMode: Text.WordWrap
                    }
                }

                MouseArea {
                    id: noteMouse
                    anchors.fill: parent
                    pressAndHoldInterval: 500
                    onClicked: openNote(model.fileName, model.content)
                    onPressAndHold: {
                        Haptic.heavy()
                        deleteDialog.noteToDelete = model.fileName
                        deleteDialog.visible = true
                    }
                }
            }

            // Empty state
            Text {
                anchors.centerIn: parent
                text: searchQuery !== "" ? "No matching notes" : "No notes yet\n\nTap + to create one"
                font.pixelSize: 18
                color: "#555566"
                horizontalAlignment: Text.AlignHCenter
                visible: notesModel.count === 0 || (searchQuery !== "" && !hasVisibleNotes())
            }

            function hasVisibleNotes() {
                for (var i = 0; i < notesModel.count; i++) {
                    var note = notesModel.get(i)
                    if (matchesSearch(note.content, note.title)) return true
                }
                return false
            }
        }

        // Add button
        Rectangle {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.rightMargin: 100
            anchors.bottomMargin: 120
            width: 72
            height: 72
            radius: 36
            color: addMouse.pressed ? accentPressed : accentColor
            z: 10

            Text {
                anchors.centerIn: parent
                text: "+"
                font.pixelSize: 40
                color: "#ffffff"
            }

            MouseArea {
                id: addMouse
                anchors.fill: parent
                onClicked: createNewNote()  // Haptic in createNewNote()
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
            color: listBackMouse.pressed ? accentPressed : accentColor
            z: 10

            Text {
                anchors.centerIn: parent
                text: "X"
                font.pixelSize: 28
                font.weight: Font.Bold
                color: "#ffffff"
            }

            MouseArea {
                id: listBackMouse
                anchors.fill: parent
                onClicked: { Haptic.tap(); Qt.quit() }
            }
        }

        // Home indicator
        Rectangle {
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottomMargin: 8
            width: 120
            height: 4
            radius: 2
            color: "#333344"
        }
    }

    // Note Editor View
    Item {
        anchors.fill: parent
        visible: editMode

        // Header
        Rectangle {
            id: editorHeader
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 80
            color: "#1a1a2e"

            Text {
                anchors.centerIn: parent
                text: currentNoteContent === "" ? "New Note" : "Edit Note"
                font.pixelSize: 20
                font.weight: Font.Medium
                color: "#ffffff"
            }
        }

        // Simple text input area
        Rectangle {
            anchors.top: editorHeader.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 16
            anchors.bottomMargin: 180
            color: "#15151f"
            radius: 12

            Flickable {
                id: textFlick
                anchors.fill: parent
                anchors.margins: 16
                contentWidth: width
                contentHeight: Math.max(textEdit.contentHeight + 50, height)
                clip: true
                flickableDirection: Flickable.VerticalFlick
                boundsBehavior: Flickable.StopAtBounds

                function ensureVisible(r) {
                    if (contentY >= r.y)
                        contentY = r.y
                    else if (contentY + height <= r.y + r.height)
                        contentY = r.y + r.height - height
                }

                TextEdit {
                    id: textEdit
                    width: textFlick.width
                    height: Math.max(contentHeight, textFlick.height)
                    text: currentNoteContent
                    font.pixelSize: 18
                    color: "#ffffff"
                    wrapMode: TextEdit.Wrap
                    selectByMouse: true
                    focus: editMode

                    onCursorRectangleChanged: textFlick.ensureVisible(cursorRectangle)
                }
            }

            // Tap anywhere to focus
            MouseArea {
                anchors.fill: parent
                propagateComposedEvents: true
                onClicked: {
                    textEdit.forceActiveFocus()
                    mouse.accepted = false
                }
                onPressed: mouse.accepted = false
                onReleased: mouse.accepted = false
            }
        }

        // Save button
        Rectangle {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.rightMargin: 100
            anchors.bottomMargin: 120
            width: 72
            height: 72
            radius: 36
            color: saveMouse.pressed ? "#2a8a4a" : "#3ca55c"
            z: 10

            Text {
                anchors.centerIn: parent
                text: "OK"
                font.pixelSize: 20
                font.weight: Font.Bold
                color: "#ffffff"
            }

            MouseArea {
                id: saveMouse
                anchors.fill: parent
                onClicked: {
                    Haptic.click()
                    if (textEdit.text.trim() !== "") {
                        saveNote(currentNoteFile, textEdit.text)
                    }
                    editMode = false
                    currentNoteFile = ""
                    currentNoteContent = ""
                    searchQuery = ""
                    searchInput.text = ""
                    folderModel.folder = ""
                    folderModel.folder = "file://" + notesDir
                    loadNotesTimer.start()
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
            color: editorBackMouse.pressed ? accentPressed : accentColor
            z: 10

            Text {
                anchors.centerIn: parent
                text: "<"
                font.pixelSize: 32
                font.weight: Font.Bold
                color: "#ffffff"
            }

            MouseArea {
                id: editorBackMouse
                anchors.fill: parent
                onClicked: {
                    Haptic.tap()
                    // Auto-save on back
                    if (textEdit.text.trim() !== "") {
                        saveNote(currentNoteFile, textEdit.text)
                    }
                    editMode = false
                    currentNoteFile = ""
                    currentNoteContent = ""
                    searchQuery = ""
                    searchInput.text = ""
                    folderModel.folder = ""
                    folderModel.folder = "file://" + notesDir
                    loadNotesTimer.start()
                }
            }
        }

        // Home indicator
        Rectangle {
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottomMargin: 8
            width: 120
            height: 4
            radius: 2
            color: "#333344"
        }
    }

    // Delete dialog
    Rectangle {
        id: deleteDialog
        anchors.fill: parent
        color: "#c0000000"
        visible: false
        z: 100

        property string noteToDelete: ""

        MouseArea {
            anchors.fill: parent
            onClicked: deleteDialog.visible = false
        }

        Rectangle {
            anchors.centerIn: parent
            width: 320
            height: 200
            radius: 20
            color: "#1a1a2e"

            Column {
                anchors.centerIn: parent
                spacing: 24

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Delete note?"
                    font.pixelSize: 20
                    color: "#ffffff"
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 20

                    Rectangle {
                        width: 120
                        height: 48
                        radius: 24
                        color: cancelMouse.pressed ? "#333344" : "#252538"

                        Text {
                            anchors.centerIn: parent
                            text: "Cancel"
                            font.pixelSize: 16
                            color: "#ffffff"
                        }

                        MouseArea {
                            id: cancelMouse
                            anchors.fill: parent
                            onClicked: { Haptic.tap(); deleteDialog.visible = false }
                        }
                    }

                    Rectangle {
                        width: 120
                        height: 48
                        radius: 24
                        color: deleteMouse.pressed ? accentPressed : accentColor

                        Text {
                            anchors.centerIn: parent
                            text: "Delete"
                            font.pixelSize: 16
                            color: "#ffffff"
                        }

                        MouseArea {
                            id: deleteMouse
                            anchors.fill: parent
                            onClicked: {
                                Haptic.heavy()
                                deleteNote(deleteDialog.noteToDelete)
                                deleteDialog.visible = false
                                folderModel.folder = ""
                                folderModel.folder = "file://" + notesDir
                                loadNotesTimer.start()
                            }
                        }
                    }
                }
            }
        }
    }
}
