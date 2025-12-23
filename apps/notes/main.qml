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

    property string notesDir: "/home/droidian/.local/state/flick/notes"
    property real textScale: 1.0
    property bool editMode: false
    property string currentNoteFile: ""
    property string currentNoteContent: ""

    Component.onCompleted: {
        console.log("NOTES_INIT:" + notesDir)
    }

    function saveNote(filename, content) {
        console.log("SAVE_NOTE:" + filename + ":" + content)
    }

    function deleteNote(filename) {
        console.log("DELETE_NOTE:" + filename)
    }

    function createNewNote() {
        var timestamp = Date.now()
        currentNoteFile = "note_" + timestamp + ".txt"
        currentNoteContent = ""
        editMode = true
    }

    function openNote(filename, content) {
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
            height: 160
            color: "#1a1a2e"

            Column {
                anchors.centerIn: parent
                spacing: 8

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Notes"
                    font.pixelSize: 36
                    font.weight: Font.Medium
                    color: "#ffffff"
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: folderModel.count + " notes"
                    font.pixelSize: 14
                    color: "#888899"
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

            model: folderModel

            delegate: Rectangle {
                id: noteItem
                width: notesList.width
                height: 100
                color: noteMouse.pressed ? "#252538" : "#15151f"
                radius: 12

                property string noteContent: ""

                Component.onCompleted: {
                    // Load content
                    var xhr = new XMLHttpRequest()
                    xhr.open("GET", model.fileURL, false)
                    xhr.send()
                    noteContent = xhr.responseText
                }

                Column {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 6

                    Text {
                        width: parent.width
                        text: getNoteTitle(noteItem.noteContent)
                        font.pixelSize: 18
                        font.weight: Font.Medium
                        color: "#ffffff"
                        elide: Text.ElideRight
                    }

                    Text {
                        width: parent.width
                        text: getNotePreview(noteItem.noteContent)
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
                    onClicked: openNote(model.fileName, noteItem.noteContent)
                    onPressAndHold: {
                        deleteDialog.noteToDelete = model.fileName
                        deleteDialog.visible = true
                    }
                }
            }

            // Empty state
            Text {
                anchors.centerIn: parent
                text: "No notes yet\n\nTap + to create one"
                font.pixelSize: 18
                color: "#555566"
                horizontalAlignment: Text.AlignHCenter
                visible: folderModel.count === 0
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
            color: addMouse.pressed ? "#c23a50" : "#e94560"
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
                onClicked: createNewNote()
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
            color: listBackMouse.pressed ? "#c23a50" : "#e94560"
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
                onClicked: Qt.quit()
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
                    if (textEdit.text.trim() !== "") {
                        saveNote(currentNoteFile, textEdit.text)
                    }
                    editMode = false
                    currentNoteFile = ""
                    currentNoteContent = ""
                    folderModel.folder = ""
                    folderModel.folder = "file://" + notesDir
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
            color: editorBackMouse.pressed ? "#c23a50" : "#e94560"
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
                    // Auto-save on back
                    if (textEdit.text.trim() !== "") {
                        saveNote(currentNoteFile, textEdit.text)
                    }
                    editMode = false
                    currentNoteFile = ""
                    currentNoteContent = ""
                    folderModel.folder = ""
                    folderModel.folder = "file://" + notesDir
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
                            onClicked: deleteDialog.visible = false
                        }
                    }

                    Rectangle {
                        width: 120
                        height: 48
                        radius: 24
                        color: deleteMouse.pressed ? "#c23a50" : "#e94560"

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
                                deleteNote(deleteDialog.noteToDelete)
                                deleteDialog.visible = false
                                folderModel.folder = ""
                                folderModel.folder = "file://" + notesDir
                            }
                        }
                    }
                }
            }
        }
    }
}
