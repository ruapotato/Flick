import QtQuick 2.15
import QtQuick.Window 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../shared" as Shared

Window {
    id: root
    visible: true
    visibility: Window.FullScreen
    color: "#0a0a0f"

    // State
    property string currentView: "vaults"  // vaults, unlock, entries, detail, edit
    property var vaults: []
    property var entries: []
    property var currentEntry: null
    property string currentVaultPath: ""
    property string currentVaultName: ""
    property bool isUnlocked: false
    property string searchQuery: ""
    property bool isEditing: false
    property string errorMessage: ""

    // IPC
    property string statusPath: "/tmp/flick_vault_status"
    property int lastStatusMtime: 0
    property string httpPort: "18943"
    property string lastVaultPath: ""
    property bool lastVaultExists: false

    // Send command to daemon via HTTP POST
    function sendCommand(cmd) {
        var xhr = new XMLHttpRequest()
        xhr.open("POST", "http://127.0.0.1:" + httpPort + "/cmd", true)
        xhr.setRequestHeader("Content-Type", "application/json")
        xhr.send(JSON.stringify(cmd))
    }

    // Check for status updates
    Timer {
        interval: 100
        running: true
        repeat: true
        onTriggered: {
            var xhr = new XMLHttpRequest()
            xhr.open("GET", "file://" + statusPath + "?" + Date.now(), false)
            try {
                xhr.send()
                if (xhr.status === 200 || xhr.status === 0) {
                    var status = JSON.parse(xhr.responseText)
                    handleStatus(status)
                }
            } catch (e) {
                // Status file not ready yet
            }
        }
    }

    function handleStatus(status) {
        if (status.action === "ready") {
            // Store last vault info for auto-open prompt
            lastVaultPath = status.last_vault || ""
            lastVaultExists = status.last_vault_exists || false
            sendCommand({action: "list_vaults"})
        }
        else if (status.action === "list_vaults") {
            vaults = status.vaults || []
            isUnlocked = status.unlocked || false
            lastVaultPath = status.last_vault || lastVaultPath
            if (isUnlocked) {
                currentVaultPath = status.current_path || ""
                currentView = "entries"
                sendCommand({action: "get_entries"})
            } else if (lastVaultPath && lastVaultExists && currentView === "vaults") {
                // Auto-navigate to unlock last vault
                currentVaultPath = lastVaultPath
                currentVaultName = lastVaultPath.split("/").pop().replace(".kdbx", "")
                currentView = "unlock"
            }
        }
        else if (status.action === "unlock") {
            if (status.success) {
                isUnlocked = true
                entries = status.entries || []
                currentView = "entries"
                errorMessage = ""
            } else {
                errorMessage = status.error || "Failed to unlock"
            }
        }
        else if (status.action === "lock") {
            isUnlocked = false
            entries = []
            currentEntry = null
            currentView = "vaults"
            sendCommand({action: "list_vaults"})
        }
        else if (status.action === "create") {
            if (status.success) {
                isUnlocked = true
                entries = []
                currentView = "entries"
                errorMessage = ""
                sendCommand({action: "list_vaults"})
            } else {
                errorMessage = status.error || "Failed to create vault"
            }
        }
        else if (status.action === "get_entries") {
            entries = status.entries || []
            isUnlocked = status.unlocked || false
        }
        else if (status.action === "get_entry") {
            currentEntry = status.entry
            if (currentEntry) {
                currentView = "detail"
            }
        }
        else if (status.action === "add_entry" || status.action === "update_entry") {
            if (status.success) {
                entries = status.entries || []
                currentView = "entries"
                isEditing = false
                currentEntry = null
            } else {
                errorMessage = status.error || "Failed to save"
            }
        }
        else if (status.action === "delete_entry") {
            if (status.success) {
                entries = status.entries || []
                currentView = "entries"
                currentEntry = null
            }
        }
        else if (status.action === "search") {
            entries = status.results || []
        }
        else if (status.action === "copy_password" || status.action === "copy_username") {
            if (status.success) {
                copiedLabel.show()
            }
        }
    }

    // Header component
    Rectangle {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 68
        color: "#1a1a2e"

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            spacing: 12

            // Back button
            Rectangle {
                width: 52
                height: 52
                radius: 26
                color: backMouse.pressed ? "#444" : "#2a2a4e"
                visible: currentView !== "vaults"

                Text {
                    anchors.centerIn: parent
                    text: "<"
                    color: "white"
                    font.pixelSize: 28
                }

                MouseArea {
                    id: backMouse
                    anchors.fill: parent
                    onClicked: {
                        if (currentView === "unlock" || currentView === "create" || currentView === "open_existing") {
                            currentView = "vaults"
                            errorMessage = ""
                        } else if (currentView === "detail" || currentView === "edit") {
                            currentView = "entries"
                            currentEntry = null
                            isEditing = false
                        } else if (currentView === "entries") {
                            sendCommand({action: "lock"})
                        }
                    }
                }
            }

            // Title
            Text {
                Layout.fillWidth: true
                text: {
                    if (currentView === "vaults") return "Password Safe"
                    if (currentView === "unlock") return "Unlock Vault"
                    if (currentView === "create") return "New Vault"
                    if (currentView === "open_existing") return "Open Vault"
                    if (currentView === "entries") return currentVaultName || "Entries"
                    if (currentView === "detail") return currentEntry ? currentEntry.title : "Entry"
                    if (currentView === "edit") return isEditing ? "Edit Entry" : "New Entry"
                    return "Password Safe"
                }
                color: "white"
                font.pixelSize: 20
                font.bold: true
                elide: Text.ElideRight
            }

            // Switch vault button (visible on entries view)
            Rectangle {
                width: 52
                height: 52
                radius: 26
                color: switchMouse.pressed ? "#444" : "#2a2a4e"
                visible: currentView === "entries"

                Text {
                    anchors.centerIn: parent
                    text: "\u{1F4C1}"  // Folder emoji
                    font.pixelSize: 26
                }

                MouseArea {
                    id: switchMouse
                    anchors.fill: parent
                    onClicked: {
                        sendCommand({action: "lock"})
                    }
                }
            }

            // Lock button (visible when unlocked)
            Rectangle {
                width: 52
                height: 52
                radius: 26
                color: lockMouse.pressed ? "#444" : "#2a2a4e"
                visible: isUnlocked && currentView !== "entries"

                Text {
                    anchors.centerIn: parent
                    text: "\u{1F512}"  // Lock emoji
                    font.pixelSize: 26
                }

                MouseArea {
                    id: lockMouse
                    anchors.fill: parent
                    onClicked: sendCommand({action: "lock"})
                }
            }

            // Add button (visible on entries view)
            Rectangle {
                width: 52
                height: 52
                radius: 26
                color: addMouse.pressed ? Shared.Theme.accentPressed : Shared.Theme.accentColor
                visible: currentView === "entries"

                Text {
                    anchors.centerIn: parent
                    text: "+"
                    color: "white"
                    font.pixelSize: 28
                    font.bold: true
                }

                MouseArea {
                    id: addMouse
                    anchors.fill: parent
                    onClicked: {
                        currentEntry = null
                        isEditing = false
                        currentView = "edit"
                    }
                }
            }
        }
    }

    // Content area
    Item {
        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom

        // Vault list view
        ListView {
            id: vaultList
            anchors.fill: parent
            anchors.margins: 16
            visible: currentView === "vaults"
            spacing: 8
            clip: true

            model: vaults

            header: Column {
                width: parent.width
                spacing: 16

                Text {
                    text: "Your Vaults"
                    color: "#888"
                    font.pixelSize: 14
                }
            }

            delegate: Rectangle {
                width: vaultList.width
                height: 64
                radius: 12
                color: vaultMouse.pressed ? "#2a2a4e" : "#1a1a2e"

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 12

                    Text {
                        text: "\u{1F512}"
                        font.pixelSize: 24
                    }

                    Column {
                        Layout.fillWidth: true
                        spacing: 4

                        Text {
                            text: modelData.name
                            color: "white"
                            font.pixelSize: 16
                            font.bold: true
                        }
                        Text {
                            text: modelData.path
                            color: "#888"
                            font.pixelSize: 12
                            elide: Text.ElideMiddle
                            width: parent.width
                        }
                    }

                    Rectangle {
                        width: 8
                        height: 8
                        radius: 4
                        color: modelData.exists ? "#4caf50" : "#f44336"
                    }
                }

                MouseArea {
                    id: vaultMouse
                    anchors.fill: parent
                    onClicked: {
                        if (modelData.exists) {
                            currentVaultPath = modelData.path
                            currentVaultName = modelData.name
                            currentView = "unlock"
                        }
                    }
                    onPressAndHold: {
                        removeConfirm.vaultPath = modelData.path
                        removeConfirm.vaultName = modelData.name
                        removeConfirm.visible = true
                    }
                }
            }

            footer: Column {
                width: parent.width
                spacing: 12
                topPadding: 24

                Rectangle {
                    width: parent.width
                    height: 56
                    radius: 12
                    color: createMouse.pressed ? Shared.Theme.accentPressed : Shared.Theme.accentColor

                    Text {
                        anchors.centerIn: parent
                        text: "+ Create New Vault"
                        color: "white"
                        font.pixelSize: 16
                        font.bold: true
                    }

                    MouseArea {
                        id: createMouse
                        anchors.fill: parent
                        onClicked: {
                            currentView = "create"
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 56
                    radius: 12
                    color: openExistingMouse.pressed ? "#2a2a4e" : "#1a1a2e"
                    border.color: "#333"
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "Open Existing Vault"
                        color: "white"
                        font.pixelSize: 16
                    }

                    MouseArea {
                        id: openExistingMouse
                        anchors.fill: parent
                        onClicked: {
                            currentView = "open_existing"
                        }
                    }
                }

                Text {
                    text: "Long press to remove a vault from list"
                    color: "#666"
                    font.pixelSize: 12
                    horizontalAlignment: Text.AlignHCenter
                    width: parent.width
                }
            }
        }

        // Unlock view
        Column {
            anchors.centerIn: parent
            anchors.margins: 32
            width: parent.width - 64
            spacing: 24
            visible: currentView === "unlock"

            Text {
                text: "\u{1F512}"
                font.pixelSize: 64
                horizontalAlignment: Text.AlignHCenter
                width: parent.width
            }

            Text {
                text: currentVaultName
                color: "white"
                font.pixelSize: 24
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                width: parent.width
            }

            TextField {
                id: unlockPassword
                width: parent.width
                height: 56
                placeholderText: "Enter password"
                echoMode: TextInput.Password
                color: "white"
                font.pixelSize: 18

                background: Rectangle {
                    color: "#1a1a2e"
                    radius: 12
                    border.color: unlockPassword.focus ? Shared.Theme.accentColor : "#333"
                    border.width: 2
                }

                Keys.onReturnPressed: {
                    if (unlockPassword.text.length > 0) {
                        sendCommand({
                            action: "unlock",
                            path: currentVaultPath,
                            password: unlockPassword.text
                        })
                    }
                }
            }

            Text {
                text: errorMessage
                color: "#f44336"
                font.pixelSize: 14
                visible: errorMessage.length > 0
                horizontalAlignment: Text.AlignHCenter
                width: parent.width
            }

            Rectangle {
                width: parent.width
                height: 56
                radius: 12
                color: unlockBtn.pressed ? Shared.Theme.accentPressed : Shared.Theme.accentColor

                Text {
                    anchors.centerIn: parent
                    text: "Unlock"
                    color: "white"
                    font.pixelSize: 18
                    font.bold: true
                }

                MouseArea {
                    id: unlockBtn
                    anchors.fill: parent
                    onClicked: {
                        if (unlockPassword.text.length > 0) {
                            sendCommand({
                                action: "unlock",
                                path: currentVaultPath,
                                password: unlockPassword.text
                            })
                        }
                    }
                }
            }
        }

        // Create vault view
        Column {
            anchors.centerIn: parent
            anchors.margins: 32
            width: parent.width - 64
            spacing: 24
            visible: currentView === "create"

            Text {
                text: "Create New Vault"
                color: "white"
                font.pixelSize: 24
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                width: parent.width
            }

            TextField {
                id: newVaultName
                width: parent.width
                height: 56
                placeholderText: "Vault name"
                color: "white"
                font.pixelSize: 18

                background: Rectangle {
                    color: "#1a1a2e"
                    radius: 12
                    border.color: newVaultName.focus ? Shared.Theme.accentColor : "#333"
                    border.width: 2
                }
            }

            TextField {
                id: newVaultPassword
                width: parent.width
                height: 56
                placeholderText: "Password"
                echoMode: TextInput.Password
                color: "white"
                font.pixelSize: 18

                background: Rectangle {
                    color: "#1a1a2e"
                    radius: 12
                    border.color: newVaultPassword.focus ? Shared.Theme.accentColor : "#333"
                    border.width: 2
                }
            }

            TextField {
                id: confirmPassword
                width: parent.width
                height: 56
                placeholderText: "Confirm password"
                echoMode: TextInput.Password
                color: "white"
                font.pixelSize: 18

                background: Rectangle {
                    color: "#1a1a2e"
                    radius: 12
                    border.color: confirmPassword.focus ? Shared.Theme.accentColor : "#333"
                    border.width: 2
                }
            }

            Text {
                text: errorMessage
                color: "#f44336"
                font.pixelSize: 14
                visible: errorMessage.length > 0
                horizontalAlignment: Text.AlignHCenter
                width: parent.width
            }

            Rectangle {
                width: parent.width
                height: 56
                radius: 12
                color: createBtn.pressed ? Shared.Theme.accentPressed : Shared.Theme.accentColor

                Text {
                    anchors.centerIn: parent
                    text: "Create Vault"
                    color: "white"
                    font.pixelSize: 18
                    font.bold: true
                }

                MouseArea {
                    id: createBtn
                    anchors.fill: parent
                    onClicked: {
                        if (newVaultName.text.length === 0) {
                            errorMessage = "Enter a vault name"
                            return
                        }
                        if (newVaultPassword.text.length < 4) {
                            errorMessage = "Password too short (min 4 chars)"
                            return
                        }
                        if (newVaultPassword.text !== confirmPassword.text) {
                            errorMessage = "Passwords don't match"
                            return
                        }
                        var path = Qt.resolvedUrl("").toString().replace("file://", "")
                            .replace(/\/apps\/passwordsafe\/?$/, "")
                        // Store in Documents
                        var vaultPath = "/home/droidian/Documents/" + newVaultName.text + ".kdbx"
                        sendCommand({
                            action: "create",
                            path: vaultPath,
                            password: newVaultPassword.text
                        })
                        currentVaultPath = vaultPath
                        currentVaultName = newVaultName.text
                    }
                }
            }
        }

        // Open existing vault view
        Column {
            anchors.centerIn: parent
            anchors.margins: 32
            width: parent.width - 64
            spacing: 24
            visible: currentView === "open_existing"

            Text {
                text: "Open Existing Vault"
                color: "white"
                font.pixelSize: 24
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                width: parent.width
            }

            Text {
                text: "Enter the full path to a .kdbx file"
                color: "#888"
                font.pixelSize: 14
                horizontalAlignment: Text.AlignHCenter
                width: parent.width
            }

            TextField {
                id: existingVaultPath
                width: parent.width
                height: 56
                placeholderText: "/home/droidian/Documents/vault.kdbx"
                text: "/home/droidian/Documents/"
                color: "white"
                font.pixelSize: 16

                background: Rectangle {
                    color: "#1a1a2e"
                    radius: 12
                    border.color: existingVaultPath.focus ? Shared.Theme.accentColor : "#333"
                    border.width: 2
                }
            }

            Text {
                text: errorMessage
                color: "#f44336"
                font.pixelSize: 14
                visible: errorMessage.length > 0
                horizontalAlignment: Text.AlignHCenter
                width: parent.width
            }

            Rectangle {
                width: parent.width
                height: 56
                radius: 12
                color: openExistingBtn.pressed ? Shared.Theme.accentPressed : Shared.Theme.accentColor

                Text {
                    anchors.centerIn: parent
                    text: "Open Vault"
                    color: "white"
                    font.pixelSize: 18
                    font.bold: true
                }

                MouseArea {
                    id: openExistingBtn
                    anchors.fill: parent
                    onClicked: {
                        var path = existingVaultPath.text.trim()
                        if (path.length === 0) {
                            errorMessage = "Enter a vault path"
                            return
                        }
                        if (!path.endsWith(".kdbx")) {
                            errorMessage = "File must be a .kdbx file"
                            return
                        }
                        errorMessage = ""
                        currentVaultPath = path
                        currentVaultName = path.split("/").pop().replace(".kdbx", "")
                        currentView = "unlock"
                    }
                }
            }
        }

        // Entries list view
        Column {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12
            visible: currentView === "entries"

            // Search field
            TextField {
                id: searchField
                width: parent.width
                height: 48
                placeholderText: "Search..."
                color: "white"
                font.pixelSize: 16

                background: Rectangle {
                    color: "#1a1a2e"
                    radius: 24
                    border.color: searchField.focus ? Shared.Theme.accentColor : "#333"
                    border.width: 1
                }

                leftPadding: 20

                onTextChanged: {
                    if (text.length > 0) {
                        sendCommand({action: "search", query: text})
                    } else {
                        sendCommand({action: "get_entries"})
                    }
                }
            }

            // Entry count
            Text {
                text: entries.length + " entries"
                color: "#888"
                font.pixelSize: 12
            }

            // Entries list
            ListView {
                id: entryList
                width: parent.width
                height: parent.height - searchField.height - 40
                spacing: 8
                clip: true
                model: entries

                delegate: Rectangle {
                    width: entryList.width
                    height: 72
                    radius: 12
                    color: entryMouse.pressed ? "#2a2a4e" : "#1a1a2e"

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 12

                        Rectangle {
                            width: 48
                            height: 48
                            radius: 24
                            color: Shared.Theme.accentColor

                            Text {
                                anchors.centerIn: parent
                                text: modelData.title.charAt(0).toUpperCase()
                                color: "white"
                                font.pixelSize: 20
                                font.bold: true
                            }
                        }

                        Column {
                            Layout.fillWidth: true
                            spacing: 4

                            Text {
                                text: modelData.title
                                color: "white"
                                font.pixelSize: 16
                                font.bold: true
                                elide: Text.ElideRight
                                width: parent.width
                            }
                            Text {
                                text: modelData.username || modelData.url || ""
                                color: "#888"
                                font.pixelSize: 14
                                elide: Text.ElideRight
                                width: parent.width
                            }
                        }

                        // Copy password button
                        Rectangle {
                            width: 44
                            height: 44
                            radius: 22
                            color: copyMouse.pressed ? "#333" : "transparent"

                            Text {
                                anchors.centerIn: parent
                                text: "\u{1F4CB}"  // Clipboard
                                font.pixelSize: 20
                            }

                            MouseArea {
                                id: copyMouse
                                anchors.fill: parent
                                onClicked: {
                                    sendCommand({
                                        action: "copy_password",
                                        uuid: modelData.uuid
                                    })
                                }
                            }
                        }
                    }

                    MouseArea {
                        id: entryMouse
                        anchors.fill: parent
                        anchors.rightMargin: 56
                        onClicked: {
                            sendCommand({
                                action: "get_entry",
                                uuid: modelData.uuid
                            })
                        }
                    }
                }

                // Empty state
                Text {
                    anchors.centerIn: parent
                    text: entries.length === 0 ? "No entries yet\nTap + to add one" : ""
                    color: "#666"
                    font.pixelSize: 16
                    horizontalAlignment: Text.AlignHCenter
                    visible: entries.length === 0
                }
            }
        }

        // Entry detail view
        Flickable {
            anchors.fill: parent
            anchors.margins: 16
            contentHeight: detailColumn.height
            clip: true
            visible: currentView === "detail"

            Column {
                id: detailColumn
                width: parent.width
                spacing: 16

                // Title
                Text {
                    text: currentEntry ? currentEntry.title : ""
                    color: "white"
                    font.pixelSize: 24
                    font.bold: true
                    width: parent.width
                    wrapMode: Text.Wrap
                }

                // Fields
                Repeater {
                    model: currentEntry ? [
                        {label: "Username", value: currentEntry.username, action: "copy_username"},
                        {label: "Password", value: "********", action: "copy_password", masked: true},
                        {label: "URL", value: currentEntry.url, action: null},
                        {label: "Notes", value: currentEntry.notes, action: null}
                    ] : []

                    delegate: Rectangle {
                        width: parent.width
                        height: modelData.value ? (modelData.label === "Notes" ? Math.max(80, notesText.contentHeight + 40) : 72) : 0
                        radius: 12
                        color: "#1a1a2e"
                        visible: modelData.value && modelData.value.length > 0

                        Column {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 4

                            Text {
                                text: modelData.label
                                color: "#888"
                                font.pixelSize: 12
                            }

                            Text {
                                id: notesText
                                text: modelData.value
                                color: "white"
                                font.pixelSize: 16
                                width: parent.width - 60
                                wrapMode: modelData.label === "Notes" ? Text.Wrap : Text.NoWrap
                                elide: modelData.label === "Notes" ? Text.ElideNone : Text.ElideRight
                            }
                        }

                        // Copy button for username/password
                        Rectangle {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.rightMargin: 12
                            width: 44
                            height: 44
                            radius: 22
                            color: fieldCopyMouse.pressed ? "#333" : "transparent"
                            visible: modelData.action !== null

                            Text {
                                anchors.centerIn: parent
                                text: "\u{1F4CB}"
                                font.pixelSize: 18
                            }

                            MouseArea {
                                id: fieldCopyMouse
                                anchors.fill: parent
                                onClicked: {
                                    sendCommand({
                                        action: modelData.action,
                                        uuid: currentEntry.uuid
                                    })
                                }
                            }
                        }
                    }
                }

                // Action buttons
                Row {
                    width: parent.width
                    spacing: 12
                    topPadding: 24

                    Rectangle {
                        width: (parent.width - 12) / 2
                        height: 56
                        radius: 12
                        color: editMouse.pressed ? Shared.Theme.accentPressed : Shared.Theme.accentColor

                        Text {
                            anchors.centerIn: parent
                            text: "Edit"
                            color: "white"
                            font.pixelSize: 16
                            font.bold: true
                        }

                        MouseArea {
                            id: editMouse
                            anchors.fill: parent
                            onClicked: {
                                isEditing = true
                                currentView = "edit"
                            }
                        }
                    }

                    Rectangle {
                        width: (parent.width - 12) / 2
                        height: 56
                        radius: 12
                        color: deleteMouse.pressed ? "#c62828" : "#f44336"

                        Text {
                            anchors.centerIn: parent
                            text: "Delete"
                            color: "white"
                            font.pixelSize: 16
                            font.bold: true
                        }

                        MouseArea {
                            id: deleteMouse
                            anchors.fill: parent
                            onClicked: {
                                deleteConfirm.visible = true
                            }
                        }
                    }
                }
            }
        }

        // Edit/Add entry view
        Flickable {
            anchors.fill: parent
            anchors.margins: 16
            contentHeight: editColumn.height
            clip: true
            visible: currentView === "edit"

            Column {
                id: editColumn
                width: parent.width
                spacing: 16

                // Title field
                Column {
                    width: parent.width
                    spacing: 4

                    Text {
                        text: "Title"
                        color: "#888"
                        font.pixelSize: 12
                    }

                    TextField {
                        id: editTitle
                        width: parent.width
                        height: 56
                        text: isEditing && currentEntry ? currentEntry.title : ""
                        placeholderText: "Entry title"
                        color: "white"
                        font.pixelSize: 16

                        background: Rectangle {
                            color: "#1a1a2e"
                            radius: 12
                            border.color: editTitle.focus ? Shared.Theme.accentColor : "#333"
                            border.width: 1
                        }
                    }
                }

                // Username field
                Column {
                    width: parent.width
                    spacing: 4

                    Text {
                        text: "Username"
                        color: "#888"
                        font.pixelSize: 12
                    }

                    TextField {
                        id: editUsername
                        width: parent.width
                        height: 56
                        text: isEditing && currentEntry ? currentEntry.username : ""
                        placeholderText: "Username or email"
                        color: "white"
                        font.pixelSize: 16

                        background: Rectangle {
                            color: "#1a1a2e"
                            radius: 12
                            border.color: editUsername.focus ? Shared.Theme.accentColor : "#333"
                            border.width: 1
                        }
                    }
                }

                // Password field
                Column {
                    width: parent.width
                    spacing: 4

                    Text {
                        text: "Password"
                        color: "#888"
                        font.pixelSize: 12
                    }

                    RowLayout {
                        width: parent.width
                        spacing: 8

                        TextField {
                            id: editPassword
                            Layout.fillWidth: true
                            height: 56
                            text: isEditing && currentEntry ? currentEntry.password : ""
                            placeholderText: "Password"
                            echoMode: showPassword.checked ? TextInput.Normal : TextInput.Password
                            color: "white"
                            font.pixelSize: 16

                            background: Rectangle {
                                color: "#1a1a2e"
                                radius: 12
                                border.color: editPassword.focus ? Shared.Theme.accentColor : "#333"
                                border.width: 1
                            }
                        }

                        Rectangle {
                            width: 56
                            height: 56
                            radius: 12
                            color: showPassword.checked ? Shared.Theme.accentColor : "#1a1a2e"

                            Text {
                                anchors.centerIn: parent
                                text: "\u{1F441}"  // Eye
                                font.pixelSize: 20
                            }

                            MouseArea {
                                id: showPassword
                                anchors.fill: parent
                                property bool checked: false
                                onClicked: checked = !checked
                            }
                        }
                    }
                }

                // URL field
                Column {
                    width: parent.width
                    spacing: 4

                    Text {
                        text: "URL"
                        color: "#888"
                        font.pixelSize: 12
                    }

                    TextField {
                        id: editUrl
                        width: parent.width
                        height: 56
                        text: isEditing && currentEntry ? currentEntry.url : ""
                        placeholderText: "https://..."
                        color: "white"
                        font.pixelSize: 16
                        inputMethodHints: Qt.ImhUrlCharactersOnly

                        background: Rectangle {
                            color: "#1a1a2e"
                            radius: 12
                            border.color: editUrl.focus ? Shared.Theme.accentColor : "#333"
                            border.width: 1
                        }
                    }
                }

                // Notes field
                Column {
                    width: parent.width
                    spacing: 4

                    Text {
                        text: "Notes"
                        color: "#888"
                        font.pixelSize: 12
                    }

                    Rectangle {
                        width: parent.width
                        height: 120
                        color: "#1a1a2e"
                        radius: 12
                        border.color: editNotes.focus ? Shared.Theme.accentColor : "#333"
                        border.width: 1

                        TextArea {
                            id: editNotes
                            anchors.fill: parent
                            anchors.margins: 12
                            text: isEditing && currentEntry ? currentEntry.notes : ""
                            placeholderText: "Additional notes..."
                            color: "white"
                            font.pixelSize: 16
                            wrapMode: Text.Wrap
                            background: null
                        }
                    }
                }

                // Error message
                Text {
                    text: errorMessage
                    color: "#f44336"
                    font.pixelSize: 14
                    visible: errorMessage.length > 0
                    horizontalAlignment: Text.AlignHCenter
                    width: parent.width
                }

                // Save button
                Rectangle {
                    width: parent.width
                    height: 56
                    radius: 12
                    color: saveMouse.pressed ? Shared.Theme.accentPressed : Shared.Theme.accentColor

                    Text {
                        anchors.centerIn: parent
                        text: "Save"
                        color: "white"
                        font.pixelSize: 18
                        font.bold: true
                    }

                    MouseArea {
                        id: saveMouse
                        anchors.fill: parent
                        onClicked: {
                            if (editTitle.text.length === 0) {
                                errorMessage = "Title is required"
                                return
                            }
                            errorMessage = ""

                            var cmd = {
                                action: isEditing ? "update_entry" : "add_entry",
                                title: editTitle.text,
                                username: editUsername.text,
                                password: editPassword.text,
                                url: editUrl.text,
                                notes: editNotes.text
                            }
                            if (isEditing && currentEntry) {
                                cmd.uuid = currentEntry.uuid
                            }
                            sendCommand(cmd)
                        }
                    }
                }

                // Spacer for keyboard
                Item {
                    width: parent.width
                    height: 200
                }
            }
        }
    }

    // Copied notification
    Rectangle {
        id: copiedLabel
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 100
        anchors.horizontalCenter: parent.horizontalCenter
        width: 150
        height: 44
        radius: 22
        color: "#4caf50"
        opacity: 0
        visible: opacity > 0

        Text {
            anchors.centerIn: parent
            text: "Copied!"
            color: "white"
            font.pixelSize: 16
            font.bold: true
        }

        function show() {
            opacity = 1
            hideTimer.start()
        }

        Timer {
            id: hideTimer
            interval: 1500
            onTriggered: copiedLabel.opacity = 0
        }

        Behavior on opacity {
            NumberAnimation { duration: 200 }
        }
    }

    // Delete confirmation dialog
    Rectangle {
        id: deleteConfirm
        anchors.fill: parent
        color: "#000000cc"
        visible: false

        MouseArea {
            anchors.fill: parent
            onClicked: deleteConfirm.visible = false
        }

        Rectangle {
            anchors.centerIn: parent
            width: parent.width - 64
            height: 180
            radius: 16
            color: "#1a1a2e"

            Column {
                anchors.centerIn: parent
                spacing: 20

                Text {
                    text: "Delete this entry?"
                    color: "white"
                    font.pixelSize: 18
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    width: parent.width
                }

                Row {
                    spacing: 12

                    Rectangle {
                        width: 120
                        height: 48
                        radius: 24
                        color: cancelDeleteMouse.pressed ? "#333" : "#2a2a4e"

                        Text {
                            anchors.centerIn: parent
                            text: "Cancel"
                            color: "white"
                            font.pixelSize: 16
                        }

                        MouseArea {
                            id: cancelDeleteMouse
                            anchors.fill: parent
                            onClicked: deleteConfirm.visible = false
                        }
                    }

                    Rectangle {
                        width: 120
                        height: 48
                        radius: 24
                        color: confirmDeleteMouse.pressed ? "#c62828" : "#f44336"

                        Text {
                            anchors.centerIn: parent
                            text: "Delete"
                            color: "white"
                            font.pixelSize: 16
                            font.bold: true
                        }

                        MouseArea {
                            id: confirmDeleteMouse
                            anchors.fill: parent
                            onClicked: {
                                if (currentEntry) {
                                    sendCommand({
                                        action: "delete_entry",
                                        uuid: currentEntry.uuid
                                    })
                                }
                                deleteConfirm.visible = false
                            }
                        }
                    }
                }
            }
        }
    }

    // Remove vault confirmation dialog
    Rectangle {
        id: removeConfirm
        anchors.fill: parent
        color: "#000000cc"
        visible: false

        property string vaultPath: ""
        property string vaultName: ""

        MouseArea {
            anchors.fill: parent
            onClicked: removeConfirm.visible = false
        }

        Rectangle {
            anchors.centerIn: parent
            width: parent.width - 64
            height: 200
            radius: 16
            color: "#1a1a2e"

            Column {
                anchors.centerIn: parent
                spacing: 16

                Text {
                    text: "Remove vault from list?"
                    color: "white"
                    font.pixelSize: 18
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    width: parent.width
                }

                Text {
                    text: removeConfirm.vaultName + "\n(File will not be deleted)"
                    color: "#888"
                    font.pixelSize: 14
                    horizontalAlignment: Text.AlignHCenter
                    width: parent.width
                }

                Row {
                    spacing: 12
                    anchors.horizontalCenter: parent.horizontalCenter

                    Rectangle {
                        width: 120
                        height: 48
                        radius: 24
                        color: cancelRemoveMouse.pressed ? "#333" : "#2a2a4e"

                        Text {
                            anchors.centerIn: parent
                            text: "Cancel"
                            color: "white"
                            font.pixelSize: 16
                        }

                        MouseArea {
                            id: cancelRemoveMouse
                            anchors.fill: parent
                            onClicked: removeConfirm.visible = false
                        }
                    }

                    Rectangle {
                        width: 120
                        height: 48
                        radius: 24
                        color: confirmRemoveMouse.pressed ? "#c62828" : "#f44336"

                        Text {
                            anchors.centerIn: parent
                            text: "Remove"
                            color: "white"
                            font.pixelSize: 16
                            font.bold: true
                        }

                        MouseArea {
                            id: confirmRemoveMouse
                            anchors.fill: parent
                            onClicked: {
                                sendCommand({
                                    action: "remove_vault",
                                    path: removeConfirm.vaultPath
                                })
                                removeConfirm.visible = false
                                sendCommand({action: "list_vaults"})
                            }
                        }
                    }
                }
            }
        }
    }

    Component.onCompleted: {
        // Initial status check will trigger list_vaults
    }
}
